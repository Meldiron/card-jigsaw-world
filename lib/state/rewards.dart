import 'package:flutter/foundation.dart';

import '../game/board.dart';
import '../models/models.dart';

/// Rewards granted when a level is reached, and the goal definitions.
/// Kept in one place so the home card, the profile and the economy agree.
class LevelReward {
  const LevelReward({required this.level, required this.coins, this.tickets = 0, this.hints = 0, this.tier, this.unlocks = const []});
  final int level;
  final int coins;
  final int tickets;
  final int hints;
  /// Board tier unlocked at this level (index into GridSpec.tiers), if any.
  final GridSpec? tier;

  /// Shapes and options that open at this level ([Unlocks.levels]).
  final List<Unlock> unlocks;

  List<String> get lines => [
        for (final u in unlocks) u.label,
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
      unlocks: Unlocks.atLevel(level),
    );
  }

  /// Next few rewards after [level] for the "what's coming" list.
  static List<LevelReward> upcoming(int level, {int count = 3}) => List.generate(count, (i) => forLevel(level + 1 + i));

  /// Level reached with [xp] lifetime experience. This is the single source
  /// of truth: the HUD, the profile, league rows and the `level` column
  /// written to the profile row all derive from the XP with this function,
  /// so no two screens can ever disagree about a player's level.
  static int levelForXp(int xp) {
    var level = 1, remaining = xp;
    while (remaining >= Profile.xpForLevel(level)) {
      remaining -= Profile.xpForLevel(level);
      level++;
    }
    return level;
  }

  /// Experience gathered since the current level was reached.
  static int xpIntoLevel(int xp) {
    var level = 1, remaining = xp;
    while (remaining >= Profile.xpForLevel(level)) {
      remaining -= Profile.xpForLevel(level);
      level++;
    }
    return remaining;
  }

  /// Lifetime XP at which [level] is reached (level 1 is 0).
  static int xpToReach(int level) {
    var total = 0;
    for (var l = 1; l < level; l++) {
      total += Profile.xpForLevel(l);
    }
    return total;
  }
}

/// Shapes and options that open as levels rise. Cards are open from the
/// start; each of these has a one-screen intro the first time it opens.
enum Unlock {
  squares,
  triangles,
  hexagons,
  painting,
  giant;

  String get label => switch (this) {
        Unlock.squares => 'Squares',
        Unlock.triangles => 'Triangles',
        Unlock.hexagons => 'Hexagons',
        Unlock.painting => 'Painting',
        Unlock.giant => 'Giant boards',
      };

  /// The shape this opens, when it is one.
  GameMode? get mode => switch (this) {
        Unlock.squares => GameMode.squares,
        Unlock.triangles => GameMode.triangles,
        Unlock.hexagons => GameMode.hexagons,
        Unlock.painting || Unlock.giant => null,
      };

  /// Level it opens at.
  int get level => Unlocks.levels[this]!;
}

class Unlocks {
  Unlocks._();

  /// Level each one opens at. On the level curve (100 XP for level 2, then 60 more per level) a
  /// player who plays about 20 minutes a day earns roughly 1,000 XP a day, so Squares come after
  /// the second picture and the rest about a day apart: Triangles and Hexagons on the first day
  /// or two, Painting on day two or three, giant boards by day four.
  static const levels = <Unlock, int>{
    Unlock.squares: 2,
    Unlock.triangles: 4,
    Unlock.hexagons: 6,
    Unlock.painting: 8,
    Unlock.giant: 10,
  };

  static Unlock? ofMode(GameMode mode) => switch (mode) {
        GameMode.cards => null,
        GameMode.squares => Unlock.squares,
        GameMode.triangles => Unlock.triangles,
        GameMode.hexagons => Unlock.hexagons,
      };

  /// What opens at [level].
  static List<Unlock> atLevel(int level) => [for (final u in Unlock.values) if (u.level == level) u];
}

/// What a player can pick on the mode and board screen: everything their
/// level has reached, plus whatever they already used (a board finished or
/// in progress with it), so nobody loses a shape they played before.
@immutable
class OpenFeatures {
  const OpenFeatures(this.open, {this.used = const {}});

  final Set<Unlock> open;

  /// Used before (open whatever the level; no intro needed).
  final Set<Unlock> used;

