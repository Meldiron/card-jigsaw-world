// Achievements count each finished board as it was finished (2026-10-17): a replay of a solved
// picture in another shape or size (saved, discarded or finished) never moves an achievement back,
// rows from older builds read through the same fallbacks as the quests, and a claimed step stays
// claimed.
import 'package:carden/data/sync/changes.dart';
import 'package:carden/data/sync/ops.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/achievements.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _apply(Map<String, dynamic> row, SyncOp op) => applyChanges(row, op.build(row).changes);

SyncOp _win(String puzzle, DateTime at, {String mode = 'cards', int cells = 16, int seconds = 600, int hints = 0, int stars = 3, String session = 's1'}) =>
    SyncOp.win(puzzleId: puzzle, gridSize: cells, mode: mode, moves: 30, seconds: seconds, hints: hints, stars: stars, session: session, resumed: false, at: at);

SyncOp _board(String puzzle, {String mode = 'hexagons', int cells = 52, int hints = 3, String session = 's2'}) =>
    SyncOp.board(puzzleId: puzzle, gridSize: cells, mode: mode, layout: '1,0,2,3', moves: 2, seconds: 400, hints: hints, session: session, resumed: false);

PuzzleProgress _read(String puzzle, Map<String, dynamic> row) => PuzzleProgress.fromRow('row-$puzzle', {'userId': 'u', 'puzzleId': puzzle, ...row});

/// Every family's progress for [rows], nothing claimed.
Map<String, int> _progress(Iterable<PuzzleProgress> rows, {DateTime? since}) {
  final facts = AchievementFacts(Profile.guest('u'), [for (final p in rows) if (p.completed) p], 0, since: since);
  return {for (final f in achievementFamilies) f.id: achievementStatus(f, facts, const []).progress};
}

void main() {
  // Finished at 23:00 (night owl), quickly and without hints, on Cards 6x6 (36 cards, a big board).
  final night = DateTime(2026, 10, 16, 23);
  final now = DateTime(2026, 10, 17, 15);

  // Ten pictures like that, so the counts are not zero.
  Map<String, Map<String, dynamic>> solved() => {
        for (var i = 0; i < 10; i++) 'p$i': _apply(const {}, _win('p$i', night.add(Duration(minutes: i)), cells: 36, seconds: 100)),
      };
  List<PuzzleProgress> rows(Map<String, Map<String, dynamic>> m) => [for (final e in m.entries) _read(e.key, e.value)];

  test('a replay in progress in another shape and size changes no achievement', () {
    final rowsBefore = solved();
    final before = _progress(rows(rowsBefore));
    expect(before['cards'], 10);
    expect(before['big'], 10);
    expect(before['speed'], 10);
    expect(before['nohints'], 10);
    expect(before['nightowl'], 10);
    // Three pictures replayed on Hexagons 7x7 with hints, saved a few moves in.
    final replayed = {...rowsBefore, for (final id in ['p0', 'p1', 'p2']) id: _apply(rowsBefore[id]!, _board(id))};
    expect(_read('p0', replayed['p0']!).mode, 'hexagons', reason: 'the board fields are the replay\'s');
    expect(_progress(rows(replayed)), before);
    // Discarded again: still the same.
    final discarded = {...replayed, for (final id in ['p0', 'p1', 'p2']) id: _apply(replayed[id]!, SyncOp.discard(id))};
    expect(_progress(rows(discarded)), before);
  });

  test('a replay finished in another shape and size adds to its families and takes from none', () {
    final rowsBefore = solved();
    final before = _progress(rows(rowsBefore));
    // p0 replayed on Squares 3x3 at 15:00, slowly, with hints.
    final after = {...rowsBefore, 'p0': _apply(_apply(rowsBefore['p0']!, _board('p0', mode: 'squares', cells: 9)), _win('p0', now, mode: 'squares', cells: 9, seconds: 900, hints: 2, session: 's2'))};
    final progress = _progress(rows(after));
    for (final id in before.keys) {
      expect(progress[id], greaterThanOrEqualTo(before[id]!), reason: '$id never goes back');
    }
    expect(progress['squares'], before['squares']! + 1);
    expect(progress['cards'], before['cards'], reason: 'p0 was finished on Cards too');
    expect(progress['allmodes'], 2);
  });

  test('the boards achievements count stay in the log, however many replays follow', () {
    // A picture finished on Hexagons 7x7 at night, then replayed on Cards 3x3 every day for a month.
    var row = _apply(const {}, _win('p', DateTime(2026, 9, 1, 23), mode: 'hexagons', cells: 52, seconds: 100));
    for (var d = 0; d < 30; d++) {
      row = _apply(_apply(row, _board('p', mode: 'cards', cells: 9)), _win('p', DateTime(2026, 9, 2 + d, 14), cells: 9, seconds: 900, hints: 1, session: 'd$d'));
    }
    final p = _read('p', row);
    expect(p.finishes.length, lessThanOrEqualTo(BoardFinish.maxEntries));
    final progress = _progress([p]);
    expect(progress['hexagons'], 1, reason: 'the Hexagons board of September 1st');
    expect(progress['master'], 1, reason: 'the biggest board');
    expect(progress['speed'], 1, reason: 'the quick board');
    expect(progress['nightowl'], 1, reason: 'the board finished at night');
    expect(progress['nohints'], 1, reason: 'the board without hints');
    expect(progress['cards'], 1);
  });

  test('rows from older builds read as before, and a board saved over them keeps their finish', () {
    final old = <String, dynamic>{
      'completed': true, 'completedAt': night.toUtc().toIso8601String(), 'mode': 'triangles', 'gridSize': 36, 'moves': 40,
      'elapsedSeconds': 100, 'hintsUsed': 0, 'stars': 3, 'layout': '', 'session': 'old',
    };
    final before = _progress([_read('p', old)]);
    expect((before['triangles'], before['big'], before['speed'], before['nohints'], before['nightowl']), (1, 1, 1, 1, 1));
    // This build saving a replay records the finish first: nothing moves.
    expect(_progress([_read('p', _apply(old, _board('p')))]), before);
    // An older build saving a replay over it loses the values; the solve and its hour still count.
    final lost = _progress([_read('p', {...old, 'mode': 'cards', 'gridSize': 9, 'layout': '1,0', 'hintsUsed': 4, 'elapsedSeconds': 3})]);
    expect((lost['solver'], lost['nightowl'], lost['cards'], lost['triangles']), (1, 1, 0, 0));
  });

  test('a claimed step stays claimed and its count never shows below it', () {
    final facts = AchievementFacts(Profile.guest('u'), const [], 0);
    final cards = achievementFamilies.firstWhere((f) => f.id == 'cards');
    final status = achievementStatus(cards, facts, const ['cards:1']);
    expect(status.claimedSteps, 1);
    expect(status.stepIndex, 1, reason: 'the next step is offered, the first is not taken back');
    expect(status.progress, cards.steps.first.threshold, reason: 'no fewer than the step claimed');
    expect(status.done, isFalse);
  });

  test('the guided start counts only boards finished after achievements opened', () {
    final row = _apply(_apply(const {}, _win('p', DateTime(2026, 10, 17, 9), mode: 'hexagons', cells: 27)), _win('p', DateTime(2026, 10, 17, 12), mode: 'squares', session: 's2'));
    final progress = _progress([_read('p', row)], since: DateTime(2026, 10, 17, 10));
    expect((progress['hexagons'], progress['squares']), (0, 1));
  });
}
