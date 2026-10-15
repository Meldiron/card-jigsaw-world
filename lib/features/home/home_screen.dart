import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/haptics.dart';
import '../../core/theme/tokens.dart';
import '../../game/board.dart';
import '../../models/models.dart';
import '../../state/auth.dart';
import '../../state/catalog.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/quick_play.dart';
import '../game/unlock_intro.dart';
import '../../state/rewards.dart';
import '../../state/unlocks.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../ads/house_ads.dart';
import '../daily/daily_reward_sheet.dart';
import '../daily/piggy_sheet.dart';
import '../daily/wheel_screen.dart' show wheelSegments;
import '../../widgets/glass.dart';
import '../gallery/library_screen.dart';
import '../gallery/pack_card.dart';
import '../gallery/pack_progress.dart';
import 'header_bar.dart';
import 'home_pack_rows.dart';
import 'tomorrow_preview.dart';

/// Home: today's puzzle, Quick play, Wheel and piggy bank, streak, level,
/// boards to continue, packs in progress, live events, daily months, packs
/// missing stars, featured packs and finished packs.
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
    final dailySolved = daily != null && daily.isToday && (progress[daily.id]?.completed ?? false);
    final tomorrow = dailySolved ? tomorrowsDaily(puzzles.value ?? const <Puzzle>[], DateTime.now()) : null;

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
    // Riverpod retries a failed catalogue read and keeps the value "loading" meanwhile (dependent
    // providers wait), so while the packs are missing the catalogue's own error is looked at
    // instead of waiting for AsyncValue.when to reach its error branch.
    // (`exists`: only read it when something already started it, never start a read from here.)
    final catalogFailed = !packs.hasValue && ref.exists(catalogProvider) && ref.watch(catalogProvider.select((v) => v.hasError && !v.hasValue));
    void retryCatalog() => ref.invalidate(catalogProvider);
    final livePacks = ref.watch(eventPacksProvider).where((p) => p.isLive).toList();
    final packRows = ref.watch(homePackRowsProvider);
    final packProgress = ref.watch(allPackProgressProvider);
    PackProgress progressOf(Pack p) => packProgress[p.id] ?? const PackProgress(solved: 0, total: 0, stars: 0);
    final missingStars = packRows.missingStars.fold<int>(0, (sum, p) => sum + progressOf(p).maxStars - progressOf(p).stars);

    return Scaffold(
      body: RefreshIndicator.adaptive(
        edgeOffset: MediaQuery.paddingOf(context).top + HeaderBar.height,
        onRefresh: () async {
          ref.invalidate(catalogProvider);
          await ref.read(profileProvider.notifier).refresh();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            const HeaderBar(title: 'Carden'),
            // Large title, as on the other tabs: the date and a greeting, so Home opens on "today".
            SliverToBoxAdapter(child: _Greeting(name: profile?.displayName)),
            // The first-time intro of a shape or option the player's level just opened.
            SliverToBoxAdapter(child: UnlockIntroHost(at: (path) => path == '/home')),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: daily == null
                    ? _HeroPlaceholder(failed: catalogFailed, onRetry: retryCatalog)
                    : _DailyHero(puzzle: daily, progress: progress[daily.id]),
              ),
            ),
            // Today's daily puzzle is solved: a blurred look at tomorrow's.
            if (tomorrow != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: TomorrowPreview(puzzle: tomorrow),
                ),
              ),
            // One tap back into the board closest to done; the full row is further down.
            if (inProgress.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Builder(builder: (context) {
                    final p = _closestToDone(inProgress, progress);
                    final pr = progress[p.id]!;
                    return _ResumeCard(puzzle: p, progress: pr, others: inProgress.length - 1, onTap: () => context.push('/game/${p.id}/${_gridCode(pr)}'));
                  }),
                ),
              ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _QuickPlayCard(),
              ),
            ),
            if (profile != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _StreakCard(profile: profile, onTap: () => showDailyRewardSheet(context)),
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
                  height: _CoverTile.size,
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
            if (packRows.inProgress.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Packs in progress',
                  subtitle: '${packRows.inProgress.length} ${packRows.inProgress.length == 1 ? 'pack' : 'packs'} to finish',
                ),
              ),
              SliverToBoxAdapter(
                child: _PackCoverRow(
                  key: const ValueKey('home-packs-in-progress'),
                  packs: packRows.inProgress,
                  progressOf: progressOf,
                ),
              ),
            ],
            // Extras after the boards and packs the player is working on.
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _QuickTile(
                        icon: AppIcons.wheel,
                        title: 'Lucky Wheel',
                        value: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text('Up to', style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w500, color: context.colors.textSecondary)),
                            const SizedBox(width: 6),
                            Amount(currency: Currency.coins, value: _wheelJackpot, size: 18, fontSize: TypeSize.title3, weight: FontWeight.w700),
                          ],
                        ),
                        footer: CostLabel(label: 'Spin for', currency: Currency.tickets, amount: Economy.wheelSpinTickets, fontSize: TypeSize.footnote, color: context.colors.textSecondary),
                        onTap: () => context.push('/wheel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _QuickTile(
                        icon: AppIcons.piggy,
                        title: 'Piggy bank',
                        ready: piggyFull,
                        value: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(formatCount(profile?.piggyCoins ?? 0), style: const TextStyle(fontSize: TypeSize.title3, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                            Text(' / ${formatCount(Profile.piggyCapacity)}', style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w500, color: context.colors.textSecondary)),
                          ],
                        ),
                        footer: piggyFull
                            ? CostLabel(label: 'Full · open for', currency: Currency.tickets, amount: Economy.piggyOpenTickets, fontSize: TypeSize.footnote, color: context.accent)
                            : ProgressBar(value: (profile?.piggyCoins ?? 0) / Profile.piggyCapacity, height: 5),
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
                  child: _LevelCard(profile: profile),
                ),
              ),
            if (isGuest)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _GuestSaveCard(onSave: () => context.push('/account')),
                ),
              ),
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
                  height: _CoverTile.size,
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
                  onAction: () {
                    ref.read(libraryFilterProvider.notifier).select(LibraryFilter.daily);
                    context.go('/library');
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: _CoverTile.size,
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
            if (packRows.missingStars.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Missing stars',
                  subtitle: '$missingStars ${missingStars == 1 ? 'star' : 'stars'} to earn in ${packRows.missingStars.length} '
                      '${packRows.missingStars.length == 1 ? 'pack' : 'packs'}',
                ),
              ),
              SliverToBoxAdapter(
                child: _PackCoverRow(
                  key: const ValueKey('home-missing-stars'),
                  packs: packRows.missingStars,
                  progressOf: progressOf,
                ),
              ),
            ],
            const SliverToBoxAdapter(child: HouseBanner()),
            SliverToBoxAdapter(
              child: SectionHeader(
                title: 'Featured packs',
                action: 'See all',
                onAction: () {
                  ref.read(libraryFilterProvider.notifier).select(LibraryFilter.all);
                  context.go('/library');
                },
              ),
            ),
            if (!packs.hasValue && (packs.hasError || catalogFailed))
              SliverToBoxAdapter(
                child: EmptyState(
                  icon: AppIcons.signal,
                  title: 'Could not load packs',
                  message: 'Check your connection and try again.',
                  action: BigButton(label: 'Try again', kind: ButtonKind.secondary, expand: false, height: 40, onTap: retryCatalog),
                ),
              )
            else
            packs.when(
              loading: () => const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Loader())),
              error: (e, _) => const SliverToBoxAdapter(
                child: EmptyState(icon: AppIcons.signal, title: 'Could not load packs', message: 'Check your connection and pull to refresh.'),
              ),
              data: (all) {
                // Library packs only (no daily months, no event packs), in catalogue order.
                final list = all.where((p) => !p.isDaily && !p.hasWindow).toList()
                  ..sort((a, b) => a.sortOrder != b.sortOrder ? a.sortOrder.compareTo(b.sortOrder) : a.id.compareTo(b.id));
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.78,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => PackCard(pack: list[i], onTap: () => context.push('/library/pack/${list[i].id}')),
                      childCount: list.length.clamp(0, featuredCount),
                    ),
                  ),
                );
              },
            ),
            if (packRows.finished.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Finished packs',
                  action: 'See all',
                  onAction: () {
                    ref.read(libraryFilterProvider.notifier).select(LibraryFilter.finished);
                    context.go('/library');
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _FinishedPacksCard(rows: packRows, progressOf: progressOf),
                ),
              ),
            ],
            SliverToBoxAdapter(child: SizedBox(height: GlassTabBar.scrollEndPadding(context))),
          ],
        ),
      ),
    );
  }

  /// Library packs in the Featured grid.
  static const featuredCount = 6;

  /// Route path for resuming a saved board (mode + ladder entry by cell count).
  static String _gridCode(PuzzleProgress pr) {
    final mode = GameMode.fromCode(pr.mode);
    final spec = BoardSpec.fromCells(mode, pr.gridSize);
    return BoardCode.toPath(spec.fullCode);
  }
}

