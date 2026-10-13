import 'dart:math';

import 'package:card_jigsaw_world/data/sync/changes.dart';
import 'package:card_jigsaw_world/data/sync/ops.dart';
import 'package:card_jigsaw_world/game/board.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/giant.dart';
import 'package:card_jigsaw_world/state/merge.dart';
import 'package:card_jigsaw_world/state/profile.dart';
import 'package:card_jigsaw_world/state/quick_play.dart';
import 'package:flutter_test/flutter_test.dart';

/// The value an op writes to [key] of a progress row.
dynamic _written(SyncOp op, String key, [Map<String, dynamic> row = const {}]) => (op.build(row).changes[key] as Put).value;

SyncOp _board({bool? painting}) => painting == null
    ? SyncOp.board(puzzleId: 'p', gridSize: 16, mode: 'cards', layout: '1,0', moves: 3, seconds: 9, hints: 0, session: 's', resumed: false)
    : SyncOp.board(puzzleId: 'p', gridSize: 16, mode: 'cards', layout: '1,0', moves: 3, seconds: 9, hints: 0, session: 's', resumed: false, painting: painting);

void main() {
  group('Painting rewards', () {
    test('pays x1.25 coins and XP on top of the mode', () {
      for (final mode in GameMode.values) {
        for (final stars in [1, 2, 3]) {
          final plain = Economy.completionCoins(36, stars, mode: mode);
          final painted = Economy.completionCoins(36, stars, mode: mode, painting: true);
          expect(painted, closeTo(plain * Economy.paintingMultiplier, 1.0), reason: '$mode $stars');
          final xp = Economy.completionXp(36, stars, mode: mode);
          expect(Economy.completionXp(36, stars, mode: mode, painting: true), closeTo(xp * Economy.paintingMultiplier, 1.0));
        }
      }
      expect(Economy.paintingMultiplier, 1.25);
      // Off by default: every existing caller pays as before.
      expect(Economy.completionCoins(16, 3), Economy.completionCoins(16, 3, painting: false));
    });
  });

  group('Painting is saved with the board', () {
    test('board and win ops write the flag; ops queued before Painting write a plain board', () {
      expect(_written(_board(painting: true), 'painting'), isTrue);
      expect(_written(_board(painting: false), 'painting'), isFalse);
      // An op stored by an older build has no flag at all.
      final legacy = SyncOp.fromJson({..._board(painting: true).toJson(), 'args': {..._board().args}..remove('painting')});
      expect(_written(legacy, 'painting', {'painting': true}), isFalse);
      final win = SyncOp.win(puzzleId: 'p', gridSize: 16, mode: 'cards', moves: 3, seconds: 9, hints: 0, stars: 3, session: 's', resumed: false, painting: true);
      expect(_written(win, 'painting'), isTrue);
      // The flag survives the op queue (stored as JSON on the device).
      expect(SyncOp.fromJson(_board(painting: true).toJson()).args['painting'], isTrue);
    });

    test('progress rows read and write it; rows from before read as a plain board', () {
      final row = PuzzleProgress.fromRow('r', {'puzzleId': 'p', 'gridSize': 16, 'mode': 'cards', 'layout': '1,0', 'painting': true});
      expect(row.painting, isTrue);
      expect(PuzzleProgress.fromRow('r', row.toData()).painting, isTrue);
      expect(PuzzleProgress.fromRow('r', {'puzzleId': 'p', 'gridSize': 16, 'layout': '1,0'}).painting, isFalse);
    });

    test('a sign-in merge keeps the flag of the board it keeps', () {
      final older = {'puzzleId': 'p', 'layout': '1,0', 'painting': true, r'$updatedAt': '2026-10-01T10:00:00Z'};
      final newer = {'puzzleId': 'p', 'layout': '0,1', r'$updatedAt': '2026-10-02T10:00:00Z'};
      expect(mergeProgressRow(older, newer)['painting'], isFalse);
      expect(mergeProgressRow({...newer, 'painting': true}, older)['painting'], isTrue);
    });
  });

  group('Giant pack', () {
    Pack pack(String id, String category) => Pack.fromRow(id, {'name': id, 'category': category});

    test('is recognised by its category', () {
      expect(isGiantPack(pack('g', 'Giant')), isTrue);
      expect(isGiantPack(pack('g', 'giant')), isTrue);
      expect(isGiantPack(pack('n', 'Nature')), isFalse);
    });

    test('Quick play never deals a giant board for a normal picture', () {
      // The home card only preselects a last board the player may play; giant tiers are
      // above every level, so a giant last board is never carried to a normal picture.
      final giantBoard = BoardSpec.giantTiers(GameMode.cards).first;
      expect(giantBoard.tierIndex, greaterThan(7));
      final z = Puzzle.fromRow('p1', {'packId': 'n', 'title': 'P'});
      final route = Uri.parse(quickPlayRoute(z, board: BoardSpec.tiers(GameMode.cards)[2]));
      expect(BoardSpec.fromCode(route.queryParameters['grid']!).isGiant, isFalse);
      // The pool the home card draws from leaves Giant packs out (see quickPlayPoolProvider);
      // the pure pool function itself only sees the packs it is given.
      final pool = quickPlayPool(
        packs: [pack('n', 'Nature')],
        puzzles: [z, Puzzle.fromRow('g1', {'packId': 'g', 'title': 'G'})],
        progress: const {},
        isUnlocked: (_) => true,
        now: DateTime(2026, 10, 14),
      );
      expect(pool!.puzzles.map((p) => p.id), ['p1']);
      expect(pickQuickPlay(pool, Random(1))!.id, 'p1');
    });
  });
}
