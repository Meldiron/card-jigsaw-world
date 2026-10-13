import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/rewards.dart';
import '../../state/social.dart';
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

/// The Quests tab dot: a daily or weekly quest or a live event has a reward
/// waiting to be claimed (the same rules as the Claim buttons on the tab).
final questRewardReadyProvider = Provider<bool>((ref) {
  final profile = ref.watch(profileProvider).value;
  if (profile == null) return false;
  final progress = (ref.watch(progressProvider).value ?? const <String, PuzzleProgress>{}).values;
  final now = DateTime.now();
  if (anyGoalReady(Goals.daily(progress, now), Goals.dailyFree, profile)) return true;
  if (anyGoalReady(Goals.weekly(progress, now), Goals.weeklyFree, profile)) return true;
  final claims = ref.watch(eventProgressProvider).value ?? const <String, EventProgress>{};
  for (final event in ref.watch(eventsProvider).value ?? const <GameEvent>[]) {
    if (!event.isActive) continue;
    final row = claims[event.id];
    if (row?.claimed ?? false) continue;
    final packId = event.packId;
    final pack = packId == null || packId.isEmpty ? null : ref.watch(eventPackProgressProvider(packId));
    final (value, target) = eventProgressOf(pack, event, row);
    if (target > 0 && value >= target) return true;
  }
  return false;
});
