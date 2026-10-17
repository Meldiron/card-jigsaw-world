import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/platform.dart';
import '../../core/sfx.dart';
import '../../core/a11y.dart';
import '../../core/theme/tokens.dart';
import '../../data/purchases.dart';
import '../../models/models.dart';
import '../../state/first_steps.dart';
import '../../state/catalog.dart';
import '../../state/profile.dart';
import '../../state/purchases.dart';
import '../../state/settings.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../../widgets/vip.dart';

/// House ads: we run no ad network, so every "ad" slot promotes something the
/// player can buy in the app (VIP, coins, tickets, hints) or a free feature
/// that leads there. Two formats:
///
/// * Rewarded: a timed full-screen card. The reward is granted only after the
///   full countdown, never by tapping the offer early. Capped per day on the
///   profile so blocking requests does not reset it.
/// * Interstitial ("break"): shown after a completed puzzle, closable after a
///   short delay, frequency-capped and never shown to VIP members.
class HouseAdPolicy {
  HouseAdPolicy._();

  /// Rewarded card length. 15 s mirrors the shortest rewarded video length
  /// networks allow; long enough to read, short enough not to annoy.
  static const rewardedDuration = Duration(seconds: 15);

  /// Interstitial close button appears after this delay (industry norm 3–5 s).
  static const interstitialCloseDelay = Duration(seconds: 5);

  /// Interstitial cadence (Gamigion / AdReact norms, tuned down because a
  /// self-promo earns nothing per impression): every Nth completion AND at
  /// least [minGap] apart, at most [maxPerSession] per app session, never in
  /// the first few puzzles of a player's life, and not within
  /// [rewardedShield] of a rewarded view.
  static const everyNthCompletion = 3;
  static const minGap = Duration(minutes: 3);
  static const maxPerSession = 1000;
  static const skipFirstCompletions = 3;
  static const rewardedShield = Duration(minutes: 10);

  /// Cooldown between rewarded views (daily cap lives on the profile).
  static const rewardedCooldown = Duration(minutes: 10);

  static int interstitialsThisSession = 0;

  static Duration rewardedWaitLeft(DateTime? lastRewardedAt) {
    if (lastRewardedAt == null) return Duration.zero;
    final left = rewardedCooldown - DateTime.now().difference(lastRewardedAt);
    return left.isNegative ? Duration.zero : left;
  }
}

/// What a creative sells. The route or action runs when the CTA is tapped.
enum CreativeKind { vip, coins, tickets, hints, piggy, monthly, event }

class Creative {
  const Creative({
    required this.id,
    required this.kind,
    required this.headline,
    required this.body,
    required this.cta,
    required this.route,
    this.price,
    this.productId,
  });
  final String id;
  final CreativeKind kind;
  final String headline;
  final String body;
  final String cta;
  final String route;
  final String? price;

  /// The App Store product the [price] line is about, when it names money.
  final String? productId;

  /// The price line to show: the App Store's own price for [productId] (in the
  /// player's currency), never the US placeholder; null while the App Store has
  /// not given it. Creatives without a product keep their free text ("7 days free").
  String? priceLine(Map<String, String> appStorePrices) {
    if (productId == null) return price;
    final local = appStorePrices[productId];
    if (local == null) return null;
    return kind == CreativeKind.vip ? StoreProducts.vipTrialLine(local) : local;
  }

  /// The CTA opens the store to buy something. On web, where nothing can be
  /// bought, these CTAs show the "available on iPhone" toast instead.
  bool get sellsPurchase => route == '/store';
}

/// Runs a creative's CTA: opens its route, or on web, when it leads to a
/// purchase, shows the "available on iPhone" toast. Returns true when the
/// route was opened.
bool openCreative(BuildContext context, WidgetRef ref, Creative creative) {
  if (creative.sellsPurchase && !ref.read(platformCapsProvider).purchases) {
    showToast(context, purchasesOnIphoneMessage, icon: AppIcons.devicePhonePortrait);
    return false;
  }
  context.push(creative.route);
  return true;
}

const _tabRoots = {'/home', '/library', '/events', '/social', '/profile'};

