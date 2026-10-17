import 'dart:math';

import 'package:carden/game/board.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pushed groups stay whole (owner, 2026-10-17): a group a move lands on shifts by one lattice step
/// instead of breaking apart, when there is room for it (`Board.moveGroup`).
void main() {
  const g3 = GridSpec(3, 3, 'Cozy');
  const g4 = GridSpec(4, 4, 'Relaxed');

  group('pushed groups', () {
    test('two groups of the same shape trade places', () {
      // Cards 0,1 at 10,11 and cards 12,13 at 8,9: both pairs on row 2.
      final b = _board(g4, {10: 0, 11: 1, 8: 12, 9: 13});
      expect(b.groupOf(10), [10, 11]);
      expect(b.groupOf(8), [8, 9]);
      final after = b.moveGroup(10, -2, 0)!;
      expect(after.slots.sublist(8, 12), [0, 1, 12, 13]);
      for (var s = 0; s < 16; s++) {
        if (s < 8 || s > 11) expect(after.slots[s], b.slots[s], reason: 'slot $s is not part of the move');
      }
    });

    test('a single card pushes a pair: the pair shifts whole, the card beyond it takes the vacated cell', () {
      // (Cards are narrower than tall, so a step across is the shortest.)
      // Card 15 at 4 moves right onto the pair 9,10 (slots 5,6); card 0 sits at 7, beyond the pair.
      final b = _board(g4, {4: 15, 5: 9, 6: 10, 7: 0});
      expect(b.groupOf(5), [5, 6]);
      final after = b.moveGroup(4, 1, 0)!;
      expect(after.slots.sublist(4, 8), [0, 15, 9, 10]);
      expect(after.groupOf(6), [6, 7]);
      expect(Board.isValidLayout(g4, after.slots), isTrue);
      expect(after.slots.sublist(8), b.slots.sublist(8));
    });

    test('a group with no room breaks as before', () {
      // The 2x2 of cards 0,1,3,4 at 1,2,4,5; the bottom row is locked, so it cannot move whole.
      final b = Board(g3, const [5, 0, 1, 2, 3, 4, 6, 7, 8]);
      expect(b.groupOf(1), [1, 2, 4, 5]);
      final after = b.moveGroup(0, 1, 0)!;
      expect(after.slots, const [0, 5, 1, 2, 3, 4, 6, 7, 8]);
    });

    test('a move that lands on no other group is unchanged: a plain swap', () {
      final b = _board(g4, {5: 9, 6: 10});
      final after = b.moveTo(0, 3)!;
      expect(after.slots, b.swap(0, 3).slots);
    });

    test('of two equal places, the pushed group goes against the move', () {
      // Squares (a step across is as long as a step down). Card 15 at 8 moves up onto the pair
      // 9,10 at 4,5. Down a row (8,9) and right a cell (5,6) each cover one loose card; the pair
      // goes down, where the card came from.
      const squares = BoardSpec(GameMode.squares, 4, 4, 'Relaxed');
      final b = _board(squares, {0: 0, 1: 1, 4: 9, 5: 10, 8: 15});
      final after = b.moveGroup(8, 0, -1)!;
      expect(after.slots.sublist(0, 2), [0, 1], reason: 'locked cards never move');
      expect(after.slots[4], 15);
      expect(after.slots.sublist(8, 10), [9, 10]);
      expect(after.slots[5], b.slots[9], reason: 'the card the pair covered takes the cell it left');
      expect(b.moveGroup(4, 0, -1), isNull, reason: 'a move onto locked cards is still refused');
    });

    test('every mode: a pushed pair keeps every shape and stays whole when it has room', () {
      for (final mode in GameMode.values) {
        final spec = BoardSpec.tiers(mode)[5];
        final tiling = spec.tiling;
        final whole = tiling.classOf(spec.cells ~/ 2);
        var kept = 0, keptAtEdge = 0;
        // A pair of picture neighbours moved together off home by a step that keeps every shape
        // (half triangles and hexagon edge pieces included), then a loose card moved onto it.
        for (var a = 0; a < spec.cells; a++) {
          for (final c in tiling.neighbours(a)) {
            final step = [(0, 2), (0, -2), (2, 0), (-2, 0), (0, 4), (4, 0)].where((s) => tiling.apply(a, s.$1, s.$2) != null && tiling.apply(c, s.$1, s.$2) != null).firstOrNull;
            if (step == null) continue;
            final pa = tiling.apply(a, step.$1, step.$2)!, pc = tiling.apply(c, step.$1, step.$2)!;
            final b = _tryBoard(spec, {pa: a, pc: c});
            if (b == null) continue;
            expect(b.groupOf(pa), unorderedEquals([pa, pc]), reason: '$mode: the pair is joined');
            for (var x = 0; x < spec.cells; x++) {
              if (x == pa || x == pc || tiling.classOf(x) != tiling.classOf(pc)) continue;
              final after = b.moveTo(x, pc);
              if (after == null) continue;
              final d = tiling.delta(x, pc)!;
              _check(b, x, d.$1, d.$2, after, '$mode pair $a,$c at $pa,$pc pushed by $x');
              for (var s = 0; s < spec.cells; s++) {
                expect(tiling.classOf(after.slots[s]), tiling.classOf(s), reason: '$mode: slot $s keeps its shape');
              }
              if (_stepOf(b, after, b.groupOf(pa)) != null) {
                kept++;
                if (tiling.classOf(a) != whole || tiling.classOf(c) != whole) keptAtEdge++;
              }
              break;
            }
          }
        }
        expect(kept, greaterThan(10), reason: '$mode: pushed pairs stay whole');
        if (mode == GameMode.triangles || mode == GameMode.hexagons) expect(keptAtEdge, greaterThan(0), reason: '$mode: with an edge piece too');
      }
    });
  });

  group('fuzz', () {
    test('thousands of random moves on random boards keep every rule', () {
      final rng = Random(2026);
      var moves = 0, pushes = 0;
      for (final mode in GameMode.values) {
        for (final tier in [0, 3, 5, 7]) {
          final spec = BoardSpec.tiers(mode, [9 / 16, 3 / 4, 1.0][rng.nextInt(3)])[tier];
          for (var round = 0; round < 6; round++) {
            var b = Board.shuffled(spec, seed: rng.nextInt(1 << 20));
            for (var step = 0; step < 60 && !b.isSolved; step++) {
              final move = _randomMove(b, rng);
              if (move == null) continue;
              final after = b.moveGroup(move.$1, move.$2, move.$3);
              if (after == null) continue;
              pushes += _check(b, move.$1, move.$2, move.$3, after, '${mode.code} ${spec.code} move ${moves + 1}');
              b = after;
              moves++;
            }
          }
        }
      }
      expect(moves, greaterThan(2000));
      expect(pushes, greaterThan(200), reason: 'the fuzz pushes groups often enough to mean something');
    });

    test('giant boards too', () {
      final rng = Random(17);
      var moves = 0, pushes = 0;
      for (final mode in GameMode.values) {
        final spec = BoardSpec.giantTiers(mode).last;
        var b = Board.shuffled(spec, seed: 3);
        for (var step = 0; step < 400; step++) {
          final move = _randomMove(b, rng);
          if (move == null) continue;
          final after = b.moveGroup(move.$1, move.$2, move.$3);
          if (after == null) continue;
          pushes += _check(b, move.$1, move.$2, move.$3, after, '${mode.code} giant move ${moves + 1}');
          b = after;
          moves++;
        }
      }
      expect(pushes, greaterThan(20));
    });
  });
}

