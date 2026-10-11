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

  static double _norm(double a) {
    while (a <= -math.pi) {
      a += 2 * math.pi;
    }
    while (a > math.pi) {
      a -= 2 * math.pi;
    }
    return a;
  }

  /// Angular wedge `(start, span)` of cell [s] at its vertex [v], with the
  /// span positive clockwise on screen; null when [v] is not a vertex of [s].
  (double, double)? _wedge(int s, Offset v) {
    final poly = tiling.polygon(s, boardSize);
    for (var i = 0; i < poly.length; i++) {
      if ((poly[i] - v).distance > 0.01) continue;
      final a = poly[(i - 1 + poly.length) % poly.length] - v, b = poly[(i + 1) % poly.length] - v;
      final ta = math.atan2(a.dy, a.dx), tb = math.atan2(b.dy, b.dx);
      final sweep = _norm(tb - ta);
      return sweep > 0 ? (ta, sweep) : (tb, -sweep);
    }
    return null;
  }

  /// The group's fan at vertex [k] of [slot]: the contiguous run of group
  /// cells around that vertex that includes this cell, as an angular range.
  /// Its two bounding rays are the open edges the outline follows into and
  /// out of the vertex, so every cell on the fan can draw the exact band
  /// (straight, rounded concave or rounded convex) through its own clip.
  /// Null where this cell has no fused edge at the vertex (an ordinary
  /// rounded corner) or where the group surrounds the vertex completely.
  _Fan? _fan(Board board, int slot, int k, int groupId, List<bool> fused) {
    final n = fused.length;
    if (!fused[(k - 1 + n) % n] && !fused[k]) return null;
    final v = tiling.polygon(slot, boardSize)[k];
    var (start, span) = _wedge(slot, v)!;
    final others = <(double, double)>[
      for (final s in tiling.cornerNeighbours(slot, k))
        if (board.groupIdOf(s) == groupId) ?_wedge(s, v),
    ];
    var grew = true;
    while (grew && span < 2 * math.pi - 1e-3) {
      grew = false;
      for (var i = 0; i < others.length; i++) {
        final w = others[i];
        if (_norm(w.$1 + w.$2 - start).abs() < 1e-3) {
          start = w.$1;
          span += w.$2;
        } else if (_norm(start + span - w.$1).abs() < 1e-3) {
          span += w.$2;
        } else {
          continue;
        }
        others.removeAt(i);
        grew = true;
        break;
      }
    }
    if (span >= 2 * math.pi - 1e-3) return null;
    return _Fan(_norm(start), span);
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
    // Where the group's outline passes a vertex of this cell next to a fused
    // edge, the cell needs to know how the group continues around it.
    final fans = [for (var k = 0; k < fusedEdges.length; k++) _fan(board, slot, k, groupId, fusedEdges)];

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
      fans: fans,
      gutterHalf: gap / 2,
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

/// The group's angular coverage around one vertex of a card: a run of
/// [span] radians clockwise on screen from [start], bounded by the two open
/// edges that leave the vertex (rays [d1] and [d2]). More than a half turn
/// is a concave corner of the group's outline, less than a half turn a
/// convex corner shared by two fused cells, exactly a half turn a straight
/// stretch passing the vertex.
class _Fan {
  const _Fan(this.start, this.span);
  final double start;
  final double span;

  bool get concave => span > math.pi + 1e-3;
  bool get convex => span < math.pi - 1e-3;
  double get end => start + span;
  Offset get d1 => Offset(math.cos(start), math.sin(start));
  Offset get d2 => Offset(math.cos(end), math.sin(end));

  /// Inward normals of the two open edges (angles).
  double get n1 => start + math.pi / 2;
  double get n2 => end - math.pi / 2;

  @override
  bool operator ==(Object other) => other is _Fan && (other.start - start).abs() < 1e-9 && (other.span - span).abs() < 1e-9;
  @override
  int get hashCode => Object.hash(start, span);
}

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
    required this.fans,
    required this.gutterHalf,
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
  final List<_Fan?> fans;
  final double gutterHalf;
  final bool grouped;

  static const _selectionStroke = 5.6;

  /// Drawn at twice this inside the clip, so 2 px show.
  static const _groupStroke = 4.0;

  /// Fused edges reach this far past the cell edge so two abutting clips
  /// overlap by a pixel: antialiasing on a diagonal seam (triangles,
  /// hexagons) otherwise lets the background show through as a hairline.
  /// The picture is continuous across a fused edge, so the overdraw shows
  /// the right pixels.
  static const _overlap = 0.5;

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
        tween: _EdgeInsetsTween(end: _EdgeInsets([for (final fused in fusedEdges) fused ? -_overlap : half])),
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
              fans: fans,
              gutterHalf: gutterHalf,
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
    required this.fans,
    required this.gutterHalf,
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

  /// How the group continues around each vertex (see [_Fan]); null where
  /// the vertex needs no special treatment.
  final List<_Fan?> fans;

  /// Half the gutter: the inset of every open edge once the card is at rest.
  final double gutterHalf;
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

  /// Closed shape path: shrunk polygon with corners rounded where both
  /// adjoining edges are open, and half of a rounded corner where this cell
  /// and a fused neighbour share a convex corner of the group (the 120°
  /// corners of two triangles), so the group's corners all look alike.
  Path _shape(List<Offset> pts) {
    final n = pts.length;
    final path = Path();
    void to(Offset p, {required bool first}) => first ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    for (var i = 0; i < n; i++) {
      final prev = pts[(i - 1 + n) % n], cur = pts[i], next = pts[(i + 1) % n];
      final prevOpen = !fusedEdges[(i - 1 + n) % n], curOpen = !fusedEdges[i];
      if (prevOpen != curOpen) {
        final cc = _convexCorner(pts, i, incoming: prevOpen);
        if (cc != null) {
          if (prevOpen) {
            to(cc.t, first: i == 0);
            path.quadraticBezierTo(cc.ctrl.dx, cc.ctrl.dy, cc.q.dx, cc.q.dy);
          } else {
            to(cc.q, first: i == 0);
            path.quadraticBezierTo(cc.ctrl.dx, cc.ctrl.dy, cc.t.dx, cc.t.dy);
          }
          continue;
        }
      }
      if (!(prevOpen && curOpen) && fans[i] != null && !fans[i]!.convex) {
        _concaveCorner(path, pts, i, start: i == 0);
        continue;
      }
      final r = _cornerRadius(pts, i);
      if (r <= 0.5) {
        to(cur, first: i == 0);
        continue;
      }
      final inDir = (cur - prev) / (cur - prev).distance;
      final outDir = (next - cur) / (next - cur).distance;
      to(cur - inDir * r, first: i == 0);
      final b = cur + outDir * r;
      path.quadraticBezierTo(cur.dx, cur.dy, b.dx, b.dy);
    }
    path.close();
    return path;
  }

  /// Perpendicular foot of [v] on the line through [a] and [b].
  static Offset _foot(Offset a, Offset b, Offset v) {
    final d = b - a;
    final len2 = d.dx * d.dx + d.dy * d.dy;
    if (len2 == 0) return a;
    return a + d * (((v - a).dx * d.dx + (v - a).dy * d.dy) / len2);
  }

  /// A convex corner of the group shared with the fused neighbour at vertex
  /// [i] (the fan there spans less than a half turn): the corner [p] of the
  /// group's inset outline, the tangent point [t] on this cell's open edge
  /// and the midpoint [q] of the rounded corner, which lies on the shared
  /// edge where the neighbour's half of the curve takes over. Null when the
  /// corner is not of that kind or too tight to round.
  ({Offset t, Offset ctrl, Offset q})? _convexCorner(List<Offset> pts, int i, {required bool incoming}) {
    final fan = fans[i];
    if (fan == null || !fan.convex) return null;
    final n = pts.length;
    final v = polygon[i];
    final h = gutterHalf;
    final l1 = v + Offset(math.cos(fan.n1), math.sin(fan.n1)) * h, l2 = v + Offset(math.cos(fan.n2), math.sin(fan.n2)) * h;
    final p = _intersect(l1, l1 + fan.d1, l2, l2 + fan.d2);
    if (p == null) return null;
    // Which of the fan's rays is this cell's own open edge?
    final e = (incoming ? polygon[(i - 1 + n) % n] : polygon[(i + 1) % n]) - v;
    if (e.distance == 0) return null;
    final u = e / e.distance;
    final ownIsFirst = u.dx * fan.d1.dx + u.dy * fan.d1.dy >= u.dx * fan.d2.dx + u.dy * fan.d2.dy;
    final own = ownIsFirst ? fan.d1 : fan.d2, far = ownIsFirst ? fan.d2 : fan.d1;
    final r = math.min(radius, e.distance / 2.2);
    // The rounding must reach past the shared edge into this cell.
    if (r <= (p - pts[i]).distance + 0.5) return null;
    final t = p + own * r, t2 = p + far * r;
    // The curve's midpoint sits on the shared edge; push it across by the
    // overlap like every other fused edge, so the two clips meet without
    // an antialiasing seam.
    final bisector = own + far;
    var across = Offset(-bisector.dy, bisector.dx) / bisector.distance;
    if (across.dx * own.dx + across.dy * own.dy > 0) across = -across;
    final q = (t + p * 2 + t2) / 4 + across * _CardFace._overlap;
    return (t: t, ctrl: (t + p) / 2, q: q);
  }

  /// Distance from [q] to the ray from [v] in direction [d] (unit).
  static double _rayDist(Offset q, Offset v, Offset d) {
    final w = q - v;
    if (w.dx * d.dx + w.dy * d.dy <= 0) return w.distance;
    return (w.dx * d.dy - w.dy * d.dx).abs();
  }

  /// Distance from [q] to the group's boundary near the fan's vertex [v]:
  /// the nearer of its two open rays.
  static double _boundaryDist(Offset q, Offset v, _Fan fan) => math.min(_rayDist(q, v, fan.d1), _rayDist(q, v, fan.d2));

  /// Where, walking from [from] towards [to] along a fused edge, the cell
  /// leaves the gutter band of the group's boundary (distance [h]).
  static Offset _cutPoint(Offset from, Offset to, Offset v, _Fan fan, double h) {
    if (_boundaryDist(from, v, fan) >= h) return from;
    if (_boundaryDist(to, v, fan) < h) return to;
    var lo = 0.0, hi = 1.0;
    for (var k = 0; k < 24; k++) {
      final mid = (lo + hi) / 2;
      if (_boundaryDist(from + (to - from) * mid, v, fan) < h) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return from + (to - from) * ((lo + hi) / 2);
  }

  /// Appends this cell's part of the group's inset boundary around the
  /// vertex [i] of a concave (or straight) fan: the lines parallel to the
  /// two open edges at the gutter inset, joined by an arc of that radius
  /// around the vertex. Every cell on the fan traces the same curve, so the
  /// pieces meet exactly on the fused edges and the picture, the card
  /// border and the accent all follow one continuous rounded outline; the
  /// vertex itself (and a middle cell's tip) stays inside the gutter.
  void _concaveCorner(Path path, List<Offset> pts, int i, {required bool start}) {
    final fan = fans[i]!;
    final n = pts.length;
    final v = polygon[i];
    final h = gutterHalf;
    final prev = pts[(i - 1 + n) % n], cur = pts[i], next = pts[(i + 1) % n];
    final prevOpen = !fusedEdges[(i - 1 + n) % n], curOpen = !fusedEdges[i];
    // Where the curve enters along the incoming edge and leaves along the
    // outgoing one: the tangent foot on an open (already inset) edge, the
    // crossing of the gutter band on a fused edge.
    final a = prevOpen ? _foot(prev, cur, v) : _cutPoint(cur, prev, v, fan, h);
    final b = curOpen ? _foot(cur, next, v) : _cutPoint(cur, next, v, fan, h);
    // Angles measured from the fan's first ray, and the curve's tangent
    // there (in the direction of growing angle).
    double u(Offset p) {
      var t = math.atan2(p.dy, p.dx) - fan.start;
      while (t < 0) {
        t += 2 * math.pi;
      }
      while (t >= 2 * math.pi) {
        t -= 2 * math.pi;
      }
      return t;
    }

    final lo = math.pi / 2, hi = math.max(lo, fan.span - math.pi / 2);
    Offset tangent(double t) {
      if (t < lo) return -fan.d1;
      if (t > hi) return fan.d2;
      return Offset(-math.sin(fan.start + t), math.cos(fan.start + t));
    }

    final ua = u(a - v), ub = u(b - v);
    final dir = ub >= ua ? 1.0 : -1.0;
    // Ends on a fused edge carry on by the overlap so the neighbour's
    // overdraw never covers the last half pixel of this cell's stroke.
    final a0 = prevOpen ? a : a - tangent(ua) * (dir * _CardFace._overlap);
    final b0 = curOpen ? b : b + tangent(ub) * (dir * _CardFace._overlap);
    start ? path.moveTo(a0.dx, a0.dy) : path.lineTo(a0.dx, a0.dy);
    if (a0 != a) path.lineTo(a.dx, a.dy);
    // The arc between the two parallel lines, as far as it runs through
    // this cell.
    final s = ua.clamp(lo, hi), e = ub.clamp(lo, hi);
    if ((e - s).abs() > 1e-6) path.arcTo(Rect.fromCircle(center: v, radius: h), fan.start + s, e - s, false);
    path.lineTo(b.dx, b.dy);
    if (b0 != b) path.lineTo(b0.dx, b0.dy);
  }

  /// Unit vector from [from] to [to] (zero when they coincide).
  static Offset _unit(Offset from, Offset to) {
    final d = to - from;
    return d.distance == 0 ? Offset.zero : d / d.distance;
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
  /// meet. Where an open edge meets a fused one the run ends at the foot of
  /// the vertex on the edge (where a concave corner's arc takes over, see
  /// [_fanBand]) or follows this cell's half of a shared convex corner; with
  /// no fan known it overshoots by [ext] so the neighbour's run meets it.
  /// With nothing fused this is the whole rounded shape.
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
        // An open run ends at a fused edge.
        final cc = _convexCorner(pts, i, incoming: true);
        if (cc != null) {
          down ? path.lineTo(cc.t.dx, cc.t.dy) : path.moveTo(cc.t.dx, cc.t.dy);
          path.quadraticBezierTo(cc.ctrl.dx, cc.ctrl.dy, cc.q.dx, cc.q.dy);
          final e = cc.q + _unit(cc.ctrl, cc.q) * _CardFace._overlap;
          path.lineTo(e.dx, e.dy);
        } else if (fans[i] != null) {
          _concaveCorner(path, pts, i, start: !down);
        } else {
          final inDir = (cur - prev) / (cur - prev).distance;
          final e = cur + inDir * ext;
          down ? path.lineTo(e.dx, e.dy) : path.moveTo(e.dx, e.dy);
        }
        down = false;
      } else if (curOpen) {
        // An open run starts at a fused edge.
        final cc = _convexCorner(pts, i, incoming: false);
        if (cc != null) {
          final s = cc.q - _unit(cc.q, cc.ctrl) * _CardFace._overlap;
          path.moveTo(s.dx, s.dy);
          path.lineTo(cc.q.dx, cc.q.dy);
          path.quadraticBezierTo(cc.ctrl.dx, cc.ctrl.dy, cc.t.dx, cc.t.dy);
        } else if (fans[i] != null) {
          _concaveCorner(path, pts, i, start: true);
        } else {
          final outDir = (next - cur) / (next - cur).distance;
          final e = cur - outDir * ext;
          path.moveTo(e.dx, e.dy);
        }
        down = true;
      } else if (fans[i] != null && !fans[i]!.convex) {
        // Both edges fused: only the corner curve passes through this cell.
        _concaveCorner(path, pts, i, start: true);
        down = false;
      }
    }
    return path;
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
    // The image slice maps to the cell bounds plus a pixel of overdraw (the
    // neighbouring picture, which is what shows across a fused edge); the
    // clip trims the gutter and everything beyond the shape.
    const over = 1.0;
    final dest = (Offset.zero & size).inflate(over);
    final sx = source.width / size.width, sy = source.height / size.height;
    final src = Rect.fromLTRB(source.left - over * sx, source.top - over * sy, source.right + over * sx, source.bottom + over * sy);
    // Cards not yet in place sit a touch darker, and the picture brightens
    // as it locks. The dim is part of the image draw (not a layer on top)
    // so the overlap zone of two fused cells is never darkened twice.
    final imagePaint = Paint()..filterQuality = FilterQuality.medium;
    if (dim > 0) imagePaint.colorFilter = ColorFilter.mode(Colors.black.withValues(alpha: dim), BlendMode.srcATop);
    canvas.drawImageRect(image, src, dest, imagePaint);
    if (tint != null) canvas.drawRect(dest, Paint()..color = tint!);
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
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CardPainter o) =>
      o.image != image ||
      o.source != source ||
      o.radius != radius ||
      !_sameList(o.insets, insets) ||
      !_sameList(o.fusedEdges, fusedEdges) ||
      !_sameList(o.fans, fans) ||
      o.gutterHalf != gutterHalf ||
      !_sameList(o.polygon, polygon) ||
      o.tint != tint ||
      o.outline != outline ||
      o.outlineWidth != outlineWidth ||
      o.outlineOuterOnly != outlineOuterOnly ||
      o.dim != dim ||
      o.borderWidth != borderWidth ||
      o.shadow != shadow;

  static bool _sameList(List<Object?> a, List<Object?> b) {
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