/// "Thursday 15 October" over "Good evening, Mia" (first name; none while it is the default "Player").
class _Greeting extends StatelessWidget {
  const _Greeting({required this.name});
  final String? name;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final part = now.hour < 5 ? 'Good evening' : (now.hour < 12 ? 'Good morning' : (now.hour < 18 ? 'Good afternoon' : 'Good evening'));
    // First name only: "Maximilian", not "Maximilian Alexander von Habsburg".
    final n = (name?.trim() ?? '').split(RegExp(r'\s+')).first;
    final title = n.isEmpty || n == 'Player' ? part : '$part, $n';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(DateFormat('EEEE d MMMM').format(now), style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textSecondary)),
          const SizedBox(height: 2),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineLarge),
        ],
      ),
    );
  }
}

class _DailyHero extends StatelessWidget {
  const _DailyHero({required this.puzzle, required this.progress});
  final Puzzle puzzle;
  final PuzzleProgress? progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = progress?.completed ?? false;
    final stars = progress?.stars ?? 0;
    return Pressable(
      onTap: () => context.push('/play/${puzzle.id}'),
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
            NetImage(url: puzzle.imageUrl, blurhash: puzzle.blurhash),
            DecoratedBox(decoration: BoxDecoration(gradient: Brand.scrim(strength: 0.8))),
            Positioned(
              left: 14,
              top: 14,
              child: Chip2(label: 'Today', icon: AppIcons.dailyPuzzle, onImage: true),
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
                          puzzle.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        if (done)
                          // The stars earned, and the reason to replay only while one is missing.
                          Row(
                            children: [
                              for (var i = 0; i < 3; i++)
                                Icon(i < stars ? AppIcons.star : AppIcons.starOutline, size: 14,
                                    color: i < stars ? Brand.star : Colors.white.withValues(alpha: 0.6)),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(stars >= 3 ? 'Solved' : 'Solved · replay for 3 stars',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: TypeSize.footnote, fontWeight: FontWeight.w500)),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Amount(currency: Currency.coins, value: 50, prefix: '+', size: 14, fontSize: TypeSize.footnote, color: Colors.white, weight: FontWeight.w600),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text('bonus today',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: TypeSize.footnote, fontWeight: FontWeight.w500)),
                              ),
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
                    child: Icon(done ? AppIcons.arrowCounterclockwise : AppIcons.playFill, color: Colors.black, size: 20),
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

/// The daily puzzle's place while the catalogue loads (a quiet empty frame with
/// a spinner, no title or button that would do nothing), or, when it could not
/// be read, what happened and a way to try again.
class _HeroPlaceholder extends StatelessWidget {
  const _HeroPlaceholder({required this.failed, required this.onRetry});
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: c.boardBackground,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.stroke),
      ),
      child: !failed
          ? const Loader()
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(AppIcons.signal, size: 26, color: c.textTertiary),
                  const SizedBox(height: 10),
                  Text("Today's puzzle could not load", textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('Check your connection and try again.', textAlign: TextAlign.center, style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary)),
                  const SizedBox(height: 14),
                  BigButton(label: 'Try again', kind: ButtonKind.secondary, expand: false, height: 40, onTap: onRetry),
                ],
              ),
            ),
    );
  }
}