/// A board with the cards of [at] (slot -> card) where given and every other card loose: not in
/// place and joined to nothing; null when no such board turns up.
Board? _tryBoard(BoardSpec spec, Map<int, int> at) {
  final rest = [for (var s = 0; s < spec.cells; s++) if (!at.containsKey(s)) s];
  for (var seed = 0; seed < 300; seed++) {
    var b = Board.shuffled(spec, seed: seed);
    at.forEach((s, c) => b = b.swap(s, b.slotOfCard(c)));
    if (!Board.isValidLayout(spec, b.slots)) return null;
    if (rest.every((s) => !b.isLocked(s) && b.groupOf(s).length == 1)) return b;
  }
  return null;
}

Board _board(BoardSpec spec, Map<int, int> at) => _tryBoard(spec, at) ?? (throw StateError('no clean board for $at'));

/// A move a player might make: mostly a card put beside one of its picture neighbours (so groups
/// form and get pushed), sometimes a card sent home or anywhere.
(int, int, int)? _randomMove(Board b, Random rng) {
  final tiling = b.tiling;
  final loose = [for (var s = 0; s < b.cells; s++) if (!b.isLocked(s)) s];
  if (loose.isEmpty) return null;
  final from = loose[rng.nextInt(loose.length)];
  int? target;
  final roll = rng.nextInt(10);
  if (roll < 6) {
    final card = b.slots[from];
    final nbs = tiling.neighbours(card).toList();
    final partner = nbs[rng.nextInt(nbs.length)];
    final dir = tiling.direction(partner, card);
    final at = b.slotOfCard(partner);
    for (final n in tiling.neighbours(at)) {
      if (tiling.direction(at, n) == dir) target = n;
    }
  } else if (roll < 8) {
    target = b.homeOf(from);
  } else {
    target = rng.nextInt(b.cells);
  }
  if (target == null || target == from) return null;
  final d = tiling.delta(from, target);
  return d == null ? null : (from, d.$1, d.$2);
}