/// Opens [creative]'s destination from inside a game: the game and its menus
/// close and the player lands on the offer itself (a tab, or the store on top
/// of Home). Returns false when the offer cannot open here (purchases on the
/// web), so the caller carries on as if no button had been tapped.
bool leaveGameForCreative(BuildContext context, WidgetRef ref, Creative creative) {
  if (creative.sellsPurchase && !ref.read(platformCapsProvider).purchases) {
    showToast(context, purchasesOnIphoneMessage, icon: AppIcons.devicePhonePortrait);
    return false;
  }
  final router = GoRouter.of(context);
  final route = creative.route;
  final path = Uri.parse(route).path;
  if (_tabRoots.contains(path)) {
    router.go(route);
  } else {
    router.go('/home');
    WidgetsBinding.instance.addPostFrameCallback((_) => router.push(route));
  }
  return true;
}

/// Monthly daily packs released so far: one per month since January 2023 (46 in October 2026).
int _dailyMonthsSoFar([DateTime? now]) {
  final t = now ?? DateTime.now();
  return (t.year - 2023) * 12 + t.month;
}

/// Every amount and price in the copy comes from the store catalogue
/// ([StoreProducts]), the pack price policy and [Economy], so a change to a
/// bundle or a price cannot leave an ad promising the old numbers.
final houseCreatives = <Creative>[
  Creative(id: 'vip-all', kind: CreativeKind.vip, headline: 'Every pack. No breaks.', body: 'VIP opens every pack and every past month, and removes these cards.', cta: 'Start free trial', route: '/store', price: StoreProducts.vipTrialLine(), productId: ProductIds.vipMonthly),
  Creative(id: 'vip-months', kind: CreativeKind.vip, headline: 'Three years of daily puzzles', body: 'All ${_dailyMonthsSoFar()} monthly albums are included with VIP.', cta: 'Go VIP', route: '/store', price: '${StoreProducts.vipTrialDays} days free'),
  _coinsCreative('coins-3000', ProductIds.coins3000, headline: 'Running low on coins?', body: (n) {
    final packs = n ~/ PackPricePolicy.standardPackCoins;
    return '${formatCount(n)} coins unlock up to ${_count(packs)} packs or ${n ~/ Economy.magicLockCostCoins} Magic Locks.';
  }),
  _coinsCreative('coins-1000', ProductIds.coins1000, headline: 'One more pack', body: (n) => '${formatCount(n)} coins unlock a standard 24-picture pack.'),
  Creative(
    id: 'tickets-5',
    kind: CreativeKind.tickets,
    headline: 'Tickets open premium packs',
    body: '${_tickets.label} open most premium packs, or give ${_count(_tickets.tickets ~/ Economy.wheelSpinTickets)} Lucky Wheel spins.',
    cta: 'Get ${_tickets.label}',
    route: '/store',
    price: StoreProducts.price(ProductIds.tickets5),
    productId: ProductIds.tickets5,
  ),
  // The bigger booster bundle (16 or 48 hints until 2026-10-17; now Peek, Hint and Magic).
  Creative(
    id: 'hints-15',
    kind: CreativeKind.hints,
    headline: 'Stuck on a card?',
    body: '${countOf(_hints.peeks, 'Peek')}, ${countOf(_hints.hints, 'Hint')} and ${formatCount(_hints.magics)} Magic: see the picture, find a card’s place, or put it there.',
    cta: 'Get boosters',
    route: '/store',
    price: StoreProducts.price(ProductIds.hints15),
    productId: ProductIds.hints15,
  ),
  piggyCreative(Profile.basePiggyCapacity),
  Creative(id: 'monthly', kind: CreativeKind.monthly, headline: 'One new picture every day', body: 'This month’s album is free. Past months come with VIP.', cta: 'Open this month', route: '/library'),
  Creative(id: 'events', kind: CreativeKind.event, headline: 'A new world-day event every week', body: 'Themed packs that open for seven days. Finish every picture for a ticket.', cta: 'See events', route: '/events'),
];

/// The piggy bank card for a piggy bank that holds [capacity] coins (the player's own size when it
/// is picked, see [pickCreative]).
Creative piggyCreative(int capacity) => Creative(
      id: 'piggy',
      kind: CreativeKind.piggy,
      headline: 'Your piggy bank is filling up',
      body: 'Every finished puzzle adds ${countOf(Economy.piggyPerPuzzle, 'coin')}, up to ${formatCount(capacity)}. Open it with one ticket.',
      cta: 'See piggy bank',
      route: '/home',
    );

ProductGrant get _tickets => StoreProducts.grant(ProductIds.tickets5);
ProductGrant get _hints => StoreProducts.grant(ProductIds.hints15);

