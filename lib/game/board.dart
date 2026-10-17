import 'dart:math';

import 'modes.dart';
import 'tiling.dart';

export 'modes.dart';
export 'tiling.dart';

/// A board layout: a game mode (tiling) with a column/row count, and the
/// difficulty tier it belongs to (its label: Cozy ... Master, Large ...
/// Colossal).
///
/// Square boards (owner, 2026-10-17): a tier always deals the same board, as
/// many pieces across as down (3x3, 4x4, ... in every mode, [squareTiers];
/// giant packs 10x10 and up, [squareGiantTiers]), whatever the picture; a
/// picture of another shape is centre-cropped to the board. **Expand** (a
/// switch on the difficulty screen, [offersExpand]) deals the same tiers with
/// the columns and rows that suit the picture's proportions instead, so the
/// whole picture is played ([expandTiers], [giantTiers]). The eight-step
/// picture-shaped ladder the game dealt before ([tiers]) is kept to resume
/// boards saved by older builds and to read their codes. docs/boards.md.
class BoardSpec {
  const BoardSpec(this.mode, this.cols, this.rows, this.label, {this.tier = -1, this.expand = false});
  final GameMode mode;
  final int cols;
  final int rows;
  final String label;

  /// Index in the mode's ladder, or -1 for a custom size.
  final int tier;

  /// Chosen with Expand on: the next picture is dealt from its Expand ladder
  /// too. A board whose columns and rows differ from its tier's square board
  /// (any board of an older build) is an Expand board.
  final bool expand;

  /// Number of pieces.
  int get cells => Tiling.cellCount(mode, cols, rows);

  /// Grid part only, e.g. `3x4` (for triangles, pieces in a row x rows).
  String get code => '${cols}x$rows';

  /// The size as players read it, columns x rows. A triangle column is one
  /// up and one down triangle wide (two of [Tiling]'s half steps), so the 4x4
  /// triangle board has nine pieces in a row (`9x4` in [code]); an old board
  /// with an odd number of half steps counts the last half column as one.
  String get size => mode == GameMode.triangles ? '${(cols) ~/ 2}x$rows' : code;

  /// Full code including the mode and the tier, e.g. `hexagons:5x7t3`.
  String get fullCode => BoardCode.encode(mode, cols, rows, tier: tier);

  Tiling get tiling => Tiling.of(mode, cols, rows);

  /// This board with [expand] set (the same columns and rows).
  BoardSpec withExpand(bool expand) => expand == this.expand ? this : BoardSpec(mode, cols, rows, label, tier: tier, expand: expand);

  static const labels = ['Cozy', 'Easy', 'Relaxed', 'Medium', 'Tricky', 'Hard', 'Expert', 'Master'];

  /// Square boards: the tier of an N x N board, the same in every mode. They
  /// keep the piece counts of the Cards ladder's square steps (Cozy 9,
  /// Relaxed 16, Tricky 25, Expert 36, Master 48 -> 49), so quests, unlock
  /// levels and rewards per tier stay as they were. Easy, Medium and Hard
  /// have no square board; they remain on boards saved before.
  static const squareTierOfSide = <int, int>{3: 0, 4: 2, 5: 4, 6: 6, 7: 7};

  /// The sides each mode can deal square: N columns and N rows ([squareDims]).
  /// Cards and Squares deal every one. A size is left out only where some
  /// piece would be one of a kind and so could only start in its own place:
  /// Triangles have no 3x3 (three rows: each side edge holds one half
  /// triangle of its shape), Hexagons no 3x3 (the middle row's two halves)
  /// and no 4x4 or 6x6 (with an even number of rows the bottom corners are
  /// one of a kind, and on 4x4 the halves of the second row too). The 5x5
  /// triangle board starts with one joined pair of halves on each side edge,
  /// the fewest five rows allow ([Tiling.unavoidableJoins]). Seven across
  /// keeps cards about 55 pt wide on a phone; bigger boards are giant boards.
  static const squareSides = <GameMode, List<int>>{
    GameMode.cards: [3, 4, 5, 6, 7],
    GameMode.squares: [3, 4, 5, 6, 7],
    GameMode.triangles: [4, 5, 6, 7],
    GameMode.hexagons: [5, 7],
  };

