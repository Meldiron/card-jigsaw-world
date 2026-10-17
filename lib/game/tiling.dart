import 'dart:math' as math;
import 'dart:ui';

import 'modes.dart';

/// A tiling maps slot indices (0..cells-1) onto a lattice and onto screen
/// geometry. The board model only needs the lattice part (neighbours,
/// deltas, placement classes); the renderer uses the geometry part.
///
/// Every tiling covers the whole board rectangle. Cards and squares do so
/// with whole rectangles. Triangles and hexagons are laid over the board and
/// clipped by it, so the pieces along the edges are half triangles and
/// partial hexagons and the picture is shown whole (see [ClippedTiling]).
///
/// Lattice deltas are `(dx, dy)` records whose meaning is tiling-specific:
/// grid deltas for cards/squares, (column, row) steps for triangles, doubled
/// coordinates for hexagons.
abstract class Tiling {
  const Tiling(this.cols, this.rows);
  final int cols;
  final int rows;

  int get cells => cols * rows;
  GameMode get mode;

  int col(int slot) => slot % cols;
  int row(int slot) => slot ~/ cols;
  bool inBounds(int c, int r) => c >= 0 && c < cols && r >= 0 && r < rows;

  /// Slots a card at [slot] may ever occupy are those sharing its class:
  /// pieces of exactly the same shape. Grids have one class; triangles have
  /// up / down plus one class per kind of half piece; hexagons have whole
  /// cells plus one class per kind of edge piece.
  int classOf(int slot) => 0;
  int get classCount => 1;

  /// Pre-set pieces (owner, 2026-10-17; docs/boards.md): a piece no other
  /// piece shares the shape of could only ever sit in its own place (pieces
  /// never turn and move only within their shape), so it is dealt there, as
  /// part of the picture's frame. It is drawn in place from the start, never
  /// moves, is never picked, a twin or counted (locked/total, rewards per
  /// piece). Grids have none; the 3x3 triangle board and the 4x4 and 6x6
  /// honeycombs have a few half pieces on their edges.
  bool isPreset(int slot) => false;

  /// How many pieces are pre-set ([isPreset]).
  int get presetCount => 0;

  /// Pieces the player plays: every piece but the pre-set ones.
  int get playableCells => cells - presetCount;

  /// Joined pairs every start shuffle of this board keeps, because some
  /// edge pieces cannot all leave their neighbours (see [TriangleTiling] and
  /// [HexTiling]).
  int get unavoidableJoins => 0;

  // ---- lattice -----------------------------------------------------------

  /// Lattice delta that takes [from] to [to], or null when no legal move
  /// exists between them (the two slots hold pieces of different shapes).
  (int, int)? delta(int from, int to);

  /// Applies a lattice delta; null when the result leaves the board or lands
  /// on a slot of another shape.
  int? apply(int slot, int dx, int dy);

  /// Adjacent slots (sharing an edge).
  Iterable<int> neighbours(int slot);

  /// Direction from [a] to [b] when they are edge-neighbours, else null.
  ///
  /// This describes which edge the two cells share, so two cards join when
  /// `direction(slotA, slotB) == direction(cardA, cardB)`. It is not a move
  /// delta: a triangle's neighbours all have the opposite orientation, so
  /// [delta] (which rejects shape changes) must not be used here.
  (int, int)? direction(int a, int b) {
    for (final n in neighbours(a)) {
      if (n == b) return (col(b) - col(a), row(b) - row(a));
    }
    return null;
  }

  // ---- geometry ----------------------------------------------------------

  /// Bounding box of a cell in a board of [size].
  Rect cellBounds(int slot, Size size);

  /// Convex polygon of a cell in board coordinates, in edge order.
  List<Offset> polygon(int slot, Size size);

  /// Neighbour across each polygon edge (edge k runs from vertex k to k+1);
  /// null on the board's edge.
  List<int?> edgeNeighbours(int slot);

