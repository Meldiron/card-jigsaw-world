import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/theme/tokens.dart';
import '../../game/board.dart';
import '../../game/game_controller.dart';
import '../../state/settings.dart';

/// Interactive board for every tiling (cards, squares, triangles, hexagons).
///
/// Cards animate between slots. Correctly adjacent cards form groups: the
/// gutter closes on every edge shared with a member of the same group, so the
/// group reads as one piece, and a floating group carries an accent border
/// along its outer edges and moves as one when dragged. Cards locked in place
/// lose border, shadow and the accent, and cards not yet in place sit a touch
/// darker, so the picture lights up as it completes. One code path serves all
/// four modes: every edge only asks who is on the other side.
class BoardWidget extends StatefulWidget {
  const BoardWidget({
    super.key,
    required this.image,
    required this.state,
    required this.onTap,
    required this.onDrop,
    required this.cardStyle,
    required this.width,
    required this.height,
  });

  final ui.Image image;
  final GameState state;
  final void Function(int slot) onTap;
  final void Function(int from, int to) onDrop;
  final CardStyle cardStyle;
  final double width;
  final double height;

  @override
  State<BoardWidget> createState() => _BoardWidgetState();
}

class _BoardWidgetState extends State<BoardWidget> {
  int? _dragSlot; // the card under the finger
  Offset _dragDelta = Offset.zero; // how far the finger moved since pan start
  int? _hoverSlot; // slot under the dragged card's centre

  Tiling get tiling => widget.state.board.tiling;
  Size get boardSize => Size(widget.width, widget.height);

  /// The part of the picture the board shows: a centre crop with the board's
  /// aspect, so hexagons and triangles keep their regular shape whatever the
  /// picture's proportions (the peek overlay uses the same `BoxFit.cover`).
  Rect get imageCrop => tiling.crop(Size(widget.image.width.toDouble(), widget.image.height.toDouble()), boardSize);