/// Wheel and piggy bank: a small widget-style tile, the name at the top, the
/// figure that matters in the middle, what it costs or how full it is below.
class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.icon, required this.title, required this.value, required this.footer, required this.onTap, this.ready = false});
  final IconData icon;
  final String title;
  final Widget value;
  final Widget footer;
  final bool ready;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onTap,
      child: Container(
        // 167: the tiles grow with Larger Text, both by the same amount, so their figures still line up.
        height: MediaQuery.textScalerOf(context).scale(112),
        // 14 pt sides and a 6 pt gap after the icon: "Lucky Wheel" fits on an SE (was "Lucky Wh...")
        // with the same icon tile, type and tile height as before.
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: Spacing.md),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: c.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconTile(icon: icon, size: IconTile.small),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.body, letterSpacing: -0.2)),
                ),
                if (ready) ...[
                  const SizedBox(width: 6),
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: Brand.live, shape: BoxShape.circle)),
                ],
              ],
            ),
            const Spacer(),
            // A long figure shrinks a little instead of running past the tile's edge.
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: value),
            const SizedBox(height: 6),
            // Same height for a price line and a progress bar, so both tiles' figures line up.
            SizedBox(height: MediaQuery.textScalerOf(context).scale(18), child: Align(alignment: Alignment.centerLeft, child: footer)),
          ],
        ),
      ),
    );
  }
}

