import 'dart:math';
import 'dart:ui';

import 'package:carden/game/board.dart';
import 'package:carden/game/game_controller.dart';
import 'package:carden/game/gather.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The board tools: Gather (giant boards) and its Undo, Shuffle, Magic on the selected card and its
/// neighbours, and the animated Peek (docs/giant-boards.md).
void main() {
  group('gather', () {
    test('brings the cards that belong in view into it, without solving any', () {
      for (final mode in GameMode.values) {
        final spec = BoardSpec.giantTiers(mode).last;
        const size = Size(360, 480);
        // A global shuffle: most cards in view belong elsewhere.
        final before = Board.shuffled(spec, seed: 9);
        final view = Rect.fromLTWH(90, 120, size.width / 3, size.height / 3);
        final after = gatherInto(before, view, size);
        expect(after, isNotNull, reason: '$mode');
        expect(Board.isValidLayout(spec, after!.slots), isTrue);
        expect(after.lockedCount, before.lockedCount, reason: 'Gather never puts a card in its place');
        expect(after.joinCount, lessThanOrEqualTo(before.joinCount + 2), reason: '$mode: Gather avoids joining pairs');
        final tiling = spec.tiling;
        bool inView(int s) => view.contains(tiling.cellCenter(s, size));
        int belongingInView(Board b) => [for (var s = 0; s < b.cells; s++) if (inView(s) && inView(b.homeOf(s))) s].length;
        final want = [for (var s = 0; s < spec.cells; s++) if (inView(s)) s].length;
        expect(belongingInView(after), greaterThan(belongingInView(before)), reason: '$mode');
        expect(belongingInView(after), greaterThanOrEqualTo((want * 0.85).floor()), reason: '$mode: most of the view now belongs here');
        // Cards in place never move.
        for (var s = 0; s < spec.cells; s++) {
          if (before.isLocked(s)) expect(after.slots[s], before.slots[s]);
        }
      }
    });

    test('nothing to gather when the view already holds its cards', () {
      final spec = BoardSpec.giantTiers(GameMode.cards).first;
      final solved = Board(spec, List.generate(spec.cells, (i) => i));
      expect(gatherInto(solved, const Rect.fromLTWH(0, 0, 100, 100), const Size(300, 400)), isNull);
      expect(canGather(solved, const Rect.fromLTWH(0, 0, 100, 100), const Size(300, 400)), isFalse);
      // The whole board in view: every card already belongs in it.
      final dealt = Board.shuffled(spec, seed: 4);
      expect(canGather(dealt, const Rect.fromLTWH(0, 0, 360, 480), const Size(360, 480)), isFalse);
    });

    test('canGather says exactly when Gather has something to do', () {
      final rng = Random(5);
      const size = Size(360, 480);
      var some = 0, none = 0;
      for (final mode in GameMode.values) {
        for (final spec in BoardSpec.giantTiers(mode)) {
          var b = Board.shuffled(spec, seed: rng.nextInt(1000));
          for (var i = 0; i < 6; i++) {
            final w = 40 + rng.nextDouble() * 320, h = 50 + rng.nextDouble() * 430;
            final view = Rect.fromLTWH(rng.nextDouble() * (size.width - w), rng.nextDouble() * (size.height - h), w, h);
            // Gather on the same view until it has nothing left to bring in.
            for (var round = 0; round < 6; round++) {
              final after = gatherInto(b, view, size);
              expect(canGather(b, view, size), after != null, reason: '$mode ${spec.code} $view round $round');
              if (after == null) {
                none++;
                break;
              }
              some++;
              b = after;
            }
          }
        }
      }
      expect(some, greaterThan(10));
      expect(none, greaterThan(10));
    });

    test('Gather is not a move and Undo takes it back without adding one', () async {
      final spec = BoardSpec.giantTiers(GameMode.cards).last;
      final layout = Board.shuffled(spec, seed: 12).slots;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final args = GameArgs(puzzleId: 'p', spec: spec, layout: layout, moves: 3);
      final ctrl = container.read(gameControllerProvider(args).notifier);
      container.listen(gameControllerProvider(args), (_, _) {});
      final events = <GameEventKind>[];
      final sub = ctrl.events.listen(events.add);
      addTearDown(sub.cancel);
      final n = ctrl.gather(const Rect.fromLTWH(0, 0, 120, 160), const Size(360, 480));
      final s = container.read(gameControllerProvider(args));
      expect(n, greaterThan(0));
      expect(s.moves, 3);
      expect(s.history, hasLength(1));
      ctrl.undo();
      final back = container.read(gameControllerProvider(args));
      expect(back.board.slots, layout);
      expect(back.moves, 3, reason: 'Undo is not a move either');
      await pumpEventQueue();
      expect(events, [GameEventKind.rearrange, GameEventKind.undo]);
    });

    test('Gather does nothing when the view holds its cards: no shuffle any more', () {
      final spec = BoardSpec.giantTiers(GameMode.cards).first;
      final layout = Board.shuffled(spec, seed: 12).slots;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final args = GameArgs(puzzleId: 'p', spec: spec, layout: layout, moves: 2);
      final ctrl = container.read(gameControllerProvider(args).notifier);
      container.listen(gameControllerProvider(args), (_, _) {});
      const size = Size(360, 480);
      expect(ctrl.gather(Offset.zero & size, size), 0);
      final s = container.read(gameControllerProvider(args));
      expect(s.board.slots, layout);
      expect(s.history, isEmpty);
    });
  });

  group('shuffle', () {
    Board joinedPairAndPlaced(BoardSpec spec) {
      // A shuffled board with one card in place and, where the shape allows it, a pair of cards
      // joined together away from their places.
      final tiling = spec.tiling;
      var b = Board.shuffled(spec, seed: 21);
      final home = List.generate(b.cells, (i) => i).firstWhere((s) => !b.isLocked(s));
      b = b.swap(home, b.slotOfCard(home));
      final mid = spec.cells ~/ 2;
      for (final y in tiling.neighbours(mid)) {
        final d = tiling.direction(mid, y);
        for (var a = 0; a < spec.cells; a++) {
          if (a == mid || a == home || b.isLocked(b.slotOfCard(a))) continue;
          for (final c in tiling.neighbours(a)) {
            if (c == y || c == home || tiling.direction(a, c) != d || tiling.classOf(a) != tiling.classOf(mid) || tiling.classOf(c) != tiling.classOf(y)) continue;
            var t = b.swap(mid, b.slotOfCard(a));
            t = t.swap(y, t.slotOfCard(c));
            if (t.slots[mid] == a && t.slots[y] == c && t.groupOf(mid).length > 1 && t.isLocked(home) && Board.isValidLayout(spec, t.slots)) return t;
          }
        }
      }
      return b;
    }

    test('only loose cards move; cards in place and joined groups stay exactly where they are', () {
      for (final mode in GameMode.values) {
        final spec = BoardSpec.giantTiers(mode).first;
        const size = Size(360, 480);
        final before = joinedPairAndPlaced(spec);
        if (mode == GameMode.cards) expect(before.groupOf(spec.cells ~/ 2).length, greaterThan(1), reason: 'the test board has a joined pair');
        final whole = Offset.zero & size;
        final after = shuffleInView(before, whole, size, random: Random(4));
        expect(after, isNotNull, reason: '$mode');
        expect(Board.isValidLayout(spec, after!.slots), isTrue);
        for (var s = 0; s < spec.cells; s++) {
          final fixed = before.isLocked(s) || before.groupOf(s).length > 1;
          if (fixed) expect(after.slots[s], before.slots[s], reason: '$mode: slot $s is in place or joined');
          if (!fixed) {
            expect(after.slots[s], isNot(before.slots[s]), reason: '$mode: every loose card moves');
            expect(after.isLocked(s), isFalse, reason: '$mode: the shuffle never puts a card in place');
          }
        }
        expect(after.lockedCount, before.lockedCount);
        expect(after.joinCount, before.joinCount, reason: '$mode: the shuffle joins no new pair');
      }
    });

    test('on the largest boards too, a whole-board shuffle joins no pair', () {
      for (final mode in GameMode.values) {
        final spec = BoardSpec.giantTiers(mode).last;
        const size = Size(360, 480);
        for (final seed in [1, 2, 3]) {
          final before = Board.shuffled(spec, seed: seed);
          final after = shuffleInView(before, Offset.zero & size, size, random: Random(seed))!;
          expect(after.joinCount, before.joinCount, reason: '$mode seed $seed');
          expect(after.lockedCount, before.lockedCount, reason: '$mode seed $seed');
        }
      }
    });

    test('a view keeps its cards: the shuffle stays inside it', () {
      final spec = BoardSpec.giantTiers(GameMode.cards).last;
      const size = Size(360, 480);
      final before = Board.shuffled(spec, seed: 8);
      final view = Rect.fromLTWH(60, 80, size.width / 3, size.height / 3);
      final after = shuffleInView(before, view, size, random: Random(1))!;
      for (var s = 0; s < spec.cells; s++) {
        if (!view.contains(spec.tiling.cellCenter(s, size))) expect(after.slots[s], before.slots[s]);
      }
    });

    test('on a normal board every loose card moves; cards in place and groups stay', () {
      for (final mode in GameMode.values) {
        for (final spec in [BoardSpec.tiers(mode)[0], BoardSpec.tiers(mode)[4]]) {
          final before = joinedPairAndPlaced(spec);
          final after = shuffleLoose(before, random: Random(2))!;
          expect(Board.isValidLayout(spec, after.slots), isTrue);
          var moved = 0, loose = 0;
          for (var s = 0; s < spec.cells; s++) {
            final fixed = before.isLocked(s) || before.groupOf(s).length > 1;
            if (fixed) expect(after.slots[s], before.slots[s], reason: '${spec.fullCode}: slot $s is in place or joined');
            if (!fixed) {
              loose++;
              if (after.slots[s] != before.slots[s]) moved++;
            }
          }
          // A shape with a single loose card (a lone half piece) cannot move; every other one does.
          expect(moved, greaterThan(loose * 3 ~/ 4), reason: '${spec.fullCode}: the loose cards move');
          expect(after.lockedCount, before.lockedCount, reason: '${spec.fullCode}: the shuffle never puts a card in place');
        }
      }
    });

    test('Shuffle is not a move; it says when nothing is left to shuffle', () {
      final spec = BoardSpec.tiers(GameMode.cards)[2];
      final layout = Board.shuffled(spec, seed: 6).slots;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final args = GameArgs(puzzleId: 'p', spec: spec, layout: layout, moves: 5);
      final ctrl = container.read(gameControllerProvider(args).notifier);
      container.listen(gameControllerProvider(args), (_, _) {});
      final moved = ctrl.shuffle(random: Random(1));
      final s = container.read(gameControllerProvider(args));
      expect(moved, spec.cells, reason: 'every card was loose');
      expect(s.moves, 5);
      expect(s.board.slots, isNot(layout));
      expect(s.board.lockedCount, 0);
      // Two loose cards that belong in each other's places cannot move without one landing home.
      final last = List<int>.generate(spec.cells, (i) => i);
      last[0] = 1;
      last[1] = 0;
      final args2 = GameArgs(puzzleId: 'q', spec: spec, layout: last);
      final ctrl2 = container.read(gameControllerProvider(args2).notifier);
      container.listen(gameControllerProvider(args2), (_, _) {});
      expect(ctrl2.shuffle(), 0);
      expect(container.read(gameControllerProvider(args2)).board.slots, last);
    });

    test('Shuffle on a giant board keeps to the view', () {
      final spec = BoardSpec.giantTiers(GameMode.cards).first;
      final layout = Board.shuffled(spec, seed: 3).slots;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final args = GameArgs(puzzleId: 'p', spec: spec, layout: layout);
      final ctrl = container.read(gameControllerProvider(args).notifier);
      container.listen(gameControllerProvider(args), (_, _) {});
      const size = Size(360, 480);
      const view = Rect.fromLTWH(100, 100, 120, 160);
      expect(ctrl.shuffle(view: view, size: size, random: Random(2)), greaterThan(4));
      final after = container.read(gameControllerProvider(args)).board;
      for (var s = 0; s < spec.cells; s++) {
        if (!view.contains(spec.tiling.cellCenter(s, size))) expect(after.slots[s], layout[s]);
      }
    });

    test('nothing to shuffle: a solved board or a single loose card', () {
      final spec = BoardSpec.giantTiers(GameMode.cards).first;
      final solved = Board(spec, List.generate(spec.cells, (i) => i));
      expect(shuffleInView(solved, const Rect.fromLTWH(0, 0, 360, 480), const Size(360, 480)), isNull);
      expect(shuffleLoose(solved), isNull);
    });
  });

  group('magic', () {
    test('Magic puts the selected card in place, even while a Hint shows another one', () {
      final spec = BoardSpec.giantTiers(GameMode.cards).first;
      final layout = Board.shuffled(spec, seed: 30).slots;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final args = GameArgs(puzzleId: 'p', spec: spec, layout: layout);
      final ctrl = container.read(gameControllerProvider(args).notifier);
      container.listen(gameControllerProvider(args), (_, _) {});
      ctrl.showHint();
      final hinted = container.read(gameControllerProvider(args)).hintSlot;
      final b = container.read(gameControllerProvider(args)).board;
      final pick = List.generate(b.cells, (i) => i).firstWhere((s) => !b.isLocked(s) && s != hinted && b.groupOf(s).length == 1);
      final card = b.slots[pick];
      ctrl.tap(pick);
      expect(container.read(gameControllerProvider(args)).selected, pick);
      expect(ctrl.magicLock(), isTrue);
      final after = container.read(gameControllerProvider(args)).board;
      expect(after.slots[card], card, reason: 'the selected card is now in its place');
      for (final n in spec.tiling.neighbours(card)) {
        expect(after.slots[n], n, reason: 'and its picture neighbour $n');
      }
    });

    test('Magic places the selected card and its neighbours: one move each, a lock but never a double lock', () async {
      const spec = GridSpec(4, 4, 'Relaxed');
      for (final card in [5, 0, 15, 6]) {
        final layout = Board.shuffled(spec, seed: card).slots;
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final args = GameArgs(puzzleId: 'p$card', spec: spec, layout: layout, moves: 2);
        final ctrl = container.read(gameControllerProvider(args).notifier);
        container.listen(gameControllerProvider(args), (_, _) {});
        final events = <GameEventKind>[];
        final sub = ctrl.events.listen(events.add);
        addTearDown(sub.cancel);
        final b = container.read(gameControllerProvider(args)).board;
        // What Magic should send: the card, then each neighbour not in place by then.
        var expected = b.moveTo(b.slotOfCard(card), card)!;
        var sent = 1;
        for (final n in spec.tiling.neighbours(card)) {
          if (expected.isLocked(n)) continue;
          expected = expected.moveTo(expected.slotOfCard(n), n)!;
          sent++;
        }
        ctrl.tap(b.slotOfCard(card));
        expect(ctrl.magicLock(), isTrue);
        final s = container.read(gameControllerProvider(args));
        expect(s.board.slots, expected.slots);
        for (final c in [card, ...spec.tiling.neighbours(card)]) {
          expect(s.board.isLocked(c), isTrue, reason: 'card $c in place');
        }
        expect(s.moves, 2 + sent, reason: 'one move per card Magic sends');
        expect(s.hintsUsed, 1);
        expect(s.history, hasLength(1), reason: 'one step on the board');
        expect(s.chain, 0, reason: 'no ×2 DOUBLE LOCK for Magic');
        expect(s.bestLock, 0, reason: 'the longest lock stays the player\'s');
        expect(s.justLocked.length, greaterThanOrEqualTo(spec.tiling.neighbours(card).length + 1));
        await pumpEventQueue();
        expect(events.last, GameEventKind.lock);
        expect(events, isNot(contains(GameEventKind.doubleLock)));
      }
    });

    test('on a 3x3, Magic places up to 5 of the 9 cards', () {
      const spec = GridSpec(3, 3, 'Cozy');
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Every card one cell along (a single cycle): no card in place, no pair joined.
      final layout = [for (var s = 0; s < 9; s++) (s + 4) % 9];
      final args = GameArgs(puzzleId: 'p', spec: spec, layout: layout);
      final ctrl = container.read(gameControllerProvider(args).notifier);
      container.listen(gameControllerProvider(args), (_, _) {});
      ctrl.tap(layout.indexOf(4));
      ctrl.magicLock();
      final b = container.read(gameControllerProvider(args)).board;
      for (final c in [4, 1, 3, 5, 7]) {
        expect(b.isLocked(c), isTrue, reason: 'card $c');
      }
      expect(container.read(gameControllerProvider(args)).moves, inInclusiveRange(1, 5));
    });
  });

  group('peek', () {
    test('a new giant board is dealt with no card in place; Peek marks the play-through and ignores a second tap', () {
      final spec = BoardSpec.giantTiers(GameMode.cards).first;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final args = GameArgs(puzzleId: 'p', spec: spec);
      container.listen(gameControllerProvider(args), (_, _) {});
      final ctrl = container.read(gameControllerProvider(args).notifier);
      final dealt = container.read(gameControllerProvider(args)).board;
      expect(dealt.lockedCount, 0);
      expect(dealt.joinCount, 0);
      ctrl.peek(duration: const Duration(milliseconds: 1));
      final s = container.read(gameControllerProvider(args));
      expect(s.peeking, isTrue);
      expect(s.peeked, isTrue);
      ctrl.tap(0);
      expect(container.read(gameControllerProvider(args)).peeking, isTrue);
      ctrl.restart();
      expect(container.read(gameControllerProvider(args)).board.lockedCount, 0);
    });
  });
}
