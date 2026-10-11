import '../game/board.dart';
import '../models/models.dart';

/// Rewards granted when a level is reached, and the goal definitions.
/// Kept in one place so the home card, the profile and the economy agree.
class LevelReward {
  const LevelReward({required this.level, required this.coins, this.tickets = 0, this.hints = 0, this.tier});
  final int level;
  final int coins;
  final int tickets;
  final int hints;
  /// Board tier unlocked at this level (index into GridSpec.tiers), if any.
  final GridSpec? tier;

  List<String> get lines => [
        '$coins coins',
        if (tickets > 0) '$tickets ticket${tickets == 1 ? '' : 's'}',
        if (hints > 0) '$hints hint${hints == 1 ? '' : 's'}',
        if (tier != null) '${tier!.code} ${tier!.label} boards',
      ];
}

class LevelRewards {
  LevelRewards._();

  /// Tier unlock schedule: the first three tiers are open from level 1.
  static const tierUnlockLevel = <int>[1, 1, 1, 2, 3, 5, 7, 10];

  /// Highest tier index available at [level].
  static int maxTierIndex(int level) {
    var idx = 0;
    for (var i = 0; i < tierUnlockLevel.length; i++) {
      if (level >= tierUnlockLevel[i]) idx = i;
    }
    return idx;
  }

  static LevelReward forLevel(int level) {
    final tierIdx = tierUnlockLevel.indexOf(level);
    return LevelReward(
      level: level,
      coins: 100 + 25 * level,
      tickets: level % 3 == 0 ? 1 : 0,
      hints: level % 2 == 0 ? 2 : 0,
      tier: tierIdx > 0 ? GridSpec.tiers[tierIdx] : null,
    );
  }

  /// Next few rewards after [level] for the "what's coming" list.
  static List<LevelReward> upcoming(int level, {int count = 3}) => List.generate(count, (i) => forLevel(level + 1 + i));
}

/// A goal with a claim key that is stored on the profile once claimed.
class Goal {
  const Goal({required this.key, required this.title, required this.progress, required this.target, required this.coins, this.tickets = 0, required this.icon, this.minCells = 0, this.mode});
  final String key;
  final String title;
  final int progress;
  final int target;
  final int coins;
  final int tickets;
  final String icon; // AppIcons name resolved by the UI
  /// Minimum board size a "Play" CTA should preselect (0 = any).
  final int minCells;
  /// Game mode the "Play" CTA should preselect, if any.
  final GameMode? mode;
  bool get done => progress >= target;
}

class Goals {
  Goals._();

  static String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// ISO-ish week key: Monday-based.
  static String weekKey(DateTime d) {
    final monday = d.subtract(Duration(days: d.weekday - 1));
    return 'w${dayKey(DateTime(monday.year, monday.month, monday.day))}';
  }

  static bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// Daily goals rotate a mode challenge so every tiling gets played.
  static List<Goal> daily(Iterable<PuzzleProgress> all, DateTime now) {
    final today = all.where((p) => p.completedAt != null && sameDay(p.completedAt!, now)).toList();
    final k = dayKey(now);
    final mode = GameMode.values[(now.day + now.month) % GameMode.values.length];
    return [
      Goal(key: 'd:$k:solve3', title: 'Solve 3 puzzles', progress: today.length, target: 3, coins: 60, icon: 'puzzle'),
      Goal(key: 'd:$k:stars2', title: 'Earn 3 stars twice', progress: today.where((p) => p.stars == 3).length, target: 2, coins: 80, icon: 'star'),
      Goal(key: 'd:$k:mode-${mode.code}', title: 'Finish a ${mode.label.toLowerCase()} board', progress: today.where((p) => p.mode == mode.code).length, target: 1, coins: 100, icon: 'puzzle', mode: mode),
      Goal(key: 'd:$k:big1', title: 'Finish a 5x5 or bigger board', progress: today.where((p) => p.gridSize >= 25).length, target: 1, coins: 120, icon: 'bigBoard', minCells: 25),
    ];
  }

  static List<Goal> weekly(Iterable<PuzzleProgress> all, DateTime now) {
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final week = all.where((p) => p.completedAt != null && !p.completedAt!.isBefore(monday)).toList();
    final days = {for (final p in week) dayKey(p.completedAt!)}.length;
    final k = weekKey(now);
    return [
      Goal(key: '$k:solve10', title: 'Solve 10 puzzles this week', progress: week.length, target: 10, coins: 0, tickets: 1, icon: 'puzzle'),
      Goal(key: '$k:stars15', title: 'Collect 15 stars', progress: week.fold<int>(0, (s, p) => s + p.stars), target: 15, coins: 0, tickets: 1, icon: 'star'),
      Goal(key: '$k:days4', title: 'Play on 4 different days', progress: days, target: 4, coins: 0, tickets: 2, icon: 'streak'),
      Goal(key: '$k:big3', title: 'Finish 3 boards of 5x5 or bigger', progress: week.where((p) => p.gridSize >= 25).length, target: 3, coins: 0, tickets: 2, icon: 'bigBoard', minCells: 25),
      Goal(key: '$k:modes', title: 'Play every mode once', progress: {for (final p in week) p.mode}.length, target: GameMode.values.length, coins: 0, tickets: 2, icon: 'puzzle'),
      Goal(key: '$k:hex2', title: 'Finish 2 hexagon boards', progress: week.where((p) => p.mode == GameMode.hexagons.code).length, target: 2, coins: 0, tickets: 1, icon: 'puzzle', mode: GameMode.hexagons),
    ];
  }
}