  /// Number of cells that meet at an interior vertex: 4 on a grid, 6 on a
  /// triangle strip, 3 in a honeycomb. A vertex with fewer is on the board's
  /// edge.
  int get vertexValence;

  /// Other cells touching vertex [k] of [slot] (edge-neighbours included).
  /// Derived from the geometry, so one implementation serves every tiling.
  List<int> cornerNeighbours(int slot, int k) {
    final key = '$mode:${cols}x$rows';
    final table = _cornerCache.putIfAbsent(key, () => List<List<List<int>>?>.filled(cells, null));
    return (table[slot] ??= _computeCorners(slot))[k];
  }

  static final _cornerCache = <String, List<List<List<int>>?>>{};

  List<List<int>> _computeCorners(int slot) {
    final size = Size(cols * 64.0, rows * 64.0);
    final own = polygon(slot, size);
    // Cells around a vertex are at most three edge-steps apart (triangles).
    final seen = <int>{slot};
    var frontier = <int>[slot];
    for (var depth = 0; depth < 3; depth++) {
      final next = <int>[];
      for (final s in frontier) {
        for (final n in neighbours(s)) {
          if (seen.add(n)) next.add(n);
        }
      }
      frontier = next;
    }
    final polys = {for (final s in seen) if (s != slot) s: polygon(s, size)};
    return [
      for (final v in own)
        [
          for (final e in polys.entries)
            if (e.value.any((p) => (p - v).distanceSquared < 1e-6)) e.key,
        ],
    ];
  }

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

  // ---- sizing ------------------------------------------------------------

  /// Board aspects (width ÷ height) at which every cell has exactly its
  /// intended shape: square squares, 5:7 cards, equilateral triangles,
  /// regular hexagons. Hexagons have a range because the cut through the
  /// top and bottom rows may slide a little.
  (double, double) get naturalAspectRange;

  /// The middle of [naturalAspectRange].
  double get naturalAspect {
    final (lo, hi) = naturalAspectRange;
    return math.sqrt(lo * hi);
  }

  /// How far (as a fraction) the cells may stretch away from their intended
  /// shape so the board can take the picture's proportions instead of
  /// cropping it. Squares stay square within 1 %.
  double get stretchTolerance;

  /// Board aspects this tiling accepts: the natural range widened by the
  /// stretch tolerance.
  (double, double) get aspectRange {
    final (lo, hi) = naturalAspectRange;
    return (lo * (1 - stretchTolerance), hi * (1 + stretchTolerance));
  }

  /// Aspect the board takes for a picture of [imageAspect]: the picture's
  /// own aspect when the cells can take it, otherwise the nearest one they
  /// can. The picture is centre-cropped to it (see [crop]).
  double boardAspect(double imageAspect) {
    final (lo, hi) = aspectRange;
    if (!imageAspect.isFinite || imageAspect <= 0) return naturalAspect;
    return imageAspect.clamp(lo, hi);
  }

  /// Fraction of the picture's area the centre crop removes for a picture of
  /// [imageAspect], and how far the cells stretch from their intended shape.
  ({double crop, double stretch}) fitFor(double imageAspect) {
    final b = boardAspect(imageAspect);
    final (lo, hi) = naturalAspectRange;
    final crop = 1.0 - math.min(imageAspect / b, b / imageAspect);
    final stretch = b < lo ? lo / b - 1 : (b > hi ? b / hi - 1 : 0.0);
    return (crop: crop, stretch: stretch);
  }

  /// Largest board of [boardAspect] that fits inside [available].
  Size fit(Size available, double imageAspect) {
    final aspect = boardAspect(imageAspect);
    final maxW = math.max(0.0, available.width), maxH = math.max(0.0, available.height);
    var w = maxW, h = w / aspect;
    if (h > maxH) {
      h = maxH;
      w = h * aspect;
    }
    return Size(w, h);
  }