  static const all = OpenFeatures({Unlock.squares, Unlock.triangles, Unlock.hexagons, Unlock.painting, Unlock.giant});

  factory OpenFeatures.forPlayer({required int level, Iterable<PuzzleProgress> progress = const [], Map<String, int> solvedByMode = const {}}) {
    final used = <Unlock>{};
    for (final e in solvedByMode.entries) {
      final u = e.value > 0 ? Unlocks.ofMode(GameMode.fromCode(e.key)) : null;
      if (u != null) used.add(u);
    }
    for (final p in progress) {
      if (!p.completed && !p.inProgress) continue;
      final mode = GameMode.fromCode(p.mode);
      final u = Unlocks.ofMode(mode);
      if (u != null) used.add(u);
      if (p.painting) used.add(Unlock.painting);
      if (p.gridSize >= BoardLayouts.giantFloor(mode)) used.add(Unlock.giant);
    }
    return OpenFeatures({for (final u in Unlock.values) if (level >= u.level || used.contains(u)) u}, used: used);
  }

  bool has(Unlock u) => open.contains(u);

  /// Whether [mode] can be picked (Cards always can).
  bool mode(GameMode mode) {
    final u = Unlocks.ofMode(mode);
    return u == null || open.contains(u);
  }

  bool get painting => has(Unlock.painting);
  bool get giant => has(Unlock.giant);

  /// The shapes that can be picked, in ladder order.
  List<GameMode> get modes => [for (final m in GameMode.values) if (mode(m)) m];

  @override
  bool operator ==(Object other) => other is OpenFeatures && setEquals(other.open, open) && setEquals(other.used, used);

  @override
  int get hashCode => Object.hash(Object.hashAllUnordered(open), Object.hashAllUnordered(used));

  @override
  String toString() => 'OpenFeatures(${open.map((u) => u.name).join(', ')})';
}

/// A goal with a claim key that is stored on the profile once claimed.
class Goal {
  const Goal({
    required this.key,
    required this.title,
    required this.progress,
    required this.target,
    required this.coins,
    this.tickets = 0,
    required this.icon,
    this.minCells = 0,
    this.mode,
    this.painting = false,
    this.vipOnly = false,
  });
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
  /// The "Play" CTA preselects Painting.
  final bool painting;
  /// Only VIP members can claim it; others see it as a locked card.
  final bool vipOnly;
  bool get done => progress >= target;
}

class Goals {
  Goals._();

  static String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Monday of [d]'s week (calendar arithmetic, so a daylight saving change cannot move it).
  static DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

  /// ISO-ish week key: Monday-based.
  static String weekKey(DateTime d) => 'w${dayKey(mondayOf(d))}';

