import 'package:carden/game/board.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Square boards (owner, 2026-10-17): a size deals the same N x N board for
/// every picture, in every mode; Expand lays the same sizes out for the
/// picture. Boards saved by older builds (the picture-shaped ladder) still
/// resume, and a square board's piece count never stands for another board
/// of the same picture, so saves resume on exactly the board they were dealt.
void main() {
  /// Portrait and square pictures every 0.01, plus landscape ones and the extremes.
  final aspects = <double>[
    for (var i = 0; i <= 50; i++) 0.5 + i * 0.01,
    9 / 16, 2 / 3, 3 / 4, 4 / 5, 939 / 893, 4 / 3, 3 / 2, 16 / 9, 0.3, 900 / 21,
  ];

  group('square ladder', () {
    test('the same sides in every mode, as far as each tiling can deal them', () {
      String sizes(GameMode m) => BoardSpec.squareTiers(m).map((t) => '${t.size} ${t.label}').join(', ');
      expect(sizes(GameMode.cards), '3x3 Cozy, 4x4 Relaxed, 5x5 Tricky, 6x6 Expert, 7x7 Master');
      expect(sizes(GameMode.squares), '3x3 Cozy, 4x4 Relaxed, 5x5 Tricky, 6x6 Expert, 7x7 Master');
      expect(sizes(GameMode.triangles), '4x4 Relaxed, 5x5 Tricky, 6x6 Expert, 7x7 Master');
      expect(sizes(GameMode.hexagons), '5x5 Tricky, 7x7 Master');
      // A triangle column is one up and one down triangle: 2N + 1 pieces in a row, about as wide as tall.
      expect([for (final t in BoardSpec.squareTiers(GameMode.triangles)) t.code], ['9x4', '11x5', '13x6', '15x7']);
      expect([for (final t in BoardSpec.squareTiers(GameMode.triangles)) t.cells], [36, 55, 78, 105]);
      for (final t in BoardSpec.squareTiers(GameMode.triangles)) {
        expect(t.tiling.naturalAspect, closeTo(2 / 1.7320508, 0.001), reason: '${t.size} is about as wide as it is tall');
      }
      // The Cards entries are the square steps of the old fixed ladder (and 7x7 for 6x8).
      expect(BoardSpec.squareTiers(GameMode.cards), GridSpec.square);
      for (final t in GridSpec.square.take(4)) {
        expect(GridSpec.tiers[t.tier], t, reason: 'tier ${t.tier} keeps its cards');
      }
    });

    test('a size deals the same board whatever the picture', () {
      for (final mode in GameMode.values) {
        for (final t in BoardSpec.squareTiers(mode)) {
          for (final a in aspects) {
            final dealt = BoardSpec.forPicture(mode, t.tier, a);
            expect(dealt, t, reason: '${mode.code} ${t.label} on $a');
            expect(dealt.expand, isFalse);
            expect(t.fitTo(a), t, reason: 'the next picture keeps ${t.fullCode}');
          }
        }
      }
    });

    test('a size a mode lacks gives the nearest one, a tie the bigger', () {
      expect(BoardSpec.forPicture(GameMode.triangles, 4, 0.75).size, '5x5');
      expect(BoardSpec.forPicture(GameMode.triangles, 0, 0.75).size, '4x4', reason: 'no 3x3 triangle board');
      expect(BoardSpec.forPicture(GameMode.hexagons, 0, 0.75).size, '5x5');
      expect(BoardSpec.forPicture(GameMode.hexagons, 6, 0.75).size, '7x7');
      // The guided start opens one step up from the first board's nine cards: Easy gives 4x4.
      expect(BoardSpec.forPicture(GameMode.cards, 1, 0.75).code, '4x4');
      // Medium and Hard, remembered from before, give Tricky and Expert.
      expect(BoardSpec.forPicture(GameMode.cards, 3, 0.75).code, '5x5');
      expect(BoardSpec.forPicture(GameMode.cards, 5, 0.75).code, '6x6');
    });

    test('codes: square boards, Expand boards and the first board', () {
      for (final mode in GameMode.values) {
        for (final t in [...BoardSpec.squareTiers(mode), ...BoardSpec.squareGiantTiers(mode)]) {
          final back = BoardSpec.fromCode(BoardCode.toPath(t.fullCode));
          expect(back, t);
          expect(back.tier, t.tier);
          expect(back.expand, isFalse, reason: t.fullCode);
          expect(BoardSpec.fromCode(t.fullCode, expand: true).expand, isTrue, reason: '?expand=1');
        }
      }
      // The guided start's first board, a code without a tier, is the square Cozy board.
      final first = BoardSpec.fromCode(BoardCode.fromPath('cards-3x3'));
      expect(first.tier, 0);
      expect(first.expand, isFalse);
      expect(first.fitTo(16 / 9), first, reason: 'nine cards whatever the picture');
      // A quest's "5x5 or bigger" shortcut opens Tricky; an old board link is an Expand board.
      expect(BoardSpec.fromCode('5x5').tierIndex, 4);
      expect(BoardSpec.fromCode('cards-3x4t1').expand, isTrue);
      expect(BoardSpec.fromCode('cards-4x4t1').expand, isTrue, reason: 'Easy has no square board: an old 4x4 Easy is an Expand board');
    });

    test('quests count a square board as its side squared', () {
      expect(BoardSpec.sizeCells(GameMode.triangles, 36), 16, reason: 'the 4x4 triangle board (36 pieces) is a 4x4');
      expect(BoardSpec.sizeCells(GameMode.triangles, 105), 49);
      expect(BoardSpec.sizeCells(GameMode.hexagons, 27), 25);
      expect(BoardSpec.sizeCells(GameMode.hexagons, 52), 49);
      expect(BoardSpec.sizeCells(GameMode.cards, 20), 20, reason: 'other boards count their pieces');
      PuzzleProgress row(String mode, int cells) => PuzzleProgress.fromRow('r', {'puzzleId': 'p', 'gridSize': cells, 'mode': mode, 'completed': true});
      expect(Goals.sizeOf(row('triangles', 36)), GridSpec.byCode('4x4')!.cells);
      expect(Goals.sizeOf(row('hexagons', 52)), greaterThanOrEqualTo(GridSpec.tiers.last.cells), reason: 'the 7x7 honeycomb is a Master board');
      expect(GridSpec.atLeast(20).code, '5x5', reason: 'an old "4x5 or bigger" quest opens 5x5');
      expect(GridSpec.atLeast(16).code, '4x4');
      expect(GridSpec.byCode('4x5')?.cells, 20, reason: 'quests made before square boards still read');
      expect(GridSpec.byCells(49)?.code, '7x7');
    });
  });

  group('Expand', () {
    test('offered where the square boards crop the picture, hidden where they suit it', () {
      expect(BoardSpec.offersExpand(GameMode.squares, 1.0), isFalse, reason: 'a square picture in Squares');
      expect(BoardSpec.offersExpand(GameMode.squares, 939 / 893), isFalse, reason: 'square enough');
      expect(BoardSpec.offersExpand(GameMode.squares, 3 / 4), isTrue);
      expect(BoardSpec.offersExpand(GameMode.squares, 3 / 2), isFalse, reason: 'landscape pictures stay on square boards either way');
      expect(BoardSpec.offersExpand(GameMode.cards, 3 / 4), isFalse, reason: 'a 3:4 picture suits 5:7 cards');
      expect(BoardSpec.offersExpand(GameMode.cards, 2 / 3), isFalse);
      expect(BoardSpec.offersExpand(GameMode.cards, 1.0), isTrue);
      expect(BoardSpec.offersExpand(GameMode.cards, 9 / 16), isTrue);
      expect(BoardSpec.offersExpand(GameMode.triangles, 3 / 4), isTrue);
      expect(BoardSpec.offersExpand(GameMode.triangles, 1.0), isFalse, reason: 'square triangle boards suit a square picture');
      expect(BoardSpec.offersExpand(GameMode.hexagons, 3 / 4), isTrue);
      expect(BoardSpec.offersExpand(GameMode.hexagons, 4 / 3), isFalse, reason: 'square honeycombs are wide');
      expect(BoardSpec.offersExpand(GameMode.cards, double.nan), isFalse);
    });

    test('the same sizes as the square ladder, growing, and showing more of the picture', () {
      for (final mode in GameMode.values) {
        final square = BoardSpec.squareTiers(mode);
        for (final a in aspects) {
          final expand = BoardSpec.expandTiers(mode, a);
          expect([for (final t in expand) t.tier], [for (final t in square) t.tier], reason: '${mode.code} on $a');
          expect([for (final t in expand) t.label], [for (final t in square) t.label]);
          for (var i = 0; i < expand.length; i++) {
            expect(expand[i].expand, isTrue);
            if (i > 0) expect(expand[i].cells, greaterThan(expand[i - 1].cells), reason: '${mode.code} on $a');
          }
          final ladder = BoardSpec.ladder(mode, a, giant: false, expand: true);
          if (BoardSpec.offersExpand(mode, a)) {
            expect(ladder, expand);
            final gain = [for (var i = 0; i < square.length; i++) square[i].tiling.fitFor(a).crop - expand[i].tiling.fitFor(a).crop];
            expect(gain.reduce((x, y) => x > y ? x : y), greaterThan(BoardSpec.expandMinGain));
          } else {
            expect(ladder, square, reason: '${mode.code} on $a: no Expand, square boards');
            expect(ladder.every((t) => t.expand), isTrue, reason: 'Expand stays chosen for the next picture');
          }
        }
      }
    });

    test('Expand on the difficulty screen is remembered with the board', () {
      const last = LastBoard(mode: 'squares', tier: 4, painting: false, expand: true);
      expect(LastBoard.fromJson(last.toJson()), last);
      expect(LastBoard.fromJson(const {'mode': 'cards', 'tier': 2})!.expand, isFalse, reason: 'off until turned on, and for boards remembered before');
    });
  });

  group('saves', () {
    /// A shuffled layout of [a] is never a layout of [b] (their pieces' shapes tell them apart).
    void apart(BoardSpec a, BoardSpec b, String why) {
      for (var seed = 0; seed < 4; seed++) {
        expect(Board.isValidLayout(b, Board.shuffled(a, seed: seed).slots), isFalse, reason: '$why: a ${a.fullCode} save would also fit ${b.fullCode}');
      }
    }

    test('a save resumes on exactly the board it was dealt on: square, Expand or old', () {
      for (final mode in GameMode.values) {
        final square = BoardSpec.squareTiers(mode);
        for (final a in aspects) {
          final all = [...square, ...BoardSpec.expandTiers(mode, a), ...BoardSpec.tiers(mode, a)];
          for (final b in all) {
            // Two boards of one picture with the same count (the 4x4 triangle board and an old
            // 6x6 strip, 36 each) are told apart by the saved layout.
            for (final other in all) {
              if (other.cells == b.cells && other != b) apart(b, other, '${mode.code} on $a');
            }
            final layout = Board.shuffled(b, seed: 1).slots;
            final back = BoardSpec.fromSaved(mode, b.cells, a, layout: layout);
            expect(back, b, reason: '${mode.code} ${b.code} (${b.cells}) on $a resumes as it was dealt');
            expect(back!.expand, b.expand && !square.contains(b), reason: '${mode.code} ${b.code} on $a');
          }
        }
      }
    });

    test('an older build reading a square board resumes that very board or starts fresh', () {
      // Older builds find a save's board by its piece count on the old ladder ([BoardSpec.tiers])
      // and start fresh when the saved layout does not fit it.
      for (final mode in GameMode.values) {
        for (final a in aspects) {
          final old = BoardSpec.tiers(mode, a);
          for (final t in [...BoardSpec.squareTiers(mode), ...BoardSpec.expandTiers(mode, a)]) {
            final hit = old.where((o) => o.cells == t.cells).firstOrNull;
            if (hit != null && hit != t) apart(t, hit, '${mode.code} ${t.size} on $a');
          }
        }
        for (final a in [BoardSpec.referenceAspect, ...BoardSpec.commonAspects]) {
          final old = BoardSpec.giantTiers(mode, a);
          for (final t in BoardSpec.squareGiantTiers(mode)) {
            final hit = old.where((o) => o.cells == t.cells).firstOrNull;
            if (hit != null && hit != t) apart(t, hit, '${mode.code} ${t.size} on $a');
          }
        }
      }
    });

    test('the 5x5 triangle board keeps one joined pair of halves on each side edge, and no card in place', () {
      final t = BoardSpec.squareTiers(GameMode.triangles).firstWhere((t) => t.size == '5x5');
      expect(t.tiling.unavoidableJoins, 2);
      for (var seed = 0; seed < 12; seed++) {
        final b = Board.shuffled(t, seed: seed);
        expect(b.lockedCount, 0);
        expect(b.joinCount, 2);
      }
    });

    test('a board saved by an older build (3x4 Cards) stays 3x4', () {
      const a = 9 / 16;
      final old = BoardSpec.tiers(GameMode.cards, a)[1];
      expect(old.code, '3x4');
      final back = BoardSpec.fromSaved(GameMode.cards, old.cells, a)!;
      expect(back.code, '3x4');
      expect(back.expand, isTrue, reason: 'treated as an Expand board');
      // Home's Continue, before the picture is in: a guess with the same piece count.
      expect(BoardSpec.fromCells(GameMode.cards, old.cells).cells, old.cells);
    });
  });
}
