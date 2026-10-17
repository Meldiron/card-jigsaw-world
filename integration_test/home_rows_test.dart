// Home QA: Quick play, Packs in progress, Missing stars, Featured packs and
// Finished packs, on a fresh guest against the live Appwrite backend.
//   xcrun simctl uninstall <udid> com.matejbaco.cardjigsawworld
//   flutter drive --dart-define=CJW_MUTE=true --dart-define=CJW_QA=true \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/home_rows_test.dart -d <udid>
// Captures land in screenshots/home_*.png.
//
// A fresh guest has no progress, so after the first Quick play tap the test
// writes progress rows through the app's own ProgressNotifier (the same save
// a finished game makes): one pack with three stars everywhere, one finished
// short of stars, two started. The newest finished game is on Squares, Easy,
// which Quick play then preselects on the mode and board screen.
import 'dart:async';

import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/features/game/difficulty_screen.dart';
import 'package:carden/features/gallery/library_screen.dart';
import 'package:carden/features/game/game_screen.dart';
import 'package:carden/game/board.dart';
import 'package:carden/models/models.dart';
import 'package:carden/router.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/progress.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/unlocks.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show MaterialApp;
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
  // Boards here are played the moment they show: no picture before the deal (GameScreen.dealPreview).
  GameScreen.dealPreview = false;

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, 600);
    await binding.takeScreenshot(name);
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

  Future<void> go(WidgetTester tester, String path, {int ms = 3000}) async {
    container(tester).read(routerProvider).go(path);
    await settle(tester, ms);
  }

  /// Scrolls Home until the section header [text] sits just under the glass
  /// header bar, so the header and its row are both in the capture.
  Future<void> scrollTo(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(find.text(text), 250, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    await settle(tester, 600);
    unawaited(Scrollable.ensureVisible(tester.element(find.text(text)), alignment: 0.12, duration: const Duration(milliseconds: 300)));
    await settle(tester, 1500);
  }

  testWidgets('Home rows', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await FirstSteps.skipFor(store); // the whole app; integration_test/first_steps_test.dart plays the first steps
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        // Shapes and options open as levels rise (lib/state/unlocks.dart); these suites play every one, so all are open and no intro sheet interrupts them.
        openFeaturesProvider.overrideWithValue(OpenFeatures.all),
        pendingUnlockIntroProvider.overrideWithValue(null),
      ],
      child: const CardenApp(),
    ));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 6000); // catalogue and covers
    if (find.text('Claim').evaluate().isNotEmpty) {
      await tapText(tester, 'Claim');
      if (find.textContaining('Claim day').evaluate().isNotEmpty) {
        await tester.tap(find.textContaining('Claim day'), warnIfMissed: false);
        await settle(tester, 1500);
      }
      await tester.tapAt(const Offset(200, 60));
      await settle(tester, 1000);
    }

    // A new player: Quick play offers an unplayed picture and, with no
    // finished game to copy, opens its difficulty screen.
    expect(find.text('Quick play'), findsOneWidget);
    expect(find.text('A picture you have not played yet'), findsOneWidget);
    expect(find.text('Packs in progress'), findsNothing);
    expect(find.text('Missing stars'), findsNothing);
    expect(find.text('Finished packs'), findsNothing);
    await shot(tester, 'home_01_new_player');
    await tapText(tester, 'Quick play', ms: 3500);
    expect(find.byType(DifficultyScreen), findsOneWidget, reason: 'first Quick play opens the difficulty screen');
    await shot(tester, 'home_02_quick_play_difficulty');
    await tester.tap(find.byIcon(CupertinoIcons.back).first, warnIfMissed: false);
    await settle(tester, 1500);

    // Progress, written the way a finished game writes it.
    final c = container(tester);
    final packs = await c.read(packsProvider.future);
    final puzzles = await c.read(allPuzzlesProvider.future);
    final profile = c.read(profileProvider.notifier);
    final library = packs.where((p) => !p.isDaily && !p.hasWindow && profile.isUnlocked(p)).toList();
    List<Puzzle> of(Pack p) => puzzles.where((z) => z.packId == p.id).toList();
    final usable = library.where((p) => of(p).length >= 4).toList();
    expect(usable.length, greaterThanOrEqualTo(4), reason: 'four unlocked library packs');
    // The two finished packs: the smallest, to keep the writes few.
    final bySize = [...usable]..sort((a, b) => of(a).length.compareTo(of(b).length));
    final perfect = bySize[0], short = bySize[1];
    // Started packs keep pictures to spare, so four solves do not finish them.
    final started = usable.where((p) => p != perfect && p != short && of(p).length >= 6).take(2).toList();
    expect(started, hasLength(2), reason: 'two larger unlocked library packs');
    debugPrint('home QA packs: perfect ${perfect.id} (${of(perfect).length}), short ${short.id} (${of(short).length}), '
        'started ${started.map((p) => p.id).join(', ')}');
    final progress = c.read(progressProvider.notifier);
    final easySquares = BoardSpec.squareTiers(GameMode.squares)[1];
    var minute = 0;
    Future<void> solve(Puzzle z, int stars, {GameMode mode = GameMode.cards, int? cells}) async => progress.complete(
          z.id,
          gridSize: cells ?? 16,
          mode: mode.code,
          moves: 30,
          seconds: 90,
          hints: 0,
          stars: stars,
          session: 'qa-${z.id}',
          resumed: false,
          at: DateTime.now().subtract(Duration(minutes: 300 - minute++)),
        );
    for (final z in of(perfect)) {
      await solve(z, 3);
    }
    final shortPictures = of(short);
    for (var i = 0; i < shortPictures.length; i++) {
      await solve(shortPictures[i], i < 3 ? 2 : 3);
    }
    for (final (i, p) in started.indexed) {
      for (final z in of(p).take(i == 0 ? 3 : 1)) {
        await solve(z, 3);
      }
    }
    // The newest finished game: Squares on the Easy board.
    await solve(of(started.first)[3], 3, mode: GameMode.squares, cells: easySquares.cells);

    await go(tester, '/home', ms: 3000);
    await shot(tester, 'home_03_quick_play_with_board');

    await scrollTo(tester, 'Packs in progress');
    expect(find.text('2 packs to finish'), findsOneWidget);
    await shot(tester, 'home_04_packs_in_progress');

    await scrollTo(tester, 'Missing stars');
    expect(find.text('3 stars to earn in 1 pack'), findsOneWidget);
    await shot(tester, 'home_05_missing_stars');

    await scrollTo(tester, 'Featured packs');
    await shot(tester, 'home_06_featured');

    await scrollTo(tester, 'Finished packs');
    expect(find.text('Packs finished'), findsOneWidget);
    expect(find.text('With every star'), findsOneWidget);
    await shot(tester, 'home_07_finished_packs');

    // See all: the Library tab, on the Finished filter.
    await tester.tap(find.text('See all').last, warnIfMissed: false);
    await settle(tester, 3000);
    expect(c.read(libraryFilterProvider), LibraryFilter.finished);
    await shot(tester, 'home_08_library_finished');

    // Quick play again: the mode and board screen, on the remembered board (owner request: Quick
    // play never starts a game by itself), then Play deals it.
    await go(tester, '/home', ms: 2500);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
    await settle(tester, 1500);
    await tapText(tester, 'Quick play', ms: 4000);
    expect(find.byType(DifficultyScreen), findsOneWidget, reason: 'Quick play opens the mode and board screen');
    expect(tester.widget<Semantics>(find.ancestor(of: find.byKey(const ValueKey('mode-squares')), matching: find.byType(Semantics)).first).properties.selected, isTrue, reason: 'the last mode is preselected');
    await shot(tester, 'home_09_quick_play_preselected');
    await tester.tap(find.byKey(const ValueKey('play-board')), warnIfMissed: false);
    await settle(tester, 6000);
    if (find.text('Got it').evaluate().isNotEmpty) await tapText(tester, 'Got it');
    expect(find.byType(BoardWidget), findsOneWidget);
    final board = tester.widget<BoardWidget>(find.byType(BoardWidget)).state.board;
    expect(board.spec.mode, GameMode.squares);
    expect(board.spec.tierIndex, 1);
    await shot(tester, 'home_10_quick_play_game');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