  static bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// Days since 1 January 2026 for [d]'s calendar date: picks the day's quest rotation.
  static int dayIndex(DateTime d) => DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(2026)).inDays;

  /// Weeks since the week of 29 December 2025 (a Monday): picks the week's quest rotation.
  static int weekIndex(DateTime d) {
    final m = mondayOf(d);
    return DateTime.utc(m.year, m.month, m.day).difference(DateTime.utc(2025, 12, 29)).inDays ~/ 7;
  }

  /// Everyone gets three daily and five weekly quests; VIP adds a fourth
  /// and a sixth. The extra ones are always the last in each list, with
  /// stable keys, so a claim made while VIP stays claimed afterwards.
  static const dailyFree = 3;
  static const weeklyFree = 5;

  /// Coins VIP members get once a week (paid when the app opens, not a quest:
  /// VIP has exactly one extra weekly quest).
  static const vipWeeklyBonus = 500;

  /// Marks the week's VIP bonus as paid (stored with the claimed quests).
  static String vipBonusKey(DateTime now) => '${weekKey(now)}:vipbonus';

  /// Cards locked by one move for the "Lock 5 cards in one move" quests.
  static const lockRun = 5;

  /// The "big board" quests ask for Tricky (5x5) once the player's level has
  /// it, and for Relaxed (4x4) before that.
  static int bigCells(int level) => level >= LevelRewards.tierUnlockLevel[4] ? GridSpec.tiers[4].cells : GridSpec.tiers[2].cells;
  static String _bigCode(int level) => level >= LevelRewards.tierUnlockLevel[4] ? GridSpec.tiers[4].code : GridSpec.tiers[2].code;

  /// The slot's quest: the one already claimed today (or this week) if any,
  /// so a quest that changes after a level-up never pays twice, else the
  /// rotation's pick.
  static Goal _slot(List<Goal> options, int index, Set<String> claimed) {
    for (final g in options) {
      if (claimed.contains(g.key)) return g;
    }
    return options[index % options.length];
  }

  static bool _atPar(PuzzleProgress p) => p.par > 0 && p.moves <= p.par;

  /// Daily quests: "Solve 3 puzzles", then one of three star/skill quests and
  /// one of three shape/technique quests that rotate by day, so six kinds turn
  /// up across a week, plus the VIP big board. Only what [open] allows is
  /// asked for: a shape or Painting the player has not reached is replaced by
  /// "Lock 5 cards in one move". [claimed] are the player's claimed quest keys.
  static List<Goal> daily(Iterable<PuzzleProgress> all, DateTime now, {OpenFeatures open = OpenFeatures.all, int level = 99, Set<String> claimed = const {}}) {
    final today = all.where((p) => p.completed && p.completedAt != null && sameDay(p.completedAt!, now)).toList();
    int count(bool Function(PuzzleProgress p) test) => today.where(test).length;
    final k = dayKey(now);
    final day = dayIndex(now);
    final shapes = [for (final m in open.modes) if (m != GameMode.cards) m];
    final mode = shapes.isEmpty ? null : shapes[(now.day + now.month) % shapes.length];
    final lock = Goal(key: 'd:$k:lock5', title: 'Lock $lockRun cards in one move', progress: count((p) => p.bestLock >= lockRun), target: 1, coins: 100, icon: 'lock');
    final shapeOrTechnique = [
      mode == null
          ? lock
          : Goal(key: 'd:$k:mode-${mode.code}', title: 'Finish a ${mode.label} board', progress: count((p) => p.mode == mode.code), target: 1, coins: 100, icon: 'puzzle', mode: mode),
      lock,
      open.painting ? Goal(key: 'd:$k:paint1', title: 'Solve a Painting board', progress: count((p) => p.painting), target: 1, coins: 100, icon: 'painting', painting: true) : lock,
    ];
    final big = bigCells(level);
    return [
      Goal(key: 'd:$k:solve3', title: 'Solve 3 puzzles', progress: today.length, target: 3, coins: 60, icon: 'puzzle'),
      _slot([
        Goal(key: 'd:$k:stars2', title: 'Earn 3 stars twice', progress: count((p) => p.stars == 3), target: 2, coins: 80, icon: 'star'),
        Goal(key: 'd:$k:nopeek2', title: 'Solve 2 pictures without Peek', progress: count((p) => !p.peeked), target: 2, coins: 80, icon: 'eye'),
        Goal(key: 'd:$k:par1', title: 'Finish a board at par', progress: count(_atPar), target: 1, coins: 80, icon: 'swaps'),
      ], day, claimed),
      _slot(shapeOrTechnique, day, claimed),
      Goal(key: 'd:$k:big1', title: 'Finish a ${_bigCode(level)} or bigger board', progress: count((p) => p.gridSize >= big), target: 1, coins: 120, icon: 'bigBoard', minCells: big, vipOnly: true),
    ];
  }

  /// Weekly quests: three that stay ("Solve 10 puzzles", "Play on 4
  /// different days", every open mode) and two that rotate by week through
  /// stars, Peek-free and at-par solves, big boards, five-card locks and
  /// Painting, plus the VIP extra. Asks only for what [open] allows.
  static List<Goal> weekly(Iterable<PuzzleProgress> all, DateTime now, {OpenFeatures open = OpenFeatures.all, int level = 99, Set<String> claimed = const {}}) {
    final monday = mondayOf(now);
    final week = all.where((p) => p.completed && p.completedAt != null && !p.completedAt!.isBefore(monday)).toList();
    int count(bool Function(PuzzleProgress p) test) => week.where(test).length;
    final days = {for (final p in week) dayKey(p.completedAt!)}.length;
    final k = weekKey(now);
    final w = weekIndex(now);
    final big = bigCells(level);
    final bigGoal = Goal(key: '$k:big3', title: 'Finish 3 boards of ${_bigCode(level)} or bigger', progress: count((p) => p.gridSize >= big), target: 3, coins: 0, tickets: 2, icon: 'bigBoard', minCells: big);
    final modes = open.modes;
    final played = {for (final p in week) p.mode};
    final everyMode = modes.length >= 2
        ? Goal(
            key: '$k:modes',
            title: modes.length == GameMode.values.length ? 'Play every mode once' : 'Play ${modes.length} modes this week',
            progress: modes.where((m) => played.contains(m.code)).length,
            target: modes.length,
            coins: 0,
            tickets: 2,
            icon: 'puzzle')
        : Goal(key: '$k:stars5', title: 'Earn 3 stars 5 times', progress: count((p) => p.stars == 3), target: 5, coins: 0, tickets: 2, icon: 'star');
    // VIP extra: two boards of the trickiest open shape (hexagons once open).
    final shapes = [for (final m in modes) if (m != GameMode.cards) m];
    final vipMode = shapes.isEmpty ? null : shapes.last;
    final vip = vipMode == null
        ? Goal(key: '$k:solve15', title: 'Solve 15 puzzles this week', progress: week.length, target: 15, coins: 0, tickets: 1, icon: 'puzzle', vipOnly: true)
        : Goal(
            key: vipMode == GameMode.hexagons ? '$k:hex2' : '$k:mode2-${vipMode.code}',
            title: 'Finish 2 ${vipMode.label} boards',
            progress: count((p) => p.mode == vipMode.code),
            target: 2,
            coins: 0,
            tickets: 1,
            icon: 'puzzle',
            mode: vipMode,
            vipOnly: true);
    return [
      Goal(key: '$k:solve10', title: 'Solve 10 puzzles this week', progress: week.length, target: 10, coins: 0, tickets: 1, icon: 'puzzle'),
      _slot([
        Goal(key: '$k:stars15', title: 'Collect 15 stars', progress: week.fold<int>(0, (s, p) => s + p.stars), target: 15, coins: 0, tickets: 1, icon: 'star'),
        Goal(key: '$k:nopeek5', title: 'Solve 5 pictures without Peek', progress: count((p) => !p.peeked), target: 5, coins: 0, tickets: 1, icon: 'eye'),
        Goal(key: '$k:par3', title: 'Finish 3 boards at par', progress: count(_atPar), target: 3, coins: 0, tickets: 1, icon: 'swaps'),
      ], w, claimed),
      Goal(key: '$k:days4', title: 'Play on 4 different days', progress: days, target: 4, coins: 0, tickets: 2, icon: 'streak'),
      _slot([
        bigGoal,
        Goal(key: '$k:lock5x3', title: 'Lock $lockRun cards in one move on 3 pictures', progress: count((p) => p.bestLock >= lockRun), target: 3, coins: 0, tickets: 2, icon: 'lock'),
        open.painting ? Goal(key: '$k:paint3', title: 'Solve 3 Painting boards', progress: count((p) => p.painting), target: 3, coins: 0, tickets: 2, icon: 'painting', painting: true) : bigGoal,
      ], w, claimed),
      everyMode,
      vip,
    ];
  }

  /// Local midnight after [now]: when daily quests reset.
  static DateTime nextDailyReset(DateTime now) => DateTime(now.year, now.month, now.day + 1);

  /// Next Monday 00:00 local: when weekly quests reset.
  static DateTime nextWeeklyReset(DateTime now) => DateTime(now.year, now.month, now.day + (8 - now.weekday));

  /// "5h 12m" / "3d 4h" style remaining time, never negative.
  static String formatLeft(Duration d) {
    if (d.isNegative) d = Duration.zero;
    // Two units at most and never a zero one: "6d", "6d 4h", "5h", "5h 12m", "12m", "<1m".
    final hours = d.inHours % 24, minutes = d.inMinutes % 60;
    if (d.inDays > 0) return hours > 0 ? '${d.inDays}d ${hours}h' : '${d.inDays}d';
    if (d.inHours > 0) return minutes > 0 ? '${d.inHours}h ${minutes}m' : '${d.inHours}h';
    return d.inMinutes > 0 ? '${d.inMinutes}m' : '<1m';
  }
}