  /// Destination cells of the dragged group if dropped on the hovered slot.
  Set<int> _hoverTargets() {
    final d = _dragSlot, h = _hoverSlot;
    if (d == null || h == null || d == h) return const {};
    final delta = tiling.delta(d, h);
    if (delta == null) return const {};
    final out = <int>{};
    for (final s in widget.state.board.groupOf(d)) {
      final t = tiling.apply(s, delta.$1, delta.$2);
      if (t == null) return const {};
      out.add(t);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final board = widget.state.board;
    final c = context.colors;
    final cell = tiling.cellSize(boardSize);
    final gap = widget.cardStyle == CardStyle.classic ? math.max(6.0, cell * 0.08) : 2.0;
    final radius = widget.cardStyle == CardStyle.classic ? math.min(18.0, cell * 0.17) : 8.0;
    final dragGroup = _dragSlot == null ? const <int>{} : board.groupOf(_dragSlot!).toSet();
    final selectedGroup = widget.state.selectedGroup.toSet();
    final hintGroup = widget.state.hintSlot == null ? const <int>{} : {widget.state.hintSlot!};
    final targets = _hoverTargets();
    final targetsValid = targets.isNotEmpty && !targets.any((t) => board.isLocked(t) && !dragGroup.contains(t));

    // Render order: locked, free, selected/hinted, dragged group last.
    final order = List<int>.generate(board.cells, (i) => i)
      ..sort((a, b) {
        int rank(int s) {
          if (dragGroup.contains(s)) return 3;
          if (selectedGroup.contains(s) || hintGroup.contains(s)) return 2;
          return board.isLocked(s) ? 0 : 1;
        }
        return rank(a).compareTo(rank(b));
      });

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(color: c.boardBackground, borderRadius: BorderRadius.circular(radius + 2)),
            ),
          ),
          if (widget.state.hintTarget != null)
            Positioned.fromRect(
              rect: tiling.cellBounds(widget.state.hintTarget!, boardSize),
              child: _PulseRing(
                color: Brand.star,
                polygon: _local(tiling.polygon(widget.state.hintTarget!, boardSize), tiling.cellBounds(widget.state.hintTarget!, boardSize)),
              ),
            ),
          for (final slot in order)
            _buildCard(
              slot,
              gap,
              radius,
              dragging: dragGroup.contains(slot),
              selected: selectedGroup.contains(slot) || hintGroup.contains(slot),
              hovered: targets.contains(slot) && !dragGroup.contains(slot) ? (targetsValid ? _Hover.ok : _Hover.blocked) : _Hover.none,
            ),
          if (widget.state.peeking)
            Positioned.fill(
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 220),
                  builder: (_, v, child) => Opacity(opacity: v * 0.92, child: child),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius + 2),
                    child: RawImage(image: widget.image, fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static List<Offset> _local(List<Offset> poly, Rect bounds) => [for (final p in poly) p - bounds.topLeft];

  bool _onGroupBoundary(Board board, int slot, int k, int groupId) {
    final around = tiling.cornerNeighbours(slot, k);
    return around.length + 1 < tiling.vertexValence || around.any((s) => board.groupIdOf(s) != groupId);
  }

  Widget _buildCard(int slot, double gap, double radius, {required bool dragging, required bool selected, required _Hover hovered}) {
    final state = widget.state;
    final board = state.board;
    final card = board.slots[slot];
    final locked = board.isLocked(slot);
    final justLocked = state.justLocked.contains(slot);
    final justJoined = state.justJoined.contains(slot);
    final bounds = tiling.cellBounds(slot, boardSize);
    final origin = dragging ? bounds.topLeft + _dragDelta : bounds.topLeft;
    final grouped = board.groupOf(slot).length > 1;
    final localPoly = _local(tiling.polygon(slot, boardSize), bounds);

    // Edges shared with a member of the same group (locked clusters are
    // groups too): the gutter closes there so the group reads as one piece.
    // Board edges and other neighbours keep the gutter, so a lone cell keeps
    // its size.
    final groupId = board.groupIdOf(slot);
    final fusedEdges = [for (final n in tiling.edgeNeighbours(slot)) n != null && board.groupIdOf(n) == groupId];
    // A vertex between two fused edges that still lies on the group's
    // boundary (a cell around it is outside the group, or off the board):
    // the neighbours' strokes stop there, so this cell fills the corner.
    final n = fusedEdges.length;
    final corners = [
      for (var k = 0; k < n; k++)
        fusedEdges[(k - 1 + n) % n] && fusedEdges[k] && _onGroupBoundary(board, slot, k, groupId),
    ];

    Widget child = _CardFace(
      image: widget.image,
      polygon: localPoly,
      source: tiling.sourceRect(card, imageCrop),
      locked: locked,
      gap: gap,
      radius: radius,
      selected: selected || dragging,
      hovered: hovered,
      lift: dragging ? 1.0 : (selected ? 0.5 : 0),
      cardStyle: widget.cardStyle,
      fusedEdges: fusedEdges,
      corners: corners,
      grouped: grouped,
    );
    if (justLocked || justJoined) {
      child = _LockPulse(key: ValueKey('pulse-$slot-${state.tick}'), strong: justLocked, child: child);
    }

    return AnimatedPositioned(
      key: ValueKey('card-$card'),
      duration: dragging ? Duration.zero : const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      left: origin.dx,
      top: origin.dy,
      width: bounds.width,
      height: bounds.height,
      child: _PolygonHitTest(
        polygon: localPoly,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onTap(slot),
          onPanStart: locked || state.status != GameStatus.playing
              ? null
              : (_) => setState(() {
                    _dragSlot = slot;
                    _dragDelta = Offset.zero;
                    _hoverSlot = slot;
                  }),
          onPanUpdate: locked
              ? null
              : (d) {
                  if (_dragSlot != slot) return;
                  setState(() {
                    _dragDelta += d.delta;
                    _hoverSlot = tiling.slotAt(tiling.cellCenter(slot, boardSize) + _dragDelta, boardSize);
                  });
                },
          onPanEnd: locked
              ? null
              : (_) {
                  if (_dragSlot != slot) return;
                  final target = tiling.slotAt(tiling.cellCenter(slot, boardSize) + _dragDelta, boardSize);
                  setState(() {
                    _dragSlot = null;
                    _hoverSlot = null;
                    _dragDelta = Offset.zero;
                  });
                  if (target != null && target != slot) widget.onDrop(slot, target);
                },
          onPanCancel: () {
            if (_dragSlot == slot) {
              setState(() {
                _dragSlot = null;
                _hoverSlot = null;
                _dragDelta = Offset.zero;
              });
            }
          },
          child: AnimatedScale(
            scale: dragging ? 1.06 : (selected ? 1.03 : 1),
            duration: const Duration(milliseconds: 140),
            child: child,
          ),
        ),
      ),
    );
  }
}

enum _Hover { none, ok, blocked }

