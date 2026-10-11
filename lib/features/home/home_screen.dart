import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../game/board.dart';
import '../../models/models.dart';
import '../../state/auth.dart';
import '../../state/catalog.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/rewards.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../ads/house_ads.dart';
import '../daily/daily_reward_sheet.dart';
import '../daily/piggy_sheet.dart';
import '../gallery/pack_card.dart';
import 'header_bar.dart';

/// Home: today's puzzle, quick actions, streak, level, continue, months, packs.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final packs = ref.watch(packsProvider);
    final dailyPacks = ref.watch(dailyPacksProvider);
    final puzzles = ref.watch(allPuzzlesProvider);
    final progress = ref.watch(progressProvider).value ?? {};
    final daily = ref.watch(dailyPuzzleProvider);
    final isGuest = ref.watch(isGuestProvider);

    final inProgress = puzzles.value == null
        ? const <Puzzle>[]
        : progress.values
            .where((p) => p.inProgress)
            .map((p) {
              for (final z in puzzles.value!) {
                if (z.id == p.puzzleId) return z;
              }
              return null;
            })
            .whereType<Puzzle>()
            .toList();

    final piggyFull = profile?.piggyFull ?? false;
    final livePacks = ref.watch(eventPacksProvider).where((p) => p.isLive).toList();

    return Scaffold(
      body: RefreshIndicator.adaptive(
        edgeOffset: MediaQuery.paddingOf(context).top + HeaderBar.height,
        onRefresh: () async {
          ref.invalidate(packsProvider);
          ref.invalidate(allPuzzlesProvider);
          await ref.read(profileProvider.notifier).refresh();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            const HeaderBar(title: 'Card Jigsaw World'),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: _DailyHero(puzzle: daily, progress: daily == null ? null : progress[daily.id]),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _QuickTile(
                        icon: AppIcons.wheel,
                        title: 'Wheel',
                        status: '1 ticket per spin',
                        ready: false,
                        onTap: () => context.push('/wheel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _QuickTile(
                        icon: AppIcons.piggy,
                        title: 'Piggy bank',
                        status: piggyFull ? 'Full' : '${profile?.piggyCoins ?? 0} / ${Profile.piggyCapacity}',
                        ready: piggyFull,
                        onTap: () => showPiggySheet(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (profile != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _StreakCard(profile: profile, onTap: () => showDailyRewardSheet(context)),
                ),
              ),
            if (profile != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _LevelCard(profile: profile),
                ),
              ),
            if (isGuest)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: SoftCard(
                    padding: EdgeInsets.zero,
                    child: ListRow(
                      icon: AppIcons.save,
                      title: 'Save progress',
                      subtitle: 'Create a free account to keep coins and puzzles on every device',
                      onTap: () => context.push('/account'),
                    ),
                  ),
                ),
              ),
            if (inProgress.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Continue solving',
                  subtitle: '${inProgress.length} unfinished puzzle${inProgress.length == 1 ? '' : 's'}',
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 170,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    physics: const BouncingScrollPhysics(),
                    itemCount: inProgress.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) {
                      final p = inProgress[i];
                      final pr = progress[p.id]!;
                      return _ContinueCard(
                        puzzle: p,
                        progress: pr,
                        onTap: () => context.push('/game/${p.id}/${_gridCode(pr)}'),
                      );
                    },
                  ),
                ),
              ),
            ],
            if (livePacks.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Live events',
                  subtitle: 'Limited-time packs',
                  action: 'All events',
                  onAction: () => context.go('/events'),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 150,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    physics: const BouncingScrollPhysics(),
                    itemCount: livePacks.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => _EventPackCard(
                      pack: livePacks[i],
                      onTap: () => context.push('/library/pack/${livePacks[i].id}'),
                    ),
                  ),
                ),
              ),
            ],
            if (dailyPacks.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Daily puzzles',
                  subtitle: 'A new picture every day',
                  action: 'All months',
                  onAction: () => context.go('/library'),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 150,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    physics: const BouncingScrollPhysics(),
                    itemCount: dailyPacks.length.clamp(0, 12),
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => _MonthCard(
                      pack: dailyPacks[i],
                      current: i == 0,
                      onTap: () => context.push('/library/pack/${dailyPacks[i].id}'),
                    ),
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: HouseBanner()),
            SliverToBoxAdapter(
              child: SectionHeader(title: 'Featured packs', action: 'See all', onAction: () => context.go('/library')),
            ),
            packs.when(
              loading: () => const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Loader())),
              error: (e, _) => const SliverToBoxAdapter(
                child: EmptyState(icon: AppIcons.signal, title: 'Could not load packs', message: 'Check your connection and pull to refresh.'),
              ),
              data: (all) {
                final list = all.where((p) => !p.isDaily).toList();
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.78,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => PackCard(pack: list[i], onTap: () => context.push('/library/pack/${list[i].id}'))
                          .animate()
                          .fadeIn(delay: (40 * i).ms, duration: 300.ms)
                          .slideY(begin: 0.06, curve: Curves.easeOut),
                      childCount: list.length.clamp(0, 6),
                    ),
                  ),
                );
              },
            ),
            SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 12)),
          ],
        ),
      ),
    );
  }

  /// Route path for resuming a saved board (mode + ladder entry by cell count).
  static String _gridCode(PuzzleProgress pr) {
    final mode = GameMode.fromCode(pr.mode);
    final spec = BoardSpec.fromCells(mode, pr.gridSize);
    return BoardCode.toPath(spec.fullCode);
  }
}

