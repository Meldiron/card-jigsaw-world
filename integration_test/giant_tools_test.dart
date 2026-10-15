// The giant board tools with the real Giant pack ("Colourful Houses") on the live backend: Peek's
// flight (10 coins, as on every board), the one-time Locate tip, a tapped card's place on the
// overview map (always on, no switch), no map while the map is off, no double tap, Gather zoomed
// in and its shuffle on the whole board, Magic on the selected card, the other shapes at their
// largest size, and Peek on a normal board.
//
// Run: tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//        --target=integration_test/giant_tools_test.dart -d <simulator>
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/features/game/giant_board.dart';
import 'package:carden/models/models.dart';
import 'package:carden/router.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/rewards.dart';
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
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The Giant pack played (QA_GIANT_PACK=pack-treasure-trove to try another).
const _packId = String.fromEnvironment('QA_GIANT_PACK', defaultValue: 'pack-colourful-houses');

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
  BoardWidget board(WidgetTester tester) => tester.widget<BoardWidget>(find.byType(BoardWidget).first);
  BoardZoom zoomOf(WidgetTester tester) => board(tester).zoom!;
  Rect boardRect(WidgetTester tester) => tester.getRect(find.byType(BoardWidget).first);
  Size boardSize(WidgetTester tester) => Size(board(tester).width, board(tester).height);
  Offset content(WidgetTester tester, int slot) => board(tester).state.board.tiling.cellCenter(slot, boardSize(tester));
  Offset onScreen(WidgetTester tester, int slot) {
    final z = board(tester).zoom;
    return boardRect(tester).topLeft + (z == null ? content(tester, slot) : z.toViewport(content(tester, slot)));
  }

  bool inView(WidgetTester tester, int slot) => (Offset.zero & boardSize(tester)).deflate(10).contains(zoomOf(tester).toViewport(content(tester, slot)));
  int coins(WidgetTester tester) => container(tester).read(profileProvider).value?.coins ?? 0;

  Future<void> tapSlot(WidgetTester tester, int slot, {int ms = 350}) async {
    if (board(tester).zoom != null && !inView(tester, slot)) {
      zoomOf(tester).lookAt(content(tester, slot));
      await settle(tester, 150);
    }
    await tester.tapAt(onScreen(tester, slot));
    await settle(tester, ms);
  }

  Future<void> openBoard(WidgetTester tester, Puzzle puzzle, String mode, String size) async {
    container(tester).read(routerProvider).push('/play/${puzzle.id}');
    await settle(tester, 6000);
    await tapText(tester, mode, ms: 800);
    await tester.dragUntilVisible(find.text(size), find.byType(Scrollable).first, const Offset(0, -200));
    await tapText(tester, size, ms: 800);
    await tester.tap(find.textContaining('· Play'), warnIfMissed: false);
    for (var i = 0; i < 40 && find.byType(BoardWidget).evaluate().isEmpty; i++) {
      await settle(tester, 500);
    }
    await settle(tester, 1500);
    if (find.text('Got it').evaluate().isNotEmpty) await tapText(tester, 'Got it');
    expect(find.byType(BoardWidget), findsOneWidget);
  }

  Future<void> leaveBoard(WidgetTester tester) async {
    await tester.tap(find.byIcon(CupertinoIcons.pause_fill), warnIfMissed: false);
    await settle(tester, 900);
    await tapText(tester, 'Save & quit', ms: 2500);
  }

  /// Taps Peek and captures the flight there, the picture, and the flight back.
  Future<void> peek(WidgetTester tester, String prefix, {required Duration away}) async {
    // A card far from its place: where it is drawn before, during and after the flight.
    final b = board(tester).state.board;
    final far = List.generate(b.cells, (i) => i).where((i) => !b.isLocked(i)).reduce((x, y) =>
        (b.tiling.cellCenter(x, boardSize(tester)) - b.tiling.cellCenter(b.homeOf(x), boardSize(tester))).distance >=
                (b.tiling.cellCenter(y, boardSize(tester)) - b.tiling.cellCenter(b.homeOf(y), boardSize(tester))).distance
            ? x
            : y);
    final card = find.byKey(ValueKey('card-${b.slots[far]}'));
    final start = tester.getTopLeft(card);
    debugPrint('QA_PEEK_AT ${DateTime.now().millisecondsSinceEpoch} $prefix');
    await tester.tap(find.byKey(const ValueKey('booster-peek')), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 150));
    final mid = tester.getTopLeft(card);
    await settle(tester, 1000);
    final end = tester.getTopLeft(card);
    debugPrint('QA_PEEK_FLIGHT $prefix start $start mid $mid end $end');
    expect((mid - start).distance, greaterThan(1), reason: 'the card is on its way after 150 ms');
    expect((end - mid).distance, greaterThan(1), reason: 'and not there yet: it flies, it does not jump');
    expect(board(tester).state.peeking, isTrue, reason: 'Peek started');
    await shot(tester, '${prefix}b_picture', wait: 0);
    await settle(tester, away.inMilliseconds - 1300);
    await settle(tester, 260);
    await shot(tester, '${prefix}c_flight_back', wait: 0);
    await settle(tester, 1200);
    expect(board(tester).state.peeking, isFalse);
    await shot(tester, '${prefix}d_back', wait: 0);
  }

  testWidgets('giant boards: Peek, Locate, Gather and its shuffle, Magic', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          openFeaturesProvider.overrideWithValue(OpenFeatures.all),
          pendingUnlockIntroProvider.overrideWithValue(null),
        ],
        child: const CardenApp(),
      ),
    );
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 5000);

    final packs = await container(tester).read(packsProvider.future);
    final pack = packs.firstWhere((p) => p.id == _packId);
    final profile = container(tester).read(profileProvider.notifier);
    await profile.addTickets(pack.priceTickets, reason: 'qa:giant');
    await settle(tester, 800);
    expect(await profile.unlockPack(pack), isTrue);
    final all = await container(tester).read(allPuzzlesProvider.future);
    final pictures = all.where((p) => p.packId == _packId).toList();

    // ---- Cards, Colossal: the whole board.
    await openBoard(tester, pictures[2], 'Cards', 'Colossal');
    final spec = board(tester).state.board.spec;
    debugPrint('QA_GIANT ${spec.code}: ${spec.cells} cards');
    await shot(tester, 'gt_01_colossal_whole');

    // ---- Peek on a giant board: 10 coins, the cards fly home and back.
    final before = coins(tester);
    expect(before, greaterThanOrEqualTo(Economy.peekCostCoins));
    await peek(tester, 'gt_02', away: const Duration(milliseconds: 3200));
    expect(before - coins(tester), Economy.peekCostCoins, reason: 'Peek costs the same on a giant board');
    expect(board(tester).state.peeked, isTrue);

    // ---- Zoom in: the first zoom explains Locate (the map is on by default).
    final z = zoomOf(tester);
    z.zoomTo(z.step, focal: boardRect(tester).size.center(Offset.zero) * 0.6);
    await settle(tester, 900);
    expect(find.byType(GiantMinimap), findsOneWidget);
    expect(find.text('Tap a card to see its place on the map'), findsOneWidget);
    await shot(tester, 'gt_03_zoomed_tip', wait: 0);
    await settle(tester, 3500);

    int loneCardInView() {
      final b = board(tester).state.board;
      return List.generate(b.cells, (i) => i).firstWhere((i) => !b.isLocked(i) && inView(tester, i) && b.groupOf(i).length == 1);
    }

    GiantMinimap minimap() => tester.widget<GiantMinimap>(find.byType(GiantMinimap));

    // ---- Tap a card: the map shows a ring where it belongs and a line to it.
    final picked = loneCardInView();
    await tapSlot(tester, picked, ms: 700);
    expect(board(tester).state.selected, picked);
    expect(minimap().locate, picked, reason: 'the tapped card is located on the map');
    await shot(tester, 'gt_04_tap_locate', wait: 0);
    // Moving it clears the marker.
    await tapSlot(tester, board(tester).state.board.homeOf(picked), ms: 900);
    expect(board(tester).state.selected, isNull);
    expect(minimap().locate, isNull);

    // ---- No Locate switch and no zoom hint in the bar: Locate is always on, with the map.
    expect(find.byKey(const ValueKey('giant-locate')), findsNothing);
    expect(find.textContaining('double-tap'), findsNothing);

    // ---- No double tap: two quick taps on a card select and deselect it; the zoom stays.
    final zoomBefore = z.zoom;
    final twice = loneCardInView();
    await tester.tapAt(onScreen(tester, twice));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(onScreen(tester, twice));
    await settle(tester, 900);
    expect(z.zoom, closeTo(zoomBefore, 1e-6), reason: 'taps never zoom');
    expect(board(tester).state.selected, isNull);

    // ---- The map off: tapping a card never brings it back.
    await tester.tap(find.byKey(const ValueKey('giant-map')), warnIfMissed: false);
    await settle(tester, 500);
    expect(find.byType(GiantMinimap), findsNothing);
    final third = loneCardInView();
    await tapSlot(tester, third, ms: 700);
    expect(board(tester).state.selected, third);
    expect(find.byType(GiantMinimap), findsNothing, reason: 'the map stays off');
    await shot(tester, 'gt_06_map_off_selected', wait: 0);
    await tapSlot(tester, third, ms: 500); // deselect
    await tester.tap(find.byKey(const ValueKey('giant-map')), warnIfMissed: false);
    await settle(tester, 500);
    expect(find.byType(GiantMinimap), findsOneWidget);

    // ---- Gather: the cards that belong in view come into it (or, if they are here, a shuffle).
    z.lookAt(boardSize(tester).center(Offset.zero));
    await settle(tester, 700);
    await shot(tester, 'gt_07_before_gather');
    final movesBefore = board(tester).state.moves;
    await tester.tap(find.byKey(const ValueKey('giant-gather')), warnIfMissed: false);
    await settle(tester, 300);
    expect(find.textContaining('gathered').evaluate().isNotEmpty || find.textContaining('here or nearby').evaluate().isNotEmpty, isTrue);
    await shot(tester, 'gt_08_gathered', wait: 500);
    expect(board(tester).state.moves, movesBefore, reason: 'Gather is not a move');
    await settle(tester, 2500);

    // ---- Magic with a card selected puts that exact card in its place.
    final chosen = loneCardInView();
    final chosenCard = board(tester).state.board.slots[chosen];
    final wallet0 = coins(tester);
    await tapSlot(tester, chosen, ms: 500);
    expect(board(tester).state.selected, chosen);
    await tester.tap(find.byKey(const ValueKey('booster-magic')), warnIfMissed: false);
    await settle(tester, 1500);
    expect(board(tester).state.board.slots[chosenCard], chosenCard, reason: 'the selected card went to its place');
    expect(wallet0 - coins(tester), Economy.magicLockCostCoins);
    await shot(tester, 'gt_09_magic_selected');

    // ---- The whole board: Gather is there too; everything belongs in view, so the loose cards
    // are shuffled, and cards in place and joined groups stay where they are.
    z.reset();
    await settle(tester, 900);
    expect(find.byKey(const ValueKey('giant-gather')), findsOneWidget);
    final b0 = board(tester).state.board;
    await shot(tester, 'gt_10_whole_before_shuffle', wait: 0);
    await tester.tap(find.byKey(const ValueKey('giant-gather')), warnIfMissed: false);
    await settle(tester, 400);
    expect(find.text('Every card for this view is here or nearby. The loose ones were shuffled.'), findsOneWidget);
    final b1 = board(tester).state.board;
    var movedLoose = 0;
    for (var s = 0; s < b0.cells; s++) {
      final fixed = b0.isLocked(s) || b0.groupOf(s).length > 1;
      if (fixed) expect(b1.slots[s], b0.slots[s], reason: 'slot $s is in place or joined');
      if (!fixed && b1.slots[s] != b0.slots[s]) movedLoose++;
    }
    debugPrint('QA_SHUFFLE ${b0.cells} cards, ${b0.lockedCount} in place, $movedLoose loose cards moved');
    expect(movedLoose, greaterThan(b0.cells ~/ 2));
    expect(b1.lockedCount, b0.lockedCount, reason: 'the shuffle never puts a card in place');
    expect(b1.joinCount, b0.joinCount, reason: 'the shuffle joins no new pair');
    await shot(tester, 'gt_11_whole_shuffled', wait: 600);
    await leaveBoard(tester);

    // ---- The other shapes at their largest giant size.
    var n = 3;
    for (final mode in ['Squares', 'Triangles', 'Hexagons']) {
      await openBoard(tester, pictures[n++], mode, 'Colossal');
      await shot(tester, 'gt_12_${mode.toLowerCase()}_whole');
      await leaveBoard(tester);
    }

    // ---- A normal board: Peek costs 10 coins and flies the same way.
    final normal = all.firstWhere((p) => p.packId != _packId && !p.isLockedByDate && (packs.where((k) => k.id == p.packId).firstOrNull?.isFree ?? false));
    container(tester).read(routerProvider).push('/play/${normal.id}');
    await settle(tester, 5000);
    await tester.tap(find.textContaining('· Play'), warnIfMissed: false);
    for (var i = 0; i < 30 && find.byType(BoardWidget).evaluate().isEmpty; i++) {
      await settle(tester, 500);
    }
    await settle(tester, 1500);
    if (find.text('Got it').evaluate().isNotEmpty) await tapText(tester, 'Got it');
    expect(board(tester).zoom, isNull);
    await shot(tester, 'gt_13_normal_board');
    final wallet = coins(tester);
    await peek(tester, 'gt_14', away: const Duration(milliseconds: 2400));
    expect(wallet - coins(tester), Economy.peekCostCoins);
    expect(Economy.peekCostCoins, 10);
    await leaveBoard(tester);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