  /// Centre crop of [image] with the aspect of [board]: the part of the
  /// picture the cells are cut from (the same crop as `BoxFit.cover`).
  Rect crop(Size image, Size board) {
    if (board.width <= 0 || board.height <= 0 || image.width <= 0 || image.height <= 0) return Offset.zero & image;
    final aspect = board.width / board.height;
    var w = image.width, h = image.height;
    if (image.width / image.height > aspect) {
      w = image.height * aspect;
    } else {
      h = image.width / aspect;
    }
    return Rect.fromLTWH((image.width - w) / 2, (image.height - h) / 2, w, h);
  }

  /// Picture region that belongs to [card]: its home cell laid out over the
  /// picture [crop] (see [crop]).
  Rect sourceRect(int card, Rect crop) => cellBounds(card, crop.size).shift(crop.topLeft);

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

  /// Number of slots of a `mode` board with this column/row count, without
  /// building the tiling.
  static int cellCount(GameMode mode, int cols, int rows) => switch (mode) {
        GameMode.hexagons => HexTiling.countFor(math.max(1, cols), math.max(1, rows)),
        GameMode.triangles => TriangleTiling.countFor(math.max(1, cols), math.max(1, rows)),
        _ => cols * rows,
      };

  static final _cache = <String, Tiling>{};

  /// The tiling for a board. Instances are shared: clipped tilings work out
  /// their pieces once.
  static Tiling of(GameMode mode, int cols, int rows) {
    final c = math.max(1, cols), r = math.max(1, rows);
    return _cache.putIfAbsent('${mode.code}:${c}x$r', () {
      return switch (mode) {
        GameMode.cards || GameMode.squares => GridTiling(c, r, mode),
        GameMode.triangles => TriangleTiling(c, r),
        GameMode.hexagons => HexTiling(c, r),
      };
    });
  }
}

/// Rectangular cells: squares are square, cards have the 5:7 proportions of
/// a playing card. The board takes the aspect that keeps that shape, and the
/// picture is centre-cropped to it.
class GridTiling extends Tiling {
  const GridTiling(super.cols, super.rows, this.mode);
  @override
  final GameMode mode;

  /// Width ÷ height of one card (a poker card is 2.5 × 3.5 in).
  static const cardAspect = 5 / 7;

  /// Width ÷ height of one cell.
  double get cellAspect => mode == GameMode.cards ? cardAspect : 1.0;

  @override
  (double, double) get naturalAspectRange {
    final a = cols / rows * cellAspect;
    return (a, a);
  }

  /// Squares stay square within 1 %. Cards may run between roughly 0.66 and
  /// 0.77 (bridge to poker proportions), never near square.
  @override
  double get stretchTolerance => mode == GameMode.cards ? 0.08 : 0.009;

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
  int get vertexValence => 4;

  @override
  int? slotAt(Offset point, Size size) {
    final c = (point.dx / (size.width / cols)).floor();
    final r = (point.dy / (size.height / rows)).floor();
    return inBounds(c, r) ? r * cols + c : null;
  }
}

/// A lattice of convex cells laid over the board rectangle and clipped by
/// it. Pieces whose cell crosses the board's edge become the part inside it
/// (half triangles, partial hexagons), so the whole picture is used.
///
/// Every piece keeps its lattice coordinates, so moves are lattice deltas
/// and joins compare the lattice direction of the shared edge. A piece only
/// ever sits in a slot of exactly its own shape ([classOf]). A shape that
/// occurs once is a pre-set piece ([isPreset]): it starts in its place and
/// stays there; every other piece shuffles away from home.
abstract class ClippedTiling extends Tiling {
  ClippedTiling(super.cols, super.rows);

  /// Lattice coordinates of every piece, in slot order.
  List<(int, int)> buildCoords();

  /// The unclipped cell at lattice coordinates [q] on a board of [size].
  List<Offset> fullPolygon((int, int) q, Size size);