Creative _coinsCreative(String id, String productId, {required String headline, required String Function(int coins) body}) {
  final grant = StoreProducts.grant(productId);
  return Creative(id: id, kind: CreativeKind.coins, headline: headline, body: body(grant.coins), cta: 'Get ${grant.label}', route: '/store', price: StoreProducts.price(productId), productId: productId);
}

/// Small counts in words ("three packs"), larger ones as digits.
String _count(int n) => const ['no', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten'].elementAtOrNull(n) ?? formatCount(n);

/// Picks a creative for the player's state; never repeats the last one.
Creative pickCreative(WidgetRef ref) {
  final store = ref.read(localStoreProvider);
  final p = ref.read(profileProvider).value;
  final pool = <Creative>[];
  if (p != null) {
    if (p.coins < 200) pool.addAll(houseCreatives.where((c) => c.kind == CreativeKind.coins));
    if (p.hints == 0) pool.addAll(houseCreatives.where((c) => c.kind == CreativeKind.hints));
    if (p.tickets == 0) pool.addAll(houseCreatives.where((c) => c.kind == CreativeKind.tickets));
    if (p.puzzlesCompleted >= 10 && !p.isVip) pool.addAll(houseCreatives.where((c) => c.kind == CreativeKind.vip));
    if (p.piggyCoins >= p.piggyCapacity * 0.6) pool.addAll(houseCreatives.where((c) => c.kind == CreativeKind.piggy));
  }
  if (pool.isEmpty) pool.addAll(houseCreatives.where((c) => !(p?.isVip ?? false) || c.kind != CreativeKind.vip));
  final candidates = pool.where((c) => c.id != store.lastCreativeId).toList();
  final list = candidates.isEmpty ? pool : candidates;
  final pick = list[Random().nextInt(list.length)];
  store.lastCreativeId = pick.id;
  // The piggy bank card names the player's own size (upgrades make it hold more than 500).
  return pick.kind == CreativeKind.piggy && p != null ? piggyCreative(p.piggyCapacity) : pick;
}

/// A cover image for the creative: event/monthly/VIP use real pack covers.
({String url, String? hash})? pickCover(WidgetRef ref, Creative c) {
  final packs = ref.read(packsProvider).value ?? const <Pack>[];
  if (packs.isEmpty) return null;
  List<Pack> src = switch (c.kind) {
    CreativeKind.event => packs.where((p) => p.hasWindow && p.isLive).toList(),
    CreativeKind.monthly => packs.where((p) => p.isCurrentMonth).toList(),
    _ => packs.where((p) => !p.isDaily && !p.hasWindow).toList(),
  };
  if (src.isEmpty) src = packs;
  final p = src[Random().nextInt(src.length)];
  return (url: p.coverUrl, hash: p.blurhash);
}

/// Records a completion and shows an interstitial when the cadence allows.
/// Returns after the ad is closed (or immediately when none is shown). When
/// the player tapped the offer, returns its creative: the caller should leave
/// the game for it ([leaveGameForCreative]) instead of moving on.
Future<Creative?> maybeShowInterstitial(BuildContext context, WidgetRef ref) async {
  final store = ref.read(localStoreProvider);
  final profile = ref.read(profileProvider).value;
  store.lifetimeCompletions = store.lifetimeCompletions + 1;
  store.completionsSinceAd = store.completionsSinceAd + 1;
  if (profile?.isVip == true) return null;
  if (store.lifetimeCompletions <= HouseAdPolicy.skipFirstCompletions) return null;
  // The guided start keeps offers back until level 5 (lib/state/first_steps.dart); nothing piles
  // up meanwhile.
  if (!ref.read(revealsProvider).contains(Reveal.promos)) {
    store.completionsSinceAd = 0;
    return null;
  }
  if (HouseAdPolicy.interstitialsThisSession >= HouseAdPolicy.maxPerSession) return null;
  // A break follows every Nth completion, or the current one when the last
  // break is more than [minGap] ago (first completion of a session counts).
  final last = store.lastInterstitialAt;
  final gapElapsed = last == null || DateTime.now().difference(last) >= HouseAdPolicy.minGap;
  if (store.completionsSinceAd < HouseAdPolicy.everyNthCompletion && !gapElapsed) return null;
  final rewarded = store.lastRewardedAt;
  if (rewarded != null && DateTime.now().difference(rewarded) < HouseAdPolicy.rewardedShield) return null;
  store.completionsSinceAd = 0;
  store.lastInterstitialAt = DateTime.now();
  HouseAdPolicy.interstitialsThisSession++;
  final creative = pickCreative(ref);
  final cover = pickCover(ref, creative);
  if (!context.mounted) return null;
  final result = await Navigator.of(context, rootNavigator: true).push<Object?>(
    PageRouteBuilder(
      opaque: true,
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => HouseAdScreen(creative: creative, coverUrl: cover, rewarded: false),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
  );
  return result == _ctaTapped ? creative : null;
}

/// Pop result of an interstitial whose offer button was tapped.
const _ctaTapped = 'cta';

/// Shows the rewarded card. Returns true when the reward was earned.
Future<bool> showRewardedHouseAd(BuildContext context, WidgetRef ref, {required int rewardCoins}) async {
  final creative = pickCreative(ref);
  final cover = pickCover(ref, creative);
  final result = await Navigator.of(context, rootNavigator: true).push<bool>(
    PageRouteBuilder(
      opaque: true,
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => HouseAdScreen(creative: creative, coverUrl: cover, rewarded: true, rewardCoins: rewardCoins),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
  );
  if (result == true) ref.read(localStoreProvider).lastRewardedAt = DateTime.now();
  return result == true;
}

/// Full-screen house ad. Image-first with a scrim, the offer at the bottom,
/// and a countdown chip top-right that turns into the close button.
class HouseAdScreen extends ConsumerStatefulWidget {
  const HouseAdScreen({super.key, required this.creative, required this.coverUrl, required this.rewarded, this.rewardCoins = 0});
  final Creative creative;
  final ({String url, String? hash})? coverUrl;
  final bool rewarded;
  final int rewardCoins;

  @override
  ConsumerState<HouseAdScreen> createState() => _HouseAdScreenState();
}

class _HouseAdScreenState extends ConsumerState<HouseAdScreen> {
  late final int _total = (widget.rewarded ? HouseAdPolicy.rewardedDuration : HouseAdPolicy.interstitialCloseDelay).inSeconds;
  late int _left = _total;
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _left = max(0, _left - 1);
        if (_left == 0) {
          _done = true;
          _timer?.cancel();
          if (widget.rewarded) {
            Sfx.instance.coin();
            Haptics.success();
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _close() async {
    if (widget.rewarded && !_done) {
      // The countdown keeps running underneath. Leaving early never pays:
      // the card closes with no reward even if the timer ran out while the
      // alert was open.
      final leave = await showAppAlert(
        context,
        title: 'Close and lose the reward?',
        message: '${_left}s left to earn ${countOf(widget.rewardCoins, 'coin')}.',
        cancelLabel: 'Keep watching',
        confirmLabel: 'Close',
        destructive: true,
      );
      if (!leave || !mounted) return;
      Navigator.of(context).pop(false);
      return;
    }
    Navigator.of(context).pop(widget.rewarded ? _done : null);
  }

  void _cta() {
    if (widget.rewarded && !_done) {
      // Opening the offer early must not short-circuit the reward: the store
      // opens on top while this card and its timer stay underneath, and the
      // coins are only collectable once the countdown has finished.
      openCreative(context, ref, widget.creative);
      return;
    }
    if (widget.rewarded) {
      Navigator.of(context).pop(true);
      openCreative(context, ref, widget.creative);
      return;
    }
    // An ad break between puzzles: the game decides where to go (it leaves the
    // puzzle for the offer instead of moving on to the next one).
    Navigator.of(context).pop(_ctaTapped);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.creative;
    final progress = 1 - _left / _total;
    final inset = pageInsetOf(context);
    final priceLine = ref.watch(platformCapsProvider).purchases ? c.priceLine(_appStorePrices(ref)) : null;
    // Light status bar: the card is dark (scrim or ground) whatever the app theme.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.coverUrl != null) NetImage(url: widget.coverUrl!.url, blurhash: widget.coverUrl!.hash) else Container(color: const Color(0xFF17171C)),
            // A scrim that is light at the top (the chips) and nearly solid under the
            // copy, whatever the picture: a white church or a beach must not wash it out.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.2, 0.38, 0.55, 0.7, 1],
                  colors: [
                    Colors.black.withValues(alpha: 0.4),
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.12),
                    Colors.black.withValues(alpha: 0.62),
                    Colors.black.withValues(alpha: 0.82),
                    Colors.black.withValues(alpha: 0.94),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(16 + inset, 8, 16 + inset, 0),
                    child: Row(
                      children: [
                        const Chip2(label: 'Offer', onImage: true),
                        const Spacer(),
                        _CountdownChip(
                          left: _left,
                          progress: progress,
                          done: _done,
                          label: widget.rewarded ? (_done ? 'Reward ready' : 'Reward in ${_left}s') : (_done ? 'Close' : 'Skip in ${_left}s'),
                          onClose: _close,
                        ),
                      ],
                    ),
                  ),
                  // The copy sits at the bottom and scrolls when a large text size makes it taller
                  // than the space under the chips.
                  Expanded(
                    child: SingleChildScrollView(
                      reverse: true,
                      physics: const ClampingScrollPhysics(),
                      child: Padding(
                    padding: EdgeInsets.fromLTRB(24 + inset, 0, 24 + inset, 16),
                    child: ConstrainedBox(
                    // On a wide window the copy and its buttons keep a phone's measure.
                    constraints: const BoxConstraints(maxWidth: PageWidth.sheet),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _KindBadge(kind: c.kind),
                        const SizedBox(height: 14),
                        Text(c.headline, style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white, shadows: _textShadow)).animate().fadeIn(delay: 150.ms).slideY(begin: A11y.reduceMotionOf(context) ? 0 : 0.1),
                        const SizedBox(height: 8),
                        Text(c.body, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: TypeSize.callout, height: 1.4, shadows: _textShadow)).animate().fadeIn(delay: 250.ms),
                        // No prices on web, where nothing can be bought, and only the App Store's own.
                        if (priceLine != null) ...[
                          const SizedBox(height: 8),
                          Text(priceLine, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: TypeSize.footnote, fontWeight: FontWeight.w600)),
                        ],
                        const SizedBox(height: 20),
                        _OfferButton(label: c.cta, onTap: _cta),
                        if (widget.rewarded) ...[
                          const SizedBox(height: 10),
                          _CollectButton(coins: widget.rewardCoins, left: _left, progress: progress, done: _done, onTap: () => Navigator.of(context).pop(true)),
                        ] else ...[
                          const SizedBox(height: 10),
                          // The countdown lives in the chip at the top; this link appears when it ends.
                          Center(
                            child: AnimatedOpacity(
                              opacity: _done ? 1 : 0,
                              duration: const Duration(milliseconds: 250),
                              child: Pressable(
                                onTap: _done ? _close : null,
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text('No thanks', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    ),
                  ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A soft shadow that keeps white copy apart from a busy picture.
const _textShadow = [Shadow(color: Color(0x66000000), blurRadius: 12)];

/// App Store prices by product id (empty until they load, or when the App Store is away).
Map<String, String> _appStorePrices(WidgetRef ref) => {
      for (final e in (ref.watch(productsProvider).value ?? const {}).entries) e.key: e.value.price,
    };

/// The reward button of the rewarded card. While the countdown runs it fills from
/// left to right with the time, and says how long is left in legible white; at the
/// end it is a plain primary button.
class _CollectButton extends StatelessWidget {
  const _CollectButton({required this.coins, required this.left, required this.progress, required this.done, required this.onTap});
  final int coins;
  final int left;
  final double progress;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(Radii.md));
    return Semantics(
      button: true,
      enabled: done,
      child: Pressable(
        onTap: done ? onTap : null,
        child: ClipRRect(
          borderRadius: radius,
          child: SizedBox(
            height: 52,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: Colors.white.withValues(alpha: 0.14)),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: done ? 1 : progress),
                  duration: const Duration(milliseconds: 950),
                  builder: (_, v, _) => FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: v, child: const ColoredBox(color: Brand.accent)),
                ),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (done) ...[const Icon(AppIcons.checkmark, color: Colors.white, size: 19), const SizedBox(width: 8)],
                      Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(done ? 'Collect ${countOf(coins, 'coin')}' : 'Collect ${countOf(coins, 'coin')} in ${left}s', maxLines: 1, style: const TextStyle(color: Colors.white, fontSize: TypeSize.callout, fontWeight: FontWeight.w600, letterSpacing: -0.2)))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The offer CTA. The ad always sits on a dark scrim whatever the app theme,
/// so the button is a fixed white pill with near-black ink: `ButtonKind.dark`
/// follows the theme and in dark mode paints white text on a white fill.
class _OfferButton extends StatelessWidget {
  const _OfferButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  static const _ink = Color(0xFF111118);

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Radii.md)),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: TypeSize.callout, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _CountdownChip extends StatelessWidget {
  const _CountdownChip({required this.left, required this.progress, required this.done, required this.label, required this.onClose});
  final int left;
  final double progress;
  final bool done;
  final String label;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onClose,
      child: Glass(
        dark: true,
        radius: 999,
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(color: Colors.white, fontSize: TypeSize.footnote, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            SizedBox(
              width: 20,
              height: 20,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (!done)
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: progress),
                      duration: const Duration(milliseconds: 900),
                      builder: (_, v, _) => CircularProgressIndicator(value: v, strokeWidth: 2.5, color: Colors.white, backgroundColor: Colors.white24),
                    ),
                  // The label already says the seconds; the ring only shows the time running.
                  Icon(done ? AppIcons.xmark : null, size: 16, color: Colors.white),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind});
  final CreativeKind kind;
  @override
  Widget build(BuildContext context) {
    // Coins, tickets and hints carry the game's own marks, as everywhere else.
    final (Widget mark, String label) = switch (kind) {
      CreativeKind.vip => (const Icon(AppIcons.vip, size: 13, color: Brand.coin), 'VIP'),
      CreativeKind.coins => (const CoinIcon(size: 14), 'Coins'),
      CreativeKind.tickets => (const TicketIcon(size: 14), 'Tickets'),
      CreativeKind.hints => (const HintIcon(size: 14), 'Boosters'),
      CreativeKind.piggy => (const Icon(AppIcons.piggy, size: 13, color: Colors.white), 'Piggy bank'),
      CreativeKind.monthly => (const Icon(AppIcons.dailyPuzzle, size: 13, color: Colors.white), 'Daily puzzles'),
      CreativeKind.event => (const Icon(AppIcons.events, size: 13, color: Colors.white), 'Events'),
    };
    // 163: the one chip for text over a photo.
    return PhotoChip(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [mark, const SizedBox(width: 5), Text(label, style: PhotoChip.textStyle)],
      ),
    );
  }
}

/// Slim, dismissible upsell strip for list screens. Hidden for VIP members.
class HouseBanner extends ConsumerStatefulWidget {
  const HouseBanner({super.key});
  @override
  ConsumerState<HouseBanner> createState() => _HouseBannerState();
}

class _HouseBannerState extends ConsumerState<HouseBanner> {
  static bool _dismissedThisSession = false;
  Creative? _creative;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    if (_dismissedThisSession || profile == null || profile.isVip) return const SizedBox.shrink();
    // Not during the guided start (offers open at level 5).
    if (!ref.watch(revealsProvider).contains(Reveal.promos)) return const SizedBox.shrink();
    _creative ??= houseCreatives.firstWhere((c) => c.kind == CreativeKind.vip);
    final c = _creative!;
    final price = ((ref.watch(platformCapsProvider).purchases ? c.priceLine(_appStorePrices(ref)) : null) ?? c.body).replaceAll('/', '\u2060/\u2060');
    // The VIP card (lib/widgets/vip.dart), stacked: the crown, the headline and the full price on
    // top (word joiners keep "$2.99/month" together), then the action and "Not now" as real buttons.
    final copy = Row(
      children: [
        const VipCrown(size: IconTile.medium),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.headline, style: const TextStyle(color: Vip.fg, fontWeight: FontWeight.w600, fontSize: TypeSize.body)),
              const SizedBox(height: 2),
              Text(price, style: TextStyle(color: Vip.fgSecondary, fontSize: TypeSize.footnote, height: 1.3)),
            ],
          ),
        ),
      ],
    );
    final goVip = BigButton(label: 'Go VIP', kind: ButtonKind.gold, height: 40, onTap: () => openCreative(context, ref, c));
    final notNow = BigButton(label: 'Not now', kind: ButtonKind.ghostLight, height: 40, expand: false, onTap: () => setState(() => _dismissedThisSession = true));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: VipSurface(
        // A wide window has the room for one line: the copy, then the two buttons beside it.
        child: context.isWide
            ? Row(
                children: [
                  Expanded(child: copy),
                  const SizedBox(width: 16),
                  SizedBox(width: 180, child: goVip),
                  const SizedBox(width: 8),
                  notNow,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  copy,
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: goVip),
                      const SizedBox(width: 8),
                      notNow,
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
