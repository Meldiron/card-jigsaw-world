import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/numbers.dart';
import '../../data/repositories.dart';
import '../../models/models.dart';
import '../../state/auth.dart';
import '../../state/catalog.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/rewards.dart';
import '../../state/social.dart';
import '../../state/unlocks.dart';
import '../gallery/pack_progress.dart';

/// A quest the player cannot claim without VIP (the extra daily and weekly
/// quest). Once claimed it stays shown as claimed.
bool goalLocked(Goal goal, int index, int freeCount, Profile? profile) {
  final claimed = profile?.claimedGoals.contains(goal.key) ?? false;
  return (goal.vipOnly || index >= freeCount) && !(profile?.isVip ?? false) && !claimed;
}

/// A finished quest the player can claim now: done, not claimed, not locked.
bool goalReady(Goal goal, int index, int freeCount, Profile? profile) =>
    goal.done && !(profile?.claimedGoals.contains(goal.key) ?? false) && !goalLocked(goal, index, freeCount, profile);

/// Whether any quest in [goals] is ready to claim (see [goalReady]).
bool anyGoalReady(List<Goal> goals, int freeCount, Profile? profile) {
  for (var i = 0; i < goals.length; i++) {
    if (goalReady(goals[i], i, freeCount, profile)) return true;
  }
  return false;
}

/// Today's daily and this week's weekly quests for [profile]: only what
/// [open] allows, and a slot keeps the quest already claimed in it.
/// [dailyPuzzle] is today's daily puzzle (`dailyPuzzleProvider`).
({List<Goal> daily, List<Goal> weekly}) questsFor(Iterable<PuzzleProgress> rows, Profile? profile, OpenFeatures open, DateTime now, {String? dailyPuzzle}) {
  final claimed = profile?.claimedGoals.toSet() ?? const <String>{};
  final level = profile?.level ?? 1;
  return (
    daily: Goals.daily(rows, now, open: open, level: level, claimed: claimed, dailyPuzzle: dailyPuzzle),
    weekly: Goals.weekly(rows, now, open: open, level: level, claimed: claimed),
  );
}

/// The quests ready to claim now, daily ones first.
List<Goal> readyGoals(Iterable<PuzzleProgress> rows, Profile? profile, OpenFeatures open, DateTime now, {String? dailyPuzzle}) {
  final q = questsFor(rows, profile, open, now, dailyPuzzle: dailyPuzzle);
  return [
    for (var i = 0; i < q.daily.length; i++)
      if (goalReady(q.daily[i], i, Goals.dailyFree, profile)) q.daily[i],
    for (var i = 0; i < q.weekly.length; i++)
      if (goalReady(q.weekly[i], i, Goals.weeklyFree, profile)) q.weekly[i],
  ];
}

/// Progress of an event's pack, or null when the event has no pack (a
/// community goal) or the pack's pictures are not in the catalogue.
final eventPackProgressProvider = Provider.family<PackProgress?, String>((ref, packId) {
  final pictures = ref.watch(packPuzzlesProvider(packId)).value ?? const <Puzzle>[];
  if (pictures.isEmpty) return null;
  return ref.watch(packProgressProvider(packId));
});

/// How far the player is with [event]: (value, target). A pack event asks
/// for every picture of its pack; other events use the backend counter.
(int, int) eventProgressOf(PackProgress? pack, GameEvent event, EventProgress? progress) =>
    pack != null ? (pack.solved, pack.total) : (progress?.progress ?? 0, event.goal);

/// Live events whose reward waits to be claimed, with the progress value the
/// claim records.
final readyEventsProvider = Provider<List<({GameEvent event, int value})>>((ref) {
  final claims = ref.watch(eventProgressProvider).value ?? const <String, EventProgress>{};
  final out = <({GameEvent event, int value})>[];
  for (final event in ref.watch(eventsProvider).value ?? const <GameEvent>[]) {
    if (!event.isActive) continue;
    final row = claims[event.id];
    if (row?.claimed ?? false) continue;
    final packId = event.packId;
    final pack = packId == null || packId.isEmpty ? null : ref.watch(eventPackProgressProvider(packId));
    final (value, target) = eventProgressOf(pack, event, row);
    if (target > 0 && value >= target) out.add((event: event, value: value));
  }
  return out;
});

/// Pays an event's reward and marks it claimed. False without a player.
Future<bool> claimEventReward(WidgetRef ref, GameEvent event, int value) async {
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) return false;
  final n = ref.read(profileProvider.notifier);
  await n.addCoins(event.rewardCoins, reason: 'event:${event.id}');
  if (event.rewardTickets > 0) await n.addTickets(event.rewardTickets, reason: 'event:${event.id}');
  await ref.read(socialRepositoryProvider).upsertEventProgress(userId, event.id, progress: value, claimed: true);
  ref.invalidate(eventProgressProvider);
  return true;
}

/// "Claimed 140 coins and 2 tickets".
String claimedLine(int coins, int tickets) {
  final parts = [
    if (coins > 0) countOf(coins, 'coin'),
    if (tickets > 0) countOf(tickets, 'ticket'),
  ];
  return parts.isEmpty ? 'Claimed' : 'Claimed ${parts.join(' and ')}';
}

/// The Quests tab dot: a daily or weekly quest or a live event has a reward
/// waiting to be claimed (the same rules as the Claim buttons on the tab).
final questRewardReadyProvider = Provider<bool>((ref) {
  final profile = ref.watch(profileProvider).value;
  if (profile == null) return false;
  final progress = (ref.watch(progressProvider).value ?? const <String, PuzzleProgress>{}).values;
  if (readyGoals(progress, profile, ref.watch(openFeaturesProvider), DateTime.now(), dailyPuzzle: ref.watch(dailyPuzzleProvider)?.id).isNotEmpty) return true;
  return ref.watch(readyEventsProvider).isNotEmpty;
});