  /// The square giant sizes (Large, Huge, Giant, Colossal) of each mode: the
  /// side nearest each of [giantTargets] that the tiling can deal. Cards
  /// 10x10 to 17x17 (100 to 289 cards); the other shapes keep their bigger
  /// counts, above every normal board ([BoardLayouts.giantFloor]).
  static const giantSquareSides = <GameMode, List<int>>{
    GameMode.cards: [10, 12, 14, 17],
    GameMode.squares: [13, 15, 18, 22],
    GameMode.triangles: [10, 13, 15, 18],
    GameMode.hexagons: [13, 15, 19, 23],
  };

  /// Columns and rows of the N x N board of [mode] (as [Tiling] counts them).
  /// A triangle column is one up and one down triangle, so a row of N
  /// columns holds 2N + 1 pieces (2N - 1 whole triangles and a half at each
  /// end) and the board is about as wide as it is tall; the others count
  /// pieces.
  static (int, int) squareDims(GameMode mode, int side) => mode == GameMode.triangles ? (2 * side + 1, side) : (side, side);

  /// Giant boards: the pictures of the Giant pack (`Pack.isGiant`) offer
  /// only these four sizes, tiers [firstGiantTier] and up, from about 100 to
  /// 300 cards. The pictures are large enough to stay sharp when zoomed in;
  /// every other picture keeps the normal ladder.
  static const giantLabels = ['Large', 'Huge', 'Giant', 'Colossal'];

  /// Tier index of the first giant size; codes carry it (`cards:12x14t8`).
  static const firstGiantTier = 8;

  /// Whether [tier] is a giant size.
  static bool isGiantTier(int tier) => tier >= firstGiantTier;

  /// Name of [tier] on either ladder.
  static String labelOf(int tier) =>
      isGiantTier(tier) ? giantLabels[(tier - firstGiantTier).clamp(0, giantLabels.length - 1)] : labels[tier.clamp(0, labels.length - 1)];

  /// Piece counts the giant sizes aim for (square and Expand alike). The
  /// other shapes scale like the normal ladders (smaller pieces, more of them).
  static const giantTargets = <GameMode, List<int>>{
    GameMode.cards: [100, 150, 200, 300],
    GameMode.squares: [160, 240, 320, 480],
    GameMode.triangles: [220, 330, 440, 660],
    GameMode.hexagons: [175, 260, 350, 525],
  };

  /// A giant size (see [giantLabels]).
  bool get isGiant => isGiantTier(tierIndex);

  /// Picture proportions used when the picture is not known yet (3:4
  /// portrait, the catalogue's most common shape).
  static const referenceAspect = 3 / 4;

  /// Piece count each tier of the picture-shaped ladder aims for ([tiers],
  /// the boards of older builds). Cards and squares keep the counts the game
  /// always had. Triangles and hexagons cover the whole picture with half
  /// pieces along the edges, which only shuffle cleanly from four rows of
  /// triangles and five rows of hexagons; that sets their smallest boards.
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

  /// The square boards of [mode] ([squareSides]), the same for every picture.
  static List<BoardSpec> squareTiers(GameMode mode) => _squares.putIfAbsent(
        mode,
        () => List.unmodifiable([
          for (final n in squareSides[mode]!) BoardSpec(mode, squareDims(mode, n).$1, squareDims(mode, n).$2, labels[squareTierOfSide[n]!], tier: squareTierOfSide[n]!),
        ]),
      );

  static final _squares = <GameMode, List<BoardSpec>>{};

  /// The four square giant sizes of [mode] ([giantSquareSides]; tiers
  /// [firstGiantTier] to [firstGiantTier] + 3).
  static List<BoardSpec> squareGiantTiers(GameMode mode) => _giantSquares.putIfAbsent(mode, () {
        final sides = giantSquareSides[mode]!;
        return List.unmodifiable([
          for (var i = 0; i < sides.length; i++) BoardSpec(mode, squareDims(mode, sides[i]).$1, squareDims(mode, sides[i]).$2, giantLabels[i], tier: firstGiantTier + i),
        ]);
      });

  static final _giantSquares = <GameMode, List<BoardSpec>>{};

