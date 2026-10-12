import 'dart:math';

import 'modes.dart';
import 'tiling.dart';

export 'modes.dart';
export 'tiling.dart';

/// A board layout: a game mode (tiling) with a column/row count, and the
/// difficulty tier it belongs to. Each mode has an eight-step ladder sharing
/// the same labels.
///
/// The column/row count of a tier depends on the picture: squares must be
/// square and cards card-shaped, triangles and hexagons must cover the whole
/// picture, so each tier picks the layout that suits the picture's
/// proportions with the least crop or stretch, keeping its piece count close
/// to the tier's target ([forPicture]).
class BoardSpec {
  const BoardSpec(this.mode, this.cols, this.rows, this.label, {this.tier = -1});
  final GameMode mode;
  final int cols;
  final int rows;
  final String label;

  /// Index in the mode's ladder, or -1 for a custom size.
  final int tier;

  /// Number of pieces.
  int get cells => Tiling.cellCount(mode, cols, rows);

  /// Grid part only, e.g. `3x4`.
  String get code => '${cols}x$rows';

  /// Full code including the mode and the tier, e.g. `hexagons:5x7t3`.
  String get fullCode => BoardCode.encode(mode, cols, rows, tier: tier);

  Tiling get tiling => Tiling.of(mode, cols, rows);

  static const labels = ['Cozy', 'Easy', 'Relaxed', 'Medium', 'Tricky', 'Hard', 'Expert', 'Master'];

  /// Picture proportions used when the picture is not known yet (3:4
  /// portrait, the catalogue's most common shape).
  static const referenceAspect = 3 / 4;

  /// Piece count each tier aims for. Cards and squares keep the counts the
  /// game always had. Triangles and hexagons cover the whole picture with
  /// half pieces along the edges, which only shuffle cleanly from four rows
  /// of triangles and five rows of hexagons; that sets their smallest
  /// boards.
  static const targets = <GameMode, List<int>>{
    GameMode.cards: [9, 12, 16, 20, 25, 30, 36, 48],
    GameMode.squares: [12, 20, 24, 30, 35, 48, 63, 80],
    GameMode.triangles: [20, 28, 42, 50, 60, 72, 88, 108],
    GameMode.hexagons: [12, 22, 31, 40, 49, 60, 71, 84],
  };

  /// The ladders before layouts followed the picture, to read old codes.
  static const _legacyLadders = <GameMode, List<(int, int)>>{
    GameMode.cards: [(3, 3), (3, 4), (4, 4), (4, 5), (5, 5), (5, 6), (6, 6), (6, 8)],
    GameMode.squares: [(3, 4), (4, 5), (4, 6), (5, 6), (5, 7), (6, 8), (7, 9), (8, 10)],
    GameMode.triangles: [(4, 3), (4, 4), (6, 4), (6, 6), (8, 6), (8, 8), (10, 8), (10, 10)],
    GameMode.hexagons: [(3, 4), (4, 5), (4, 6), (5, 6), (5, 7), (6, 8), (6, 9), (7, 10)],
  };

  /// The eight boards of [mode] for a picture of [aspect] (width ÷ height).
  static List<BoardSpec> tiers(GameMode mode, [double aspect = referenceAspect]) {
    final dims = BoardLayouts.forAspect(mode, aspect);
    return [for (var i = 0; i < dims.length; i++) BoardSpec(mode, dims[i].$1, dims[i].$2, labels[i], tier: i)];
  }

  /// Tier [tier] of [mode] laid out for a picture of [aspect].
  static BoardSpec forPicture(GameMode mode, int tier, double aspect) => tiers(mode, aspect)[tier.clamp(0, labels.length - 1)];

  /// This board's tier laid out for a picture of [aspect].
  BoardSpec fitTo(double aspect) => forPicture(mode, tierIndex < 0 ? 2 : tierIndex, aspect);

  /// Index of this spec in its mode's ladder, or -1 for custom sizes.
  int get tierIndex => tier >= 0 ? tier : _tierOf(mode, cols, rows);

