// Shapes and options that open as levels rise, their one-screen intros, the
// new quests, Claim all, the quest line on the completion overlay and
// Another picture from Quick play. A fresh player on the live backend.
//
// Run: tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//        --target=integration_test/progression_quests_test.dart -d <simulator>
//
// The later unlocks (levels 4 to 10) come from XP granted through the same
// completion call a solve makes, so the run does not have to play 60 boards.
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/events/events_screen.dart';
import 'package:carden/features/events/quest_rewards.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/features/game/difficulty_screen.dart';
import 'package:carden/game/board.dart';
import 'package:carden/router.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/progress.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/unlocks.dart';
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

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(CardenApp)));
  String location(WidgetTester tester) => container(tester).read(routerProvider).state.uri.toString();

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

  /// From the difficulty screen: Cozy, Play, solve; leaves the completion overlay up.
  Future<void> playCozy(WidgetTester tester) async {
    await tester.dragUntilVisible(find.text('Cozy'), find.byType(Scrollable).first, const Offset(0, -200));
    await settle(tester, 500);
    await tapText(tester, 'Cozy', ms: 600);
    await tester.tap(find.textContaining('· Play'), warnIfMissed: false);
    await settle(tester, 6000);
    if (find.text('Got it').evaluate().isNotEmpty) await tapText(tester, 'Got it');
    await solveBoard(tester);
    await settle(tester, 3500);
    expect(find.text('Picture complete'), findsOneWidget);
  }

  Future<void> quickPlay(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('home-quick-play')), warnIfMissed: false);
    await settle(tester, 4000);
    expect(find.byType(DifficultyScreen), findsOneWidget);
  }

  Future<void> backHome(WidgetTester tester) async {
    await tapText(tester, 'Back to pack', ms: 2500);
    await tapText(tester, 'Home', ms: 3000);
  }

  /// XP through the completion call a solve makes (a QA shortcut to the later levels).
  Future<int> grantXp(WidgetTester tester, String id) async {
    final r = await container(tester).read(profileProvider.notifier).recordCompletion(puzzleId: 'qa-xp-$id', cells: 300, stars: 3, firstTime: true);
    await settle(tester, 3000);
    return r.level;
  }

  /// Waits on Home for [u]'s intro and captures it.
  Future<void> expectIntro(WidgetTester tester, Unlock u, String name) async {
    for (var i = 0; i < 20 && find.byKey(ValueKey('unlock-intro-${u.name}')).evaluate().isEmpty; i++) {
      await settle(tester, 500);
    }
    expect(find.byKey(ValueKey('unlock-intro-${u.name}')), findsOneWidget, reason: '${u.label} intro on Home');
    await shot(tester, name);
  }

  testWidgets('shapes open as levels rise; new quests; Claim all; Another picture', (tester) async {
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
    expect(container(tester).read(openFeaturesProvider).modes, [GameMode.cards], reason: 'a new player starts with Cards only');
    // The level card names the next unlock.
    await tester.dragUntilVisible(find.byKey(const ValueKey('next-unlock-squares')), find.byType(Scrollable).first, const Offset(0, -250));
    await shot(tester, 'pq_01_home_next_unlock');
    await tester.fling(find.byType(Scrollable).first, const Offset(0, 3000), 3000);
    await settle(tester, 1000);

    // Quick play: the other shapes and Painting are locked with their levels.
    await quickPlay(tester);
    expect(find.text('Level ${Unlock.squares.level}'), findsOneWidget);
    expect(find.text('Level ${Unlock.hexagons.level}'), findsOneWidget);
    await shot(tester, 'pq_02_difficulty_locked');
    await tester.tap(find.byKey(const ValueKey('mode-squares')), warnIfMissed: false);
    await settle(tester, 1200);
    expect(find.text('Squares open at level ${Unlock.squares.level}'), findsOneWidget);
    await shot(tester, 'pq_03_locked_info');
    await tapText(tester, 'Got it');
    await tester.dragUntilVisible(find.byKey(const ValueKey('painting-option')), find.byType(Scrollable).first, const Offset(0, -200));
    await settle(tester, 500);
    expect(find.text('Level ${Unlock.painting.level}'), findsOneWidget);
    await shot(tester, 'pq_03b_painting_locked');

    // Another picture: a new one from the Quick play pool, same board.
    final first = location(tester);
    await tester.tap(find.byKey(const ValueKey('another-picture')), warnIfMissed: false);
    await settle(tester, 4000);
    final second = location(tester);
    expect(second, isNot(first), reason: 'Another picture opens a different picture');
    expect(second, contains('from=quick'));
    await shot(tester, 'pq_04_another_picture');

    // Two Cozy boards: level 2 opens Squares, shown on the completion overlay.
    var questLine = false;
    await playCozy(tester);
    questLine |= find.byKey(const ValueKey('quest-ready-line')).evaluate().isNotEmpty;
    await shot(tester, 'pq_05_first_completion');
    await backHome(tester);
    await quickPlay(tester);
    await playCozy(tester);
    expect(find.byKey(const ValueKey('level-up-line')), findsOneWidget);
    expect(find.textContaining('Squares are open'), findsOneWidget);
    questLine |= find.byKey(const ValueKey('quest-ready-line')).evaluate().isNotEmpty;
    await shot(tester, 'pq_06_completion_unlock');
    if (find.byKey(const ValueKey('quest-ready-line')).evaluate().isNotEmpty) {
      // The quest line opens the Quests tab.
      await tester.tap(find.byKey(const ValueKey('quest-ready-line')), warnIfMissed: false);
      await settle(tester, 3000);
      expect(find.byType(EventsScreen), findsOneWidget);
      await shot(tester, 'pq_07_quests_from_line');
      await tapText(tester, 'Home', ms: 3000);
    } else {
      await backHome(tester);
    }

    // Home shows the Squares intro; Try it opens a picture with Squares preselected.
    await expectIntro(tester, Unlock.squares, 'pq_08_intro_squares');
    await tester.tap(find.byKey(const ValueKey('unlock-try')), warnIfMissed: false);
    await settle(tester, 4000);
    expect(find.byType(DifficultyScreen), findsOneWidget);
    expect(find.textContaining('squares · Play'), findsOneWidget);
    await shot(tester, 'pq_09_try_squares');
    await tester.tap(find.byIcon(CupertinoIcons.back).first, warnIfMissed: false);
    await settle(tester, 1500);

    // A third board finishes "Solve 3 puzzles", and nothing else: every other quest asks for
    // something these Cozy boards are not.
    await quickPlay(tester);
    await playCozy(tester);
    questLine |= find.byKey(const ValueKey('quest-ready-line')).evaluate().isNotEmpty;
    await shot(tester, 'pq_10_third_completion');
    expect(questLine, isTrue, reason: 'a solve that finished a quest said so on the overlay');
    await backHome(tester);
    await tapText(tester, 'Quests', ms: 3000);
    final ready = readyGoals(container(tester).read(progressProvider).value!.values, container(tester).read(profileProvider).value, container(tester).read(openFeaturesProvider), DateTime.now());
    debugPrint('QA_READY ${ready.map((g) => g.key).toList()}');
    expect([for (final g in ready) if (g.key.startsWith('d:')) g.title], ['Solve 3 puzzles']);
    await shot(tester, 'pq_11_ready');
    if (find.byKey(const ValueKey('claim-all')).evaluate().isNotEmpty) {
      await tapText(tester, 'Claim all', ms: 3000);
    } else {
      await tapText(tester, 'Claim', ms: 3000);
    }
    await shot(tester, 'pq_12_claimed');
    expect(readyGoals(container(tester).read(progressProvider).value!.values, container(tester).read(profileProvider).value, container(tester).read(openFeaturesProvider), DateTime.now()), isEmpty);
    expect(find.byKey(const ValueKey('claim-all')), findsNothing);
    // The day's quests at level 2: no locked shape, Painting or "every mode".
    await tester.fling(find.byType(CustomScrollView).last, const Offset(0, -700), 2000);
    await settle(tester, 1200);
    await shot(tester, 'pq_13_quests_level2');

    // The later unlocks, one intro each on Home.
    await tapText(tester, 'Home', ms: 2500);
    expect(await grantXp(tester, 'a'), greaterThanOrEqualTo(Unlock.triangles.level));
    await expectIntro(tester, Unlock.triangles, 'pq_14_intro_triangles');
    await tapText(tester, 'Later');
    expect(await grantXp(tester, 'b'), greaterThanOrEqualTo(Unlock.hexagons.level));
    await expectIntro(tester, Unlock.hexagons, 'pq_15_intro_hexagons');
    await tapText(tester, 'Later');
    expect(await grantXp(tester, 'c'), greaterThanOrEqualTo(Unlock.painting.level));
    await expectIntro(tester, Unlock.painting, 'pq_16_intro_painting');
    await tester.tap(find.byKey(const ValueKey('unlock-try')), warnIfMissed: false);
    await settle(tester, 4000);
    expect(find.byType(DifficultyScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('painting-bonus')), findsOneWidget, reason: 'Try it preselects Painting');
    await shot(tester, 'pq_17_try_painting');
    await tester.tap(find.byIcon(CupertinoIcons.back).first, warnIfMissed: false);
    await settle(tester, 1500);
    expect(await grantXp(tester, 'd'), greaterThanOrEqualTo(Unlock.giant.level));
    await expectIntro(tester, Unlock.giant, 'pq_18_intro_giant');
    await tester.tap(find.byKey(const ValueKey('unlock-try')), warnIfMissed: false);
    await settle(tester, 4000);
    await shot(tester, 'pq_19_try_giant');
    debugPrint('QA_GIANT_TRY ${location(tester)}');
    expect(container(tester).read(openFeaturesProvider), OpenFeatures.forPlayer(level: container(tester).read(profileProvider).value!.level));
    expect(container(tester).read(pendingUnlockIntroProvider), isNull);
  }, timeout: const Timeout(Duration(minutes: 12)));
}
