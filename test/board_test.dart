import 'dart:math' as math;
import 'dart:ui';

import 'package:carden/game/board.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const g3 = GridSpec(3, 3, 'Cozy');

  group('Board basics', () {
    test('shuffled boards of 12+ cards are full derangements', () {
      for (var seed = 0; seed < 50; seed++) {
        final b = Board.shuffled(const GridSpec(4, 4, 'Relaxed'), seed: seed);
        expect(b.isSolved, isFalse);
        expect(b.lockedCount, 0, reason: 'seed $seed');
      }
    });

    test('every tier of every mode starts with zero locked cards and zero joined pairs', () {
      for (final mode in GameMode.values) {
        for (final t in BoardSpec.tiers(mode)) {
          for (var seed = 0; seed < 60; seed++) {
            final b = Board.shuffled(t, seed: seed);
            final why = '${mode.code} ${t.code} seed $seed';
            expect(b.lockedCount, 0, reason: why);
            expect(b.joinCount, 0, reason: why);
            expect(b.floatingGroups, 0, reason: why);
            expect(List<int>.of(b.slots)..sort(), List.generate(t.cells, (i) => i), reason: '$why is a permutation');
          }
        }
      }
    });

    test('unseeded shuffles are also derangements without joins', () {
      for (var i = 0; i < 20; i++) {
        final b = Board.shuffled(BoardSpec.tiers(GameMode.values[i % 4])[i % 8]);
        expect(b.lockedCount, 0);
        expect(b.joinCount, 0);
      }
    });

    test('par equals n minus cycles', () {
      final b = Board(g3, [1, 2, 0, 4, 3, 5, 6, 7, 8]);
      expect(b.par, 3);
      expect(b.swap(3, 4).par, 2);
    });

    test('star thresholds', () {
      expect(Board.starsFor(moves: 10, par: 10), 3);
      expect(Board.starsFor(moves: 16, par: 10), 3);
      expect(Board.starsFor(moves: 17, par: 10), 2);
      expect(Board.starsFor(moves: 24, par: 10), 2);
      expect(Board.starsFor(moves: 25, par: 10), 1);
    });

    test('grid codes round-trip', () {
      for (final t in GridSpec.tiers) {
        expect(GridSpec.fromCode(t.code), t);
        expect(GridSpec.fromCells(t.cells), t);
      }
    });

    test('board codes round-trip through path form for every mode', () {
      for (final mode in GameMode.values) {
        for (final t in BoardSpec.tiers(mode)) {
          final path = BoardCode.toPath(t.fullCode);
          expect(path.contains(':'), isFalse);
          expect(BoardSpec.fromCode(path), t);
          expect(BoardSpec.fromCode(t.fullCode), t);
        }
      }
      // Legacy grid-only codes mean cards.
      expect(BoardSpec.fromCode('4x4'), const GridSpec(4, 4, 'Relaxed'));
      expect(BoardSpec.fromCode('4x4').mode, GameMode.cards);
    });
  });

  group('Groups', () {
    test('correctly adjacent cards form a group anywhere on the board', () {
      // Cards 0 and 1 are picture-neighbours (left/right). Put them at slots 6,7.
      final b = Board(g3, [4, 5, 2, 3, 8, 7, 0, 1, 6]);
      expect(b.joined(6, 7), isTrue);
      expect(b.groupOf(6), [6, 7]);
      expect(b.groupOf(7), [6, 7]);
      // Cards 4 and 5 at slots 0,1 are neighbours in the picture (row 1), and
      // card 8 sits directly below card 5, so the three form one group.
      expect(b.groupOf(0), [0, 1, 4]);
      expect(b.floatingGroups, 2);
    });

    test('vertical neighbours join and reversed order does not', () {
      final b = Board(g3, [1, 2, 0, 4, 3, 5, 6, 7, 8]);
      expect(b.joined(0, 3), isTrue);
      final c = Board(g3, [4, 2, 0, 1, 3, 5, 6, 7, 8]);
      expect(c.joined(0, 3), isFalse);
    });

    test('a group moves as one and displaces cards into vacated cells', () {
      final b = Board(g3, [4, 5, 2, 3, 8, 7, 0, 1, 6]);
      final after = b.moveGroup(6, 0, -2)!;
      expect(after.slots[0], 0);
      expect(after.slots[1], 1);
      expect(after.slots[6], 4);
      expect(after.slots[7], 5);
      expect(after.isLocked(0), isTrue);
      expect(after.isLocked(1), isTrue);
    });

    test('a group can shift onto cells it already occupies', () {
      final b = Board(g3, [1, 2, 0, 3, 4, 5, 6, 7, 8]);
      expect(b.groupOf(0), [0, 1]);
      final after = b.moveTo(0, 1)!;
      expect(after.slots.sublist(0, 3), [0, 1, 2]);
    });

    test('moves out of bounds or onto locked cards are rejected', () {
      final b = Board(g3, [0, 1, 5, 3, 4, 2, 6, 7, 8]);
      expect(b.moveGroup(0, 1, 0), isNull, reason: 'locked group cannot move');
      expect(b.moveGroup(2, 1, 0), isNull, reason: 'out of bounds');
      expect(b.moveTo(2, 0), isNull, reason: 'onto a locked card');
      final ok = b.moveTo(2, 5)!;
      expect(ok.isSolved, isTrue);
    });

    test('moveTo with a single card equals a swap', () {
      final b = Board.shuffled(const GridSpec(4, 5, 'Medium'), seed: 7);
      final a = b.moveTo(3, 11)!;
      if (b.groupOf(3).length == 1 && b.groupOf(11).length == 1) {
        expect(a.slots, b.swap(3, 11).slots);
      }
    });

    test('sending every misplaced card home solves within par for every mode', () {
      for (final mode in GameMode.values) {
        for (final t in {
          for (final a in [9 / 16, 3 / 4, 1.0]) ...[BoardSpec.tiers(mode, a)[0], BoardSpec.tiers(mode, a)[1], BoardSpec.tiers(mode, a)[5]],
        }) {
          for (var seed = 0; seed < 8; seed++) {
            var b = Board.shuffled(t, seed: seed);
            final par = b.par;
            var moves = 0;
            while (!b.isSolved) {
              final slot = List.generate(b.cells, (i) => i).firstWhere((i) => !b.isLocked(i));
              final next = b.moveTo(slot, b.homeOf(slot));
              expect(next, isNotNull, reason: '${mode.code} ${t.code} seed $seed: cannot send $slot home');
              b = next!;
              moves++;
              expect(moves, lessThanOrEqualTo(t.cells * 2), reason: 'runaway');
            }
            expect(moves, lessThanOrEqualTo(par), reason: '${mode.code} ${t.code} seed $seed');
          }
        }
      }
    });
  });

  group('Tilings', () {
    test('neighbour counts: squares 4, triangles 3, hexagons 6 in the interior', () {
      final sq = Tiling.of(GameMode.squares, 5, 6);
      expect(sq.neighbours(5 * 2 + 2).length, 4);
      final tri = Tiling.of(GameMode.triangles, 8, 6);
      expect(tri.neighbours(8 * 2 + 3).length, 3);
      expect(tri.neighbours(8 * 2 + 4).length, 3);
      final hex = Tiling.of(GameMode.hexagons, 5, 6);
      expect(hex.neighbours(5 * 2 + 2).length, 6);
      expect(hex.neighbours(5 * 3 + 2).length, 6);
      // Corners have fewer.
      expect(hex.neighbours(0).length, lessThan(6));
      expect(tri.neighbours(0).length, lessThan(3));
    });

    test('triangles keep orientation and shape on shuffle and moves', () {
      final spec = BoardSpec.tiers(GameMode.triangles)[3];
      final tiling = spec.tiling as TriangleTiling;
      for (var seed = 0; seed < 20; seed++) {
        final b = Board.shuffled(spec, seed: seed);
        for (var s = 0; s < b.cells; s++) {
          expect(tiling.isUp(s), tiling.isUp(b.slots[s]), reason: 'seed $seed slot $s');
          expect(tiling.classOf(s), tiling.classOf(b.slots[s]), reason: 'seed $seed slot $s');
        }
        // Slot 0 is the top-left half: it cannot move onto a whole
        // triangle; two rows down is the next half of its shape.
        expect(b.moveGroup(0, 1, 0), isNull);
        final shifted = b.moveGroup(0, 0, 2) ?? b.moveGroup(0, 0, 4);
        if (shifted != null) {
          for (var s = 0; s < shifted.cells; s++) {
            expect(tiling.classOf(s), tiling.classOf(shifted.slots[s]));
          }
        }
      }
    });

    test('group moves keep every displaced card in a slot of its own shape', () {
      for (final mode in [GameMode.triangles, GameMode.hexagons]) {
        for (final spec in BoardSpec.tiers(mode, 0.75)) {
          final t = spec.tiling;
          for (var seed = 0; seed < 5; seed++) {
            var b = Board.shuffled(spec, seed: seed);
            final rng = math.Random(seed);
            for (var step = 0; step < 60; step++) {
              final from = rng.nextInt(b.cells), to = rng.nextInt(b.cells);
              final next = b.moveTo(from, to);
              if (next == null) continue;
              b = next;
              for (var s = 0; s < b.cells; s++) {
                expect(t.classOf(b.slots[s]), t.classOf(s), reason: '${spec.fullCode} seed $seed step $step slot $s');
              }
            }
          }
        }
      }
    });

    test('hexagon neighbours are symmetric and directions are consistent', () {
      final hex = Tiling.of(GameMode.hexagons, 5, 7);
      for (var s = 0; s < hex.cells; s++) {
        for (final n in hex.neighbours(s)) {
          expect(hex.neighbours(n).contains(s), isTrue, reason: '$s <-> $n');
          final d = hex.direction(s, n)!;
          // A move by that step lands there only between pieces of one shape.
          expect(hex.apply(s, d.$1, d.$2), hex.classOf(s) == hex.classOf(n) ? n : isNull);
          final back = hex.direction(n, s)!;
          expect((back.$1, back.$2), (-d.$1, -d.$2));
        }
      }
    });

    test('every tier of every mode fits a phone board area with sane cells', () {
      // Portrait phone play area (iPhone 15 Pro minus HUD and boosters) and
      // a spread of picture shapes, including the 900×21 handscroll that
      // collapsed the hexagons 3x4 board into a strip.
      const area = Size(369, 450);
      const pictures = [900 / 21, 3 / 4, 1.0, 16 / 9, 9 / 16, 2 / 3];
      for (final mode in GameMode.values) {
        for (final t in BoardSpec.tiers(mode)) {
          for (final aspect in pictures) {
            final why = '${mode.code} ${t.code} picture $aspect';
            final size = t.tiling.fit(area, aspect);
            expect(size.width, lessThanOrEqualTo(area.width + 0.01), reason: why);
            expect(size.height, lessThanOrEqualTo(area.height + 0.01), reason: why);
            expect(math.max(size.width, size.height), greaterThanOrEqualTo(math.min(area.width, area.height) - 0.01), reason: '$why fills the area');
            expect(size.width, greaterThan(200), reason: '$why is not a strip');
            expect(size.height, greaterThan(200), reason: '$why is not a strip');
            final cell = t.tiling.cellSize(size);
            expect(cell, greaterThan(22), reason: '$why cells are tappable');
          }
        }
      }
    });

    test('whole hexagons are regular and whole triangles equilateral on a board of their natural aspect', () {
      for (final t in BoardSpec.tiers(GameMode.hexagons)) {
        final hex = t.tiling;
        final size = hex.fit(const Size(369, 450), hex.naturalAspect);
        var whole = 0;
        for (var s = 0; s < hex.cells; s++) {
          final poly = hex.polygon(s, size);
          if (poly.length != 6) continue;
          whole++;
          final c = hex.cellCenter(s, size);
          final radii = [for (final v in poly) (v - c).distance];
          for (final r in radii) {
            expect(r, closeTo(radii.first, 1e-6), reason: '${t.code} slot $s');
          }
          final b = hex.cellBounds(s, size);
          expect(b.width / b.height, closeTo(math.sqrt(3) / 2, 1e-6), reason: '${t.code} slot $s width:height');
        }
        expect(whole, greaterThan(0), reason: t.code);
      }
      for (final t in BoardSpec.tiers(GameMode.triangles)) {
        final tri = t.tiling;
        final size = tri.fit(const Size(369, 450), tri.naturalAspect);
        for (var s = 0; s < tri.cells; s++) {
          final p = tri.polygon(s, size);
          final b = tri.cellBounds(s, size);
          // Whole triangles only (halves and fused edge pieces are narrower).
          if (b.width < size.width / ((tri as TriangleTiling).steps) * 1.9) continue;
          final sides = [for (var i = 0; i < 3; i++) (p[(i + 1) % 3] - p[i]).distance];
          for (final side in sides) {
            expect(side, closeTo(sides.first, 1e-6), reason: '${t.code} slot $s');
          }
        }
      }
    });

    test('rectangular grids keep their cell shape and crop the picture instead', () {
      for (final mode in [GameMode.cards, GameMode.squares]) {
        for (final spec in BoardSpec.tiers(mode)) {
          final t = spec.tiling as GridTiling;
          final (lo, hi) = t.aspectRange;
          for (final a in [900 / 21, 3 / 4, 1.0, 21 / 900, double.nan]) {
            final b = t.boardAspect(a);
            expect(b, inInclusiveRange(lo - 1e-9, hi + 1e-9), reason: '${spec.code} on $a');
          }
          final strip = t.fit(const Size(369, 450), 900 / 21);
          expect(strip.height, greaterThan(150), reason: '${spec.code}: a handscroll does not collapse the board');
        }
      }
    });

    test('picture crop has the board aspect, sits inside the picture and holds every cell', () {
      const image = Size(1400, 33); // the handscroll after decoding at 1400 px wide
      const portrait = Size(900, 1200);
      for (final mode in GameMode.values) {
        for (final t in BoardSpec.tiers(mode)) {
          for (final img in [image, portrait]) {
            final tiling = t.tiling;
            final board = tiling.fit(const Size(369, 450), img.width / img.height);
            final crop = tiling.crop(img, board);
            final why = '${mode.code} ${t.code} on $img';
            expect(crop.width / crop.height, closeTo(board.width / board.height, 1e-6), reason: why);
            expect(crop.left, greaterThanOrEqualTo(-0.01), reason: why);
            expect(crop.top, greaterThanOrEqualTo(-0.01), reason: why);
            expect(crop.right, lessThanOrEqualTo(img.width + 0.01), reason: why);
            expect(crop.bottom, lessThanOrEqualTo(img.height + 0.01), reason: why);
            // Centred: equal margins on the cropped axis.
            expect(crop.left, closeTo(img.width - crop.right, 1e-6), reason: why);
            expect(crop.top, closeTo(img.height - crop.bottom, 1e-6), reason: why);
            for (var s = 0; s < tiling.cells; s++) {
              final src = tiling.sourceRect(s, crop);
              expect(src.left, greaterThanOrEqualTo(crop.left - 0.01), reason: '$why slot $s');
              expect(src.top, greaterThanOrEqualTo(crop.top - 0.01), reason: '$why slot $s');
              expect(src.right, lessThanOrEqualTo(crop.right + 0.01), reason: '$why slot $s');
              expect(src.bottom, lessThanOrEqualTo(crop.bottom + 0.01), reason: '$why slot $s');
            }
          }
        }
      }
      // A 3:4 picture on a 3x3 cards board (cards a touch narrower than 5:7)
      // is used whole.
      final cards = const GridSpec(3, 3, 'Cozy').tiling;
      expect(cards.crop(portrait, cards.fit(const Size(300, 400), 3 / 4)), Offset.zero & portrait);
    });

    test('corner neighbours: every cell around an interior vertex, fewer on the board edge', () {
      const size = Size(300, 400);
      for (final mode in GameMode.values) {
        final t = BoardSpec.tiers(mode)[3].tiling;
        var interior = 0;
        for (var s = 0; s < t.cells; s++) {
          final poly = t.polygon(s, size);
          for (var k = 0; k < poly.length; k++) {
            final around = t.cornerNeighbours(s, k);
            expect(around.contains(s), isFalse);
            expect(around.length + 1, lessThanOrEqualTo(t.vertexValence), reason: '${mode.code} slot $s vertex $k');
            if (around.length + 1 == t.vertexValence) interior++;
            for (final n in around) {
              expect(t.polygon(n, size).any((p) => (p - poly[k]).distance < 1e-6), isTrue, reason: '${mode.code} $n shares vertex $k of $s');
            }
            // Edge neighbours adjoining the vertex always share it.
            final e = t.edgeNeighbours(s);
            for (final n in [e[(k - 1 + poly.length) % poly.length], e[k]]) {
              if (n != null) expect(around, contains(n));
            }
          }
        }
        expect(interior, greaterThan(0), reason: '${mode.code} has interior vertices');
      }
    });

    test('geometry: cells cover the board and hit-testing finds centres', () {
      const size = Size(300, 400);
      for (final mode in GameMode.values) {
        final t = BoardSpec.tiers(mode)[2].tiling;
        for (var s = 0; s < t.cells; s++) {
          final c = t.cellCenter(s, size);
          expect(t.slotAt(c, size), s, reason: '${mode.code} slot $s');
          final b = t.cellBounds(s, size);
          expect(b.left, greaterThanOrEqualTo(-0.01));
          expect(b.top, greaterThanOrEqualTo(-0.01));
          expect(b.right, lessThanOrEqualTo(size.width + 0.01));
          expect(b.bottom, lessThanOrEqualTo(size.height + 0.01));
          expect(t.edgeNeighbours(s).length, t.polygon(s, size).length);
        }
      }
    });
  });
}
