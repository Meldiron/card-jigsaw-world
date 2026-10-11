import 'dart:io';
import 'dart:math' as math;
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
/// a group's outside (including the concave corners of an L and a T) and the
/// dim on cards that are not in place yet.
///
/// The shape gallery at the end renders fused groups of many shapes in all
/// four tilings and writes them as PNGs (`build/board_shapes/`, or the
/// directory in `CJW_RENDER_DIR`) so the outline can be inspected by eye.
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

  Future<ui.Image> render(WidgetTester tester, Board board, {double width = 300, double height = 300, bool dark = false, CardStyle style = CardStyle.classic}) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: width,
              height: height,
              child: BoardWidget(
                image: flatImage(),
                state: stateFor(board),
                onTap: (_) {},
                onDrop: (_, _) {},
                cardStyle: style,
                width: width,
                height: height,
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

  Future<ByteData> bytes(WidgetTester tester, ui.Image img) async {
    late ByteData data;
    await tester.runAsync(() async => data = (await img.toByteData())!);
    return data;
  }

  /// Writes a render as PNG for inspection by eye.
  final outDir = Directory(Platform.environment['CJW_RENDER_DIR'] ?? 'build/board_shapes');
  Future<void> dump(WidgetTester tester, String name, ui.Image img) async {
    late ByteData png;
    await tester.runAsync(() async {
      await outDir.create(recursive: true);
      png = (await img.toByteData(format: ui.ImageByteFormat.png))!;
      await File('${outDir.path}/$name.png').writeAsBytes(png.buffer.asUint8List());
    });
  }

  Color pixelOf(ByteData data, ui.Image img, int x, int y) {
    final i = (y * img.width + x) * 4;
    return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
  }

  bool near(Color a, Color b, [int tol = 6]) =>
      ((a.r - b.r) * 255).abs() <= tol && ((a.g - b.g) * 255).abs() <= tol && ((a.b - b.b) * 255).abs() <= tol;

  // 16 % black over mid grey.
  final dimmed = Color.fromARGB(255, (0x80 * 0.84).round(), (0x80 * 0.84).round(), (0x80 * 0.84).round());

  /// A board where the cards of [homes] sit, in formation, [dx]/[dy] lattice
  /// steps away from home (one fused group), and every other card sits
  /// somewhere harmless: nothing else fused, nothing locked.
  Board boardWithShape(BoardSpec spec, List<int> homes, int dx, int dy, {int seed = 1}) {
    final tiling = spec.tiling;
    final targets = [for (final h in homes) tiling.apply(h, dx, dy)!];
    final rng = math.Random(seed);
    for (var attempt = 0; attempt < 2000; attempt++) {
      final slots = List<int>.filled(spec.cells, -1);
      for (var i = 0; i < homes.length; i++) {
        slots[targets[i]] = homes[i];
      }
      for (var cls = 0; cls < tiling.classCount; cls++) {
        final cards = [for (var c = 0; c < spec.cells; c++) if (tiling.classOf(c) == cls && !homes.contains(c)) c]..shuffle(rng);
        final free = [for (var s = 0; s < spec.cells; s++) if (tiling.classOf(s) == cls && !targets.contains(s)) s];
        for (var i = 0; i < free.length; i++) {
          slots[free[i]] = cards[i];
        }
      }
      final board = Board(spec, slots);
      final groups = <int>{for (var s = 0; s < spec.cells; s++) if (board.groupOf(s).length > 1) board.groupIdOf(s)};
      final locked = [for (var s = 0; s < spec.cells; s++) if (board.isLocked(s)) s];
      if (locked.isEmpty && groups.length == 1 && board.groupOf(targets.first).toSet().containsAll(targets) && board.groupOf(targets.first).length == targets.length) {
        return board;
      }
    }
    throw StateError('no clean layout for $homes on ${spec.fullCode}');
  }

  testWidgets('an L-shaped group is fused and its concave corner is one clean band', (tester) async {
    // Cards 0, 1 (top row) and 3 (under 0) sit in slots 4, 5, 7: an L whose
    // concave corner is the bottom-right vertex of slot 4, next to slot 8.
    final board = Board(g3, [8, 7, 6, 5, 0, 1, 4, 3, 2]);
    expect(board.groupOf(4), [4, 5, 7]);
    final img = await render(tester, board);
    await dump(tester, 'cards3_L', img);
    final data = await bytes(tester, img);
    Color px(int x, int y) => pixelOf(data, img, x, y);
    // Cells are 100 px, gutter 8 (half 4), accent 2 px wide: the visible
    // band runs 4..6 px inside the group's boundary.
    expect(near(px(150, 150), dimmed), isTrue, reason: 'free card is dimmed');
    // Fused seam between slots 4 and 5: picture on both sides, no gutter.
    expect(near(px(199, 150), dimmed), isTrue, reason: 'no gutter left of the seam');
    expect(near(px(200, 150), dimmed), isTrue, reason: 'no gutter right of the seam');
    // Straight runs: bottom edge of slot 5 and right edge of slot 7.
    expect(near(px(250, 195), Brand.accent, 40), isTrue, reason: 'accent along the bottom of slot 5');
    expect(near(px(195, 250), Brand.accent, 40), isTrue, reason: 'accent along the right of slot 7');
    // Concave corner at (200, 200): the band turns on an arc of radius 4..6
    // around the vertex, inside slot 4, meeting both straight runs.
    expect(near(px(196, 196), Brand.accent, 40), isTrue, reason: 'accent on the concave arc');
    expect(near(px(199, 195), Brand.accent, 40), isTrue, reason: 'arc meets the run of slot 5 at the seam');
    expect(near(px(195, 199), Brand.accent, 40), isTrue, reason: 'arc meets the run of slot 7 at the seam');
    expect(near(px(201, 195), Brand.accent, 40), isTrue, reason: 'run of slot 5 reaches the seam');
    expect(near(px(195, 201), Brand.accent, 40), isTrue, reason: 'run of slot 7 reaches the seam');
    // The vertex itself lies in the gutter (the picture is cut along the
    // same curve), and nothing bleeds into the picture.
    expect(near(px(199, 199), dimmed) || near(px(199, 199), Brand.accent, 40), isFalse, reason: 'the vertex itself is gutter (no notch)');
    expect(near(px(197, 197), dimmed) || near(px(197, 197), Brand.accent, 40), isFalse, reason: 'inside the arc is gutter');
    expect(near(px(190, 190), dimmed), isTrue, reason: 'no outline inside the group');
    expect(near(px(150, 196), dimmed), isTrue, reason: 'no outline along the fused seam between 4 and 7');
    // Outer edge of the group (left edge of slot 4, inset by the half gutter): accent band.
    expect(near(px(105, 150), Brand.accent, 40), isTrue, reason: 'accent on the outer edge');
  });

  testWidgets('a T-shaped group has two clean concave corners', (tester) async {
    // Cards 0, 1, 2 in slots 3, 4, 5 and card 4 in slot 7: concave corners
    // at (100, 200) and (200, 200), both in slot 4.
    final board = boardWithShape(g3, [0, 1, 2, 4], 0, 1);
    expect(board.groupOf(4).toSet(), {3, 4, 5, 7});
    final img = await render(tester, board);
    await dump(tester, 'cards3_T', img);
    final data = await bytes(tester, img);
    Color px(int x, int y) => pixelOf(data, img, x, y);
    for (final (vx, sx) in [(100, 1), (200, -1)]) {
      // Pixel whose centre is 3.5 px diagonally inside the vertex: on the
      // arc (radius 4..6 around the vertex).
      final x = (vx + 3.5 * sx).floor();
      expect(near(px(x, 196), Brand.accent, 40), isTrue, reason: 'arc around ($vx, 200)');
      final v = px((vx + 0.5 * sx).floor(), 199);
      expect(near(v, dimmed) || near(v, Brand.accent, 40), isFalse, reason: 'vertex ($vx, 200) is gutter, no notch');
      expect(near(px(vx + sx * 12, 188), dimmed), isTrue, reason: 'no bleed near ($vx, 200)');
    }
    expect(near(px(150, 196), dimmed), isTrue, reason: 'no outline on the seam between 4 and 7');
    expect(near(px(50, 195), Brand.accent, 40), isTrue, reason: 'bottom run of slot 3');
    expect(near(px(250, 195), Brand.accent, 40), isTrue, reason: 'bottom run of slot 5');
  });

  testWidgets('an interior vertex of a block group stays clean and locked clusters have no border', (tester) async {
    // Cards 0, 1, 3, 4 in slots 4, 5, 7, 8: a 2x2 block whose centre vertex
    // (200, 200) is interior to the group.
    final block = Board(g3, [8, 7, 6, 5, 0, 1, 2, 3, 4]);
    expect(block.groupOf(4), [4, 5, 7, 8]);
    final img = await render(tester, block);
    final data = await bytes(tester, img);
    for (final (x, y) in [(199, 199), (200, 200), (199, 200), (200, 199), (195, 195), (205, 205)]) {
      expect(near(pixelOf(data, img, x, y), dimmed), isTrue, reason: 'interior vertex pixel ($x, $y) shows the picture');
    }
    // Locked cluster: cards 0, 1, 3, 4 in place; full brightness and no accent.
    final locked = Board(g3, [0, 1, 8, 3, 4, 7, 6, 5, 2]);
    final img2 = await render(tester, locked);
    final data2 = await bytes(tester, img2);
    expect(near(pixelOf(data2, img2, 50, 50), grey), isTrue, reason: 'locked card at full brightness');
    expect(near(pixelOf(data2, img2, 99, 99), grey), isTrue, reason: 'locked interior vertex shows the picture');
    expect(near(pixelOf(data2, img2, 5, 50), grey), isTrue, reason: 'locked edge has no border');
  });

  testWidgets('a hexagon group shows the picture at its interior vertex and no accent inside', (tester) async {
    // Three hexagons around one vertex: (0,0), (1,0) and (0,1) below them.
    const spec = BoardSpec(GameMode.hexagons, 4, 5, 'Custom');
    final board = boardWithShape(spec, [0, 1, 4], 1, 1);
    final size = spec.tiling.fit(const Size(360, 360), 1);
    final w = size.width.round(), h = size.height.round();
    final img = await render(tester, board, width: w.toDouble(), height: h.toDouble());
    await dump(tester, 'hex_tri', img);
    final data = await bytes(tester, img);
    final tiling = spec.tiling;
    final boardSize = Size(w.toDouble(), h.toDouble());
    final members = board.groupOf(tiling.apply(0, 1, 1)!);
    // The vertex every member shares is interior: picture all around it.
    final polys = {for (final s in members) s: tiling.polygon(s, boardSize)};
    Offset? shared;
    for (final v in polys[members.first]!) {
      if (members.skip(1).every((s) => polys[s]!.any((p) => (p - v).distance < 0.01))) shared = v;
    }
    expect(shared, isNotNull);
    for (final (ddx, ddy) in [(0, 0), (3, 0), (-3, 0), (0, 3), (0, -3)]) {
      final x = shared!.dx.round() + ddx, y = shared.dy.round() + ddy;
      expect(near(pixelOf(data, img, x, y), dimmed), isTrue, reason: 'interior vertex pixel ($x, $y) shows the picture');
    }
    // Centre of each member: picture, no accent.
    for (final s in members) {
      final c = tiling.cellCenter(s, boardSize);
      expect(near(pixelOf(data, img, c.dx.round(), c.dy.round()), dimmed), isTrue, reason: 'cell $s centre is picture');
    }
  });

  testWidgets('shape gallery renders every tiling without artefacts and writes PNGs', (tester) async {
    const squares = BoardSpec(GameMode.squares, 4, 5, 'Custom');
    const cards = BoardSpec(GameMode.cards, 4, 4, 'Custom');
    const tri = BoardSpec(GameMode.triangles, 6, 4, 'Custom');
    const hex = BoardSpec(GameMode.hexagons, 4, 5, 'Custom');
    int c(BoardSpec s) => s.cols;
    final cases = <(String, BoardSpec, List<int>, int, int)>[
      for (final s in [squares, cards]) ...[
        ('${s.mode.code}_I_edge', s, [0, 1, 2], 1, 0),
        ('${s.mode.code}_L', s, [0, 1, c(s)], 1, 1),
        ('${s.mode.code}_T', s, [0, 1, 2, c(s) + 1], 0, 1),
        ('${s.mode.code}_S', s, [1, 2, c(s), c(s) + 1], 1, 1),
        ('${s.mode.code}_2x2', s, [0, 1, c(s), c(s) + 1], 1, 1),
        ('${s.mode.code}_plus', s, [1, c(s), c(s) + 1, c(s) + 2, 2 * c(s) + 1], 0, 1),
        ('${s.mode.code}_pair_edge', s, [0, c(s)], 1, 0),
      ],
      ('triangles_row3', tri, [0, 1, 2], 2, 0),
      ('triangles_bent', tri, [0, 1, 2, 6], 1, 1),
      ('triangles_ring', tri, [0, 1, 2, 6, 7, 8], 2, 0),
      ('triangles_pair', tri, [1, 2], 1, 1),
      ('hexagons_line', hex, [0, 1, 2], 0, 1),
      ('hexagons_bent', hex, [0, 1, 5], 1, 1),
      ('hexagons_tri', hex, [0, 1, 4], 1, 1),
      ('hexagons_blob', hex, [0, 1, 4, 5, 9], 1, 1),
      ('hexagons_edge', hex, [0, 4], 1, 0),
    ];
    for (final (name, spec, homes, dx, dy) in cases) {
      final board = boardWithShape(spec, homes, dx, dy);
      final size = spec.tiling.fit(const Size(360, 360), 1);
      final w = size.width.round(), h = size.height.round();
      for (final dark in [false, true]) {
        for (final style in [CardStyle.classic, CardStyle.minimal]) {
          final img = await render(tester, board, width: w.toDouble(), height: h.toDouble(), dark: dark, style: style);
          final data = await bytes(tester, img);
          // Every member's centre shows the (dimmed) picture, never the accent.
          final tiling = spec.tiling;
          final boardSize = Size(w.toDouble(), h.toDouble());
          final members = board.groupOf(tiling.apply(homes.first, dx, dy)!);
          for (final s in members) {
            final p = tiling.cellCenter(s, boardSize);
            expect(near(pixelOf(data, img, p.dx.round(), p.dy.round()), dimmed), isTrue, reason: '$name: centre of $s is picture');
          }
          await dump(tester, '${name}_${dark ? 'dark' : 'light'}_${style.name}', img);
        }
      }
    }
  });
}