  /// Parses `mode:CxR`, `mode:CxRtT`, `CxR` (cards) or the URL forms
  /// `mode-CxR` / `mode-CxRtT`.
  static BoardSpec fromCode(String code) {
    final d = BoardCode.decode(BoardCode.fromPath(code));
    final t = d.tier != null && d.tier! >= 0 && d.tier! < labels.length ? d.tier! : _tierOf(d.mode, d.cols, d.rows);
    return BoardSpec(d.mode, d.cols, d.rows, t >= 0 ? labels[t] : 'Custom', tier: t);
  }

  /// Ladder index of a board size given without a tier. Codes made by this
  /// version always carry the tier, so these are old links and saves (and
  /// shortcuts such as a quest's `5x5`): the old fixed ladders first, then
  /// the reference ladder and the ladders of the common picture shapes, then
  /// the tier whose target piece count is nearest.
  static int _tierOf(GameMode mode, int cols, int rows) {
    final legacy = _legacyLadders[mode]!.indexWhere((d) => d.$1 == cols && d.$2 == rows);
    if (legacy >= 0) return legacy;
    for (final a in [referenceAspect, ...commonAspects]) {
      final i = BoardLayouts.forAspect(mode, a).indexWhere((d) => d.$1 == cols && d.$2 == rows);
      if (i >= 0) return i;
    }
    final cells = Tiling.cellCount(mode, cols, rows);
    final t = targets[mode]!;
    var best = 0;
    for (var i = 1; i < t.length; i++) {
      if ((log(cells / t[i])).abs() < (log(cells / t[best])).abs()) best = i;
    }
    return best;
  }

  /// Picture shapes tried when a board must be recovered without the
  /// picture: square, 4:5, 3:4, 2:3, 9:16.
  static const commonAspects = [1.0, 4 / 5, 3 / 4, 2 / 3, 9 / 16];

  /// The board a saved game of [cells] pieces was dealt on, for a picture
  /// of [aspect]; null when no tier of this picture has that many pieces
  /// (the layout changed since, so the save cannot be resumed).
  static BoardSpec? fromSaved(GameMode mode, int cells, double aspect) {
    for (final t in tiers(mode, aspect)) {
      if (t.cells == cells) return t;
    }
    return null;
  }

  /// Best-effort recovery of a board from a saved cell count when the
  /// picture is not at hand: a tier with that many pieces for a common
  /// picture shape, else the old ladder, else the Relaxed tier. The game
  /// screen settles the exact layout once the picture is loaded.
  static BoardSpec fromCells(GameMode mode, int cells) {
    for (final a in [referenceAspect, ...commonAspects]) {
      final hit = fromSaved(mode, cells, a);
      if (hit != null) return hit;
    }
    final legacy = _legacyLadders[mode]!.indexWhere((d) => d.$1 * d.$2 == cells);
    if (legacy >= 0) {
      final d = _legacyLadders[mode]![legacy];
      return BoardSpec(mode, d.$1, d.$2, labels[legacy], tier: legacy);
    }
    return tiers(mode)[2];
  }

  @override
  bool operator ==(Object other) => other is BoardSpec && other.mode == mode && other.cols == cols && other.rows == rows;
  @override
  int get hashCode => Object.hash(mode, cols, rows);
}

/// Chooses the eight boards of a mode for a picture's proportions.
///
/// Every candidate size is scored per tier: the share of the picture its
/// centre crop removes (heavily for triangles and hexagons, which are meant
/// to show the whole picture), how far its cells stretch from their ideal
/// shape, and how far its piece count is from the tier's target. A small
/// dynamic programme then picks one size per tier with strictly growing
/// piece counts (at least 10 % more each step) at the lowest total score,
/// so neighbouring tiers never collapse onto the same board.
class BoardLayouts {
  BoardLayouts._();

  static final _cache = <String, List<(int, int)>>{};

  /// Smallest growth in pieces from one tier to the next.
  static const minStep = 1.1;

