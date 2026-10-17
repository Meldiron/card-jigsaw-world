// The board the player chose last opens again on the next picture (owner, 2026-10-16), on the
// real app with a QA guest: Library > a pack > a picture > Squares, Cozy, Painting > Play > solve >
// Back to pack > another picture, whose difficulty screen opens on Squares, Cozy and Painting.
//
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/remember_board_test.dart -d <simulator>
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/features/game/difficulty_screen.dart';
import 'package:carden/features/game/game_screen.dart';
import 'package:carden/game/board.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/first_steps.dart';
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
  BoardWidget board(WidgetTester tester) => tester.widget<BoardWidget>(find.byType(BoardWidget).first);

  Offset onScreen(WidgetTester tester, int slot) {
    final w = board(tester);
    final rect = tester.getRect(find.byType(BoardWidget).first);
    return rect.topLeft + w.state.board.tiling.cellCenter(slot, Size(w.width, w.height));
  }

  /// Sends every misplaced card home, one tap-tap move at a time.
  Future<void> solve(WidgetTester tester) async {
    for (var guard = 0; guard < 80; guard++) {
      final b = board(tester).state.board;
      if (b.isSolved) return;
      final slot = List.generate(b.cells, (i) => i).firstWhere((i) => !b.isLocked(i));
      await tester.tapAt(onScreen(tester, slot));
      await settle(tester, 250);
      await tester.tapAt(onScreen(tester, b.homeOf(slot)));
      await settle(tester, 450);
    }
  }

  bool paintingOn(WidgetTester tester) => tester.widget<CupertinoSwitch>(find.descendant(of: find.byKey(const ValueKey('painting-option')), matching: find.byType(CupertinoSwitch))).value;

  /// A picture tile on the pack page (its title is in the tile's accessibility label).
  Future<void> tapPicture(WidgetTester tester, String title) async {
    final tile = find.bySemanticsLabel(RegExp('(^|, )${RegExp.escape(title)}(,|\$)'));
    await tester.scrollUntilVisible(tile, 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(tile.first, warnIfMissed: false);
    await settle(tester, 4000);
  }

  testWidgets('the next picture opens on the board chosen last', (tester) async {
    final semantics = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await FirstSteps.skipFor(store); // the whole app; integration_test/first_steps_test.dart plays the first steps
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        // Squares and Painting open at levels 2 and 8; a new guest has them open here, without intro sheets.
        openFeaturesProvider.overrideWithValue(OpenFeatures.all),
        pendingUnlockIntroProvider.overrideWithValue(null),
      ],
      child: const CardenApp(),
    ));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 5000);

    // Library > a free pack > its first picture: Squares, Cozy (3x3) and Painting.
    await tapText(tester, 'Library', ms: 3000);
    final c = container(tester);
    final packs = c.read(packsProvider).value!;
    final all = c.read(allPuzzlesProvider).value!;
    final pack = packs.firstWhere((p) => p.isFree && !p.hasWindow && all.where((z) => z.packId == p.id).length >= 2);
    final pictures = [for (final z in all) if (z.packId == pack.id) z];
    await tester.dragUntilVisible(find.text(pack.name), find.byType(Scrollable).first, const Offset(0, -200));
    await tapText(tester, pack.name, ms: 4000);
    await tapPicture(tester, pictures[0].title);
    expect(find.byType(DifficultyScreen), findsOneWidget);
    await tapText(tester, 'Squares', ms: 600);
    await tester.dragUntilVisible(find.text('Cozy'), find.byType(Scrollable).first, const Offset(0, -200));
    await tapText(tester, 'Cozy', ms: 600);
    await tester.dragUntilVisible(find.byKey(const ValueKey('painting-option')), find.byType(Scrollable).first, const Offset(0, -200));
    await tester.tap(find.byKey(const ValueKey('painting-option')), warnIfMissed: false);
    await settle(tester, 800);
    expect(paintingOn(tester), isTrue);
    await shot(tester, 'rb_01_chosen');
    await tester.tap(find.byKey(const ValueKey('play-board')), warnIfMissed: false);
    await settle(tester, 6000);
    if (find.text('Got it').evaluate().isNotEmpty) await tapText(tester, 'Got it');
    expect(board(tester).state.board.spec.mode, GameMode.squares);
    expect(board(tester).painting, isTrue);

    // Solve it, then Back to pack.
    await solve(tester);
    await settle(tester, 4000);
    await shot(tester, 'rb_02_solved');
    await tapText(tester, 'Back to pack', ms: 4000);

    // Another picture of the same pack, never played: it opens on Squares, Cozy and Painting.
    final played = c.read(progressProvider).value ?? const {};
    final other = pictures.firstWhere((z) => z.id != pictures[0].id && played[z.id] == null);
    await tapPicture(tester, other.title);
    expect(find.byType(DifficultyScreen), findsOneWidget);
    expect(tester.widget<Semantics>(find.ancestor(of: find.byKey(const ValueKey('mode-squares')), matching: find.byType(Semantics)).first).properties.selected, isTrue, reason: 'Squares is preselected');
    final selected = tester.widgetList<Text>(find.text('Cozy'));
    expect(selected, isNotEmpty);
    await tester.dragUntilVisible(find.byKey(const ValueKey('painting-option')), find.byType(Scrollable).first, const Offset(0, -200));
    expect(paintingOn(tester), isTrue, reason: 'Painting is preselected');
    final last = c.read(settingsProvider).lastBoard!;
    expect((last.mode, last.tier, last.painting), ('squares', 0, true));
    final cozy = BoardSpec.squareTiers(GameMode.squares)[0];
    expect(find.descendant(of: find.byKey(const ValueKey('play-board')), matching: find.text('Play')), findsOneWidget);
    await shot(tester, 'rb_03_next_picture_${cozy.code}');
    semantics.dispose();
  });
}