  /// Lattice delta across each edge of [fullPolygon] (edge k runs from
  /// vertex k to k+1), for a cell at [q].
  List<(int, int)> edgeDirections((int, int) q);

  /// A board size whose aspect suits the tiling, used to work out the
  /// pieces' shapes and neighbours once.
  Size get canonicalSize {
    final a = naturalAspect;
    return Size(1000 * a, 1000);
  }

  /// Lattice cells merged into another piece: cell -> the piece's own
  /// coordinates (see [TriangleTiling]).
  Map<(int, int), (int, int)> get aliases => const {};

  late final List<(int, int)> coords = buildCoords();
  late final Map<(int, int), int> _index = () {
    final m = {for (var i = 0; i < coords.length; i++) coords[i]: i};
    for (final a in aliases.entries) {
      final t = m[a.value];
      if (t != null) m[a.key] = t;
    }
    return m;
  }();

  /// Slot at lattice coordinates [q], or null.
  int? slotOf((int, int) q) => _index[q];

  @override
  int get cells => coords.length;

  late final _topology = _computeTopology();

  @override
  int classOf(int slot) => _topology.classes[slot];

  @override
  int get classCount => _topology.classCount;

  /// Pieces whose shape no other piece has (a board of one piece has none).
  late final List<bool> _preset = () {
    final size = List<int>.filled(classCount, 0);
    for (var s = 0; s < cells; s++) {
      size[classOf(s)]++;
    }
    return List<bool>.unmodifiable([for (var s = 0; s < cells; s++) cells > 1 && size[classOf(s)] == 1]);
  }();

  @override
  bool isPreset(int slot) => _preset[slot];

  @override
  late final int presetCount = _preset.where((p) => p).length;

  /// Slots of every placement class.
  List<List<int>> get classMembers {
    final out = List.generate(classCount, (_) => <int>[]);
    for (var s = 0; s < cells; s++) {
      out[classOf(s)].add(s);
    }
    return out;
  }

  @override
  List<int?> edgeNeighbours(int slot) => _topology.edges[slot];

  @override
  Iterable<int> neighbours(int slot) => _topology.neighbours[slot];

  @override
  (int, int)? direction(int a, int b) {
    if (!_topology.neighbours[a].contains(b)) return null;
    final p = coords[a], q = coords[b];
    return (q.$1 - p.$1, q.$2 - p.$2);
  }

  @override
  (int, int)? delta(int from, int to) {
    if (classOf(from) != classOf(to)) return null;
    final p = coords[from], q = coords[to];
    return (q.$1 - p.$1, q.$2 - p.$2);
  }

  @override
  int? apply(int slot, int dx, int dy) {
    final p = coords[slot];
    final q = (p.$1 + dx, p.$2 + dy);
    final t = _index[q];
    if (t == null || coords[t] != q || classOf(t) != classOf(slot)) return null;
    return t;
  }

  /// Clipped polygons for the last few board sizes (the board, the
  /// geometry probes and the preview each ask for their own).
  final _polyCache = <Size, List<List<Offset>?>>{};

  @override
  List<Offset> polygon(int slot, Size size) {
    var table = _polyCache[size];
    if (table == null) {
      if (_polyCache.length >= 6) _polyCache.remove(_polyCache.keys.first);
      table = _polyCache[size] = List<List<Offset>?>.filled(cells, null);
    }
    return table[slot] ??= clipToBoard(fullPolygon(coords[slot], size), size);
  }

