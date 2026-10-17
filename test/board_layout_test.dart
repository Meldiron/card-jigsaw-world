import 'dart:math' as math;
import 'dart:ui';

import 'package:carden/game/board.dart';
import 'package:flutter_test/flutter_test.dart';

/// Boards that follow the picture (Expand, and the ladder older builds
/// dealt): squares stay square, cards keep playing-card proportions,
/// triangles and hexagons cover the whole picture with half pieces along the
/// edges. Every board on offer, square ones included, must shuffle into a
/// start with no card in place and no joined pair. Square boards themselves:
/// `test/square_boards_test.dart`.
void main() {
  /// Portrait and square pictures every 0.01, plus landscape ones (cropped)
  /// and the extremes.
  final aspects = <double>[
    for (var i = 0; i <= 50; i++) 0.5 + i * 0.01,
    9 / 16, 2 / 3, 3 / 4, 4 / 5, 939 / 893, 4 / 3, 16 / 9, 0.3, 900 / 21,
  ];

  /// Every distinct board offered for those pictures, per mode: square,
  /// Expand and the boards older builds dealt (they still resume).
  Map<GameMode, Set<BoardSpec>> offered() => {
        for (final mode in GameMode.values)
          mode: {
            ...BoardSpec.squareTiers(mode),
            for (final a in aspects) ...[...BoardSpec.expandTiers(mode, a), ...BoardSpec.tiers(mode, a)],
          },
      };

  /// The picture-shaped ladders: Expand and the old one.
  List<BoardSpec> shaped(GameMode mode, double a) => [...BoardSpec.expandTiers(mode, a), ...BoardSpec.tiers(mode, a)];

  test('the old ladder keeps eight boards with strictly growing piece counts', () {
    for (final mode in GameMode.values) {
      for (final a in aspects) {
        final tiers = BoardSpec.tiers(mode, a);
        expect(tiers.length, 8);
        for (var i = 0; i < 8; i++) {
          expect(tiers[i].tier, i);
          expect(tiers[i].label, BoardSpec.labels[i]);
          if (i > 0) expect(tiers[i].cells, greaterThan(tiers[i - 1].cells), reason: '${mode.code} at $a: ${tiers.map((t) => t.code)}');
        }
      }
    }
  });

  test('goal and achievement thresholds hold on every picture: Tricky >= 25, Expert >= 36, Master >= 48 pieces', () {
    for (final mode in GameMode.values) {
      for (final a in aspects) {
        final tiers = BoardSpec.tiers(mode, a);
        expect(tiers[4].cells, greaterThanOrEqualTo(25), reason: '${mode.code} at $a');
        expect(tiers[6].cells, greaterThanOrEqualTo(36), reason: '${mode.code} at $a');
        expect(tiers[7].cells, greaterThanOrEqualTo(48), reason: '${mode.code} at $a');
        // Expand counts wherever its square board would (16 for Relaxed too).
        for (final t in BoardSpec.expandTiers(mode, a)) {
          expect(t.cells, greaterThanOrEqualTo(BoardLayouts.expandFloors[t.tier] ?? 0), reason: '${mode.code} ${t.label} at $a');
        }
      }
    }
    // A quest's "5x5 or bigger" shortcut opens the Tricky tier.
    expect(BoardSpec.fromCode('5x5').tierIndex, 4);
  });

  test('squares cells are square within 1 % for every board on offer and every picture', () {
    for (final a in aspects) {
      for (final spec in [...BoardSpec.squareTiers(GameMode.squares), ...shaped(GameMode.squares, a)]) {
        final size = spec.tiling.fit(const Size(369, 450), a);
        final cell = spec.tiling.cellBounds(0, size);
        expect(cell.width / cell.height, closeTo(1, 0.01), reason: '${spec.code} for a $a picture');
      }
    }
  });

  test('cards are portrait, close to 5:7 and never near square', () {
    for (final a in aspects) {
      for (final spec in [...BoardSpec.squareTiers(GameMode.cards), ...shaped(GameMode.cards, a)]) {
        final size = spec.tiling.fit(const Size(369, 450), a);
        final cell = spec.tiling.cellBounds(0, size);
        final r = cell.width / cell.height;
        expect(r, inInclusiveRange(0.64, 0.78), reason: '${spec.code} for a $a picture: cell $r');
      }
    }
  });

  test('the feedback picture (939 x 893) gets square squares and card-shaped cards', () {
    const a = 939 / 893;
    final squares = BoardSpec.forPicture(GameMode.squares, 2, a, expand: true);
    expect(squares.cols, squares.rows, reason: 'a square picture is cut into a square grid of squares');
    expect(BoardSpec.offersExpand(GameMode.squares, a), isFalse, reason: 'square enough: no Expand in Squares');
    final cards = BoardSpec.forPicture(GameMode.cards, 2, a, expand: true);
    expect(cards.cols, greaterThan(cards.rows), reason: 'with Expand, portrait cards on a square picture need more columns than rows');
    for (final spec in [...shaped(GameMode.squares, a), ...shaped(GameMode.cards, a)]) {
      expect(spec.tiling.fitFor(a).crop, lessThan(0.15), reason: '${spec.fullCode} crops little');
    }
  });

  test('with Expand, triangles and hexagons cover common portrait pictures nearly whole', () {
    // The sizes added with pre-set pieces (3x3 triangles, 4x4 and 6x6 honeycombs) have fewer
    // shapes to choose from: their Expand board never crops more than their square board.
    const added = {GameMode.triangles: [0], GameMode.hexagons: [2, 6]};
    for (final mode in [GameMode.triangles, GameMode.hexagons]) {
      for (final a in [9 / 16, 2 / 3, 3 / 4, 4 / 5, 1.0]) {
        for (final spec in shaped(mode, a)) {
          final f = spec.tiling.fitFor(a);
          if (spec.expand && added[mode]!.contains(spec.tier) && BoardSpec.expandTiers(mode, a).contains(spec)) {
            expect(f.crop, lessThanOrEqualTo(BoardSpec.squareAt(mode, spec.tier)!.tiling.fitFor(a).crop + 0.01), reason: '${spec.fullCode} on $a crops ${f.crop}');
          } else {
            expect(f.crop, lessThan(0.07), reason: '${spec.fullCode} on $a crops ${f.crop}');
          }
          expect(f.stretch, lessThanOrEqualTo(spec.tiling.stretchTolerance / (1 - spec.tiling.stretchTolerance) + 1e-9), reason: '${spec.fullCode} on $a');
        }
      }
    }
  });

  test('a piece is one of a kind only where it is pre-set, and only on the small boards that need it', () {
    for (final entry in offered().entries) {
      for (final spec in entry.value) {
        final t = spec.tiling;
        expect(t.cells, spec.cells, reason: spec.fullCode);
        final counts = <int, int>{};
        for (var s = 0; s < t.cells; s++) {
          counts[t.classOf(s)] = (counts[t.classOf(s)] ?? 0) + 1;
        }
        expect(counts.length, t.classCount, reason: spec.fullCode);
        for (var s = 0; s < t.cells; s++) {
          expect(t.isPreset(s), counts[t.classOf(s)] == 1, reason: '${spec.fullCode} slot $s');
        }
        // Three rows of triangles (two middle halves), the 4x4 honeycomb (four) and the 6x6 one (two).
        final expected = switch (spec.mode) {
          GameMode.triangles when spec.rows == 3 => 2,
          GameMode.hexagons when spec.cols == 4 && spec.rows == 4 => 4,
          GameMode.hexagons when spec.cols == 6 && spec.rows == 6 => 2,
          _ => 0,
        };
        expect(t.presetCount, expected, reason: spec.fullCode);
        expect(spec.playableCells, spec.cells - expected);
      }
    }
  });

  test('the start shuffle never places a piece and never starts with a joined pair, edge pieces included', () {
    for (final entry in offered().entries) {
      for (final spec in entry.value) {
        for (var seed = 0; seed < 6; seed++) {
          final b = Board.shuffled(spec, seed: seed);
          final why = '${spec.fullCode} seed $seed';
          expect(b.lockedCount, 0, reason: '$why: a piece starts in place');
          // Only the 5x5 triangle board (a pair of halves on each side edge) and the 4x4 honeycomb (a pair in
          // its bottom row of three) keep joined pairs (Tiling.unavoidableJoins); pre-set pieces are not counted.
          expect(b.joinCount, lessThanOrEqualTo(spec.tiling.unavoidableJoins), reason: '$why: a pair starts joined');
          expect(Board.isValidLayout(spec, b.slots), isTrue, reason: '$why: every piece sits in a slot of its own shape');
        }
      }
    }
  });

  test('clipped boards: pieces tile the board exactly and edge pieces are not slivers', () {
    for (final mode in [GameMode.triangles, GameMode.hexagons]) {
      for (final spec in offered()[mode]!) {
        final t = spec.tiling;
        for (final a in [0.5625, 0.75, 1.0]) {
          final size = t.fit(const Size(400, 500), a);
          var area = 0.0, full = 0.0;
          for (var s = 0; s < t.cells; s++) {
            final p = t.polygon(s, size);
            final ar = _area(p);
            area += ar;
            full = math.max(full, ar);
            for (final v in p) {
              expect(v.dx, inInclusiveRange(-1e-6, size.width + 1e-6), reason: '${spec.fullCode} slot $s inside the board');
              expect(v.dy, inInclusiveRange(-1e-6, size.height + 1e-6), reason: '${spec.fullCode} slot $s inside the board');
            }
          }
          expect(area, closeTo(size.width * size.height, size.width * size.height * 1e-6), reason: '${spec.fullCode} covers the board once');
          for (var s = 0; s < t.cells; s++) {
            final p = t.polygon(s, size);
            expect(_area(p), greaterThan(full * 0.25), reason: '${spec.fullCode} slot $s is a sliver');
          }
        }
      }
    }
  });

  test('codes carry the tier, and old codes and saves map onto a tier', () {
    final spec = BoardSpec.forPicture(GameMode.squares, 4, 0.75, expand: true);
    expect(spec.fullCode, 'squares:${spec.code}t4');
    final back = BoardSpec.fromCode(BoardCode.toPath(spec.fullCode));
    expect(back, spec);
    expect(back.tier, 4);
    expect(back.label, 'Tricky');
    expect(back.expand, isTrue, reason: 'a board that is not square is an Expand board');
    // A code of the old ladder (Medium has no square board) is an Expand board of its tier.
    final medium = BoardSpec.fromCode('squares-5x6t3');
    expect(medium.expand, isTrue);
    expect(medium.label, 'Medium');
    // Legacy codes: old fixed ladders.
    expect(BoardSpec.fromCode('squares-4x6').tierIndex, 2);
    expect(BoardSpec.fromCode('4x4').mode, GameMode.cards);
    expect(BoardSpec.fromCode('hexagons-7x10').tierIndex, 7);
    // Following the next picture keeps the tier and Expand.
    expect(back.fitTo(2 / 3).tier, 4);
    expect(back.fitTo(2 / 3), BoardSpec.forPicture(GameMode.squares, 4, 2 / 3, expand: true));
    expect(back.fitTo(2 / 3).expand, isTrue);
    expect(medium.fitTo(0.75).tier, anyOf(2, 4), reason: 'the nearest tier Expand deals');
    // A save resumes on the board with its piece count for this picture.
    final t = BoardSpec.forPicture(GameMode.hexagons, 7, 0.75, expand: true);
    expect(BoardSpec.fromSaved(GameMode.hexagons, t.cells, 0.75), t);
    expect(BoardSpec.fromSaved(GameMode.hexagons, 30, 0.75), isNull, reason: 'the old 5x6 honeycomb no longer exists');
    final old = BoardSpec.tiers(GameMode.squares)[5];
    expect(BoardSpec.fromCells(GameMode.squares, old.cells), old);
  });

  test('saves from before a layout changed are rejected', () {
    final spec = BoardSpec.forPicture(GameMode.triangles, 2, 0.75);
    final good = Board.shuffled(spec, seed: 1).slots;
    expect(Board.isValidLayout(spec, good), isTrue);
    expect(Board.isValidLayout(spec, good.sublist(1)), isFalse, reason: 'wrong length');
    expect(Board.isValidLayout(spec, [...good.sublist(1), good.first + 1000]), isFalse, reason: 'not a permutation');
    // Swap a half piece with a whole one: same length, wrong shapes.
    final t = spec.tiling;
    final half = List.generate(t.cells, (i) => i).firstWhere((s) => t.classOf(s) != t.classOf(t.cells ~/ 2));
    final bad = List<int>.of(good);
    final i = bad.indexOf(half), j = t.cells ~/ 2;
    final tmp = bad[i];
    bad[i] = bad[j];
    bad[j] = tmp;
    expect(Board.isValidLayout(spec, bad), isFalse, reason: 'a piece in a slot of another shape');
    // Old triangle 6x4 saves (24 cards, the old orientation) do not resume.
    final old = [for (var s = 0; s < 24; s++) s];
    final idx = List<int>.generate(24, (i) => i)..shuffle(math.Random(2));
    expect(Board.isValidLayout(BoardSpec.fromCells(GameMode.triangles, 24), [for (final k in idx) old[k]]), isFalse);
  });
}

double _area(List<Offset> p) {
  var a = 0.0;
  for (var i = 0; i < p.length; i++) {
    final u = p[i], v = p[(i + 1) % p.length];
    a += u.dx * v.dy - v.dx * u.dy;
  }
  return a.abs() / 2;
}
