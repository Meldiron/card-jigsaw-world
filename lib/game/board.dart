import 'dart:math';

import 'modes.dart';
import 'tiling.dart';

export 'modes.dart';
export 'tiling.dart';

/// A board layout: a game mode (tiling) with a column/row count. Each mode
/// has an eight-step difficulty ladder sharing the same labels.
class BoardSpec {
  const BoardSpec(this.mode, this.cols, this.rows, this.label);
  final GameMode mode;
  final int cols;
  final int rows;
  final String label;

  int get cells => cols * rows;

  /// Grid part only, e.g. `3x4`.
  String get code => '${cols}x$rows';

  /// Full code including the mode, e.g. `hexagons:5x6`.
  String get fullCode => BoardCode.encode(mode, cols, rows);

  Tiling get tiling => Tiling.of(mode, cols, rows);

  static const labels = ['Cozy', 'Easy', 'Relaxed', 'Medium', 'Tricky', 'Hard', 'Expert', 'Master'];

  static const _ladders = <GameMode, List<(int, int)>>{
    GameMode.cards: [(3, 3), (3, 4), (4, 4), (4, 5), (5, 5), (5, 6), (6, 6), (6, 8)],
    GameMode.squares: [(3, 4), (4, 5), (4, 6), (5, 6), (5, 7), (6, 8), (7, 9), (8, 10)],
    GameMode.triangles: [(4, 3), (4, 4), (6, 4), (6, 6), (8, 6), (8, 8), (10, 8), (10, 10)],
    GameMode.hexagons: [(3, 4), (4, 5), (4, 6), (5, 6), (5, 7), (6, 8), (6, 9), (7, 10)],
  };

  static List<BoardSpec> tiers(GameMode mode) => [
        for (var i = 0; i < 8; i++) BoardSpec(mode, _ladders[mode]![i].$1, _ladders[mode]![i].$2, labels[i]),
      ];

  /// Index of this spec in its mode's ladder, or -1 for custom sizes.
  int get tierIndex => tiers(mode).indexWhere((t) => t.cols == cols && t.rows == rows);

  /// Parses `mode:CxR`, `CxR` (cards) or the URL form `mode-CxR`.
  static BoardSpec fromCode(String code) {
    final d = BoardCode.decode(BoardCode.fromPath(code));
    final ladder = tiers(d.mode);
    return ladder.firstWhere(
      (t) => t.cols == d.cols && t.rows == d.rows,
      orElse: () => BoardSpec(d.mode, d.cols, d.rows, 'Custom'),
    );
  }

  /// Best-effort recovery of a ladder entry from a saved cell count.
  static BoardSpec fromCells(GameMode mode, int cells) =>
      tiers(mode).firstWhere((t) => t.cells == cells, orElse: () => tiers(mode)[2]);

  @override
  bool operator ==(Object other) => other is BoardSpec && other.mode == mode && other.cols == cols && other.rows == rows;
  @override
  int get hashCode => Object.hash(mode, cols, rows);
}

/// Cards-mode spec. Kept as a subclass so existing call sites and the
/// level-reward table keep working (`GridSpec.tiers`, `.code`, `.label`).
class GridSpec extends BoardSpec {
  const GridSpec(int cols, int rows, String label) : super(GameMode.cards, cols, rows, label);

  static const tiers = <GridSpec>[
    GridSpec(3, 3, 'Cozy'),
    GridSpec(3, 4, 'Easy'),
    GridSpec(4, 4, 'Relaxed'),
    GridSpec(4, 5, 'Medium'),
    GridSpec(5, 5, 'Tricky'),
    GridSpec(5, 6, 'Hard'),
    GridSpec(6, 6, 'Expert'),
    GridSpec(6, 8, 'Master'),
  ];

  static GridSpec fromCells(int cells) => tiers.firstWhere((t) => t.cells == cells, orElse: () => tiers[2]);
  static GridSpec fromCode(String code) => tiers.firstWhere((t) => t.code == code, orElse: () => tiers[2]);
}

