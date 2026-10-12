import '../../state/achievements.dart';

/// Where an achievement card belongs in a list.
enum AchievementStage {
  /// A reward is waiting: listed first.
  claimable,

  /// Working towards the next tier.
  inProgress,

  /// Every tier claimed: listed last.
  complete,
}

AchievementStage achievementStage(AchievementStatus s) {
  if (s.done) return AchievementStage.claimable;
  if (s.allClaimed) return AchievementStage.complete;
  return AchievementStage.inProgress;
}

/// Display order of achievement families, as family ids: claimable first,
/// then in progress (closest to its next tier first), then fully claimed.
/// Ties keep the catalogue order, so the result is stable.
///
/// Screens compute this once when the list is opened and keep it while the
/// player is there (see [applyAchievementOrder]), so claiming a reward never
/// moves the card away from under the finger.
List<String> achievementOrder(List<AchievementStatus> statuses) {
  final position = {for (var i = 0; i < statuses.length; i++) statuses[i].family.id: i};
  double ratio(AchievementStatus s) => s.target <= 0 ? 0 : (s.progress / s.target).clamp(0.0, 1.0);
  final sorted = [...statuses]
    ..sort((a, b) {
      final byStage = achievementStage(a).index.compareTo(achievementStage(b).index);
      if (byStage != 0) return byStage;
      if (achievementStage(a) == AchievementStage.inProgress) {
        final byRatio = ratio(b).compareTo(ratio(a));
        if (byRatio != 0) return byRatio;
      }
      return position[a.family.id]!.compareTo(position[b.family.id]!);
    });
  return [for (final s in sorted) s.family.id];
}

/// Lays the live statuses out in a previously computed [order]: each card
/// keeps its place and only its content updates (next tier, or Done).
/// Families missing from [order] follow at the end in their live order.
List<AchievementStatus> applyAchievementOrder(List<AchievementStatus> live, List<String> order) {
  final byId = {for (final s in live) s.family.id: s};
  final placed = <AchievementStatus>[for (final id in order) ?byId.remove(id)];
  return [...placed, ...live.where((s) => byId.containsKey(s.family.id))];
}