/// The Lucky Wheel's top prize, for the Home tile.
final int _wheelJackpot = wheelSegments.where((s) => s.kind == Currency.coins).map((s) => s.amount).reduce(max);

/// Streak: week dots and what today's or tomorrow's gift is worth. After
/// missed days a lost streak can be restored with today's gift: the dots give
/// way to that offer.
class _StreakCard extends ConsumerWidget {
  const _StreakCard({required this.profile, required this.onTap});
  final Profile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final canRestore = ref.read(profileProvider.notifier).canRestoreStreak;
    final streak = profile.currentStreak;
    final available = profile.dailyAvailable;
    final missed = !profile.streakAlive && profile.streak > 0;
    final nextIdx = profile.nextGiftDay;
    final filled = profile.giftsClaimedThisRound;
    final next = Economy.dailyRewards[nextIdx];
    final title = streak > 0 ? '$streak-day streak' : (missed ? 'Streak ended' : 'Start a streak');
    final status = missed
        ? (canRestore ? 'Missed a day after ${profile.streak} days' : 'Missed a day · claim to start again')
        : !available
            ? 'Claimed · back tomorrow'
            : (streak > 0 ? 'Claim today to keep it going' : 'Claim a gift every day');
    return SoftCard(
      onTap: onTap,
      padding: Insets.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconTile(icon: AppIcons.streak, size: IconTile.medium),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(AppIcons.chevronRight, size: 16, color: c.textTertiary),
            ],
          ),
          const SizedBox(height: 14),
          if (canRestore)
            // The offer opens the Daily gift sheet, which asks once more before the tickets are spent.
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              decoration: BoxDecoration(color: c.canvas, borderRadius: BorderRadius.circular(Radii.md), border: Border.all(color: c.stroke)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Keep your streak',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 1),
                        Text('Today becomes day ${profile.streak % 7 + 1}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: TypeSize.caption, color: c.textSecondary)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  BigButton.cost(
                    label: 'Restore',
                    currency: Currency.tickets,
                    amount: Economy.streakRestoreTickets(profile.streak),
                    kind: ButtonKind.secondary,
                    height: 36,
                    expand: false,
                    onTap: onTap,
                  ),
                ],
              ),
            )
          else
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
                            color: i < filled ? context.accentFill : Colors.transparent,
                            border: Border.all(color: i < filled ? context.accentFill : (i == nextIdx ? context.accent : c.stroke), width: i == nextIdx && i >= filled ? 1.5 : 1),
                          ),
                          child: i < filled ? Icon(AppIcons.checkmark, size: 12, color: context.onAccent) : null,
                        ),
                        const SizedBox(height: 4),
                        Text('${i + 1}', style: TextStyle(fontSize: TypeSize.micro, fontWeight: FontWeight.w600, color: c.textTertiary)),
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
              // 167: the label gives way (ellipsis) before the amounts and Claim do, at any text size.
              Expanded(
                child: Row(
                  children: [
                    if (available) ...[
                      Container(width: 6, height: 6, decoration: const BoxDecoration(color: Brand.live, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(available ? "Today's gift" : "Tomorrow's gift",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w500, color: available ? c.textPrimary : c.textSecondary)),
                    ),
                    const SizedBox(width: 10),
                    Amount(currency: Currency.coins, value: next.coins, size: 15, fontSize: TypeSize.footnote),
                    if (next.tickets > 0) ...[const SizedBox(width: 8), Amount(currency: Currency.tickets, value: next.tickets, size: 15, fontSize: TypeSize.footnote)],
                    if (next.hints > 0) ...[const SizedBox(width: 8), Amount(currency: Currency.hints, value: next.hints, size: 15, fontSize: TypeSize.footnote)],
                  ],
                ),
              ),
              if (available) ...[const SizedBox(width: 8), BigButton(label: 'Claim', height: 36, expand: false, onTap: onTap)],
            ],
          ),
        ],
      ),
    );
  }
}