/// Immutable board: `slots[i]` is the index of the card currently sitting in
/// slot `i`. Card `k` belongs in slot `k`, so slot `i` is locked when
/// `slots[i] == i`.
///
/// Cards that are *correctly adjacent* (card 5 sitting directly left of
/// card 6, say) form a **group** anywhere on the board. Groups are derived
/// from the layout, never stored, and move as a single unit. Adjacency and
/// movement come from the spec's [Tiling].
class Board {
  Board(this.spec, List<int> slots)
      : slots = List.unmodifiable(slots),
        tiling = spec.tiling {
    _groups = _computeGroups();
  }

  final BoardSpec spec;
  final Tiling tiling;
  final List<int> slots;
  late final List<int> _groups; // slot -> group id
  late final Map<int, List<int>> _members = _computeMembers();

  int get cells => spec.cells;
  int get cols => spec.cols;
  int get rows => spec.rows;

  bool isLocked(int slot) => slots[slot] == slot;
  bool get isSolved {
    for (var i = 0; i < slots.length; i++) {
      if (slots[i] != i) return false;
    }
    return true;
  }

  int get misplaced {
    var c = 0;
    for (var i = 0; i < slots.length; i++) {
      if (slots[i] != i) c++;
    }
    return c;
  }

  int get lockedCount => cells - misplaced;

  /// Minimum number of single swaps to solve = n - (number of permutation cycles).
  int get par {
    final seen = List<bool>.filled(slots.length, false);
    var cycles = 0;
    for (var i = 0; i < slots.length; i++) {
      if (seen[i]) continue;
      cycles++;
      var j = i;
      while (!seen[j]) {
        seen[j] = true;
        j = slots[j];
      }
    }
    return slots.length - cycles;
  }

  /// Slot where the card currently at [slot] belongs.
  int homeOf(int slot) => slots[slot];

  /// Slot that currently holds card [card].
  int slotOfCard(int card) => slots.indexOf(card);

  // ---- groups ------------------------------------------------------------

  /// True when the cards at [a] and [b] (adjacent slots) belong next to each
  /// other in the picture in the same direction.
  bool joined(int a, int b) {
    final dir = tiling.direction(a, b);
    if (dir == null) return false;
    return tiling.direction(slots[a], slots[b]) == dir;
  }

  List<int> _computeGroups() {
    final g = List<int>.filled(cells, -1);
    var next = 0;
    for (var s = 0; s < cells; s++) {
      if (g[s] != -1) continue;
      final stack = [s];
      g[s] = next;
      while (stack.isNotEmpty) {
        final cur = stack.removeLast();
        for (final n in neighbours(cur)) {
          if (g[n] == -1 && joined(cur, n)) {
            g[n] = next;
            stack.add(n);
          }
        }
      }
      next++;
    }
    return g;
  }

  Map<int, List<int>> _computeMembers() {
    final m = <int, List<int>>{};
    for (var s = 0; s < cells; s++) {
      m.putIfAbsent(_groups[s], () => []).add(s);
    }
    return m;
  }

  Iterable<int> neighbours(int s) => tiling.neighbours(s);

  int groupIdOf(int slot) => _groups[slot];

  /// Slots (sorted) forming the group that contains [slot].
  List<int> groupOf(int slot) => _members[_groups[slot]]!;

  /// Number of groups with 2+ cards that are not yet locked in place.
  int get floatingGroups => _members.values.where((g) => g.length > 1 && !isLocked(g.first)).length;

  /// Count of joined edges (each pair once) – used to detect new snaps.
  int get joinCount {
    var c = 0;
    for (var s = 0; s < cells; s++) {
      for (final n in neighbours(s)) {
        if (n > s && joined(s, n)) c++;
      }
    }
    return c;
  }

  // ---- moves ------------------------------------------------------------

