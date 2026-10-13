import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform.dart';
import '../core/qa.dart';
import '../core/reminders.dart';
import '../models/models.dart';
import 'catalog.dart';
import 'profile.dart';
import 'progress.dart';
import 'rewards.dart';
import 'settings.dart';

/// Days ahead that get a reminder. A player away for a week hears nothing
/// more until they open the game again (each open plans the next week).
const reminderDays = 7;

/// One daily reminder: a local notification at the player's reminder time.
@immutable
class ReminderNote {
  const ReminderNote({required this.id, required this.at, required this.title, required this.body, required this.route});

  /// The day (`2026-10-14`); iOS keeps one reminder per id.
  final String id;
  final DateTime at;
  final String title;
  final String body;

  /// Where a tap goes: the day's daily puzzle, or Home.
  final String route;

  Map<String, Object?> toJson() => {'id': id, 'at': at.millisecondsSinceEpoch, 'title': title, 'body': body, 'route': route};

  @override
  String toString() => 'ReminderNote($id ${at.hour}:${at.minute.toString().padLeft(2, '0')} "$title" / "$body" -> $route)';
}

/// The reminders to schedule at [now]: one a day at [minutes] after local
/// midnight, for today and the next [days] - 1 days. Today is skipped once
/// the player has claimed today's daily gift or solved today's daily
/// puzzle, and any time already past is skipped. A reminder names the
/// day's daily puzzle when the catalogue has it, and asks to keep the
/// streak when that day's gift would continue a streak of 2 or more.
///
/// [puzzles] is the released catalogue (daily pictures carry a `date`).
List<ReminderNote> planReminders({
  required DateTime now,
  required int minutes,
  required Iterable<Puzzle> puzzles,
  required Profile? profile,
  required Map<String, PuzzleProgress> progress,
  int days = reminderDays,
}) {
  final last = profile?.lastDailyClaim?.toLocal();
  final claimedToday = last != null && Goals.sameDay(last, now);
  final claimedYesterday = last != null && Goals.sameDay(last, DateTime(now.year, now.month, now.day - 1));
  final streak = profile?.streak ?? 0;
  final byDay = {for (final p in puzzles) if (p.date != null) Goals.dayKey(p.date!): p};
  final notes = <ReminderNote>[];
  for (var d = 0; d < days; d++) {
    // Built from calendar fields, so a daylight saving change keeps the time.
    final at = DateTime(now.year, now.month, now.day + d, minutes ~/ 60, minutes % 60);
    if (!at.isAfter(now)) continue;
    final key = Goals.dayKey(at);
    final puzzle = byDay[key];
    if (d == 0 && (claimedToday || (puzzle != null && progress[puzzle.id]?.completed == true))) continue;
    // The gift on day d continues the streak only if the day before was
    // claimed: yesterday for today, today for tomorrow. Later days follow
    // a day without the game, so the streak is gone by then.
    final keepsStreak = streak >= 2 && ((d == 0 && claimedYesterday) || (d == 1 && claimedToday));
    final String title, body;
    if (keepsStreak) {
      title = 'Keep your $streak-day streak';
      body = puzzle != null ? "${puzzle.title} is today's daily puzzle, and your daily gift is waiting." : "Today's daily puzzle and your daily gift are waiting.";
    } else {
      title = "Today's daily puzzle";
      body = puzzle != null ? '${puzzle.title} is ready, and so is your daily gift.' : 'A new picture is ready, and so is your daily gift.';
    }
    notes.add(ReminderNote(id: key, at: at, title: title, body: body, route: puzzle != null ? '/play/${puzzle.id}' : '/home'));
  }
  return notes;
}

/// Keeps the pending reminders in line with the Settings switch, the iOS
/// permission and the player's day. [refresh] runs when the app starts,
/// comes back and goes to the background, so the week ahead is always
/// planned from the latest state (a claimed gift removes today's reminder).
class RemindersController {
  RemindersController(this._ref);
  final Ref _ref;

  Future<void> refresh() async {
    if (!supportsNotifications) return;
    final settings = _ref.read(settingsProvider);
    if (!settings.reminders) {
      await ReminderChannel.cancel();
      return;
    }
    if (await ReminderChannel.status() != ReminderPermission.granted) {
      // Turned off in iOS Settings: the switch follows.
      _ref.read(settingsProvider.notifier).setReminders(false);
      await ReminderChannel.cancel();
      return;
    }
    var puzzles = const <Puzzle>[];
    try {
      puzzles = await _ref.read(allPuzzlesProvider.future).timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('reminders: catalogue not ready ($e)');
    }
    final notes = planReminders(
      now: DateTime.now(),
      minutes: _ref.read(settingsProvider).reminderMinutes,
      puzzles: puzzles,
      profile: _ref.read(profileProvider).value,
      progress: _ref.read(progressProvider).value ?? const {},
    );
    await ReminderChannel.schedule([for (final n in notes) n.toJson()]);
  }

  /// Turns reminders on, asking iOS the first time. False when iOS does not
  /// allow notifications (the switch stays off).
  Future<bool> enable() async {
    final granted = await ReminderChannel.request(quiet: QaRun.enabled && QaRun.integrationRun);
    _ref.read(settingsProvider.notifier).setReminders(granted);
    if (granted) await refresh();
    return granted;
  }

  Future<void> disable() async {
    _ref.read(settingsProvider.notifier).setReminders(false);
    await ReminderChannel.cancel();
  }

  Future<void> setTime(int minutes) async {
    _ref.read(settingsProvider.notifier).setReminderMinutes(minutes);
    await refresh();
  }
}

final remindersProvider = Provider<RemindersController>((ref) => RemindersController(ref));