/// A guest's caution: their coins and puzzles live on this device only until they create an
/// account. A calm card like the rest of Home (no orange fill), made a caution by the warning
/// outline and mark and a line that says what is at stake, with one clear action.
class _GuestSaveCard extends StatelessWidget {
  const _GuestSaveCard({required this.onSave});
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      onTap: onSave,
      padding: Insets.cardCompact,
      borderColor: c.warning.withValues(alpha: 0.45),
      child: Row(
        children: [
          IconTile(
            icon: AppIcons.caution,
            size: IconTile.medium,
            color: c.warning.withValues(alpha: context.isDark ? 0.2 : 0.14),
            iconColor: c.warning,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Not backed up', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  'Lost if this app is deleted',
                  style: TextStyle(fontSize: TypeSize.footnote, height: 1.3, color: c.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          BigButton(label: 'Save', kind: ButtonKind.secondary, height: 36, expand: false, onTap: onSave),
        ],
      ),
    );
  }
}

/// Level: progress, the next level's rewards as chips (what opens first, in cobalt, then the
/// currencies), and the two after it as rows in the same marks, smaller.
class _LevelCard extends ConsumerWidget {
  const _LevelCard({required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final level = profile.level;
    // What the player already opened before its level (a shape used, giant boards bought early)
    // is not promised again. Only the player's own opens count: a test that opens everything
    // (`OpenFeatures.all`) keeps the card as a new player sees it.
    final opened = {...ref.watch(openFeaturesProvider).used, ...Unlocks.openedEarly(profile.unlockedTiers)};
    final next = LevelRewards.forLevel(level + 1).without(opened);
    final later = [for (final r in LevelRewards.upcoming(level + 1, count: 2)) r.without(opened)];
    return SoftCard(
      padding: Insets.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconTile(icon: AppIcons.level, size: IconTile.medium),
              const SizedBox(width: 12),
              // The XP sits at the end of the title's line; with Larger Text on a small phone it moves
              // under the title instead of pushing the row off the card.
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text('Level $level', style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      '${formatCount(profile.xpIntoLevel)} / ${formatCount(Profile.xpForLevel(level))} XP',
                      style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w500, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ProgressBar(value: profile.levelProgress, height: 8),
          const SizedBox(height: 14),
          Text(
            'Next: level ${level + 1}',
            style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textPrimary),
          ),
          const SizedBox(height: 8),
          _LevelRewardChips(reward: next, keyed: true),
          const SizedBox(height: 12),
          Container(height: 1, color: c.stroke),
          const SizedBox(height: 10),
          Text(
            'Coming up',
            style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textSecondary),
          ),
          const SizedBox(height: 8),
          for (final r in later)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A column for the level names (wider with Larger Text, so a name never runs into its marks).
                  ConstrainedBox(
                    constraints: BoxConstraints(minWidth: MediaQuery.textScalerOf(context).scale(64)),
                    child: Text(
                      'Level ${r.level}',
                      style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(child: _LevelRewardMarks(reward: r)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A reward as chips ([RewardChip], large): what it opens first (cobalt), then coins, tickets and
/// hints in neutral chips with their currency marks. The Level card's next level; achievements use
/// the same chips, compact, for what a step gives. [keyed] keys each unlock `next-unlock-<name>`
/// (tests scroll to it).
class _LevelRewardChips extends StatelessWidget {
  const _LevelRewardChips({required this.reward, this.keyed = false});
  final LevelReward reward;
  final bool keyed;

  @override
  Widget build(BuildContext context) {
    final r = reward;
    // A chip wider than the card (Larger Text on a small phone) scales down instead of overflowing.
    Widget fit(Widget chip) => FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: chip);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final u in r.unlocks)
          fit(RewardChip.unlock(key: keyed ? ValueKey('next-unlock-${u.name}') : null, large: true, leading: Icon(_unlockIcon(u), size: 12, color: context.accent), label: u.label)),
        if (r.tier != null)
          fit(RewardChip.unlock(large: true, leading: Icon(AppIcons.bigBoard, size: 12, color: context.accent), label: '${r.tier!.code} ${r.tier!.label} boards')),
        RewardChip.amount(currency: Currency.coins, value: r.coins, large: true),
        if (r.tickets > 0) RewardChip.amount(currency: Currency.tickets, value: r.tickets, large: true),
        if (r.hints > 0) RewardChip.amount(currency: Currency.hints, value: r.hints, large: true),
      ],
    );
  }
}

/// A reward in a row of marks without chips (the Level card's "Coming up"): cobalt unlocks, then
/// currency marks with their numbers in secondary text, so the next level keeps the emphasis.
class _LevelRewardMarks extends StatelessWidget {
  const _LevelRewardMarks({required this.reward});
  final LevelReward reward;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = reward;
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final u in r.unlocks) _UnlockMark(icon: _unlockIcon(u), label: u.label),
        if (r.tier != null) _UnlockMark(icon: AppIcons.bigBoard, label: '${r.tier!.code} ${r.tier!.label}'),
        Amount(currency: Currency.coins, value: r.coins, size: 14, fontSize: TypeSize.footnote, weight: FontWeight.w600, color: c.textSecondary),
        if (r.tickets > 0) Amount(currency: Currency.tickets, value: r.tickets, size: 14, fontSize: TypeSize.footnote, weight: FontWeight.w600, color: c.textSecondary),
        if (r.hints > 0) Amount(currency: Currency.hints, value: r.hints, size: 14, fontSize: TypeSize.footnote, weight: FontWeight.w600, color: c.textSecondary),
      ],
    );
  }
}