  /// Expand: the tiers of [squareTiers] laid out for a picture of [aspect]
  /// (width ÷ height), about as many pieces each, in the columns and rows
  /// that suit the picture ([BoardLayouts.expandFor]).
  static List<BoardSpec> expandTiers(GameMode mode, double aspect) {
    final square = squareTiers(mode);
    final dims = BoardLayouts.expandFor(mode, aspect);
    return [for (var i = 0; i < dims.length; i++) BoardSpec(mode, dims[i].$1, dims[i].$2, square[i].label, tier: square[i].tier, expand: true)];
  }

  /// The eight-step ladder older builds dealt for a picture of [aspect]: its
  /// columns and rows followed the picture. Kept so their saves resume as
  /// they were and their codes still open (as Expand boards).
  static List<BoardSpec> tiers(GameMode mode, [double aspect = referenceAspect]) {
    final dims = BoardLayouts.forAspect(mode, aspect);
    return [for (var i = 0; i < dims.length; i++) BoardSpec(mode, dims[i].$1, dims[i].$2, labels[i], tier: i, expand: true)];
  }

  /// Expand on a giant picture: the four giant sizes laid out for a picture
  /// of [aspect] (the giant ladder older builds dealt; tiers [firstGiantTier]
  /// to [firstGiantTier] + 3).
  static List<BoardSpec> giantTiers(GameMode mode, [double aspect = referenceAspect]) {
    final dims = BoardLayouts.forAspect(mode, aspect, giant: true);
    return [for (var i = 0; i < dims.length; i++) BoardSpec(mode, dims[i].$1, dims[i].$2, giantLabels[i], tier: firstGiantTier + i, expand: true)];
  }

  /// How much more of the picture (a share of its area) Expand must show on
  /// some size for the switch to be offered.
  static const expandMinGain = 0.05;

  /// Whether a picture of [aspect] offers Expand in [mode]: some size of the
  /// Expand ladder shows noticeably more of the picture than its square
  /// board. Not when the square boards already suit the picture (a square
  /// picture in Squares, a 3:4 one in Cards), nor when Expand would crop as
  /// much (landscape pictures stay on portrait or square boards).
  static bool offersExpand(GameMode mode, double aspect, {bool giant = false}) {
    if (!aspect.isFinite || aspect <= 0) return false;
    final square = giant ? squareGiantTiers(mode) : squareTiers(mode);
    final natural = giant ? giantTiers(mode, aspect) : expandTiers(mode, aspect);
    for (var i = 0; i < square.length && i < natural.length; i++) {
      if (square[i].tiling.fitFor(aspect).crop - natural[i].tiling.fitFor(aspect).crop > expandMinGain) return true;
    }
    return false;
  }

  /// The ladder a picture of [aspect] offers: the giant sizes for the Giant
  /// pack, else the normal ones; square, or with [expand] laid out for the
  /// picture when it [offersExpand]. The boards carry [expand] either way, so
  /// the next picture is dealt the same way.
  static List<BoardSpec> ladder(GameMode mode, double aspect, {required bool giant, bool expand = false}) {
    final natural = expand && offersExpand(mode, aspect, giant: giant);
    final list = natural ? (giant ? giantTiers(mode, aspect) : expandTiers(mode, aspect)) : (giant ? squareGiantTiers(mode) : squareTiers(mode));
    return [for (final t in list) t.withExpand(expand)];
  }

  /// The board of [ladder] nearest to [tier] (a tie goes to the bigger one):
  /// a mode without that size offers the one next to it (Triangles have no
  /// 5x5, so Tricky gives way to Expert).
  static BoardSpec nearest(List<BoardSpec> ladder, int tier) {
    var best = ladder.first;
    for (final t in ladder) {
      final d = (t.tier - tier).abs(), b = (best.tier - tier).abs();
      if (d < b || (d == b && t.tier > best.tier)) best = t;
    }
    return best;
  }

  /// Tier [tier] of [mode] for a picture of [aspect] (a giant tier on the
  /// giant ladder), square or with [expand]; the nearest size its ladder has.
  static BoardSpec forPicture(GameMode mode, int tier, double aspect, {bool expand = false}) =>
      nearest(ladder(mode, aspect, giant: isGiantTier(tier), expand: expand), tier);

  /// This board's tier for a picture of [aspect], dealt the same way.
  BoardSpec fitTo(double aspect) => forPicture(mode, tierIndex < 0 ? 2 : tierIndex, aspect, expand: expand);