/// Where the cards of [g] (slots on [before]) went: the common lattice step, or null when the
/// group was broken up.
(int, int)? _stepOf(Board before, Board after, List<int> g) {
  final t = before.tiling.delta(g.first, after.slotOfCard(before.slots[g.first]));
  if (t == null) return null;
  for (final s in g) {
    if (before.tiling.apply(s, t.$1, t.$2) != after.slotOfCard(before.slots[s])) return null;
  }
  return t;
}

/// The rule before groups were kept whole: the cards in the destination fill the vacated cells in
/// reading order.
List<int> _plain(Board b, int slot, int dx, int dy) {
  final group = b.groupOf(slot);
  final dest = [for (final s in group) b.tiling.apply(s, dx, dy)!];
  final next = List<int>.from(b.slots);
  final destSet = dest.toSet(), groupSet = group.toSet();
  final vacated = group.where((s) => !destSet.contains(s)).toList()..sort();
  final displaced = dest.where((d) => !groupSet.contains(d)).toList()..sort();
  for (var i = 0; i < group.length; i++) {
    next[dest[i]] = b.slots[group[i]];
  }
  for (var cls = 0; cls < b.tiling.classCount; cls++) {
    final into = [for (final v in vacated) if (b.tiling.classOf(v) == cls) v];
    final from = [for (final d in displaced) if (b.tiling.classOf(d) == cls) d];
    for (var i = 0; i < into.length; i++) {
      next[into[i]] = b.slots[from[i]];
    }
  }
  return next;
}

/// Checks one move against the rules: a valid layout, locked cards untouched, the moving group
/// whole at its destination, a move onto no other group unchanged from the old rule, and no
/// pushed group broken while a step had room for it (walking the groups in the documented order,
/// largest first). Returns how many groups the move pushed.
int _check(Board b, int slot, int dx, int dy, Board after, String why) {
  final tiling = b.tiling;
  expect(Board.isValidLayout(b.spec, after.slots), isTrue, reason: why);
  for (var s = 0; s < b.cells; s++) {
    if (b.isLocked(s)) expect(after.slots[s], s, reason: '$why: locked slot $s');
  }
  final group = b.groupOf(slot);
  final dest = [for (final s in group) tiling.apply(s, dx, dy)!];
  final destSet = dest.toSet(), groupSet = group.toSet();
  for (var i = 0; i < group.length; i++) {
    expect(after.slots[dest[i]], b.slots[group[i]], reason: '$why: the moving group lands whole');
  }
  final pushed = <List<int>>[];
  for (final d in dest) {
    if (!groupSet.contains(d) && b.groupOf(d).length > 1 && !pushed.any((g) => g.contains(d))) pushed.add(b.groupOf(d));
  }
  if (pushed.isEmpty) {
    expect(after.slots, _plain(b, slot, dx, dy), reason: '$why: no group touched, the move is as before');
    return 0;
  }
  pushed.sort((x, y) => x.length != y.length ? y.length - x.length : x.first - y.first);
  final free = <int>{for (final s in group) if (!destSet.contains(s)) s};
  final taken = <int>{};
  bool loose(int s) => !destSet.contains(s) && !groupSet.contains(s) && !taken.contains(s) && !b.isLocked(s) && b.groupOf(s).length == 1;
  for (final g in pushed) {
    final own = {for (final s in g) if (!destSet.contains(s)) s};
    bool open(int s) => free.contains(s) || own.contains(s) || loose(s);
    final step = _stepOf(b, after, g);
    if (step == null) {
      // Broken: no lattice step had room for it.
      for (var c = 0; c < b.cells; c++) {
        final t = tiling.delta(g.first, c);
        if (t == null || c == g.first) continue;
        final fits = g.every((s) {
          final to = tiling.apply(s, t.$1, t.$2);
          return to != null && open(to);
        });
        expect(fits, isFalse, reason: '$why: group $g broke although step $t had room');
      }
      continue;
    }
    for (final s in g) {
      final to = tiling.apply(s, step.$1, step.$2)!;
      expect(open(to), isTrue, reason: '$why: group $g landed on a cell it may not use');
      if (!free.remove(to) && !own.remove(to)) taken.add(to);
    }
    free.addAll(own);
  }
  return pushed.length;
}
