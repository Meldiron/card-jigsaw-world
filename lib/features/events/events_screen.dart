import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories.dart';
import '../../models/models.dart';
import '../../state/auth.dart';
import '../../state/catalog.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/rewards.dart';
import '../../state/social.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../home/header_bar.dart';

/// Quests tab: daily quests, weekly quests, then live events.
class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
  /// Ticks the "Resets in" chips (and re-rolls the quests at midnight).
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(eventsProvider);
    final eventProgress = ref.watch(eventProgressProvider).value ?? {};
    final progress = ref.watch(progressProvider).value ?? {};
    final now = DateTime.now();
    final daily = Goals.daily(progress.values, now);
    final weekly = Goals.weekly(progress.values, now);

    return Scaffold(
      body: RefreshIndicator.adaptive(
        edgeOffset: MediaQuery.paddingOf(context).top + HeaderBar.height,
        onRefresh: () async {
          ref.invalidate(eventsProvider);
          ref.invalidate(eventProgressProvider);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            const HeaderBar(title: 'Quests'),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Text('Quests', style: Theme.of(context).textTheme.headlineLarge),
              ),
            ),
            SliverToBoxAdapter(
              child: SectionHeader(
                title: 'Daily quests',
                subtitle: 'Coins · new every day',
                trailing: _ResetsIn(at: Goals.nextDailyReset(now), now: now),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              ),
            ),
            SliverToBoxAdapter(child: _GoalList(goals: daily, freeCount: Goals.dailyFree)),
            SliverToBoxAdapter(
              child: SectionHeader(title: 'Weekly quests', subtitle: 'Tickets · new every week', trailing: _ResetsIn(at: Goals.nextWeeklyReset(now), now: now)),
            ),
            SliverToBoxAdapter(child: _GoalList(goals: weekly, freeCount: Goals.weeklyFree)),
            const SliverToBoxAdapter(child: SectionHeader(title: 'Live events', subtitle: 'World-day events, one week each')),
            events.when(
              loading: () => const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Loader())),
              error: (e, _) => const SliverToBoxAdapter(child: EmptyState(icon: AppIcons.signal, title: 'Events could not load', message: 'Check your connection and pull to refresh.')),
              data: (list) {
                final active = list.where((e) => e.isActive).toList();
                final upcoming = list.where((e) => e.isUpcoming).toList()..sort((a, b) => a.startAt!.compareTo(b.startAt!));
                if (active.isEmpty && upcoming.isEmpty) {
                  return const SliverToBoxAdapter(
                    child: EmptyState(icon: AppIcons.balloon, title: 'No events this week', message: 'New world-day events open every few days.'),
                  );
                }
                return SliverList(
                  delegate: SliverChildListDelegate([
                    for (var i = 0; i < active.length; i++)
                      Padding(
                        padding: EdgeInsets.fromLTRB(20, i == 0 ? 0 : 12, 20, 0),
                        child: _EventCard(event: active[i], progress: eventProgress[active[i].id]).animate().fadeIn(delay: (50 * i).ms),
                      ),
                    if (active.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: SoftCard(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Text('Nothing live right now. The next event opens soon.', style: TextStyle(color: context.colors.textSecondary, fontSize: 13.5)),
                        ),
                      ),
                    if (upcoming.isNotEmpty) ...[
                      const SectionHeader(title: 'Coming up', subtitle: 'Opens three days before the day'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: SoftCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              for (var i = 0; i < upcoming.length; i++) ...[
                                _UpcomingRow(event: upcoming[i]),
                                if (i < upcoming.length - 1) Divider(height: 1, color: context.colors.stroke, indent: 76),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ]),
                );
              },
            ),
            SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24)),
          ],
        ),
      ),
    );
  }
}

/// "Resets in 5h 12m" chip next to a quest section header.
class _ResetsIn extends StatelessWidget {
  const _ResetsIn({required this.at, required this.now});
  final DateTime at;
  final DateTime now;

  @override
  Widget build(BuildContext context) => Chip2(label: 'Resets in ${Goals.formatLeft(at.difference(now))}', icon: AppIcons.time);
}

