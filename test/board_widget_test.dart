import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:card_jigsaw_world/core/theme/app_theme.dart';
import 'package:card_jigsaw_world/core/theme/tokens.dart';
import 'package:card_jigsaw_world/features/game/board_widget.dart';
import 'package:card_jigsaw_world/game/board.dart';
import 'package:card_jigsaw_world/game/game_controller.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pixel checks on the rendered board: fused groups, the accent border along
/// a group's outside (including the inner corner of an L) and the dim on
/// cards that are not in place yet.
void main() {
  const g3 = GridSpec(3, 3, 'Cozy');
  const grey = Color(0xFF808080);

  ui.Image flatImage() {
    final rec = ui.PictureRecorder();
    Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 300, 300), Paint()..color = grey);
    return rec.endRecording().toImageSync(300, 300);
  }

  GameState stateFor(Board board) => GameState(
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
      );

  Future<ui.Image> render(WidgetTester tester, Board board) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 300,
              height: 300,
              child: BoardWidget(
                image: flatImage(),
                state: stateFor(board),
                onTap: (_) {},
                onDrop: (_, _) {},
                cardStyle: CardStyle.classic,
                width: 300,
                height: 300,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    late ui.Image img;
    await tester.runAsync(() async => img = await boundary.toImage());
    return img;
  }

  Future<Color> pixel(WidgetTester tester, ui.Image img, int x, int y) async {
    late ByteData data;
    await tester.runAsync(() async => data = (await img.toByteData())!);
    final i = (y * img.width + x) * 4;
    return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
  }

  bool near(Color a, Color b, [int tol = 6]) =>
      ((a.r - b.r) * 255).abs() <= tol && ((a.g - b.g) * 255).abs() <= tol && ((a.b - b.b) * 255).abs() <= tol;

  // 16 % black over mid grey.
  final dimmed = Color.fromARGB(255, (0x80 * 0.84).round(), (0x80 * 0.84).round(), (0x80 * 0.84).round());

  testWidgets('an L-shaped group is fused and its inner corner carries the accent border', (tester) async {
    // Cards 0, 1 (top row) and 3 (under 0) sit in slots 4, 5, 7: an L whose
    // inner corner is the bottom-right vertex of slot 4, next to slot 8.
    final board = Board(g3, [8, 7, 6, 5, 0, 1, 4, 3, 2]);
    expect(board.groupOf(4), [4, 5, 7]);
    final img = await render(tester, board);
    // Cells are 100 px; slot 4 spans (100..200, 100..200).
    expect(near(await pixel(tester, img, 150, 150), dimmed), isTrue, reason: 'free card is dimmed');
    // Fused seam between slots 4 and 5: picture on both sides, no gutter.
    expect(near(await pixel(tester, img, 199, 150), dimmed), isTrue, reason: 'no gutter left of the seam');
    expect(near(await pixel(tester, img, 200, 150), dimmed), isTrue, reason: 'no gutter right of the seam');
    // Inner corner: the accent border continues around the corner.
    expect(near(await pixel(tester, img, 199, 199), Brand.accent, 40), isTrue, reason: 'accent at the inner corner');
    // Outer edge of the group (left edge of slot 4, inset by the half gutter): accent band.
    expect(near(await pixel(tester, img, 105, 150), Brand.accent, 40), isTrue, reason: 'accent on the outer edge');
  });

  testWidgets('an interior vertex of a block group stays clean and locked clusters have no border', (tester) async {
    // Cards 0, 1, 3, 4 in slots 4, 5, 7, 8: a 2x2 block whose centre vertex
    // (200, 200) is interior to the group.
    final block = Board(g3, [8, 7, 6, 5, 0, 1, 2, 3, 4]);
    expect(block.groupOf(4), [4, 5, 7, 8]);
    final img = await render(tester, block);
    for (final (x, y) in [(199, 199), (200, 200), (199, 200), (200, 199)]) {
      expect(near(await pixel(tester, img, x, y), dimmed), isTrue, reason: 'interior vertex pixel ($x, $y) shows the picture');
    }
    // Locked cluster: cards 0, 1, 3, 4 in place; full brightness and no accent.
    final locked = Board(g3, [0, 1, 8, 3, 4, 7, 6, 5, 2]);
    final img2 = await render(tester, locked);
    expect(near(await pixel(tester, img2, 50, 50), grey), isTrue, reason: 'locked card at full brightness');
    expect(near(await pixel(tester, img2, 99, 99), grey), isTrue, reason: 'locked interior vertex shows the picture');
    expect(near(await pixel(tester, img2, 5, 50), grey), isTrue, reason: 'locked edge has no border');
  });
}
