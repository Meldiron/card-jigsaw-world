import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/dates.dart';
import '../core/numbers.dart';
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
        countOf(coins, 'coin'),
        if (tickets > 0) countOf(tickets, 'ticket'),
        if (hints > 0) countOf(hints, 'hint'),
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

  /// The key an unlock opened before its level with tickets is kept under, in the profile's
  /// `unlockedTiers` list (next to early board tiers `<mode>:<index>`, so no new column: older
  /// builds read the list and ignore a key they do not know). Only giant boards are sold early.
  static String earlyKey(Unlock u) => 'early:${u.name}';
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

  /// [unlockedTiers] is the profile's list of early unlocks: an unlock whose [Unlocks.earlyKey] is
  /// in it was opened before its level (giant boards for tickets, see `Economy.giantEarlyFee`).
  factory OpenFeatures.forPlayer({required int level, Iterable<PuzzleProgress> progress = const [], Map<String, int> solvedByMode = const {}, Iterable<String> unlockedTiers = const []}) {
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
    final early = {for (final u in Unlock.values) if (unlockedTiers.contains(Unlocks.earlyKey(u))) u};
    return OpenFeatures({for (final u in Unlock.values) if (level >= u.level || used.contains(u) || early.contains(u)) u}, used: used);
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
    this.puzzleId,
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

  /// The "Play" CTA opens this picture (today's daily puzzle).
  final String? puzzleId;
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

  /// The lock quest for players whose boards are mostly 25 cards or more, where 5 comes by itself.
  static const bigLockRun = 8;

  /// "41 seconds", "2:05".
  static String formatTime(int seconds) => seconds < 60 ? '$seconds seconds' : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  static bool _atPar(PuzzleProgress p) => p.par > 0 && p.moves <= p.par;

  /// Par quests count boards of Relaxed (4x4) and up: on the two smallest boards par comes
  /// without trying.
  static final _parTier = GridSpec.tiers[2];
  static bool _atParBig(PuzzleProgress p) => _atPar(p) && p.gridSize >= _parTier.cells;

  /// Daily quests. Besides "Solve 3 puzzles" (60 coins), each quest comes from a different lane,
  /// so one ordinary board never finishes two of them:
  ///
  /// * **How you play** (80): a board in a shape the player does not usually play, a board two
  ///   sizes above their usual one, or a Painting board. Rotates by day.
  /// * **Skill** (100): finish a 4x4 or bigger board at par, lock 5 cards in one move (8 for a
  ///   player whose boards are mostly 25 cards or more, where 5 comes by itself), or beat the
  ///   player's second-best time on the Cards size they play most.
  /// * **VIP** (120): the other skill when it fits, else a second shape, else today's daily puzzle
  ///   ([dailyPuzzle]).
  ///
  /// Quests that one board does together never share a day ([_Lanes.fits]): a bigger board with a
  /// shape, Painting or locking 5 cards, and Painting with a shape. "Usual" is [PlayHabits] from
  /// the boards finished before today, so the quests stay the same all day. Only what [open] and
  /// [level] allow is asked for; a level 1 player, with nothing to change yet, gets "Earn 3 stars
  /// twice". A slot keeps the quest already claimed in it today.
  static List<Goal> daily(Iterable<PuzzleProgress> all, DateTime now, {OpenFeatures open = OpenFeatures.all, int level = 99, Set<String> claimed = const {}, String? dailyPuzzle}) {
    final today = all.where((p) => p.completed && p.completedAt != null && sameDay(p.completedAt!, now)).toList();
    int count(bool Function(PuzzleProgress p) test) => today.where(test).length;
    final k = dayKey(now);
    final day = dayIndex(now);
    final h = PlayHabits.of(all, DateTime(now.year, now.month, now.day));
    final lanes = _Lanes(h, open, level, dailyPuzzle: dailyPuzzle != null);

    Goal? build(int slot, String kind) {
      final key = 'd:$k:s$slot:$kind';
      final coins = const {2: 80, 3: 100, 4: 120}[slot]!;
      final vip = slot == 4;
      final (name, arg) = _split(kind);
      switch (name) {
        case 'mode':
          final m = GameMode.values.where((m) => m.code == arg).firstOrNull;
          if (m == null) return null;
          return Goal(key: key, title: 'Finish a board in ${m.label}', progress: count((p) => p.mode == m.code), target: 1, coins: coins, icon: 'puzzle', mode: m, vipOnly: vip);
        case 'size':
          final t = GridSpec.tiers.where((t) => t.code == arg).firstOrNull;
          if (t == null) return null;
          return Goal(key: key, title: 'Finish a ${t.code} or bigger board', progress: count((p) => p.gridSize >= t.cells), target: 1, coins: coins, icon: 'bigBoard', minCells: t.cells, vipOnly: vip);
        case 'paint':
          return Goal(key: key, title: 'Solve a Painting board', progress: count((p) => p.painting), target: 1, coins: coins, icon: 'painting', painting: true, vipOnly: vip);
        case 'par':
          return Goal(key: key, title: 'Finish a ${_parTier.code} or bigger board at par', progress: count(_atParBig), target: 1, coins: coins, icon: 'swaps', minCells: _parTier.cells, vipOnly: vip);
        case 'lock':
          final n = int.tryParse(arg) ?? lockRun;
          return Goal(key: key, title: 'Lock $n cards in one move', progress: count((p) => p.bestLock >= n), target: 1, coins: coins, icon: 'lock', minCells: GridSpec.tiers[4].cells, vipOnly: vip);
        case 'fast':
          final f = _fast(arg);
          if (f == null) return null;
          return Goal(key: key, title: 'Solve a ${f.tier.code} board in under ${formatTime(f.seconds)}', progress: count((p) => _fastEnough(p, f)), target: 1, coins: coins, icon: 'time', minCells: f.tier.cells, mode: GameMode.cards, vipOnly: vip);
        case 'nopeek':
          return Goal(key: key, title: 'Solve 2 pictures without Peek', progress: count((p) => !p.peeked), target: 2, coins: coins, icon: 'eye', vipOnly: vip);
        case 'daily':
          if (dailyPuzzle == null) return null;
          return Goal(key: key, title: "Solve today's daily puzzle", progress: count((p) => p.puzzleId == dailyPuzzle), target: 1, coins: coins, icon: 'dailyPuzzle', puzzleId: dailyPuzzle, vipOnly: vip);
        case 'stars':
          return Goal(key: key, title: 'Earn 3 stars twice', progress: count((p) => p.stars == 3), target: 2, coins: coins, icon: 'star', vipOnly: vip);
        case 'solve':
          return Goal(key: key, title: 'Solve 5 puzzles', progress: today.length, target: 5, coins: coins, icon: 'puzzle', vipOnly: vip);
      }
      return null;
    }

    final picks = lanes.pick(
      day,
      slots: 3,
      pinned: _pinned(claimed, 'd:$k:s', 4),
      fallbacks: const ['stars', 'solve', 'nopeek'],
    );
    return [
      Goal(key: 'd:$k:solve3', title: 'Solve 3 puzzles', progress: today.length, target: 3, coins: 60, icon: 'puzzle'),
      for (var i = 0; i < picks.length; i++) build(i + 2, picks[i]) ?? build(i + 2, 'solve')!,
    ];
  }

  /// Weekly quests: "Solve 10 puzzles" (1 ticket) and "Play on 4 different days" (2) stay; the
  /// others come from different lanes as in [daily]: a skill (1: two 4x4 or bigger boards at par,
  /// 5 or 8 cards locked in one move on two pictures, or two boards under the time to beat), two
  /// ways of playing that one board cannot do together
  /// (2 each: every mode once with three bigger boards or three Painting boards; never the bigger
  /// boards with Painting), and the VIP extra (1).
  static List<Goal> weekly(Iterable<PuzzleProgress> all, DateTime now, {OpenFeatures open = OpenFeatures.all, int level = 99, Set<String> claimed = const {}}) {
    final monday = mondayOf(now);
    final week = all.where((p) => p.completed && p.completedAt != null && !p.completedAt!.isBefore(monday)).toList();
    int count(bool Function(PuzzleProgress p) test) => week.where(test).length;
    final days = {for (final p in week) dayKey(p.completedAt!)}.length;
    final k = weekKey(now);
    final h = PlayHabits.of(all, monday);
    final lanes = _Lanes(h, open, level, weekly: true);
    final modes = open.modes;
    final played = {for (final p in week) p.mode};

    Goal? build(int slot, String kind) {
      final key = '$k:s$slot:$kind';
      final tickets = const {2: 1, 4: 2, 5: 2, 6: 1}[slot]!;
      final vip = slot == 6;
      final (name, arg) = _split(kind);
      switch (name) {
        case 'modes':
          return Goal(
              key: key,
              title: modes.length == GameMode.values.length ? 'Play every mode once' : 'Play ${modes.length} modes this week',
              progress: modes.where((m) => played.contains(m.code)).length,
              target: modes.length,
              coins: 0,
              tickets: tickets,
              icon: 'puzzle',
              vipOnly: vip);
        case 'size':
          final t = GridSpec.tiers.where((t) => t.code == arg).firstOrNull;
          if (t == null) return null;
          return Goal(key: key, title: 'Finish 3 boards of ${t.code} or bigger', progress: count((p) => p.gridSize >= t.cells), target: 3, coins: 0, tickets: tickets, icon: 'bigBoard', minCells: t.cells, vipOnly: vip);
        case 'paint':
          return Goal(key: key, title: 'Solve 3 Painting boards', progress: count((p) => p.painting), target: 3, coins: 0, tickets: tickets, icon: 'painting', painting: true, vipOnly: vip);
        case 'par':
          return Goal(key: key, title: 'Finish two ${_parTier.code} or bigger boards at par', progress: count(_atParBig), target: 2, coins: 0, tickets: tickets, icon: 'swaps', minCells: _parTier.cells, vipOnly: vip);
        case 'lock':
          final n = int.tryParse(arg) ?? lockRun;
          return Goal(key: key, title: 'Lock $n cards in one move on two pictures', progress: count((p) => p.bestLock >= n), target: 2, coins: 0, tickets: tickets, icon: 'lock', minCells: GridSpec.tiers[4].cells, vipOnly: vip);
        case 'fast':
          final f = _fast(arg);
          if (f == null) return null;
          return Goal(key: key, title: 'Solve two ${f.tier.code} boards in under ${formatTime(f.seconds)}', progress: count((p) => _fastEnough(p, f)), target: 2, coins: 0, tickets: tickets, icon: 'time', minCells: f.tier.cells, mode: GameMode.cards, vipOnly: vip);
        case 'nopeek':
          return Goal(key: key, title: 'Solve 5 pictures without Peek', progress: count((p) => !p.peeked), target: 5, coins: 0, tickets: tickets, icon: 'eye', vipOnly: vip);
        case 'stars':
          return Goal(key: key, title: 'Collect 15 stars', progress: week.fold<int>(0, (s, p) => s + p.stars), target: 15, coins: 0, tickets: tickets, icon: 'star', vipOnly: vip);
        case 'solve':
          return Goal(key: key, title: 'Solve 15 puzzles this week', progress: week.length, target: 15, coins: 0, tickets: tickets, icon: 'puzzle', vipOnly: vip);
      }
      return null;
    }

    // Slots 2 (skill), 4 and 5 (ways of playing), 6 (VIP); 1 and 3 always stay.
    final picks = lanes.pickWeek(
      weekIndex(now),
      pinned: {
        for (final e in _pinned(claimed, '$k:s', 6).entries)
          if (e.key != 1 && e.key != 3) e.key: e.value,
      },
      fallbacks: const ['stars', 'solve', 'nopeek'],
    );
    Goal slot(int s) => build(s, picks[s]!) ?? build(s, 'solve')!;
    return [
      Goal(key: '$k:solve10', title: 'Solve 10 puzzles this week', progress: week.length, target: 10, coins: 0, tickets: 1, icon: 'puzzle'),
      slot(2),
      Goal(key: '$k:days4', title: 'Play on 4 different days', progress: days, target: 4, coins: 0, tickets: 2, icon: 'streak'),
      slot(4),
      slot(5),
      slot(6),
    ];
  }

  /// "4x4-41" -> the 4x4 tier and 41 seconds.
  static ({GridSpec tier, int seconds})? _fast(String arg) {
    final parts = arg.split('-');
    if (parts.length != 2) return null;
    final tier = GridSpec.tiers.where((t) => t.code == parts[0]).firstOrNull;
    final seconds = int.tryParse(parts[1]);
    return tier == null || seconds == null ? null : (tier: tier, seconds: seconds);
  }

  static bool _fastEnough(PuzzleProgress p, ({GridSpec tier, int seconds}) f) =>
      GameMode.fromCode(p.mode) == GameMode.cards && p.gridSize == f.tier.cells && p.elapsedSeconds > 0 && p.elapsedSeconds < f.seconds;

  /// "mode-hexagons" -> ("mode", "hexagons"); "par" -> ("par", "").
  static (String, String) _split(String kind) {
    final i = kind.indexOf('-');
    return i < 0 ? (kind, '') : (kind.substring(0, i), kind.substring(i + 1));
  }

  /// Quests already claimed in this period, by slot: `<prefix><slot>:<kind>` -> {slot: kind}.
  static Map<int, String> _pinned(Set<String> claimed, String prefix, int maxSlot) {
    final out = <int, String>{};
    for (final key in claimed) {
      if (!key.startsWith(prefix)) continue;
      final rest = key.substring(prefix.length);
      final colon = rest.indexOf(':');
      final slot = colon < 0 ? null : int.tryParse(rest.substring(0, colon));
      if (slot == null || slot < 2 || slot > maxSlot) continue;
      out[slot] = rest.substring(colon + 1);
    }
    return out;
  }

  /// Local midnight after [now]: when daily quests reset.
  static DateTime nextDailyReset(DateTime now) => DateTime(now.year, now.month, now.day + 1);

  /// Next Monday 00:00 local: when weekly quests reset.
  static DateTime nextWeeklyReset(DateTime now) => DateTime(now.year, now.month, now.day + (8 - now.weekday));

  /// Time left until a reset, in the app's one style (`formatTimeLeft`, lib/core/dates.dart).
  static String formatLeft(Duration d) => formatTimeLeft(d);
}

