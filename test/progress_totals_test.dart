import 'package:carden/data/sync/changes.dart';
import 'package:carden/data/sync/ops.dart';
import 'package:carden/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

PuzzleProgress row(Map<String, dynamic> d) => PuzzleProgress.fromRow('r', {'userId': 'u', 'puzzleId': 'p', ...d});

SyncOp board({required int moves, required int seconds, int hints = 0, String session = 's1', bool resumed = false}) => SyncOp.board(
      puzzleId: 'p',
      gridSize: 16,
      mode: 'cards',
      layout: '1,0,2,3',
      moves: moves,
      seconds: seconds,
      hints: hints,
      session: session,
      resumed: resumed,
    );

Map<String, dynamic> totals(SyncOp op, Map<String, dynamic> row) {
  final out = applyChanges(row, op.build(row).changes);
  return {'totalMoves': out['totalMoves'], 'totalSeconds': out['totalSeconds'], 'totalHints': out['totalHints']};
}

void main() {
  test('first save seeds the totals', () {
    expect(totals(board(moves: 5, seconds: 30, hints: 1), {}), {'totalMoves': 5, 'totalSeconds': 30, 'totalHints': 1});
  });

  test('a continuing play-through replaces its earlier numbers', () {
    final saved = {'moves': 5, 'elapsedSeconds': 30, 'hintsUsed': 1, 'totalMoves': 25, 'totalSeconds': 130, 'totalHints': 3, 'session': 's1', 'layout': '0,1'};
    expect(totals(board(moves: 9, seconds: 50, hints: 2), saved), {'totalMoves': 29, 'totalSeconds': 150, 'totalHints': 4});
  });

  test('sending the same save twice gives the same totals', () {
    final op = board(moves: 9, seconds: 50);
    final once = applyChanges({'moves': 5, 'elapsedSeconds': 30, 'totalMoves': 25, 'totalSeconds': 130, 'session': 's1', 'layout': '0,1'}, op.build({'moves': 5, 'elapsedSeconds': 30, 'totalMoves': 25, 'totalSeconds': 130, 'session': 's1', 'layout': '0,1'}).changes);
    final twice = applyChanges(once, op.build(once).changes);
    expect(twice['totalMoves'], once['totalMoves']);
    expect(twice['totalSeconds'], once['totalSeconds']);
  });

  test('a replay after a win adds on top', () {
    final won = {'moves': 20, 'elapsedSeconds': 100, 'hintsUsed': 2, 'completed': true, 'totalMoves': 20, 'totalSeconds': 100, 'totalHints': 2, 'session': 's1', 'layout': ''};
    expect(totals(board(moves: 3, seconds: 4, session: 's2'), won), {'totalMoves': 23, 'totalSeconds': 104, 'totalHints': 2});
  });

  test('a restart is a new play-through', () {
    final saved = {'moves': 12, 'elapsedSeconds': 60, 'totalMoves': 12, 'totalSeconds': 60, 'session': 's1', 'layout': '0,1'};
    expect(totals(board(moves: 1, seconds: 2, session: 's2'), saved), {'totalMoves': 13, 'totalSeconds': 62, 'totalHints': 0});
  });

  test('a board saved by an older version continues when resumed', () {
    final legacy = {'moves': 7, 'elapsedSeconds': 40, 'hintsUsed': 1, 'layout': '0,1,2,3'};
    expect(totals(board(moves: 10, seconds: 55, hints: 1, resumed: true), legacy), {'totalMoves': 10, 'totalSeconds': 55, 'totalHints': 1});
    expect(totals(board(moves: 10, seconds: 55, hints: 1), legacy), {'totalMoves': 17, 'totalSeconds': 95, 'totalHints': 2});
  });

  test('rows from older clients fall back to the last session', () {
    final old = row({'moves': 7, 'elapsedSeconds': 40, 'hintsUsed': 1});
    expect(old.totalMoves, 7);
    expect(old.totalSeconds, 40);
    expect(old.totalHints, 1);
  });

  test('a solved picture stays solved, also on rows an older version un-solved during a replay', () {
    final replayed = row({'completed': false, 'stars': 2, 'completedAt': '2026-10-01T10:00:00.000Z', 'layout': '0,1,2,3'});
    expect(replayed.completed, isTrue);
    expect(replayed.inProgress, isTrue, reason: 'a replay in progress resumes');
    final saved = applyChanges({'completed': true, 'stars': 3, 'layout': ''}, board(moves: 2, seconds: 3).build({}).changes);
    expect(saved['completed'], isTrue, reason: 'board saves never touch the solved flag');
  });
}
