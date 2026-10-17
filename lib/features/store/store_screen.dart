import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport, ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/haptics.dart';
import '../../core/links.dart';
import '../../core/platform.dart';
import '../../core/sfx.dart';
import '../../core/a11y.dart';
import '../../core/app_links.dart';
import '../../core/theme/tokens.dart';
import '../../data/purchases.dart';
import '../../models/models.dart';
import '../../state/first_steps.dart';
import '../../state/profile.dart';
import '../../state/purchases.dart';
import '../../state/settings.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../../widgets/vip.dart';
import '../ads/house_ads.dart';
import '../daily/daily_reward_sheet.dart';
import '../daily/piggy_sheet.dart';
import '../links/deep_links.dart';

/// Store: free bonus video (capped per day), coin bundles, ticket bundles,
/// hint packs, VIP. Purchases go through StoreKit and are verified by the
/// `verify-purchase` Appwrite Function before anything is granted; the tapped
/// row waits while the App Store sheet is open, then [PurchaseHost] shows the
/// purchase sheet ([purchaseFlowProvider]). In debug
/// builds without a store (plain simulator) a clearly labelled sandbox
/// dialog stands in so the flow can still be exercised.
///
/// On web there is no store and no price is shown anywhere: every bundle and
/// VIP stay listed with "Available on iPhone" in place of the price and the
/// buy buttons, next to the free sources (bonus video, quests, piggy bank).
/// Earned currency is saved to the account like on iPhone.
class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key, this.showVip = false});
  /// Opens scrolled to the VIP card (`/store?vip=1`).
  final bool showVip;
  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  bool _adBusy = false;

  /// The product whose App Store details are being asked for again.
  String? _querying;
  final _vipKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (ref.read(platformCapsProvider).purchases) {
      ref.read(purchaseServiceProvider).start();
      // Opened after an answer without products: ask the App Store again, so the prices load.
      if ((ref.read(productsProvider).value ?? const {}).isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.invalidate(storeAvailableProvider);
        });
      }
    }
    if (widget.showVip) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _vipKey.currentContext;
        if (ctx != null) _revealBelowBar(ctx);
      });
    }
  }

  /// Scrolls so [target] starts just under the glass bar. `Scrollable.ensureVisible` aligns
  /// against the whole viewport, which runs behind the bar, so a tall card's title ended
  /// up under it.
  void _revealBelowBar(BuildContext target) {
    final box = target.findRenderObject();
    final position = Scrollable.maybeOf(target)?.position;
    if (box == null || position == null) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final bar = MediaQuery.paddingOf(context).top + kToolbarHeight + 12;
    final to = (viewport.getOffsetToReveal(box, 0).offset - bar).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (A11y.reduceMotionOf(context)) {
      position.jumpTo(to);
    } else {
      position.animateTo(to, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    }
  }

  Future<void> _watchAd() async {
    if (_adBusy) return;
    // The allowance is persisted on the profile, so blocking the ad network
    // does not reset it.
    final wait = HouseAdPolicy.rewardedWaitLeft(ref.read(localStoreProvider).lastRewardedAt);
    if (wait > Duration.zero) {
      showToast(context, 'Next offer in ${formatTimeLeft(wait)}.', icon: AppIcons.time);
      return;
    }
    final ok = await ref.read(profileProvider.notifier).consumeAd();
    if (!mounted) return;
    if (!ok) {
      showToast(context, 'All ${Profile.adsPerDay} videos used today. Back tomorrow.', icon: AppIcons.time);
      return;
    }
    setState(() => _adBusy = true);
    final earned = await showRewardedHouseAd(context, ref, rewardCoins: Economy.adRewardCoins);
    if (!mounted) return;
    setState(() => _adBusy = false);
    if (!earned) {
      showToast(context, 'Closed early. No coins this time.', icon: AppIcons.time);
      return;
    }
    await ref.read(profileProvider.notifier).addCoins(Economy.adRewardCoins, reason: 'bonus-video');
    if (!mounted) return;
    showToast(context, 'Added ${countOf(Economy.adRewardCoins, 'coin')}', leading: const CoinIcon(size: 20));
  }

  /// Debug-only stand-in used when no store is reachable (plain simulator).
  /// Unreachable in release builds.
  Future<bool> _sandboxConfirm(String title, String price) async {
    if (!kDebugMode) return false;
    final ok = await showAppAlert(
      context,
      title: 'Sandbox purchase (debug build)',
      message: '$title for $price.\n\nNo store is available on this device. This debug-only checkout grants the item locally so the flow can be tested.',
      cancelLabel: 'Not now',
      confirmLabel: 'Buy',
    );
    return ok && mounted;
  }

  bool get _storeAvailable => ref.read(storeAvailableProvider).value ?? false;

  /// The App Store's product [id]. The products are asked for once per launch, so an answer
  /// without them (no network, or Apple not serving them yet, as for a while after the Paid Apps
  /// agreement turns active) is asked again before the store says it is not available.
  Future<ProductDetails?> _product(String id) async {
    final details = ref.read(productsProvider).value?[id];
    if (details != null && _storeAvailable) return details;
    if (!ref.read(platformCapsProvider).purchases) return null;
    setState(() => _querying = id);
    ref.invalidate(storeAvailableProvider);
    final products = await ref.read(productsProvider.future);
    if (mounted) setState(() => _querying = null);
    return _storeAvailable ? products[id] : null;
  }

  bool get _busy => _querying != null || ref.read(purchaseFlowProvider).busy;

  Future<void> _buy(_Product p) async {
    if (_busy) return;
    final details = await _product(p.id);
    if (!mounted) return;
    if (details != null) {
      await ref.read(purchaseFlowProvider.notifier).buy(details);
      return;
    }
    if (!kDebugMode) {
      showToast(context, 'The App Store is not available right now. Try again later.', icon: AppIcons.time);
      return;
    }
    if (!await _sandboxConfirm(p.title, p.price)) return;
    final n = ref.read(profileProvider.notifier);
    final g = p.grant;
    if (g.coins > 0) await n.addCoins(g.coins, reason: 'sandbox:${p.id}');
    if (g.tickets > 0) await n.addTickets(g.tickets, reason: 'sandbox:${p.id}');
    if (g.hints > 0) await n.addHints(g.hints, reason: 'sandbox:${p.id}');
    if (!mounted) return;
    Sfx.instance.coin();
    Haptics.success();
    showToast(context, 'Added ${p.title}', icon: AppIcons.check);
  }

  Future<void> _redeemCode() async {
    if (!ref.read(platformCapsProvider).giftCodes) {
      showToast(context, 'Gift codes can be redeemed on iPhone and iPad through the App Store.', icon: AppIcons.gift);
      return;
    }
    final opened = await ref.read(purchaseServiceProvider).presentCodeRedemptionSheet();
    if (!opened && mounted) {
      showToast(context, 'Gift codes can be redeemed on iPhone and iPad through the App Store.', icon: AppIcons.gift);
    }
  }

  Future<void> _buyVip(String productId) async {
    if (_busy) return;
    final details = await _product(productId);
    if (!mounted) return;
    if (details != null) {
      await ref.read(purchaseFlowProvider.notifier).buy(details);
      return;
    }
    if (!kDebugMode) {
      showToast(context, 'The App Store is not available right now. Try again later.', icon: AppIcons.time);
      return;
    }
    final trial = 'after a ${StoreProducts.vipTrialDays}-day trial';
    if (!await _sandboxConfirm('Carden VIP', productId == ProductIds.vipYearly ? '${StoreProducts.price(ProductIds.vipYearly)} / year $trial' : '${StoreProducts.price(ProductIds.vipMonthly)} / month $trial')) return;
    await ref.read(profileProvider.notifier).setVip(true);
    if (!mounted) return;
    Sfx.instance.win();
    Haptics.success();
    showToast(context, 'VIP active · every pack unlocked', icon: AppIcons.vip);
  }

  /// The number behind [_price], for comparing bundles.
  double _rawPrice(_Product p, Map<String, ProductDetails> products) => products[p.id]?.rawPrice ?? double.parse(StoreProducts.usdPrices[p.id]!);

  /// "Save 58%" for the yearly plan, from the App Store prices when both loaded, else the fallbacks.
  int? _yearlySaving(Map<String, ProductDetails> products) {
    final m = products[ProductIds.vipMonthly], y = products[ProductIds.vipYearly];
    if (m != null && y != null) return StoreProducts.yearlySavingPercent(m.rawPrice, y.rawPrice);
    return StoreProducts.yearlySavingPercent(
      double.parse(StoreProducts.usdPrices[ProductIds.vipMonthly]!),
      double.parse(StoreProducts.usdPrices[ProductIds.vipYearly]!),
    );
  }

  /// Store price when the product loaded, else the placeholder.
  String _price(_Product p, Map<String, ProductDetails> products) => products[p.id]?.price ?? p.price;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final profile = ref.watch(profileProvider).value;
    final caps = ref.watch(platformCapsProvider);
    final productsAsync = caps.purchases ? ref.watch(productsProvider) : null;
    final products = productsAsync?.value ?? const <String, ProductDetails>{};
    // The App Store answered without prices (offline, or not serving the products): nothing can be
    // bought, so nothing is shown for sale; the free ways to earn stay. While it is asked again the
    // panel stays (its button waits) instead of flashing the catalogue with placeholder prices.
    final pricesDown = caps.purchases && (productsAsync?.hasValue ?? false) && products.isEmpty;
    final retrying = pricesDown && (productsAsync?.isLoading ?? false);
    final adsLeft = profile?.adsLeftToday ?? Profile.adsPerDay;
    final isVip = profile?.isVip ?? false;
    final flow = ref.watch(purchaseFlowProvider);
    final busy = _querying != null || flow.busy;
    // The row that waits: its products asked for again, or its App Store sheet open.
    final activeId = _querying ?? (flow.stage == PurchaseStage.paying ? flow.productId : null);
    Widget grid(List<_Product> list) => _ProductGrid(products: list, onBuy: _buy, priceOf: (p) => _price(p, products), rawPriceOf: (p) => _rawPrice(p, products), busy: busy, activeId: activeId, purchasable: caps.purchases);
    final freeVideo = _FreeVideoOffer(adsLeft: adsLeft, busy: _adBusy, onWatch: _watchAd);
    final legal = <Widget>[
      if (!pricesDown) ...[
        const SizedBox(height: 16),
        Text(
          !caps.purchases
              ? 'VIP and bundles are sold in the iPhone app. A VIP subscription bought there is active here too.'
              : isVip
                  ? 'Payment is charged to your Apple ID when you confirm. VIP renews automatically unless cancelled at least 24 hours before the period ends; manage it in your App Store account settings.'
                  : 'Payment is charged to your Apple ID when you confirm, or when the free trial ends. VIP renews automatically unless cancelled at least 24 hours before the period ends; manage it in your App Store account settings.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: TypeSize.caption, height: 1.35, color: c.textTertiary),
        ),
      ],
      // Apple asks for both links where a subscription is sold (guideline 3.1.2).
      const SizedBox(height: 6),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _FooterLink(key: const ValueKey('store-terms'), label: 'Terms of use', url: AppLinks.termsOfUse),
          Text('·', style: TextStyle(fontSize: TypeSize.caption, color: c.textTertiary)),
          _FooterLink(key: const ValueKey('store-privacy'), label: 'Privacy policy', url: AppLinks.privacyPolicy),
        ],
      ),
    ];
    const header = EdgeInsets.fromLTRB(0, 24, 0, 12);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('Store'),
        leading: Padding(padding: const EdgeInsets.only(left: 12), child: RoundIconButton(icon: AppIcons.xmark, size: 38, onTap: () => context.pop())),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                CurrencyPill(currency: Currency.tickets, value: profile?.tickets ?? 0, compact: true),
                const SizedBox(width: 6),
                CurrencyPill(currency: Currency.coins, value: profile?.coins ?? 0, compact: true),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        // Opened at VIP (`/store?vip=1`): the VIP card, far down the list, is built at once so it
        // can be scrolled to.
        scrollCacheExtent: widget.showVip ? const ScrollCacheExtent.pixels(6000) : null,
        // The store is a sheet: the end padding clears the home indicator.
        padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + kToolbarHeight + 8, 20, GlassTabBar.scrollEndPadding(context)),
        children: [
          if (!caps.purchases) ...[
            const StoreWebNotice(),
            const SizedBox(height: 12),
          ],
          // A member sees their membership first, small; the sales card is for everyone else.
          if (isVip) ...[
            _VipMemberCard(key: _vipKey, until: profile?.vipExpiresAt, manage: caps.purchases),
            const SizedBox(height: 12),
          ],
          if (pricesDown) ...[
            // Nothing for sale while the App Store is away: one panel says so, then what is free.
            _StoreDownPanel(retrying: retrying, onRetry: () => ref.invalidate(storeAvailableProvider)),
            const SectionHeader(title: 'Earn for free', subtitle: 'Coins, tickets and hints without paying', padding: header),
            freeVideo,
            const SizedBox(height: 12),
            const _FreeWays(),
          ] else ...[
            // What can be bought first; the free video is the first coin offer, styled like a bundle.
            SectionHeader(title: 'Coins', subtitle: 'Unlock packs and boosters', padding: header.copyWith(top: isVip || !caps.purchases ? 12 : 4)),
            freeVideo,
            const SizedBox(height: 12),
            grid(_coinProducts),
            const SectionHeader(title: 'Tickets', subtitle: 'Premium packs and the piggy bank', padding: header),
            grid(_ticketProducts),
            const SectionHeader(title: 'Hints', subtitle: 'Show a card its place', padding: header),
            grid(_boosterProducts),
            if (!isVip) ...[
              const SizedBox(height: 24),
              _VipCard(
                key: _vipKey,
                monthlyPrice: products[ProductIds.vipMonthly]?.price ?? StoreProducts.price(ProductIds.vipMonthly),
                yearlyPrice: products[ProductIds.vipYearly]?.price ?? StoreProducts.price(ProductIds.vipYearly),
                yearlySaving: _yearlySaving(products),
                busy: busy,
                activeId: activeId,
                purchasable: caps.purchases,
                onBuyMonthly: () => _buyVip(ProductIds.vipMonthly),
                onBuyYearly: () => _buyVip(ProductIds.vipYearly),
                onRedeem: _redeemCode,
              ),
            ],
            // The terms sit with what they are about: right under the last thing for sale.
            ...legal,
            // Then how to get things without paying.
            const SectionHeader(title: 'Earn for free', subtitle: 'Coins, tickets and hints without paying', padding: header),
            const _FreeWays(),
          ],
          if (pricesDown) ...[const SizedBox(height: 16), ...legal],
        ],
      ),
    );
  }
}