/// What a player usually plays, from their last [PlayHabits.recent] boards finished before a
/// moment (the start of today, or of the week): the shape most of them have, their middle size
/// and whether most were Painting boards. Quests ask for something else.
@immutable
class PlayHabits {
  const PlayHabits({this.mode = GameMode.cards, this.cells = 16, this.upper = 16, this.paints = false, this.byMode = const {}, this.timed});

  /// Boards looked at.
  static const recent = 20;

  final GameMode mode;

  /// Cards on the middle board (a player with no boards yet: 16, the default 4x4).
  final int cells;

  /// Cards on the board at four fifths of the way up: how big the player's bigger boards are.
  final int upper;
  final bool paints;

  /// Boards per shape.
  final Map<GameMode, int> byMode;

  /// The Cards size the player plays most and their second-best time on it (needs 3 timed
  /// boards of that size): the time to beat.
  final ({GridSpec tier, int seconds})? timed;

  factory PlayHabits.of(Iterable<PuzzleProgress> all, DateTime before) {
    final done = [for (final p in all) if (p.completed && p.completedAt != null && p.completedAt!.isBefore(before)) p]
      ..sort((a, b) => b.completedAt!.compareTo(a.completedAt!));
    final last = done.take(recent).toList();
    if (last.isEmpty) return const PlayHabits();
    final byMode = <GameMode, int>{};
    for (final p in last) {
      final m = GameMode.fromCode(p.mode);
      byMode[m] = (byMode[m] ?? 0) + 1;
    }
    final mode = byMode.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    final sizes = [for (final p in last) p.gridSize]..sort();
    // The time to beat: second-best time on the Cards size most recent Cards boards had.
    ({GridSpec tier, int seconds})? timed;
    final cardSizes = <int, int>{};
    for (final p in last) {
      if (GameMode.fromCode(p.mode) == GameMode.cards) cardSizes[p.gridSize] = (cardSizes[p.gridSize] ?? 0) + 1;
    }
    if (cardSizes.isNotEmpty) {
      final cells = cardSizes.entries.reduce((a, b) => b.value > a.value ? b : a).key;
      final tier = GridSpec.tiers.where((t) => t.cells == cells).firstOrNull;
      final times = [
        for (final p in done)
          if (GameMode.fromCode(p.mode) == GameMode.cards && p.gridSize == cells && (p.bestSeconds ?? p.elapsedSeconds) > 0) p.bestSeconds ?? p.elapsedSeconds,
      ]..sort();
      if (tier != null && times.length >= 3) timed = (tier: tier, seconds: times[1]);
    }
    return PlayHabits(
      mode: mode,
      cells: sizes[sizes.length ~/ 2],
      upper: sizes[((sizes.length - 1) * 4) ~/ 5],
      paints: last.where((p) => p.painting).length * 2 > last.length,
      byMode: byMode,
      timed: timed,
    );
  }
}

