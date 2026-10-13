import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/reminders.dart';
import 'package:flutter_test/flutter_test.dart';

/// 13 October 2026, 09:00 local; the reminder time is 19:00.
final _now = DateTime(2026, 10, 13, 9);
const _seven = 19 * 60;

List<Puzzle> _month() => [
      for (var d = 1; d <= 31; d++)
        Puzzle.fromRow('daily-$d', {'packId': 'daily-2026-10', 'title': 'Picture $d', 'date': '2026-10-${d.toString().padLeft(2, '0')}'}),
    ];

Profile _profile({int streak = 0, DateTime? lastClaim}) =>
    Profile.fromRow('u', {'userId': 'u', 'streak': streak, 'lastDailyClaim': ?lastClaim?.toIso8601String()});

PuzzleProgress _solved(String id) => PuzzleProgress.fromRow('row-$id', {'userId': 'u', 'puzzleId': id, 'gridSize': 16, 'mode': 'cards', 'completed': true, 'stars': 3});

void main() {
  final month = _month();

  test('one reminder a day for a week at the chosen time, naming the daily puzzle', () {
    final notes = planReminders(now: _now, minutes: _seven, puzzles: month, profile: _profile(), progress: const {});
    expect(notes, hasLength(reminderDays));
    expect([for (final n in notes) n.id], ['2026-10-13', '2026-10-14', '2026-10-15', '2026-10-16', '2026-10-17', '2026-10-18', '2026-10-19']);
    for (final n in notes) {
      expect((n.at.hour, n.at.minute), (19, 0));
    }
    expect(notes.first.title, "Today's daily puzzle");
    expect(notes.first.body, 'Picture 13 is ready, and so is your daily gift.');
    expect(notes.first.route, '/play/daily-13');
  });

  test('no reminder today once the daily gift is claimed or the daily puzzle is solved', () {
    final claimed = planReminders(now: _now, minutes: _seven, puzzles: month, profile: _profile(streak: 1, lastClaim: DateTime(2026, 10, 13, 8)), progress: const {});
    expect(claimed.first.id, '2026-10-14');
    final solved = planReminders(now: _now, minutes: _seven, puzzles: month, profile: _profile(), progress: {'daily-13': _solved('daily-13')});
    expect(solved.first.id, '2026-10-14');
  });

  test('a time already past today starts tomorrow', () {
    final notes = planReminders(now: DateTime(2026, 10, 13, 20), minutes: _seven, puzzles: month, profile: _profile(), progress: const {});
    expect(notes.first.id, '2026-10-14');
    expect(notes, hasLength(reminderDays - 1));
  });

  test('asks to keep a streak only on the day the gift would continue it', () {
    // Claimed yesterday: today's gift continues the 4-day streak.
    final open = planReminders(now: _now, minutes: _seven, puzzles: month, profile: _profile(streak: 4, lastClaim: DateTime(2026, 10, 12, 18)), progress: const {});
    expect(open[0].title, 'Keep your 4-day streak');
    expect(open[0].body, "Picture 13 is today's daily puzzle, and your daily gift is waiting.");
    expect(open[1].title, "Today's daily puzzle");
    // Claimed today: tomorrow's gift continues it, today has no reminder.
    final today = planReminders(now: _now, minutes: _seven, puzzles: month, profile: _profile(streak: 5, lastClaim: DateTime(2026, 10, 13, 8)), progress: const {});
    expect(today[0].id, '2026-10-14');
    expect(today[0].title, 'Keep your 5-day streak');
    expect(today[1].title, "Today's daily puzzle");
    // A 1-day streak is not worth a streak reminder.
    final one = planReminders(now: _now, minutes: _seven, puzzles: month, profile: _profile(streak: 1, lastClaim: DateTime(2026, 10, 12, 18)), progress: const {});
    expect(one[0].title, "Today's daily puzzle");
  });

  test('days without a daily puzzle in the catalogue open Home', () {
    // 28 October: the November pack is not released yet, so its days are unknown.
    final notes = planReminders(now: DateTime(2026, 10, 28, 9), minutes: _seven, puzzles: month, profile: _profile(), progress: const {});
    final november = notes.where((n) => n.id.startsWith('2026-11')).toList();
    expect(november, isNotEmpty);
    for (final n in november) {
      expect(n.body, 'A new picture is ready, and so is your daily gift.');
      expect(n.route, '/home');
    }
  });

  test('the time survives a daylight saving change', () {
    // Europe moves the clocks back on 25 October 2026; the time stays 19:00.
    final notes = planReminders(now: DateTime(2026, 10, 22, 9), minutes: 19 * 60 + 30, puzzles: month, profile: _profile(), progress: const {});
    for (final n in notes) {
      expect((n.at.hour, n.at.minute), (19, 30));
    }
  });

  test('JSON carries what the native side reads', () {
    final n = planReminders(now: _now, minutes: _seven, puzzles: month, profile: _profile(), progress: const {}).first;
    expect(n.toJson(), {'id': '2026-10-13', 'at': DateTime(2026, 10, 13, 19).millisecondsSinceEpoch, 'title': n.title, 'body': n.body, 'route': '/play/daily-13'});
  });
}
