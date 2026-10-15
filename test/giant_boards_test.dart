import 'package:carden/game/board.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const aspects = [BoardSpec.referenceAspect, ...BoardSpec.commonAspects];

  group('giant ladder', () {
    test('four sizes per shape, growing, near their targets, apart from the normal ladder', () {
      for (final mode in GameMode.values) {
        for (final a in aspects) {
          final giant = BoardSpec.giantTiers(mode, a);
          final normal = BoardSpec.tiers(mode, a);
          expect(giant, hasLength(4), reason: '$mode $a');
          final targets = BoardSpec.giantTargets[mode]!;
          for (var i = 0; i < giant.length; i++) {
            final g = giant[i];
            expect(g.tier, BoardSpec.firstGiantTier + i);
            expect(g.isGiant, isTrue);
            expect(g.label, BoardSpec.giantLabels[i]);
            expect(g.cells, inInclusiveRange(targets[i] * 0.7, targets[i] * 1.35), reason: '$mode $a ${g.code} (${g.cells}) vs ${targets[i]}');
            if (i > 0) expect(g.cells, greaterThan(giant[i - 1].cells * 1.09));
          }
          expect(giant.first.cells, greaterThan(normal.last.cells), reason: '$mode $a');
          expect(normal.every((t) => !t.isGiant), isTrue);
        }
      }
    });

    test('codes, saves and piece counts find giant boards again', () {
      for (final mode in GameMode.values) {
        for (final g in BoardSpec.giantTiers(mode)) {
          final back = BoardSpec.fromCode(BoardCode.toPath(g.fullCode));
          expect(back, g);
          expect(back.tierIndex, g.tier);
          expect(back.label, g.label);
          expect(BoardSpec.fromSaved(mode, g.cells, BoardSpec.referenceAspect), g);
          expect(BoardSpec.fromCells(mode, g.cells).tierIndex, g.tier);
          expect(BoardSpec.forPicture(mode, g.tier, BoardSpec.referenceAspect), g);
          expect(g.fitTo(1.0).isGiant, isTrue);
        }
        // Normal boards keep their own ladder.
        for (final t in BoardSpec.tiers(mode)) {
          expect(BoardSpec.fromCells(mode, t.cells).isGiant, isFalse);
          expect(BoardSpec.fromCode(t.fullCode).tierIndex, t.tier);
        }
      }
      expect(BoardSpec.labelOf(8), 'Large');
      expect(BoardSpec.labelOf(11), 'Colossal');
      expect(BoardSpec.labelOf(7), 'Master');
    });

    test('the largest board saves within the 4096-character layout column', () {
      for (final mode in GameMode.values) {
        for (final a in aspects) {
          final biggest = BoardSpec.giantTiers(mode, a).last;
          final board = Board.shuffled(biggest, seed: 7);
          expect(board.slots.join(',').length, lessThan(4096), reason: '$mode $a ${biggest.cells} cells');
        }
      }
    });

    test('shuffles of 300+ pieces are fast, deranged and have no joined pair', () {
      for (final mode in GameMode.values) {
        final biggest = BoardSpec.giantTiers(mode).last;
        final watch = Stopwatch()..start();
        final board = Board.shuffled(biggest, seed: 3);
        watch.stop();
        expect(board.lockedCount, 0, reason: '$mode');
        expect(board.joinCount, 0, reason: '$mode');
        expect(watch.elapsedMilliseconds, lessThan(1500), reason: '$mode took ${watch.elapsedMilliseconds} ms');
        // A move keeps the board valid at this size.
        final next = board.moveTo(0, board.homeOf(0));
        if (next != null) expect(Board.isValidLayout(biggest, next.slots), isTrue);
      }
    });
  });
}