  /// Fewest pieces a tier may have, whatever the picture: goals and
  /// achievements count boards of 25 ("5x5 or bigger", reached from Tricky),
  /// 36 (Expert) and 48 (Master) pieces.
  static const minCells = [0, 0, 0, 0, 25, 0, 36, 48];

  /// Column/row counts of the eight tiers of [mode] for a picture of
  /// [imageAspect]. Landscape pictures are treated as square (the board
  /// stays portrait or square and the picture is cropped); very tall ones
  /// as 1:2.
  static List<(int, int)> forAspect(GameMode mode, double imageAspect) {
    final a = (!imageAspect.isFinite || imageAspect <= 0 ? BoardSpec.referenceAspect : imageAspect).clamp(0.5, 1.0);
    final key = '${mode.code}:${a.toStringAsFixed(6)}';
    return _cache.putIfAbsent(key, () => _solve(mode, a));
  }

  static List<(int, int)> candidates(GameMode mode) => _candidates.putIfAbsent(mode, () {
        final t = BoardSpec.targets[mode]!;
        final clipped = mode == GameMode.triangles || mode == GameMode.hexagons;
        final lo = t.first * 0.6, hi = t.last * (clipped ? 1.45 : 1.3);
        final out = <(int, int)>[];
        void add(int c, int r) {
          final cells = Tiling.cellCount(mode, c, r);
          if (cells < lo || cells > hi) return;
          final (a, b) = Tiling.of(mode, c, r).aspectRange;
          // Portrait or square boards (a picture is cropped rather than the
          // board turning landscape), down to 1:2.
          if (a > 1.0 || b < 0.5) return;
          out.add((c, r));
        }

        switch (mode) {
          case GameMode.cards || GameMode.squares:
            for (var r = 3; r <= 16; r++) {
              for (var c = 3; c <= 14; c++) {
                add(c, r);
              }
            }
          // Edge pieces must be able to leave home without forming a pair
          // (see TriangleTiling and HexTiling): no five-row triangle strips,
          // and no three-wide honeycombs, whose top row of three cannot be
          // shuffled without two of them still side by side.
          case GameMode.triangles:
            for (var r = 4; r <= 12; r++) {
              if (r == 5) continue;
              for (var c = 4; c <= 18; c++) {
                add(c, r);
              }
            }
          case GameMode.hexagons:
            for (var r = 5; r <= 17; r += 2) {
              for (var c = 2; c <= 10; c++) {
                if (c == 3) continue;
                add(c, r);
              }
            }
        }
        out.sort((x, y) {
          final d = Tiling.cellCount(mode, x.$1, x.$2) - Tiling.cellCount(mode, y.$1, y.$2);
          if (d != 0) return d;
          return x.$1 != y.$1 ? x.$1 - y.$1 : x.$2 - y.$2;
        });
        return out;
      });

  static final _candidates = <GameMode, List<(int, int)>>{};

  /// Score of [dims] as tier [tier] of [mode] for a picture of [aspect].
  static double score(GameMode mode, (int, int) dims, int tier, double aspect) {
    final tiling = Tiling.of(mode, dims.$1, dims.$2);
    final f = tiling.fitFor(aspect);
    final clipped = mode == GameMode.triangles || mode == GameMode.hexagons;
    final cropWeight = clipped ? 4.0 : 1.0;
    final stretchWeight = mode == GameMode.cards ? 0.5 : 0.3;
    final countWeight = clipped ? 0.15 : 0.25;
    final target = BoardSpec.targets[mode]![tier];
    return cropWeight * (f.crop + 3 * max(0, f.crop - 0.05)) + stretchWeight * f.stretch + countWeight * (log(tiling.cells / target)).abs();
  }

