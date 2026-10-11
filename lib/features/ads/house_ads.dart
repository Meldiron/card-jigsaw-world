import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/profile.dart';
import '../../state/settings.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// House ads: we run no ad network, so every "ad" slot promotes something the
/// player can buy in the app (VIP, coins, tickets, hints) or a free feature
/// that leads there. Two formats:
///
/// * Rewarded: a timed full-screen card. The reward is granted only after the
///   countdown completes (or the player taps the offer). Capped per day on the
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
  static const everyNthCompletion = 4;
  static const minGap = Duration(minutes: 4);
  static const maxPerSession = 3;
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
  });
  final String id;
  final CreativeKind kind;
  final String headline;
  final String body;
  final String cta;
  final String route;
  final String? price;
}

const _creatives = <Creative>[
  Creative(id: 'vip-all', kind: CreativeKind.vip, headline: 'Every pack. No breaks.', body: 'VIP opens every pack and every past month, and removes these cards.', cta: 'Start free trial', route: '/store', price: '7 days free, then \$4.99/month'),
  Creative(id: 'vip-months', kind: CreativeKind.vip, headline: 'Three years of daily puzzles', body: 'All 46 monthly albums are included with VIP.', cta: 'Go VIP', route: '/store', price: '7 days free'),
  Creative(id: 'coins-3000', kind: CreativeKind.coins, headline: 'Running low on coins?', body: '3,000 coins unlock up to seven packs or 25 magic locks.', cta: 'Get 3,000 coins', route: '/store', price: '\$2.99'),
  Creative(id: 'coins-1000', kind: CreativeKind.coins, headline: 'A pack a day', body: '1,000 coins covers two monthly albums or a themed pack.', cta: 'Get 1,000 coins', route: '/store', price: '\$0.99'),
  Creative(id: 'tickets-5', kind: CreativeKind.tickets, headline: 'Spin the Lucky Wheel', body: 'Five tickets: five spins, or one premium pack and the piggy bank.', cta: 'Get 5 tickets', route: '/store', price: '\$1.99'),
  Creative(id: 'hints-15', kind: CreativeKind.hints, headline: 'Stuck on a card?', body: '15 hints show exactly where a card belongs.', cta: 'Get 15 hints', route: '/store', price: '\$2.49'),
  Creative(id: 'piggy', kind: CreativeKind.piggy, headline: 'Your piggy bank is filling up', body: 'Every finished puzzle adds 25 coins. Open it with one ticket.', cta: 'See piggy bank', route: '/home'),
  Creative(id: 'monthly', kind: CreativeKind.monthly, headline: 'One new picture every day', body: 'This month’s album is free. Past months come with VIP.', cta: 'Open this month', route: '/library'),
  Creative(id: 'events', kind: CreativeKind.event, headline: 'A new world-day event every week', body: 'Themed packs that open for seven days. Finish five for a ticket.', cta: 'See events', route: '/events'),
];

/// Picks a creative for the player's state; never repeats the last one.
Creative pickCreative(WidgetRef ref) {
  final store = ref.read(localStoreProvider);
  final p = ref.read(profileProvider).value;
  final pool = <Creative>[];
  if (p != null) {
    if (p.coins < 200) pool.addAll(_creatives.where((c) => c.kind == CreativeKind.coins));
    if (p.hints == 0) pool.addAll(_creatives.where((c) => c.kind == CreativeKind.hints));
    if (p.tickets == 0) pool.addAll(_creatives.where((c) => c.kind == CreativeKind.tickets));
    if (p.puzzlesCompleted >= 10 && !p.isVip) pool.addAll(_creatives.where((c) => c.kind == CreativeKind.vip));
    if (p.piggyCoins >= Profile.piggyCapacity * 0.6) pool.addAll(_creatives.where((c) => c.kind == CreativeKind.piggy));
  }
  if (pool.isEmpty) pool.addAll(_creatives.where((c) => !(p?.isVip ?? false) || c.kind != CreativeKind.vip));
  final candidates = pool.where((c) => c.id != store.lastCreativeId).toList();
  final list = candidates.isEmpty ? pool : candidates;
  final pick = list[Random().nextInt(list.length)];
  store.lastCreativeId = pick.id;
  return pick;
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
/// Returns after the ad is closed (or immediately when none is shown).
Future<void> maybeShowInterstitial(BuildContext context, WidgetRef ref) async {
  final store = ref.read(localStoreProvider);
  final profile = ref.read(profileProvider).value;
  store.lifetimeCompletions = store.lifetimeCompletions + 1;
  store.completionsSinceAd = store.completionsSinceAd + 1;
  if (profile?.isVip == true) return;
  if (store.lifetimeCompletions <= HouseAdPolicy.skipFirstCompletions) return;
  if (store.completionsSinceAd < HouseAdPolicy.everyNthCompletion) return;
  if (HouseAdPolicy.interstitialsThisSession >= HouseAdPolicy.maxPerSession) return;
  final last = store.lastInterstitialAt;
  if (last != null && DateTime.now().difference(last) < HouseAdPolicy.minGap) return;
  final rewarded = store.lastRewardedAt;
  if (rewarded != null && DateTime.now().difference(rewarded) < HouseAdPolicy.rewardedShield) return;
  store.completionsSinceAd = 0;
  store.lastInterstitialAt = DateTime.now();
  HouseAdPolicy.interstitialsThisSession++;
  final creative = pickCreative(ref);
  final cover = pickCover(ref, creative);
  if (!context.mounted) return;
  await Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: true,
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => HouseAdScreen(creative: creative, coverUrl: cover, rewarded: false),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ),
  );
}

