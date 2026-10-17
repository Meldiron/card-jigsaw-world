import 'dart:convert';
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
  /// Square board size opened at this level (one of GridSpec.square), if any.
  final GridSpec? tier;

  /// Shapes and options that open at this level ([Unlocks.levels]).
  final List<Unlock> unlocks;

  /// This reward without the unlocks in [opened]: a shape the player already used, or giant boards
  /// opened early with tickets, is not promised again (the Home level card's next level and
  /// "Coming up").
  LevelReward without(Set<Unlock> opened) => unlocks.any(opened.contains)
      ? LevelReward(level: level, coins: coins, tickets: tickets, hints: hints, tier: tier, unlocks: [for (final u in unlocks) if (!opened.contains(u)) u])
      : this;

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

  /// Coins a level-up pays: 100 + 25 per level until that reaches [levelCoinsCap] (level 8), then
  /// the cap; every 10th level pays [milestoneLevelCoins] (owner, 2026-10-17: "only up to 300, or
  /// 500 in some major milestones"; 100 + 25 per level without end before).
  static const levelCoinsCap = 300;
  static const milestoneLevelCoins = 500;
  static int coinsForLevel(int level) => level % 10 == 0 ? milestoneLevelCoins : min(levelCoinsCap, 100 + 25 * level);

  static LevelReward forLevel(int level) {
    final tierIdx = tierUnlockLevel.indexOf(level);
    return LevelReward(
      level: level,
      coins: coinsForLevel(level),
      tickets: level % 3 == 0 ? 1 : 0,
      hints: level % 2 == 0 ? 2 : 0,
      // Levels 2 and 5 open Medium and Hard, which have no square board (old saves only).
      tier: tierIdx > 0 ? GridSpec.square.where((t) => t.tier == tierIdx).firstOrNull : null,
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

  /// The unlocks opened early with tickets, from the profile's `unlockedTiers`.
  static Set<Unlock> openedEarly(Iterable<String> unlockedTiers) => {for (final u in Unlock.values) if (unlockedTiers.contains(earlyKey(u))) u};
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
    final early = Unlocks.openedEarly(unlockedTiers);
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
    this.swap,
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

  /// The quest a swap would give in its place (Quests tab, for [QuestSwap.tickets]); null when the
  /// quest is claimed or nothing suitable is left this period.
  final QuestSwap? swap;
  bool get done => progress >= target;

  Goal _withSwap(QuestSwap? swap) => Goal(
        key: key,
        title: title,
        progress: progress,
        target: target,
        coins: coins,
        tickets: tickets,
        icon: icon,
        minCells: minCells,
        mode: mode,
        painting: painting,
        vipOnly: vipOnly,
        puzzleId: puzzleId,
        swap: swap,
      );
}

/// Swapping a quest that is not finished for another (owner, 2026-10-17): every swap costs
/// [tickets] and changes only that quest. Swaps live in `profiles.questSwaps`, a JSON map of slot
/// (`d:2026-10-17:s2`, `w2026-10-12:s4`) to the quests the slot has had this period, the one first
/// dealt first and the current one last ([Goals.decodeSwaps]). Every quest that is not finished or
/// claimed has one (TestFlight feedback, 2026-10-17). The next quest is never finished already, fits
/// the other quests still to do (one board never finishes two) and comes from a lane none of them
/// shows: first one the period has not used yet, then a plain one (asking for more than is done,
/// "Earn 3 stars 4 times" after two today), then one swapped away earlier; when every lane is taken,
/// a plain one asking for more than the same one on screen. Older builds ignore the column and show
/// the quest first dealt.
@immutable
class QuestSwap {
  const QuestSwap({required this.slot, required this.base, required this.next, required this.nextTitle, required this.count, this.fixedKey});

  /// Tickets one swap costs.
  static const tickets = 1;

  /// The period and slot: `d:2026-10-17:s2`, `w2026-10-12:s4`.
  final String slot;

  /// The quest first dealt in the slot (kept, so the other slots never move).
  final String base;

  /// The quest a swap gives, and its title.
  final String next;
  final String nextTitle;

  /// Swaps already made in the slot this period.
  final int count;

  /// The claim key of the slot's fixed quest ("Solve 3 puzzles": `d:<day>:solve3`), whose key has
  /// no slot in it.
  final String? fixedKey;
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

  /// The least time a timed quest asks to beat on a Cards board of [cells] cards: the play-time
  /// model's time on the board (docs/economy.md, section 2: `cells x (1.3 + 0.1 x cells)` seconds)
  /// at the owner's measured pace (0.7, the fastest real play we have), rounded up to 5 seconds:
  /// 3x3 15 seconds, 4x4 35, 5x5 1:10, 6x6 2:05, 7x7 3:35. A time to beat taken from boards
  /// finished with help (a friend on a shared board, Magic, cards that look the same) can be a few
  /// seconds, which no one beats alone (TestFlight, 2026-10-17: "a 3x3 board in under 4 seconds").
  static int fastFloor(int cells) => (cells * (13 + cells) * 7 / 500).ceil() * 5;

  /// Plain quests that can ask for more when the usual number is done already (a swap brings
  /// "Earn 3 stars 4 times" after two today): kind -> how many more, by day and by week. The
  /// number asked for is the kind's argument (`stars-4`), which builds from before ignore.
  static const _moreDaily = {'stars': 2, 'nopeek': 2, 'solve': 3};
  static const _moreWeekly = {'stars': 15, 'nopeek': 5, 'solve': 5};

  /// The number a plain quest asks for: its argument, never below the usual [n].
  static int _target(String arg, int n) => max(n, int.tryParse(arg) ?? n);

  static bool _atPar(PuzzleProgress p) => p.par > 0 && p.moves <= p.par;

  /// Par quests count boards of Relaxed (4x4) and up: on the two smallest boards par comes
  /// without trying.
  static final _parTier = GridSpec.tiers[2];
  static bool _atParBig(PuzzleProgress p) => _atPar(p) && sizeOf(p) >= _parTier.cells;

  /// The size a finished board counts as where a quest names one ("a 4x4 or bigger board"): a
  /// square board as its side squared (the 4x4 triangle strip has 14 pieces), any other as its
  /// pieces ([BoardSpec.sizeCells]).
  static int sizeOf(PuzzleProgress p) => BoardSpec.sizeCells(GameMode.fromCode(p.mode), p.gridSize);

  /// Daily quests. Besides "Solve 3 puzzles" (60 coins), each quest comes from a different lane,
  /// so one ordinary board never finishes two of them:
  ///
  /// * **How you play** (80): a board in a shape the player does not usually play, a board a
  ///   size above their usual ones, or a Painting board. Rotates by day.
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
  ///
  /// [swaps] (`Profile.questSwaps`) replaces a slot's quest with the one swapped in last; the other
  /// slots are dealt as if the slot still had the quest first dealt in it, so a swap changes only its
  /// own quest. Each quest carries the swap it offers ([Goal.swap]).
  static List<Goal> daily(Iterable<PuzzleProgress> all, DateTime now, {OpenFeatures open = OpenFeatures.all, int level = 99, Set<String> claimed = const {}, String? dailyPuzzle, DateTime? since, Map<String, List<String>> swaps = const {}}) {
    // [since]: the guided start counts only pictures finished after Quests opened.
    final today = all.where((p) => p.completed && p.completedAt != null && sameDay(p.completedAt!, now) && (since == null || p.completedAt!.isAfter(since))).toList();
    int count(bool Function(PuzzleProgress p) test) => today.where(test).length;
    final k = dayKey(now);
    final day = dayIndex(now);
    final h = PlayHabits.of(all, DateTime(now.year, now.month, now.day));
    final lanes = _Lanes(h, open, level, dailyPuzzle: dailyPuzzle != null);

    Goal? build(int slot, String kind) {
      final key = 'd:$k:s$slot:$kind';
      final coins = const {1: 60, 2: 80, 3: 100, 4: 120}[slot]!;
      final vip = slot == 4;
      final (name, arg) = _split(kind);
      switch (name) {
        // The quest ordinary play finishes, always first dealt in slot 1 (its key has no slot).
        case 'solve3':
          return Goal(key: 'd:$k:solve3', title: 'Solve 3 puzzles', progress: today.length, target: 3, coins: 60, icon: 'puzzle');
        case 'mode':
          final m = GameMode.values.where((m) => m.code == arg).firstOrNull;
          if (m == null) return null;
          return Goal(key: key, title: 'Finish a board in ${m.label}', progress: count((p) => p.mode == m.code), target: 1, coins: coins, icon: 'puzzle', mode: m, vipOnly: vip);
        case 'size':
          final t = GridSpec.byCode(arg);
          if (t == null) return null;
          return Goal(key: key, title: 'Finish a ${t.code} or bigger board', progress: count((p) => sizeOf(p) >= t.cells), target: 1, coins: coins, icon: 'bigBoard', minCells: t.cells, vipOnly: vip);
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
          final n = _target(arg, 2);
          return Goal(key: key, title: 'Solve $n pictures without Peek', progress: count((p) => !p.peeked), target: n, coins: coins, icon: 'eye', vipOnly: vip);
        case 'daily':
          if (dailyPuzzle == null) return null;
          return Goal(key: key, title: "Solve today's daily puzzle", progress: count((p) => p.puzzleId == dailyPuzzle), target: 1, coins: coins, icon: 'dailyPuzzle', puzzleId: dailyPuzzle, vipOnly: vip);
        case 'stars':
          final n = _target(arg, 2);
          return Goal(key: key, title: n == 2 ? 'Earn 3 stars twice' : 'Earn 3 stars $n times', progress: count((p) => p.stars == 3), target: n, coins: coins, icon: 'star', vipOnly: vip);
        case 'solve':
          final n = _target(arg, 5);
          return Goal(key: key, title: 'Solve $n puzzles', progress: today.length, target: n, coins: coins, icon: 'puzzle', vipOnly: vip);
      }
      return null;
    }

    final claimedKinds = _pinned(claimed, 'd:$k:s', 4);
    final history = {for (var s = 1; s <= 4; s++) s: swaps['d:$k:s$s'] ?? const <String>[]};
    final picks = lanes.pick(
      day,
      slots: 3,
      pinned: _dealtPins(claimedKinds, history, const [2, 3, 4]),
      fallbacks: const ['stars', 'solve', 'nopeek'],
    );
    final dealt = {1: 'solve3', for (var i = 0; i < picks.length; i++) i + 2: build(i + 2, picks[i]) != null ? picks[i] : 'solve'};
    return _withSwaps(
      lanes,
      dealt: dealt,
      claimedKinds: claimedKinds,
      history: history,
      slotKey: (s) => 'd:$k:s$s',
      fixedKeys: {1: 'd:$k:solve3'},
      claimed: claimed,
      build: build,
      pool: lanes.swapPool(day ~/ max(1, lanes.hows(0).length)),
      turn: day,
      more: _moreDaily,
    );
  }

  /// Weekly quests: "Solve 10 puzzles" (1 ticket) and "Play on 4 different days" (2) stay; the
  /// others come from different lanes as in [daily]: a skill (1: two 4x4 or bigger boards at par,
  /// 5 or 8 cards locked in one move on two pictures, or two boards under the time to beat), two
  /// ways of playing that one board cannot do together
  /// (2 each: every mode once with three bigger boards or three Painting boards; never the bigger
  /// boards with Painting), and the VIP extra (1).
  /// [swaps] as in [daily].
  static List<Goal> weekly(Iterable<PuzzleProgress> all, DateTime now, {OpenFeatures open = OpenFeatures.all, int level = 99, Set<String> claimed = const {}, DateTime? since, Map<String, List<String>> swaps = const {}}) {
    final monday = mondayOf(now);
    final week = all.where((p) => p.completed && p.completedAt != null && !p.completedAt!.isBefore(monday) && (since == null || p.completedAt!.isAfter(since))).toList();
    int count(bool Function(PuzzleProgress p) test) => week.where(test).length;
    final days = {for (final p in week) dayKey(p.completedAt!)}.length;
    final k = weekKey(now);
    final h = PlayHabits.of(all, monday);
    final lanes = _Lanes(h, open, level, weekly: true);
    final modes = open.modes;
    final played = {for (final p in week) p.mode};

    Goal? build(int slot, String kind) {
      final key = '$k:s$slot:$kind';
      final tickets = const {1: 1, 2: 1, 3: 2, 4: 2, 5: 2, 6: 1}[slot]!;
      final vip = slot == 6;
      final (name, arg) = _split(kind);
      switch (name) {
        // The two quests always first dealt in slots 1 and 3 (their keys have no slot).
        case 'solve10':
          return Goal(key: '$k:solve10', title: 'Solve 10 puzzles this week', progress: week.length, target: 10, coins: 0, tickets: 1, icon: 'puzzle');
        case 'days4':
          return Goal(key: '$k:days4', title: 'Play on 4 different days', progress: days, target: 4, coins: 0, tickets: 2, icon: 'streak');
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
          final t = GridSpec.byCode(arg);
          if (t == null) return null;
          return Goal(key: key, title: 'Finish 3 boards of ${t.code} or bigger', progress: count((p) => sizeOf(p) >= t.cells), target: 3, coins: 0, tickets: tickets, icon: 'bigBoard', minCells: t.cells, vipOnly: vip);
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
          final n = _target(arg, 5);
          return Goal(key: key, title: 'Solve $n pictures without Peek', progress: count((p) => !p.peeked), target: n, coins: 0, tickets: tickets, icon: 'eye', vipOnly: vip);
        case 'stars':
          final n = _target(arg, 15);
          return Goal(key: key, title: 'Collect $n stars', progress: week.fold<int>(0, (s, p) => s + p.stars), target: n, coins: 0, tickets: tickets, icon: 'star', vipOnly: vip);
        case 'solve':
          final n = _target(arg, 15);
          return Goal(key: key, title: 'Solve $n puzzles this week', progress: week.length, target: n, coins: 0, tickets: tickets, icon: 'puzzle', vipOnly: vip);
      }
      return null;
    }

    // Slots 2 (skill), 4 and 5 (ways of playing), 6 (VIP); 1 and 3 are dealt the same every week.
    final claimedKinds = _pinned(claimed, '$k:s', 6);
    final history = {for (var s = 1; s <= 6; s++) s: swaps['$k:s$s'] ?? const <String>[]};
    final picks = lanes.pickWeek(
      weekIndex(now),
      pinned: _dealtPins(claimedKinds, history, const [2, 4, 5, 6]),
      fallbacks: const ['stars', 'solve', 'nopeek'],
    );
    final dealt = {
      1: 'solve10',
      3: 'days4',
      for (final s in const [2, 4, 5, 6]) s: build(s, picks[s]!) != null ? picks[s]! : 'solve',
    };
    return _withSwaps(
      lanes,
      dealt: dealt,
      claimedKinds: claimedKinds,
      history: history,
      slotKey: (s) => '$k:s$s',
      fixedKeys: {1: '$k:solve10', 3: '$k:days4'},
      claimed: claimed,
      build: build,
      pool: lanes.swapPool(weekIndex(now)),
      turn: weekIndex(now),
      more: _moreWeekly,
    );
  }

  /// What the lane picks keep for [slots]: a swapped slot the quest first dealt in it (so the other
  /// slots do not move), else a quest claimed in it.
  static Map<int, String> _dealtPins(Map<int, String> claimedKinds, Map<int, List<String>> history, List<int> slots) => {
        for (final s in slots)
          if (history[s]!.isNotEmpty)
            s: history[s]!.first
          else if (claimedKinds[s] != null)
            s: claimedKinds[s]!,
      };

  /// The period's quests in slot order: a claimed quest stays, a swapped slot shows the quest swapped
  /// in last, the others what was [dealt]. Each quest that is not finished or claimed carries the
  /// swap it offers ([QuestSwap]); [more] names the plain quests that can ask for more.
  static List<Goal> _withSwaps(
    _Lanes lanes, {
    required Map<int, String> dealt,
    required Map<int, String> claimedKinds,
    required Map<int, List<String>> history,
    required String Function(int slot) slotKey,
    required Map<int, String> fixedKeys,
    required Set<String> claimed,
    required Goal? Function(int slot, String kind) build,
    required List<String> pool,
    required int turn,
    required Map<String, int> more,
  }) {
    final slots = dealt.keys.toList()..sort();
    final current = {for (final s in slots) s: claimedKinds[s] ?? (history[s]!.isNotEmpty ? history[s]!.last : dealt[s]!)};
    final goals = {for (final s in slots) s: build(s, current[s]!) ?? build(s, 'solve')!};
    // Every lane the period has shown: today's quests and every quest swapped in or away.
    final shown = {
      for (final s in slots) ...[current[s]!, dealt[s]!, ...history[s]!],
    }.map(_Lanes.lane).toSet();
    // Quests still to do: a finished or claimed one cannot be finished again, so it neither takes a
    // lane nor shares a board with the quest that comes.
    bool open(int s) => !goals[s]!.done && !claimed.contains(goals[s]!.key) && !claimedKinds.containsKey(s) && !(fixedKeys[s] != null && claimed.contains(fixedKeys[s]));
    QuestSwap? swapOf(int s) {
      final fixed = fixedKeys[s];
      if (!open(s)) return null;
      final others = [for (final o in slots) if (o != s && open(o)) current[o]!];
      // The lanes on screen now that a swap does not bring: the slot's own and the other quests'.
      final showing = {_Lanes.lane(current[s]!), for (final o in others) _Lanes.lane(o)};
      final h = history[s]!;
      final order = pool.isEmpty ? pool : [for (var i = 0; i < pool.length; i++) pool[(turn + s + h.length + i) % pool.length]];
      // [kind] as the slot would have it: a quest already finished would pay for the ticket at once,
      // so it is no swap, except a plain one, which then asks for more than is done.
      (String, Goal)? offer(String kind) {
        if (showing.contains(_Lanes.lane(kind)) || !lanes.fitsAll(kind, others)) return null;
        var next = build(s, kind);
        final step = more[kind];
        if (next != null && next.done && step != null) next = build(s, kind = '$kind-${next.progress + step}');
        return next == null || next.done ? null : (kind, next);
      }

      // When every lane is taken (a new player has few kinds of quest; a bigger board leaves out the
      // lock and Painting beside it): a plain quest of another lane than the slot's, asking for more
      // than the same quest on screen ("Solve 6 puzzles" beside "Solve 3 puzzles"), as the dealing's
      // fallbacks do.
      (String, Goal)? beyond(String kind) {
        final lane = _Lanes.lane(kind), step = more[kind]!;
        if (lane == _Lanes.lane(current[s]!) || !lanes.fitsAll(kind, others.where((o) => _Lanes.lane(o) != lane))) return null;
        final next = build(s, kind);
        if (next == null) return null;
        final above = [for (final o in slots) if (o != s && open(o) && _Lanes.lane(current[o]!) == lane) goals[o]!.target];
        final ask = '$kind-${max(next.progress, above.fold(0, max)) + step}';
        return (ask, build(s, ask)!);
      }

      // A lane the period has not shown yet; then the plain quests; then a lane swapped away earlier;
      // then the plain quests beyond those on screen.
      final pick = order.where((k) => !shown.contains(_Lanes.lane(k))).map(offer).nonNulls.firstOrNull ??
          order.where(more.containsKey).map(offer).nonNulls.firstOrNull ??
          order.map(offer).nonNulls.firstOrNull ??
          ['solve', 'stars', 'nopeek'].where(more.containsKey).map(beyond).nonNulls.firstOrNull;
      if (pick == null) return null;
      return QuestSwap(slot: slotKey(s), base: h.isEmpty ? current[s]! : h.first, next: pick.$1, nextTitle: pick.$2.title, count: h.isEmpty ? 0 : h.length - 1, fixedKey: fixed);
    }

    return [for (final s in slots) goals[s]!._withSwap(swapOf(s))];
  }

  /// `profiles.questSwaps` (a JSON map of slot to the quests it has had, see [QuestSwap]); anything
  /// unreadable counts as no swaps.
  static Map<String, List<String>> decodeSwaps(dynamic raw) {
    if (raw == null) return const {};
    try {
      final m = raw is Map ? raw : jsonDecode(raw.toString());
      if (m is! Map) return const {};
      return {
        for (final e in m.entries)
          if (e.value is List && (e.value as List).isNotEmpty) e.key.toString(): [for (final v in e.value as List) v.toString()],
      };
    } catch (_) {
      return const {};
    }
  }

  /// The day (or the week's Monday) a swap slot belongs to: `d:2026-10-17:s2`, `w2026-10-12:s4`.
  static DateTime? swapPeriod(String slot) {
    final date = slot.startsWith('d:') ? slot.substring(2) : (slot.startsWith('w') ? slot.substring(1) : '');
    return date.length < 10 ? null : DateTime.tryParse(date.substring(0, 10));
  }

  /// "4x4-41" -> the 4x4 size and 41 seconds. Keys stored before 2026-10-17 read as fair quests: a
  /// size from before square boards (`4x5`, which no board has now) names the square size at least
  /// as big, its time scaled to that board by the play-time model, and no time is below
  /// [fastFloor] ("fast-3x3-4" reads as a 3x3 board in under 15 seconds).
  static ({GridSpec tier, int seconds})? _fast(String arg) {
    final parts = arg.split('-');
    if (parts.length != 2) return null;
    final named = GridSpec.byCode(parts[0]);
    final seconds = int.tryParse(parts[1]);
    if (named == null || seconds == null) return null;
    final tier = GridSpec.atLeast(named.cells);
    int model(int cells) => cells * (13 + cells);
    final scaled = tier.cells == named.cells ? seconds : (seconds * model(tier.cells) / model(named.cells)).ceil();
    return (tier: tier, seconds: max(scaled, fastFloor(tier.cells)));
  }

  /// A finished Cards board of the quest's size under its time. A row with a board in progress (a
  /// replay) holds that board's size and time, not a finish.
  static bool _fastEnough(PuzzleProgress p, ({GridSpec tier, int seconds}) f) =>
      !p.inProgress && GameMode.fromCode(p.mode) == GameMode.cards && p.gridSize == f.tier.cells && p.elapsedSeconds > 0 && p.elapsedSeconds < f.seconds;

  /// "mode-hexagons" -> ("mode", "hexagons"); "par" -> ("par", "").
  static (String, String) _split(String kind) {
    final i = kind.indexOf('-');
    return i < 0 ? (kind, '') : (kind.substring(0, i), kind.substring(i + 1));
  }

  /// Quests already claimed in this period, by slot: `<prefix><slot>:<kind>` -> {slot: kind}. The
  /// quests first dealt in slots 1 (and 3, weekly) have keys without a slot and are not in here; a
  /// quest swapped into those slots has one (`d:<day>:s1:<kind>`).
  static Map<int, String> _pinned(Set<String> claimed, String prefix, int maxSlot) {
    final out = <int, String>{};
    for (final key in claimed) {
      if (!key.startsWith(prefix)) continue;
      final rest = key.substring(prefix.length);
      final colon = rest.indexOf(':');
      final slot = colon < 0 ? null : int.tryParse(rest.substring(0, colon));
      if (slot == null || slot < 1 || slot > maxSlot) continue;
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

  /// The square Cards size the player plays most and their second-best time on it (needs 3 timed
  /// boards of that size), never below [Goals.fastFloor]: the time to beat.
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
    final sizes = [for (final p in last) Goals.sizeOf(p)]..sort();
    // The time to beat: second-best time on the square Cards size most recent Cards boards had
    // (boards of sizes from before square boards cannot be dealt any more), never below what a
    // quick player does alone ([Goals.fastFloor]). Each finish counts with its own time: a row's
    // `bestSeconds` is the picture's best on any size or shape, and a row with a replay in
    // progress holds that board's size and time.
    ({GridSpec tier, int seconds})? timed;
    bool cards(PuzzleProgress p) => !p.inProgress && GameMode.fromCode(p.mode) == GameMode.cards && GridSpec.square.any((t) => t.cells == p.gridSize);
    final cardSizes = <int, int>{};
    for (final p in last) {
      if (cards(p)) cardSizes[p.gridSize] = (cardSizes[p.gridSize] ?? 0) + 1;
    }
    if (cardSizes.isNotEmpty) {
      final cells = cardSizes.entries.reduce((a, b) => b.value > a.value ? b : a).key;
      final tier = GridSpec.byCells(cells);
      final times = [
        for (final p in done)
          if (cards(p) && p.gridSize == cells && p.elapsedSeconds > 0) p.elapsedSeconds,
      ]..sort();
      if (tier != null && times.length >= 3) timed = (tier: tier, seconds: max(times[1], Goals.fastFloor(cells)));
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

  /// A size the player does not reach as it is: the square size above their bigger boards, as
  /// far as the level reaches; null when that is not bigger than those.
  GridSpec? get stepUp {
    const sizes = GridSpec.square;
    var at = 0, top = 0;
    for (var i = 0; i < sizes.length; i++) {
      if (sizes[i].cells <= h.upper) at = i;
      if (sizes[i].tier <= LevelRewards.maxTierIndex(level)) top = i;
    }
    final t = sizes[min(at + 1, top)];
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
        // The fixed quests: "Solve 3 puzzles" and "Solve 10 puzzles this week" are the solve lane.
        'solve3' || 'solve10' => 'solve',
        'days4' => 'days',
        final n => n,
      };

  /// Every quest a swap can bring, in order: the ways of playing, the skills, every shape (daily),
  /// today's daily puzzle, then the plain ones. [turn] picks the day's shape as [pick] does.
  List<String> swapPool(int turn) {
    final out = <String>[];
    for (final k in [
      ...hows(turn),
      ...skills,
      if (!weekly) for (final m in shapes) 'mode-${m.code}',
      if (!weekly && dailyPuzzle) 'daily',
      'stars',
      'nopeek',
      'solve',
    ]) {
      if (!out.contains(k)) out.add(k);
    }
    return out;
  }

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
