// TestFlight feedback of 2026-10-17 on the Quests tab, on the real app (live Appwrite backend, a QA
// guest): every quest not finished or claimed can be swapped (the timed one had no Swap), a swap is a
// swipe to the left with the confirmation after it (not a button), and the timed quests ask for a
// time a player can beat ("Solve a 3x3 board in under 4 seconds" came from boards finished in a few
// seconds with help).
//
// Run: tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//        --target=integration_test/quest_swipe_test.dart -d <simulator>
import 'package:carden/app.dart';
import 'package:carden/core/appwrite.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/data/sync/ops.dart';
import 'package:carden/models/models.dart';
import 'package:carden/router.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/progress.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

  Future<void> shot(WidgetTester tester, String name, {int wait = 400}) async {
    if (wait > 0) await settle(tester, wait);
    await binding.takeScreenshot(name);
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(CardenApp)));

  Future<Map<String, dynamic>> serverRow(WidgetTester tester) async {
    for (var i = 0; i < 30 && container(tester).read(syncProvider.notifier).debugOps.isNotEmpty; i++) {
      await settle(tester, 500);
    }
    final userId = (await container(tester).read(authProvider.future))!.$id;
    final row = await container(tester).read(tablesProvider).getRow(databaseId: AppwriteConfig.databaseId, tableId: AppwriteConfig.profiles, rowId: userId);
    return row.data;
  }

  /// A quest row as the swipe finds it: `quest-swap-<slot>`.
  Finder row(String slot) => find.byKey(ValueKey('quest-swap-$slot'));

  /// Swipes [slot]'s row to the left; with [partway] it stops short, shows the action and lets go.
  Future<void> swipe(WidgetTester tester, String slot, {String? partway}) async {
    final f = row(slot);
    await Scrollable.ensureVisible(tester.element(f), alignment: 0.4);
    await settle(tester, 600);
    final g = await tester.startGesture(tester.getCenter(f));
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    if (partway != null) {
      await shot(tester, partway, wait: 200);
      await g.moveBy(const Offset(110, 0));
      await g.up();
      await settle(tester, 1000);
      return;
    }
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(-25, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await settle(tester, 1500);
  }

  testWidgets('quests swipe to swap, every one still to do, timed ones a player can beat', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await FirstSteps.skipFor(store); // the whole app; integration_test/first_steps_test.dart plays the first steps
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const CardenApp(),
    ));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 5000);
    final semantics = tester.ensureSemantics();
    Profile me() => container(tester).read(profileProvider).value!;

    // The tester's history: Cards 3x3 boards finished last week in 3 to 6 seconds (a friend on a
    // shared board, Magic), so today's and this week's quests both read them. Before the fix the
    // time to beat was their second-best: 4 seconds.
    final lastWeek = Goals.mondayOf(DateTime.now()).subtract(const Duration(hours: 12));
    for (var i = 0; i < 4; i++) {
      container(tester).read(progressProvider.notifier).complete('qa-qs-fast-$i',
          gridSize: 9, mode: 'cards', moves: 8, seconds: 3 + i, hints: 0, stars: 3, session: SyncOp.newId(), resumed: false, at: lastWeek.subtract(Duration(minutes: i)));
    }
    await settle(tester, 2500);

    container(tester).read(routerProvider).go('/events');
    await settle(tester, 2500);
    final now = DateTime.now();
    final day = 'd:${Goals.dayKey(now)}', week = Goals.weekKey(now);
    expect(find.text('Solve a 3x3 board in under 15 seconds'), findsOneWidget, reason: 'the daily timed quest asks for 15 seconds, not 4');
    expect(find.textContaining('under 4 seconds'), findsNothing);
    expect(find.text('Swap'), findsNothing, reason: 'no Swap button on the rows');
    expect(find.byKey(const ValueKey('quest-swipe-hint')), findsOneWidget);
    // Every quest the free player sees, timed one included, swipes.
    for (final s in ['$day:s1', '$day:s2', '$day:s3']) {
      expect(row(s), findsOneWidget, reason: '$s swipes');
    }
    expect(tester.getSemantics(find.descendant(of: row('$day:s3'), matching: find.byType(ColoredBox)).first), isSemantics(customActions: [const CustomSemanticsAction(label: 'Swap for 1 ticket')]));
    await shot(tester, 'qs_01_quests');

    // The daily timed quest: part of the way shows the action; all the way asks first.
    await swipe(tester, '$day:s3', partway: 'qs_02_swipe_partway');
    expect(find.text('Swap this quest?'), findsNothing, reason: 'let go short of the action: nothing asked');
    final t0 = me().tickets;
    await swipe(tester, '$day:s3');
    expect(find.text('Swap this quest?'), findsOneWidget);
    expect(find.textContaining('“Solve a 3x3 board in under 15 seconds” becomes'), findsOneWidget);
    await shot(tester, 'qs_03_swap_confirm_daily');
    await tapText(tester, 'Swap for 1 ticket', ms: 2000);
    expect(me().tickets, t0 - 1, reason: 'a swap costs a ticket');
    expect(find.text('Solve a 3x3 board in under 15 seconds'), findsNothing, reason: 'the timed quest went');
    expect(find.byKey(const ValueKey('quest-swipe-hint')), findsNothing, reason: 'the line goes after the first swipe');
    await shot(tester, 'qs_04_daily_swapped');

    // The weekly timed quest.
    expect(find.text('Solve two 3x3 boards in under 15 seconds'), findsOneWidget);
    expect(row('$week:s2'), findsOneWidget);
    await swipe(tester, '$week:s2');
    expect(find.text('Swap this quest?'), findsOneWidget);
    await shot(tester, 'qs_05_swap_confirm_weekly');
    await tapText(tester, 'Swap for 1 ticket', ms: 2000);
    expect(me().tickets, t0 - 2);
    expect(find.text('Solve two 3x3 boards in under 15 seconds'), findsNothing);
    await shot(tester, 'qs_06_weekly_swapped');

    // The quest swapped in swipes again; Cancel keeps it and charges nothing.
    await swipe(tester, '$week:s2');
    await tapText(tester, 'Cancel', ms: 1200);
    expect(me().tickets, t0 - 2);
    // The last ticket on the fixed "Solve 3 puzzles"; then none left: the store, as elsewhere.
    await swipe(tester, '$day:s1');
    await tapText(tester, 'Swap for 1 ticket', ms: 2000);
    expect(me().tickets, 0);
    final row0 = await serverRow(tester);
    expect(row0['tickets'], 0);
    expect(Goals.decodeSwaps(row0['questSwaps']).keys, containsAll(['$day:s3', '$week:s2', '$day:s1']));
    await shot(tester, 'qs_07_three_swaps');
    await swipe(tester, '$day:s2');
    expect(find.text('Swap this quest?'), findsNothing, reason: 'no tickets: no question');
    await settle(tester, 1500);
    await shot(tester, 'qs_08_no_tickets_store');
    expect(container(tester).read(routerProvider).state.uri.path, '/store');
    debugPrint('QA_QS swaps ${me().questSwaps}');
    semantics.dispose();
  });
}
