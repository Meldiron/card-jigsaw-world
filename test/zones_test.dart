import 'dart:ui';

import 'package:card_jigsaw_world/game/board.dart';
import 'package:card_jigsaw_world/game/game_controller.dart';
import 'package:card_jigsaw_world/game/zones.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Giant boards dealt by zone, Gather and the animated Peek (docs/giant-boards.md).
void main() {
  const aspects = [BoardSpec.referenceAspect, ...BoardSpec.commonAspects];

  group('zones', () {
    test('every giant board splits into a few zones of about a normal board each', () {
      for (final mode in GameMode.values) {
        for (final a in aspects) {
          final ladder = BoardSpec.giantTiers(mode, a);
          for (final spec in ladder) {
            final z = BoardZones.of(spec);
            expect(z.count, inInclusiveRange(3, 16), reason: '$mode $a ${spec.code}');
            expect(z.zoneOf, hasLength(spec.cells));
            final target = BoardZones.targetFor(mode);
            for (var i = 0; i < z.count; i++) {
              expect(z.members[i], isNotEmpty, reason: 'zone $i of $mode ${spec.code}');
              expect(z.members[i].length, inInclusiveRange(target * 0.45, target * 2.1), reason: 'zone $i of $mode ${spec.code}');
            }
          }
          // The smallest giant size has four zones, the largest about twelve.
          expect(BoardZones.of(ladder.first).count, inInclusiveRange(3, 6), reason: '$mode $a');
          expect(BoardZones.of(ladder.last).count, inInclusiveRange(8, 16), reason: '$mode $a');
        }
      }
    });

    test('pools stay in one shape class and are big enough to shuffle', () {
      for (final mode in GameMode.values) {
        for (final spec in BoardSpec.giantTiers(mode)) {
          final z = BoardZones.of(spec);
          final tiling = spec.tiling;
          final seen = <int>{};
          for (final pool in z.pools) {
            final cls = tiling.classOf(pool.first);
            expect(pool.every((s) => tiling.classOf(s) == cls), isTrue);
            final classSize = List.generate(spec.cells, (s) => s).where((s) => tiling.classOf(s) == cls).length;
            expect(pool.length >= BoardZones.minPool || pool.length == classSize, isTrue, reason: '$mode ${spec.code} pool of ${pool.length}');
            seen.addAll(pool);
          }
          expect(seen, hasLength(spec.cells), reason: 'every slot in exactly one pool');
        }
      }
    });

    test('a zoned deal keeps every card in its zone, none in place, no pair joined', () {
      for (final mode in GameMode.values) {
        for (final spec in BoardSpec.giantTiers(mode)) {
          final z = BoardZones.of(spec);
          for (final seed in [1, 2]) {
            final b = dealBoard(spec, seed: seed);
            expect(Board.isValidLayout(spec, b.slots), isTrue);
            expect(b.lockedCount, 0, reason: '$mode ${spec.code} seed $seed');
            expect(b.joinCount, 0, reason: '$mode ${spec.code} seed $seed');
            for (var s = 0; s < b.cells; s++) {
              expect(z.poolOf[b.slots[s]], z.poolOf[s], reason: '$mode ${spec.code}: card ${b.slots[s]} dealt outside its pool');
            }
            expect(z.dealtIn(b), isTrue);
          }
        }
      }
    });

    test('a board dealt across the whole board (saved before zones) is told apart', () {
      for (final mode in GameMode.values) {
        final spec = BoardSpec.giantTiers(mode).last;
        expect(BoardZones.of(spec).dealtIn(Board.shuffled(spec, seed: 4)), isFalse, reason: '$mode');
      }
    });

    test('normal boards are never dealt by zone', () {
      for (final mode in GameMode.values) {
        for (final spec in BoardSpec.tiers(mode)) {
          expect(BoardZones.appliesTo(spec), isFalse);
        }
      }
    });

    test('zone borders vanish between two finished zones', () {
      final spec = BoardSpec.giantTiers(GameMode.cards).first;
      final z = BoardZones.of(spec);
      const size = Size(300, 400);
      final all = z.borders(spec.tiling, size);
      expect(all, isNotEmpty);
      expect(z.borders(spec.tiling, size, skip: {for (var i = 0; i < z.count; i++) i}), isEmpty);
      final solved = Board(spec, List.generate(spec.cells, (i) => i));
      expect(z.completeZones(solved), hasLength(z.count));
      expect(z.completeZones(dealBoard(spec, seed: 3)), isEmpty);
    });
  });

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
      expect(container.read(gameControllerProvider(args)).zoned, isFalse, reason: 'a whole-board deal plays without zones');
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
    test('a new giant board is zoned; Peek marks the play-through and ignores a second tap', () {
      final spec = BoardSpec.giantTiers(GameMode.cards).first;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final args = GameArgs(puzzleId: 'p', spec: spec);
      container.listen(gameControllerProvider(args), (_, _) {});
      final ctrl = container.read(gameControllerProvider(args).notifier);
      expect(container.read(gameControllerProvider(args)).zoned, isTrue);
      ctrl.peek(duration: const Duration(milliseconds: 1));
      final s = container.read(gameControllerProvider(args));
      expect(s.peeking, isTrue);
      expect(s.peeked, isTrue);
      ctrl.tap(0);
      expect(container.read(gameControllerProvider(args)).peeking, isTrue);
      ctrl.restart();
      expect(container.read(gameControllerProvider(args)).zoned, isTrue, reason: 'a restarted giant board is dealt by zone again');
    });
  });
}
