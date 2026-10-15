import 'dart:ui';

import 'package:carden/game/board.dart';
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

  group('triangles 5x4 (four rows, even steps: halves on both edges)', () {
    // Row r, piece k; (k + r) odd points up. Slot = r * 5 + k.
    //   r0:  0TL  1u  2d  3u  4TR      TL/TR/BL/BR: halves with the right
    //   r1:  5BL  6d  7u  8d  9BR      angle top-left, top-right, ...
    //   r2: 10TL 11u 12d 13u 14TR
    //   r3: 15BL 16d 17u 18d 19BR
    const spec = BoardSpec(GameMode.triangles, 5, 4, 'Easy');
    final tri = spec.tiling as TriangleTiling;

    /// A layout with no card in place (each shape class cycled by one),
    /// then the given cards swapped into the given slots.
    List<int> layout(Map<int, int> cardAtSlot) {
      final classes = <int, List<int>>{};
      for (var s = 0; s < tri.cells; s++) {
        classes.putIfAbsent(tri.classOf(s), () => []).add(s);
      }
      final slots = List<int>.filled(tri.cells, 0);
      for (final cls in classes.values) {
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

    test('pieces, orientation and shape classes', () {
      expect(tri.cells, 20);
      expect(tri.isUp(1), isTrue);
      expect(tri.isUp(2), isFalse);
      expect(tri.isUp(0), isFalse, reason: 'the top-left piece is half of a down triangle');
      // Six shapes: up, down and four kinds of half, two of each half.
      expect(tri.classCount, 6);
      expect(tri.classOf(0), tri.classOf(10));
      expect(tri.classOf(5), tri.classOf(15));
      expect(tri.classOf(4), tri.classOf(14));
      expect(tri.classOf(9), tri.classOf(19));
      expect({tri.classOf(0), tri.classOf(5), tri.classOf(4), tri.classOf(9), tri.classOf(1), tri.classOf(2)}.length, 6);
    });

    test('neighbours: slants left and right, the base below (up) or above (down), halves along the edge', () {
      expect(tri.neighbours(0).toSet(), {1}, reason: 'top-left half: only its slant');
      expect(tri.neighbours(1).toSet(), {6, 2, 0}, reason: 'up triangle: base touches the row below');
      expect(tri.neighbours(2).toSet(), {3, 1}, reason: 'top-row down triangle has nothing above');
      expect(tri.neighbours(5).toSet(), {10, 6}, reason: 'a half shares its base with the half below');
      expect(tri.neighbours(7).toSet(), {12, 8, 6}, reason: 'interior up triangle');
      expect(tri.neighbours(6).toSet(), {1, 7, 5}, reason: 'interior down triangle');
      expect(tri.neighbours(4).toSet(), {3}, reason: 'top-right half');
      expect(tri.neighbours(9).toSet(), {14, 8});
      expect(tri.neighbours(19).toSet(), {18}, reason: 'bottom-right half');
    });

    test('neighbours never share a shape, so no card moves onto a neighbour slot', () {
      for (var s = 0; s < tri.cells; s++) {
        for (final n in tri.neighbours(s)) {
          expect(tri.classOf(n), isNot(tri.classOf(s)));
          expect(tri.delta(s, n), isNull);
          expect(tri.direction(s, n), isNotNull, reason: 'but the shared edge is still a direction');
        }
      }
    });

    test('cards next to each other in the picture join side by side', () {
      // Cards 1 (up) and 2 (down) sit at slots 11 (up) and 12 (down).
      final b = Board(spec, layout({11: 1, 12: 2}));
      expect(b.joined(11, 12), isTrue);
      // (The cycled halves put card 0 at slot 10, so it joins in as well.)
      expect(b.groupOf(11), containsAll([11, 12]));
      expect(b.joinCount, greaterThanOrEqualTo(1));
    });

    test('cards sharing a horizontal base join vertically', () {
      // Card 1 (up, r0) sits on card 6 (down, r1). Place them at 11 and 16.
      final b = Board(spec, layout({11: 1, 16: 6}));
      expect(b.joined(11, 16), isTrue);
      expect(b.groupOf(11), containsAll([11, 16]));
    });

    test('half pieces join their neighbours like any card', () {
      // Card 0 (top-left half) left of card 1, placed two rows down.
      final b = Board(spec, layout({10: 0, 11: 1}));
      expect(b.joined(10, 11), isTrue);
      expect(b.groupOf(10), [10, 11]);
    });

    test('mirrored order does not join', () {
      // Card 2 (down) left of card 1 (up) is not how the picture goes.
      final b = Board(spec, layout({6: 2, 7: 1}));
      expect(b.joined(6, 7), isFalse);
      expect(b.groupOf(6), [6]);
    });

    test('a triangle group moves as one and keeps its shapes', () {
      final b = Board(spec, layout({11: 1, 12: 2}));
      expect(b.lockedCount, 0);
      final home = b.moveGroup(11, 0, -2)!;
      expect(home.isLocked(1), isTrue);
      expect(home.isLocked(2), isTrue);
      expect(b.moveGroup(11, 1, 0), isNull, reason: 'a step that changes orientation is refused');
    });

    test('dropping a card beside its picture neighbour snaps them together', () {
      var checked = 0;
      for (var seed = 0; seed < 30; seed++) {
        final b = Board.shuffled(spec, seed: seed);
        expect(b.joinCount, 0);
        final s1 = b.slotOfCard(1);
        final right = tri.edgeNeighbours(s1)[1];
        if (right == null || b.isLocked(right) || b.groupOf(b.slotOfCard(2)).length > 1) continue;
        final after = b.moveTo(b.slotOfCard(2), right);
        if (after == null) continue;
        expect(after.joined(after.slotOfCard(1), after.slotOfCard(2)), isTrue, reason: 'seed $seed');
        expect(after.joinCount, greaterThan(b.joinCount), reason: 'seed $seed: the controller reports a snap when joins increase');
        checked++;
      }
      expect(checked, greaterThan(5));
    });

    test('shuffled boards really start without a joined pair or a piece in place', () {
      for (final t in [spec, ...BoardSpec.tiers(GameMode.triangles)]) {
        for (var seed = 0; seed < 20; seed++) {
          final b = Board.shuffled(t, seed: seed);
          expect(b.joinCount, 0, reason: '${t.code} seed $seed');
          expect(b.lockedCount, 0, reason: '${t.code} seed $seed');
          expect(b.floatingGroups, 0, reason: '${t.code} seed $seed');
        }
      }
    });
  });

  group('triangles 6x4 (four rows, odd steps: right-edge halves fused)', () {
    // Rows of six with a half at k = 0; at k = 5 the halves of rows 0-1 and
    // 2-3 are fused into left-pointing triangles. Slots: r0 0-5, r1 6-10,
    // r2 11-16, r3 17-21.
    const spec = BoardSpec(GameMode.triangles, 6, 4, 'Easy');
    final tri = spec.tiling as TriangleTiling;

    test('the fused pieces form one class and touch both rows', () {
      expect(tri.cells, 22);
      expect(spec.cells, 22);
      expect(tri.classOf(5), tri.classOf(16));
      expect(tri.neighbours(5).toSet(), {4, 10});
      expect(tri.neighbours(16).toSet(), {15, 21});
      expect(tri.direction(5, 10), (-1, 1));
      expect(tri.direction(10, 5), (1, -1));
      expect(tri.polygon(5, const Size(500, 400)).length, 3);
    });

    test('a fused piece joins its neighbours and moves by two rows', () {
      final slots = List<int>.generate(22, (i) => i);
      // Cards 4 and 5 at slots 15 and 16; cards 15 and 16 at home of 4 and 5.
      slots[15] = 4;
      slots[4] = 15;
      slots[16] = 5;
      slots[5] = 16;
      final b = Board(spec, slots);
      expect(b.joined(15, 16), isTrue);
      final home = b.moveTo(16, 5)!;
      expect(home.isLocked(4), isTrue);
      expect(home.isLocked(5), isTrue);
    });
  });

  group('hexagons 4x5', () {
    // Doubled coordinates (X, r): even rows hold X = 1, 3, 5, 7 (their outer
    // sides on the board's edges), odd rows X = 0..8 (halves at both ends).
    // Slots: r0 0-3 (top pieces), r1 4-8, r2 9-12, r3 13-17, r4 18-21.
    const spec = BoardSpec(GameMode.hexagons, 4, 5, 'Easy');
    final hex = spec.tiling;

    test('pieces and shape classes', () {
      expect(hex.cells, 22);
      expect(spec.cells, 22);
      // Whole, top, bottom, left half, right half.
      expect(hex.classCount, 5);
      expect(hex.classOf(4), hex.classOf(13), reason: 'left halves');
      expect(hex.classOf(8), hex.classOf(17), reason: 'right halves');
      expect(hex.classOf(0), hex.classOf(3), reason: 'top pieces');
      expect(hex.classOf(18), hex.classOf(21), reason: 'bottom pieces');
      expect(hex.classOf(6), hex.classOf(10), reason: 'whole hexagons');
    });

    test('interior cells have six neighbours', () {
      expect(hex.neighbours(6).toSet(), {7, 5, 2, 1, 11, 10});
      expect(hex.neighbours(10).toSet(), {11, 9, 6, 5, 15, 14});
    });

    test('edge pieces have fewer neighbours and no corner is cut twice', () {
      expect(hex.neighbours(0).toSet(), {1, 5, 4}, reason: 'top-left: a top piece flush with the left edge');
      expect(hex.neighbours(4).toSet(), {0, 5, 9}, reason: 'left half');
      expect(hex.neighbours(8).toSet(), {3, 7, 12}, reason: 'right half');
      expect(hex.neighbours(21).toSet(), {20, 16, 17}, reason: 'bottom-right');
      for (final corner in [0, 3, 18, 21]) {
        expect(hex.polygon(corner, const Size(400, 500)).length, 5, reason: 'corner $corner is a cut hexagon, not a quarter');
      }
    });

    test('the same edge has the same direction on even and odd rows', () {
      // 10 -> 6 (even row up-right) and 6 -> 2 (odd row up-right) are both NE.
      expect(hex.direction(10, 6), hex.direction(6, 2));
      expect(hex.direction(10, 5), hex.direction(6, 1), reason: 'NW');
      expect(hex.direction(10, 11), hex.direction(6, 7), reason: 'E');
      expect(hex.direction(10, 15), hex.direction(6, 11), reason: 'SE');
      expect(hex.direction(10, 6), isNot(hex.direction(10, 5)));
    });

    test('cards join along diagonal edges across rows of different parity', () {
      // Card 6 (X4 r1) is NE of card 10 (X3 r2). Put card 10 at slot 14
      // (X2 r3) and card 6 at slot 10 (X3 r2): 10 is NE of 14, so they join.
      final slots = List.generate(22, (i) => i);
      slots[14] = 10;
      slots[10] = 6;
      slots[6] = 14;
      final b = Board(spec, slots);
      expect(b.joined(14, 10), isTrue);
      expect(b.groupOf(14), [10, 14]);
      // Mirrored: card 6 SW of card 14 is wrong.
      final wrong = List.generate(22, (i) => i);
      wrong[14] = 6;
      wrong[6] = 14;
      expect(Board(spec, wrong).joined(14, 10), isFalse);
    });

    test('cards join side by side and the group moves as one', () {
      final slots = List.generate(22, (i) => i);
      slots[15] = 9;
      slots[9] = 15;
      slots[16] = 10;
      slots[10] = 16;
      final b = Board(spec, slots);
      expect(b.joined(15, 16), isTrue);
      expect(b.groupOf(15), [15, 16]);
      final moved = b.moveTo(15, 9)!;
      expect(moved.isLocked(9), isTrue);
      expect(moved.isLocked(10), isTrue);
    });

    test('shuffled boards start without a joined pair', () {
      for (final t in [spec, ...BoardSpec.tiers(GameMode.hexagons)]) {
        for (var seed = 0; seed < 20; seed++) {
          final b = Board.shuffled(t, seed: seed);
          expect(b.joinCount, 0, reason: '${t.code} seed $seed');
          expect(b.lockedCount, 0, reason: '${t.code} seed $seed');
        }
      }
    });
  });
}