  static List<(int, int)> _solve(GameMode mode, double aspect) {
    final cands = candidates(mode);
    final n = cands.length, k = BoardSpec.labels.length;
    final counts = [for (final d in cands) Tiling.cellCount(mode, d.$1, d.$2)];
    final best = List.generate(k, (_) => List<double>.filled(n, double.infinity));
    final prev = List.generate(k, (_) => List<int>.filled(n, -1));
    for (var i = 0; i < n; i++) {
      best[0][i] = score(mode, cands[i], 0, aspect);
    }
    for (var t = 1; t < k; t++) {
      for (var i = 0; i < n; i++) {
        if (counts[i] < minCells[t]) continue;
        final s = score(mode, cands[i], t, aspect);
        for (var j = 0; j < n; j++) {
          if (counts[i] < counts[j] * minStep || best[t - 1][j] == double.infinity) continue;
          final v = best[t - 1][j] + s;
          if (v < best[t][i]) {
            best[t][i] = v;
            prev[t][i] = j;
          }
        }
      }
    }
    var end = 0;
    for (var i = 1; i < n; i++) {
      if (best[k - 1][i] < best[k - 1][end]) end = i;
    }
    final out = List<(int, int)>.filled(k, (0, 0));
    for (var t = k - 1; t >= 0; t--) {
      out[t] = cands[end];
      end = prev[t][end];
    }
    return List.unmodifiable(out);
  }
}

/// Cards-mode spec on the original fixed ladder. Kept so the level-reward
/// table and settings keep their tier names and sizes (`GridSpec.tiers`,
/// `.code`, `.label`); boards themselves come from [BoardSpec.tiers].
class GridSpec extends BoardSpec {
  const GridSpec(int cols, int rows, String label, {super.tier}) : super(GameMode.cards, cols, rows, label);

  static const tiers = <GridSpec>[
    GridSpec(3, 3, 'Cozy', tier: 0),
    GridSpec(3, 4, 'Easy', tier: 1),
    GridSpec(4, 4, 'Relaxed', tier: 2),
    GridSpec(4, 5, 'Medium', tier: 3),
    GridSpec(5, 5, 'Tricky', tier: 4),
    GridSpec(5, 6, 'Hard', tier: 5),
    GridSpec(6, 6, 'Expert', tier: 6),
    GridSpec(6, 8, 'Master', tier: 7),
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

  int get cells => slots.length;
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
    for (var i = 0; i < group.length; i++) {
      next[dest[i]] = slots[group[i]];
    }
    // Displaced cards fill the vacated cells in reading order, each within
    // its own shape class (a half piece only ever lands in a half slot).
    for (var cls = 0; cls < tiling.classCount; cls++) {
      final into = [for (final v in vacated) if (tiling.classOf(v) == cls) v];
      final from = [for (final d in displaced) if (tiling.classOf(d) == cls) d];
      for (var i = 0; i < into.length && i < from.length; i++) {
        next[into[i]] = slots[from[i]];
      }
    }
    return Board(spec, next);
  }

