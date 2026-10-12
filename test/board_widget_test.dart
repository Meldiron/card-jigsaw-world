import 'dart:io';
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
/// a group's outside (including the concave corners of an L and a T), the
/// dim and frame on cards that are not in place yet, and cards in place
/// filling their whole cell with square corners.
///
/// The galleries render fused groups of many shapes in all four tilings,
/// the cut of every mode for square, 3:4 and 9:16 pictures, triangle and
/// hexagon boards with their clipped edge pieces, and boards with a single
/// card in place, and write them as PNGs (`build/board_shapes/`, or the
/// directory in `CJW_RENDER_DIR`) so they can be inspected by eye.
void main() {
  const g3 = GridSpec(3, 3, 'Cozy');
  const grey = Color(0xFF808080);

  ui.Image flatImage() {
    final rec = ui.PictureRecorder();
    Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 300, 300), Paint()..color = grey);
    return rec.endRecording().toImageSync(300, 300);
  }

  /// A painted landscape with light and dark areas, so every piece shows
  /// something different and the frame can be judged on both.
  ui.Image picture(int w, int h) {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final W = w.toDouble(), H = h.toDouble();
    canvas.drawRect(Rect.fromLTWH(0, 0, W, H), Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, H * 0.6), const [Color(0xFF9CC3E6), Color(0xFFF3E3C3)]));
    canvas.drawCircle(Offset(W * 0.72, H * 0.2), W * 0.09, Paint()..color = const Color(0xFFFFF4D6));
    final far = Path()
      ..moveTo(0, H * 0.55)
      ..lineTo(W * 0.18, H * 0.32)
      ..lineTo(W * 0.36, H * 0.48)
      ..lineTo(W * 0.58, H * 0.26)
      ..lineTo(W * 0.82, H * 0.46)
      ..lineTo(W, H * 0.36)
      ..lineTo(W, H * 0.62)
      ..lineTo(0, H * 0.62)
      ..close();
    canvas.drawPath(far, Paint()..color = const Color(0xFF55627A));
    final near = Path()
      ..moveTo(0, H * 0.7)
      ..quadraticBezierTo(W * 0.3, H * 0.55, W * 0.6, H * 0.66)
      ..quadraticBezierTo(W * 0.85, H * 0.74, W, H * 0.64)
      ..lineTo(W, H)
      ..lineTo(0, H)
      ..close();
    canvas.drawPath(near, Paint()..shader = ui.Gradient.linear(Offset(0, H * 0.6), Offset(0, H), const [Color(0xFF4F7A3A), Color(0xFF1E2E17)]));
    for (var i = 0; i < 7; i++) {
      final x = W * (0.08 + i * 0.14), y = H * (0.78 + (i % 3) * 0.05);
      canvas.drawCircle(Offset(x, y), W * 0.045, Paint()..color = const Color(0xFF233A1A));
      canvas.drawRect(Rect.fromCenter(center: Offset(x, y + W * 0.06), width: W * 0.012, height: W * 0.06), Paint()..color = const Color(0xFF3A2A1A));
    }
    // A thin frame line marks the picture's own edge, so a crop shows.
    canvas.drawRect(Rect.fromLTWH(1.5, 1.5, W - 3, H - 3), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFFB0413E));
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

  Future<ui.Image> render(WidgetTester tester, Board board, {double width = 300, double height = 300, bool dark = false, CardStyle style = CardStyle.classic, ui.Image? image, int? selected}) async {
    final key = GlobalKey();
    final img = image ?? flatImage();
    await tester.pumpWidget(MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      home: Scaffold(
        backgroundColor: dark ? const Color(0xFF0D0D11) : const Color(0xFFF6F6F8),
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: Container(
              color: dark ? const Color(0xFF0D0D11) : const Color(0xFFF6F6F8),
              width: width,
              height: height,
              child: BoardWidget(
                image: img,
                state: stateFor(board, selected: selected),
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
    late ui.Image out;
    await tester.runAsync(() async => out = await boundary.toImage());
    return out;
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
  Board boardWithShape(BoardSpec spec, List<int> homes, int dx, int dy) {
    final tiling = spec.tiling;
    final targets = [for (final h in homes) tiling.apply(h, dx, dy)!];
    for (var seed = 0; seed < 600; seed++) {
      var board = Board.shuffled(spec, seed: seed);
      for (var i = 0; i < homes.length; i++) {
        board = board.swap(board.slotOfCard(homes[i]), targets[i]);
      }
      final groups = <int>{for (var s = 0; s < spec.cells; s++) if (board.groupOf(s).length > 1) board.groupIdOf(s)};
      if (board.lockedCount == 0 && groups.length == 1 && board.groupOf(targets.first).toSet().containsAll(targets) && board.groupOf(targets.first).length == targets.length) {
        return board;
      }
    }
    throw StateError('no clean layout for $homes on ${spec.fullCode}');
  }

  /// A shuffled board with exactly the cards of [placed] in place and no
  /// group anywhere else: a clean start with those cards sent home.
  Board boardWithPlaced(BoardSpec spec, Set<int> placed) {
    for (var seed = 0; seed < 400; seed++) {
      var board = Board.shuffled(spec, seed: seed);
      for (final p in placed) {
        board = board.swap(board.slotOfCard(p), p);
      }
      final locked = {for (var s = 0; s < spec.cells; s++) if (board.isLocked(s)) s};
      if (locked.length == placed.length && locked.containsAll(placed) && board.floatingGroups == 0 && Board.isValidLayout(spec, board.slots)) return board;
    }
    throw StateError('no clean layout with $placed on ${spec.fullCode}');
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

  testWidgets('an interior vertex of a block group stays clean and cards in place fill their cells edge to edge', (tester) async {
    // Cards 0, 1, 3, 4 in slots 4, 5, 7, 8: a 2x2 block whose centre vertex
    // (200, 200) is interior to the group.
    final block = Board(g3, [8, 7, 6, 5, 0, 1, 2, 3, 4]);
    expect(block.groupOf(4), [4, 5, 7, 8]);
    final img = await render(tester, block);
    final data = await bytes(tester, img);
    for (final (x, y) in [(199, 199), (200, 200), (199, 200), (200, 199), (195, 195), (205, 205)]) {
      expect(near(pixelOf(data, img, x, y), dimmed), isTrue, reason: 'interior vertex pixel ($x, $y) shows the picture');
    }
    // Locked cluster: cards 0, 1, 3, 4 in place; full brightness, no accent,
    // no frame, no gutter and square corners, even towards free neighbours.
    final locked = Board(g3, [0, 1, 8, 3, 4, 7, 6, 5, 2]);
    final img2 = await render(tester, locked);
    await dump(tester, 'cards3_locked_cluster', img2);
    final data2 = await bytes(tester, img2);
    Color px(int x, int y) => pixelOf(data2, img2, x, y);
    expect(near(px(50, 50), grey), isTrue, reason: 'locked card at full brightness');
    expect(near(px(99, 99), grey), isTrue, reason: 'locked interior vertex shows the picture');
    expect(near(px(5, 50), grey), isTrue, reason: 'locked edge has no frame');
    expect(near(px(0, 50), grey), isTrue, reason: 'locked card reaches the board edge');
    expect(near(px(0, 0), grey), isTrue, reason: 'locked corner is square');
    expect(near(px(199, 50), grey), isTrue, reason: 'locked card fills its cell up to a free neighbour');
    expect(near(px(199, 199), grey), isTrue, reason: 'locked corner next to free cards is square');
    // The free neighbour keeps its gutter, frame and dim.
    expect(near(px(201, 50), grey) || near(px(201, 50), dimmed), isFalse, reason: 'free neighbour keeps its gutter');
    expect(near(px(250, 50), dimmed), isTrue, reason: 'free neighbour is dimmed');
  });

  testWidgets('a single card in place is square, bright and frameless; its free neighbours are framed', (tester) async {
    final single = Board(g3, [2, 0, 1, 5, 4, 3, 8, 6, 7]);
    expect(single.isLocked(4), isTrue);
    expect(single.lockedCount, 1);
    for (final dark in [false, true]) {
      final img = await render(tester, single, dark: dark);
      await dump(tester, 'cards3_single_locked_${dark ? 'dark' : 'light'}', img);
      final data = await bytes(tester, img);
      Color px(int x, int y) => pixelOf(data, img, x, y);
      for (final (x, y) in [(100, 100), (199, 100), (100, 199), (199, 199), (150, 150), (101, 150)]) {
        expect(near(px(x, y), grey), isTrue, reason: 'locked cell pixel ($x, $y) is plain picture (dark $dark)');
      }
      // Free cards: the frame band sits just inside the gutter, lighter than
      // the picture, and the very corner is rounded off.
      final band = px(6, 150);
      expect(band.r > dimmed.r + 0.2, isTrue, reason: 'free card frame is light (dark $dark): $band');
      expect(near(px(5, 5), dimmed) || near(px(5, 5), grey), isFalse, reason: 'free card corner is rounded (dark $dark)');
    }
  });

  testWidgets('a hexagon group shows the picture at its interior vertex and no accent inside', (tester) async {
    // Three hexagons around one vertex: slots 5, 6 (row 1) and 10 (row 2),
    // moved one step down-left.
    const spec = BoardSpec(GameMode.hexagons, 4, 5, 'Custom');
    final board = boardWithShape(spec, [5, 6, 10], -1, 1);
    final size = spec.tiling.fit(const Size(360, 360), 0.8);
    final w = size.width.round(), h = size.height.round();
    final img = await render(tester, board, width: w.toDouble(), height: h.toDouble());
    await dump(tester, 'hex_tri', img);
    final data = await bytes(tester, img);
    final tiling = spec.tiling;
    final boardSize = Size(w.toDouble(), h.toDouble());
    final members = board.groupOf(tiling.apply(5, -1, 1)!);
    expect(members.length, 3);
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
    // Triangles 6x4 (four rows, odd steps): rows of pieces k = 0..5 with a
    // half at k = 0; the right edge's halves are fused in pairs into
    // left-pointing triangles (slots 5 and 16). Slots: r0 0-5, r1 6-10,
    // r2 11-16, r3 17-21. Piece (k, r) points up when k + r is odd.
    const tri = BoardSpec(GameMode.triangles, 6, 4, 'Custom');
    // Triangles 9x6: plain halves on both edges, rows of 9 (slot r * 9 + k).
    const tri6 = BoardSpec(GameMode.triangles, 9, 6, 'Custom');
    // Hexagons 4x5: rows of 4 (even) and 5 (odd, halves at both ends).
    // Slots: r0 0-3 (top pieces), r1 4-8, r2 9-12, r3 13-17, r4 18-21.
    const hex = BoardSpec(GameMode.hexagons, 4, 5, 'Custom');
    // Hexagons 5x7: r0 0-4, r1 5-10, r2 11-15, r3 16-21, r4 22-26, ...
    const hex7 = BoardSpec(GameMode.hexagons, 5, 7, 'Custom');
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
      ('triangles_row3', tri6, [2, 3, 4], 0, 2),
      ('triangles_bent', tri, [1, 2, 7], 2, 2),
      ('triangles_ring', tri6, [2, 3, 4, 11, 12, 13], 0, 2),
      ('triangles_pair', tri, [2, 3], 0, 2),
      ('triangles_half_and_full', tri, [0, 1], 0, 2),
      ('triangles_fused_edge', tri, [4, 5], 0, 2),
      ('hexagons_line', hex, [9, 10, 11], 2, 0),
      ('hexagons_bent', hex, [5, 6, 11], -1, 1),
      ('hexagons_tri', hex, [5, 6, 10], -1, 1),
      ('hexagons_blob', hex7, [6, 7, 12, 13, 18], 2, 2),
      ('hexagons_top_pair', hex, [0, 1], 4, 0),
      ('hexagons_half_and_full', hex, [4, 5], 0, 2),
    ];
    for (final (name, spec, homes, dx, dy) in cases) {
      final board = boardWithShape(spec, homes, dx, dy);
      final size = spec.tiling.fit(const Size(360, 360), 0.8);
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

  testWidgets('cut gallery: every mode on square, 3:4 and 9:16 pictures', (tester) async {
    const area = Size(360, 460);
    for (final (pname, pw, ph) in [('square', 900, 900), ('3x4', 900, 1200), ('9x16', 900, 1600)]) {
      final image = picture(pw, ph);
      final aspect = pw / ph;
      for (final mode in GameMode.values) {
        for (final tier in [0, 2, 5]) {
          final spec = BoardSpec.forPicture(mode, tier, aspect);
          final size = spec.tiling.fit(area, aspect);
          final w = size.width.roundToDouble(), h = size.height.roundToDouble();
          final shuffled = Board.shuffled(spec, seed: 11);
          final img = await render(tester, shuffled, width: w, height: h, image: image);
          await dump(tester, 'cut_${mode.code}_${pname}_t${tier}_${spec.code}_shuffled', img);
          if (tier == 2) {
            final solved = Board(spec, List.generate(spec.cells, (i) => i));
            final img2 = await render(tester, solved, width: w, height: h, image: image);
            await dump(tester, 'cut_${mode.code}_${pname}_t${tier}_${spec.code}_solved', img2);
            // Solved, every piece fills its cell: the picture reaches every
            // edge of the board, half pieces included (no board background).
            final data = await bytes(tester, img2);
            final bg = AppTheme.light().extension<AppColors>()!.boardBackground;
            final iw = img2.width, ih = img2.height;
            for (var k = 1; k < 20; k++) {
              for (final (x, y) in [((iw - 1) * k ~/ 20, 0), ((iw - 1) * k ~/ 20, ih - 1), (0, (ih - 1) * k ~/ 20), (iw - 1, (ih - 1) * k ~/ 20)]) {
                expect(near(pixelOf(data, img2, x, y), bg, 3), isFalse, reason: '${spec.fullCode} on $pname: board edge pixel ($x, $y) shows the picture');
              }
            }
          }
        }
      }
    }
  });

  testWidgets('placed gallery: one card in place among free ones, and a placed cluster, in every mode', (tester) async {
    const area = Size(360, 460);
    final image = picture(900, 1200);
    for (final mode in GameMode.values) {
      final spec = BoardSpec.forPicture(mode, 2, 0.75);
      final tiling = spec.tiling;
      // A whole piece away from the edges.
      final whole = switch (mode) {
        GameMode.triangles => 3,
        GameMode.hexagons => 6,
        _ => 4,
      };
      final inner = [for (var s = 0; s < spec.cells; s++) if (tiling.neighbours(s).length == whole) s];
      final pick = inner.isNotEmpty ? inner[inner.length ~/ 2] : spec.cells ~/ 2;
      final size = tiling.fit(area, 0.75);
      final w = size.width.roundToDouble(), h = size.height.roundToDouble();
      final single = boardWithPlaced(spec, {pick});
      // A cluster of cards in place: a whole piece and its neighbours.
      final cluster = boardWithPlaced(spec, {pick, ...tiling.neighbours(pick)});
      for (final dark in [false, true]) {
        for (final style in [CardStyle.classic, CardStyle.minimal]) {
          final suffix = '${dark ? 'dark' : 'light'}_${style.name}';
          await dump(tester, 'placed_single_${mode.code}_$suffix', await render(tester, single, width: w, height: h, image: image, dark: dark, style: style));
          await dump(tester, 'placed_cluster_${mode.code}_$suffix', await render(tester, cluster, width: w, height: h, image: image, dark: dark, style: style));
        }
      }
      // A selected card on the dark theme: the ink edge must read against
      // the frame.
      final sel = [for (var s = 0; s < spec.cells; s++) if (!single.isLocked(s)) s].first;
      await dump(tester, 'placed_selected_${mode.code}_dark', await render(tester, single, width: w, height: h, image: image, dark: true, selected: sel));
    }
  });

  testWidgets('dragged card: square corners, no frame, outline outside the picture', (tester) async {
    const area = Size(360, 460);
    final image = picture(900, 1200);
    for (final mode in [GameMode.cards, GameMode.hexagons]) {
      final spec = BoardSpec.forPicture(mode, 2, 0.75);
      final tiling = spec.tiling;
      final size = tiling.fit(area, 0.75);
      final w = size.width.roundToDouble(), h = size.height.roundToDouble();
      final board = boardWithPlaced(spec, const {});
      await render(tester, board, width: w, height: h, image: image, dark: true);
      final origin = tester.getTopLeft(find.byType(BoardWidget));
      final slot = spec.cells ~/ 2;
      final gesture = await tester.startGesture(origin + tiling.cellCenter(slot, Size(w, h)));
      await gesture.moveBy(const Offset(18, 10));
      await tester.pump();
      await gesture.moveBy(const Offset(18, 10));
      await tester.pump(const Duration(milliseconds: 400));
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.ancestor(of: find.byType(BoardWidget), matching: find.byType(RepaintBoundary)).first);
      late ui.Image shot;
      await tester.runAsync(() async => shot = await boundary.toImage());
      await dump(tester, 'dragging_${mode.code}_dark', shot);
      await gesture.cancel();
      await tester.pumpAndSettle();
    }
  });
}
