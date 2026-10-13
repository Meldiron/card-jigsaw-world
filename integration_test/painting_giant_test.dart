// Painting (cards in black and white until they lock, x1.25) and giant boards (100 to 300
// cards, pinch to zoom) on the real app and the live backend.
//
// Run: tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//        --target=integration_test/painting_giant_test.dart -d <simulator>
//
// Until the Giant pack is in the catalogue, the second picture of Wild Nature stands in for a
// Giant pack picture (the provider that says so is overridden); its 1200 px picture is soft
// when zoomed in, but the ladder, the full-size decode, zoom, moves and resume are the same.
import 'package:card_jigsaw_world/app.dart';
import 'package:card_jigsaw_world/core/sfx.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/features/game/board_widget.dart';
import 'package:card_jigsaw_world/features/game/difficulty_screen.dart';
import 'package:card_jigsaw_world/game/board.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/router.dart';
import 'package:card_jigsaw_world/state/catalog.dart';
import 'package:card_jigsaw_world/state/giant.dart';
import 'package:card_jigsaw_world/state/profile.dart';
import 'package:card_jigsaw_world/state/progress.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:card_jigsaw_world/state/rewards.dart';
import 'package:card_jigsaw_world/state/unlocks.dart';
import 'package:card_jigsaw_world/state/social.dart';
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