  @override
  Rect cellBounds(int slot, Size size) {
    final p = polygon(slot, size);
    var l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
    for (final v in p) {
      l = math.min(l, v.dx);
      t = math.min(t, v.dy);
      r = math.max(r, v.dx);
      b = math.max(b, v.dy);
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  /// Area centroid, so an edge piece's centre sits inside its visible part.
  @override
  Offset cellCenter(int slot, Size size) {
    final p = polygon(slot, size);
    var a = 0.0, cx = 0.0, cy = 0.0;
    for (var i = 0; i < p.length; i++) {
      final u = p[i], v = p[(i + 1) % p.length];
      final cross = u.dx * v.dy - v.dx * u.dy;
      a += cross;
      cx += (u.dx + v.dx) * cross;
      cy += (u.dy + v.dy) * cross;
    }
    if (a.abs() < 1e-9) return super.cellCenter(slot, size);
    return Offset(cx / (3 * a), cy / (3 * a));
  }

  /// Sutherland–Hodgman clip of a convex polygon to the board rectangle,
  /// without repeated or collinear vertices.
  static List<Offset> clipToBoard(List<Offset> poly, Size size) {
    final eps = 1e-9 * math.max(1, math.max(size.width, size.height));
    var out = poly;
    for (final edge in const [0, 1, 2, 3]) {
      bool inside(Offset p) => switch (edge) {
            0 => p.dx >= -eps,
            1 => p.dy >= -eps,
            2 => p.dx <= size.width + eps,
            _ => p.dy <= size.height + eps,
          };
      Offset cut(Offset a, Offset b) {
        final t = switch (edge) {
          0 => (0 - a.dx) / (b.dx - a.dx),
          1 => (0 - a.dy) / (b.dy - a.dy),
          2 => (size.width - a.dx) / (b.dx - a.dx),
          _ => (size.height - a.dy) / (b.dy - a.dy),
        };
        final p = a + (b - a) * t;
        // Snap onto the clip line exactly.
        return switch (edge) {
          0 => Offset(0, p.dy),
          1 => Offset(p.dx, 0),
          2 => Offset(size.width, p.dy),
          _ => Offset(p.dx, size.height),
        };
      }

      final input = out;
      out = <Offset>[];
      if (input.isEmpty) break;
      for (var i = 0; i < input.length; i++) {
        final s = input[(i - 1 + input.length) % input.length], e = input[i];
        if (inside(e)) {
          if (!inside(s)) out.add(cut(s, e));
          out.add(e);
        } else if (inside(s)) {
          out.add(cut(s, e));
        }
      }
    }
    // Drop repeated and collinear vertices.
    final tol = 1e-6 * math.max(1, math.max(size.width, size.height));
    var pts = <Offset>[];
    for (final p in out) {
      if (pts.isEmpty || (pts.last - p).distance > tol) pts.add(p);
    }
    if (pts.length > 1 && (pts.first - pts.last).distance <= tol) pts.removeLast();
    var changed = true;
    while (changed && pts.length > 3) {
      changed = false;
      for (var i = 0; i < pts.length; i++) {
        final a = pts[(i - 1 + pts.length) % pts.length], b = pts[i], c = pts[(i + 1) % pts.length];
        final cross = (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
        if (cross.abs() <= tol * ((c - a).distance + 1)) {
          pts = [...pts]..removeAt(i);
          changed = true;
          break;
        }
      }
    }
    return pts;
  }

  _Topology _computeTopology() {
    final size = canonicalSize;
    final scale = math.max(size.width, size.height);
    final tol = 1e-6 * scale;
    final classes = List<int>.filled(cells, 0);
    final reps = <List<Offset>>[];
    final edges = <List<int?>>[];
    final nbrs = <List<int>>[];
    for (var s = 0; s < cells; s++) {
      final full = fullPolygon(coords[s], size);
      final dirs = edgeDirections(coords[s]);
      final poly = polygon(s, size);
      // Shape class: the polygon relative to its first vertex, compared
      // with every class found so far.
      final shape = _normalise(poly);
      var cls = -1;
      for (var k = 0; k < reps.length; k++) {
        final r = reps[k];
        if (r.length != shape.length) continue;
        var same = true;
        for (var i = 0; i < r.length && same; i++) {
          if ((r[i] - shape[i]).distance > tol * 10) same = false;
        }
        if (same) {
          cls = k;
          break;
        }
      }
      if (cls < 0) {
        cls = reps.length;
        reps.add(shape);
      }
      classes[s] = cls;
      // Each clipped edge lies on one edge of the full cell (a lattice edge)
      // or on the board's edge.
      final e = <int?>[];
      for (var i = 0; i < poly.length; i++) {
        final a = poly[i], b = poly[(i + 1) % poly.length];
        final mid = (a + b) / 2;
        int? n;
        for (var j = 0; j < full.length; j++) {
          if (_onSegment(mid, full[j], full[(j + 1) % full.length], tol * 10)) {
            final d = dirs[j];
            n = _index[(coords[s].$1 + d.$1, coords[s].$2 + d.$2)];
            break;
          }
        }
        e.add(n);
      }
      edges.add(e);
      nbrs.add(<int>{for (final n in e) ?n}.toList());
    }
    return _Topology(classes, reps.length, edges, nbrs);
  }

  /// Vertices relative to the top-most (then left-most) one, starting there.
  static List<Offset> _normalise(List<Offset> poly) {
    var start = 0;
    for (var i = 1; i < poly.length; i++) {
      final p = poly[i], q = poly[start];
      if (p.dy < q.dy - 1e-6 || ((p.dy - q.dy).abs() <= 1e-6 && p.dx < q.dx)) start = i;
    }
    final o = poly[start];
    return [for (var i = 0; i < poly.length; i++) poly[(start + i) % poly.length] - o];
  }

  static bool _onSegment(Offset p, Offset a, Offset b, double tol) {
    final d = b - a;
    final len2 = d.dx * d.dx + d.dy * d.dy;
    if (len2 == 0) return (p - a).distance <= tol;
    final t = ((p - a).dx * d.dx + (p - a).dy * d.dy) / len2;
    if (t < -1e-6 || t > 1 + 1e-6) return false;
    return (a + d * t - p).distance <= tol;
  }
}

class _Topology {
  _Topology(this.classes, this.classCount, this.edges, this.neighbours);
  final List<int> classes;
  final int classCount;
  final List<List<int?>> edges;
  final List<List<int>> neighbours;
}

/// Rows of alternating up/down triangles across the whole board. A row holds
/// `cols` pieces: a half triangle at each end (the board's edge runs through
/// the apex of the end triangles) and `cols - 2` whole triangles between.
/// Piece (k, r) points up when (k + r) is odd, so the top-left piece is a
/// down half. Rows fill the height exactly, so only the left and right
/// edges cut.
///
/// The half pieces of one edge alternate between two shapes down the
/// column, and two neighbouring halves can share an edge. A start shuffle
/// without a joined pair needs four rows (with the top-left half pointing
/// down, the left column pairs rows 1-2) or six and more; with four rows and
/// an odd number of steps the right column would pair rows 0-1 and 2-3, so
/// those halves are fused into two left-pointing triangles instead. Five
/// rows always keep one joined pair of halves on each side edge (of the two
/// orders that move all three halves of a shape, each joins one pair), which
/// only the 5x5 square board accepts ([unavoidableJoins]). Three rows hold a
/// half of a shape no other piece has on each side edge (the middle row's):
/// on the 3x3 square board those two are pre-set ([isPreset]).
class TriangleTiling extends ClippedTiling {
  TriangleTiling(super.cols, super.rows);
  @override
  GameMode get mode => GameMode.triangles;

  /// Half-steps across the board: whole triangles span two of them.
  int get steps => math.max(1, cols - 1);

  /// Whether the right edge's halves are fused in pairs (see the class doc).
  static bool fusesRightEdge(int cols, int rows) => rows == 4 && (cols - 1).isOdd;

  static int countFor(int cols, int rows) => cols * rows - (fusesRightEdge(cols, rows) ? rows ~/ 2 : 0);

  bool get _fused => fusesRightEdge(cols, rows);

  /// One joined pair of halves on each side edge of a five-row board.
  @override
  int get unavoidableJoins => rows == 5 ? 2 : 0;

  bool isUp(int slot) => (coords[slot].$1 + coords[slot].$2).isOdd;

  @override
  int col(int slot) => coords[slot].$1;

  @override
  int row(int slot) => coords[slot].$2;

  @override
  List<(int, int)> buildCoords() => [
        for (var r = 0; r < rows; r++)
          for (var k = 0; k < cols; k++)
            if (!(_fused && k == cols - 1 && r.isOdd)) (k, r),
      ];

  @override
  Map<(int, int), (int, int)> get aliases => _fused ? {for (var r = 1; r < rows; r += 2) (cols - 1, r): (cols - 1, r - 1)} : const {};

  /// Up: base-left, base-right, apex. Down: top-left, top-right, apex.
  /// Edge 0 is the horizontal base/top, edge 1 the right slant, edge 2 the
  /// left slant. A fused right-edge pair is a triangle pointing left: top,
  /// bottom, tip.
  @override
  List<Offset> fullPolygon((int, int) q, Size size) {
    final (k, r) = q;
    final half = size.width / steps, h = size.height / rows;
    final x = k * half, top = r * h, bottom = (r + 1) * h;
    if (_fused && k == cols - 1) {
      return [Offset(x, top), Offset(x, top + 2 * h), Offset(x - half, bottom)];
    }
    if ((k + r).isOdd) {
      return [Offset(x - half, bottom), Offset(x + half, bottom), Offset(x, top)];
    }
    return [Offset(x - half, top), Offset(x + half, top), Offset(x, bottom)];
  }

  @override
  List<(int, int)> edgeDirections((int, int) q) {
    if (_fused && q.$1 == cols - 1) return const [(1, 0), (-1, 1), (-1, 0)];
    final up = (q.$1 + q.$2).isOdd;
    return [(0, up ? 1 : -1), (1, 0), (-1, 0)];
  }

  /// Equilateral when a triangle's height is √3/2 of its base: the board is
  /// `steps` half-bases wide and `rows` heights tall.
  @override
  (double, double) get naturalAspectRange {
    final a = steps / (rows * math.sqrt(3));
    return (a, a);
  }

  @override
  double get stretchTolerance => 0.10;

  @override
  int get vertexValence => 6;

  @override
  double cellSize(Size size) => math.min(2 * size.width / steps * 0.8, size.height / rows);
}

/// A pointy-top honeycomb across the whole board. Even rows hold `cols`
/// hexagons whose outer sides lie on the board's left and right edges; odd
/// rows are shifted by half a cell, so the board's edges cut their end
/// cells in half (`cols + 1` pieces). The top and bottom edges cut through
/// the first and last rows (both even), a little above or below their
/// centres, which absorbs the picture's proportions.
///
/// Lattice coordinates are doubled: (X, r) with X = 2·(centre x / width),
/// so a neighbour is always (±2, 0) or (±1, ±1) away whatever the row.
///
/// With an odd row count of five or more no edge piece is a singleton:
/// left halves, right halves, top pieces and bottom pieces each occur at
/// least twice, and no corner is cut twice. The square 4x4 and 6x6 boards
/// have singletons, which are pre-set ([isPreset]): with an even number of
/// rows the bottom row is a shifted one, so its two corners are halves cut at
/// the bottom too, and on 4x4 the second row's halves have no partner either
/// (three rows would leave the middle row's two halves alone).
class HexTiling extends ClippedTiling {
  HexTiling(super.cols, super.rows);
  @override
  GameMode get mode => GameMode.hexagons;

  /// A row of exactly three pieces of one shape always keeps two of them side
  /// by side in order (both orders that move all three do). The 4x4 board
  /// has one such row (the bottom one, between its pre-set corners): one
  /// joined pair. On the 3x3 board (not offered) both rows of three move one
  /// step along and the middle row's two whole hexagons trade places, so
  /// every deal keeps six joined pairs and is solved in one move (all four
  /// deals there are; `test/preset_pieces_test.dart` searches every one).
  /// Every board on offer but the 4x4 keeps none.
  @override
  int get unavoidableJoins => switch ((cols, rows)) {
        (3, 3) => 6,
        (4, 4) => 1,
        _ => 0,
      };

  /// Where the top edge cuts the first row, in hexagon heights from its
  /// centre (positive: the centre lies inside the board). From half a
  /// hexagon to all but the top cap, so an edge piece is never a thin
  /// strip; the bottom edge mirrors it.
  static const minCut = 0.0;
  static const maxCut = 0.24;

  static int countFor(int cols, int rows) => (rows + 1) ~/ 2 * cols + rows ~/ 2 * (cols + 1);

  @override
  int get cells => countFor(cols, rows);

  @override
  List<(int, int)> buildCoords() => [
        for (var r = 0; r < rows; r++)
          if (r.isEven)
            for (var c = 0; c < cols; c++) (2 * c + 1, r)
          else
            for (var c = 0; c <= cols; c++) (2 * c, r),
      ];

  int _rowStart(int r) => (r + 1) ~/ 2 * cols + r ~/ 2 * (cols + 1);

  @override
  int col(int slot) => slot - _rowStart(row(slot));

  @override
  int row(int slot) {
    var r = 0;
    while (r + 1 < rows && _rowStart(r + 1) <= slot) {
      r++;
    }
    return r;
  }

  @override
  bool inBounds(int c, int r) => r >= 0 && r < rows && c >= 0 && c < (r.isEven ? cols : cols + 1);

  /// Cell width, cell height (vertex to vertex) and the centre of the first
  /// row for a board of [size]. Hexagons are regular while the cut can
  /// absorb the board's height; beyond that they stretch vertically.
  ({double w, double hh, double top}) metrics(Size size) {
    final w = size.width / cols;
    var hh = w * 2 / math.sqrt(3);
    final span = (rows - 1) * 0.75;
    var cut = (size.height / hh - span) / 2;
    if (cut < minCut || cut > maxCut) {
      cut = cut.clamp(minCut, maxCut);
      hh = size.height / (span + 2 * cut);
    }
    return (w: w, hh: hh, top: cut * hh);
  }

  /// Vertices start at the lower-right corner (30°) and go clockwise on
  /// screen: SE, SW, W, NW, NE, E edges.
  @override
  List<Offset> fullPolygon((int, int) q, Size size) {
    final m = metrics(size);
    final cx = q.$1 * m.w / 2, cy = m.top + q.$2 * 0.75 * m.hh;
    final hw = m.w / 2, qh = m.hh / 4, hh2 = m.hh / 2;
    return [
      Offset(cx + hw, cy + qh),
      Offset(cx, cy + hh2),
      Offset(cx - hw, cy + qh),
      Offset(cx - hw, cy - qh),
      Offset(cx, cy - hh2),
      Offset(cx + hw, cy - qh),
    ];
  }

  @override
  List<(int, int)> edgeDirections((int, int) q) => const [(1, 1), (-1, 1), (-2, 0), (-1, -1), (1, -1), (2, 0)];

  /// Regular when a hexagon is √3/2 as wide as it is tall; the cut through
  /// the first and last rows gives a range of heights.
  @override
  (double, double) get naturalAspectRange {
    final span = (rows - 1) * 0.75;
    final width = cols * math.sqrt(3) / 2;
    final lo = width / (span + 2 * maxCut);
    final tall = span + 2 * minCut;
    return (lo, tall > 0.05 ? width / tall : lo * 4);
  }

  @override
  double get stretchTolerance => 0.10;

  @override
  int get vertexValence => 3;

  @override
  double cellSize(Size size) {
    final m = metrics(size);
    return math.min(m.w, m.hh * 0.85);
  }
}