  /// Whether [layout] is a board state for [spec]: a permutation of the
  /// right length that keeps every card in a slot of its own shape. Saves
  /// from before a board's layout changed fail this and start fresh.
  static bool isValidLayout(BoardSpec spec, List<int>? layout) {
    if (layout == null || layout.length != spec.cells) return false;
    final tiling = spec.tiling;
    final seen = List<bool>.filled(layout.length, false);
    for (var s = 0; s < layout.length; s++) {
      final c = layout[s];
      if (c < 0 || c >= layout.length || seen[c]) return false;
      seen[c] = true;
      if (tiling.classOf(c) != tiling.classOf(s)) return false;
    }
    return true;
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

  /// Builds a shuffled board. No card ever starts in place and no two
  /// picture-neighbours start next to each other, so the player never finds
  /// a locked card or a pre-made group on the table. Cards only move within
  /// their placement class (triangle orientation).
  ///
  /// Random permutations are tried first; if none is clean, a derangement is
  /// repaired by targeted swaps until every join is broken. Only as a last
  /// resort does the board keep a join. It never keeps a fixed point.
  factory Board.shuffled(BoardSpec spec, {int? seed}) {
    final rng = Random(seed);
    final tiling = spec.tiling;
    final n = spec.cells;
    final classes = List.generate(tiling.classCount, (_) => <int>[]);
    for (var s = 0; s < n; s++) {
      classes[tiling.classOf(s)].add(s);
    }
    List<int> random() {
      final perm = List<int>.filled(n, 0);
      for (final cls in classes) {
        final cards = List<int>.from(cls)..shuffle(rng);
        for (var i = 0; i < cls.length; i++) {
          perm[cls[i]] = cards[i];
        }
      }
      return perm;
    }

    for (var attempt = 0; attempt < 400; attempt++) {
      final perm = random();
      if (_fixedPoints(perm) == 0 && _joins(tiling, perm) == 0) return Board(spec, perm);
    }
    List<int>? best;
    var bestJoins = 1 << 30;
    for (var round = 0; round < 24; round++) {
      final perm = random();
      _derange(perm, classes, rng);
      final joins = _breakJoins(perm, tiling, classes, rng);
      if (joins == 0) return Board(spec, perm);
      if (joins < bestJoins) {
        bestJoins = joins;
        best = perm;
      }
    }
    return Board(spec, best!);
  }

  /// Removes every fixed point by swapping it with another slot of its class.
  /// Swapping a fixed point `i` with any `j` of the same class leaves neither
  /// fixed: `perm[j]` cannot be `i` (that is `perm[i]`), and `i != j`.
  static void _derange(List<int> perm, List<List<int>> classes, Random rng) {
    final classOf = <int, List<int>>{};
    for (final cls in classes) {
      for (final s in cls) {
        classOf[s] = cls;
      }
    }
    for (var i = 0; i < perm.length; i++) {
      if (perm[i] != i) continue;
      final cls = classOf[i]!;
      if (cls.length < 2) continue;
      var j = cls[rng.nextInt(cls.length)];
      while (j == i) {
        j = cls[rng.nextInt(cls.length)];
      }
      final t = perm[i];
      perm[i] = perm[j];
      perm[j] = t;
    }
  }

  /// Local search: swap one end of a joined pair with a random slot of its
  /// class whenever that keeps the permutation a derangement and does not add
  /// joins. Returns the number of joins left.
  static int _breakJoins(List<int> perm, Tiling tiling, List<List<int>> classes, Random rng) {
    final classOf = <int, List<int>>{};
    for (final cls in classes) {
      for (final s in cls) {
        classOf[s] = cls;
      }
    }
    bool joinedAt(int a, int b) => tiling.direction(perm[a], perm[b]) == tiling.direction(a, b);
    int joinsAround(int x, int y) {
      var c = 0;
      for (final nb in tiling.neighbours(x)) {
        if (joinedAt(x, nb)) c++;
      }
      for (final nb in tiling.neighbours(y)) {
        if (nb != x && joinedAt(y, nb)) c++;
      }
      return c;
    }

    var joins = _joins(tiling, perm);
    for (var iter = 0; iter < 4000 && joins > 0; iter++) {
      // Pick a random joined edge and one of its ends.
      int? x;
      var seen = 0;
      for (var s = 0; s < perm.length; s++) {
        for (final nb in tiling.neighbours(s)) {
          if (nb > s && joinedAt(s, nb)) {
            seen++;
            if (rng.nextInt(seen) == 0) x = rng.nextBool() ? s : nb;
          }
        }
      }
      if (x == null) break;
      final cls = classOf[x]!;
      if (cls.length < 2) break;
      var y = cls[rng.nextInt(cls.length)];
      if (y == x) continue;
      if (perm[y] == x || perm[x] == y) continue; // the swap would fix a card in place
      final before = joinsAround(x, y);
      final t = perm[x];
      perm[x] = perm[y];
      perm[y] = t;
      final after = joinsAround(x, y);
      if (after > before || (after == before && rng.nextInt(4) != 0)) {
        perm[y] = perm[x];
        perm[x] = t;
        continue;
      }
      joins += after - before;
    }
    return joins;
  }

  /// Joined edges of a raw permutation (each pair once).
  static int _joins(Tiling tiling, List<int> perm) {
    var c = 0;
    for (var s = 0; s < perm.length; s++) {
      for (final nb in tiling.neighbours(s)) {
        if (nb > s && tiling.direction(perm[s], perm[nb]) == tiling.direction(s, nb)) c++;
      }
    }
    return c;
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