/// An unlock in a row of reward marks: cobalt icon and name.
class _UnlockMark extends StatelessWidget {
  const _UnlockMark({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: context.accent),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: context.accent),
        ),
      ],
    ),
  );
}

IconData _unlockIcon(Unlock u) => switch (u) {
      Unlock.painting => AppIcons.painting,
      Unlock.giant => AppIcons.bigBoard,
      _ => AppIcons.unlock,
    };

/// Month tile for the daily puzzle row: cover, name and the same progress
/// line and completion badges as the library cards.
class _MonthCard extends ConsumerWidget {
  const _MonthCard({required this.pack, required this.current, required this.onTap});
  final Pack pack;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(packProgressProvider(pack.id));
    return _CoverTile(
      pack: pack,
      progress: progress,
      chip: current ? const Chip2(label: 'This month', onImage: true, dot: Brand.live) : null,
      onTap: onTap,
    );
  }
}

/// Image-first tile for a live event pack, with the pack's progress.
class _EventPackCard extends ConsumerWidget {
  const _EventPackCard({required this.pack, required this.onTap});
  final Pack pack;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(packProgressProvider(pack.id));
    return _CoverTile(
      pack: pack,
      progress: progress,
      chip: Chip2(label: _endsIn(pack), onImage: true, dot: Brand.live),
      nameLines: 2,
      onTap: onTap,
    );
  }
}

/// "Ends in 3d" for an event pack's chip.
String _endsIn(Pack pack) {
  final end = pack.endAt;
  return end == null ? 'Live' : endsIn(end.difference(DateTime.now()));
}

/// Square cover tile shared by the Home event and month rows: picture with
/// a scrim, a status chip top left, the completion badges top right, and the
/// name over the pack's progress line.
class _CoverTile extends StatelessWidget {
  const _CoverTile({required this.pack, required this.progress, required this.onTap, this.chip, this.nameLines = 1});
  final Pack pack;
  final PackProgress progress;
  final Widget? chip;
  final int nameLines;
  final VoidCallback onTap;

  static const double size = 150;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: size,
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
            Positioned(
              left: 8,
              top: 8,
              right: 8,
              child: Row(
                children: [
                  // The chip yields to the badges on a narrow tile instead of overlapping them.
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: chip == null ? const SizedBox.shrink() : FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: chip),
                    ),
                  ),
                  if (progress.complete) ...[const SizedBox(width: 6), PackDoneBadges(progress: progress, size: 22)],
                ],
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pack.name, maxLines: nameLines, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: TypeSize.body, letterSpacing: -0.2, height: 1.15)),
                  const SizedBox(height: 6),
                  PackProgressLine(progress: progress, onImage: true, height: 4, fontSize: TypeSize.micro),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A board in progress as a square picture tile, the same shape as the pack
