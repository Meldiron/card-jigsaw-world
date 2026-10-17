import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:carden/game/board.dart';
import 'package:carden/game/game_controller.dart';
import 'package:carden/game/twins.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/coop/board_change.dart';
import 'package:carden/state/profile.dart' show Economy;
import 'package:carden/state/rewards.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pre-set pieces (owner, 2026-10-17; docs/boards.md): where a piece is the only one of its shape
/// (it could only ever sit in its own place), the board stays a full rectangle and the piece is
/// dealt in place, part of the picture's frame. It never moves, is never picked, never a twin and
/// never counted; every other piece plays as on any board. The 3x3 triangle board and the 4x4 and
/// 6x6 honeycombs have them.
void main() {
  BoardSpec square(GameMode mode, int side) => BoardSpec.squareTiers(mode).firstWhere((t) => t.rows == side);
  final added = [square(GameMode.triangles, 3), square(GameMode.hexagons, 4), square(GameMode.hexagons, 6)];
  List<int> presets(BoardSpec spec) => [for (var s = 0; s < spec.cells; s++) if (spec.tiling.isPreset(s)) s];

  test('which pieces are pre-set: the only ones of their shape', () {
    // The 3x3 triangle board (7 x 3 pieces): the middle row's two end halves.
    expect(presets(added[0]), [7, 13]);
    // The 4x4 honeycomb: the second row's halves and the bottom row's corners (rows of 4, 5, 4, 5).
    expect(presets(added[1]), [4, 8, 13, 17]);
    // The 6x6 honeycomb: the bottom row's corners.
    expect(presets(added[2]), [32, 38]);
    for (final spec in added) {
      expect(spec.playableCells, spec.cells - presets(spec).length);
      final t = spec.tiling;
      for (final s in presets(spec)) {
        expect([for (var o = 0; o < spec.cells; o++) if (t.classOf(o) == t.classOf(s)) o], [s], reason: '${spec.fullCode} slot $s');
        // Half pieces on the board's edge (the outline touches it).
        expect(t.edgeNeighbours(s).contains(null), isTrue, reason: '${spec.fullCode} slot $s');
      }
    }
    // No other square board and no giant board has any.
    for (final mode in GameMode.values) {
      for (final spec in [...BoardSpec.squareTiers(mode), ...BoardSpec.squareGiantTiers(mode)]) {
        if (!added.contains(spec)) expect(spec.tiling.presetCount, 0, reason: spec.fullCode);
      }
    }
  });

  test('the deal: pre-set pieces in place, no playable piece in place, the fewest joined pairs', () {
    for (final spec in added) {
      for (var seed = 0; seed < 40; seed++) {
        final b = Board.shuffled(spec, seed: seed);
        final why = '${spec.fullCode} seed $seed';
        expect(Board.isValidLayout(spec, b.slots), isTrue, reason: why);
        for (final s in presets(spec)) {
          expect(b.slots[s], s, reason: '$why: pre-set slot $s');
        }
        expect(b.lockedCount, 0, reason: '$why: no playable card starts in place');
        expect(b.misplaced, spec.playableCells, reason: why);
        // The 4x4 honeycomb keeps one pair in its bottom row of three; the others none.
        expect(b.joinCount, spec.tiling.unavoidableJoins, reason: why);
        expect(b.floatingGroups, spec.tiling.unavoidableJoins, reason: why);
      }
    }
    expect(added.map((s) => s.tiling.unavoidableJoins), [0, 1, 0]);
  });

  test('every deal is solvable, and solving never moves a pre-set piece', () {
    for (final spec in added) {
      for (var seed = 0; seed < 10; seed++) {
        var b = Board.shuffled(spec, seed: seed);
        var moves = 0;
        while (!b.isSolved) {
          final s = List<int>.generate(b.cells, (i) => i).firstWhere((i) => !b.isLocked(i));
          final next = b.moveTo(s, b.homeOf(s));
          expect(next, isNotNull, reason: '${spec.fullCode} seed $seed');
          for (final p in presets(spec)) {
            expect(next!.slots[p], p);
          }
          b = next!;
          moves++;
          expect(moves, lessThanOrEqualTo(spec.playableCells));
        }
        expect(b.lockedCount, spec.playableCells);
      }
    }
  });

  test('no move picks a pre-set piece, moves one, or puts another card on its place', () {
    for (final spec in added) {
      final b = Board.shuffled(spec, seed: 3);
      for (var s = 0; s < b.cells; s++) {
        for (var t = 0; t < b.cells; t++) {
          if (s == t) continue;
          final next = b.moveTo(s, t);
          if (presets(spec).contains(s)) expect(next, isNull, reason: '${spec.fullCode}: $s is pre-set');
          if (next == null) continue;
          for (final p in presets(spec)) {
            expect(next.slots[p], p, reason: '${spec.fullCode} $s -> $t');
          }
          // Co-op sends the slots a change touches: never a pre-set one.
          expect(BoardChange.between(b.slots, next.slots).slotSet.intersection(presets(spec).toSet()), isEmpty);
        }
      }
    }
  });

  test('the game: a tap or a drag on a pre-set piece does nothing; Magic, Shuffle and Gather leave them', () async {
    for (final spec in added) {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final layout = Board.shuffled(spec, seed: 5).slots;
      final args = GameArgs(puzzleId: 'p', spec: spec, layout: layout, moves: 1);
      final ctrl = container.read(gameControllerProvider(args).notifier);
      container.listen(gameControllerProvider(args), (_, _) {});
      final events = <GameEventKind>[];
      final sub = ctrl.events.listen(events.add);
      addTearDown(sub.cancel);
      final p = presets(spec).first;
      ctrl.tap(p);
      expect(container.read(gameControllerProvider(args)).selected, isNull, reason: 'never picked');
      ctrl.drop(p, p == 0 ? 1 : 0);
      expect(container.read(gameControllerProvider(args)).board.slots, layout, reason: 'never moved');
      expect(container.read(gameControllerProvider(args)).moves, 1, reason: 'not a move');
      await pumpEventQueue();
      expect(events, [GameEventKind.invalid, GameEventKind.invalid]);
      // Shuffle and Gather.
      expect(ctrl.shuffle(random: Random(2)), greaterThan(0));
      final size = spec.tiling.fit(const Size(400, 400), 1);
      ctrl.gather(Rect.fromLTWH(0, 0, size.width / 2, size.height), size);
      var s = container.read(gameControllerProvider(args));
      for (final q in presets(spec)) {
        expect(s.board.slots[q], q);
      }
      expect(s.board.lockedCount, 0, reason: '${spec.fullCode}: Shuffle and Gather never place a card');
      // Magic until the board is done: it never sends a pre-set piece.
      while (s.status != GameStatus.won) {
        expect(ctrl.magicLock(), isTrue);
        s = container.read(gameControllerProvider(args));
        for (final q in presets(spec)) {
          expect(s.board.slots[q], q);
        }
      }
      expect(s.board.lockedCount, spec.playableCells);
      expect(ctrl.magicLock(), isFalse, reason: 'nothing left to send');
    }
  });

  test('never twins: a plain picture makes twins of every shape but the pre-set pieces', () {
    for (final spec in added) {
      const w = 420, h = 360;
      final rgba = Uint8List(w * h * 4);
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = 92;
        rgba[i + 1] = 140;
        rgba[i + 2] = 205;
        rgba[i + 3] = 255;
      }
      final twins = TwinFinder(TwinPicture(w, h, rgba), spec).find();
      expect(twins.isEmpty, isFalse, reason: spec.fullCode);
      for (final cls in twins.classes) {
        expect(cls.toSet().intersection(presets(spec).toSet()), isEmpty, reason: spec.fullCode);
      }
      for (final p in presets(spec)) {
        for (var s = 0; s < spec.cells; s++) {
          if (s != p) expect(twins.same(p, s), isFalse);
        }
      }
      // The deal with those twins (every card of a shape looks alike, so they all start looking in
      // place) still keeps them in place.
      final all = Board.shuffled(spec, seed: 1, twins: twins);
      expect(Board.isValidLayout(spec, all.slots), isTrue);
      for (final p in presets(spec)) {
        expect(all.slots[p], p);
      }
      // A few twins per shape: the deal and every trade a move makes leave the pre-set pieces.
      final t = spec.tiling;
      final some = Twins.fromClasses(spec.cells, [
        for (var c = 0; c < t.classCount; c++)
          if ([for (var s = 0; s < spec.cells; s++) if (t.classOf(s) == c) s] case final cls when cls.length >= 6) cls.sublist(0, 2),
      ]);
      for (var seed = 0; seed < 8; seed++) {
        var b = Board.shuffled(spec, seed: seed, twins: some);
        for (var k = 0; k < 6 && !b.isSolved; k++) {
          final s = List<int>.generate(b.cells, (i) => i).firstWhere((i) => !b.isLocked(i));
          final settled = some.settle(b, b.moveTo(s, b.homeOf(s))!);
          for (final (x, y) in settled.swaps) {
            expect(presets(spec).contains(x) || presets(spec).contains(y), isFalse);
          }
          b = settled.board;
          for (final p in presets(spec)) {
            expect(b.slots[p], p);
          }
        }
      }
    }
  });

  test('counts: locked of the playable cards, rewards per playable card, quests by the side', () {
    final pay = {
      for (final spec in added) spec.fullCode: (Economy.completionCoins(spec.playableCells, 3, mode: spec.mode), Economy.completionXp(spec.playableCells, 3, mode: spec.mode)),
    };
    // docs/economy.md: what each pays for 3 stars, the first time.
    expect(pay, {'triangles:7x3t0': (50, 105), 'hexagons:4x4t2': (41, 98), 'hexagons:6x6t6': (108, 185)});
    for (final spec in added) {
      final b = Board.shuffled(spec, seed: 2);
      expect(b.lockedCount, 0);
      expect(b.playableCells, spec.playableCells);
      expect(BoardSpec.progressOf(spec.mode, b.slots), (placed: 0, playable: spec.playableCells), reason: 'a saved board just dealt');
      final solved = Board(spec, List<int>.generate(spec.cells, (i) => i));
      expect(solved.lockedCount, spec.playableCells);
      expect(BoardSpec.progressOf(spec.mode, solved.slots), (placed: spec.playableCells, playable: spec.playableCells));
      // Saves keep every piece (gridSize is the layout's length); quests count the side squared.
      final side = spec.mode == GameMode.triangles ? spec.rows : spec.cols;
      expect(Goals.sizeOf(BoardFinish(at: DateTime(2026, 10, 17), gridSize: spec.cells, mode: spec.mode.code)), side * side);
    }
  });

  test('Expand never crops more than the square board of these sizes', () {
    for (final spec in added) {
      for (var a = 0.5; a <= 1.0001; a += 0.005) {
        final e = BoardSpec.expandTiers(spec.mode, a).firstWhere((t) => t.tier == spec.tier);
        expect(e.tiling.fitFor(a).crop, lessThanOrEqualTo(spec.tiling.fitFor(a).crop + 1e-9), reason: '${spec.fullCode} on $a: ${e.code}');
        expect(e.cells, greaterThanOrEqualTo(BoardLayouts.expandFloors[spec.tier] ?? 0));
        // Its Expand board deals like any other: no playable card in place.
        expect(Board.shuffled(e, seed: 1).lockedCount, 0);
      }
    }
  });

  test('saves resume on the board they were dealt on, for every picture', () {
    for (final spec in added) {
      final layout = Board.shuffled(spec, seed: 4).slots;
      for (final a in [9 / 16, 2 / 3, 3 / 4, 4 / 5, 1.0, 4 / 3]) {
        expect(BoardSpec.fromSaved(spec.mode, spec.cells, a, layout: layout), spec, reason: '${spec.fullCode} on $a');
      }
      expect(BoardSpec.fromCells(spec.mode, spec.cells), spec, reason: 'Home\'s Continue before the picture is read');
      expect(BoardSpec.fromCode(BoardCode.toPath(spec.fullCode)), spec);
    }
  });

  test('Hexagons have no 3x3: every one of its four deals keeps six joined pairs and is solved in one move', () {
    final spec = BoardSpec(GameMode.hexagons, 3, 3, 'Cozy', tier: 0);
    final t = spec.tiling;
    expect(presets(spec), [3, 6], reason: 'the middle row\'s two halves');
    final deals = _allDeals(spec);
    expect(deals, hasLength(4));
    for (final d in deals) {
      final b = Board(spec, d);
      expect(b.joinCount, 6);
      expect(t.unavoidableJoins, 6);
      var oneMove = false;
      for (var s = 0; s < b.cells && !oneMove; s++) {
        for (var g = 0; g < b.cells && !oneMove; g++) {
          if (s != g && !b.isLocked(s)) oneMove = b.moveTo(s, g)?.isSolved ?? false;
        }
      }
      expect(oneMove, isTrue);
    }
    expect(BoardSpec.squareTiers(GameMode.hexagons).first.size, '4x4');
  });

  test('the 4x4 honeycomb: no deal keeps fewer than one joined pair (all of them searched)', () {
    final spec = added[1];
    final deals = _allDeals(spec);
    expect(deals.length, greaterThan(30000));
    var fewest = 1 << 30;
    for (final d in deals) {
      fewest = min(fewest, Board(spec, d).joinCount);
    }
    expect(fewest, spec.tiling.unavoidableJoins);
  });
}