/// Limits hit-testing to the cell's polygon so overlapping bounding boxes
/// (triangles, hexagons) route taps to the right card.
class _PolygonHitTest extends SingleChildRenderObjectWidget {
  const _PolygonHitTest({required this.polygon, required super.child});
  final List<Offset> polygon;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPolygonHitTest(polygon);

  @override
  void updateRenderObject(BuildContext context, _RenderPolygonHitTest renderObject) {
    renderObject.polygon = polygon;
  }
}

class _RenderPolygonHitTest extends RenderProxyBox {
  _RenderPolygonHitTest(this.polygon);
  List<Offset> polygon;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!_inside(position)) return false;
    return super.hitTest(result, position: position);
  }

  bool _inside(Offset p) {
    var sign = 0;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i], b = polygon[(i + 1) % polygon.length];
      final cross = (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx);
      if (cross.abs() < 1e-9) continue;
      final s = cross > 0 ? 1 : -1;
      if (sign == 0) {
        sign = s;
      } else if (s != sign) {
        return false;
      }
    }
    return true;
  }
}

/// Paints one card: its slice of the image with border, shadow and state
/// outline. The same treatment applies to every tiling:
///
/// * free: gutter, border (classic style), soft shadow, a slight dim;
/// * grouped: the gutter closes towards members of the same group and a
///   2 px accent border runs along the group's outer edges;
/// * selected / dragged: ink outline along the outer edges, lift (shadow +
///   scale);
/// * locked: full brightness, no border, shadow or accent; the gutter closes
///   towards other locked cards.
///
/// The dim is one flat overlay clipped to the card's own shape. Fused cards
/// abut exactly, so a group darkens evenly with no seam or double layer.
class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.image,
    required this.polygon,
    required this.source,
    required this.locked,
    required this.gap,
    required this.radius,
    required this.selected,
    required this.hovered,
    required this.lift,
    required this.cardStyle,
    required this.fusedEdges,
    required this.corners,
    required this.grouped,
  });

  final ui.Image image;
  final List<Offset> polygon;
  final Rect source;
  final bool locked;
  final double gap;
  final double radius;
  final bool selected;
  final _Hover hovered;
  final double lift;
  final CardStyle cardStyle;
  final List<bool> fusedEdges;
  final List<bool> corners;
  final bool grouped;

  static const _selectionStroke = 5.6;

  /// Drawn at twice this inside the clip, so 2 px show.
  static const _groupStroke = 4.0;

  /// Flat darkening over cards that are not in place yet.
  static const _dim = 0.16;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // The edge colour is "ink": near-black on the light theme (where the card
    // border is white) and white on the dark theme (where the border is dark
    // grey), so it always contrasts with the border.
    final ink = context.isDark ? Colors.white : const Color(0xFF111118);
    final half = gap / 2;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: locked ? 1 : 0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (_, lockT, _) => TweenAnimationBuilder<_EdgeInsets>(
        // Each edge's gutter slides shut as the card snaps to its group, in
        // step with the card's own move.
        tween: _EdgeInsetsTween(end: _EdgeInsets([for (final fused in fusedEdges) fused ? 0.0 : half])),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        builder: (_, insets, _) {
          // Interaction language: a picked-up card lifts (shadow + scale) and
          // gets an ink edge; the drop target brightens; a blocked target dims
          // with a red edge; a floating group shares one accent edge. No colour
          // casts over the picture.
          final Color? outline;
          final double stroke;
          var outerOnly = true;
          if (selected) {
            outline = ink;
            stroke = _selectionStroke;
          } else if (hovered == _Hover.ok) {
            outline = ink;
            stroke = _selectionStroke;
            outerOnly = false;
          } else if (hovered == _Hover.blocked) {
            outline = Brand.danger;
            stroke = _selectionStroke;
            outerOnly = false;
          } else if (grouped && !locked) {
            outline = context.accent;
            stroke = _groupStroke;
          } else {
            outline = null;
            stroke = 0;
          }
          return CustomPaint(
            painter: _CardPainter(
              image: image,
              polygon: polygon,
              source: source,
              insets: insets.values,
              radius: radius,
              fusedEdges: fusedEdges,
              corners: corners,
              borderColor: cardStyle == CardStyle.classic ? c.cardFace : Colors.transparent,
              borderWidth: cardStyle == CardStyle.classic ? math.max(1.5, gap * 0.55) * (1 - lockT) : 0,
              shadow: lockT > 0.95 || lift == 0 ? null : Colors.black.withValues(alpha: (0.25 + 0.2 * lift) * (1 - lockT)),
              shadowBlur: 10 + lift * 20,
              shadowDy: 4 + lift * 10,
              tint: hovered == _Hover.ok
                  ? Colors.white.withValues(alpha: 0.28)
                  : hovered == _Hover.blocked
                      ? Colors.black.withValues(alpha: 0.35)
                      : null,
              dim: _dim * (1 - lockT),
              outline: outline,
              outlineWidth: stroke,
              outlineOuterOnly: outerOnly,
            ),
          );
        },
      ),
    );
  }
}