/// covers below it: the shape (when not cards) top left, the title on up to
/// two lines and the cards in place at the bottom.
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
    final mode = GameMode.fromCode(progress.mode);
    return Pressable(
      onTap: onTap,
      child: Container(
        width: _CoverTile.size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.boardBackground,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: c.stroke),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetImage(url: puzzle.thumbUrl, blurhash: puzzle.blurhash),
            DecoratedBox(decoration: BoxDecoration(gradient: Brand.scrim(strength: 0.8))),
            // The shape when it is not plain cards, and Painting: what the board will feel like.
            if (mode != GameMode.cards || progress.painting)
              Positioned(
                left: 8,
                top: 8,
                child: Chip2(label: [if (mode != GameMode.cards) mode.label, if (progress.painting) 'Painting'].join(' · '), onImage: true),
              ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(puzzle.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: TypeSize.body, letterSpacing: -0.2, height: 1.15)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: ProgressBar(value: total == 0 ? 0 : locked / total, height: 4, color: Colors.white, background: Colors.white.withValues(alpha: 0.3))),
                      const SizedBox(width: 6),
                      Text('$locked/$total', style: const TextStyle(color: Colors.white, fontSize: TypeSize.micro, fontWeight: FontWeight.w600)),
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

/// Share of a saved board's cards already in their place.
double _lockedShare(PuzzleProgress pr) {
  final layout = pr.layout;
  if (layout == null || layout.isEmpty) return 0;
  var locked = 0;
  for (var i = 0; i < layout.length; i++) {
    if (layout[i] == i) locked++;
  }
  return locked / layout.length;
}

/// The board in progress with the largest share of cards in place.
Puzzle _closestToDone(List<Puzzle> boards, Map<String, PuzzleProgress> progress) =>
    boards.reduce((a, b) => _lockedShare(progress[b.id]!) > _lockedShare(progress[a.id]!) ? b : a);

/// Continue: the board closest to done, in the shape of the Quick play card,
/// with how far along it is.
class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.puzzle, required this.progress, required this.others, required this.onTap});
  final Puzzle puzzle;
  final PuzzleProgress progress;
  final int others;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final share = _lockedShare(progress);
    return SoftCard(
      key: const ValueKey('home-resume'),
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      child: Row(
        children: [
          SizedBox(width: 52, height: 52, child: NetImage(url: puzzle.thumbUrl, blurhash: puzzle.blurhash, radius: 10)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(others > 0 ? 'Continue · ${others + 1} boards' : 'Continue',
                    style: TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w600, color: context.accent, letterSpacing: -0.1)),
                const SizedBox(height: 1),
                Text(puzzle.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: ProgressBar(value: share, height: 5)),
                    const SizedBox(width: 8),
                    Text('${(share * 100).round()}%', style: TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w600, color: c.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: context.accentFill, shape: BoxShape.circle),
            child: Icon(AppIcons.playFill, color: context.onAccent, size: 18),
          ),
        ],
      ),
    );
  }
}

final _quickPlayRandom = Random();

/// Quick play: one tap opens a random picture the player can play now on
/// its difficulty screen. It prefers pictures never played, then ones short
/// of three stars, then any (see [quickPlayPool]); the picture is drawn at
/// tap time. The mode and board of the player's last finished game are
/// preselected when that board is still open to them.
class _QuickPlayCard extends ConsumerWidget {
  const _QuickPlayCard();

