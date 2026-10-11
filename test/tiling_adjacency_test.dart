import 'package:card_jigsaw_world/game/board.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which board positions count as neighbours in each tiling, and that groups
/// form between them exactly as they do for cards. Triangles once never
/// joined because the edge direction went through the move delta, which
/// rejects every step between opposite orientations.
void main() {
  group('every tiling', () {
    test('direction is defined and antisymmetric for every neighbour pair', () {
      for (final mode in GameMode.values) {
        for (final t in BoardSpec.tiers(mode)) {
          final tiling = t.tiling;
          for (var s = 0; s < tiling.cells; s++) {
            for (final n in tiling.neighbours(s)) {
              final why = '${mode.code} ${t.code} $s -> $n';
              expect(tiling.neighbours(n), contains(s), reason: why);
              final d = tiling.direction(s, n);
              expect(d, isNotNull, reason: why);
              final back = tiling.direction(n, s);
              expect(back, (-d!.$1, -d.$2), reason: why);
              // Different neighbours of one cell lie in different directions.
              for (final m in tiling.neighbours(s)) {
                if (m != n) expect(tiling.direction(s, m), isNot(d), reason: '$why vs $m');
              }
            }
            expect(tiling.direction(s, s), isNull);
          }
        }
      }
    });

    test('joined is symmetric and the solved board joins every edge', () {
      for (final mode in GameMode.values) {
        final t = BoardSpec.tiers(mode)[2];
        final solved = Board(t, List.generate(t.cells, (i) => i));
        var edges = 0;
        for (var s = 0; s < t.cells; s++) {
          for (final n in solved.neighbours(s)) {
            expect(solved.joined(s, n), isTrue, reason: '${mode.code} $s-$n');
            expect(solved.joined(n, s), isTrue, reason: '${mode.code} $n-$s');
            if (n > s) edges++;
          }
        }
        expect(solved.joinCount, edges, reason: mode.code);
        expect(solved.groupOf(0).length, t.cells, reason: mode.code);
      }
    });
  });

  group('triangles 4x4', () {
    // Row r, column c; (c + r) even points up. Slot = r * 4 + c.
    //   r0:  0u  1d  2u  3d
    //   r1:  4d  5u  6d  7u
    //   r2:  8u  9d 10u 11d
    //   r3: 12d 13u 14d 15u
    const spec = BoardSpec(GameMode.triangles, 4, 4, 'Easy');
    final tri = spec.tiling as TriangleTiling;

    /// A layout with no card in place (each orientation class cycled by one),
    /// then the given cards swapped into the given slots.
    List<int> layout(Map<int, int> cardAtSlot) {
      final classes = [<int>[], <int>[]];
      for (var s = 0; s < 16; s++) {
        classes[tri.classOf(s)].add(s);
      }
      final slots = List<int>.filled(16, 0);
      for (final cls in classes) {
        for (var i = 0; i < cls.length; i++) {
          slots[cls[i]] = cls[(i + 1) % cls.length];
        }
      }
      cardAtSlot.forEach((slot, card) {
        final from = slots.indexOf(card);
        slots[from] = slots[slot];
        slots[slot] = card;
      });
      return slots;
    }

    test('neighbours: left, right, and below (up) or above (down)', () {
      expect(tri.isUp(0), isTrue);
      expect(tri.isUp(1), isFalse);
      expect(tri.neighbours(0).toSet(), {4, 1}, reason: 'top-left up triangle: base touches the row below');
      expect(tri.neighbours(1).toSet(), {0, 2}, reason: 'top-row down triangle has nothing above');
      expect(tri.neighbours(5).toSet(), {9, 6, 4}, reason: 'interior up triangle');
      expect(tri.neighbours(6).toSet(), {2, 7, 5}, reason: 'interior down triangle');
      expect(tri.neighbours(12).toSet(), {8, 13}, reason: 'bottom-left down triangle');
      expect(tri.neighbours(15).toSet(), {14}, reason: 'bottom-right up triangle has nothing below or right');
    });

    test('neighbours have the opposite orientation and no legal move delta', () {
      for (var s = 0; s < tri.cells; s++) {
        for (final n in tri.neighbours(s)) {
          expect(tri.isUp(n), isNot(tri.isUp(s)));
          expect(tri.delta(s, n), isNull, reason: 'a card never moves onto a neighbour slot');
          expect(tri.direction(s, n), isNotNull, reason: 'but the shared edge is still a direction');
        }
      }
    });

    test('cards next to each other in the picture join side by side', () {
      // Cards 0 (up) and 1 (down) sit at slots 8 (up) and 9 (down).
      final b = Board(spec, layout({8: 0, 9: 1}));
      expect(b.joined(8, 9), isTrue);
      expect(b.joined(9, 8), isTrue);
      expect(b.groupOf(8), [8, 9]);
      expect(b.groupOf(9), [8, 9]);
      expect(b.joinCount, greaterThanOrEqualTo(1));
    });

    test('cards sharing a horizontal base join vertically', () {
      // Card 0 (up, r0 c0) sits on card 4 (down, r1 c0). Place them at slots 2 and 6.
      final b = Board(spec, layout({2: 0, 6: 4}));
      expect(b.joined(2, 6), isTrue);
      expect(b.groupOf(2), [2, 6]);
    });

    test('mirrored order does not join', () {
      // Card 1 (down) left of card 0 (up): slots 9 and 10.
      final b = Board(spec, layout({9: 1, 10: 0}));
      expect(b.joined(9, 10), isFalse);
      expect(b.groupOf(9), [9]);
    });

    test('a triangle group moves as one and keeps orientation', () {
      final b = Board(spec, layout({8: 0, 9: 1}));
      expect(b.lockedCount, 0);
      final moved = b.moveGroup(8, 2, 0)!;
      expect(moved.slots[10], 0);
      expect(moved.slots[11], 1);
      expect(moved.groupOf(10), [10, 11]);
      final home = moved.moveGroup(10, -2, -2)!;
      expect(home.isLocked(0), isTrue);
      expect(home.isLocked(1), isTrue);
    });

    test('dropping a card beside its picture neighbour snaps them together', () {
      // From a shuffled board (no joins), move card 1 to the slot right of card 0.
      var checked = 0;
      for (var seed = 0; seed < 20; seed++) {
        final b = Board.shuffled(spec, seed: seed);
        expect(b.joinCount, 0);
        final s0 = b.slotOfCard(0);
        if (s0 % 4 == 3) continue;
        final after = b.moveTo(b.slotOfCard(1), s0 + 1);
        expect(after, isNotNull, reason: 'seed $seed');
        expect(after!.joined(s0, s0 + 1), isTrue, reason: 'seed $seed');
        expect(after.groupOf(s0), [s0, s0 + 1], reason: 'seed $seed');
        expect(after.joinCount, greaterThan(b.joinCount), reason: 'seed $seed: the controller reports a snap when joins increase');
        checked++;
      }
      expect(checked, greaterThan(5));
    });

    test('shuffled boards really start without a joined pair', () {
      for (final t in BoardSpec.tiers(GameMode.triangles)) {
        for (var seed = 0; seed < 20; seed++) {
          final b = Board.shuffled(t, seed: seed);
          expect(b.joinCount, 0, reason: '${t.code} seed $seed');
          expect(b.floatingGroups, 0, reason: '${t.code} seed $seed');
        }
      }
    });
  });

  group('hexagons 4x5', () {
    // Odd-r offset: odd rows shift right by half a cell. Slot = r * 4 + c.
    const spec = BoardSpec(GameMode.hexagons, 4, 5, 'Easy');
    final hex = spec.tiling;

    test('neighbours of an odd-row cell touch the columns to its right above and below', () {
      expect(hex.neighbours(5).toSet(), {4, 6, 1, 2, 9, 10});
    });

    test('neighbours of an even-row cell touch the columns to its left above and below', () {
      expect(hex.neighbours(9).toSet(), {8, 10, 4, 5, 12, 13});
    });

    test('edges and corners have fewer neighbours', () {
      expect(hex.neighbours(0).toSet(), {1, 4});
      expect(hex.neighbours(3).toSet(), {2, 6, 7});
      expect(hex.neighbours(16).toSet(), {17, 12}, reason: 'even row: nothing up-left of column 0');
      expect(hex.neighbours(7).toSet(), {6, 3, 11}, reason: 'odd row, right edge: the up-right and down-right cells are out');
      expect(hex.neighbours(19).toSet(), {18, 14, 15}, reason: 'even row, bottom-right: up-left and up');
    });

    test('the same edge has the same direction on even and odd rows', () {
      // 9 -> 5 (even row up-right) and 5 -> 2 (odd row up-right) are both NE.
      expect(hex.direction(9, 5), hex.direction(5, 2));
      expect(hex.direction(9, 4), hex.direction(5, 1), reason: 'NW');
      expect(hex.direction(9, 10), hex.direction(5, 6), reason: 'E');
      expect(hex.direction(9, 13), hex.direction(5, 10), reason: 'SE');
      expect(hex.direction(9, 5), isNot(hex.direction(9, 4)));
    });

    test('cards join along diagonal edges across rows of different parity', () {
      // Card 1 (r0 c1) is NE of card 4 (r1 c0). Put card 4 at slot 9 (r2 c1)
      // and card 1 at slot 5 (r1 c1): 5 is NE of 9, so they must join.
      final slots = List.generate(20, (i) => i);
      slots[9] = 4;
      slots[4] = 9;
      slots[5] = 1;
      slots[1] = 5;
      final b = Board(spec, slots);
      expect(b.joined(9, 5), isTrue);
      expect(b.groupOf(9), [5, 9]);
      // Mirrored: card 1 SW of card 4 is wrong.
      final wrong = List.generate(20, (i) => i);
      wrong[9] = 1;
      wrong[1] = 9;
      wrong[5] = 4;
      wrong[4] = 5;
      expect(Board(spec, wrong).joined(9, 5), isFalse);
    });

    test('cards join side by side and the group moves as one', () {
      final slots = List.generate(20, (i) => i);
      slots[13] = 0;
      slots[0] = 13;
      slots[14] = 1;
      slots[1] = 14;
      final b = Board(spec, slots);
      expect(b.joined(13, 14), isTrue);
      expect(b.groupOf(13), [13, 14]);
      final moved = b.moveTo(13, 0)!;
      expect(moved.isLocked(0), isTrue);
      expect(moved.isLocked(1), isTrue);
    });

    test('shuffled boards start without a joined pair', () {
      for (final t in BoardSpec.tiers(GameMode.hexagons)) {
        for (var seed = 0; seed < 20; seed++) {
          expect(Board.shuffled(t, seed: seed).joinCount, 0, reason: '${t.code} seed $seed');
        }
      }
    });
  });
}
