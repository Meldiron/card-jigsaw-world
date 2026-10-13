import 'dart:ui' as ui;

import 'package:card_jigsaw_world/core/theme/app_theme.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/features/game/board_widget.dart';
import 'package:card_jigsaw_world/features/game/giant_board.dart';
import 'package:card_jigsaw_world/game/board.dart';
import 'package:card_jigsaw_world/game/game_controller.dart';
import 'package:card_jigsaw_world/state/giant.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The giant board tools: the zoom's limits and moves, the edge rule for every tiling, the saved
/// views, the double tap, the overview map and the milestones.
void main() {
  ui.Image picture(int w, int h) {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    const colours = [Color(0xFFD9480F), Color(0xFF2F9E44), Color(0xFF1971C2), Color(0xFFF08C00)];
    for (var i = 0; i < 16; i++) {
      canvas.drawRect(Rect.fromLTWH(0, h * i / 16, w.toDouble(), h / 16 + 1), Paint()..color = colours[i % colours.length]);
    }
    return rec.endRecording().toImageSync(w, h);
  }

  GameState stateFor(Board board, {int? selected}) => GameState(
        board: board,
        par: board.par,
        moves: 0,
        elapsed: 0,
        status: GameStatus.playing,
        selected: selected,
        hintsUsed: 0,
        history: const [],
        justLocked: const {},
        justJoined: const {},
        hintSlot: null,
        hintTarget: null,
        peeking: false,
        chain: 0,
        tick: 0,
      );

  group('BoardZoom', () {
    late BoardZoom zoom;
    setUp(() {
      zoom = BoardZoom(vsync: const TestVSync())..viewport = const Size(360, 480);
    });
    tearDown(() => zoom.dispose());

    test('the zoom limit follows the card size: smaller giant boards stop earlier', () {
      zoom.fitCell(20); // a 300-card board: 96 / 20 = 4.8, capped at 4
      expect(zoom.limit, BoardZoom.maxZoom);
      zoom.fitCell(36); // a 100-card board
      expect(zoom.limit, closeTo(96 / 36, 1e-9));
      expect(zoom.step, BoardZoom.stepZoom);
      zoom.fitCell(44);
      expect(zoom.step, closeTo(96 / 44, 1e-9), reason: 'the step never passes the limit');
      zoom.fitCell(80); // never below 2x
      expect(zoom.limit, 2);
      zoom.set(9, Offset.zero);
      expect(zoom.zoom, 2);
    });

    test('the board always covers the view, whatever the move', () {
      zoom.set(2, const Offset(500, 500));
      expect(zoom.pan, Offset.zero);
      final moved = zoom.panBy(const Offset(-10000, -10000));
      expect(zoom.pan, const Offset(-360, -480));
      expect(moved, const Offset(-360, -480));
      expect(zoom.panBy(const Offset(-5, -5)), Offset.zero, reason: 'already at the far corner');
      zoom.lookAt(const Offset(180, 240));
      expect(zoom.visible.center, const Offset(180, 240));
      zoom.lookAt(const Offset(-50, -50));
      expect(zoom.pan, Offset.zero);
    });

    test('the visible rectangle and viewport mapping agree', () {
      zoom.set(3, const Offset(-360, -480));
      expect(zoom.visible, const Rect.fromLTWH(120, 160, 120, 160));
      expect(zoom.toViewport(const Offset(120, 160)), Offset.zero);
      expect(zoom.toViewport(const Offset(240, 320)), const Offset(360, 480));
    });

    test('a saved view restores to the same part of the picture on another screen size', () {
      zoom.set(2.5, Offset.zero);
      zoom.lookAt(const Offset(90, 300));
      final saved = zoom.snapshot;
      expect(saved.zoom, 2.5);
      final other = BoardZoom(vsync: const TestVSync());
      addTearDown(other.dispose);
      other.restore(saved.zoom, saved.centre); // before its first layout: applied with the size
      expect(other.zoom, 1);
      other.viewport = const Size(400, 533.3333);
      expect(other.zoom, 2.5);
      final c = other.visible.center;
      expect(c.dx / 400, closeTo(90 / 360, 1e-3));
      expect(c.dy / 533.3333, closeTo(300 / 480, 1e-3));
    });
  });

  test('edge cards: every tiling marks exactly the cells on the board outline', () {
    final cards = BoardSpec.giantTiers(GameMode.cards).first;
    final t = cards.tiling;
    final edges = [for (var s = 0; s < cards.cells; s++) if (isEdgeCard(t, s)) s];
    expect(edges.length, 2 * (cards.cols + cards.rows) - 4);
    for (final mode in GameMode.values) {
      final spec = BoardSpec.giantTiers(mode).last;
      final count = [for (var s = 0; s < spec.cells; s++) if (isEdgeCard(spec.tiling, s)) s].length;
      expect(count, greaterThan(0), reason: mode.code);
      expect(count, lessThan(spec.cells ~/ 2), reason: '${mode.code}: the frame is a minority of the board');
    }
  });

  group('GiantViews', () {
    late GiantViews views;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      views = GiantViews(await LocalStore.open());
    });

    test('write, read and clear one view per picture, shape and size', () {
      final spec = BoardSpec.giantTiers(GameMode.cards).first;
      final id = GiantViews.id('p1', spec);
      expect(views.read(id), isNull);
      views.write(id, (zoom: 2.5, centre: const Offset(0.25, 0.75)));
      expect(views.read(id), (zoom: 2.5, centre: const Offset(0.25, 0.75)));
      expect(views.read(GiantViews.id('p1', BoardSpec.giantTiers(GameMode.squares).first)), isNull);
      views.clear(id);
      expect(views.read(id), isNull);
    });

    test('keeps the newest views only', () {
      for (var i = 0; i < GiantViews.keep + 5; i++) {
        views.write('p$i', (zoom: 2, centre: const Offset(0.5, 0.5)));
      }
      expect(views.read('p0'), isNull);
      expect(views.read('p4'), isNull);
      expect(views.read('p5'), isNotNull);
      expect(views.read('p${GiantViews.keep + 4}'), isNotNull);
    });

    test('the overview map is on until switched off', () {
      expect(views.showMap, isTrue);
      views.showMap = false;
      expect(views.showMap, isFalse);
    });
  });

  group('giant board widget', () {
    Future<(BoardZoom, List<int>)> pumpBoard(WidgetTester tester, Board board, {int? selected, bool edges = false}) async {
      final zoom = BoardZoom(vsync: const TestVSync());
      addTearDown(zoom.dispose);
      final taps = <int>[];
      final size = board.tiling.fit(const Size(360, 520), BoardSpec.referenceAspect);
      var state = stateFor(board, selected: selected);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => BoardWidget(
                image: picture(1200, 1600),
                state: state,
                width: size.width,
                height: size.height,
                cardStyle: CardStyle.classic,
                zoom: zoom,
                edges: edges,
                onDrop: (_, _) {},
                onTap: (slot) {
                  taps.add(slot);
                  // The controller's rule: tap selects, tap again deselects.
                  setState(() => state = stateFor(board, selected: state.selected == slot ? null : slot));
                },
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return (zoom, taps);
    }

    Offset slotOnScreen(WidgetTester tester, Board board, BoardZoom zoom, int slot) {
      final rect = tester.getRect(find.byType(BoardWidget));
      final w = tester.widget<BoardWidget>(find.byType(BoardWidget));
      return rect.topLeft + zoom.toViewport(board.tiling.cellCenter(slot, Size(w.width, w.height)));
    }

    testWidgets('double tap zooms in at the card, leaves the selection as it was, and zooms back out', (tester) async {
      final spec = BoardSpec.giantTiers(GameMode.cards).first;
      final board = Board.shuffled(spec, seed: 3);
      final (zoom, taps) = await pumpBoard(tester, board);
      final slot = List.generate(board.cells, (i) => i).firstWhere((i) => !board.isLocked(i));
      final at = slotOnScreen(tester, board, zoom, slot);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(zoom.zoomed, isTrue);
      expect(zoom.zoom, closeTo(zoom.step, 1e-6));
      // Selected by the first tap, deselected again for the double tap.
      expect(taps, [slot, slot]);
      expect(tester.widget<BoardWidget>(find.byType(BoardWidget)).state.selected, isNull);
      // The card that was double-tapped stays under the finger.
      expect((slotOnScreen(tester, board, zoom, slot) - at).distance, lessThan(2));

      final again = slotOnScreen(tester, board, zoom, slot);
      await tester.tapAt(again);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(again);
      await tester.pumpAndSettle();
      expect(zoom.zoomed, isFalse);
    });

    testWidgets('two taps on different cards are a move, never a double tap', (tester) async {
      final spec = BoardSpec.giantTiers(GameMode.cards).first;
      final board = Board.shuffled(spec, seed: 5);
      final (zoom, taps) = await pumpBoard(tester, board);
      final free = List.generate(board.cells, (i) => i).where((i) => !board.isLocked(i)).take(2).toList();
      await tester.tapAt(slotOnScreen(tester, board, zoom, free[0]));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(slotOnScreen(tester, board, zoom, free[1]));
      await tester.pumpAndSettle();
      expect(taps, free);
      expect(zoom.zoomed, isFalse);
    });

    testWidgets('normal boards never zoom on a double tap', (tester) async {
      final spec = BoardSpec.tiers(GameMode.cards)[2];
      final board = Board.shuffled(spec, seed: 2);
      final taps = <int>[];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: BoardWidget(
              image: picture(900, 1200),
              state: stateFor(board),
              width: 300,
              height: 400,
              cardStyle: CardStyle.classic,
              onDrop: (_, _) {},
              onTap: taps.add,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(BoardWidget));
      final at = rect.topLeft + board.tiling.cellCenter(0, const Size(300, 400));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(taps, [0, 0], reason: 'both taps reach the game as before');
    });

    testWidgets('the overview map moves the view where it is tapped', (tester) async {
      final spec = BoardSpec.giantTiers(GameMode.cards).last;
      final board = Board.shuffled(spec, seed: 7);
      final zoom = BoardZoom(vsync: const TestVSync())..viewport = const Size(360, 480);
      addTearDown(zoom.dispose);
      zoom.set(3, Offset.zero);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: GiantMinimap(image: picture(1200, 1600), board: board, boardSize: const Size(360, 480), zoom: zoom, width: 120, selected: 4),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final map = tester.getRect(find.byKey(const ValueKey('giant-minimap')));
      // The map's inner area starts 3 px in; tap three quarters of the way across and down.
      await tester.tapAt(map.topLeft + const Offset(3, 3) + const Offset(90, 120));
      await tester.pumpAndSettle();
      expect(zoom.visible.center.dx, closeTo(270, 1));
      expect(zoom.visible.center.dy, closeTo(360, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('milestones: the frame, then halfway, each once', (tester) async {
      final spec = BoardSpec.giantTiers(GameMode.cards).first;
      var board = Board.shuffled(spec, seed: 9);
      late StateSetter set;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: StatefulBuilder(builder: (context, s) {
            set = s;
            return GiantMilestones(board: board, playing: true);
          }),
        ),
      ));
      Board sendHome(Board b, Iterable<int> slots) {
        for (final s in slots) {
          if (!b.isLocked(s)) b = b.swap(s, b.slotOfCard(s));
        }
        return b;
      }

      final edge = [for (var s = 0; s < board.cells; s++) if (isEdgeCard(board.tiling, s)) s];
      // A toast stays two seconds after it has slid in; step the clock frame by frame.
      Future<void> wait(int ms) async {
        for (var t = 0; t < ms; t += 100) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      set(() => board = sendHome(board, edge));
      await wait(400);
      expect(find.text('Frame complete'), findsOneWidget);
      await wait(3500);
      expect(find.byType(SnackBar), findsNothing);
      set(() => board = sendHome(board, List.generate(board.cells ~/ 2 + 1, (i) => i)));
      await wait(400);
      expect(find.text('Halfway there'), findsOneWidget);
      // Nothing more on later moves.
      await wait(3500);
      set(() => board = sendHome(board, List.generate(board.cells - 2, (i) => i)));
      await wait(400);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