/// The quest lanes a player can be given, and the day's (or week's) pick from them. Kinds:
/// `mode-<shape>`, `size-<tier>`, `paint` (ways of playing), `par`, `lock` (skills), and, weekly,
/// `modes` (every mode once). Fallbacks (`stars`, `solve`) fill a slot only when nothing else fits.
class _Lanes {
  _Lanes(this.h, this.open, this.level, {this.weekly = false, this.dailyPuzzle = false});
  final PlayHabits h;
  final OpenFeatures open;
  final int level;
  final bool weekly;

  /// Today's daily puzzle is known (the VIP extra can ask for it).
  final bool dailyPuzzle;

  /// Shapes to ask for: open, not the one the player usually plays, the least played first.
  List<GameMode> get shapes {
    if (open.modes.length < 2) return const [];
    final list = [for (final m in open.modes) if (m != h.mode) m];
    list.sort((a, b) => (h.byMode[a] ?? 0).compareTo(h.byMode[b] ?? 0));
    return list;
  }

  /// A size the player does not reach as it is: two above the middle board and one above their
  /// bigger boards, as far as the level reaches; null when that is not bigger than those.
  GridSpec? get stepUp {
    int tierOf(int cells) {
      var t = 0;
      for (var i = 0; i < GridSpec.tiers.length; i++) {
        if (GridSpec.tiers[i].cells <= cells) t = i;
      }
      return t;
    }

    final t = GridSpec.tiers[min(max(tierOf(h.cells) + 2, tierOf(h.upper) + 1), LevelRewards.maxTierIndex(level))];
    return t.cells > h.upper ? t : null;
  }

