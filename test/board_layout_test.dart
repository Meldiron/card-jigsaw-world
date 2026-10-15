import 'dart:math' as math;
import 'dart:ui';

import 'package:carden/game/board.dart';
import 'package:flutter_test/flutter_test.dart';

/// Boards follow the picture: squares stay square, cards keep playing-card
/// proportions, triangles and hexagons cover the whole picture with half
/// pieces along the edges. Every board on offer must shuffle into a start
/// with no card in place and no joined pair.
void main() {
  /// Portrait and square pictures every 0.01, plus landscape ones (cropped)
  /// and the extremes.
  final aspects = <double>[
    for (var i = 0; i <= 50; i++) 0.5 + i * 0.01,
    9 / 16, 2 / 3, 3 / 4, 4 / 5, 939 / 893, 4 / 3, 16 / 9, 0.3, 900 / 21,
  ];

  /// Every distinct board offered for those pictures, per mode.
  Map<GameMode, Set<BoardSpec>> offered() => {
        for (final mode in GameMode.values)
          mode: {
            for (final a in aspects) ...BoardSpec.tiers(mode, a),
          },
      };

  test('every tier list has eight boards with strictly growing piece counts', () {
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
      }
    }
    // A quest's "5x5 or bigger" shortcut opens the Tricky tier.
    expect(BoardSpec.fromCode('5x5').tierIndex, 4);
  });

  test('squares cells are square within 1 % for every board on offer and every picture', () {
    for (final a in aspects) {
      for (final spec in BoardSpec.tiers(GameMode.squares, a)) {
        final size = spec.tiling.fit(const Size(369, 450), a);
        final cell = spec.tiling.cellBounds(0, size);
        expect(cell.width / cell.height, closeTo(1, 0.01), reason: '${spec.code} for a $a picture');
      }
    }
  });

  test('cards are portrait, close to 5:7 and never near square', () {
    for (final a in aspects) {
      for (final spec in BoardSpec.tiers(GameMode.cards, a)) {
        final size = spec.tiling.fit(const Size(369, 450), a);
        final cell = spec.tiling.cellBounds(0, size);
        final r = cell.width / cell.height;
        expect(r, inInclusiveRange(0.64, 0.78), reason: '${spec.code} for a $a picture: cell $r');
      }
    }
  });

  test('the feedback picture (939 x 893) gets square squares and card-shaped cards', () {
    const a = 939 / 893;
    final squares = BoardSpec.forPicture(GameMode.squares, 2, a);
    expect(squares.cols, squares.rows, reason: 'a square picture is cut into a square grid of squares');
    final cards = BoardSpec.forPicture(GameMode.cards, 2, a);
    expect(cards.cols, greaterThan(cards.rows), reason: 'portrait cards on a square picture need more columns than rows');
    for (final spec in [...BoardSpec.tiers(GameMode.squares, a), ...BoardSpec.tiers(GameMode.cards, a)]) {
      expect(spec.tiling.fitFor(a).crop, lessThan(0.15), reason: '${spec.fullCode} crops little');
    }
  });

  test('triangles and hexagons cover common portrait pictures nearly whole', () {
    for (final mode in [GameMode.triangles, GameMode.hexagons]) {
      for (final a in [9 / 16, 2 / 3, 3 / 4, 4 / 5, 1.0]) {
        for (final spec in BoardSpec.tiers(mode, a)) {
          final f = spec.tiling.fitFor(a);
          expect(f.crop, lessThan(0.07), reason: '${spec.fullCode} on $a crops ${f.crop}');
          expect(f.stretch, lessThanOrEqualTo(spec.tiling.stretchTolerance / (1 - spec.tiling.stretchTolerance) + 1e-9), reason: '${spec.fullCode} on $a');
        }
      }
    }
  });

  test('every placement class has at least two slots on every board on offer', () {
    for (final entry in offered().entries) {
      for (final spec in entry.value) {
        final t = spec.tiling;
        expect(t.cells, spec.cells, reason: spec.fullCode);
        final counts = <int, int>{};
        for (var s = 0; s < t.cells; s++) {
          counts[t.classOf(s)] = (counts[t.classOf(s)] ?? 0) + 1;
        }
        expect(counts.length, t.classCount, reason: spec.fullCode);
        for (final c in counts.entries) {
          expect(c.value, greaterThanOrEqualTo(2), reason: '${spec.fullCode} class ${c.key} is one of a kind');
        }
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
          expect(b.joinCount, 0, reason: '$why: a pair starts joined');
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
    final spec = BoardSpec.forPicture(GameMode.squares, 3, 1.0);
    expect(spec.fullCode, 'squares:${spec.code}t3');
    final back = BoardSpec.fromCode(BoardCode.toPath(spec.fullCode));
    expect(back, spec);
    expect(back.tier, 3);
    expect(back.label, 'Medium');
    // Legacy codes: old fixed ladders.
    expect(BoardSpec.fromCode('squares-4x6').tierIndex, 2);
    expect(BoardSpec.fromCode('4x4').mode, GameMode.cards);
    expect(BoardSpec.fromCode('hexagons-7x10').tierIndex, 7);
    // Following the next picture keeps the tier.
    expect(spec.fitTo(0.75).tier, 3);
    expect(spec.fitTo(0.75), BoardSpec.forPicture(GameMode.squares, 3, 0.75));
    // A save resumes on the board with its piece count for this picture.
    final t = BoardSpec.forPicture(GameMode.hexagons, 4, 0.75);
    expect(BoardSpec.fromSaved(GameMode.hexagons, t.cells, 0.75), t);
    expect(BoardSpec.fromSaved(GameMode.hexagons, 30, 0.75), isNull, reason: 'the old 5x6 honeycomb no longer exists');
    expect(BoardSpec.fromCells(GameMode.squares, BoardSpec.tiers(GameMode.squares)[5].cells), BoardSpec.tiers(GameMode.squares)[5]);
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