  /// Moves the whole group containing [slot] by a lattice delta. Cards that
  /// were sitting in the destination cells are displaced into the cells the
  /// group vacated, in reading order. Returns null when the move is not
  /// allowed (out of bounds, placement rule broken, onto cards locked in
  /// place, or the group itself is locked in place).
  Board? moveGroup(int slot, int dx, int dy) {
    if (dx == 0 && dy == 0) return null;
    final group = groupOf(slot);
    if (isLocked(group.first)) return null;
    final dest = <int>[];
    for (final s in group) {
      final d = tiling.apply(s, dx, dy);
      if (d == null) return null;
      dest.add(d);
    }
    final groupSet = group.toSet();
    for (final d in dest) {
      if (!groupSet.contains(d) && isLocked(d)) return null;
    }
    final next = List<int>.from(slots);
    final destSet = dest.toSet();
    final vacated = group.where((s) => !destSet.contains(s)).toList()..sort();
    final displaced = dest.where((d) => !groupSet.contains(d)).toList()..sort();
    final displacedCards = displaced.map((d) => slots[d]).toList();
    for (var i = 0; i < group.length; i++) {
      next[dest[i]] = slots[group[i]];
    }
    for (var i = 0; i < vacated.length; i++) {
      next[vacated[i]] = displacedCards[i];
    }
    return Board(spec, next);
  }

  /// Moves the group containing [slot] so that this card lands on [target].
  Board? moveTo(int slot, int target) {
    final d = tiling.delta(slot, target);
    if (d == null) return null;
    return moveGroup(slot, d.$1, d.$2);
  }

  /// Plain two-card swap (kept for tests and tooling).
  Board swap(int a, int b) {
    if (a == b) return this;
    final next = List<int>.from(slots);
    final t = next[a];
    next[a] = next[b];
    next[b] = t;
    return Board(spec, next);
  }

  /// Builds a shuffled board. No card starts in place (for tiny boards at
  /// most one), and no two picture-neighbours start next to each other, so
  /// the player never finds a pre-made group on the table. Cards only move
  /// within their placement class (triangle orientation).
  factory Board.shuffled(BoardSpec spec, {int? seed}) {
    final rng = Random(seed);
    final tiling = spec.tiling;
    final n = spec.cells;
    final maxFixed = n >= 12 ? 0 : 1;
    final classes = List.generate(tiling.classCount, (_) => <int>[]);
    for (var s = 0; s < n; s++) {
      classes[tiling.classOf(s)].add(s);
    }
    Board? best;
    var bestJoins = 1 << 30;
    for (var attempt = 0; attempt < 2000; attempt++) {
      final perm = List<int>.filled(n, 0);
      for (final cls in classes) {
        final cards = List<int>.from(cls)..shuffle(rng);
        for (var i = 0; i < cls.length; i++) {
          perm[cls[i]] = cards[i];
        }
      }
      if (_fixedPoints(perm) > maxFixed) continue;
      final b = Board(spec, perm);
      final joins = b.joinCount;
      if (joins == 0) return b;
      if (joins < bestJoins) {
        bestJoins = joins;
        best = b;
      }
    }
    return best ?? Board(spec, _cycleWithinClasses(classes, n));
  }

  static List<int> _cycleWithinClasses(List<List<int>> classes, int n) {
    final perm = List<int>.filled(n, 0);
    for (final cls in classes) {
      for (var i = 0; i < cls.length; i++) {
        perm[cls[i]] = cls[(i + 1) % cls.length];
      }
    }
    return perm;
  }

  static int _fixedPoints(List<int> p) {
    var c = 0;
    for (var i = 0; i < p.length; i++) {
      if (p[i] == i) c++;
    }
    return c;
  }

  /// Star rating from moves vs par (par = minimum single swaps, which no
  /// human hits). Three stars rewards focused play with a couple of slips,
  /// two stars a handful of mistakes, one star trial and error.
  /// 3x3 (par 7): 3 stars <= 11, 2 stars <= 17. 6x8 (par 46): <= 64 / <= 103.
  static int starsFor({required int moves, required int par}) {
    if (moves <= (par * 1.35).round() + 2) return 3;
    if (moves <= (par * 2.2).round() + 2) return 2;
    return 1;
  }
}
