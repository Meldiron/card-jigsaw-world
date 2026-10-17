// Twin cards on a shared board (docs/twins.md, docs/multiplayer.md): another player's change can
// hold a twin trade (on their screen the dropped card took its twin's identity and the twin kept
// its place). Put on this screen with `GameController.showShared`, the two cards must not fly across
// the board: their widgets stay where the mover's screen keeps them.
import 'dart:ui' as ui;

import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/game/board.dart';
import 'package:carden/game/game_controller.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _spec = BoardSpec.squareTiers(GameMode.cards)[1]; // 4x4

/// A 4x4 board dealt back to front: no card in place, no pair joined.
List<int> _reversed() => List.generate(16, (s) => 15 - s);

final _twins = Twins.fromClasses(16, [
  [0, 1],
]);

/// One screen: a controller on the shared layout with the twins measured.
(ProviderContainer, GameArgs) _screen(String id) {
  final c = ProviderContainer();
  final args = GameArgs(puzzleId: id, spec: _spec, layout: _reversed());
  c.listen(gameControllerProvider(args), (_, _) {});
  c.read(gameControllerProvider(args).notifier).useTwins(_twins);
  return (c, args);
}

/// The widget key of the card in each slot (the board keys a card's widget by `cardKeys`).
List<int> _widgetAtSlot(GameState s) => [for (final card in s.board.slots) s.cardKeys?[card] ?? card];

void main() {
  test('a twin trade made on another screen moves the same widgets here as there', () {
    final (a, argsA) = _screen('amy');
    final (b, argsB) = _screen('bob');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    // Amy drops card 1 (slot 14) on card 0's place: it takes card 0's identity, card 0's twin
    // stays where card 0 waited (slot 15).
    a.read(gameControllerProvider(argsA).notifier).drop(14, 0);
    final amy = a.read(gameControllerProvider(argsA));
    expect(amy.board.isLocked(0), isTrue);
    expect(amy.board.slots[15], 1);
    // Bob gets the change as a layout.
    b.read(gameControllerProvider(argsB).notifier).showShared(amy.board.slots);
    final bob = b.read(gameControllerProvider(argsB));
    expect(bob.board.slots, amy.board.slots);
    expect(bob.moves, 0);
    expect(_widgetAtSlot(bob), _widgetAtSlot(amy), reason: 'every widget where Amy\'s screen has it');
    expect(_widgetAtSlot(bob)[15], 0, reason: 'the twin that waited kept its widget');
    expect(_widgetAtSlot(bob)[0], 1, reason: 'the dropped card\'s widget is where it landed');
  });

  test('two twins exchanging places keep both widgets in place; other cards move as before', () {
    final (b, args) = _screen('bob');
    addTearDown(b.dispose);
    final ctrl = b.read(gameControllerProvider(args).notifier);
    final before = b.read(gameControllerProvider(args));
    final widgets = _widgetAtSlot(before);
    // Cards 0 (slot 15) and 1 (slot 14) trade places, and cards 2 and 3 too (not twins).
    final layout = List<int>.from(before.board.slots);
    layout[15] = 1;
    layout[14] = 0;
    layout[13] = 3;
    layout[12] = 2;
    ctrl.showShared(layout);
    final after = b.read(gameControllerProvider(args));
    expect(after.board.slots, layout);
    final now = _widgetAtSlot(after);
    expect(now[15], widgets[15]);
    expect(now[14], widgets[14]);
    expect(now[13], 3, reason: 'card 3\'s own widget moved to its new slot');
    expect(now[12], 2);
  });

  test('without twins measured here the widgets follow their cards', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final args = GameArgs(puzzleId: 'p', spec: _spec, layout: _reversed());
    c.listen(gameControllerProvider(args), (_, _) {});
    final layout = _reversed();
    layout[15] = 1;
    layout[14] = 0;
    c.read(gameControllerProvider(args).notifier).showShared(layout);
    expect(c.read(gameControllerProvider(args)).cardKeys, isNull);
  });

  testWidgets('on the board, a remote twin exchange leaves both cards\' widgets in place', (tester) async {
    final (b, args) = _screen('bob');
    final rec = ui.PictureRecorder();
    Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 250, 350), Paint()..color = const Color(0xFF6094DE));
    final image = rec.endRecording().toImageSync(250, 350);
    Widget board(GameState s) => MaterialApp(
          theme: AppTheme.light(),
          home: Center(
            child: BoardWidget(image: image, state: s, width: 250, height: 350, cardStyle: CardStyle.classic, onTap: (_) {}, onDrop: (_, _) {}),
          ),
        );
    await tester.pumpWidget(board(b.read(gameControllerProvider(args))));
    final origin = tester.getTopLeft(find.byType(BoardWidget));
    Offset at(int slot) => _spec.tiling.cellBounds(slot, const Size(250, 350)).topLeft;
    expect(tester.getTopLeft(find.byKey(const ValueKey('card-0'))) - origin, at(15));
    expect(tester.getTopLeft(find.byKey(const ValueKey('card-1'))) - origin, at(14));
    final card0 = tester.element(find.byKey(const ValueKey('card-0')));
    // The other player's screen sent cards 0 and 1 exchanging places.
    final layout = _reversed();
    layout[15] = 1;
    layout[14] = 0;
    b.read(gameControllerProvider(args).notifier).showShared(layout);
    await tester.pumpWidget(board(b.read(gameControllerProvider(args))));
    await tester.pump(const Duration(milliseconds: 16));
    // Mid-animation and after it, both widgets are where they were.
    expect(tester.getTopLeft(find.byKey(const ValueKey('card-0'))) - origin, at(15));
    expect(tester.getTopLeft(find.byKey(const ValueKey('card-1'))) - origin, at(14));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('card-0'))) - origin, at(15));
    expect(tester.getTopLeft(find.byKey(const ValueKey('card-1'))) - origin, at(14));
    expect(tester.element(find.byKey(const ValueKey('card-0'))), same(card0), reason: 'the same widget, now showing card 1');
    // The game's clock is a timer: gone with the controller, before the test ends.
    b.dispose();
  });
}