class _GoalList extends ConsumerWidget {
  const _GoalList({required this.goals, required this.freeCount});
  final List<Goal> goals;
  /// Quests past this index are VIP-only: locked cards for everyone else.
  final int freeCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final profile = ref.watch(profileProvider).value;
    final isVip = profile?.isVip ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SoftCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < goals.length; i++) ...[
              () {
                final claimed = profile?.claimedGoals.contains(goals[i].key) ?? false;
                final locked = (goals[i].vipOnly || i >= freeCount) && !isVip && !claimed;
                return locked ? _VipGoalRow(goal: goals[i]) : _GoalRow(goal: goals[i], claimed: claimed);
              }(),
              if (i < goals.length - 1) Divider(height: 1, color: c.stroke, indent: 16),
            ],
          ],
        ),
      ),
    );
  }
}

/// The extra quest non-VIP players see: locked, labelled VIP, opens the
/// Store's VIP card.
class _VipGoalRow extends StatelessWidget {
  const _VipGoalRow({required this.goal});
  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reward = goal.coins > 0
        ? Amount(currency: Currency.coins, value: goal.coins, prefix: '+', size: 14, fontSize: 12.5, color: c.textTertiary)
        : Amount(currency: Currency.tickets, value: goal.tickets, prefix: '+', size: 14, fontSize: 12.5, color: c.textTertiary);
    return Pressable(
      onTap: () => context.push('/store?vip=1'),
      scale: 0.99,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
        child: Row(
          children: [
            Icon(AppIcons.lock, size: 16, color: c.textTertiary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(goal.title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: c.textSecondary)),
                  const SizedBox(height: 4),
                  Text('Extra quest for VIP members', style: TextStyle(fontSize: 12, color: c.textTertiary)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                reward,
                const SizedBox(height: 6),
                const Chip2(label: 'VIP', icon: AppIcons.vip, color: Brand.coin, foreground: Color(0xFF2A1F00)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalRow extends ConsumerWidget {
  const _GoalRow({required this.goal, required this.claimed});
  final Goal goal;
  final bool claimed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    Future<void> claim() async {
      final ok = await ref.read(profileProvider.notifier).claimGoal(goal);
      if (!context.mounted || !ok) return;
      Sfx.instance.coin();
      Haptics.success();
      final what = goal.coins > 0 ? '${goal.coins} coins' : '${goal.tickets} ticket${goal.tickets == 1 ? '' : 's'}';
      showToast(context, 'Claimed $what', icon: AppIcons.check);
    }

    void play() {
      final p = pickRandomPlayable(ref);
      if (p != null) {
        context.push('/play/${p.id}?${goal.minCells >= 25 ? 'grid=5x5' : 'grid='}${goal.mode != null ? '&mode=${goal.mode!.code}' : ''}');
      } else {
        showToast(context, 'Unlock a pack to start playing', icon: AppIcons.lock);
      }
    }

    final reward = goal.coins > 0
        ? Amount(currency: Currency.coins, value: goal.coins, prefix: '+', size: 14, fontSize: 12.5)
        : Amount(currency: Currency.tickets, value: goal.tickets, prefix: '+', size: 14, fontSize: 12.5);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(goal.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(child: ProgressBar(value: goal.progress / goal.target, height: 6, color: goal.done ? c.success : null)),
                    const SizedBox(width: 8),
                    Text('${goal.progress.clamp(0, goal.target)}/${goal.target}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              reward,
              const SizedBox(height: 6),
              if (claimed)
                Icon(CupertinoIcons.checkmark_circle_fill, color: c.success, size: 22)
              else if (goal.done)
                BigButton(label: 'Claim', height: 34, expand: false, onTap: claim)
              else
                BigButton(label: 'Play', kind: ButtonKind.secondary, height: 34, expand: false, onTap: play),
            ],
          ),
        ],
      ),
    );
  }
}

class _EventCard extends ConsumerWidget {
  const _EventCard({required this.event, required this.progress});
  final GameEvent event;
  final EventProgress? progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    // A pack event asks for every picture in its pack (N of N). The counts
    // come from the catalog and the player's own progress rows; the backend
    // counter is the fallback for events without a pack (community goals).
    final packId = event.packId;
    final packPuzzles = packId == null || packId.isEmpty ? const <Puzzle>[] : (ref.watch(packPuzzlesProvider(packId)).value ?? const <Puzzle>[]);
    final isPackQuest = packPuzzles.isNotEmpty;
    final solved = ref.watch(progressProvider).value ?? const <String, PuzzleProgress>{};
    final target = isPackQuest ? packPuzzles.length : event.goal;
    final value = isPackQuest ? packPuzzles.where((p) => solved[p.id]?.completed == true).length : (progress?.progress ?? 0);
    final done = value >= target;
    final claimed = progress?.claimed ?? false;
    final description = isPackQuest ? 'Finish all $target pictures in the ${event.name} pack while the event is live.' : event.description;
    final left = event.timeLeft;
    final leftLabel = left.inDays > 0 ? 'Ends in ${left.inDays}d' : 'Ends in ${left.inHours}h';
    final community = event.type == EventType.social ? ref.watch(communityProgressProvider(event.id)).value : null;

    Future<void> claim() async {
      final userId = ref.read(currentUserIdProvider);
      if (userId == null) return;
      final n = ref.read(profileProvider.notifier);
      await n.addCoins(event.rewardCoins, reason: 'event:${event.id}');
      if (event.rewardTickets > 0) await n.addTickets(event.rewardTickets, reason: 'event:${event.id}');
      await ref.read(socialRepositoryProvider).upsertEventProgress(userId, event.id, progress: value, claimed: true);
      ref.invalidate(eventProgressProvider);
      if (!context.mounted) return;
      Sfx.instance.win();
      Haptics.success();
      showToast(context, 'Claimed ${event.rewardCoins} coins${event.rewardTickets > 0 ? ' and ${event.rewardTickets} ticket${event.rewardTickets == 1 ? '' : 's'}' : ''}', icon: AppIcons.check);
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(Radii.lg), border: Border.all(color: c.stroke)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 150,
            child: Stack(
              fit: StackFit.expand,
              children: [
                NetImage(url: event.coverUrl, blurhash: _coverHash(ref, event)),
                DecoratedBox(decoration: BoxDecoration(gradient: Brand.scrim(strength: 0.7))),
                Positioned(
                  left: 14,
                  top: 12,
                  child: Chip2(label: leftLabel, icon: AppIcons.eventType(event.type), onImage: true),
                ),
                Positioned(
                  left: 16,
                  bottom: 12,
                  right: 16,
                  child: Text(event.name, style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description, style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: ProgressBar(value: target == 0 ? 0 : value / target, height: 8, color: done ? c.success : null)),
                    const SizedBox(width: 10),
                    Text('$value / $target', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ),
                if (community != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(AppIcons.community, size: 14, color: c.textSecondary),
                      const SizedBox(width: 6),
                      Text('$community puzzles solved by everyone', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.textSecondary)),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Amount(currency: Currency.coins, value: event.rewardCoins, size: 16, fontSize: 13),
                    if (event.rewardTickets > 0) ...[
                      const SizedBox(width: 12),
                      Amount(currency: Currency.tickets, value: event.rewardTickets, size: 16, fontSize: 13),
                    ],
                    const Spacer(),
                    if (claimed)
                      Row(children: [Icon(CupertinoIcons.checkmark_circle_fill, color: c.success, size: 18), const SizedBox(width: 4), const Text('Claimed', style: TextStyle(fontWeight: FontWeight.w600))])
                    else if (done)
                      BigButton(label: 'Claim', expand: false, height: 38, onTap: claim)
                    else
                      BigButton(
                        label: event.packId != null ? 'Play pack' : 'Play',
                        kind: ButtonKind.secondary,
                        expand: false,
                        height: 38,
                        onTap: () => event.packId != null ? context.go('/library/pack/${event.packId}') : context.go('/library'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


/// Compact row for an event that opens within the next three days.
class _UpcomingRow extends ConsumerWidget {
  const _UpcomingRow({required this.event});
  final GameEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final d = event.startsIn;
    final opens = d.inDays > 0 ? 'Opens in ${d.inDays}d ${d.inHours % 24}h' : 'Opens in ${d.inHours}h ${d.inMinutes % 60}m';
    return Pressable(
      onTap: event.packId == null ? null : () => context.go('/library/pack/${event.packId}'),
      scale: 0.99,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        child: Row(
          children: [
            SizedBox(width: 52, height: 52, child: NetImage(url: event.coverUrl, radius: 10, blurhash: _coverHash(ref, event))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(event.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Chip2(label: opens, icon: AppIcons.time),
          ],
        ),
      ),
    );
  }
}


/// The event cover is its pack cover, so reuse the pack's BlurHash.
String? _coverHash(WidgetRef ref, GameEvent event) {
  final packs = ref.read(packsProvider).value ?? const <Pack>[];
  for (final p in packs) {
    if (p.id == event.packId) return p.blurhash;
  }
  return null;
}
