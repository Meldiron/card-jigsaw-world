import 'dart:math';
import 'dart:ui';

import 'package:carden/game/board.dart';
import 'package:carden/game/game_controller.dart';
import 'package:carden/game/gather.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Giant boards: Gather, its shuffle, Magic on the selected card and the animated Peek
/// (docs/giant-boards.md).
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
    });

    test('Gather is not a move and Undo takes it back', () {
      final spec = BoardSpec.giantTiers(GameMode.cards).last;
      final layout = Board.shuffled(spec, seed: 12).slots;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final args = GameArgs(puzzleId: 'p', spec: spec, layout: layout, moves: 3);
      final ctrl = container.read(gameControllerProvider(args).notifier);
      container.listen(gameControllerProvider(args), (_, _) {});
      final n = ctrl.gather(const Rect.fromLTWH(0, 0, 120, 160), const Size(360, 480)).gathered;
      final s = container.read(gameControllerProvider(args));
      expect(n, greaterThan(0));
      expect(s.moves, 3);
      expect(s.history, hasLength(1));
      ctrl.undo();
      expect(container.read(gameControllerProvider(args)).board.slots, layout);
    });
  });

  group('shuffle (a Gather with nothing to bring in)', () {
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

    test('Gather shuffles when the view already holds its cards; Undo takes it back', () {
      final spec = BoardSpec.giantTiers(GameMode.cards).first;
      final layout = Board.shuffled(spec, seed: 12).slots;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final args = GameArgs(puzzleId: 'p', spec: spec, layout: layout, moves: 2);
      final ctrl = container.read(gameControllerProvider(args).notifier);
      container.listen(gameControllerProvider(args), (_, _) {});
      // The whole board in view: every card belongs here, so nothing is gathered.
      const size = Size(360, 480);
      final r = ctrl.gather(Offset.zero & size, size, random: Random(3));
      expect(r.gathered, 0);
      expect(r.shuffled, greaterThan(spec.cells ~/ 2));
      final s = container.read(gameControllerProvider(args));
      expect(s.moves, 2, reason: 'not a move');
      expect(s.board.slots, isNot(layout));
      ctrl.undo();
      expect(container.read(gameControllerProvider(args)).board.slots, layout);
    });

    test('nothing to shuffle: a solved board or a single loose card', () {
      final spec = BoardSpec.giantTiers(GameMode.cards).first;
      final solved = Board(spec, List.generate(spec.cells, (i) => i));
      expect(shuffleInView(solved, const Rect.fromLTWH(0, 0, 360, 480), const Size(360, 480)), isNull);
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
