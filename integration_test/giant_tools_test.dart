// The giant board tools with the real Giant pack ("Colourful Houses") on the live backend: Peek's
// flight (10 coins, as on every board), the one-time Locate tip, a tapped card's place on the
// overview map, the Locate switch, no map while the map is off, Gather, the other shapes at their
// largest size, and Peek on a normal board.
//
// Run: tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//        --target=integration_test/giant_tools_test.dart -d <simulator>
import 'package:card_jigsaw_world/app.dart';
import 'package:card_jigsaw_world/core/sfx.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/features/game/board_widget.dart';
import 'package:card_jigsaw_world/features/game/giant_board.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/router.dart';
import 'package:card_jigsaw_world/state/catalog.dart';
import 'package:card_jigsaw_world/state/giant.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:card_jigsaw_world/state/profile.dart';
import 'package:card_jigsaw_world/state/rewards.dart';
import 'package:card_jigsaw_world/state/unlocks.dart';
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

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(CardJigsawApp)));
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

  testWidgets('giant boards: Peek, Locate, Gather', (tester) async {
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
        child: const CardJigsawApp(),
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

    // ---- Zoom in: the first zoom explains Locate (the map and Locate are on by default).
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

    // ---- Locate off: a tapped card is only selected; on again, it is located.
    await tester.tap(find.byKey(const ValueKey('giant-locate')), warnIfMissed: false);
    await settle(tester, 400);
    expect(container(tester).read(giantViewsProvider).locate, isFalse, reason: 'the switch is remembered');
    final second = loneCardInView();
    await tapSlot(tester, second, ms: 600);
    expect(board(tester).state.selected, second);
    expect(minimap().locate, isNull, reason: 'Locate is off');
    await shot(tester, 'gt_05_locate_off', wait: 0);
    await tester.tap(find.byKey(const ValueKey('giant-locate')), warnIfMissed: false);
    await settle(tester, 400);
    expect(minimap().locate, second, reason: 'Locate on again: the selected card shows');
    await tapSlot(tester, second, ms: 500); // deselect

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

    // ---- Gather: the cards that belong in view come into it.
    z.lookAt(boardSize(tester).center(Offset.zero));
    await settle(tester, 700);
    await shot(tester, 'gt_07_before_gather');
    final movesBefore = board(tester).state.moves;
    await tester.tap(find.byKey(const ValueKey('giant-gather')), warnIfMissed: false);
    await settle(tester, 300);
    final gatheredToast = find.textContaining('gathered').evaluate().isNotEmpty || find.text('Every card for this view is here').evaluate().isNotEmpty;
    expect(gatheredToast, isTrue);
    await shot(tester, 'gt_08_gathered', wait: 500);
    expect(board(tester).state.moves, movesBefore, reason: 'Gather is not a move');

    z.reset();
    await settle(tester, 700);
    await shot(tester, 'gt_09_whole_after_gather');
    await leaveBoard(tester);

    // ---- The other shapes at their largest giant size.
    var n = 3;
    for (final mode in ['Squares', 'Triangles', 'Hexagons']) {
      await openBoard(tester, pictures[n++], mode, 'Colossal');
      await shot(tester, 'gt_10_${mode.toLowerCase()}_whole');
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
    await shot(tester, 'gt_11_normal_board');
    final wallet = coins(tester);
    await peek(tester, 'gt_12', away: const Duration(milliseconds: 2400));
    expect(wallet - coins(tester), Economy.peekCostCoins);
    expect(Economy.peekCostCoins, 10);
    await leaveBoard(tester);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