/// Per-edge gutter insets with value equality, so the implicit animation only
/// restarts when an edge actually opens or closes.
class _EdgeInsets {
  const _EdgeInsets(this.values);
  final List<double> values;

  @override
  bool operator ==(Object other) {
    if (other is! _EdgeInsets || other.values.length != values.length) return false;
    for (var i = 0; i < values.length; i++) {
      if (other.values[i] != values[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(values);
}

class _EdgeInsetsTween extends Tween<_EdgeInsets> {
  _EdgeInsetsTween({super.end});

  @override
  _EdgeInsets lerp(double t) {
    final a = begin ?? end!, b = end!;
    return _EdgeInsets([for (var i = 0; i < b.values.length; i++) (i < a.values.length ? a.values[i] : b.values[i]) + (b.values[i] - (i < a.values.length ? a.values[i] : b.values[i])) * t]);
  }
}

class _CardPainter extends CustomPainter {
  _CardPainter({
    required this.image,
    required this.polygon,
    required this.source,
    required this.insets,
    required this.radius,
    required this.fusedEdges,
    required this.corners,
    required this.borderColor,
    required this.borderWidth,
    required this.shadow,
    required this.shadowBlur,
    required this.shadowDy,
    required this.tint,
    required this.dim,
    required this.outline,
    required this.outlineWidth,
    required this.outlineOuterOnly,
  });

  final ui.Image image;
  final List<Offset> polygon;
  final Rect source;

  /// Gutter inset per polygon edge (edge k runs from vertex k to k+1).
  final List<double> insets;
  final double radius;
  final List<bool> fusedEdges;

  /// Vertices between two fused edges that lie on the group's boundary.
  final List<bool> corners;
  final Color borderColor;
  final double borderWidth;
  final Color? shadow;
  final double shadowBlur;
  final double shadowDy;
  final Color? tint;

  /// Alpha of the flat black overlay (0 for a card in place).
  final double dim;
  final Color? outline;
  final double outlineWidth;

  /// Whether the outline follows only the open (non-fused) edges, so a fused
  /// group gets one border around its outside; otherwise the whole shape.
  final bool outlineOuterOnly;

  /// The card polygon with every edge moved inward by its inset.
  List<Offset> _shrunk() {
    final n = polygon.length;
    var cx = 0.0, cy = 0.0;
    for (final p in polygon) {
      cx += p.dx;
      cy += p.dy;
    }
    final centroid = Offset(cx / n, cy / n);
    // Offset each edge line inward, then intersect consecutive lines.
    final lines = <(Offset, Offset)>[];
    for (var i = 0; i < n; i++) {
      final a = polygon[i], b = polygon[(i + 1) % n];
      final d = insets[i];
      final edge = b - a;
      final len = edge.distance;
      if (len == 0) {
        lines.add((a, b));
        continue;
      }
      var normal = Offset(-edge.dy / len, edge.dx / len);
      final mid = (a + b) / 2;
      if ((centroid - mid).dx * normal.dx + (centroid - mid).dy * normal.dy < 0) normal = -normal;
      lines.add((a + normal * d, b + normal * d));
    }
    final out = <Offset>[];
    for (var i = 0; i < n; i++) {
      final prev = lines[(i - 1 + n) % n], cur = lines[i];
      out.add(_intersect(prev.$1, prev.$2, cur.$1, cur.$2) ?? cur.$1);
    }
    return out;
  }

  static Offset? _intersect(Offset p1, Offset p2, Offset p3, Offset p4) {
    final d = (p1.dx - p2.dx) * (p3.dy - p4.dy) - (p1.dy - p2.dy) * (p3.dx - p4.dx);
    if (d.abs() < 1e-9) return null;
    final t = ((p1.dx - p3.dx) * (p3.dy - p4.dy) - (p1.dy - p3.dy) * (p3.dx - p4.dx)) / d;
    return Offset(p1.dx + t * (p2.dx - p1.dx), p1.dy + t * (p2.dy - p1.dy));
  }

  /// Closed shape path: shrunk polygon with corners rounded where neither
  /// adjoining edge is fused to a locked neighbour.
  Path _shape(List<Offset> pts) {
    final n = pts.length;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final prev = pts[(i - 1 + n) % n], cur = pts[i], next = pts[(i + 1) % n];
      final r = _cornerRadius(pts, i);
      if (r <= 0.5) {
        i == 0 ? path.moveTo(cur.dx, cur.dy) : path.lineTo(cur.dx, cur.dy);
        continue;
      }
      final inDir = (cur - prev) / (cur - prev).distance;
      final outDir = (next - cur) / (next - cur).distance;
      final a = cur - inDir * r;
      final b = cur + outDir * r;
      i == 0 ? path.moveTo(a.dx, a.dy) : path.lineTo(a.dx, a.dy);
      path.quadraticBezierTo(cur.dx, cur.dy, b.dx, b.dy);
    }
    path.close();
    return path;
  }

  /// Corner radius used by [_shape] at vertex [i] (0 where an adjoining edge
  /// is fused, so fused cells meet in a straight line).
  double _cornerRadius(List<Offset> pts, int i) {
    final n = pts.length;
    if (fusedEdges[(i - 1 + n) % n] || fusedEdges[i]) return 0;
    final prev = pts[(i - 1 + n) % n], cur = pts[i], next = pts[(i + 1) % n];
    return math.min(radius, math.min((cur - prev).distance, (next - cur).distance) / 2.2);
  }

  /// The open (non-fused) edges as stroke runs: rounded where two open edges
  /// meet, and overshooting by [ext] where an open edge meets a fused one so
  /// the runs of neighbouring cells join without a notch (the clip trims the
  /// overshoot). With nothing fused this is the whole rounded shape.
  Path _outline(List<Offset> pts, double ext) {
    final n = pts.length;
    if (!fusedEdges.contains(true)) return _shape(pts);
    final path = Path();
    // Start the walk just after a fused edge so no run wraps around.
    final start = (fusedEdges.indexOf(true) + 1) % n;
    var down = false;
    for (var k = 0; k < n; k++) {
      final i = (start + k) % n;
      final prev = pts[(i - 1 + n) % n], cur = pts[i], next = pts[(i + 1) % n];
      final prevOpen = !fusedEdges[(i - 1 + n) % n], curOpen = !fusedEdges[i];
      if (prevOpen && curOpen) {
        final r = _cornerRadius(pts, i);
        if (r <= 0.5) {
          down ? path.lineTo(cur.dx, cur.dy) : path.moveTo(cur.dx, cur.dy);
        } else {
          final inDir = (cur - prev) / (cur - prev).distance;
          final outDir = (next - cur) / (next - cur).distance;
          final a = cur - inDir * r, b = cur + outDir * r;
          down ? path.lineTo(a.dx, a.dy) : path.moveTo(a.dx, a.dy);
          path.quadraticBezierTo(cur.dx, cur.dy, b.dx, b.dy);
        }
        down = true;
      } else if (prevOpen) {
        final inDir = (cur - prev) / (cur - prev).distance;
        final e = cur + inDir * ext;
        down ? path.lineTo(e.dx, e.dy) : path.moveTo(e.dx, e.dy);
        down = false;
      } else if (curOpen) {
        final outDir = (next - cur) / (next - cur).distance;
        final e = cur - outDir * ext;
        path.moveTo(e.dx, e.dy);
        down = true;
      }
    }
    return path;
  }

  /// Band fill at a vertex between two fused edges where the group boundary
  /// turns: the square (grid) or disc sector (triangles) of radius [r] that
  /// a continuous stroke along the group's outside would leave there.
  Path _cornerPatch(List<Offset> pts, int k, double r) {
    final n = pts.length;
    final v = pts[k];
    final u1 = (pts[(k - 1 + n) % n] - v), u2 = (pts[(k + 1) % n] - v);
    if (u1.distance == 0 || u2.distance == 0) return Path();
    final a = u1 / u1.distance, b = u2 / u2.distance;
    final cosAngle = a.dx * b.dx + a.dy * b.dy;
    final path = Path()..moveTo(v.dx, v.dy);
    if (cosAngle < 0.1) {
      // Right angle or wider: the parallelogram spanned by the two edges.
      final p = v + a * r, q = v + a * r + b * r, s = v + b * r;
      path
        ..lineTo(p.dx, p.dy)
        ..lineTo(q.dx, q.dy)
        ..lineTo(s.dx, s.dy);
    } else {
      // Acute: a sector, approximated by a short polyline.
      const steps = 4;
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final d = a * (1 - t) + b * t;
        final p = v + d / d.distance * r;
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pts = _shrunk();
    final shape = _shape(pts);
    if (shadow != null) {
      canvas.drawPath(shape.shift(Offset(0, shadowDy)), Paint()..color = shadow!..maskFilter = MaskFilter.blur(BlurStyle.normal, shadowBlur / 2));
    }
    canvas.save();
    canvas.clipPath(shape);
    // The image slice always maps to the full cell bounds; the clip trims the gutter.
    canvas.drawImageRect(image, source, Offset.zero & size, Paint()..filterQuality = FilterQuality.medium);
    if (tint != null) canvas.drawRect(Offset.zero & size, Paint()..color = tint!);
    // One flat layer over the whole clip: cards not yet in place sit a touch
    // darker, and the picture brightens as it locks.
    if (dim > 0) canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withValues(alpha: dim));
    // Strokes are drawn at twice the width inside the clip, so exactly half
    // shows: the visible band hugs the edge without bleeding into the gutter.
    if (borderWidth > 0) {
      canvas.drawPath(_outline(pts, borderWidth * 2), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth * 2
        ..color = borderColor);
    }
    if (outline != null && outlineWidth > 0) {
      canvas.drawPath(outlineOuterOnly ? _outline(pts, outlineWidth) : shape, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outlineWidth
        ..color = outline!);
    }
    for (var k = 0; k < corners.length; k++) {
      if (!corners[k]) continue;
      if (borderWidth > 0) canvas.drawPath(_cornerPatch(pts, k, borderWidth), Paint()..color = borderColor);
      if (outline != null && outlineWidth > 0 && outlineOuterOnly) {
        canvas.drawPath(_cornerPatch(pts, k, outlineWidth / 2), Paint()..color = outline!);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CardPainter o) =>
      o.image != image ||
      o.source != source ||
      o.radius != radius ||
      !_sameList(o.insets, insets) ||
      !_sameList(o.fusedEdges, fusedEdges) ||
      !_sameList(o.corners, corners) ||
      !_sameList(o.polygon, polygon) ||
      o.tint != tint ||
      o.outline != outline ||
      o.outlineWidth != outlineWidth ||
      o.outlineOuterOnly != outlineOuterOnly ||
      o.dim != dim ||
      o.borderWidth != borderWidth ||
      o.shadow != shadow;

  static bool _sameList(List<Object> a, List<Object> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Flash + scale pop played when a card locks in place (strong) or snaps to a
/// neighbour (soft).
class _LockPulse extends StatefulWidget {
  const _LockPulse({super.key, required this.child, required this.strong});
  final Widget child;
  final bool strong;
  @override
  State<_LockPulse> createState() => _LockPulseState();
}

class _LockPulseState extends State<_LockPulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520))..forward();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.strong ? Brand.star : Colors.white;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = _c.value;
        final scale = 1 + math.sin(t * math.pi) * (widget.strong ? 0.1 : 0.05);
        return Transform.scale(
          scale: scale,
          child: Stack(
            fit: StackFit.expand,
            children: [
              child!,
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: (1 - t) * (widget.strong ? 0.55 : 0.3)),
                    boxShadow: [BoxShadow(color: color.withValues(alpha: (1 - t) * 0.8), blurRadius: 24 * (1 - t) + 4, spreadRadius: 2)],
                  ),
                ),
              ),
            ],
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Pulsing outline used to show where a hinted card belongs.
class _PulseRing extends StatefulWidget {
  const _PulseRing({required this.color, required this.polygon});
  final Color color;
  final List<Offset> polygon;
  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => CustomPaint(painter: _PulsePainter(polygon: widget.polygon, color: widget.color, t: _c.value)),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({required this.polygon, required this.color, required this.t});
  final List<Offset> polygon;
  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (polygon.isEmpty) return;
    final path = Path()..moveTo(polygon.first.dx, polygon.first.dy);
    for (final p in polygon.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.5 * t)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color.withValues(alpha: 0.5 + t * 0.5));
  }

  @override
  bool shouldRepaint(_PulsePainter o) => o.t != t || o.color != color || o.polygon != polygon;
}
