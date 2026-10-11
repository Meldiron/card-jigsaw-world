import 'dart:math' as math;
import 'dart:ui';

import 'modes.dart';

/// A tiling maps slot indices (0..cells-1) onto a lattice and onto screen
/// geometry. The board model only needs the lattice part (neighbours,
/// deltas); the renderer uses the geometry part.
///
/// Lattice deltas are `(dx, dy)` records whose meaning is tiling-specific:
/// grid deltas for cards/squares/triangles, axial deltas for hexagons.
abstract class Tiling {
  const Tiling(this.cols, this.rows);
  final int cols;
  final int rows;

  int get cells => cols * rows;
  GameMode get mode;

  int col(int slot) => slot % cols;
  int row(int slot) => slot ~/ cols;
  bool inBounds(int c, int r) => c >= 0 && c < cols && r >= 0 && r < rows;

  /// Slots a card at [slot] may ever occupy are those sharing its class.
  /// Grids and hexes have one class; triangles have two (up / down).
  int classOf(int slot) => 0;
  int get classCount => 1;

  // ---- lattice -----------------------------------------------------------

  /// Lattice delta that takes [from] to [to], or null when no legal move
  /// exists between them (e.g. a triangle orientation mismatch).
  (int, int)? delta(int from, int to);

  /// Applies a lattice delta; null when the result leaves the board or
  /// violates the tiling's placement rule.
  int? apply(int slot, int dx, int dy);

  /// Adjacent slots (sharing an edge).
  Iterable<int> neighbours(int slot);

  /// Direction from [a] to [b] when they are edge-neighbours, else null.
  (int, int)? direction(int a, int b) {
    for (final n in neighbours(a)) {
      if (n == b) return delta(a, b);
    }
    return null;
  }

  // ---- geometry ----------------------------------------------------------

  /// Bounding box of a cell in a board of [size].
  Rect cellBounds(int slot, Size size);

  /// Convex polygon of a cell in board coordinates, in edge order.
  List<Offset> polygon(int slot, Size size);

  /// Neighbour across each polygon edge (edge k runs from vertex k to k+1).
  List<int?> edgeNeighbours(int slot);

  Offset cellCenter(int slot, Size size) {
    final p = polygon(slot, size);
    var x = 0.0, y = 0.0;
    for (final v in p) {
      x += v.dx;
      y += v.dy;
    }
    return Offset(x / p.length, y / p.length);
  }

  /// Slot under [point], or null when outside every cell.
  int? slotAt(Offset point, Size size) {
    int? best;
    var bestDist = double.infinity;
    for (var s = 0; s < cells; s++) {
      if (!cellBounds(s, size).inflate(0.5).contains(point)) continue;
      if (_inside(point, polygon(s, size))) return s;
      final d = (cellCenter(s, size) - point).distanceSquared;
      if (d < bestDist) {
        bestDist = d;
        best = s;
      }
    }
    return best;
  }

  /// Picture region that belongs to [card] (its home cell in image space).
  Rect sourceRect(int card, Size image) => cellBounds(card, image);

  /// Representative cell size, used to scale gutters and corner radii.
  double cellSize(Size size) {
    final b = cellBounds(0, size);
    return math.min(b.width, b.height);
  }

  static bool _inside(Offset p, List<Offset> poly) {
    var sign = 0;
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
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

  static Tiling of(GameMode mode, int cols, int rows) => switch (mode) {
        GameMode.cards || GameMode.squares => GridTiling(cols, rows, mode),
        GameMode.triangles => TriangleTiling(cols, rows),
        GameMode.hexagons => HexTiling(cols, rows),
      };
}

/// Rectangular cells (cards and squares differ only in the ladder).
class GridTiling extends Tiling {
  const GridTiling(super.cols, super.rows, this.mode);
  @override
  final GameMode mode;

  @override
  (int, int)? delta(int from, int to) => (col(to) - col(from), row(to) - row(from));

  @override
  int? apply(int slot, int dx, int dy) {
    final c = col(slot) + dx, r = row(slot) + dy;
    return inBounds(c, r) ? r * cols + c : null;
  }

  @override
  Iterable<int> neighbours(int slot) sync* {
    final c = col(slot), r = row(slot);
    if (r > 0) yield slot - cols;
    if (c < cols - 1) yield slot + 1;
    if (r < rows - 1) yield slot + cols;
    if (c > 0) yield slot - 1;
  }

  @override
  Rect cellBounds(int slot, Size size) {
    final w = size.width / cols, h = size.height / rows;
    return Rect.fromLTWH(col(slot) * w, row(slot) * h, w, h);
  }

  @override
  List<Offset> polygon(int slot, Size size) {
    final b = cellBounds(slot, size);
    return [b.topLeft, b.topRight, b.bottomRight, b.bottomLeft];
  }

  /// Edge order: top, right, bottom, left.
  @override
  List<int?> edgeNeighbours(int slot) => [apply(slot, 0, -1), apply(slot, 1, 0), apply(slot, 0, 1), apply(slot, -1, 0)];

  @override
  int? slotAt(Offset point, Size size) {
    final c = (point.dx / (size.width / cols)).floor();
    final r = (point.dy / (size.height / rows)).floor();
    return inBounds(c, r) ? r * cols + c : null;
  }
}

/// Strips of alternating up/down triangles. Cell (i, r) points up when
/// (i + r) is even. Triangles only ever sit in slots of their own
/// orientation, so every legal delta has an even (dx + dy).
class TriangleTiling extends Tiling {
  const TriangleTiling(super.cols, super.rows);
  @override
  GameMode get mode => GameMode.triangles;