  /// Index of this spec in its mode's ladder, or -1 for custom sizes.
  int get tierIndex => tier >= 0 ? tier : _tierOf(mode, cols, rows);

  /// Pieces a finished board of [cells] pieces in [mode] counts as where a
  /// quest names a size ("a 4x4 or bigger board"): a square board counts as
  /// its side squared (the 4x4 triangle board, 36 pieces, is a 4x4; the 7x7
  /// honeycomb, 52, a 7x7), any other board as its pieces.
  static int sizeCells(GameMode mode, int cells) {
    for (final t in [...squareTiers(mode), ...squareGiantTiers(mode)]) {
      if (t.cells == cells) return t.rows * t.rows;
    }
    return cells;
  }

  /// The square board of [tier] in [mode], or null when the mode has none.
  static BoardSpec? squareAt(GameMode mode, int tier) {
    for (final t in isGiantTier(tier) ? squareGiantTiers(mode) : squareTiers(mode)) {
      if (t.tier == tier) return t;
    }
    return null;
  }

  /// Parses `mode:CxR`, `mode:CxRtT`, `CxR` (cards) or the URL forms
  /// `mode-CxR` / `mode-CxRtT`. A board other than its tier's square board
  /// is an Expand board; [expand] (a link's `?expand=1`) marks a square one
  /// as chosen with Expand too.
  static BoardSpec fromCode(String code, {bool expand = false}) {
    final d = BoardCode.decode(BoardCode.fromPath(code));
    final t = d.tier != null && d.tier! >= 0 && d.tier! < firstGiantTier + giantLabels.length ? d.tier! : _tierOf(d.mode, d.cols, d.rows);
    final square = t >= 0 ? squareAt(d.mode, t) : null;
    final natural = expand || square == null || square.cols != d.cols || square.rows != d.rows;
    return BoardSpec(d.mode, d.cols, d.rows, t >= 0 ? labelOf(t) : 'Custom', tier: t, expand: natural);
  }

  /// Ladder index of a board size given without a tier. Codes made by this
  /// version always carry the tier, so these are old links and saves (and
  /// shortcuts such as a quest's `5x5`): the square boards first, then the
  /// old fixed ladders, then the old ladders of the reference picture and
  /// the common picture shapes, then the tier whose target piece count is
  /// nearest.
  static int _tierOf(GameMode mode, int cols, int rows) {
    for (final t in [...squareTiers(mode), ...squareGiantTiers(mode)]) {
      if (t.cols == cols && t.rows == rows) return t.tier;
    }
    final legacy = _legacyLadders[mode]!.indexWhere((d) => d.$1 == cols && d.$2 == rows);
    if (legacy >= 0) return legacy;
    for (final a in [referenceAspect, ...commonAspects]) {
      final i = BoardLayouts.forAspect(mode, a).indexWhere((d) => d.$1 == cols && d.$2 == rows);
      if (i >= 0) return i;
    }
    final cells = Tiling.cellCount(mode, cols, rows);
    // Giant boards are never smaller than the biggest normal candidate.
    if (cells >= BoardLayouts.giantFloor(mode)) {
      for (final a in [referenceAspect, ...commonAspects]) {
        final i = BoardLayouts.forAspect(mode, a, giant: true).indexWhere((d) => d.$1 == cols && d.$2 == rows);
        if (i >= 0) return firstGiantTier + i;
      }
      final g = giantTargets[mode]!;
      var nearest = 0;
      for (var i = 1; i < g.length; i++) {
        if ((log(cells / g[i])).abs() < (log(cells / g[nearest])).abs()) nearest = i;
      }
      return firstGiantTier + nearest;
    }
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
  /// of [aspect]: a square board, else an Expand board, else a board of the
  /// ladder older builds dealt (their saves resume as they were, a 3x4 stays
  /// 3x4); null when no board of this picture has that many pieces (the save
  /// cannot be resumed). Where two boards of a picture have the same count
  /// (the 4x4 triangle board and an old 6x6 strip, 36 each), the saved
  /// [layout] names the one whose pieces it fits ([Board.isValidLayout];
  /// `test/square_boards_test.dart`). The normal and giant counts never
  /// overlap ([BoardLayouts.giantFloor]).
  static BoardSpec? fromSaved(GameMode mode, int cells, double aspect, {List<int>? layout}) {
    final giant = cells >= BoardLayouts.giantFloor(mode);
    final candidates = giant
        ? [...squareGiantTiers(mode), ...giantTiers(mode, aspect)]
        : [...squareTiers(mode), ...expandTiers(mode, aspect), ...tiers(mode, aspect)];
    BoardSpec? first;
    for (final t in candidates) {
      if (t.cells != cells) continue;
      if (layout == null || Board.isValidLayout(t, layout)) return t;
      first ??= t;
    }
    return layout == null ? first : null;
  }

  /// Best-effort recovery of a board from a saved cell count when the
  /// picture is not at hand: a square board with that many pieces, else a
  /// board with that many pieces for a common picture shape, else the old
  /// fixed ladder, else the Relaxed square board. The game screen settles
  /// the exact layout once the picture is loaded.
  static BoardSpec fromCells(GameMode mode, int cells) {
    for (final t in [...squareTiers(mode), ...squareGiantTiers(mode)]) {
      if (t.cells == cells) return t;
    }
    for (final a in [referenceAspect, ...commonAspects]) {
      final hit = fromSaved(mode, cells, a);
      if (hit != null) return hit;
    }
    final legacy = _legacyLadders[mode]!.indexWhere((d) => d.$1 * d.$2 == cells);
    if (legacy >= 0) {
      final d = _legacyLadders[mode]![legacy];
      return BoardSpec(mode, d.$1, d.$2, labels[legacy], tier: legacy, expand: true);
    }
    return nearest(squareTiers(mode), 2);
  }

  @override
  bool operator ==(Object other) => other is BoardSpec && other.mode == mode && other.cols == cols && other.rows == rows;
  @override
  int get hashCode => Object.hash(mode, cols, rows);
}

/// Chooses the boards of a mode for a picture's proportions: the Expand
/// ladder ([expandFor]), and the picture-shaped ladders older builds dealt
/// and giant pictures deal with Expand ([forAspect]).
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