/// The stand-in Giant pack picture until the real pack exists.
String? _standIn;

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
  BoardWidget board(WidgetTester tester) => tester.widget<BoardWidget>(find.byType(BoardWidget).first);

  /// Where slot [slot] of the board is on screen, with the board's zoom.
  Offset onScreen(WidgetTester tester, int slot) {
    final w = board(tester);
    final rect = tester.getRect(find.byType(BoardWidget).first);
    final local = w.state.board.tiling.cellCenter(slot, Size(w.width, w.height));
    final z = w.zoom;
    return rect.topLeft + (z == null ? local : local * z.zoom + z.pan);
  }

  bool visible(WidgetTester tester, Offset p) => tester.getRect(find.byType(BoardWidget).first).deflate(6).contains(p);

  /// Sends every misplaced card home, one tap-tap move at a time (normal boards).
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

  testWidgets('painting board, giant board: zoom, move while zoomed, resume', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        // Shapes and options open as levels rise (lib/state/unlocks.dart); these suites play every one, so all are open and no intro sheet interrupts them.
        openFeaturesProvider.overrideWithValue(OpenFeatures.all),
        pendingUnlockIntroProvider.overrideWithValue(null),
        isGiantPuzzleProvider.overrideWith((ref, id) {
          if (id == _standIn) return true;
          final puzzle = ref.watch(resolvedPuzzleProvider(id));
          final packs = ref.watch(packsProvider).value ?? const <Pack>[];
          return puzzle != null && packs.any((p) => p.id == puzzle.packId && isGiantPack(p));
        }),
      ],
      child: const CardJigsawApp(),
    ));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 5000);

    // ---- Painting: Library > Wild Nature > Hidden Waterfall > Cozy + Painting.
    await tapText(tester, 'Library', ms: 3000);
    await tapText(tester, 'Wild Nature', ms: 4000);
    await tapText(tester, 'Hidden Waterfall', ms: 4000);
    expect(find.byType(DifficultyScreen), findsOneWidget);
    await tester.dragUntilVisible(find.text('Cozy'), find.byType(Scrollable).first, const Offset(0, -200));
    await tapText(tester, 'Cozy', ms: 600);
    await tester.dragUntilVisible(find.byKey(const ValueKey('painting-option')), find.byType(Scrollable).first, const Offset(0, -200));
    await tester.tap(find.byKey(const ValueKey('painting-option')), warnIfMissed: false);
    await settle(tester, 800);
    expect(find.byKey(const ValueKey('painting-bonus')), findsOneWidget, reason: 'the rewards show the Painting bonus');
    await shot(tester, 'pg_01_difficulty_painting');
    final coinsBefore = container(tester).read(profileProvider).value!.coins;
    await tester.tap(find.textContaining('· Play'), warnIfMissed: false);
    await settle(tester, 6000);
    if (find.text('Got it').evaluate().isNotEmpty) await tapText(tester, 'Got it');
    expect(board(tester).painting, isTrue);
    expect(find.textContaining('· Painting'), findsOneWidget, reason: 'the HUD names Painting');
    await shot(tester, 'pg_02_painting_start');
    // Two cards home: they get their colour back, the rest stays black and white.
    for (var k = 0; k < 2; k++) {
      final b = board(tester).state.board;
      final slot = List.generate(b.cells, (i) => i).firstWhere((i) => !b.isLocked(i));
      await tester.tapAt(onScreen(tester, slot));
      await settle(tester, 250);
      await tester.tapAt(onScreen(tester, b.homeOf(slot)));
      await settle(tester, 900);
    }
    expect(board(tester).state.board.lockedCount, greaterThan(0));
    await shot(tester, 'pg_03_painting_locked');
    // Leave and come back: the board resumes in Painting.
    await tester.tap(find.byIcon(CupertinoIcons.pause_fill), warnIfMissed: false);
    await settle(tester, 900);
    await tapText(tester, 'Save & quit', ms: 2500);
    final hidden = container(tester).read(allPuzzlesProvider).value!.firstWhere((p) => p.title == 'Hidden Waterfall');
    expect(container(tester).read(puzzleProgressProvider(hidden.id))!.painting, isTrue, reason: 'saved with the board');
    // A started picture resumes straight from the pack; its difficulty screen shows the frozen choice.
    container(tester).read(routerProvider).push('/play/${hidden.id}');
    await settle(tester, 4000);
    expect(find.textContaining('in Painting is in progress'), findsOneWidget);
    expect(find.byKey(const ValueKey('painting-bonus')), findsOneWidget);
    await shot(tester, 'pg_03b_painting_resume_difficulty');
    await tester.tap(find.textContaining('Continue ·'), warnIfMissed: false);
    await settle(tester, 5000);
    expect(board(tester).painting, isTrue, reason: 'resumes in Painting');
    await solve(tester);
    await settle(tester, 3500);
    expect(find.text('Picture complete'), findsOneWidget);
    await shot(tester, 'pg_04_painting_complete');
    final reward = container(tester).read(profileProvider).value!.coins - coinsBefore;
    final stars = board(tester).state.stars;
    final cells = board(tester).state.board.cells;
    final expected = Economy.completionCoins(cells, stars, painting: true);
    debugPrint('QA painting reward: +$reward coins (painting formula $expected, plain ${Economy.completionCoins(cells, stars)})');
    expect(reward, greaterThanOrEqualTo(expected), reason: 'paid with the Painting bonus (level-up coins may come on top)');
    await tapText(tester, 'Back to pack', ms: 2500);

    // ---- Giant board on a Giant pack picture (or the stand-in).
    final packs = container(tester).read(packsProvider).value!;
    final all = container(tester).read(allPuzzlesProvider).value!;
    final giantPack = packs.where(isGiantPack).firstOrNull;
    Puzzle target;
    if (giantPack != null) {
      target = all.firstWhere((p) => p.packId == giantPack.id);
      debugPrint('QA giant: real Giant pack ${giantPack.id}, picture ${target.id}');
    } else {
      final wild = packs.firstWhere((p) => p.name == 'Wild Nature');
      target = (all.where((p) => p.packId == wild.id).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))[1];
      _standIn = target.id;
      debugPrint('QA giant: no Giant pack yet, stand-in ${target.id} (${target.title})');
    }
    container(tester).read(routerProvider).push('/play/${target.id}');
    await settle(tester, 6000);
    for (final label in BoardSpec.giantLabels) {
      expect(find.text(label), findsWidgets, reason: 'giant ladder shows $label');
    }
    expect(find.text('Cozy'), findsNothing, reason: 'no normal sizes for a Giant pack picture');
    await shot(tester, 'pg_05_giant_difficulty');
    await tester.dragUntilVisible(find.text('Colossal'), find.byType(Scrollable).first, const Offset(0, -200));
    await tapText(tester, 'Colossal', ms: 800);
    await shot(tester, 'pg_05b_giant_colossal');
    await tester.tap(find.textContaining('· Play'), warnIfMissed: false);
    await settle(tester, 8000);
    final spec = board(tester).state.board.spec;
    debugPrint('QA giant board: ${spec.fullCode} ${spec.cells} cards');
    expect(spec.isGiant, isTrue);
    expect(spec.cells, greaterThanOrEqualTo(250));
    expect(board(tester).zoom, isNotNull);
    await shot(tester, 'pg_06_giant_whole');

    // Zoom in with the button, then pinch further.
    await tester.tap(find.byKey(const ValueKey('zoom-in')), warnIfMissed: false);
    await settle(tester, 900);
    final z1 = board(tester).zoom!.zoom;
    expect(z1, greaterThan(2.0));
    final mid = tester.getRect(find.byType(BoardWidget).first).center;
    // Each pump is one frame built on the UI thread (debug build: an upper bound).
    final frames = <int>[];
    Future<void> frame() async {
      final w = Stopwatch()..start();
      await tester.pump();
      frames.add(w.elapsedMicroseconds);
    }

    final a = await tester.startGesture(mid - const Offset(30, 0));
    final b = await tester.startGesture(mid + const Offset(30, 0), pointer: 7);
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(-6, 0));
      await b.moveBy(const Offset(6, 0));
      await frame();
    }
    // Two fingers moving together pan the board.
    final panBefore = board(tester).zoom!.pan;
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(0, 8));
      await b.moveBy(const Offset(0, 8));
      await frame();
    }
    await a.up();
    await b.up();
    await settle(tester, 600);
    final z2 = board(tester).zoom!.zoom;
    frames.sort();
    debugPrint('QA zoom: button $z1, after pinch $z2, pan ${panBefore.dy.round()} -> ${board(tester).zoom!.pan.dy.round()}; '
        'pinch frames median ${frames[frames.length ~/ 2] ~/ 1000} ms, worst ${frames.last ~/ 1000} ms');
    expect(z2, greaterThan(z1));
    await shot(tester, 'pg_07_giant_zoomed');

    // A tap-tap move while zoomed: pick a card on screen, pan to its home, tap there.
    final before = board(tester).state.board;
    int? from;
    for (var s = 0; s < before.cells; s++) {
      if (!before.isLocked(s) && visible(tester, onScreen(tester, s))) {
        from = s;
        break;
      }
    }
    expect(from, isNotNull);
    await tester.tapAt(onScreen(tester, from!));
    await settle(tester, 500);
    expect(board(tester).state.selectedGroup, contains(from), reason: 'the card is selected');
    await shot(tester, 'pg_08_giant_selected_zoomed');
    final home = before.homeOf(from);
    if (!visible(tester, onScreen(tester, home))) {
      // Pan so the target cell sits in the middle of the board (the player would use two fingers).
      final z = board(tester).zoom!;
      final w = board(tester);
      final local = w.state.board.tiling.cellCenter(home, Size(w.width, w.height));
      z.set(z.zoom, Size(w.width, w.height).center(Offset.zero) - local * z.zoom);
      await settle(tester, 600);
    }
    expect(board(tester).state.selectedGroup, contains(from), reason: 'still selected after panning');
    await tester.tapAt(onScreen(tester, home));
    await settle(tester, 1200);
    final after = board(tester).state.board;
    expect(after.slots, isNot(equals(before.slots)), reason: 'the move happened');
    expect(after.isLocked(home), isTrue, reason: 'the card locked at home');
    await shot(tester, 'pg_09_giant_moved_zoomed');

    // Back to the whole board.
    await tester.tap(find.byKey(const ValueKey('zoom-whole-board')), warnIfMissed: false);
    await settle(tester, 900);
    expect(board(tester).zoom!.zoomed, isFalse);
    await shot(tester, 'pg_10_giant_whole_again');

    // Leave and resume the giant board.
    final moves = board(tester).state.moves;
    final layout = board(tester).state.board.slots.join(',');
    await tester.tap(find.byIcon(CupertinoIcons.pause_fill), warnIfMissed: false);
    await settle(tester, 900);
    await tapText(tester, 'Save & quit', ms: 2500);
    expect(container(tester).read(puzzleProgressProvider(target.id))!.layout!.join(','), layout);
    container(tester).read(routerProvider).push('/play/${target.id}');
    await settle(tester, 6000);
    expect(find.textContaining('Continue ·'), findsOneWidget);
    await shot(tester, 'pg_11_giant_resume_difficulty');
    await tester.tap(find.textContaining('Continue ·'), warnIfMissed: false);
    await settle(tester, 8000);
    expect(board(tester).state.board.spec, spec, reason: 'same giant board');
    expect(board(tester).state.moves, moves);
    expect(board(tester).state.board.slots.join(','), layout);
    await shot(tester, 'pg_12_giant_resumed');
    final settings = container(tester).read(settingsProvider);
    debugPrint('QA done (default grid ${settings.defaultGrid})');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
