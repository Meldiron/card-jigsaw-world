import 'dart:ui' as ui;

import 'package:carden/core/a11y.dart';
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/game/board.dart';
import 'package:carden/game/game_controller.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The picture before the deal and the tap that ends Peek (owner, 2026-10-17): a board dealt here
/// opens on its whole picture for a moment, then the cards glide to where they were dealt; a tap
/// skips it; it is not a Peek, not a move, and the clock waits for it. A tap during Peek sends the
/// cards back at once.
void main() {
  const spec = GridSpec(3, 3, 'Cozy', tier: 0);

  // Listened to, as the game screen does: the controller is kept while the time passes.
  GameController controllerFor(ProviderContainer c, GameArgs args) {
    c.listen(gameControllerProvider(args), (_, _) {});
    return c.read(gameControllerProvider(args).notifier);
  }

  testWidgets('a dealt board opens on its picture, then deals; free, not a Peek, the clock waits', (tester) async {
    final c = ProviderContainer();
    const args = GameArgs(puzzleId: 'p', spec: spec, preview: true);
    final ctrl = controllerFor(c, args);
    GameState s() => c.read(gameControllerProvider(args));
    expect(s().previewing, isTrue, reason: 'it waits for the board to be on screen');
    expect(s().showingPicture, isTrue);
    // Nothing is played while the picture shows.
    final slots = s().board.slots;
    ctrl.tap(0);
    ctrl.drop(0, 1);
    expect(s().selected, isNull);
    expect(s().board.slots, slots);
    expect(ctrl.shuffle(), 0);
    // On screen: the picture shows for a moment; the clock does not run meanwhile.
    ctrl.startPreview();
    await tester.pump(GameController.previewTime - const Duration(milliseconds: 100));
    expect(s().previewing, isTrue);
    await tester.pump(const Duration(milliseconds: 200));
    expect(s().previewing, isFalse, reason: 'the cards are dealt');
    expect(s().elapsed, 0, reason: 'the clock waited for it');
    expect(s().peeked, isFalse, reason: 'not a Peek (the "without Peek" quests)');
    expect(s().moves, 0);
    // Disposed inside the test: the clock's timer goes with it.
    c.dispose();
  });

  testWidgets('a tap ends the preview and Peek at once', (tester) async {
    final c = ProviderContainer();
    const args = GameArgs(puzzleId: 'p', spec: spec, preview: true);
    final ctrl = controllerFor(c, args);
    GameState s() => c.read(gameControllerProvider(args));
    ctrl.startPreview();
    await tester.pump(const Duration(milliseconds: 300));
    ctrl.endPeek();
    expect(s().previewing, isFalse, reason: 'skipped');
    ctrl.peek();
    expect(s().peeking, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    ctrl.endPeek();
    expect(s().peeking, isFalse, reason: 'the cards fly back now, not after the Peek time');
    expect(s().peeked, isTrue);
    // The Peek's own timer is gone: it does not end a later Peek early.
    ctrl.peek();
    await tester.pump(GameController.peekTime - const Duration(milliseconds: 100));
    expect(s().peeking, isTrue);
    await tester.pump(const Duration(milliseconds: 200));
    expect(s().peeking, isFalse);
    // Disposed inside the test: the clock's timer goes with it.
    c.dispose();
  });

  testWidgets('a resumed board never opens on the picture; a new deal of it can', (tester) async {
    final c = ProviderContainer();
    const args = GameArgs(puzzleId: 'p', spec: spec, layout: [1, 0, 2, 3, 4, 5, 6, 7, 8], moves: 3, preview: true);
    final ctrl = controllerFor(c, args);
    GameState s() => c.read(gameControllerProvider(args));
    expect(s().previewing, isFalse);
    ctrl.restart(preview: true);
    expect(s().previewing, isTrue, reason: 'Shuffle and restart, Replay');
    await tester.pump(GameController.previewTime + const Duration(milliseconds: 50));
    expect(s().previewing, isFalse, reason: 'on screen already: it ends by itself');
    // Disposed inside the test: the clock's timer goes with it.
    c.dispose();
  });

  group('on the board', () {
    ui.Image image() {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 300, 300), Paint()..color = const Color(0xFF808080));
      return rec.endRecording().toImageSync(300, 300);
    }

    GameState stateFor(Board board, {bool previewing = false}) => GameState(
          board: board,
          par: board.par,
          moves: 0,
          elapsed: 0,
          status: GameStatus.playing,
          selected: null,
          hintsUsed: 0,
          history: const [],
          justLocked: const {},
          justJoined: const {},
          hintSlot: null,
          hintTarget: null,
          peeking: false,
          chain: 0,
          tick: 0,
          previewing: previewing,
        );

    Future<void> pump(WidgetTester tester, ui.Image img, GameState state, {bool reduceMotion = false}) => tester.pumpWidget(MaterialApp(
          theme: AppTheme.light(),
          home: A11y(
            prefs: Accessibility(reduceMotion: reduceMotion),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: BoardWidget(image: img, state: state, onTap: (_) {}, onDrop: (_, _) {}, cardStyle: CardStyle.classic, width: 300, height: 300),
              ),
            ),
          ),
        ));

    testWidgets('the cards wait in their places, then glide to where they were dealt', (tester) async {
      final img = image();
      // Card 0 was dealt to the far corner (slot 8), card 8 to slot 0.
      final board = debugBoard(spec, const [8, 1, 2, 3, 4, 5, 6, 7, 0]);
      final tiling = board.tiling;
      const size = Size(300, 300);
      Offset at(int card) => tester.getTopLeft(find.byKey(ValueKey('card-$card')));
      await pump(tester, img, stateFor(board, previewing: true));
      expect(at(0), tiling.cellBounds(0, size).topLeft, reason: 'the picture: card 0 in its own place');
      await pump(tester, img, stateFor(board));
      await tester.pump(const Duration(milliseconds: 500));
      final mid = at(0);
      expect(mid, isNot(tiling.cellBounds(0, size).topLeft), reason: 'on its way');
      expect(mid, isNot(tiling.cellBounds(8, size).topLeft), reason: 'not there yet: it glides');
      await tester.pumpAndSettle();
      expect(at(0), tiling.cellBounds(8, size).topLeft, reason: 'dealt');
    });

    testWidgets('reduce motion: the picture fades into the dealt cards', (tester) async {
      final img = image();
      final board = debugBoard(spec, const [8, 1, 2, 3, 4, 5, 6, 7, 0]);
      await pump(tester, img, stateFor(board, previewing: true), reduceMotion: true);
      final fade = find.byKey(const ValueKey('deal-preview-fade'));
      expect(fade, findsOneWidget);
      await pump(tester, img, stateFor(board), reduceMotion: true);
      expect(tester.getTopLeft(find.byKey(const ValueKey('card-0'))), board.tiling.cellBounds(8, const Size(300, 300)).topLeft, reason: 'the cards jump under the picture');
      await tester.pump(const Duration(milliseconds: 200));
      final opacity = tester.widget<AnimatedOpacity>(find.descendant(of: fade, matching: find.byType(AnimatedOpacity)));
      expect(opacity.opacity, 0, reason: 'the picture fades out');
      await tester.pump(const Duration(seconds: 2));
      expect(fade, findsNothing);
    });
  });
}
