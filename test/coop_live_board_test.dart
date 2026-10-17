// The board's side of live drags in Play together (docs/multiplayer.md, "Live picks and drags"):
// another player's dragged card is drawn where their finger is, with its group, in their colour and
// with their initial, and goes to its slot (gliding) when the drag is over; this player's drags are
// reported as fractions of the board.
import 'dart:ui' as ui;

import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/features/coop/coop_players.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/game/board.dart';
import 'package:carden/game/game_controller.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _spec = BoardSpec.squareTiers(GameMode.cards)[1]; // 4x4
const _size = Size(240, 320);

/// A 4x4 board dealt back to front: no card in place, no pair joined.
List<int> _reversed() => List.generate(16, (s) => 15 - s);

const _mark = CoopCardMark(userId: 'amy', initial: 'A', color: Color(0xFFE07A2F), onColor: Colors.white, held: true);

void main() {
  late ui.Image image;
  setUpAll(() {
    final rec = ui.PictureRecorder();
    Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 240, 320), Paint()..color = const Color(0xFF6094DE));
    image = rec.endRecording().toImageSync(240, 320);
  });

  GameState stateOf(List<int> layout) {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final args = GameArgs(puzzleId: 'p', spec: _spec, layout: layout);
    final s = c.read(gameControllerProvider(args));
    // The game's clock is a timer: stop it with the container, before the test ends.
    c.dispose();
    return s;
  }

  Widget board(GameState s, {ValueNotifier<Map<int, CoopGhost>>? ghosts, void Function(int, Offset, bool)? onDragMove, void Function(int)? onDragEnd, void Function(int, int)? onDrop}) => MaterialApp(
        theme: AppTheme.light(),
        home: Align(
          alignment: Alignment.topLeft,
          child: BoardWidget(
            image: image,
            state: s,
            width: _size.width,
            height: _size.height,
            cardStyle: CardStyle.classic,
            onTap: (_) {},
            onDrop: onDrop ?? (_, _) {},
            ghosts: ghosts,
            onDragMove: onDragMove,
            onDragEnd: onDragEnd,
          ),
        ),
      );

  Offset fraction(int slot) {
    final c = _spec.tiling.cellCenter(slot, _size);
    return Offset(c.dx / _size.width, c.dy / _size.height);
  }

  testWidgets('another player\'s dragged card is drawn where their finger is, then glides to its slot', (tester) async {
    final s = stateOf(_reversed());
    final ghosts = ValueNotifier<Map<int, CoopGhost>>(const {});
    await tester.pumpWidget(board(s, ghosts: ghosts));
    final origin = tester.getTopLeft(find.byType(BoardWidget));
    Offset topLeftOf(int card) => tester.getTopLeft(find.byKey(ValueKey('card-$card'))) - origin;
    // Card 15 is in slot 0; Amy has it over slot 10.
    expect(topLeftOf(15), _spec.tiling.cellBounds(0, _size).topLeft);
    ghosts.value = {15: CoopGhost(card: 15, at: fraction(10), mark: _mark)};
    await tester.pump();
    expect(topLeftOf(15), _spec.tiling.cellBounds(10, _size).topLeft);
    expect(find.byKey(const ValueKey('coop-drag-15')), findsOneWidget, reason: 'her initial on it');
    // Halfway to slot 5: drawn there at once (the play-back already glides).
    final half = (fraction(10) + fraction(5)) / 2;
    ghosts.value = {15: CoopGhost(card: 15, at: half, mark: _mark)};
    await tester.pump();
    final between = (_spec.tiling.cellBounds(10, _size).topLeft + _spec.tiling.cellBounds(5, _size).topLeft) / 2;
    expect((topLeftOf(15) - between).distance, lessThan(0.01));
    // Her drag is over (cancelled): the card glides back to its slot.
    ghosts.value = const {};
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final gliding = topLeftOf(15);
    expect(gliding, isNot(between));
    expect(gliding, isNot(_spec.tiling.cellBounds(0, _size).topLeft));
    await tester.pumpAndSettle();
    expect(topLeftOf(15), _spec.tiling.cellBounds(0, _size).topLeft);
    expect(find.byKey(const ValueKey('coop-drag-15')), findsNothing);
  });

  testWidgets('a dragged card takes its joined group along; a card in place is never lifted', (tester) async {
    // Cards 0 and 1 joined in slots 5 and 6; card 4 in place in slot 4.
    final layout = List<int>.filled(16, -1);
    layout[5] = 0;
    layout[6] = 1;
    layout[4] = 4;
    final rest = [for (var c = 0; c < 16; c++) if (!layout.contains(c)) c];
    for (var s = 0, i = 0; s < 16; s++) {
      if (layout[s] < 0) layout[s] = rest[i++];
    }
    final st = stateOf(layout);
    expect(st.board.groupOf(5).toSet(), {5, 6});
    final ghosts = ValueNotifier<Map<int, CoopGhost>>(const {});
    await tester.pumpWidget(board(st, ghosts: ghosts));
    final origin = tester.getTopLeft(find.byType(BoardWidget));
    Offset topLeftOf(int card) => tester.getTopLeft(find.byKey(ValueKey('card-$card'))) - origin;
    final delta = _spec.tiling.cellBounds(9, _size).topLeft - _spec.tiling.cellBounds(5, _size).topLeft;
    ghosts.value = {
      0: CoopGhost(card: 0, at: fraction(9), mark: _mark),
      4: CoopGhost(card: 4, at: fraction(15), mark: _mark),
    };
    await tester.pump();
    expect(topLeftOf(0), _spec.tiling.cellBounds(5, _size).topLeft + delta);
    expect(topLeftOf(1), _spec.tiling.cellBounds(6, _size).topLeft + delta, reason: 'its group comes along');
    expect(topLeftOf(4), _spec.tiling.cellBounds(4, _size).topLeft, reason: 'in place: not lifted');
    expect(find.byKey(const ValueKey('coop-drag-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('coop-drag-1')), findsNothing, reason: 'one initial for the group');
  });

  testWidgets('a moved card\'s mark fades out and carries no initial; a held card keeps its outline and initial', (tester) async {
    final s = stateOf(_reversed());
    final since = DateTime.now();
    final moved = CoopCardMark(userId: 'amy', initial: 'A', color: const Color(0xFFE07A2F), onColor: Colors.white, held: false, badge: false, since: since, fadeFor: const Duration(milliseconds: 1500));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Align(
        alignment: Alignment.topLeft,
        child: BoardWidget(image: image, state: s, width: _size.width, height: _size.height, cardStyle: CardStyle.classic, onTap: (_) {}, onDrop: (_, _) {}, marks: {3: moved, 7: _mark}),
      ),
    ));
    double opacity() => tester.widget<FadeTransition>(find.ancestor(of: find.byKey(const ValueKey('coop-moved-3')), matching: find.byType(FadeTransition)).first).opacity.value;
    expect(find.byKey(const ValueKey('coop-mark-3')), findsNothing, reason: 'no initial on a moved card');
    expect(find.byKey(const ValueKey('coop-mark-7')), findsOneWidget, reason: 'the held card keeps it');
    final start = opacity();
    await tester.pump(const Duration(milliseconds: 800));
    final mid = opacity();
    await tester.pump(const Duration(milliseconds: 800));
    expect(start, greaterThan(0.9));
    expect(mid, lessThan(start));
    expect(opacity(), lessThan(0.05), reason: 'gone in about 1.5 s');
  });

  testWidgets('this player\'s drag is reported as fractions of the board, and its end after the drop', (tester) async {
    final s = stateOf(_reversed());
    final events = <String>[];
    await tester.pumpWidget(board(
      s,
      onDragMove: (slot, at, start) => events.add('${start ? 'start' : 'move'} $slot ${at.dx.toStringAsFixed(3)} ${at.dy.toStringAsFixed(3)}'),
      onDragEnd: (slot) => events.add('end $slot'),
      onDrop: (from, to) => events.add('drop $from $to'),
    ));
    final from = tester.getCenter(find.byKey(const ValueKey('card-15')));
    final cell = _spec.tiling.cellBounds(0, _size);
    final gesture = await tester.startGesture(from);
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(Offset(0, cell.height / 4));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    expect(events.first, startsWith('start 0'));
    final f0 = fraction(0);
    expect(events.first, endsWith('${f0.dx.toStringAsFixed(3)} ${f0.dy.toStringAsFixed(3)}'), reason: 'the drag starts at the card\'s centre');
    expect(events.where((e) => e.startsWith('move 0')).length, greaterThanOrEqualTo(4));
    expect(events.reversed.take(2).toList(), ['end 0', 'drop 0 4'], reason: 'the end follows the drop');
  });
}