  /// Fewest pieces a tier of the old eight-step ladder may have, whatever
  /// the picture: goals and achievements count boards of 25 ("5x5 or
  /// bigger", reached from Tricky), 36 (Expert) and 48 (Master) pieces.
  static const minCells = [0, 0, 0, 0, 25, 0, 36, 48];

  /// Fewest pieces an Expand size may have, by tier: the counts quests and
  /// achievements look for (16 for "4x4 or bigger", 25, 36 and 48), so an
  /// Expand board counts wherever its square board would.
  static const expandFloors = <int, int>{2: 16, 4: 25, 6: 36, 7: 48};

  /// Column/row counts of the eight tiers of the ladder older builds dealt
  /// for [mode] and a picture of [imageAspect], or with [giant] the four
  /// giant sizes (Expand on a giant picture). Landscape pictures are treated
  /// as square (the board stays portrait or square and the picture is
  /// cropped); very tall ones as 1:2.
  static List<(int, int)> forAspect(GameMode mode, double imageAspect, {bool giant = false}) {
    final a = _clamp(imageAspect);
    final key = '${giant ? 'giant:' : ''}${mode.code}:${a.toStringAsFixed(6)}';
    return _cache.putIfAbsent(key, () => giant ? _solveGiant(mode, a) : _solve(mode, a));
  }

  /// Expand: column/row counts for the square tiers of [mode]
  /// ([BoardSpec.squareTiers]) on a picture of [imageAspect], each aiming
  /// at its square board's piece count (at least [expandFloors]), chosen
  /// and shaped as [forAspect] chooses them.
  static List<(int, int)> expandFor(GameMode mode, double imageAspect) {
    final a = _clamp(imageAspect);
    return _cache.putIfAbsent('expand:${mode.code}:${a.toStringAsFixed(6)}', () {
      final square = BoardSpec.squareTiers(mode);
      return _pick(mode, a, _expandCandidates(mode), [for (final t in square) t.cells], [for (final t in square) expandFloors[t.tier] ?? 0]);
    });
  }

  static double _clamp(double aspect) => (!aspect.isFinite || aspect <= 0 ? BoardSpec.referenceAspect : aspect).clamp(0.5, 1.0);

  /// Most pieces a normal tier of [mode] may have.
  static double _normalCeiling(GameMode mode) {
    final clipped = mode == GameMode.triangles || mode == GameMode.hexagons;
    return BoardSpec.targets[mode]!.last * (clipped ? 1.45 : 1.3);
  }