class _DailyHero extends StatelessWidget {
  const _DailyHero({required this.puzzle, required this.progress});
  final Puzzle? puzzle;
  final PuzzleProgress? progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = progress?.completed ?? false;
    return Pressable(
      onTap: puzzle == null ? null : () => context.push('/play/${puzzle!.id}'),
      scale: 0.985,
      child: Container(
        height: 220,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.boardBackground,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: c.stroke),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (puzzle != null) NetImage(url: puzzle!.imageUrl, blurhash: puzzle!.blurhash),
            DecoratedBox(decoration: BoxDecoration(gradient: Brand.scrim(strength: 0.8))),
            Positioned(
              left: 14,
              top: 14,
              child: Chip2(label: done ? 'Today · solved' : 'Today', icon: AppIcons.dailyPuzzle, onImage: true),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          puzzle?.title ?? 'Loading…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        if (done)
                          Text('Solved · replay for more stars',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w500))
                        else
                          Row(
                            children: [
                              Amount(currency: Currency.coins, value: 50, prefix: '+', size: 14, fontSize: 13, color: Colors.white, weight: FontWeight.w600),
                              const SizedBox(width: 6),
                              Text('bonus today',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w500)),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: Icon(done ? CupertinoIcons.arrow_counterclockwise : CupertinoIcons.play_fill, color: Colors.black, size: 20),
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

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.icon, required this.title, required this.status, required this.ready, required this.onTap});
  final IconData icon;
  final String title;
  final String status;
  final bool ready;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 112,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: c.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(icon: icon, size: 34, radius: 10),
            const Spacer(),
            Row(
              children: [
                Flexible(
                  child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, letterSpacing: -0.2)),
                ),
                if (ready) ...[
                  const SizedBox(width: 5),
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: Brand.live, shape: BoxShape.circle)),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(status, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: ready ? context.accent : c.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Streak: week dots and what today's or tomorrow's gift is worth.
class _StreakCard extends ConsumerWidget {
  const _StreakCard({required this.profile, required this.onTap});
  final Profile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final canRestore = ref.read(profileProvider.notifier).canRestoreStreak;
    final streak = profile.streak;
    final nextIdx = profile.dailyAvailable ? streak % 7 : streak % 7;
    final filled = profile.dailyAvailable ? streak % 7 : ((streak - 1) % 7) + 1;
    final next = Economy.dailyRewards[nextIdx];
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconTile(icon: AppIcons.streak, size: 36, radius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$streak-day streak', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      canRestore
                          ? 'Streak reset · restore ${profile.longestStreak} days'
                          : (profile.dailyAvailable ? 'Claim today to keep it going' : 'Claimed · back tomorrow'),
                      style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              if (canRestore)
                BigButton(label: 'Restore', kind: ButtonKind.secondary, height: 30, expand: false, onTap: onTap)
              else
                Icon(CupertinoIcons.chevron_right, size: 16, color: c.textTertiary),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < 7; i++) ...[
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < filled ? context.accent : Colors.transparent,
                          border: Border.all(color: i < filled ? context.accent : (i == nextIdx ? context.accent : c.stroke), width: i == nextIdx && i >= filled ? 1.5 : 1),
                        ),
                        child: i < filled ? const Icon(CupertinoIcons.checkmark, size: 12, color: Colors.white) : null,
                      ),
                      const SizedBox(height: 4),
                      Text('${i + 1}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c.textTertiary)),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: c.stroke),
          const SizedBox(height: 10),
          Row(
            children: [
              if (profile.dailyAvailable) ...[
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: Brand.live, shape: BoxShape.circle)),
                const SizedBox(width: 6),
              ],
              Text(profile.dailyAvailable ? "Today's gift" : "Tomorrow's gift",
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: profile.dailyAvailable ? c.textPrimary : c.textSecondary)),
              const SizedBox(width: 10),
              Amount(currency: Currency.coins, value: next.coins, size: 15, fontSize: 13),
              if (next.tickets > 0) ...[const SizedBox(width: 8), Amount(currency: Currency.tickets, value: next.tickets, size: 15, fontSize: 13)],
              if (next.hints > 0) ...[const SizedBox(width: 8), Amount(currency: Currency.hints, value: next.hints, size: 15, fontSize: 13)],
              const Spacer(),
              if (profile.dailyAvailable) BigButton(label: 'Claim', height: 36, expand: false, onTap: onTap),
            ],
          ),
        ],
      ),
    );
  }
}

