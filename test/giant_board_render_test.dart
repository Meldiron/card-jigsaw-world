import 'dart:io';
import 'dart:ui' as ui;

import 'package:card_jigsaw_world/core/theme/app_theme.dart';
import 'package:card_jigsaw_world/features/game/board_widget.dart';
import 'package:card_jigsaw_world/game/board.dart';
import 'package:card_jigsaw_world/game/game_controller.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The largest giant board of every shape, in Painting with part of it in place, at the whole
/// board and zoomed in: it renders without errors, the zoom keeps the board covering the view,
/// and the renders go to `build/board_shapes/giant_*.png` (or `CJW_RENDER_DIR`) for a look.
void main() {
  ui.Image picture(int w, int h) {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    // Coloured stripes and rings: the black and white cards and the coloured ones are easy to tell apart.
    const colours = [Color(0xFFD9480F), Color(0xFF2F9E44), Color(0xFF1971C2), Color(0xFFF08C00), Color(0xFF9C36B5), Color(0xFF0CA678)];
    for (var i = 0; i < 24; i++) {
      canvas.drawRect(Rect.fromLTWH(0, h * i / 24, w.toDouble(), h / 24 + 1), Paint()..color = colours[i % colours.length]);
    }
    for (var i = 0; i < 12; i++) {
      canvas.drawCircle(Offset(w / 2, h / 2), w * (0.5 - i * 0.04), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.012
        ..color = Colors.white.withValues(alpha: 0.6));
    }
    return rec.endRecording().toImageSync(w, h);
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

  /// A shuffled board with the first [share] of its slots sent home.
  Board partlySolved(BoardSpec spec, double share) {
    var b = Board.shuffled(spec, seed: 11);
    for (var s = 0; s < (b.cells * share).round(); s++) {
      if (!b.isLocked(s)) b = b.swap(s, b.slotOfCard(s));
    }
    return b;
  }

  final outDir = Directory(Platform.environment['CJW_RENDER_DIR'] ?? 'build/board_shapes');

  for (final mode in GameMode.values) {
    testWidgets('largest giant ${mode.code} board renders whole and zoomed, in Painting', (tester) async {
      final spec = BoardSpec.giantTiers(mode).last;
      final board = partlySolved(spec, 0.4);
      expect(Board.isValidLayout(spec, board.slots), isTrue);
      final size = spec.tiling.fit(const Size(380, 560), BoardSpec.referenceAspect);
      final zoom = BoardZoom(vsync: const TestVSync());
      addTearDown(zoom.dispose);
      final image = picture(2400, 3200);
      final key = GlobalKey();
      final watch = Stopwatch()..start();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: BoardWidget(
                image: image,
                state: stateFor(board),
                onTap: (_) {},
                onDrop: (_, _) {},
                cardStyle: CardStyle.classic,
                width: size.width,
                height: size.height,
                painting: true,
                zoom: zoom,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final firstBuild = watch.elapsedMilliseconds;
      Future<void> dump(String name) async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final img = await boundary.toImage(pixelRatio: 2);
          final png = (await img.toByteData(format: ui.ImageByteFormat.png))!;
          await outDir.create(recursive: true);
          await File('${outDir.path}/$name.png').writeAsBytes(png.buffer.asUint8List());
        });
      }

      await dump('giant_${mode.code}_whole');
      // Zoomed in on the top left corner and panned past the edge: the board still covers the view.
      zoom.set(3, const Offset(50, 50));
      await tester.pump();
      expect(zoom.zoom, 3);
      expect(zoom.pan, Offset.zero);
      zoom.set(3, Offset(-size.width * 1.4, -size.height * 1.4));
      await tester.pump();
      expect(zoom.pan.dx, -size.width * 1.4);
      zoom.set(9, const Offset(-99999, -99999));
      await tester.pump();
      expect(zoom.zoom, BoardZoom.maxZoom);
      expect(zoom.pan, Offset(size.width * (1 - BoardZoom.maxZoom), size.height * (1 - BoardZoom.maxZoom)));
      zoom.set(2.5, Offset(-size.width * 0.6, -size.height * 0.6));
      await tester.pump();
      await dump('giant_${mode.code}_zoomed');
      expect(tester.takeException(), isNull);
      debugPrint('${mode.code} ${spec.code}: ${spec.cells} pieces, first build ${firstBuild}ms');
    });
  }
}
