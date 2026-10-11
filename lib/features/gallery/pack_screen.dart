import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../game/board.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// Pack detail: image hero, access state, and a grid of puzzles with stars.
/// Daily (monthly) packs render as a calendar; past months need VIP or coins.
class PackScreen extends ConsumerWidget {
  const PackScreen({super.key, required this.packId});
  final String packId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final packs = ref.watch(packsProvider).value ?? const [];
    final pack = packs.where((p) => p.id == packId).firstOrNull;
    if (pack == null) {
      return Scaffold(appBar: AppBar(), body: const Loader());
    }
    final puzzles = ref.watch(packPuzzlesProvider(packId));
    final progress = ref.watch(progressProvider).value ?? {};
    final profileN = ref.read(profileProvider.notifier);
    final profile = ref.watch(profileProvider).value;
    final unlocked = profile != null && profileN.isUnlocked(pack);
    final list = puzzles.value ?? const <Puzzle>[];
    final done = list.where((p) => progress[p.id]?.completed == true).length;
    final stars = list.fold<int>(0, (s, p) => s + (progress[p.id]?.stars ?? 0));
    final available = list.where((p) => !p.isLockedByDate).length;
    final priceCurrency = pack.priceTickets > 0 ? Currency.tickets : Currency.coins;
    final priceValue = pack.priceTickets > 0 ? pack.priceTickets : pack.priceCoins;

    Future<void> unlock() async {
      final ok = await profileN.unlockPack(pack);
      if (!context.mounted) return;
      if (ok) {
        Haptics.success();
        Sfx.instance.coin();
        showToast(context, '${pack.name} unlocked', icon: AppIcons.check);
      } else {
        Sfx.instance.error();
        final needTickets = pack.priceTickets > 0;
        showToast(
          context,
          needTickets ? 'Not enough Tickets. Finish weekly goals or level up to earn more.' : 'Not enough Coins. Play more puzzles or visit the store.',
          leading: const CoinIcon(size: 20),
        );
        context.push('/store');
      }
    }

