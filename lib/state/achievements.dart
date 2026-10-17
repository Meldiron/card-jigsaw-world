import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/numbers.dart';
import '../game/board.dart';
import '../models/models.dart';
import '../widgets/icons.dart';
import 'first_steps.dart';
import 'profile.dart';
import 'progress.dart';
import 'social.dart';

/// One claimable step of an achievement family.
class AchievementStep {
  const AchievementStep(this.threshold, {this.coins = 0, this.tickets = 0, this.avatarKey});
  final int threshold;
  final int coins;
  final int tickets;
  /// Avatar granted on claim, e.g. `solver@2`.
  final String? avatarKey;
}

/// An achievement with one or more steps. Multi-step families grant the same
/// avatar family upgraded per step.
class AchievementFamily {
  const AchievementFamily({
    required this.id,
    required this.title,
    required this.icon,
    required this.describe,
    required this.steps,
    required this.progress,
  });
  final String id;
  final String title;
  final IconData icon;
  /// Description for a step, given its threshold.
  final String Function(int threshold) describe;
  final List<AchievementStep> steps;
  final int Function(AchievementFacts f) progress;
}

class AchievementStatus {
  const AchievementStatus({required this.family, required this.stepIndex, required this.progress, required this.claimedSteps});
  final AchievementFamily family;
  /// Index of the next unclaimed step; equals steps.length when all claimed.
  final int stepIndex;
  final int progress;
  final int claimedSteps;

  bool get allClaimed => stepIndex >= family.steps.length;
  AchievementStep? get step => allClaimed ? null : family.steps[stepIndex];
  int get target => step?.threshold ?? family.steps.last.threshold;
  bool get done => !allClaimed && progress >= target;
  String get stepKey => '${family.id}:${stepIndex + 1}';
  String get description => family.describe(target);
}

/// Derived numbers every family reads from.
///
/// How a picture was played (shape, size, hints, time, the hour) comes from its finished boards
/// ([PuzzleProgress.finishes]), each with its own values, never from the row's board fields, which
/// a replay overwrites as soon as it is saved: a picture counts once for a family when one of its
/// boards does what the family asks, so a replay in another shape or size never moves a count back.
/// Rows from older builds read through the same fallbacks as the quests (their last finish on the
/// board fields until a board is saved over them).
class AchievementFacts {
  AchievementFacts(this.profile, this.done, this.friends, {this.starsFromPictures = false, DateTime? since})
      : _boards = {
          for (final p in done) p.puzzleId: [for (final b in p.finishes) if (since == null || b.at.isAfter(since)) b],
        };
  final Profile profile;
  final List<PuzzleProgress> done;
  final int friends;

  /// Each solved picture's finished boards that count ([since]: the guided start counts only those
  /// after achievements opened).
  final Map<String, List<BoardFinish>> _boards;

  /// Stars collected: the profile's total, or (guided start) the stars of [done] only.
  final bool starsFromPictures;
  late final int stars = starsFromPictures ? done.fold<int>(0, (s, p) => s + p.stars) : profile.totalStars;

  List<BoardFinish> _of(PuzzleProgress p) => _boards[p.puzzleId] ?? const [];

  /// Pictures with a finished board, its values known, that passes [test].
  int _pictures(bool Function(BoardFinish b) test) => done.where((p) => _of(p).any((b) => b.known && test(b))).length;

  /// Pictures with a board finished at a time that passes [test] (the time is known also when the
  /// values are not).
  int _finishedAt(bool Function(BoardFinish b) test) => done.where((p) => _of(p).any(test)).length;

  late final int perfect = done.where((p) => p.stars == 3).length;
  late final int noHints = _pictures((b) => b.hints == 0);
  late final int big = _pictures((b) => b.gridSize >= 36);
  late final int master = _pictures((b) => b.gridSize >= GridSpec.tiers.last.cells);
  late final int packs = {for (final p in done) p.puzzleId.replaceAll(RegExp(r'-\d+$'), '')}.length;
  late final int daily = done.where((p) => p.puzzleId.startsWith('daily-')).length;
  late final int events = done.where((p) => p.puzzleId.startsWith('evpack-')).length;
  late final int nightOwl = _finishedAt((b) => b.atNight);
  late final int earlyBird = _finishedAt((b) => b.early);
  late final int speed = _pictures((b) => b.quick);

  /// The most pictures finished on one day (a picture counts on every day one of its boards was
  /// finished).
  late final int marathon = () {
    final byDay = <String, Set<String>>{};
    for (final p in done) {
      for (final b in _of(p)) {
        (byDay['${b.at.year}-${b.at.month}-${b.at.day}'] ??= {}).add(p.puzzleId);
      }
    }
    return byDay.values.fold<int>(0, (m, v) => v.length > m ? v.length : m);
  }();
  late final int modes = {
    for (final p in done)
      for (final b in _of(p))
        if (b.known) b.mode,
  }.length;
  int mode(GameMode m) => _pictures((b) => b.mode == m.code);
}