/// Every deal of [spec] with no playable card in place: each shape's cards in every order that
/// moves them all.
List<List<int>> _allDeals(BoardSpec spec) {
  final t = spec.tiling;
  final classes = <int, List<int>>{};
  for (var s = 0; s < spec.cells; s++) {
    (classes[t.classOf(s)] ??= []).add(s);
  }
  Iterable<List<int>> orders(List<int> xs) sync* {
    if (xs.length <= 1) {
      yield List.of(xs);
      return;
    }
    for (var i = 0; i < xs.length; i++) {
      for (final rest in orders([...xs]..removeAt(i))) {
        yield [xs[i], ...rest];
      }
    }
  }

  final shapes = classes.values.toList();
  final options = [
    for (final cls in shapes)
      [
        for (final o in orders(cls))
          if (cls.length == 1 || [for (var i = 0; i < cls.length; i++) o[i] != cls[i]].every((x) => x)) o,
      ],
  ];
  final out = <List<int>>[];
  void build(int k, List<int> perm) {
    if (k == shapes.length) {
      out.add(List.of(perm));
      return;
    }
    for (final o in options[k]) {
      for (var i = 0; i < shapes[k].length; i++) {
        perm[shapes[k][i]] = o[i];
      }
      build(k + 1, perm);
    }
  }

  build(0, List<int>.filled(spec.cells, -1));
  return out;
}