  /// Fewest pieces a giant size of [mode] may have: above every normal
  /// candidate, so a saved piece count always names one ladder.
  static int giantFloor(GameMode mode) => max(_normalCeiling(mode).floor() + 1, (BoardSpec.giantTargets[mode]!.first * 0.8).round());

  /// Sizes the old eight-step ladder of [mode] chooses from.
  static List<(int, int)> candidates(GameMode mode) => _candidates.putIfAbsent(mode, () => _shaped(mode, BoardSpec.targets[mode]!.first * 0.6, _normalCeiling(mode)));

  static final _candidates = <GameMode, List<(int, int)>>{};

  /// Sizes the Expand ladder of [mode] chooses from: the same shapes around
  /// the square boards' piece counts; triangle rows a whole number of
  /// columns wide, so every size reads as columns x rows ([BoardSpec.size]).
  static List<(int, int)> _expandCandidates(GameMode mode) => _expandCands.putIfAbsent(mode, () {
        final square = BoardSpec.squareTiers(mode);
        final clipped = mode == GameMode.triangles || mode == GameMode.hexagons;
        return _shaped(mode, square.first.cells * 0.6, square.last.cells * (clipped ? 1.45 : 1.3), wholeColumns: true);
      });

  static final _expandCands = <GameMode, List<(int, int)>>{};

  /// Normal-sized boards of [mode] with [lo] to [hi] pieces that suit a
  /// picture: portrait or square, sorted by piece count.
  static List<(int, int)> _shaped(GameMode mode, double lo, double hi, {bool wholeColumns = false}) {
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
            if (wholeColumns && (c - 1).isOdd) continue;
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
  }