  bool get painting => open.painting && !h.paints;

  /// Locking 5 cards needs a board of 25 cards (Tricky), which the level must have; on boards that
  /// big it happens by itself, so players who mostly play them are asked for 8.
  bool get lock => level >= LevelRewards.tierUnlockLevel[4];
  int get lockRun => h.upper < GridSpec.tiers[4].cells ? Goals.lockRun : Goals.bigLockRun;

  /// The ways of playing on offer, in rotation order, with today's shape for [turn].
  List<String> hows(int turn) {
    final s = shapes, up = stepUp;
    return [
      if (weekly && open.modes.length >= 2) 'modes',
      if (!weekly && s.isNotEmpty) 'mode-${_leastPlayed(s)[turn % _leastPlayed(s).length].code}',
      if (up != null) 'size-${up.code}',
      if (painting) 'paint',
    ];
  }

  /// The shapes played least (several when they tie).
  List<GameMode> _leastPlayed(List<GameMode> shapes) {
    final low = h.byMode[shapes.first] ?? 0;
    return [for (final m in shapes) if ((h.byMode[m] ?? 0) == low) m];
  }

  List<String> get skills => [
        'par',
        if (lock) 'lock-$lockRun',
        if (h.timed != null) 'fast-${h.timed!.tier.code}-${h.timed!.seconds}',
      ];

