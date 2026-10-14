import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
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
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic, alignment: 0.1);
      });
    }
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
          showToast(context, 'VIP active until ${_date(g.vipExpiresAt!)}', icon: AppIcons.vip);
        } else {
          Sfx.instance.coin();
          Haptics.success();
          final parts = [
            if (g.coins > 0) '${groupThousands(g.coins)} coins',
            if (g.tickets > 0) '${groupThousands(g.tickets)} ticket${g.tickets == 1 ? '' : 's'}',
            if (g.hints > 0) '${groupThousands(g.hints)} hint${g.hints == 1 ? '' : 's'}',
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

  static String _date(DateTime d) => '${d.day}.${d.month}.${d.year}';

  Future<void> _watchAd() async {
    if (_adBusy) return;
    // The allowance is persisted on the profile, so blocking the ad network
    // does not reset it.
    final wait = HouseAdPolicy.rewardedWaitLeft(ref.read(localStoreProvider).lastRewardedAt);
    if (wait > Duration.zero) {
      showToast(context, 'Next offer in ${wait.inMinutes + 1} min.', icon: AppIcons.time);
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
    showToast(context, 'Added ${Economy.adRewardCoins} coins', leading: const CoinIcon(size: 20));
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
      showToast(context, 'Gift codes can be redeemed on iPhone and iPad through the App Store.', icon: CupertinoIcons.gift);
      return;
    }
    final opened = await ref.read(purchaseServiceProvider).presentCodeRedemptionSheet();
    if (!opened && mounted) {
      showToast(context, 'Gift codes can be redeemed on iPhone and iPad through the App Store.', icon: CupertinoIcons.gift);
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

  /// Store price when the product loaded, else the placeholder.
  String _price(_Product p, Map<String, ProductDetails> products) => products[p.id]?.price ?? p.price;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final profile = ref.watch(profileProvider).value;
    final caps = ref.watch(platformCapsProvider);
    final products = caps.purchases ? (ref.watch(productsProvider).value ?? const <String, ProductDetails>{}) : const <String, ProductDetails>{};
    final storeUp = caps.purchases && (ref.watch(storeAvailableProvider).value ?? false);
    final adsLeft = profile?.adsLeftToday ?? Profile.adsPerDay;
    final isVip = profile?.isVip ?? false;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('Store'),
        leading: Padding(padding: const EdgeInsets.only(left: 12), child: RoundIconButton(icon: CupertinoIcons.xmark, size: 38, onTap: () => context.pop())),
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
          // Free coins via bonus video, limited per day.
          SoftCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Free coins', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 3),
                      Text('Watch a 15-second offer', style: TextStyle(color: c.textSecondary, fontSize: 13.5)),
                      const SizedBox(height: 2),
                      Text(adsLeft > 0 ? '$adsLeft of ${Profile.adsPerDay} left today' : 'All ${Profile.adsPerDay} used today', style: TextStyle(color: c.textTertiary, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (adsLeft > 0)
                  BigButton.cost(label: 'Watch', currency: Currency.coins, amount: Economy.adRewardCoins, amountPrefix: '+', height: 40, expand: false, onTap: _adBusy ? null : _watchAd)
                else
                  const BigButton(label: 'Back tomorrow', height: 40, expand: false),
              ],
            ),
          ),
          const SectionHeader(title: 'Coins', subtitle: 'Unlock packs and boosters', padding: EdgeInsets.fromLTRB(0, 24, 0, 12)),
          _FreeNote(text: 'Free coins: daily quests, the daily gift, level-ups, the piggy bank (${Economy.piggyPerPuzzle} per picture, up to ${Profile.piggyCapacity}) and the Lucky Wheel.', route: '/events'),
          _ProductGrid(products: _coinProducts, onBuy: _buy, priceOf: (p) => _price(p, products), busy: _buying, purchasable: caps.purchases),
          const SectionHeader(title: 'Tickets', subtitle: 'Premium packs and the piggy bank', padding: EdgeInsets.fromLTRB(0, 24, 0, 12)),
          _FreeNote(text: 'Free tickets: the daily gift, weekly quests, world-day events and every third level.', route: '/events'),
          _ProductGrid(products: _ticketProducts, onBuy: _buy, priceOf: (p) => _price(p, products), busy: _buying, purchasable: caps.purchases),
          const SectionHeader(title: 'Hints', subtitle: 'Show a card its place', padding: EdgeInsets.fromLTRB(0, 24, 0, 12)),
          _FreeNote(text: 'Free hints: the daily gift on even days, every second level and the Lucky Wheel.', route: '/home'),
          _ProductGrid(products: _boosterProducts, onBuy: _buy, priceOf: (p) => _price(p, products), busy: _buying, purchasable: caps.purchases),
          const SizedBox(height: 24),
          _VipCard(
            key: _vipKey,
            isVip: isVip,
            vipUntil: profile?.vipExpiresAt,
            monthlyPrice: products[ProductIds.vipMonthly]?.price ?? StoreProducts.price(ProductIds.vipMonthly),
            yearlyPrice: products[ProductIds.vipYearly]?.price ?? StoreProducts.price(ProductIds.vipYearly),
            busy: _buying,
            purchasable: caps.purchases,
            onBuyMonthly: () => _buyVip(ProductIds.vipMonthly),
            onBuyYearly: () => _buyVip(ProductIds.vipYearly),
            onRedeem: _redeemCode,
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              !caps.purchases
                  ? 'VIP and bundles are sold in the iPhone app. A VIP subscription bought there is active here too.'
                  : storeUp
                      ? 'Payment is charged to your Apple ID when you confirm, or when the free trial ends. VIP renews automatically unless cancelled at least 24 hours before the period ends; manage it in your App Store account settings.'
                      : (kDebugMode ? 'Store unavailable on this device. Debug sandbox purchases grant items locally.' : 'The App Store is not available right now.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: c.textTertiary),
            ),
          ),
          // Apple asks for both links where a subscription is sold (guideline 3.1.2).
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _FooterLink(key: const ValueKey('store-terms'), label: 'Terms of use', url: AppLinks.termsOfUse),
              Text('·', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
              _FooterLink(key: const ValueKey('store-privacy'), label: 'Privacy policy', url: AppLinks.privacyPolicy),
            ],
          ),
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
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.accent)),
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
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconTile(icon: CupertinoIcons.device_phone_portrait, size: 34, radius: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Web version', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(message, style: TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VipCard extends StatelessWidget {
  const _VipCard({
    super.key,
    required this.isVip,
    required this.vipUntil,
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.busy,
    this.purchasable = true,
    required this.onBuyMonthly,
    required this.onBuyYearly,
    required this.onRedeem,
  });
  final bool isVip;
  final DateTime? vipUntil;
  final String monthlyPrice;
  final String yearlyPrice;
  final bool busy;
  /// False on web: the benefits stay as information, the buy buttons, the
  /// prices and the gift-code link are replaced by an "Available on iPhone"
  /// label.
  final bool purchasable;
  final VoidCallback onBuyMonthly;
  final VoidCallback onBuyYearly;
  final VoidCallback onRedeem;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = context.isDark ? c.cardElevated : c.textPrimary;
    const fg = Colors.white;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.lg), border: Border.all(color: context.isDark ? c.stroke : Colors.transparent)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                child: const Icon(AppIcons.vip, color: Brand.coin, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text('Card Jigsaw World VIP', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19, letterSpacing: -0.3, color: fg))),
              if (isVip) const Chip2(label: 'Active', icon: CupertinoIcons.checkmark_alt, color: Color(0x22FFFFFF), foreground: fg),
            ],
          ),
          const SizedBox(height: 14),
          for (final line in const [
            'Every pack and every past monthly pack unlocked',
            'A 4th daily quest and a 6th weekly quest',
            'No bonus videos, ever',
            'Unlimited My Puzzles uploads',
            '+500 coins every week',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(CupertinoIcons.checkmark_circle_fill, color: Brand.coin, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(line, style: TextStyle(color: fg.withValues(alpha: 0.9), fontSize: 13.5))),
                ],
              ),
            ),
          const SizedBox(height: 10),
          if (isVip)
            Text(
              vipUntil != null ? 'VIP is active until ${vipUntil!.day}.${vipUntil!.month}.${vipUntil!.year}. Thank you for supporting the game.' : 'VIP is active. Thank you for supporting the game.',
              style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 13),
            )
          else if (!purchasable)
            Row(
              children: [
                const Chip2(label: 'Available on iPhone', icon: CupertinoIcons.device_phone_portrait, color: Color(0x22FFFFFF), foreground: fg),
                const SizedBox(width: 10),
                // No price on web: the App Store shows it on iPhone.
                Expanded(child: Text('Starts with a ${StoreProducts.vipTrialDays}-day free trial.', style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 12))),
              ],
            )
          else ...[
            BigButton(label: 'Start ${StoreProducts.vipTrialDays}-day free trial', kind: ButtonKind.gold, loading: busy, onTap: onBuyMonthly),
            const SizedBox(height: 6),
            Text(StoreProducts.vipTrialLine(monthlyPrice), style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 12)),
            const SizedBox(height: 10),
            BigButton(label: 'Yearly · $yearlyPrice · ${StoreProducts.vipTrialDays} days free', kind: ButtonKind.ghostLight, loading: busy, onTap: onBuyYearly),
          ],
          if (purchasable) ...[
            const SizedBox(height: 14),
            Center(
              child: Pressable(
                onTap: onRedeem,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.gift, size: 16, color: fg.withValues(alpha: 0.75)),
                      const SizedBox(width: 6),
                      Flexible(child: Text('Have a gift code? Redeem it', style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w600))),
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
      _Art.hints => stack((s) => HintIcon(size: s), 2, 32),
      _Art.hintsLarge => stack((s) => HintIcon(size: s), 4, 28),
    };
  }
}