  void _start(BuildContext context, WidgetRef ref) {
    final puzzle = pickQuickPlay(ref.read(quickPlayPoolProvider), _quickPlayRandom);
    if (puzzle == null) return;
    Haptics.light();
    final board = openQuickPlayBoard(ref.read(quickPlayBoardProvider), level: ref.read(profileProvider).value?.level ?? 1, hasTier: ref.read(profileProvider.notifier).hasTier);
    context.push(quickPlayRoute(puzzle, saved: ref.read(progressProvider).value?[puzzle.id], board: board));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final pool = ref.watch(quickPlayPoolProvider);
    final status = switch (pool?.tier) {
      QuickPlayTier.fresh => 'A picture you have not played yet',
      QuickPlayTier.improve => 'A picture still short of 3 stars',
      QuickPlayTier.any => 'A random picture to replay',
      null => ref.exists(catalogProvider) && ref.watch(catalogProvider.select((v) => v.hasError && !v.hasValue)) ? 'Pictures could not load' : 'Loading pictures…',
    };
    return SoftCard(
      key: const ValueKey('home-quick-play'),
      onTap: pool == null ? null : () => _start(context, ref),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          const IconTile(icon: AppIcons.shuffle, size: IconTile.medium),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Quick play', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Greyed until there are pictures to pick from.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: pool == null ? c.stroke : context.accentFill, shape: BoxShape.circle),
            child: Icon(AppIcons.playFill, color: pool == null ? c.textTertiary : context.onAccent, size: 18),
          ),
        ],
      ),
    );
  }
}

/// Horizontal row of pack covers with each pack's progress line (Packs in
/// progress, Missing stars). Event packs keep their "Ends in" chip.
class _PackCoverRow extends StatelessWidget {
  const _PackCoverRow({super.key, required this.packs, required this.progressOf});
  final List<Pack> packs;
  final PackProgress Function(Pack pack) progressOf;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _CoverTile.size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        physics: const BouncingScrollPhysics(),
        itemCount: packs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final pack = packs[i];
          return _CoverTile(
            pack: pack,
            progress: progressOf(pack),
            chip: pack.hasWindow && pack.isLive ? Chip2(label: _endsIn(pack), onImage: true, dot: Brand.live) : null,
            nameLines: 2,
            onTap: () => context.push('/library/pack/${pack.id}'),
          );
        },
      ),
    );
  }
}

/// Finished packs: the totals, then the most recently finished packs as
/// compact rows. "See all" in the section header opens the Library on
/// Finished.
class _FinishedPacksCard extends StatelessWidget {
  const _FinishedPacksCard({required this.rows, required this.progressOf});
  final HomePackRows rows;
  final PackProgress Function(Pack pack) progressOf;

  /// Rows shown on Home; the rest are in the Library.
  static const shown = 3;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = rows.stats;
    final list = rows.finished.take(shown).toList();
    return SoftCard(
      key: const ValueKey('home-finished-packs'),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Three equal cells split by hairlines; labels may wrap to a second line instead of
          // being cut ("With every st...") on a small screen or with larger text.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _StatCell(value: s.packs, label: s.packs == 1 ? 'Pack finished' : 'Packs finished')),
                VerticalDivider(width: 1, thickness: 1, indent: 14, endIndent: 14, color: c.stroke),
                Expanded(child: _StatCell(value: s.perfect, label: 'With every star', star: true)),
                VerticalDivider(width: 1, thickness: 1, indent: 14, endIndent: 14, color: c.stroke),
                Expanded(child: _StatCell(value: s.pictures, label: 'Pictures solved')),
              ],
            ),
          ),
          for (final pack in list) ...[
            Divider(height: 1, color: c.stroke, indent: pack == list.first ? 0 : 76),
            _FinishedRow(pack: pack, progress: progressOf(pack)),
          ],
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label, this.star = false});
  final int value;
  final String label;
  final bool star;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(formatCount(value), style: Theme.of(context).textTheme.titleLarge),
              if (star) ...[const SizedBox(width: 4), const Icon(AppIcons.star, size: 14, color: Brand.star)],
            ],
          ),
          const SizedBox(height: 2),
          Text(label, maxLines: 2, textAlign: TextAlign.center, style: TextStyle(fontSize: TypeSize.caption, height: 1.2, fontWeight: FontWeight.w500, color: c.textSecondary)),
        ],
      ),
    );
  }
}

/// One finished pack: cover with the done badges, name, star progress line.
class _FinishedRow extends StatelessWidget {
  const _FinishedRow({required this.pack, required this.progress});
  final Pack pack;
  final PackProgress progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: () => context.push('/library/pack/${pack.id}'),
      scale: 0.99,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: NetImage(url: pack.coverUrl, radius: 10, blurhash: pack.blurhash),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(pack.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.body)),
                      ),
                      const SizedBox(width: 6),
                      PackDoneBadges(progress: progress, size: 16),
                    ],
                  ),
                  const SizedBox(height: 6),
                  PackProgressLine(progress: progress, height: 4),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(AppIcons.chevronRight, size: 16, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}