  static String lane(String kind) => switch (_Lanes._name(kind)) {
        'mode' => 'shape',
        final n => n,
      };

  static String _name(String kind) => kind.split('-').first;

  /// Lanes one ordinary board serves together: a bigger board in the asked shape, as a Painting
  /// board or with 5 cards locked (which big boards do by themselves), and a Painting board in the
  /// asked shape. "Every mode once" needs several boards, so it pairs with anything.
  static const _together = {('size', 'lock'), ('size', 'shape'), ('size', 'paint'), ('paint', 'shape')};

  /// Whether two quests can share a day (or a week): different lanes, except two different shapes,
  /// and never two lanes in [_together].
  bool fits(String a, String b) {
    final la = lane(a), lb = lane(b);
    if (la == lb) return la == 'shape' && a != b;
    // The time to beat is on Cards: a fast Cards board would also be the Cards board asked for.
    if ({a, b}.contains('mode-cards') && (la == 'fast' || lb == 'fast')) return false;
    // A player on boards smaller than 4x4 goes up a size for par too: one board would do both.
    if ({la, lb}.containsAll(const ['size', 'par']) && h.upper < Goals._parTier.cells) return false;
    return !_together.contains((la, lb)) && !_together.contains((lb, la));
  }

  bool fitsAll(String kind, Iterable<String> chosen) => chosen.every((c) => fits(kind, c));