/// Quiet reminder that every currency can be earned without paying.
class _FreeNote extends StatelessWidget {
  const _FreeNote({required this.text, required this.route});
  final String text;
  final String route;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SoftCard(
        padding: const EdgeInsets.all(12),
        onTap: () {
          context.pop();
          context.go(route);
        },
        child: Row(
          children: [
            const IconTile(icon: AppIcons.dailyGift, size: 30, radius: 9),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(fontSize: 13, height: 1.35, color: c.textSecondary))),
            const SizedBox(width: 6),
            Icon(CupertinoIcons.chevron_right, size: 15, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.products, required this.onBuy, required this.priceOf, this.busy = false, this.purchasable = true});
  final List<_Product> products;
  final void Function(_Product) onBuy;
  final String Function(_Product) priceOf;
  final bool busy;

  /// False on web: each tile shows "Available on iPhone" instead of its
  /// price, and a tap says where to buy it.
  final bool purchasable;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GridView.builder(
      shrinkWrap: true,
      // A nested scroll view inherits the status-bar and home-indicator
      // insets as padding unless told otherwise; that was the empty band
      // under each free-currency note.
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.08),
      itemCount: products.length,
      itemBuilder: (_, i) {
        final p = products[i];
        return Pressable(
          onTap: !purchasable
              ? () => showToast(context, purchasesOnIphoneMessage, icon: CupertinoIcons.device_phone_portrait)
              : (busy ? null : () => onBuy(p)),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(Radii.lg), border: Border.all(color: c.stroke)),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProductArt(art: p.art),
                    const Spacer(),
                    Text(p.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 6),
                    if (purchasable)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: c.accentTint, borderRadius: BorderRadius.circular(999)),
                        child: Text(priceOf(p), style: TextStyle(color: context.accent, fontWeight: FontWeight.w700, fontSize: 13)),
                      )
                    else
                      Chip2(label: 'Available on iPhone', icon: CupertinoIcons.device_phone_portrait, color: c.accentTint, foreground: context.accent),
                  ],
                ),
                if (p.badge != null)
                  Positioned(right: 0, top: 0, child: Chip2(label: p.badge!, color: c.accentTint, foreground: context.accent)),
              ],
            ),
          ),
        );
      },
    );
  }
}
