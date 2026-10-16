// A new player's first steps (owner, 2026-10-16), on the real app with a QA guest and no shortcuts:
// the welcome pages lead into a first board with a hint per step, the finish leads Home, Home starts
// calm and grows with the second picture, locked tabs explain themselves and open with "Unlock
// anyway", one-time tips show in the Library and on the board picker, and "Unlock anyway" on Home
// opens everything.
//
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/first_steps_test.dart -d <simulator>
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/features/game/difficulty_screen.dart';
import 'package:carden/features/game/game_screen.dart';
import 'package:carden/game/board.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
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

  Future<void> tapKey(WidgetTester tester, String key, {int ms = 1200}) async {
    final f = find.byKey(ValueKey(key));
    expect(f, findsWidgets, reason: 'expected $key on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  Future<void> scrollTo(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);
    await settle(tester, 600);
  }

  bool shown(String key) => find.byKey(ValueKey(key)).evaluate().isNotEmpty;

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(CardenApp)));
  BoardWidget board(WidgetTester tester) => tester.widget<BoardWidget>(find.byType(BoardWidget).first);

  Offset onScreen(WidgetTester tester, int slot) {
    final w = board(tester);
    final rect = tester.getRect(find.byType(BoardWidget).first);
    return rect.topLeft + w.state.board.tiling.cellCenter(slot, Size(w.width, w.height));
  }

  Future<void> move(WidgetTester tester, int from, int to) async {
    await tester.tapAt(onScreen(tester, from));
    await settle(tester, 350);
    await tester.tapAt(onScreen(tester, to));
    await settle(tester, 600);
  }

  /// Sends every misplaced card home, one tap-tap move at a time.
  Future<void> solve(WidgetTester tester) async {
    for (var guard = 0; guard < 80; guard++) {
      final b = board(tester).state.board;
      if (b.isSolved) return;
      final slot = List.generate(b.cells, (i) => i).firstWhere((i) => !b.isLocked(i));
      await move(tester, slot, b.homeOf(slot));
    }
  }

  /// A tab of the floating tab bar by its label (the tab bar is the last of the texts).
  Future<void> tapTab(WidgetTester tester, String label, {int ms = 1500}) async {
    await tester.tap(find.text(label).last, warnIfMissed: false);
    await settle(tester, ms);
  }

  testWidgets('first steps: first board, a calm Home that grows, locked tabs, Unlock anyway', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(overrides: [localStoreProvider.overrideWithValue(store)], child: const CardenApp()));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await shot(tester, 'fs_00_welcome_last');
    await tapText(tester, 'Start playing', ms: 3000);
    await settle(tester, 3000);
    final c = container(tester);
    expect(c.read(firstStepsProvider).calm, isTrue, reason: 'a new player gets the guided start');

    // 1. Straight into a first board: nine cards, the hint for step 1, no tools yet.
    expect(find.byType(GameScreen), findsOneWidget, reason: 'the welcome pages lead into a board, not Home');
    final spec = board(tester).state.board.spec;
    expect((spec.mode, spec.cells), (GameMode.cards, 9));
    expect(shown('coach-pick'), isTrue);
    await shot(tester, 'fs_01_first_board');

    // 2. Pick a card: its place is outlined.
    var b = board(tester).state.board;
    final slot = List.generate(b.cells, (i) => i).firstWhere((i) => !b.isLocked(i));
    await tester.tapAt(onScreen(tester, slot));
    await settle(tester, 700);
    expect(shown('coach-place'), isTrue);
    expect(board(tester).state.hintTarget, b.homeOf(slot), reason: 'the outline shows where the picked card belongs');
    await shot(tester, 'fs_02_place');

    // 3. Put it there: it locks, and the hint says so.
    await tester.tapAt(onScreen(tester, b.homeOf(slot)));
    await settle(tester, 900);
    expect(shown('coach-locked') || shown('coach-joined'), isTrue);
    await shot(tester, 'fs_03_locked');

    // 4. The next move ends the hints; the tools come in.
    b = board(tester).state.board;
    final next = List.generate(b.cells, (i) => i).firstWhere((i) => !b.isLocked(i));
    await move(tester, next, b.homeOf(next));
    await settle(tester, 600);
    expect(shown('coach'), isFalse);
    expect(c.read(settingsProvider).tutorialSeen, isTrue);
    await shot(tester, 'fs_04_tools');

    // 5. Finish: the first-picture line, and the way out is Home.
    await solve(tester);
    await settle(tester, 4000);
    expect(shown('first-board-line'), isTrue);
    expect(find.text('Home'), findsWidgets);
    await shot(tester, 'fs_05_complete');
    await tapKey(tester, 'completion-back', ms: 3500);

    // 6. A calm Home: today's picture, the next step and the daily gift that just opened; no Quick
    //    play or pack rows yet; Quests and Social locked.
    expect(find.byType(GameScreen), findsNothing);
    expect(shown('reveal-tip-dailyGift'), isTrue, reason: 'the daily gift just opened');
    expect(shown('next-step-pack'), isTrue);
    expect(shown('home-quick-play'), isFalse);
    expect(find.text('Featured packs'), findsNothing);
    expect(shown('tab-lock-Quests') && shown('tab-lock-Social'), isTrue);
    await shot(tester, 'fs_06_home');
    await scrollTo(tester, find.byKey(const ValueKey('more-to-come')));
    await tester.ensureVisible(find.byKey(const ValueKey('unlock-anyway')));
    await settle(tester, 600);
    await shot(tester, 'fs_07_more_to_come');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await settle(tester, 800);

    // 7. A locked tab says when it opens; Not now keeps it closed.
    await tapTab(tester, 'Quests', ms: 1200);
    expect(find.text('Quests open after 2 pictures'), findsOneWidget);
    await shot(tester, 'fs_08_locked_tab');
    await tester.tap(find.text('Not now').last, warnIfMissed: false);
    await settle(tester, 1000);
    expect(shown('tab-lock-Quests'), isTrue);

    // 8. Unlock anyway on Social opens that tab only.
    await tapTab(tester, 'Social', ms: 1200);
    expect(find.text('Social opens at level 4'), findsOneWidget);
    // The alert's button (Home's own "Unlock anyway" is built under the alert).
    await tester.tap(find.text('Unlock anyway').last, warnIfMissed: false);
    await settle(tester, 2500);
    expect(find.text('Social'), findsWidgets);
    expect(shown('tab-lock-Social'), isFalse);
    expect(shown('tab-lock-Quests'), isTrue);
    await shot(tester, 'fs_09_social_open');

    // 9. The Library's one-time tip.
    await tapTab(tester, 'Library', ms: 2500);
    expect(shown('tip-library'), isTrue);
    await shot(tester, 'fs_10_library_tip');
    await tapKey(tester, 'tip-library-close', ms: 800);
    expect(shown('tip-library'), isFalse);

    // 10. Home: close the tip, follow the next step to the board picker and its one-time tip.
    await tapTab(tester, 'Home', ms: 2000);
    await tapKey(tester, 'reveal-tip-close', ms: 800);
    expect(shown('reveal-tip-dailyGift'), isFalse);
    await tapKey(tester, 'next-step-pack', ms: 3500);
    expect(find.byType(DifficultyScreen), findsOneWidget);
    expect(shown('tip-board'), isTrue);
    await shot(tester, 'fs_11_board_tip');
    await tester.tap(find.textContaining('· Play').first, warnIfMissed: false);
    await settle(tester, 6000);
    expect(shown('coach'), isFalse, reason: 'the hints are for the first board only');
    await solve(tester);
    await settle(tester, 4000);
    await shot(tester, 'fs_12_second_complete');
    await tapKey(tester, 'completion-back', ms: 3500);
    if (shown('unlock-try')) await tapText(tester, 'Later', ms: 1200);

    // 11. Two pictures: packs on Home and Quests open, with what just opened said once.
    expect(shown('tab-lock-Quests'), isFalse);
    expect(shown('reveal-tip-quests'), isTrue);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await settle(tester, 800);
    await shot(tester, 'fs_13_home_grows');
    await tapKey(tester, 'reveal-tip-action', ms: 2500);
    expect(find.text('Quests'), findsWidgets);
    expect(c.read(firstStepsProvider).tips.contains('tab:quests'), isTrue, reason: 'visited: the new-tab dot goes');
    await tapTab(tester, 'Home', ms: 2000);

    // 12. Unlock anyway on Home opens everything.
    await scrollTo(tester, find.byKey(const ValueKey('unlock-anyway')));
    await tapKey(tester, 'unlock-anyway', ms: 2000);
    expect(c.read(firstStepsProvider).calm, isFalse);
    expect(shown('more-to-come'), isFalse);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await settle(tester, 800);
    await shot(tester, 'fs_14_everything');
  });
}
