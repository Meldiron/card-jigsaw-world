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
import '../../core/theme/tokens.dart';
import '../../data/purchases.dart';
import '../../models/models.dart';
import '../../state/profile.dart';
import '../../state/sync.dart';
import '../../state/purchases.dart';
import '../../state/settings.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../ads/house_ads.dart';

/// Store: free bonus video (capped per day), coin bundles, ticket bundles,
/// hint packs, VIP. Purchases go through StoreKit and are verified by the
/// `verify-purchase` Appwrite Function before anything is granted. In debug
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
  bool _buying = false;
  StreamSubscription<PurchaseEvent>? _events;
  final _vipKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (ref.read(platformCapsProvider).purchases) {
      final service = ref.read(purchaseServiceProvider);
      service.start();
      _events = service.events.listen(_onPurchaseEvent);
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
    position.animateTo(to, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  void _onPurchaseEvent(PurchaseEvent e) {
    if (!mounted) return;
    switch (e) {
      case PurchaseVerified():
        setState(() => _buying = false);
        ref.read(syncProvider.notifier).sync(silent: true);
        final g = e.grant;
        if (e.alreadyApplied && !e.restored) {
          showToast(context, 'Purchase already applied', icon: AppIcons.check);
        } else if (g.vipExpiresAt != null) {
          Sfx.instance.win();
          Haptics.success();
          showToast(context, 'VIP active until ${formatDate(g.vipExpiresAt!)}', icon: AppIcons.vip);
        } else {
          Sfx.instance.coin();
          Haptics.success();
          final parts = [
            if (g.coins > 0) '${formatCount(g.coins)} coins',
            if (g.tickets > 0) '${formatCount(g.tickets)} ticket${g.tickets == 1 ? '' : 's'}',
            if (g.hints > 0) '${formatCount(g.hints)} hint${g.hints == 1 ? '' : 's'}',
          ];
          showToast(context, 'Added ${parts.join(', ')}', icon: AppIcons.check);
        }
      case PurchaseFailed():
        setState(() => _buying = false);
        showToast(context, e.message, icon: AppIcons.time);
      case PurchaseCanceled():
        setState(() => _buying = false);
      case PurchasePending():
        showToast(context, 'Waiting for approval', icon: AppIcons.time);
      case RestoreFinished():
        setState(() => _buying = false);
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
    setState(() => _buying = true);
    ref.invalidate(storeAvailableProvider);
    final products = await ref.read(productsProvider.future);
    if (mounted) setState(() => _buying = false);
    return _storeAvailable ? products[id] : null;
  }

  Future<void> _buy(_Product p) async {
    if (_buying) return;
    final details = await _product(p.id);
    if (!mounted) return;
    if (details != null) {
      setState(() => _buying = true);
      final started = await ref.read(purchaseServiceProvider).buy(details);
      if (!started && mounted) setState(() => _buying = false);
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
    if (_buying) return;
    final details = await _product(productId);
    if (!mounted) return;
    if (details != null) {
      setState(() => _buying = true);
      final started = await ref.read(purchaseServiceProvider).buy(details);
      if (!started && mounted) setState(() => _buying = false);
      return;
    }
    if (!kDebugMode) {
      showToast(context, 'The App Store is not available right now. Try again later.', icon: AppIcons.time);
      return;
    }
    final trial = 'after a ${StoreProducts.vipTrialDays}-day trial';
    if (!await _sandboxConfirm('Card Jigsaw World VIP', productId == ProductIds.vipYearly ? '${StoreProducts.price(ProductIds.vipYearly)} / year $trial' : '${StoreProducts.price(ProductIds.vipMonthly)} / month $trial')) return;
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
    final storeUp = caps.purchases && (ref.watch(storeAvailableProvider).value ?? false);
    // The App Store answered without prices (offline, or not serving the products): say so,
    // instead of showing the placeholder US prices as if they could be bought.
    final pricesDown = caps.purchases && !(productsAsync?.isLoading ?? false) && products.isEmpty;
    final adsLeft = profile?.adsLeftToday ?? Profile.adsPerDay;
    final isVip = profile?.isVip ?? false;
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
          if (pricesDown) ...[
            _StoreDownNotice(onRetry: () => ref.invalidate(storeAvailableProvider)),
            const SizedBox(height: 12),
          ],
          // A member sees their membership first, small; the sales card is for everyone else.
          if (isVip) ...[
            _VipMemberCard(key: _vipKey, until: profile?.vipExpiresAt, manage: caps.purchases),
            const SizedBox(height: 12),
          ],
          // Free coins via bonus video, limited per day and spaced by a cooldown.
          _FreeCoinsRow(adsLeft: adsLeft, busy: _adBusy, onWatch: _watchAd),
          const SectionHeader(title: 'Coins', subtitle: 'Unlock packs and boosters', padding: EdgeInsets.fromLTRB(0, 24, 0, 8)),
          _FreeNote(text: 'Free coins: daily quests, the daily gift, level-ups, the piggy bank and the Lucky Wheel.'),
          _ProductGrid(products: _coinProducts, onBuy: _buy, priceOf: (p) => _price(p, products), rawPriceOf: (p) => _rawPrice(p, products), busy: _buying, purchasable: caps.purchases, unavailable: pricesDown),
          const SectionHeader(title: 'Tickets', subtitle: 'Premium packs and the piggy bank', padding: EdgeInsets.fromLTRB(0, 24, 0, 8)),
          _FreeNote(text: 'Free tickets: the daily gift, weekly quests, world-day events and every third level.'),
          _ProductGrid(products: _ticketProducts, onBuy: _buy, priceOf: (p) => _price(p, products), rawPriceOf: (p) => _rawPrice(p, products), busy: _buying, purchasable: caps.purchases, unavailable: pricesDown),
          const SectionHeader(title: 'Hints', subtitle: 'Show a card its place', padding: EdgeInsets.fromLTRB(0, 24, 0, 8)),
          _FreeNote(text: 'Free hints: the daily gift on even days, every second level and the Lucky Wheel.'),
          _ProductGrid(products: _boosterProducts, onBuy: _buy, priceOf: (p) => _price(p, products), rawPriceOf: (p) => _rawPrice(p, products), busy: _buying, purchasable: caps.purchases, unavailable: pricesDown),
          if (!isVip) ...[
            const SizedBox(height: 24),
            _VipCard(
              key: _vipKey,
              isVip: isVip,
              vipUntil: profile?.vipExpiresAt,
              monthlyPrice: products[ProductIds.vipMonthly]?.price ?? StoreProducts.price(ProductIds.vipMonthly),
              yearlyPrice: products[ProductIds.vipYearly]?.price ?? StoreProducts.price(ProductIds.vipYearly),
              yearlySaving: _yearlySaving(products),
              busy: _buying,
              purchasable: caps.purchases,
              unavailable: pricesDown,
              onBuyMonthly: () => _buyVip(ProductIds.vipMonthly),
              onBuyYearly: () => _buyVip(ProductIds.vipYearly),
              onRedeem: _redeemCode,
            ),
          ],
          const SizedBox(height: 16),
          Center(
            child: Text(
              !caps.purchases
                  ? 'VIP and bundles are sold in the iPhone app. A VIP subscription bought there is active here too.'
                  : isVip && storeUp
                      ? 'Payment is charged to your Apple ID when you confirm. VIP renews automatically unless cancelled at least 24 hours before the period ends; manage it in your App Store account settings.'
                      : storeUp || !pricesDown
                      ? 'Payment is charged to your Apple ID when you confirm, or when the free trial ends. VIP renews automatically unless cancelled at least 24 hours before the period ends; manage it in your App Store account settings.'
                      : (kDebugMode ? 'Store unavailable on this device. Debug sandbox purchases grant items locally.' : 'The App Store is not available right now.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: TypeSize.caption, color: c.textTertiary),
            ),
          ),
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
        ],
      ),
    );
  }
}

/// The free video row: one line of detail and one honest state on the right:
/// "Watch +40", the minutes until the next one, or "Back tomorrow" as plain text.
class _FreeCoinsRow extends ConsumerStatefulWidget {
  const _FreeCoinsRow({required this.adsLeft, required this.busy, required this.onWatch});
  final int adsLeft;
  final bool busy;
  final VoidCallback onWatch;

  @override
  ConsumerState<_FreeCoinsRow> createState() => _FreeCoinsRowState();
}

class _FreeCoinsRowState extends ConsumerState<_FreeCoinsRow> {
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
    // While a cooldown runs, look again every 20 s so the row turns back into Watch by itself.
    _tick?.cancel();
    if (wait > Duration.zero && widget.adsLeft > 0) _tick = Timer(const Duration(seconds: 20), () => mounted ? setState(() {}) : null);
    final Widget trailing;
    if (widget.adsLeft == 0) {
      trailing = Text('Back tomorrow', style: TextStyle(color: c.textSecondary, fontSize: TypeSize.body, fontWeight: FontWeight.w600));
    } else if (wait > Duration.zero) {
      trailing = Text('Next in ${formatTimeLeft(wait)}', style: TextStyle(color: c.textSecondary, fontSize: TypeSize.body, fontWeight: FontWeight.w600));
    } else {
      trailing = BigButton.cost(label: 'Watch', currency: Currency.coins, amount: Economy.adRewardCoins, amountPrefix: '+', height: 40, expand: false, onTap: widget.busy ? null : widget.onWatch);
    }
    return SoftCard(
      padding: Insets.cardCompact,
      child: Row(
        children: [
          const IconTile(icon: AppIcons.video, size: IconTile.medium),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Free coins', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  // The play mark and Watch say it is a video; the line keeps to what changes.
                  widget.adsLeft > 0 ? '${widget.adsLeft} left today' : 'All ${Profile.adsPerDay} used today',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing,
        ],
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

/// Top of the Store when the App Store gave no prices: what happened, that the
/// game itself is not affected, and a way to ask again.
class _StoreDownNotice extends StatelessWidget {
  const _StoreDownNotice({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      padding: Insets.card,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconTile(icon: AppIcons.signal, size: IconTile.small),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('The App Store is not responding', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text('Prices and purchases come back when it answers. Free coins and everything you own work as usual.', style: TextStyle(fontSize: TypeSize.footnote, height: 1.35, color: c.textSecondary)),
                const SizedBox(height: 10),
                BigButton(label: 'Try again', kind: ButtonKind.secondary, height: 36, expand: false, onTap: onRetry),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Store's first row for a VIP member: what they have, until when, and where to
/// manage it. One quiet card instead of the sales pitch.
class _VipMemberCard extends StatelessWidget {
  const _VipMemberCard({super.key, required this.until, required this.manage});
  final DateTime? until;
  /// False on web: the subscription is managed on iPhone.
  final bool manage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      padding: Insets.card,
      child: Row(
        children: [
          IconTile(icon: AppIcons.vip, size: IconTile.medium, color: Brand.coin.withValues(alpha: context.isDark ? 0.18 : 0.14), iconColor: context.isDark ? Brand.coin : Brand.coinDeep),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('VIP', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  until != null ? 'Active until ${formatDate(until!)}' : 'Active',
                  style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary),
                ),
              ],
            ),
          ),
          if (manage)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              minimumSize: const Size(44, 44),
              onPressed: () async {
                if (!await openLink(AppLinks.manageSubscriptions) && context.mounted) {
                  showToast(context, 'The page could not open. Check your connection and try again.', icon: AppIcons.signal);
                }
              },
              child: Text('Manage', style: TextStyle(color: context.accent, fontSize: TypeSize.body, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

class _VipCard extends StatefulWidget {
  const _VipCard({
    super.key,
    required this.isVip,
    required this.vipUntil,
    required this.monthlyPrice,
    required this.yearlyPrice,
    this.yearlySaving,
    required this.busy,
    this.purchasable = true,
    this.unavailable = false,
    required this.onBuyMonthly,
    required this.onBuyYearly,
    required this.onRedeem,
  });
  final bool isVip;
  final DateTime? vipUntil;
  final String monthlyPrice;
  final String yearlyPrice;
  /// Whole percent the yearly plan saves over twelve months, when known.
  final int? yearlySaving;
  final bool busy;
  /// False on web: the benefits stay as information, the buy buttons, the
  /// prices and the gift-code link are replaced by an "Available on iPhone"
  /// label.
  final bool purchasable;

  /// The App Store gave no prices: the plans are not offered until it answers.
  final bool unavailable;
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
    final isVip = w.isVip, vipUntil = w.vipUntil, purchasable = w.purchasable, busy = w.busy;
    final c = context.colors;
    // A quiet card like the rest of the Store: the crown keeps its gold, actions are cobalt.
    final fg = c.textPrimary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(Radii.lg), border: Border.all(color: c.stroke)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconTile(icon: AppIcons.vip, size: IconTile.medium, color: Brand.coin.withValues(alpha: context.isDark ? 0.18 : 0.14), iconColor: context.isDark ? Brand.coin : Brand.coinDeep),
              const SizedBox(width: 12),
              Expanded(child: Text('Card Jigsaw World VIP', style: TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.title3, letterSpacing: -0.3, color: fg))),
              if (isVip) const Chip2(label: 'Active', icon: AppIcons.checkmarkAlt),
            ],
          ),
          const SizedBox(height: 14),
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
                children: [
                  Icon(AppIcons.checkmarkCircleFill, color: context.accent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(line, style: TextStyle(color: fg, fontSize: TypeSize.footnote))),
                ],
              ),
            ),
          const SizedBox(height: 10),
          if (isVip)
            Text(
              vipUntil != null ? 'VIP is active until ${formatDate(vipUntil)}. Thank you for supporting the game.' : 'VIP is active. Thank you for supporting the game.',
              style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote),
            )
          else if (purchasable && w.unavailable)
            Row(
              children: [
                Icon(AppIcons.signal, size: 16, color: c.textSecondary),
                const SizedBox(width: 8),
                Expanded(child: Text('Plans and prices show here once the App Store answers.', style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote))),
              ],
            )
          else if (!purchasable)
            Row(
              children: [
                Chip2(label: 'Available on iPhone', icon: AppIcons.devicePhonePortrait, color: c.accentTint, foreground: context.accent),
                const SizedBox(width: 10),
                // No price on web: the App Store shows it on iPhone.
                Expanded(child: Text('Starts with a ${StoreProducts.vipTrialDays}-day free trial.', style: TextStyle(color: c.textSecondary, fontSize: TypeSize.caption))),
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
              onTap: () => setState(() => _yearly = true),
            ),
            const SizedBox(height: 8),
            _PlanRow(
              key: const ValueKey('vip-plan-monthly'),
              title: 'Monthly',
              price: w.monthlyPrice,
              period: '/ month',
              selected: !_yearly,
              onTap: () => setState(() => _yearly = false),
            ),
            const SizedBox(height: 14),
            BigButton(label: 'Start ${StoreProducts.vipTrialDays}-day free trial', loading: busy, onTap: _yearly ? w.onBuyYearly : w.onBuyMonthly),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '${StoreProducts.vipTrialDays} days free, then ${_yearly ? '${w.yearlyPrice} a year' : '${w.monthlyPrice} a month'}. Cancel anytime.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote),
              ),
            ),
          ],
          if (purchasable && !w.unavailable) ...[
            const SizedBox(height: 14),
            Center(
              child: Pressable(
                onTap: w.onRedeem,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.gift, size: 16, color: context.accent),
                      const SizedBox(width: 6),
                      Flexible(child: Text('Have a gift code? Redeem it', style: TextStyle(color: context.accent, fontSize: TypeSize.footnote, fontWeight: FontWeight.w600))),
                    ],
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

/// One VIP plan: a radio mark, the plan name (with its saving) and its price, large.
/// The selected plan is tinted and outlined in the accent.
class _PlanRow extends StatelessWidget {
  const _PlanRow({super.key, required this.title, required this.price, required this.period, this.badge, required this.selected, required this.onTap});
  final String title;
  final String price;
  final String period;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = context.accent;
    final fg = c.textPrimary;
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
            color: selected ? c.accentTint : c.card,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: selected ? accent : c.stroke, width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              Icon(selected ? AppIcons.checkmarkCircleFill : AppIcons.circle, size: 22, color: selected ? accent : c.textTertiary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: fg, fontSize: TypeSize.body, fontWeight: FontWeight.w600)),
                    if (badge != null) Text(badge!, style: TextStyle(color: accent, fontSize: TypeSize.caption, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: price, style: const TextStyle(fontSize: TypeSize.headline, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                  TextSpan(text: ' $period', style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary)),
                ]),
                style: TextStyle(color: fg),
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
  const _Product(this.id, {this.art = _Art.coin, this.badge});
  final String id;
  final _Art art;
  final String? badge;

  ProductGrant get grant => StoreProducts.grant(id);
  String get title => grant.label;
  String get price => StoreProducts.price(id);
}

final _coinProducts = [
  const _Product(ProductIds.coins1000, art: _Art.coin),
  const _Product(ProductIds.coins3000, art: _Art.coins, badge: 'Popular'),
  _Product(ProductIds.coins5500, art: _Art.coinsLarge, badge: '+${StoreProducts.coinBonusPercent(ProductIds.coins5500)}%'),
  const _Product(ProductIds.coins12000, art: _Art.coinsHuge, badge: 'Best value'),
];
const _ticketProducts = [
  _Product(ProductIds.tickets5, art: _Art.ticket),
  _Product(ProductIds.tickets15, art: _Art.tickets, badge: 'Popular'),
];
const _boosterProducts = [
  _Product(ProductIds.hints5, art: _Art.hints),
  _Product(ProductIds.hints15, art: _Art.hintsLarge, badge: 'Popular'),
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

/// Quiet reminder that every currency can be earned without paying: one caption under
/// the section title. It is information, not a button (it used to close the Store and
/// jump to another tab).
class _FreeNote extends StatelessWidget {
  const _FreeNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(AppIcons.dailyGift, size: 15, color: c.textTertiary)),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(fontSize: TypeSize.footnote, height: 1.35, color: c.textSecondary))),
        ],
      ),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.products, required this.onBuy, required this.priceOf, required this.rawPriceOf, this.busy = false, this.purchasable = true, this.unavailable = false});
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
  final bool busy;

  /// False on web: each tile shows "Available on iPhone" instead of its
  /// price, and a tap says where to buy it.
  final bool purchasable;

  /// No prices from the App Store: the rows stay as information, with no price.
  final bool unavailable;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // One grouped list per section, as in the App Store's in-app purchase list: art,
    // amount and what makes it special on the left, the price as a button on the right.
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SoftCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < products.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: c.stroke, indent: 16 + 72 + 12),
              _ProductRow(
                product: products[i],
                price: priceOf(products[i]),
                bonus: _bonus(products[i]),
                best: products.length > 1 && i == products.length - 1 && _bonus(products[i]) >= 3,
                purchasable: purchasable,
                unavailable: unavailable,
                onTap: !purchasable
                    ? () => showToast(context, purchasesOnIphoneMessage, icon: AppIcons.devicePhonePortrait)
                    : (busy ? null : () => onBuy(products[i])),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.price, required this.bonus, required this.best, required this.purchasable, this.unavailable = false, required this.onTap});
  final _Product product;
  final String price;
  final int bonus;
  final bool best;
  final bool purchasable;
  final bool unavailable;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = product;
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
        child: Row(
          children: [
            SizedBox(width: 72, height: 40, child: Align(alignment: Alignment.centerLeft, child: _ProductArt(art: p.art))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.callout, letterSpacing: -0.2)),
                  if (bonus >= 3) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text('+$bonus%', style: TextStyle(color: context.accent, fontWeight: FontWeight.w600, fontSize: TypeSize.footnote)),
                        Flexible(
                          child: Text(
                            ' more ${p.grant.coins > 0 ? 'coins' : p.grant.tickets > 0 ? 'tickets' : 'hints'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: context.accent, fontWeight: FontWeight.w600, fontSize: TypeSize.footnote),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (purchasable && unavailable)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: c.canvas, borderRadius: BorderRadius.circular(999), border: Border.all(color: c.stroke)),
                child: Text('Unavailable', maxLines: 1, style: TextStyle(color: c.textTertiary, fontWeight: FontWeight.w600, fontSize: TypeSize.footnote)),
              )
            else if (purchasable)
              Container(
                constraints: const BoxConstraints(minWidth: 76),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                alignment: Alignment.center,
                // The best deal of the section is the one filled price: the value speaks, no label needed.
                decoration: BoxDecoration(color: best ? context.accent : c.accentTint, borderRadius: BorderRadius.circular(999)),
                child: Text(price, style: TextStyle(color: best ? Colors.white : context.accent, fontWeight: FontWeight.w700, fontSize: TypeSize.body)),
              )
            else
              Icon(AppIcons.devicePhonePortrait, size: 18, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}
