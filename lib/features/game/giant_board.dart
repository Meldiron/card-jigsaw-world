import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../game/board.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import 'board_widget.dart';

/// The tools around a giant board (100 to 300 cards and more), chosen from
/// how big-board jigsaw apps help on a phone (see docs/giant-boards.md):
/// a bar with the Edges filter and the zoom buttons, an overview map of the
/// whole board while zoomed in, a pointer to a selected card that is out of
/// view, and calm milestones on the way (the frame, halfway).

/// Above a giant board: the Edges filter, a short hint, the overview map
/// switch (while zoomed in), zoom in, and back to the whole board.
class GiantBoardBar extends StatelessWidget {
  const GiantBoardBar({
    super.key,
    required this.zoom,
    required this.width,
    required this.edges,
    required this.onEdges,
    required this.showMap,
    required this.onMap,
  });

  final BoardZoom zoom;
  final double width;
  final bool edges;
  final VoidCallback onEdges;
  final bool showMap;
  final VoidCallback onMap;

  static const height = 44.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: width,
      height: height,
      child: ListenableBuilder(
        listenable: zoom,
        builder: (context, _) {
          final canZoomIn = zoom.zoom < zoom.limit - 0.01;
          return Row(
            children: [
              _ToggleChip(key: const ValueKey('giant-edges'), icon: AppIcons.edges, label: 'Edges', on: edges, onTap: onEdges),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  zoom.zoomed ? 'Zoom ${zoom.zoom.toStringAsFixed(1)}x' : 'Pinch or double-tap to zoom',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.textSecondary),
                ),
              ),
              if (zoom.zoomed) ...[
                RoundIconButton(
                  key: const ValueKey('giant-map'),
                  icon: AppIcons.minimap,
                  size: 34,
                  color: showMap ? c.accentTint : null,
                  iconColor: showMap ? context.accent : c.textSecondary,
                  onTap: onMap,
                ),
                const SizedBox(width: 8),
              ],
              RoundIconButton(
                key: const ValueKey('zoom-in'),
                icon: AppIcons.zoom,
                size: 34,
                iconColor: canZoomIn ? context.accent : c.textTertiary,
                onTap: canZoomIn ? () => zoom.zoomTo(zoom.zoomed ? math.min(zoom.limit, zoom.zoom * 1.6) : zoom.step) : null,
              ),
              const SizedBox(width: 8),
              RoundIconButton(
                key: const ValueKey('zoom-whole-board'),
                icon: AppIcons.wholeBoard,
                size: 34,
                iconColor: zoom.zoomed ? context.accent : c.textTertiary,
                onTap: zoom.zoomed ? zoom.reset : null,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A small capsule switch: icon and label, cobalt while on.
class _ToggleChip extends StatelessWidget {
  const _ToggleChip({super.key, required this.icon, required this.label, required this.on, required this.onTap});
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = on ? context.accent : c.textSecondary;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: on ? c.accentTint : c.card,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: on ? context.accent.withValues(alpha: 0.5) : c.stroke),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// The whole board in miniature while zoomed in: the cards as they lie now
/// (cards in place bright, the rest darker, so the unfinished areas are easy
/// to spot), the part in view outlined, and the selected card marked. Tap or
/// drag on it to move the view there.
class GiantMinimap extends StatelessWidget {
  const GiantMinimap({
    super.key,
    required this.image,
    required this.board,
    required this.boardSize,
    required this.zoom,
    required this.width,
    this.selected,
    this.painting = false,
  });

  final ui.Image image;
  final Board board;

  /// The board's size on screen at zoom 1.
  final Size boardSize;
  final BoardZoom zoom;
  final double width;
  final int? selected;
  final bool painting;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scale = width / boardSize.width;
    final size = Size(width, boardSize.height * scale);
    const inset = 3.0;
    Offset toBoard(Offset local) => (local - const Offset(inset, inset)) / scale;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => zoom.centreOn(toBoard(d.localPosition)),
      onPanStart: (d) => zoom.lookAt(toBoard(d.localPosition)),
      onPanUpdate: (d) => zoom.lookAt(toBoard(d.localPosition)),
      child: Container(
        key: const ValueKey('giant-minimap'),
        width: size.width + 2 * inset,
        height: size.height + 2 * inset,
        padding: const EdgeInsets.all(inset),
        decoration: BoxDecoration(
          color: c.card.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.stroke),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Stack(
            children: [
              RepaintBoundary(child: CustomPaint(size: size, painter: _MiniBoardPainter(image: image, board: board, boardSize: boardSize, painting: painting))),
              ListenableBuilder(
                listenable: zoom,
                builder: (context, _) => CustomPaint(
                  size: size,
                  painter: _ViewPainter(
                    view: Rect.fromLTRB(zoom.visible.left * scale, zoom.visible.top * scale, zoom.visible.right * scale, zoom.visible.bottom * scale),
                    selected: selected == null ? null : board.tiling.cellCenter(selected!, boardSize) * scale,
                    accent: context.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniBoardPainter extends CustomPainter {
  _MiniBoardPainter({required this.image, required this.board, required this.boardSize, required this.painting});
  final ui.Image image;
  final Board board;
  final Size boardSize;
  final bool painting;

  static const _grey = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  void paint(Canvas canvas, Size size) {
    final tiling = board.tiling;
    canvas.save();
    canvas.scale(size.width / boardSize.width);
    final crop = tiling.crop(Size(image.width.toDouble(), image.height.toDouble()), boardSize);
    final colour = Paint()..filterQuality = FilterQuality.low;
    final grey = Paint()
      ..filterQuality = FilterQuality.low
      ..colorFilter = _grey;
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.3);
    for (var slot = 0; slot < board.cells; slot++) {
      final locked = board.isLocked(slot);
      final bounds = tiling.cellBounds(slot, boardSize);
      final poly = tiling.polygon(slot, boardSize);
      final rect = poly.length == 4 && poly.every((p) => (p.dx - bounds.left).abs() < 0.01 || (p.dx - bounds.right).abs() < 0.01);
      canvas.save();
      if (rect) {
        canvas.clipRect(bounds);
      } else {
        canvas.clipPath(Path()..addPolygon(poly, true));
      }
      canvas.drawImageRect(image, tiling.sourceRect(board.slots[slot], crop), bounds, painting && !locked ? grey : colour);
      if (!locked) canvas.drawRect(bounds, shade);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MiniBoardPainter old) => old.board != board || old.image != image || old.painting != painting || old.boardSize != boardSize;
}

class _ViewPainter extends CustomPainter {
  _ViewPainter({required this.view, required this.selected, required this.accent});
  final Rect view;
  final Offset? selected;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final r = view.intersect(Offset.zero & size);
    // Everything outside the view a touch darker, the view outlined.
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)));
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.22));
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.deflate(0.75), const Radius.circular(3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.inflate(0.75), const Radius.circular(3.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accent,
    );
    final s = selected;
    if (s != null) {
      canvas.drawCircle(s, 4.2, Paint()..color = Colors.white);
      canvas.drawCircle(s, 2.8, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(_ViewPainter old) => old.view != view || old.selected != selected || old.accent != accent;
}

/// While zoomed in with a card selected that is out of view: a small round
/// pointer on the edge of the view, turned towards the card. Tap it to bring
/// the card back into view.
class OffscreenSelection extends StatelessWidget {
  const OffscreenSelection({super.key, required this.zoom, required this.board, required this.boardSize, required this.selected});
  final BoardZoom zoom;
  final Board board;
  final Size boardSize;
  final int? selected;

  static const _size = 36.0;

  @override
  Widget build(BuildContext context) {
    final slot = selected;
    if (slot == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: zoom,
      builder: (context, _) {
        if (!zoom.zoomed) return const SizedBox.shrink();
        final centre = board.tiling.cellCenter(slot, boardSize);
        final p = zoom.toViewport(centre);
        final view = Offset.zero & boardSize;
        if (view.deflate(4).contains(p)) return const SizedBox.shrink();
        final inset = view.deflate(_size / 2 + 6);
        final at = Offset(p.dx.clamp(inset.left, inset.right), p.dy.clamp(inset.top, inset.bottom));
        final angle = math.atan2(p.dy - at.dy, p.dx - at.dx) + math.pi / 2;
        return Positioned(
          left: at.dx - _size / 2,
          top: at.dy - _size / 2,
          child: Pressable(
            key: const ValueKey('giant-offscreen-selection'),
            onTap: () => zoom.centreOn(centre),
            child: Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                color: context.accent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3))],
              ),
              child: Transform.rotate(angle: angle, child: const Icon(AppIcons.towards, size: 18, color: Colors.white)),
            ),
          ),
        );
      },
    );
  }
}

/// Calm milestones on a long board: the frame done (every edge card in
/// place) and halfway, each shown once per board as a toast.
class GiantMilestones extends StatefulWidget {
  const GiantMilestones({super.key, required this.board, required this.playing, this.onFrame});
  final Board board;
  final bool playing;

  /// The frame was just completed (the Edges filter has nothing left to show).
  final VoidCallback? onFrame;

  @override
  State<GiantMilestones> createState() => _GiantMilestonesState();
}

class _GiantMilestonesState extends State<GiantMilestones> {
  // What was already done when the board opened (a resumed board past
  // halfway says nothing).
  late bool _frame;
  late bool _half;

  @override
  void initState() {
    super.initState();
    _frame = _frameDone(widget.board);
    _half = _halfDone(widget.board);
  }

  static bool _frameDone(Board b) {
    for (var s = 0; s < b.cells; s++) {
      if (isEdgeCard(b.tiling, s) && !b.isLocked(s)) return false;
    }
    return true;
  }

  static bool _halfDone(Board b) {
    var locked = 0;
    for (var s = 0; s < b.cells; s++) {
      if (b.isLocked(s)) locked++;
    }
    return locked * 2 >= b.cells;
  }

  @override
  void didUpdateWidget(GiantMilestones old) {
    super.didUpdateWidget(old);
    if (old.board == widget.board) return;
    final frame = _frameDone(widget.board), half = _halfDone(widget.board);
    final solved = widget.board.isSolved;
    if (widget.playing && !solved) {
      if (frame && !_frame) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showToast(context, 'Frame complete', icon: AppIcons.edges);
          widget.onFrame?.call();
        });
      } else if (half && !_half) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) showToast(context, 'Halfway there', icon: AppIcons.puzzle);
        });
      }
    }
    _frame = frame;
    _half = half;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
