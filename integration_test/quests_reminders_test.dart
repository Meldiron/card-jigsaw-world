// TestFlight round of 2026-10-13: Quick play opens the mode and board
// picker, the Quests tab shows a dot while a reward waits, the Social tab is
// a plain leaderboard, and Settings > Daily reminders schedules real local
// notifications. Drives the real app (live Appwrite backend).
//
// Run: tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//        --target=integration_test/quests_reminders_test.dart -d <simulator>
//
// The host takes part in two steps, keyed on lines this test prints:
//   QA_MARK:background:<epoch s>  send the app to the background (open the
//       Settings app) and bring it back after that time: the reminder must
//       fire while the game is not in front.
//   QA_MARK:prompt                take a simulator screenshot: the iOS
//       permission prompt is up (nothing here can tap it).
// Integration runs ask iOS for quiet (provisional) permission, which needs
// no prompt; the last step shows the real prompt.
import 'dart:async';

import 'package:card_jigsaw_world/app.dart';
import 'package:card_jigsaw_world/core/reminders.dart';
import 'package:card_jigsaw_world/core/sfx.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/features/events/events_screen.dart';
import 'package:card_jigsaw_world/features/events/quest_rewards.dart';
import 'package:card_jigsaw_world/features/game/board_widget.dart';
import 'package:card_jigsaw_world/features/game/difficulty_screen.dart';
import 'package:card_jigsaw_world/state/reminders.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
  // The app has infinite animations (shimmer, pulses), so pump for a fixed time.
  await tester.pump(const Duration(milliseconds: 50));
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, 400);
    await binding.takeScreenshot(name);
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(CardJigsawApp)));

  /// Sends every misplaced card home, one tap-tap move at a time.
  Future<void> solveBoard(WidgetTester tester) async {
    for (var guard = 0; guard < 80; guard++) {
      final bf = find.byType(BoardWidget);
      if (bf.evaluate().isEmpty) return;
      final board = tester.widget<BoardWidget>(bf.first).state.board;
      if (board.isSolved) return;
      final rect = tester.getRect(bf.first);
      Offset center(int slot) => rect.topLeft + board.tiling.cellCenter(slot, rect.size);
      final slot = List.generate(board.cells, (i) => i).firstWhere((i) => !board.isLocked(i));
      await tester.tapAt(center(slot));
      await settle(tester, 250);
      await tester.tapAt(center(board.homeOf(slot)));
      await settle(tester, 450);
    }
  }

  /// Home > Quick play > difficulty screen > Play > solved > back to Home.
  Future<void> quickPlay(WidgetTester tester, {required String shotName, bool pickCozy = false}) async {
    await tester.tap(find.byKey(const ValueKey('home-quick-play')), warnIfMissed: false);
    await settle(tester, 4000);
    expect(find.byType(DifficultyScreen), findsOneWidget, reason: 'Quick play opens the mode and board picker');
    expect(find.text('Choose a mode'), findsOneWidget);
    if (pickCozy) {
      await tester.dragUntilVisible(find.text('Cozy'), find.byType(Scrollable).first, const Offset(0, -200));
      await settle(tester, 600);
      await tapText(tester, 'Cozy');
    } else {
      await tester.dragUntilVisible(find.text('Cozy'), find.byType(Scrollable).first, const Offset(0, -200));
      await settle(tester, 600);
    }
    await shot(tester, shotName);
    await tester.tap(find.textContaining('· Play'), warnIfMissed: false);
    await settle(tester, 6000);
    if (find.text('Got it').evaluate().isNotEmpty) await tapText(tester, 'Got it');
    await solveBoard(tester);
    await settle(tester, 3000);
    expect(find.text('Picture complete'), findsOneWidget);
    await tapText(tester, 'Back to pack', ms: 2500);
    await tapText(tester, 'Home', ms: 2500);
  }

  testWidgets('quick play, quests dot, leaderboard, daily reminders', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const CardJigsawApp(),
    ));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 5000);
    await shot(tester, 'qr_01_home');

    // Quick play opens the picker; the first time nothing is preselected.
    await quickPlay(tester, shotName: 'qr_02_quick_play_first', pickCozy: true);
    // The second time the last board (Cards, Cozy) is preselected.
    await quickPlay(tester, shotName: 'qr_03_quick_play_preselected');

    // Two 3-star boards finish "Earn 3 stars twice"; play on until a quest is ready.
    for (var i = 0; i < 3 && !container(tester).read(questRewardReadyProvider); i++) {
      await quickPlay(tester, shotName: 'qr_03b_quick_play_more_$i');
    }
    expect(container(tester).read(questRewardReadyProvider), isTrue, reason: 'a finished quest lights the Quests dot');
    await shot(tester, 'qr_04_home_quests_dot');

    await tapText(tester, 'Quests', ms: 3000);
    await shot(tester, 'qr_05_quests_ready');
    final claims = find.descendant(of: find.byType(EventsScreen), matching: find.text('Claim'));
    for (var guard = 0; guard < 8 && claims.evaluate().isNotEmpty; guard++) {
      await tester.ensureVisible(claims.first);
      await settle(tester, 400);
      await tester.tap(claims.first, warnIfMissed: false);
      await settle(tester, 1800);
    }
    expect(container(tester).read(questRewardReadyProvider), isFalse, reason: 'claiming every reward clears the dot');
    await tester.fling(find.byType(CustomScrollView).last, const Offset(0, 3000), 3000);
    await settle(tester, 1200);
    await shot(tester, 'qr_06_quests_claimed');

    // Social: a plain leaderboard, no league or season.
    await tapText(tester, 'Social', ms: 3500);
    expect(find.text('Leaderboard'), findsWidgets);
    expect(find.text('Crystal League'), findsNothing);
    expect(find.textContaining('season'), findsNothing);
    await shot(tester, 'qr_07_leaderboard');

    // Settings > Daily reminders.
    await tapText(tester, 'Profile', ms: 2500);
    await tester.tap(find.byIcon(CupertinoIcons.gear_alt_fill).first, warnIfMissed: false);
    await settle(tester, 1500);
    expect(container(tester).read(settingsProvider).reminders, isFalse, reason: 'reminders start off');
    expect(find.text('Reminder time'), findsNothing);
    await shot(tester, 'qr_08_settings_reminders_off');
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('settings-reminders')), matching: find.byType(CupertinoSwitch)), warnIfMissed: false);
    await settle(tester, 3000);
    expect(container(tester).read(settingsProvider).reminders, isTrue);
    expect(await ReminderChannel.status(), ReminderPermission.granted);
    await shot(tester, 'qr_09_settings_reminders_on');
    final week = await ReminderChannel.pending();
    for (final n in week) {
      debugPrint('QA_PENDING $n');
    }
    // A week ahead; today drops out once 19:00 has passed.
    expect(week.length, inInclusiveRange(reminderDays - 1, reminderDays));
    expect(week.every((n) => DateTime.fromMillisecondsSinceEpoch((n['at'] as num).toInt()).hour == 19), isTrue);

    await tapText(tester, 'Reminder time', ms: 1500);
    await shot(tester, 'qr_10_reminder_time_sheet');
    await tapText(tester, 'Set time', ms: 1500);

    // A reminder two minutes from now (the time sheet's own save path), and
    // the game in the background when it fires.
    final now = DateTime.now();
    final fire = DateTime(now.year, now.month, now.day, now.hour, now.minute + 2);
    await container(tester).read(remindersProvider).setTime(fire.hour * 60 + fire.minute);
    await settle(tester, 1500);
    await shot(tester, 'qr_11_settings_time_changed');
    final soon = await ReminderChannel.pending();
    debugPrint('QA_PENDING_SOON ${soon.first}');
    expect(soon.any((n) => (n['at'] as num).toInt() == fire.millisecondsSinceEpoch), isTrue, reason: 'next reminder at ${fire.toIso8601String()}');
    debugPrint('QA_MARK:background:${fire.millisecondsSinceEpoch ~/ 1000}');
    // Pumping stops while the app is in the background and resumes when the host brings it back.
    while (DateTime.now().isBefore(fire.add(const Duration(seconds: 25)))) {
      await settle(tester, 1000);
    }
    await settle(tester, 2500);
    final delivered = await ReminderChannel.delivered();
    debugPrint('QA_DELIVERED $delivered');
    expect(delivered, isNotEmpty, reason: 'the reminder fired');
    expect(delivered.first['title'], anyOf("Today's daily puzzle", startsWith('Keep your')));
    expect(delivered.first['route'], startsWith('/'));
    await shot(tester, 'qr_12_back_after_reminder');

    // The real permission prompt (quiet permission can be raised to full).
    unawaited(ReminderChannel.request());
    debugPrint('QA_MARK:prompt');
    await settle(tester, 15000);
  });
}