List<AchievementStep> _tiered(List<int> thresholds, String avatar, {int coins = 100, int tickets = 0}) => [
      for (var i = 0; i < thresholds.length; i++)
        AchievementStep(thresholds[i], coins: coins * (i + 1), tickets: i >= 2 ? tickets + 1 : tickets, avatarKey: '$avatar@${i + 1}'),
    ];

final achievementFamilies = <AchievementFamily>[
  AchievementFamily(id: 'solver', title: 'Solver', icon: AppIcons.puzzle, describe: (t) => 'Solve $t puzzle${t == 1 ? '' : 's'}', steps: _tiered([1, 10, 50, 200, 500], 'solver', coins: 60), progress: (f) => f.done.length),
  AchievementFamily(id: 'perfect', title: 'Perfectionist', icon: AppIcons.star, describe: (t) => 'Earn 3 stars on $t puzzles', steps: _tiered([5, 25, 100], 'perfect', coins: 120), progress: (f) => f.perfect),
  AchievementFamily(id: 'streak', title: 'On a roll', icon: AppIcons.streak, describe: (t) => 'Reach a $t-day streak', steps: _tiered([7, 30, 100], 'flame', coins: 150, tickets: 1), progress: (f) => f.profile.longestStreak),
  AchievementFamily(id: 'level', title: 'Veteran', icon: AppIcons.level, describe: (t) => 'Reach level $t', steps: _tiered([5, 10, 20, 35, 50], 'medal', coins: 200, tickets: 1), progress: (f) => f.profile.level),
  AchievementFamily(id: 'cards', title: 'Card Sharp', icon: AppIcons.modeCards, describe: (t) => 'Finish $t Cards boards', steps: _tiered([10, 50], 'cards', coins: 100), progress: (f) => f.mode(GameMode.cards)),
  AchievementFamily(id: 'squares', title: 'Square Deal', icon: AppIcons.modeSquares, describe: (t) => 'Finish $t Squares boards', steps: _tiered([10, 50], 'square', coins: 110), progress: (f) => f.mode(GameMode.squares)),
  AchievementFamily(id: 'triangles', title: 'Triangulate', icon: AppIcons.modeTriangles, describe: (t) => 'Finish $t Triangles boards', steps: _tiered([10, 50], 'triangle', coins: 130), progress: (f) => f.mode(GameMode.triangles)),
  AchievementFamily(id: 'hexagons', title: 'Honeycomb', icon: AppIcons.modeHexagons, describe: (t) => 'Finish $t Hexagons boards', steps: _tiered([10, 50], 'hex', coins: 150), progress: (f) => f.mode(GameMode.hexagons)),
  AchievementFamily(id: 'big', title: 'Big Boards', icon: AppIcons.bigBoard, describe: (t) => 'Finish $t boards of 6x6 or bigger', steps: _tiered([5, 25], 'grid', coins: 150), progress: (f) => f.big),
  AchievementFamily(id: 'master', title: 'Master', icon: AppIcons.crown, describe: (t) => 'Finish $t Master board${t == 1 ? '' : 's'}', steps: _tiered([1, 10], 'crown', coins: 250, tickets: 1), progress: (f) => f.master),
  AchievementFamily(id: 'nohints', title: 'Unassisted', icon: AppIcons.noHints, describe: (t) => 'Finish $t puzzles without hints', steps: _tiered([10, 50], 'mind', coins: 120), progress: (f) => f.noHints),
  AchievementFamily(id: 'collector', title: 'Collector', icon: AppIcons.collector, describe: (t) => 'Solve a puzzle in $t different packs', steps: _tiered([3, 10, 30], 'album', coins: 100), progress: (f) => f.packs),
  AchievementFamily(id: 'daily', title: 'Daily Devotee', icon: AppIcons.dailyPuzzle, describe: (t) => 'Solve $t daily puzzles', steps: _tiered([7, 30, 100], 'calendar', coins: 100, tickets: 1), progress: (f) => f.daily),
  AchievementFamily(id: 'events', title: 'Event Goer', icon: AppIcons.events, describe: (t) => 'Solve $t event puzzles', steps: _tiered([5, 25], 'ticket', coins: 120, tickets: 1), progress: (f) => f.events),
  AchievementFamily(id: 'nightowl', title: 'Night Owl', icon: AppIcons.nightOwl, describe: (t) => 'Solve $t puzzles between 22:00 and 05:00', steps: const [AchievementStep(10, coins: 150, avatarKey: 'owl')], progress: (f) => f.nightOwl),
  AchievementFamily(id: 'earlybird', title: 'Early Bird', icon: AppIcons.earlyBird, describe: (t) => 'Solve $t puzzles between 05:00 and 08:00', steps: const [AchievementStep(10, coins: 150, avatarKey: 'bird')], progress: (f) => f.earlyBird),
  AchievementFamily(id: 'speed', title: 'Quick Hands', icon: AppIcons.speed, describe: (t) => 'Finish $t puzzles in under 4 seconds per card', steps: _tiered([10, 50], 'speed', coins: 120), progress: (f) => f.speed),
  AchievementFamily(id: 'marathon', title: 'Marathon', icon: AppIcons.marathon, describe: (t) => 'Solve $t puzzles in one day', steps: _tiered([10, 25], 'marathon', coins: 200), progress: (f) => f.marathon),
  AchievementFamily(id: 'allmodes', title: 'All Shapes', icon: AppIcons.allModes, describe: (t) => 'Finish a board in every mode', steps: [AchievementStep(GameMode.values.length, coins: 200, tickets: 1, avatarKey: 'shapes')], progress: (f) => f.modes),
  AchievementFamily(id: 'starhoarder', title: 'Star Hoarder', icon: AppIcons.starHoarder, describe: (t) => 'Collect $t stars', steps: _tiered([50, 250, 1000], 'stars', coins: 150), progress: (f) => f.stars),
  AchievementFamily(id: 'rich', title: 'Well Off', icon: AppIcons.piggy, describe: (t) => 'Hold ${formatCount(t)} coins at once', steps: const [AchievementStep(5000, tickets: 2, avatarKey: 'vault')], progress: (f) => f.profile.coins),
  AchievementFamily(id: 'vip', title: 'VIP member', icon: AppIcons.vip, describe: (t) => 'Join VIP', steps: const [AchievementStep(1, coins: 300, avatarKey: 'vip')], progress: (f) => f.profile.isVip ? 1 : 0),
  AchievementFamily(id: 'social', title: 'Good Company', icon: AppIcons.friends, describe: (t) => 'Add $t friend${t == 1 ? '' : 's'}', steps: _tiered([1, 5], 'friends', coins: 100), progress: (f) => f.friends),
  AchievementFamily(id: 'piggy', title: 'Piggy Breaker', icon: AppIcons.piggy, describe: (t) => 'Fill the piggy bank to ${formatCount(t)} coins', steps: const [AchievementStep(Profile.basePiggyCapacity, coins: 100)], progress: (f) => f.profile.piggyCoins),
];

