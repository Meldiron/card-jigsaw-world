// Giant boards with the real Giant pack ("Colourful Houses", 4096 px pictures) on the live
// backend: the size picker, the whole 306-card board, the zoom-in button and pinch to zoom (no
// double tap), the overview map, the pointer to a selected card out of view, auto-pan while dragging,
// resuming on the same view, every shape at its largest giant size (with frame timings), and a
// full solve of the smallest giant board with the frame and halfway milestones.
//
// Run: tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//        --target=integration_test/giant_ux_test.dart -d <simulator>
import 'dart:ui' as ui;

import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/models/models.dart';
import 'package:carden/router.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/giant.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/unlocks.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
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

const _packId = 'pack-colourful-houses';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, 500);
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
  Offset onScreen(WidgetTester tester, int slot) => boardRect(tester).topLeft + zoomOf(tester).toViewport(content(tester, slot));
  bool inView(WidgetTester tester, int slot) => (Offset.zero & boardSize(tester)).deflate(10).contains(zoomOf(tester).toViewport(content(tester, slot)));

  /// Taps [slot]; brings it into view first when the board is zoomed in and it is not.
  Future<void> tapSlot(WidgetTester tester, int slot, {int ms = 350}) async {
    if (!inView(tester, slot)) {
      zoomOf(tester).lookAt(content(tester, slot));
      await settle(tester, 120);
    }
    await tester.tapAt(onScreen(tester, slot));
    await settle(tester, ms);
  }

  /// Frame build and raster times over [run] (debug build on the simulator: an upper bound).
  Future<String> timings(WidgetTester tester, String label, Future<void> Function() run) async {
    final frames = <ui.FrameTiming>[];
    void collect(List<ui.FrameTiming> t) => frames.addAll(t);
    SchedulerBinding.instance.addTimingsCallback(collect);
    await run();
    await settle(tester, 600);
    SchedulerBinding.instance.removeTimingsCallback(collect);
    if (frames.isEmpty) return '$label: no frames';
    final build = [for (final f in frames) f.buildDuration.inMicroseconds / 1000]..sort();
    final raster = [for (final f in frames) f.rasterDuration.inMicroseconds / 1000]..sort();
    double p(List<double> v, double q) => v[((v.length - 1) * q).round()];
    final line =
        '$label: ${frames.length} frames, build median ${p(build, 0.5).toStringAsFixed(1)} ms p90 ${p(build, 0.9).toStringAsFixed(1)} max ${build.last.toStringAsFixed(1)}, '
        'raster median ${p(raster, 0.5).toStringAsFixed(1)} ms p90 ${p(raster, 0.9).toStringAsFixed(1)} max ${raster.last.toStringAsFixed(1)}';
    debugPrint('QA_TIMING $line');
    return line;
  }

  /// A two-finger pinch around [centre]: the fingers move from [from] apart to [to] apart.
  Future<void> pinch(WidgetTester tester, Offset centre, double from, double to) async {
    final a = await tester.startGesture(centre - Offset(from / 2, 0), pointer: 71);
    final b = await tester.startGesture(centre + Offset(from / 2, 0), pointer: 72);
    for (var i = 1; i <= 12; i++) {
      final d = from + (to - from) * i / 12;
      await a.moveTo(centre - Offset(d / 2, 0));
      await b.moveTo(centre + Offset(d / 2, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await settle(tester, 400);
  }

  /// Opens [puzzle] on the giant size [size] in [mode] from its difficulty screen.
  Future<void> openBoard(WidgetTester tester, Puzzle puzzle, String mode, String size) async {
    container(tester).read(routerProvider).push('/play/${puzzle.id}');
    await settle(tester, 6000);
    await tapText(tester, mode, ms: 800);
    await tester.dragUntilVisible(find.text(size), find.byType(Scrollable).first, const Offset(0, -200));
    await tapText(tester, size, ms: 800);
    await tester.tap(find.textContaining('· Play'), warnIfMissed: false);
    // 4096 px pictures: the full-size download and decode take a moment.
    for (var i = 0; i < 40 && find.byType(BoardWidget).evaluate().isEmpty; i++) {
      await settle(tester, 500);
    }
    await settle(tester, 1500);
    if (find.text('Got it').evaluate().isNotEmpty) await tapText(tester, 'Got it');
    expect(find.byType(BoardWidget), findsOneWidget);
    expect(board(tester).zoom, isNotNull, reason: 'giant boards zoom');
  }

  Future<void> leaveBoard(WidgetTester tester) async {
    await tester.tap(find.byIcon(CupertinoIcons.pause_fill), warnIfMissed: false);
    await settle(tester, 900);
    await tapText(tester, 'Save & quit', ms: 2500);
  }

  testWidgets('giant boards with the real Giant pack', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await FirstSteps.skipFor(store); // the whole app; integration_test/first_steps_test.dart plays the first steps
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          // Giant boards open at level 10 and the other shapes on the way there; this suite plays them all.
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

    // The QA guest gets the 12 tickets the pack costs and unlocks it like a player would.
    final packs = await container(tester).read(packsProvider.future);
    final pack = packs.firstWhere((p) => p.id == _packId);
    expect(isGiantPack(pack), isTrue);
    final profile = container(tester).read(profileProvider.notifier);
    await profile.addTickets(pack.priceTickets, reason: 'qa:giant');
    await settle(tester, 800);
    expect(await profile.unlockPack(pack), isTrue);
    final pictures = (await container(tester).read(allPuzzlesProvider.future)).where((p) => p.packId == _packId).toList();
    expect(pictures.length, greaterThanOrEqualTo(20));
    final results = <String>[];

    container(tester).read(routerProvider).push('/library/pack/$_packId');
    await settle(tester, 6000);
    await shot(tester, 'gx_01_pack');
    container(tester).read(routerProvider).pop();
    await settle(tester, 800);

    // ---- Cards, Colossal (306): the whole board, the zoom-in button, pinch, the close view.
    await openBoard(tester, pictures[0], 'Cards', 'Colossal');
    await shot(tester, 'gx_02_cards_colossal_whole');
    final z = zoomOf(tester);
    expect(z.zoomed, isFalse);
    debugPrint('QA_GIANT ${pictures[0].title}: ${board(tester).state.board.cells} cards, limit ${z.limit.toStringAsFixed(2)}x');


    // The zoom-in button: in by one step, nothing selected, the overview map in the corner.
    await tester.tap(find.byKey(const ValueKey('zoom-in')), warnIfMissed: false);
    await settle(tester, 900);
    expect(z.zoomed, isTrue);
    expect(board(tester).state.selected, isNull);
    expect(find.byKey(const ValueKey('giant-minimap')), findsOneWidget);
    await shot(tester, 'gx_04_zoom_button');

    // Pinch further in, to the board's limit: is the real picture sharp up close?
    results.add(await timings(tester, 'cards 306 pinch', () => pinch(tester, boardRect(tester).center, 80, 260)));
    z.zoomTo(z.limit);
    await settle(tester, 700);
    expect(z.zoom, closeTo(z.limit, 0.01));
    await shot(tester, 'gx_05_cards_max_zoom');

    // Select a card, look elsewhere: the pointer shows where it went; tapping it brings it back.
    final b1 = board(tester).state.board;
    final sel = List.generate(b1.cells, (i) => i).firstWhere((i) => !b1.isLocked(i) && inView(tester, i));
    await tapSlot(tester, sel);
    expect(board(tester).state.selected, sel);
    z.lookAt(Offset(boardSize(tester).width * 0.85, boardSize(tester).height * 0.85));
    await settle(tester, 600);
    expect(inView(tester, sel), isFalse);
    expect(find.byKey(const ValueKey('giant-offscreen-selection')), findsOneWidget);
    await shot(tester, 'gx_06_offscreen_pointer');
    await tester.tap(find.byKey(const ValueKey('giant-offscreen-selection')), warnIfMissed: false);
    await settle(tester, 700);
    expect(inView(tester, sel), isTrue);
    expect(board(tester).state.selected, sel, reason: 'still selected after travelling');
    await shot(tester, 'gx_07_back_to_selected');

    // The overview map: tap its bottom right corner, the view goes there.
    final map = tester.getRect(find.byKey(const ValueKey('giant-minimap')));
    await tester.tapAt(map.bottomRight - const Offset(8, 8));
    await settle(tester, 700);
    expect(z.visible.center.dx, greaterThan(boardSize(tester).width * 0.6));
    expect(z.visible.center.dy, greaterThan(boardSize(tester).height * 0.6));
    await shot(tester, 'gx_08_minimap_jump');

    // Drag a card to the left edge of the view and hold it there: the board slides under it.
    final b2 = board(tester).state.board;
    final dragSlot = List.generate(b2.cells, (i) => i).firstWhere((i) => !b2.isLocked(i) && inView(tester, i) && b2.groupOf(i).length == 1);
    final panBefore = z.pan;
    final g = await tester.startGesture(onScreen(tester, dragSlot));
    final edge = Offset(boardRect(tester).left + 12, onScreen(tester, dragSlot).dy);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(onScreen(tester, dragSlot), edge, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await settle(tester, 900);
    expect(z.pan.dx, greaterThan(panBefore.dx + 40), reason: 'auto-pan moved the view left');
    await shot(tester, 'gx_09_autopan_hold');
    await g.up();
    await settle(tester, 900);

    // Leave and come back: the board opens on the same view.
    final before = z.snapshot;
    await leaveBoard(tester);
    container(tester).read(routerProvider).push('/play/${pictures[0].id}');
    await settle(tester, 6000);
    await tester.tap(find.textContaining('Continue ·'), warnIfMissed: false);
    for (var i = 0; i < 40 && find.byType(BoardWidget).evaluate().isEmpty; i++) {
      await settle(tester, 500);
    }
    await settle(tester, 2000);
    final after = zoomOf(tester).snapshot;
    debugPrint('QA_VIEW before ${before.zoom} ${before.centre} after ${after.zoom} ${after.centre}');
    expect(after.zoom, closeTo(before.zoom, 0.02));
    expect((after.centre - before.centre).distance, lessThan(0.02));
    await shot(tester, 'gx_10_resumed_same_view');
    await leaveBoard(tester);

    // ---- The other shapes at their largest giant size: whole, Edges, zoomed with the map.
    var n = 1;
    for (final mode in ['Squares', 'Triangles', 'Hexagons']) {
      await openBoard(tester, pictures[n], mode, 'Colossal');
      final slug = mode.toLowerCase();
      debugPrint('QA_GIANT ${pictures[n].title} $mode: ${board(tester).state.board.cells} cards, limit ${zoomOf(tester).limit.toStringAsFixed(2)}x');
      await shot(tester, 'gx_11_${slug}_whole');
      results.add(
        await timings(tester, '$slug ${board(tester).state.board.cells} zoom', () async {
          zoomOf(tester).zoomTo(zoomOf(tester).step);
          await settle(tester, 500);
          await pinch(tester, boardRect(tester).center, 90, 200);
          zoomOf(tester).lookAt(boardSize(tester).center(Offset.zero) * 0.6);
          await settle(tester, 300);
        }),
      );
      // A move while zoomed in.
      final b = board(tester).state.board;
      final s = List.generate(b.cells, (i) => i).firstWhere((i) => !b.isLocked(i) && inView(tester, i));
      await tapSlot(tester, s);
      await tapSlot(tester, b.homeOf(s), ms: 900);
      expect(board(tester).state.board.isLocked(b.homeOf(s)) || board(tester).state.moves > 0, isTrue);
      await shot(tester, 'gx_13_${slug}_zoomed');
      await leaveBoard(tester);
      n++;
    }

    // ---- Full solve of the smallest giant size (Cards, Large) with the Edges filter first.
    await openBoard(tester, pictures[4], 'Cards', 'Large');
    await shot(tester, 'gx_14_large_whole');
    var frameSeen = false, halfSeen = false;
    Future<void> sendHome(int slot) async {
      final b = board(tester).state.board;
      if (b.isLocked(slot) || b.isSolved) return;
      final from = b.slotOfCard(slot);
      await tapSlot(tester, from, ms: 200);
      await tapSlot(tester, slot, ms: 450);
      if (!frameSeen && find.text('Frame complete').evaluate().isNotEmpty) {
        frameSeen = true;
        await shot(tester, 'gx_15_frame_complete');
      }
      if (!halfSeen && find.text('Halfway there').evaluate().isNotEmpty) {
        halfSeen = true;
        await shot(tester, 'gx_16_halfway');
      }
    }

    final first = board(tester).state.board;
    final edgeSlots = [
      for (var s = 0; s < first.cells; s++)
        if (isEdgeCard(first.tiling, s)) s,
    ];
    for (final s in edgeSlots) {
      await sendHome(s);
    }
    await settle(tester, 600);
    if (!frameSeen && find.text('Frame complete').evaluate().isNotEmpty) {
      frameSeen = true;
      await shot(tester, 'gx_15_frame_complete');
    }
    for (var guard = 0; guard < 400 && !board(tester).state.board.isSolved; guard++) {
      final b = board(tester).state.board;
      final slot = List.generate(b.cells, (i) => i).firstWhere((i) => !b.isLocked(i));
      await sendHome(slot);
    }
    await settle(tester, 3000);
    expect(find.text('Picture complete'), findsOneWidget);
    expect(frameSeen, isTrue, reason: 'the frame milestone showed');
    await shot(tester, 'gx_17_large_complete');
    expect(container(tester).read(giantViewsProvider).read(GiantViews.id(pictures[4].id, first.spec)), isNull, reason: 'a finished board forgets its view');

    for (final r in results) {
      debugPrint('QA_TIMING_SUMMARY $r');
    }
  }, timeout: const Timeout(Duration(minutes: 25)));
}