/// The free video as the first coin offer, styled like a bundle: the coin art with a play mark,
/// the amount, how many are left today, and the "price" (Watch) as the tile's button. One honest
/// state in its place: Watch, the minutes until the next one, or Back tomorrow.
class _FreeVideoOffer extends ConsumerStatefulWidget {
  const _FreeVideoOffer({required this.adsLeft, required this.busy, required this.onWatch});
  final int adsLeft;
  final bool busy;
  final VoidCallback onWatch;

  @override
  ConsumerState<_FreeVideoOffer> createState() => _FreeVideoOfferState();
}

class _FreeVideoOfferState extends ConsumerState<_FreeVideoOffer> {
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wait = HouseAdPolicy.rewardedWaitLeft(ref.read(localStoreProvider).lastRewardedAt);
    // While a cooldown runs, look again every 20 s so the tile turns back into Watch by itself.
    _tick?.cancel();
    if (wait > Duration.zero && widget.adsLeft > 0) _tick = Timer(const Duration(seconds: 20), () => mounted ? setState(() {}) : null);
    final ready = widget.adsLeft > 0 && wait <= Duration.zero;
    final status = widget.adsLeft == 0 ? 'Back tomorrow' : (wait > Duration.zero ? 'Next in ${formatTimeLeft(wait)}' : null);
    return Pressable(
      onTap: ready && !widget.busy ? widget.onWatch : null,
      scale: 0.99,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(Radii.lg), border: Border.all(color: c.stroke)),
        child: Row(
          children: [
            // A coin with a small play mark: a bundle paid for with a short video.
            SizedBox(
              width: 46,
              height: 42,
              child: Stack(
                children: [
                  const Positioned(left: 0, top: 3, child: CoinIcon(size: 36)),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: context.accentFill, shape: BoxShape.circle, border: Border.all(color: c.card, width: 2)),
                      child: Padding(padding: const EdgeInsets.only(left: 1), child: Icon(AppIcons.playFill, size: 9, color: context.onAccent)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Two lines at most (Larger Text on a small phone), never cut.
                  Text('${formatCount(Economy.adRewardCoins)} coins, free', maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.callout, letterSpacing: -0.2)),
                  const SizedBox(height: 2),
                  Text(
                    // The play mark and Watch say it is a video; the line keeps to what changes.
                    widget.adsLeft > 0 ? '${widget.adsLeft} of ${Profile.adsPerDay} left today' : 'All ${Profile.adsPerDay} used today',
                    maxLines: 2,
                    style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // The tile's "price": a button like the bundles' price buttons, or the state as text.
            if (status != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(status, style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote, fontWeight: FontWeight.w600)),
              )
            else
              _PriceButton(
                width: 96,
                busy: widget.busy,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(AppIcons.playFill, size: 12, color: context.accent),
                    const SizedBox(width: 6),
                    Text('Watch', style: TextStyle(color: context.accent, fontWeight: FontWeight.w700, fontSize: TypeSize.body)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({super.key, required this.label, required this.url});
  final String label;
  final Uri url;

  @override
  Widget build(BuildContext context) => CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        onPressed: () async {
          if (!await openLink(url) && context.mounted) showToast(context, 'The page could not open. Check your connection and try again.', icon: AppIcons.signal);
        },
        child: Text(label, style: TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w600, color: context.accent)),
      );
}

/// Web notice at the top of the store: no purchases here, but everything
/// earned is saved to the account.
class StoreWebNotice extends StatelessWidget {
  const StoreWebNotice({super.key});

  static const message = 'Purchases are available in the iPhone app. Coins, tickets and hints you earn here are saved to your account.';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      padding: Insets.card,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconTile(icon: AppIcons.devicePhonePortrait, size: IconTile.small),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Web version', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(message, style: TextStyle(fontSize: TypeSize.footnote, height: 1.4, color: c.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// In place of the bundles and VIP when the App Store gave no prices: what happened, that the game
/// itself is not affected, and the one action that can help.
class _StoreDownPanel extends StatelessWidget {
  const _StoreDownPanel({required this.retrying, required this.onRetry});
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        children: [
          const IconTile(icon: AppIcons.signal, size: IconTile.tool),
          const SizedBox(height: 12),
          Text('Purchases are unavailable', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'The App Store is not responding, so coins, tickets, hints and VIP cannot be bought right now. Everything you own works as usual.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: TypeSize.footnote, height: 1.4, color: c.textSecondary),
          ),
          const SizedBox(height: 16),
          BigButton(label: 'Try again', kind: ButtonKind.secondary, height: 44, loading: retrying, onTap: retrying ? null : onRetry),
        ],
      ),
    );
  }
}

/// The Store's first row for a VIP member: what they have, until when, and where to manage it.
/// A small card in the VIP look (lib/widgets/vip.dart) instead of the sales pitch.
class _VipMemberCard extends StatelessWidget {
  const _VipMemberCard({super.key, required this.until, required this.manage});
  final DateTime? until;
  /// False on web: the subscription is managed on iPhone.
  final bool manage;

  @override
  Widget build(BuildContext context) {
    return VipSurface(
      padding: Insets.cardCompact,
      child: Row(
        children: [
          const VipCrown(size: IconTile.medium),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('VIP', style: TextStyle(color: Vip.fg, fontWeight: FontWeight.w700, fontSize: TypeSize.headline, letterSpacing: -0.2)),
                const SizedBox(height: 2),
                // On a narrow phone the line breaks before the date, never inside it.
                Text(
                  until != null ? 'Active until ${formatDate(until!).replaceAll(' ', '\u00A0')}' : 'Active',
                  maxLines: 2,
                  style: TextStyle(fontSize: TypeSize.footnote, color: Vip.fgSecondary),
                ),
              ],
            ),
          ),
          if (manage) ...[
            const SizedBox(width: 12),
            BigButton(
              label: 'Manage',
              kind: ButtonKind.ghostLight,
              height: 36,
              expand: false,
              onTap: () async {
                if (!await openLink(AppLinks.manageSubscriptions) && context.mounted) {
                  showToast(context, 'The page could not open. Check your connection and try again.', icon: AppIcons.signal);
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// VIP for everyone who does not have it, in the VIP look (lib/widgets/vip.dart): the benefits,
/// then the two plans with their prices as the most prominent pricing on the card, one gold button
/// that starts the selected plan's free trial, and the exact line of what follows (App Review 3.1.2).
class _VipCard extends StatefulWidget {
  const _VipCard({
    super.key,
    required this.monthlyPrice,
    required this.yearlyPrice,
    this.yearlySaving,
    required this.busy,
    this.activeId,
    this.purchasable = true,
    required this.onBuyMonthly,
    required this.onBuyYearly,
    required this.onRedeem,
  });
  final String monthlyPrice;
  final String yearlyPrice;
  /// Whole percent the yearly plan saves over twelve months, when known.
  final int? yearlySaving;

  /// A purchase is under way: the plans and the trial button take no tap.
  final bool busy;

  /// The plan whose purchase is under way: the trial button shows a spinner.
  final String? activeId;
  /// False on web: the benefits stay as information, the buy buttons, the
  /// prices and the gift-code link are replaced by an "Available on iPhone"
  /// label.
  final bool purchasable;
  final VoidCallback onBuyMonthly;
  final VoidCallback onBuyYearly;
  final VoidCallback onRedeem;

  @override
  State<_VipCard> createState() => _VipCardState();
}

class _VipCardState extends State<_VipCard> {
  /// The plan the trial button starts. Yearly first: it is the better deal.
  bool _yearly = true;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final busy = w.busy;
    return VipSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              VipCrown(size: 44),
              SizedBox(width: 12),
              Expanded(child: Text('Carden VIP', style: TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.title3, letterSpacing: -0.3, color: Vip.fg))),
            ],
          ),
          const SizedBox(height: 16),
          for (final line in const [
            'Every pack and every past monthly pack unlocked',
            'A 4th daily quest and a 6th weekly quest',
            'No breaks between puzzles',
            'Unlimited My Puzzles uploads',
            '+500 coins every week',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 1), child: Icon(AppIcons.checkmarkCircleFill, color: Vip.gold, size: 16)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(line, style: TextStyle(color: Vip.fg.withValues(alpha: 0.92), fontSize: TypeSize.footnote, height: 1.3))),
                ],
              ),
            ),
          const SizedBox(height: 10),
          if (!w.purchasable)
            Row(
              children: [
                Chip2(label: 'Available on iPhone', icon: AppIcons.devicePhonePortrait, color: Colors.white.withValues(alpha: 0.12), foreground: Vip.fg),
                const SizedBox(width: 10),
                // No price on web: the App Store shows it on iPhone.
                Expanded(child: Text('Starts with a ${StoreProducts.vipTrialDays}-day free trial.', style: TextStyle(color: Vip.fgSecondary, fontSize: TypeSize.caption))),
              ],
            )
          else ...[
            // The plans with their prices are the most prominent pricing on the card; the
            // trial is how either plan starts (App Review 3.1.2).
            _PlanRow(
              key: const ValueKey('vip-plan-yearly'),
              title: 'Yearly',
              price: w.yearlyPrice,
              period: '/ year',
              badge: w.yearlySaving == null ? null : 'Save ${w.yearlySaving}%',
              selected: _yearly,
              onTap: busy ? null : () => setState(() => _yearly = true),
            ),
            const SizedBox(height: 8),
            _PlanRow(
              key: const ValueKey('vip-plan-monthly'),
              title: 'Monthly',
              price: w.monthlyPrice,
              period: '/ month',
              selected: !_yearly,
              onTap: busy ? null : () => setState(() => _yearly = false),
            ),
            const SizedBox(height: 16),
            // One button starts the selected plan; it waits while either plan's App Store sheet is open.
            BigButton(
              label: 'Start ${StoreProducts.vipTrialDays}-day free trial',
              kind: ButtonKind.gold,
              loading: w.activeId == ProductIds.vipYearly || w.activeId == ProductIds.vipMonthly,
              onTap: busy ? null : (_yearly ? w.onBuyYearly : w.onBuyMonthly),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '${StoreProducts.vipTrialDays} days free, then ${_yearly ? '${w.yearlyPrice} a year' : '${w.monthlyPrice} a month'}. Cancel anytime.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Vip.fgSecondary, fontSize: TypeSize.footnote),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Pressable(
                onTap: w.onRedeem,
                child: TapTarget(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(AppIcons.gift, size: 16, color: Vip.fgSecondary),
                        const SizedBox(width: 6),
                        Flexible(child: Text('Have a gift code? Redeem it', style: TextStyle(color: Vip.fg.withValues(alpha: 0.86), fontSize: TypeSize.footnote, fontWeight: FontWeight.w600))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One VIP plan on the VIP card: a radio mark, the plan name (with its saving in gold) and its
/// price, large. The selected plan gets a gold outline on a faint white fill.
class _PlanRow extends StatelessWidget {
  const _PlanRow({super.key, required this.title, required this.price, required this.period, this.badge, required this.selected, required this.onTap});
  final String title;
  final String price;
  final String period;
  final String? badge;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: '$title, $price $period',
      child: Pressable(
        onTap: onTap,
        scale: 0.98,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: selected ? 0.08 : 0.0),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: selected ? Vip.gold : Vip.lineOf(context), width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              Icon(selected ? AppIcons.checkmarkCircleFill : AppIcons.circle, size: 22, color: selected ? Vip.gold : Vip.fgTertiaryOf(context)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Vip.fg, fontSize: TypeSize.body, fontWeight: FontWeight.w600)),
                    if (badge != null) Text(badge!, style: const TextStyle(color: Vip.gold, fontSize: TypeSize.caption, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: price, style: const TextStyle(fontSize: TypeSize.headline, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                  TextSpan(text: ' $period', style: TextStyle(fontSize: TypeSize.footnote, color: Vip.fgSecondary)),
                ]),
                style: const TextStyle(color: Vip.fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Art { coin, coins, coinsLarge, coinsHuge, ticket, tickets, hints, hintsLarge }

/// A store tile. Amounts and fallback prices come from [StoreProducts], the
/// one table the server grant and the App Store metadata are checked against.
class _Product {
  const _Product(this.id, {this.art = _Art.coin});
  final String id;
  final _Art art;

  ProductGrant get grant => StoreProducts.grant(id);
  String get title => grant.label;
  String get price => StoreProducts.price(id);
}

const _coinProducts = [
  _Product(ProductIds.coins1000, art: _Art.coin),
  _Product(ProductIds.coins3000, art: _Art.coins),
  _Product(ProductIds.coins5500, art: _Art.coinsLarge),
  _Product(ProductIds.coins12000, art: _Art.coinsHuge),
];
const _ticketProducts = [
  _Product(ProductIds.tickets5, art: _Art.ticket),
  _Product(ProductIds.tickets15, art: _Art.tickets),
];
const _boosterProducts = [
  _Product(ProductIds.hints5, art: _Art.hints),
  _Product(ProductIds.hints15, art: _Art.hintsLarge),
];

/// Product artwork: stacked currency marks whose count grows with the bundle.
class _ProductArt extends StatelessWidget {
  const _ProductArt({required this.art});
  final _Art art;

  @override
  Widget build(BuildContext context) {
    Widget stack(Widget Function(double) make, int count, double size) => SizedBox(
          height: 40,
          width: size + (count - 1) * size * 0.45,
          child: Stack(
            children: [
              for (var i = 0; i < count; i++) Positioned(left: i * size * 0.45, top: (count - 1 - i) * 2.0, child: make(size)),
            ],
          ),
        );
    return switch (art) {
      _Art.coin => stack((s) => CoinIcon(size: s), 1, 36),
      _Art.coins => stack((s) => CoinIcon(size: s), 2, 34),
      _Art.coinsLarge => stack((s) => CoinIcon(size: s), 3, 32),
      _Art.coinsHuge => stack((s) => CoinIcon(size: s), 4, 30),
      _Art.ticket => stack((s) => TicketIcon(size: s), 1, 32),
      _Art.tickets => stack((s) => TicketIcon(size: s), 3, 28),
      // Each disc sits on a ring in the card colour, so the next one does not cut its bulb.
      _Art.hints => stack((s) => _Ringed(size: s, child: HintIcon(size: s)), 2, 32),
      _Art.hintsLarge => stack((s) => _Ringed(size: s, child: HintIcon(size: s)), 4, 28),
    };
  }
}

/// A round mark with a 2 pt ring in the card colour around it (stacked artwork).
class _Ringed extends StatelessWidget {
  const _Ringed({required this.size, required this.child});
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: context.colors.card, width: 2)),
        child: child,
      );
}

/// Every way to earn without paying, each row naming where it leads: playing first (the Store
/// closes and a picture opens), the daily gift and the piggy bank as sheets over the Store, the
/// Lucky Wheel on top of it, the quests on their tab. Level-ups are information only.
class _FreeWays extends ConsumerWidget {
  const _FreeWays();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    Widget divider() => Divider(height: 1, thickness: 1, color: c.stroke, indent: 16 + IconTile.small + 12);
    return SoftCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Every picture pays coins (Economy.completionCoins: more for bigger boards and stars).
          ListRow(
            key: const ValueKey('store-play-puzzle'),
            icon: AppIcons.shuffle,
            title: 'Play a puzzle',
            subtitle: 'Coins for every picture, more with 3 stars',
            onTap: () => playFromStore(context, ref),
          ),
          divider(),
          ListRow(icon: AppIcons.dailyGift, title: 'Daily gift', subtitle: 'Coins daily, plus tickets and hints', onTap: () => showDailyRewardSheet(context)),
          divider(),
          ListRow(
            icon: AppIcons.quests,
            title: 'Quests',
            subtitle: 'Coins daily, tickets weekly',
            onTap: () {
              context.pop();
              context.go('/events');
            },
          ),
          divider(),
          ListRow(icon: AppIcons.piggy, title: 'Piggy bank', subtitle: '${Economy.piggyPerPuzzle} coins for every picture, up to ${formatCount(Profile.piggyCapacity)}', onTap: () => showPiggySheet(context)),
          divider(),
          ListRow(icon: AppIcons.wheel, title: 'Lucky Wheel', subtitle: 'Coins, hints and boosters for a ticket', onTap: () => context.push('/wheel')),
          divider(),
          const ListRow(icon: AppIcons.level, title: 'Level-ups', subtitle: 'Coins, hints and tickets as you level', trailing: SizedBox.shrink()),
        ],
      ),
    );
  }
}

/// Earn for free > Play a puzzle (owner feedback, 2026-10-17): closes the Store and starts Quick
/// play, as on Home (the `/quick` link action: a random picture's board picker, never a board by
/// itself). Before Quick play opens in the guided start (3 pictures, [Reveal.quickPlay]) it opens the
/// picture Home suggests instead ([nextStepProvider]), or Home itself when there is none: the first
/// board is under way and Home's Continue leads back to it.
void playFromStore(BuildContext context, WidgetRef ref) {
  final quickPlay = ref.read(revealsProvider).contains(Reveal.quickPlay);
  final next = quickPlay ? null : ref.read(nextStepProvider);
  // Read before the Store closes: its context and ref go with it.
  final links = ref.read(deepLinksProvider);
  final router = GoRouter.of(context);
  context.pop();
  if (quickPlay) {
    unawaited(links.show(AppLink.parse(Uri(path: '/quick'))!));
  } else if (next == null || next.route == '/library') {
    // A tab is gone to, as Home's next-step card does; a picture opens on top.
    router.go(next?.route ?? '/home');
  } else {
    unawaited(router.push(next.route));
  }
}

/// A tile's price: a full-width button in the accent tint, or filled (the one primary) for the
/// section's best deal. While its App Store sheet is open, a spinner keeps its place.
class _PriceButton extends StatelessWidget {
  const _PriceButton({required this.child, this.filled = false, this.busy = false, this.width});
  final Widget child;
  final bool filled;
  final bool busy;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 36,
      width: width,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: filled ? context.accentFill : c.accentTint, borderRadius: BorderRadius.circular(Radii.md)),
      child: busy ? SizedBox(height: 18, child: CupertinoActivityIndicator(radius: 7, color: filled ? context.onAccent : null)) : FittedBox(fit: BoxFit.scaleDown, child: child),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.products, required this.onBuy, required this.priceOf, required this.rawPriceOf, this.busy = false, this.activeId, this.purchasable = true});
  final List<_Product> products;
  final void Function(_Product) onBuy;
  final String Function(_Product) priceOf;
  final double Function(_Product) rawPriceOf;

  static double _amount(_Product p) => (p.grant.coins + p.grant.tickets + p.grant.hints).toDouble();

  /// How much more a bundle gives per unit of money than the smallest one, in whole
  /// percent rounded down: a fact the player can check, instead of a "Popular" label.
  int _bonus(_Product p) {
    final base = _amount(products.first) / rawPriceOf(products.first);
    return ((_amount(p) / rawPriceOf(p) / base - 1) * 100).floor();
  }

  /// A purchase is under way: no tile takes a tap, and the others dim.
  final bool busy;

  /// The tile whose purchase is under way: a spinner in place of its price.
  final String? activeId;

  /// False on web: each tile shows "Available on iPhone" instead of its
  /// price, and a tap says where to buy it.
  final bool purchasable;

  @override
  Widget build(BuildContext context) {
    // Two centred tiles a row: the measured saving in its own line on top (never over the art),
    // the art, the amount, and the price as a full-width button. The section's best deal is the
    // one filled price: the value speaks, no outline or label needed.
    final bestIndex = products.length > 1 && _bonus(products.last) >= 3 ? products.length - 1 : -1;
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 12.0;
        final width = (box.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < products.length; i++)
              SizedBox(
                width: width,
                child: _ProductTile(
                  product: products[i],
                  price: priceOf(products[i]),
                  bonus: _bonus(products[i]),
                  best: i == bestIndex,
                  purchasable: purchasable,
                  active: products[i].id == activeId,
                  dimmed: busy && products[i].id != activeId,
                  onTap: !purchasable
                      ? () => showToast(context, purchasesOnIphoneMessage, icon: AppIcons.devicePhonePortrait)
                      : (busy ? null : () => onBuy(products[i])),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.price, required this.bonus, required this.best, required this.purchasable, this.active = false, this.dimmed = false, required this.onTap});
  final _Product product;
  final String price;
  final int bonus;
  final bool best;
  final bool purchasable;

  /// Its App Store sheet is open: a spinner in place of the price.
  final bool active;

  /// Another tile's purchase is under way.
  final bool dimmed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = product;
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: AnimatedOpacity(
        opacity: dimmed ? 0.5 : 1,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(Radii.lg), border: Border.all(color: c.stroke)),
          child: Column(
            children: [
              // The saving has its own line, so it never sits on the art; empty for the base bundle
              // (and on web, where no price is shown to compare).
              SizedBox(
                // The chip's own height (it grows with Larger Text), the same in every tile of a row.
                height: MediaQuery.textScalerOf(context).scale(TypeSize.caption * 1.2) + 10,
                child: bonus >= 3 && purchasable
                    ? Center(child: Chip2(label: '+$bonus% more', color: c.accentTint, foreground: context.accent))
                    : null,
              ),
              const SizedBox(height: 10),
              SizedBox(height: 42, child: Center(child: _ProductArt(art: p.art))),
              const SizedBox(height: 12),
              // The amount is never cut: with Larger Text on a small phone it scales down a little.
              FittedBox(fit: BoxFit.scaleDown, child: Text(p.title, maxLines: 1, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.callout, letterSpacing: -0.2))),
              const SizedBox(height: 12),
              if (purchasable)
                _PriceButton(
                  filled: best,
                  busy: active,
                  // Differentiate without colour: the best deal also carries a rosette, not only the fill.
                  child: best && A11y.symbolsOf(context)
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(AppIcons.level, size: 14, color: context.onAccent),
                          const SizedBox(width: 4),
                          Text(price, maxLines: 1, style: TextStyle(color: context.onAccent, fontWeight: FontWeight.w700, fontSize: TypeSize.body)),
                        ])
                      : Text(price, maxLines: 1, style: TextStyle(color: best ? context.onAccent : context.accent, fontWeight: FontWeight.w700, fontSize: TypeSize.body)),
                )
              else
                _PriceButton(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.devicePhonePortrait, size: 13, color: context.accent),
                      const SizedBox(width: 4),
                      Text('Available on iPhone', maxLines: 1, style: TextStyle(color: context.accent, fontWeight: FontWeight.w600, fontSize: TypeSize.caption)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