/// Live status of every family, from the profile and progress rows.
final achievementsProvider = Provider<List<AchievementStatus>>((ref) {
  final profile = ref.watch(profileProvider).value ?? Profile.guest('local');
  final progress = ref.watch(progressProvider).value ?? const <String, PuzzleProgress>{};
  final friends = ref.watch(friendsProvider).value?.length ?? 0;
  // Guided start: only pictures finished after achievements opened count (owner, 2026-10-16), so
  // they do not open full of rewards; states such as the level, the streak or the coins held stay
  // what they are.
  final since = ref.watch(countsFromProvider(Reveal.achievements));
  final counted = since.millisecondsSinceEpoch == 0;
  final done = [for (final p in progress.values) if (p.completed && (counted || (p.completedAt != null && p.completedAt!.isAfter(since)))) p];
  final facts = AchievementFacts(profile, done, friends, starsFromPictures: !counted, since: counted ? null : since);
  return [for (final f in achievementFamilies) achievementStatus(f, facts, profile.claimedAchievements)];
});

/// [family]'s status: the next step not claimed and the progress towards it. A step claimed stays
/// claimed whatever the count does later (a picture's boards read another way, a merge), and the
/// progress shown never falls below the last step claimed.
AchievementStatus achievementStatus(AchievementFamily family, AchievementFacts facts, Iterable<String> claimedKeys) {
  final keys = claimedKeys.toSet();
  var claimed = 0;
  while (claimed < family.steps.length && keys.contains('${family.id}:${claimed + 1}')) {
    claimed++;
  }
  final floor = claimed == 0 ? 0 : family.steps[claimed - 1].threshold;
  return AchievementStatus(family: family, stepIndex: claimed, progress: max(family.progress(facts), floor), claimedSteps: claimed);
}

/// Avatar keys the player owns: starters, purchases, and claimed tiers.
Set<String> ownedAvatarKeys(Profile profile) {
  final owned = <String>{...AppIcons.freeAvatarKeys, ...profile.unlockedAvatars};
  for (final f in achievementFamilies) {
    for (var i = 0; i < f.steps.length; i++) {
      final key = f.steps[i].avatarKey;
      if (key != null && profile.claimedAchievements.contains('${f.id}:${i + 1}')) owned.add(key);
    }
  }
  return owned;
}

/// The step that first grants an avatar family, for "Reach X" copy.
({AchievementFamily family, int stepIndex})? avatarRequirement(String avatarKey) {
  for (final f in achievementFamilies) {
    for (var i = 0; i < f.steps.length; i++) {
      final k = f.steps[i].avatarKey;
      if (k == avatarKey || k == '$avatarKey@1') return (family: f, stepIndex: i);
    }
  }
  return null;
}