  bool isUp(int slot) => (col(slot) + row(slot)).isEven;

  @override
  int classOf(int slot) => isUp(slot) ? 0 : 1;
  @override
  int get classCount => 2;

  @override
  (int, int)? delta(int from, int to) {
    final dx = col(to) - col(from), dy = row(to) - row(from);
    return (dx + dy).isEven ? (dx, dy) : null;
  }

  @override
  int? apply(int slot, int dx, int dy) {
    if ((dx + dy).isOdd) return null;
    final c = col(slot) + dx, r = row(slot) + dy;
    return inBounds(c, r) ? r * cols + c : null;
  }

  @override
  Iterable<int> neighbours(int slot) sync* {
    final c = col(slot), r = row(slot);
    // Edge order matches [polygon]: base (vertical neighbour), right, left.
    if (isUp(slot)) {
      if (r < rows - 1) yield slot + cols;
    } else {
      if (r > 0) yield slot - cols;
    }
    if (c < cols - 1) yield slot + 1;
    if (c > 0) yield slot - 1;
  }

  @override
  List<int?> edgeNeighbours(int slot) {
    final c = col(slot), r = row(slot);
    final vertical = isUp(slot) ? (r < rows - 1 ? slot + cols : null) : (r > 0 ? slot - cols : null);
    return [vertical, c < cols - 1 ? slot + 1 : null, c > 0 ? slot - 1 : null];
  }

  double _tw(Size s) => 2 * s.width / (cols + 1);
  double _th(Size s) => s.height / rows;

  @override
  Rect cellBounds(int slot, Size size) {
    final tw = _tw(size), th = _th(size);
    return Rect.fromLTWH(col(slot) * tw / 2, row(slot) * th, tw, th);
  }

  /// Up: base-left, base-right, apex. Down: top-left, top-right, apex.
  /// Edge 0 is the horizontal base/top, edge 1 the right slant, edge 2 the
  /// left slant – matching [edgeNeighbours].
  @override
  List<Offset> polygon(int slot, Size size) {
    final b = cellBounds(slot, size);
    if (isUp(slot)) {
      return [b.bottomLeft, b.bottomRight, Offset(b.center.dx, b.top)];
    }
    return [b.topLeft, b.topRight, Offset(b.center.dx, b.bottom)];
  }

  @override
  double cellSize(Size size) => math.min(_tw(size) * 0.8, _th(size));
}

/// Pointy-top honeycomb in odd-r offset coordinates (odd rows shift right by
/// half a cell). Lattice deltas are axial (dq, dr).
class HexTiling extends Tiling {
  const HexTiling(super.cols, super.rows);
  @override
  GameMode get mode => GameMode.hexagons;

  static const _dirs = <(int, int)>[(1, 0), (0, 1), (-1, 1), (-1, 0), (0, -1), (1, -1)];

  (int, int) _axial(int slot) {
    final c = col(slot), r = row(slot);
    return (c - (r - (r & 1)) ~/ 2, r);
  }

  int? _fromAxial(int q, int r) {
    final c = q + (r - (r & 1)) ~/ 2;
    return inBounds(c, r) ? r * cols + c : null;
  }

  @override
  (int, int)? delta(int from, int to) {
    final a = _axial(from), b = _axial(to);
    return (b.$1 - a.$1, b.$2 - a.$2);
  }

  @override
  int? apply(int slot, int dx, int dy) {
    final a = _axial(slot);
    return _fromAxial(a.$1 + dx, a.$2 + dy);
  }

  @override
  Iterable<int> neighbours(int slot) sync* {
    for (final d in _dirs) {
      final n = apply(slot, d.$1, d.$2);
      if (n != null) yield n;
    }
  }

  /// Polygon vertices start at the lower-right corner (30°) and go clockwise
  /// on screen: SE, SW, W, NW, NE, E edges.
  @override
  List<int?> edgeNeighbours(int slot) => [
        apply(slot, 0, 1), // SE
        apply(slot, -1, 1), // SW
        apply(slot, -1, 0), // W
        apply(slot, 0, -1), // NW
        apply(slot, 1, -1), // NE
        apply(slot, 1, 0), // E
      ];

  double _hw(Size s) => s.width / (cols + 0.5);
  double _hh(Size s) => s.height / (0.75 * rows + 0.25);

  Offset _center(int slot, Size size) {
    final hw = _hw(size), hh = _hh(size);
    final r = row(slot);
    return Offset((col(slot) + 0.5 + (r.isOdd ? 0.5 : 0)) * hw, (0.5 + 0.75 * r) * hh);
  }

  @override
  Offset cellCenter(int slot, Size size) => _center(slot, size);

  @override
  Rect cellBounds(int slot, Size size) {
    final hw = _hw(size), hh = _hh(size);
    return Rect.fromCenter(center: _center(slot, size), width: hw, height: hh);
  }

  @override
  List<Offset> polygon(int slot, Size size) {
    final c = _center(slot, size);
    final rx = _hw(size) / math.sqrt(3), ry = _hh(size) / 2;
    return [
      for (var k = 0; k < 6; k++)
        Offset(c.dx + rx * math.cos((30 + 60 * k) * math.pi / 180), c.dy + ry * math.sin((30 + 60 * k) * math.pi / 180)),
    ];
  }

  @override
  double cellSize(Size size) => math.min(_hw(size), _hh(size) * 0.85);
}
