import 'dart:ui';

import 'package:card_jigsaw_world/game/board.dart';
import 'package:card_jigsaw_world/game/game_controller.dart';
import 'package:card_jigsaw_world/game/gather.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Giant boards: Gather and the animated Peek (docs/giant-boards.md).
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
      final n = ctrl.gather(const Rect.fromLTWH(0, 0, 120, 160), const Size(360, 480));
      final s = container.read(gameControllerProvider(args));
      expect(n, greaterThan(0));
      expect(s.moves, 3);
      expect(s.history, hasLength(1));
      ctrl.undo();
      expect(container.read(gameControllerProvider(args)).board.slots, layout);
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
