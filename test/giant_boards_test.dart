import 'package:carden/game/board.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const aspects = [BoardSpec.referenceAspect, ...BoardSpec.commonAspects];

  group('giant ladder', () {
    test('square giant sizes: four per shape, NxN, growing, near their targets, above every normal board', () {
      for (final mode in GameMode.values) {
        final giant = BoardSpec.squareGiantTiers(mode);
        expect(giant, hasLength(4), reason: '$mode');
        final targets = BoardSpec.giantTargets[mode]!;
        for (var i = 0; i < giant.length; i++) {
          final g = giant[i];
          expect(g.cols, g.rows, reason: '$mode ${g.code} is square');
          expect(g.tier, BoardSpec.firstGiantTier + i);
          expect(g.label, BoardSpec.giantLabels[i]);
          expect(g.isGiant, isTrue);
          expect(g.cells, inInclusiveRange(targets[i] * 0.85, targets[i] * 1.15), reason: '$mode ${g.code} (${g.cells}) vs ${targets[i]}');
          expect(g.cells, greaterThanOrEqualTo(BoardLayouts.giantFloor(mode)), reason: '$mode ${g.code}: a saved count names the giant ladder');
          if (i > 0) expect(g.cells, greaterThan(giant[i - 1].cells * 1.09));
        }
        // Cards: 10x10 to 17x17, about 100 to 300 cards.
        if (mode == GameMode.cards) expect(giant.map((g) => g.code), ['10x10', '12x12', '14x14', '17x17']);
      }
    });

    test('square giant boards shuffle with no card in place and no joined pair', () {
      for (final mode in GameMode.values) {
        for (final g in BoardSpec.squareGiantTiers(mode)) {
          final b = Board.shuffled(g, seed: 5);
          expect(b.lockedCount, 0, reason: g.fullCode);
          expect(b.joinCount, 0, reason: g.fullCode);
          expect(Board.isValidLayout(g, b.slots), isTrue, reason: g.fullCode);
          expect(b.slots.join(',').length, lessThan(4096), reason: '${g.fullCode} saves within the layout column');
        }
      }
    });

    test('Expand sizes (the old giant ladder): four per shape, growing, near their targets, apart from the normal ladder', () {
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
        for (final g in [...BoardSpec.squareGiantTiers(mode), ...BoardSpec.giantTiers(mode)]) {
          final back = BoardSpec.fromCode(BoardCode.toPath(g.fullCode));
          expect(back, g);
          expect(back.tierIndex, g.tier);
          expect(back.label, g.label);
          expect(BoardSpec.fromSaved(mode, g.cells, BoardSpec.referenceAspect), g);
          expect(BoardSpec.fromCells(mode, g.cells).tierIndex, g.tier);
          expect(g.fitTo(1.0).isGiant, isTrue);
        }
        for (final g in BoardSpec.squareGiantTiers(mode)) {
          expect(BoardSpec.fromCode(g.fullCode).expand, isFalse);
          expect(BoardSpec.forPicture(mode, g.tier, BoardSpec.referenceAspect), g, reason: 'square unless Expand');
          expect(BoardSpec.forPicture(mode, g.tier, 0.31), g, reason: 'whatever the picture');
        }
        for (final g in BoardSpec.giantTiers(mode)) {
          expect(BoardSpec.forPicture(mode, g.tier, BoardSpec.referenceAspect, expand: true), BoardSpec.offersExpand(mode, BoardSpec.referenceAspect, giant: true) ? g : BoardSpec.squareAt(mode, g.tier));
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
