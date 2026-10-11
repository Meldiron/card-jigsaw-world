import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../data/purchases.dart';
import '../../models/models.dart';
import '../../state/profile.dart';
import '../../state/purchases.dart';
import '../../state/settings.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../ads/house_ads.dart';

/// Store: free bonus video (capped per day), coin bundles, ticket bundles,
/// hint packs, VIP. Purchases go through StoreKit and are verified by the
/// `verify-purchase` Appwrite Function before anything is granted. In debug
/// builds without a store (plain simulator) a clearly labelled sandbox
/// dialog stands in so the flow can still be exercised.
class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key});
  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  bool _adBusy = false;
  bool _buying = false;
  StreamSubscription<PurchaseEvent>? _events;

  @override
  void initState() {
    super.initState();
    final service = ref.read(purchaseServiceProvider);
    service.start();
    _events = service.events.listen(_onPurchaseEvent);
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
        ref.read(profileProvider.notifier).refresh();
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
            if (g.coins > 0) '${_fmt(g.coins)} coins',
            if (g.tickets > 0) '${g.tickets} ticket${g.tickets == 1 ? '' : 's'}',
            if (g.hints > 0) '${g.hints} hint${g.hints == 1 ? '' : 's'}',
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

  static String _fmt(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
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
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Sandbox purchase (debug build)'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('$title for $price.\n\nNo store is available on this device. This debug-only checkout grants the item locally so the flow can be tested.'),
        ),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Buy')),
        ],
      ),
    );
    return ok == true && mounted;
  }

  bool get _storeAvailable => ref.read(storeAvailableProvider).value ?? false;

  Future<void> _buy(_Product p) async {
    if (_buying) return;
    final products = ref.read(productsProvider).value ?? const {};
    final details = products[p.id];
    if (_storeAvailable && details != null) {
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
    if (p.coins > 0) await n.addCoins(p.coins, reason: 'sandbox:${p.id}');
    if (p.tickets > 0) await n.addTickets(p.tickets, reason: 'sandbox:${p.id}');
    if (p.hints > 0) await n.addHints(p.hints, reason: 'sandbox:${p.id}');
    if (!mounted) return;
    Sfx.instance.coin();
    Haptics.success();
    showToast(context, 'Added ${p.title}', icon: AppIcons.check);
  }

  Future<void> _buyVip(String productId) async {
    if (_buying) return;
    final products = ref.read(productsProvider).value ?? const {};
    final details = products[productId];
    if (_storeAvailable && details != null) {
      setState(() => _buying = true);
      final started = await ref.read(purchaseServiceProvider).buy(details);
      if (!started && mounted) setState(() => _buying = false);
      return;
    }
    if (!kDebugMode) {
      showToast(context, 'The App Store is not available right now. Try again later.', icon: AppIcons.time);
      return;
    }
    if (!await _sandboxConfirm('Card Jigsaw VIP', productId == ProductIds.vipYearly ? '\$14.99 / year after a 7-day trial' : '\$2.99 / month after a 7-day trial')) return;
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
    final products = ref.watch(productsProvider).value ?? const <String, ProductDetails>{};
    final storeUp = ref.watch(storeAvailableProvider).value ?? false;
    final adsLeft = profile?.adsLeftToday ?? Profile.adsPerDay;
    final isVip = profile?.isVip ?? false;
    return Scaffold(
      appBar: AppBar(
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
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
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
                      Row(
                        children: [
                          Text('Free coins', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(width: 8),
                          Amount(currency: Currency.coins, value: Economy.adRewardCoins, prefix: '+', size: 15, fontSize: 13.5),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text('Watch a 15-second offer', style: TextStyle(color: c.textSecondary, fontSize: 13.5)),
                      const SizedBox(height: 2),
                      Text(adsLeft > 0 ? '$adsLeft of ${Profile.adsPerDay} left today' : 'All ${Profile.adsPerDay} used today', style: TextStyle(color: c.textTertiary, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                BigButton(
                  label: adsLeft > 0 ? 'Watch' : 'Back tomorrow',
                  height: 40,
                  expand: false,
                  onTap: _adBusy || adsLeft <= 0 ? null : _watchAd,
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'Coins', subtitle: 'Unlock packs and boosters', padding: EdgeInsets.fromLTRB(0, 24, 0, 12)),
          _FreeNote(text: 'Free coins: daily goals, the daily gift, level-ups, the piggy bank and the Lucky Wheel.', route: '/events'),
          _ProductGrid(products: _coinProducts, onBuy: _buy, priceOf: (p) => _price(p, products), busy: _buying),
          const SectionHeader(title: 'Tickets', subtitle: 'Premium packs and the piggy bank', padding: EdgeInsets.fromLTRB(0, 24, 0, 12)),
          _FreeNote(text: 'Free tickets: weekly goals, world-day events and every third level.', route: '/events'),
          _ProductGrid(products: _ticketProducts, onBuy: _buy, priceOf: (p) => _price(p, products), busy: _buying),
          const SectionHeader(title: 'Hints', subtitle: 'Show a card its place', padding: EdgeInsets.fromLTRB(0, 24, 0, 12)),
          _FreeNote(text: 'Free hints: the daily gift on even days, every second level and the Lucky Wheel.', route: '/home'),
          _ProductGrid(products: _boosterProducts, onBuy: _buy, priceOf: (p) => _price(p, products), busy: _buying),
          const SizedBox(height: 24),
          _VipCard(
            isVip: isVip,
            vipUntil: profile?.vipExpiresAt,
            monthlyPrice: products[ProductIds.vipMonthly]?.price ?? '\$2.99',
            yearlyPrice: products[ProductIds.vipYearly]?.price ?? '\$14.99',
            busy: _buying,
            onBuyMonthly: () => _buyVip(ProductIds.vipMonthly),
            onBuyYearly: () => _buyVip(ProductIds.vipYearly),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              storeUp
                  ? 'Payment is handled by the App Store. Subscriptions renew automatically and can be cancelled in your Apple ID settings.'
                  : (kDebugMode ? 'Store unavailable on this device. Debug sandbox purchases grant items locally.' : 'The App Store is not available right now.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: c.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _VipCard extends StatelessWidget {
  const _VipCard({
    required this.isVip,
    required this.vipUntil,
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.busy,
    required this.onBuyMonthly,
    required this.onBuyYearly,
  });
  final bool isVip;
  final DateTime? vipUntil;
  final String monthlyPrice;
  final String yearlyPrice;
  final bool busy;
  final VoidCallback onBuyMonthly;
  final VoidCallback onBuyYearly;

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
              const Expanded(child: Text('Card Jigsaw VIP', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19, letterSpacing: -0.3, color: fg))),
              if (isVip) const Chip2(label: 'Active', icon: CupertinoIcons.checkmark_alt, color: Color(0x22FFFFFF), foreground: fg),
            ],
          ),
          const SizedBox(height: 14),
          for (final line in const [
            'Every pack and every past monthly pack unlocked',
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
          else ...[
            BigButton(label: 'Start 7-day free trial', kind: ButtonKind.gold, loading: busy, onTap: onBuyMonthly),
            const SizedBox(height: 6),
            Text('7 days free, then $monthlyPrice/month', style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 12)),
            const SizedBox(height: 10),
            BigButton(label: 'Yearly · $yearlyPrice · 7 days free', kind: ButtonKind.ghost, loading: busy, onTap: onBuyYearly),
          ],
        ],
      ),
    );
  }
}

enum _Art { coin, coins, coinsLarge, coinsHuge, ticket, tickets, hints, hintsLarge }

class _Product {
  const _Product(this.id, this.title, this.price, {this.coins = 0, this.tickets = 0, this.hints = 0, this.art = _Art.coin, this.badge});
  final String id;
  final String title;
  final String price;
  final int coins;
  final int tickets;
  final int hints;
  final _Art art;
  final String? badge;
}

const _coinProducts = [
  _Product(ProductIds.coins1000, '1,000 coins', '\$0.99', coins: 1000, art: _Art.coin),
  _Product(ProductIds.coins3000, '3,000 coins', '\$2.99', coins: 3000, art: _Art.coins, badge: 'Popular'),
  _Product(ProductIds.coins5500, '5,500 coins', '\$4.99', coins: 5500, art: _Art.coinsLarge, badge: '+10%'),
  _Product(ProductIds.coins12000, '12,000 coins', '\$9.99', coins: 12000, art: _Art.coinsHuge, badge: 'Best value'),
];
const _ticketProducts = [
  _Product(ProductIds.tickets5, '5 tickets', '\$1.99', tickets: 5, art: _Art.ticket),
  _Product(ProductIds.tickets15, '15 tickets', '\$4.99', tickets: 15, art: _Art.tickets, badge: 'Popular'),
];
const _boosterProducts = [
  _Product(ProductIds.hints5, '5 hints', '\$0.99', hints: 5, art: _Art.hints),
  _Product(ProductIds.hints15, '15 hints', '\$2.49', hints: 15, art: _Art.hintsLarge, badge: 'Popular'),
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
  const _ProductGrid({required this.products, required this.onBuy, required this.priceOf, this.busy = false});
  final List<_Product> products;
  final void Function(_Product) onBuy;
  final String Function(_Product) priceOf;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.08),
      itemCount: products.length,
      itemBuilder: (_, i) {
        final p = products[i];
        return Pressable(
          onTap: busy ? null : () => onBuy(p),
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: c.accentTint, borderRadius: BorderRadius.circular(999)),
                      child: Text(priceOf(p), style: TextStyle(color: context.accent, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
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