  /// Sizes the giant ladder of [mode] chooses from: the same shape rules as
  /// [candidates] with many more rows and columns.
  static List<(int, int)> giantCandidates(GameMode mode) => _giantCandidates.putIfAbsent(mode, () {
        final t = BoardSpec.giantTargets[mode]!;
        final clipped = mode == GameMode.triangles || mode == GameMode.hexagons;
        final lo = giantFloor(mode), hi = t.last * (clipped ? 1.45 : 1.3);
        final out = <(int, int)>[];
        void add(int c, int r) {
          final cells = Tiling.cellCount(mode, c, r);
          if (cells < lo || cells > hi) return;
          final (a, b) = Tiling.of(mode, c, r).aspectRange;
          if (a > 1.0 || b < 0.5) return;
          out.add((c, r));
        }

        switch (mode) {
          case GameMode.cards || GameMode.squares:
            for (var r = 6; r <= 40; r++) {
              for (var c = 6; c <= 36; c++) {
                add(c, r);
              }
            }
          case GameMode.triangles:
            for (var r = 6; r <= 36; r++) {
              for (var c = 8; c <= 64; c++) {
                add(c, r);
              }
            }
          case GameMode.hexagons:
            for (var r = 9; r <= 51; r += 2) {
              for (var c = 4; c <= 36; c++) {
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

  static final _giantCandidates = <GameMode, List<(int, int)>>{};

  /// Score of [dims] in [mode] for a picture of [aspect], as a size aiming
  /// at [target] pieces.
  static double score(GameMode mode, (int, int) dims, int target, double aspect) {
    final f = Tiling.of(mode, dims.$1, dims.$2).fitFor(aspect);
    final clipped = mode == GameMode.triangles || mode == GameMode.hexagons;
    final cropWeight = clipped ? 4.0 : 1.0;
    final stretchWeight = mode == GameMode.cards ? 0.5 : 0.3;
    final countWeight = clipped ? 0.15 : 0.25;
    final cells = Tiling.cellCount(mode, dims.$1, dims.$2);
    return cropWeight * (f.crop + 3 * max(0, f.crop - 0.05)) + stretchWeight * f.stretch + countWeight * (log(cells / target)).abs();
  }

  static List<(int, int)> _solve(GameMode mode, double aspect) => _pick(mode, aspect, candidates(mode), BoardSpec.targets[mode]!, minCells);

  static List<(int, int)> _solveGiant(GameMode mode, double aspect) => _pick(mode, aspect, giantCandidates(mode), BoardSpec.giantTargets[mode]!, const [0, 0, 0, 0]);

  /// One size per entry of [targets] out of [cands] (sorted by piece count)
  /// at the lowest total [score], each at least [minStep] bigger than the one
  /// before and at least [floors] pieces.
  static List<(int, int)> _pick(GameMode mode, double aspect, List<(int, int)> cands, List<int> targets, List<int> floors) {
    final n = cands.length, k = targets.length;
    final counts = [for (final d in cands) Tiling.cellCount(mode, d.$1, d.$2)];
    final best = List.generate(k, (_) => List<double>.filled(n, double.infinity));
    final prev = List.generate(k, (_) => List<int>.filled(n, -1));
    for (var i = 0; i < n; i++) {
      if (counts[i] < floors[0]) continue;
      best[0][i] = score(mode, cands[i], targets[0], aspect);
    }
    for (var t = 1; t < k; t++) {
      for (var i = 0; i < n; i++) {
        if (counts[i] < floors[t]) continue;
        final s = score(mode, cands[i], targets[t], aspect);
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

/// Cards-mode spec on the original fixed ladder. Kept so settings and quest
/// keys made before square boards keep their tier names and sizes
/// (`GridSpec.tiers`, `.code`, `.label`); the sizes quests and level rewards
/// name now are the square ones ([square]). Boards themselves come from
/// [BoardSpec.ladder].
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

  /// The square Cards boards (the Cards entries of [BoardSpec.squareTiers]):
  /// 3x3 Cozy, 4x4 Relaxed, 5x5 Tricky, 6x6 Expert, 7x7 Master.
  static const square = <GridSpec>[
    GridSpec(3, 3, 'Cozy', tier: 0),
    GridSpec(4, 4, 'Relaxed', tier: 2),
    GridSpec(5, 5, 'Tricky', tier: 4),
    GridSpec(6, 6, 'Expert', tier: 6),
    GridSpec(7, 7, 'Master', tier: 7),
  ];

  static GridSpec fromCells(int cells) => tiers.firstWhere((t) => t.cells == cells, orElse: () => tiers[2]);
  static GridSpec fromCode(String code) => tiers.firstWhere((t) => t.code == code, orElse: () => tiers[2]);

  /// The size named by [code] (`5x5`, or `4x5` in a quest made before square boards), or null.
  static GridSpec? byCode(String code) => square.where((t) => t.code == code).firstOrNull ?? tiers.where((t) => t.code == code).firstOrNull;

  /// The Cards size with [cells] cards (square first), or null.
  static GridSpec? byCells(int cells) => square.where((t) => t.cells == cells).firstOrNull ?? tiers.where((t) => t.cells == cells).firstOrNull;

  /// The smallest square size of at least [cells] cards (a quest's "or bigger" shortcut), else Master.
  static GridSpec atLeast(int cells) => square.firstWhere((t) => t.cells >= cells, orElse: () => square.last);
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

  /// Moves the whole group containing [slot] by a lattice delta. Returns null
  /// when the move is not allowed (out of bounds, placement rule broken, onto
  /// cards locked in place, or the group itself is locked in place).
  ///
  /// The cards in the destination make room. Another group the move lands on
  /// stays whole when it can (owner, 2026-10-17): largest first, it shifts by
  /// one lattice step ([_pushStep]) onto cells that are free after the move
  /// (the ones the moving group left, its own) or that hold loose cards, which
  /// then make room in turn. A group with no such place breaks, as before.
  /// The cards still without a cell fill the free cells in reading order, each
  /// within its own shape class (a half piece only ever lands in a half slot),
  /// so a move that lands on no other group is a plain swap or shift. Locked
  /// cards never move, and the result depends only on the board and the move.
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
    for (var i = 0; i < group.length; i++) {
      next[dest[i]] = slots[group[i]];
    }
    // Cells waiting for a card, and the cards waiting for a cell (by the slot each comes from).
    final free = <int>{for (final s in group) if (!destSet.contains(s)) s};
    final pool = <int>{for (final d in dest) if (!groupSet.contains(d)) d};
    final pushed = <List<int>>[];
    final seen = <int>{};
    for (final d in pool) {
      if (groupOf(d).length > 1 && seen.add(_groups[d])) pushed.add(groupOf(d));
    }
    if (pushed.isNotEmpty) {
      pushed.sort((a, b) => a.length != b.length ? b.length - a.length : a.first - b.first);
      // Loose cells a pushed group has already taken.
      final taken = <int>{};
      bool loose(int s) => !destSet.contains(s) && !groupSet.contains(s) && !taken.contains(s) && !isLocked(s) && groupOf(s).length == 1;
      for (final g in pushed) {
        final own = <int>{for (final s in g) if (!destSet.contains(s)) s};
        final step = _pushStep(g, (s) => free.contains(s) || own.contains(s) || loose(s), loose, dx, dy);
        if (step == null) continue;
        for (final s in g) {
          final to = tiling.apply(s, step.$1, step.$2)!;
          next[to] = slots[s];
          if (!free.remove(to) && !own.remove(to)) {
            // A loose card makes room in turn.
            taken.add(to);
            pool.add(to);
          }
        }
        pool.removeAll(g);
        free.addAll(own);
      }
    }
    final into = free.toList()..sort();
    final from = pool.toList()..sort();
    for (var cls = 0; cls < tiling.classCount; cls++) {
      final cells = [for (final v in into) if (tiling.classOf(v) == cls) v];
      final cards = [for (final d in from) if (tiling.classOf(d) == cls) d];
      for (var i = 0; i < cells.length && i < cards.length; i++) {
        next[cells[i]] = slots[cards[i]];
      }
    }
    return Board(spec, next);
  }

  /// The lattice step that keeps the pushed group [g] whole: every card lands
  /// on a cell [open] allows, in a slot of its own shape. Of those, the step
  /// that displaces the fewest [loose] cards, then the shortest, then the one
  /// most against the move ([dx], [dy]), so two groups of one shape simply
  /// trade places. Null when there is none.
  (int, int)? _pushStep(List<int> g, bool Function(int slot) open, bool Function(int slot) loose, int dx, int dy) {
    final anchor = g.first;
    final cls = tiling.classOf(anchor);
    final move = _stepVector(dx, dy);
    (int, int)? best;
    var bestLoose = 0;
    var bestLength = 0.0, bestAgainst = 0.0;
    for (var c = 0; c < cells; c++) {
      if (c == anchor || tiling.classOf(c) != cls || !open(c)) continue;
      final t = tiling.delta(anchor, c);
      if (t == null) continue;
      var displaced = 0;
      var fits = true;
      for (final s in g) {
        final to = tiling.apply(s, t.$1, t.$2);
        if (to == null || !open(to)) {
          fits = false;
          break;
        }
        if (loose(to)) displaced++;
      }
      if (!fits) continue;
      final v = _stepVector(t.$1, t.$2);
      final length = v.$1 * v.$1 + v.$2 * v.$2, against = v.$1 * move.$1 + v.$2 * move.$2;
      const eps = 1e-9;
      final better = best == null ||
          displaced < bestLoose ||
          (displaced == bestLoose && (length < bestLength - eps || ((length - bestLength).abs() <= eps && against < bestAgainst - eps)));
      if (better) {
        best = t;
        bestLoose = displaced;
        bestLength = length;
        bestAgainst = against;
      }
    }
    return best;
  }

  /// A lattice step as a distance on the picture, in cells, so steps compare
  /// in every shape (triangle half-steps and rows, doubled hexagon columns).
  (double, double) _stepVector(int dx, int dy) => switch (tiling) {
        GridTiling(:final cellAspect) => (dx * cellAspect, dy.toDouble()),
        _ => (dx * 0.5, dy * 0.866),
      };

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
  /// resort does the board keep a join: a tiling whose edge pieces cannot all
  /// part (the five-row triangle board, [Tiling.unavoidableJoins]) keeps the
  /// fewest it must. It never keeps a fixed point.
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
      if (_fixedPoints(perm) == 0 && _joins(tiling, perm) <= tiling.unavoidableJoins) return Board(spec, perm);
    }
    List<int>? best;
    var bestJoins = 1 << 30;
    for (var round = 0; round < 24; round++) {
      final perm = random();
      _derange(perm, classes, rng);
      final joins = _breakJoins(perm, tiling, classes, rng);
      if (joins <= tiling.unavoidableJoins) return Board(spec, perm);
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
    for (var iter = 0; iter < 4000 && joins > tiling.unavoidableJoins; iter++) {
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