  /// The day's quests for slots 2 (a way of playing), 3 (a skill) and 4 (VIP), keeping [pinned]
  /// ones (claimed earlier today). Consecutive days get a different way of playing and, when there
  /// are two, a different skill.
  List<String> pick(int day, {required int slots, required Map<int, String> pinned, required List<String> fallbacks}) {
    final chosen = <int, String>{...pinned};
    String? first(Iterable<String> options) {
      for (final o in options) {
        if (fitsAll(o, chosen.values)) return o;
      }
      return null;
    }

    List<String> rotate(List<String> list, int by) => list.isEmpty ? list : [for (var i = 0; i < list.length; i++) list[(by + i) % list.length]];
    final hows = this.hows(day ~/ max(1, this.hows(0).length));
    final skills = this.skills;
    String fallback() => first(fallbacks) ?? fallbacks.last;
    chosen[2] ??= first(rotate(hows, day)) ?? first(rotate(skills, day + 1)) ?? fallback();
    chosen[3] ??= first(rotate(skills, day)) ?? first(rotate(hows, day + 1)) ?? fallback();
    // VIP: the other skill, else a second shape (never on the same board as the first), else
    // today's daily puzzle, else another way of playing.
    chosen[4] ??= first([
          ...rotate(skills, day + 1),
          for (final m in rotate(shapes.map((m) => m.code).toList(), day + 1)) 'mode-$m',
          if (dailyPuzzle) 'daily',
          ...rotate(hows, day + 1),
        ]) ??
        fallback();
    return [for (var s = 2; s <= slots + 1; s++) chosen[s]!];
  }

  /// The week's quests for slots 2 (a skill), 4 and 5 (ways of playing) and 6 (VIP).
  Map<int, String> pickWeek(int week, {required Map<int, String> pinned, required List<String> fallbacks}) {
    final chosen = <int, String>{...pinned};
    String? first(Iterable<String> options) {
      for (final o in options) {
        if (fitsAll(o, chosen.values)) return o;
      }
      return null;
    }

    List<String> rotate(List<String> list, int by) => list.isEmpty ? list : [for (var i = 0; i < list.length; i++) list[(by + i) % list.length]];
    final hows = this.hows(week), skills = this.skills;
    String fallback() => first(fallbacks) ?? fallbacks.last;
    chosen[4] ??= first(rotate(hows, week)) ?? fallback();
    chosen[2] ??= first(rotate(skills, week)) ?? fallback();
    chosen[5] ??= first(rotate(hows, week + 1)) ?? first(rotate(skills, week + 1)) ?? fallback();
    chosen[6] ??= first([...rotate(skills, week + 1), ...rotate(hows, week + 2)]) ?? fallback();
    return chosen;
  }
}