    void goVip() => context.push('/store');

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            stretch: true,
            backgroundColor: Colors.transparent,
            scrolledUnderElevation: 0,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: RoundIconButton(icon: CupertinoIcons.back, size: 38, onTap: () => context.pop()),
            ),
            flexibleSpace: _CollapsedGlass(
              child: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(url: pack.coverUrl, blurhash: pack.blurhash),
                  DecoratedBox(decoration: BoxDecoration(gradient: Brand.scrim(strength: 0.7))),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Chip2(label: pack.category, icon: AppIcons.category(pack.category), onImage: true),
                            if (pack.hasWindow && !pack.isExpired) ...[
                              const SizedBox(width: 6),
                              Chip2(
                                label: pack.isUpcoming ? 'Opens in ${_countdown(pack.startAt!)}' : 'Ends in ${_countdown(pack.endAt!)}',
                                icon: pack.isUpcoming ? AppIcons.time : AppIcons.balloon,
                                color: pack.isUpcoming ? Colors.black.withValues(alpha: 0.45) : Brand.live,
                                foreground: Colors.white,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(pack.name, style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pack.description, style: TextStyle(color: c.textSecondary, fontSize: 14.5, height: 1.4)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _Stat(label: pack.isDaily ? 'Available' : 'Puzzles', value: pack.isDaily ? '$available/${list.length}' : '${list.length}'),
                      _Stat(label: 'Solved', value: '$done'),
                      _Stat(label: 'Stars', value: '$stars/${list.length * 3}', last: true),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (!unlocked)
                    _accessCard(context, pack, priceCurrency, priceValue, goVip, unlock).animate().fadeIn().slideY(begin: 0.1)
                  else
                    Row(
                      children: [
                        Icon(AppIcons.check, color: c.success, size: 18),
                        const SizedBox(width: 6),
                        Text('Unlocked · tap any picture to play', style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w500)),
                      ],
                    ),
                ],
              ),
            ),
          ),
          puzzles.when(
            loading: () => const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Loader())),
            error: (e, _) => const SliverToBoxAdapter(child: EmptyState(icon: AppIcons.signal, title: 'Pictures did not load', message: 'Check your connection and pull to try again.')),
            data: (list) => SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: pack.isDaily ? 4 : 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: pack.isDaily ? 0.8 : 0.72,
                ),
                delegate: SliverChildBuilderDelegate((_, i) {
                  final p = list[i];
                  final pr = progress[p.id];
                  return _PuzzleTile(
                    puzzle: p,
                    progress: pr,
                    locked: !unlocked,
                    dateLocked: p.isLockedByDate,
                    daily: pack.isDaily,
                    onTap: () {
                      if (p.isLockedByDate) {
                        Haptics.medium();
                        showToast(context, 'Opens on ${p.date!.day} ${_monthName(p.date!.month)}. Today\'s puzzle is ready now.', icon: AppIcons.lock);
                        return;
                      }
                      if (!unlocked) {
                        Haptics.medium();
                        _showAccessSheet(context, pack, priceCurrency, priceValue, goVip, unlock);
                        return;
                      }
                      if (pr != null && pr.inProgress) {
                        context.push('/game/${p.id}/${_gridCodeFor(pr)}');
                      } else {
                        context.push('/play/${p.id}');
                      }
                    },
                  ).animate().fadeIn(delay: (20 * i).ms, duration: 220.ms);
                }, childCount: list.length),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the single access card used for every locked state.
  static Widget _accessCard(BuildContext context, Pack pack, Currency currency, int price, VoidCallback onVip, VoidCallback onUnlock, {VoidCallback? onClose}) {
    void wrap(VoidCallback f) {
      onClose?.call();
      f();
    }

    if (pack.hasWindow && pack.isUpcoming) {
      return _AccessCard(
        icon: AppIcons.time,
        title: 'Opens soon',
        reason: 'Opens in ${_countdown(pack.startAt!)}.',
        ghost: ('Back to events', () => wrap(() => context.go('/events'))),
      );
    }
    if (pack.hasWindow && pack.isExpired) {
      return _AccessCard(
        icon: AppIcons.balloon,
        title: 'Event ended',
        reason: 'This pack was part of a past event.',
        ghost: ('Browse events', () => wrap(() => context.go('/events'))),
      );
    }
    if (pack.isDaily) {
      return _AccessCard(
        icon: AppIcons.lock,
        title: 'Past month',
        reason: 'Past months are included with VIP or can be unlocked once.',
        primary: ('Go VIP', AppIcons.vip, null, () => wrap(onVip)),
        secondary: ('Unlock for', null, Amount(currency: currency, value: price, size: 18, color: context.accent), () => wrap(onUnlock)),
      );
    }
    return _AccessCard(
      icon: AppIcons.lock,
      title: 'Locked pack',
      reason: 'Unlock once to play every picture.',
      primary: ('Unlock for', AppIcons.unlock, Amount(currency: currency, value: price, size: 18, color: Colors.white), () => wrap(onUnlock)),
      secondary: ('Go VIP', AppIcons.vip, null, () => wrap(onVip)),
    );
  }

  static void _showAccessSheet(BuildContext context, Pack pack, Currency currency, int price, VoidCallback onVip, VoidCallback onUnlock) {
    showAppSheet(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pack.name, style: Theme.of(ctx).textTheme.headlineSmall),
            const SizedBox(height: 12),
            _accessCard(ctx, pack, currency, price, onVip, onUnlock, onClose: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    );
  }

  static String _countdown(DateTime at) {
    final d = at.difference(DateTime.now());
    if (d.isNegative) return '0h';
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h';
    return '${d.inMinutes}m';
  }

  static String _monthName(int m) => const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][m - 1];

  /// Route path for resuming a saved board (mode + ladder entry by cell count).
  static String _gridCodeFor(PuzzleProgress pr) {
    final mode = GameMode.fromCode(pr.mode);
    return BoardCode.toPath(BoardSpec.fromCells(mode, pr.gridSize).fullCode);
  }
}

