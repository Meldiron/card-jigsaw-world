import 'dart:ui';

import 'package:card_jigsaw_world/game/board.dart';
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

    test('every mode and tier starts with no pre-joined pair and at most one lucky card', () {
      for (final mode in GameMode.values) {
        for (final t in BoardSpec.tiers(mode)) {
          for (var seed = 0; seed < 12; seed++) {
            final b = Board.shuffled(t, seed: seed);
            expect(b.joinCount, 0, reason: '${mode.code} ${t.code} seed $seed');
            expect(b.lockedCount, lessThanOrEqualTo(t.cells >= 12 ? 0 : 1), reason: '${mode.code} ${t.code} seed $seed');
          }
        }
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
        for (final t in [BoardSpec.tiers(mode)[1], BoardSpec.tiers(mode)[5]]) {
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

    test('triangles keep orientation parity on shuffle and moves', () {
      final spec = BoardSpec.tiers(GameMode.triangles)[3];
      final tiling = spec.tiling as TriangleTiling;
      for (var seed = 0; seed < 20; seed++) {
        final b = Board.shuffled(spec, seed: seed);
        for (var s = 0; s < b.cells; s++) {
          expect(tiling.isUp(s), tiling.isUp(b.slots[s]), reason: 'seed $seed slot $s');
        }
        // Odd-parity deltas are rejected; even ones keep parity.
        expect(b.moveGroup(0, 1, 0), isNull);
        final shifted = b.moveGroup(0, 2, 0) ?? b.moveGroup(0, 1, 1);
        if (shifted != null) {
          for (var s = 0; s < shifted.cells; s++) {
            expect(tiling.isUp(s), tiling.isUp(shifted.slots[s]));
          }
        }
      }
    });

    test('hexagon neighbours are symmetric and directions are consistent', () {
      final hex = Tiling.of(GameMode.hexagons, 5, 6);
      for (var s = 0; s < hex.cells; s++) {
        for (final n in hex.neighbours(s)) {
          expect(hex.neighbours(n).contains(s), isTrue, reason: '$s <-> $n');
          final d = hex.direction(s, n)!;
          expect(hex.apply(s, d.$1, d.$2), n);
          final back = hex.direction(n, s)!;
          expect((back.$1, back.$2), (-d.$1, -d.$2));
        }
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