/// Shows the rewarded card. Returns true when the reward was earned.
Future<bool> showRewardedHouseAd(BuildContext context, WidgetRef ref, {required int rewardCoins}) async {
  final creative = pickCreative(ref);
  final cover = pickCover(ref, creative);
  final result = await Navigator.of(context, rootNavigator: true).push<bool>(
    PageRouteBuilder(
      opaque: true,
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => HouseAdScreen(creative: creative, coverUrl: cover, rewarded: true, rewardCoins: rewardCoins),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
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
      final leave = await showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Close and lose the reward?'),
          content: Padding(padding: const EdgeInsets.only(top: 8), child: Text('${_left}s left to earn ${widget.rewardCoins} coins.')),
          actions: [
            CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep watching')),
            CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Close')),
          ],
        ),
      );
      if (leave != true || !mounted) return;
      Navigator.of(context).pop(false);
      return;
    }
    Navigator.of(context).pop(widget.rewarded ? _done : null);
  }

  void _cta() {
    // Tapping the offer counts as a completed view.
    Navigator.of(context).pop(widget.rewarded ? true : null);
    context.push(widget.creative.route);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.creative;
    final progress = 1 - _left / _total;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.coverUrl != null) NetImage(url: widget.coverUrl!.url, blurhash: widget.coverUrl!.hash) else Container(color: const Color(0xFF17171C)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.45, 1],
                colors: [Colors.black.withValues(alpha: 0.35), Colors.black.withValues(alpha: 0.15), Colors.black.withValues(alpha: 0.92)],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _KindBadge(kind: c.kind),
                      const SizedBox(height: 14),
                      Text(c.headline, style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white)).animate().fadeIn(delay: 150.ms).slideY(begin: 0.1),
                      const SizedBox(height: 8),
                      Text(c.body, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 16, height: 1.4)).animate().fadeIn(delay: 250.ms),
                      if (c.price != null) ...[
                        const SizedBox(height: 8),
                        Text(c.price!, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                      const SizedBox(height: 20),
                      BigButton(label: c.cta, kind: ButtonKind.dark, onTap: _cta),
                      if (widget.rewarded) ...[
                        const SizedBox(height: 10),
                        AnimatedOpacity(
                          opacity: _done ? 1 : 0.55,
                          duration: const Duration(milliseconds: 250),
                          child: BigButton(
                            label: _done ? 'Collect ${widget.rewardCoins} coins' : 'Collect ${widget.rewardCoins} coins in ${_left}s',
                            kind: ButtonKind.primary,
                            icon: _done ? Icons.check_rounded : null,
                            onTap: _done ? () => Navigator.of(context).pop(true) : null,
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 10),
                        Center(
                          child: Pressable(
                            onTap: _done ? _close : null,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(_done ? 'No thanks' : 'Continue in ${_left}s', style: TextStyle(color: Colors.white.withValues(alpha: _done ? 0.9 : 0.5), fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
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
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            SizedBox(
              width: 26,
              height: 26,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (!done)
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: progress),
                      duration: const Duration(milliseconds: 900),
                      builder: (_, v, __) => CircularProgressIndicator(value: v, strokeWidth: 2.5, color: Colors.white, backgroundColor: Colors.white24),
                    ),
                  Icon(done ? Icons.close_rounded : null, size: 16, color: Colors.white),
                  if (!done) Text('$left', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
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
    final (IconData icon, String label) = switch (kind) {
      CreativeKind.vip => (AppIcons.vip, 'VIP'),
      CreativeKind.coins => (Icons.monetization_on_rounded, 'Coins'),
      CreativeKind.tickets => (Icons.confirmation_number_rounded, 'Tickets'),
      CreativeKind.hints => (AppIcons.hint, 'Hints'),
      CreativeKind.piggy => (AppIcons.piggy, 'Piggy bank'),
      CreativeKind.monthly => (AppIcons.dailyPuzzle, 'Daily puzzles'),
      CreativeKind.event => (AppIcons.events, 'Events'),
    };
    return Chip2(label: label, icon: icon, onImage: true);
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
    _creative ??= _creatives.firstWhere((c) => c.kind == CreativeKind.vip);
    final c = _creative!;
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: context.isDark ? colors.cardElevated : colors.textPrimary,
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: Row(
          children: [
            Icon(AppIcons.vip, color: Brand.coin, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.headline, style: TextStyle(color: context.isDark ? colors.textPrimary : Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(c.price ?? c.body, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: (context.isDark ? colors.textPrimary : Colors.white).withValues(alpha: 0.7), fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            BigButton(label: 'Go VIP', kind: ButtonKind.gold, height: 36, expand: false, onTap: () => context.push(c.route)),
            const SizedBox(width: 4),
            Pressable(
              onTap: () => setState(() => _dismissedThisSession = true),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.close_rounded, size: 18, color: (context.isDark ? colors.textPrimary : Colors.white).withValues(alpha: 0.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