/// Once the cover has collapsed into a plain bar it becomes glass, with the
/// top of the picture blurred behind the title.
class _CollapsedGlass extends StatelessWidget {
  const _CollapsedGlass({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, cons) {
        final collapsed = cons.maxHeight <= MediaQuery.paddingOf(context).top + kToolbarHeight + 1;
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            GlassSurface(visible: collapsed, hairline: Border(bottom: BorderSide(color: c.stroke, width: 0.5)), child: const SizedBox.expand()),
          ],
        );
      },
    );
  }
}

/// The one access card used for every locked state: icon, title, reason,
/// and up to two actions. Keeps locked packs, past months and event packs
/// visually identical.
class _AccessCard extends StatelessWidget {
  const _AccessCard({required this.icon, required this.title, required this.reason, this.primary, this.secondary, this.ghost});
  final IconData icon;
  final String title;
  final String reason;
  final (String, IconData?, Widget?, VoidCallback)? primary;
  final (String, IconData?, Widget?, VoidCallback)? secondary;
  final (String, VoidCallback)? ghost;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(icon: icon, size: 40, radius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: -0.2)),
                    const SizedBox(height: 2),
                    Text(reason, style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
          if (primary != null) ...[
            const SizedBox(height: 14),
            BigButton(label: primary!.$1, icon: primary!.$2, trailing: primary!.$3, onTap: primary!.$4),
          ],
          if (secondary != null) ...[
            const SizedBox(height: 8),
            BigButton(label: secondary!.$1, icon: secondary!.$2, trailing: secondary!.$3, kind: ButtonKind.secondary, onTap: secondary!.$4),
          ],
          if (ghost != null) ...[
            const SizedBox(height: 14),
            BigButton(label: ghost!.$1, kind: ButtonKind.ghost, onTap: ghost!.$2),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.last = false});
  final String label;
  final String value;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: Container(
        margin: EdgeInsets.only(right: last ? 0 : 8),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(Radii.md), border: Border.all(color: c.stroke)),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: -0.3)),
            Text(label, style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

class _PuzzleTile extends StatelessWidget {
  const _PuzzleTile({required this.puzzle, required this.progress, required this.locked, required this.onTap, this.dateLocked = false, this.daily = false});
  final Puzzle puzzle;
  final PuzzleProgress? progress;
  final bool locked;
  final bool dateLocked;
  final bool daily;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final completed = progress?.completed == true;
    final started = progress?.inProgress == true;
    return Pressable(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: puzzle.isToday ? Brand.live : c.stroke, width: puzzle.isToday ? 1.5 : 1),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (dateLocked)
              Container(color: c.boardBackground, child: Icon(AppIcons.lock, color: c.textTertiary, size: 18))
            else
              NetImage(url: puzzle.thumbUrl, blurhash: puzzle.blurhash),
            if (locked && !dateLocked)
              Container(color: Colors.black.withValues(alpha: 0.4), child: const Icon(AppIcons.lock, color: Colors.white, size: 18)),
            if (daily && puzzle.date != null)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: puzzle.isToday ? Brand.live : (dateLocked ? c.card : Colors.black.withValues(alpha: 0.5)),
                    shape: BoxShape.circle,
                    border: dateLocked ? Border.all(color: c.stroke) : null,
                  ),
                  child: Text('${puzzle.date!.day}', style: TextStyle(color: dateLocked ? c.textTertiary : Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ),
            if (started)
              const Positioned(left: 6, top: 6, child: Chip2(label: 'Continue', onImage: true)),
            if (!dateLocked)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
                  decoration: BoxDecoration(gradient: Brand.scrim(strength: 0.7)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(puzzle.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      if (completed)
                        Stars(count: progress!.stars, size: 11)
                      else
                        Text(puzzle.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 9.5)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