/// Level: progress plus what the next levels unlock.
class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final level = profile.level;
    final next = LevelRewards.forLevel(level + 1);
    final later = LevelRewards.upcoming(level + 1, count: 2);
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconTile(icon: AppIcons.level, size: 36, radius: 10),
              const SizedBox(width: 12),
              Expanded(child: Text('Level $level', style: Theme.of(context).textTheme.titleLarge)),
              Text('${profile.xpIntoLevel} / ${Profile.xpForLevel(level)} XP',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: c.textSecondary)),
            ],
          ),
          const SizedBox(height: 12),
          ProgressBar(value: profile.levelProgress, height: 8),
          const SizedBox(height: 14),
          Text('Next: level ${level + 1}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _RewardChip(child: Amount(currency: Currency.coins, value: next.coins, size: 14, fontSize: 12.5)),
              if (next.tickets > 0) _RewardChip(child: Amount(currency: Currency.tickets, value: next.tickets, size: 14, fontSize: 12.5)),
              if (next.hints > 0) _RewardChip(child: Amount(currency: Currency.hints, value: next.hints, size: 14, fontSize: 12.5)),
              if (next.tier != null) Chip2(label: '${next.tier!.code} ${next.tier!.label} boards', icon: AppIcons.bigBoard),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: c.stroke),
          const SizedBox(height: 10),
          Text('Coming up', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textTertiary)),
          const SizedBox(height: 6),
          for (final r in later)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text('Level ${r.level}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textSecondary)),
                  ),
                  Expanded(
                    child: Text(r.lines.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, height: 1.3, color: c.textTertiary)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RewardChip extends StatelessWidget {
  const _RewardChip({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: c.canvas, borderRadius: BorderRadius.circular(999), border: Border.all(color: c.stroke)),
      child: child,
    );
  }
}

/// Month tile for the daily puzzle row.
class _MonthCard extends ConsumerWidget {
  const _MonthCard({required this.pack, required this.current, required this.onTap});
  final Pack pack;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final puzzles = ref.watch(packPuzzlesProvider(pack.id)).value ?? const <Puzzle>[];
    final progress = ref.watch(progressProvider).value ?? {};
    final done = puzzles.where((p) => progress[p.id]?.completed == true).length;
    final total = puzzles.isEmpty ? pack.imageCount : puzzles.length;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 132,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.boardBackground,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: c.stroke),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetImage(url: pack.coverUrl, blurhash: pack.blurhash),
            DecoratedBox(decoration: BoxDecoration(gradient: Brand.scrim(strength: 0.8))),
            if (current)
              const Positioned(left: 8, top: 8, child: Chip2(label: 'This month', color: Brand.live, foreground: Colors.white)),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pack.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: -0.2)),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: ProgressBar(value: total == 0 ? 0 : done / total, height: 4, color: Colors.white, background: Colors.white.withValues(alpha: 0.3)),
                      ),
                      const SizedBox(width: 6),
                      Text('$done/$total', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600)),
                    ],
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

/// Image-first tile for a live event pack.
class _EventPackCard extends StatelessWidget {
  const _EventPackCard({required this.pack, required this.onTap});
  final Pack pack;
  final VoidCallback onTap;

  String get _endsIn {
    final end = pack.endAt;
    if (end == null) return 'Live';
    final d = end.difference(DateTime.now());
    if (d.inDays >= 1) return 'Ends in ${d.inDays}d';
    if (d.inHours >= 1) return 'Ends in ${d.inHours}h';
    return 'Ends soon';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 150,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.boardBackground,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: c.stroke),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetImage(url: pack.coverUrl, blurhash: pack.blurhash),
            DecoratedBox(decoration: BoxDecoration(gradient: Brand.scrim(strength: 0.8))),
            Positioned(left: 8, top: 8, child: Chip2(label: _endsIn, color: Brand.live, foreground: Colors.white)),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pack.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: -0.2, height: 1.15)),
                  const SizedBox(height: 3),
                  Text('${pack.imageCount} puzzles', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.puzzle, required this.progress, required this.onTap});
  final Puzzle puzzle;
  final PuzzleProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final locked = progress.layout == null ? 0 : [for (var i = 0; i < progress.layout!.length; i++) if (progress.layout![i] == i) i].length;
    final total = progress.layout?.length ?? progress.gridSize;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 150,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: c.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: NetImage(url: puzzle.thumbUrl, blurhash: puzzle.blurhash, width: double.infinity)),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(puzzle.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  ProgressBar(value: total == 0 ? 0 : locked / total, height: 5),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
