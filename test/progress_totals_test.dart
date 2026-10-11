import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/progress.dart';
import 'package:flutter_test/flutter_test.dart';

PuzzleProgress row(Map<String, dynamic> d) => PuzzleProgress.fromRow('r', {'userId': 'u', 'puzzleId': 'p', ...d});

void main() {
  test('first save seeds the totals', () {
    final t = ProgressNotifier.sessionTotals(null, {'moves': 5, 'elapsedSeconds': 30, 'hintsUsed': 1});
    expect(t, {'totalMoves': 5, 'totalSeconds': 30, 'totalHints': 1});
  });

  test('a continuing session replaces the running part', () {
    final existing = row({'moves': 5, 'elapsedSeconds': 30, 'hintsUsed': 1, 'totalMoves': 25, 'totalSeconds': 130, 'totalHints': 3});
    final t = ProgressNotifier.sessionTotals(existing, {'moves': 9, 'elapsedSeconds': 50, 'hintsUsed': 2});
    expect(t, {'totalMoves': 29, 'totalSeconds': 150, 'totalHints': 4});
  });

  test('a replay after a win adds on top', () {
    final existing = row({'moves': 20, 'elapsedSeconds': 100, 'hintsUsed': 2, 'completed': true, 'totalMoves': 20, 'totalSeconds': 100, 'totalHints': 2});
    final t = ProgressNotifier.sessionTotals(existing, {'moves': 3, 'elapsedSeconds': 4, 'hintsUsed': 0, 'completed': false});
    expect(t, {'totalMoves': 23, 'totalSeconds': 104, 'totalHints': 2});
  });

  test('a restart (counters drop) starts a new session', () {
    final existing = row({'moves': 12, 'elapsedSeconds': 60, 'hintsUsed': 0, 'totalMoves': 12, 'totalSeconds': 60, 'totalHints': 0});
    final t = ProgressNotifier.sessionTotals(existing, {'moves': 1, 'elapsedSeconds': 2, 'hintsUsed': 0});
    expect(t, {'totalMoves': 13, 'totalSeconds': 62, 'totalHints': 0});
  });

  test('rows from older clients fall back to the last session', () {
    final old = row({'moves': 7, 'elapsedSeconds': 40, 'hintsUsed': 1});
    expect(old.totalMoves, 7);
    expect(old.totalSeconds, 40);
    expect(old.totalHints, 1);
  });
}
