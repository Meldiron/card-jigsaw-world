import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;

import 'board.dart';

/// Twin cards (owner, 2026-10-17; docs/twins.md): cards of one shape that look exactly alike (two
/// patches of the same plain sky, say). A card dropped on its twin's place counts as placed, and a
/// card put where its twin would join a neighbour joins: the two loose cards trade identities, so
/// the board says it is locked or joined. The picture they show does not change, by construction.
///
/// Twins come in classes in which every two cards are twins ([TwinFinder]); [same] asks whether
/// two cards are interchangeable. Nothing here is random: every device that has the same classes
/// and the same board makes the same decisions.
class Twins {
  Twins._(this._ids, this.classCount);

  /// No twins: the picture is not measured yet, or no two of its cards look alike.
  static final none = Twins._(Int32List(0), 0);

  /// Twins from [classes] (lists of cards, each of two or more) on a board of [cells] cards.
  factory Twins.fromClasses(int cells, Iterable<List<int>> classes) {
    final ids = Int32List(cells)..fillRange(0, cells, -1);
    var n = 0;
    for (final c in classes) {
      if (c.length < 2) continue;
      for (final card in c) {
        ids[card] = n;
      }
      n++;
    }
    return n == 0 ? none : Twins._(ids, n);
  }

  final Int32List _ids;

  /// Number of twin classes.
  final int classCount;

  bool get isEmpty => classCount == 0;

  /// Cards that have a twin.
  int get cards => [for (final i in _ids) if (i >= 0) i].length;

  /// The twin classes, each sorted.
  List<List<int>> get classes {
    final out = List.generate(classCount, (_) => <int>[]);
    for (var c = 0; c < _ids.length; c++) {
      if (_ids[c] >= 0) out[_ids[c]].add(c);
    }
    return out;
  }

  /// Whether [a] and [b] are the same card or twins.
  bool same(int a, int b) => a == b || (classCount > 0 && _ids[a] >= 0 && _ids[a] == _ids[b]);

  /// Whether [card] at [slot] looks in its place: it is the slot's card or that card's twin.
  bool looksPlaced(int card, int slot) => same(card, slot);

  /// Whether cards [a] at slot [sa] and [b] at slot [sb] (neighbours) look joined: they belong
  /// side by side that way, or the twin of one does next to the other. One side's twin is enough:
  /// that is the identity swap [settle] makes.
  bool looksJoined(Tiling tiling, int sa, int a, int sb, int b) {
    final d = tiling.direction(sa, sb);
    if (d == null) return false;
    if (tiling.direction(a, b) == d) return true;
    if (classCount == 0 || (_ids[a] < 0 && _ids[b] < 0)) return false;
    return _twinBefore(tiling, a, b, d) != null || _twinAfter(tiling, a, b, d) != null;
  }

  /// A twin of [a] (not [a]) whose place lies [d] before [b]'s place: with it in [a]'s slot,
  /// the two would join.
  int? _twinBefore(Tiling tiling, int a, int b, (int, int) d) {
    if (_ids[a] < 0) return null;
    for (final x in tiling.neighbours(b)) {
      if (x != a && same(x, a) && tiling.direction(x, b) == d) return x;
    }
    return null;
  }

  /// A twin of [b] (not [b]) whose place lies [d] after [a]'s place.
  int? _twinAfter(Tiling tiling, int a, int b, (int, int) d) {
    if (_ids[b] < 0) return null;
    for (final y in tiling.neighbours(a)) {
      if (y != b && same(y, b) && tiling.direction(a, y) == d) return y;
    }
    return null;
  }

  /// Makes a move count what it shows: [after] is the board a move made from [before]. Every
  /// card the move put somewhere new (in slot order) that sits on its twin's place takes the
  /// identity of that place's own card; then every such card that sits where its twin would join
  /// a neighbour takes the twin's identity, or the neighbour takes its own twin's. Only loose cards
  /// trade (never a card in place or in a joined group), so nothing the player built changes. The
  /// twin that gives up its identity keeps its place and its look; should it lock or join there, it
  /// already looked in place or joined (it looks like the card it becomes), so that counts too. A
  /// board on which every card looks in place is finished.
  ///
  /// Returns the board and the identity swaps in order (the two cards of each keep their places
  /// on screen and trade pictures that look the same).
  ({Board board, List<(int, int)> swaps}) settle(Board before, Board after) {
    if (isEmpty) return (board: after, swaps: const []);
    final tiling = after.tiling;
    final n = after.cells;
    final cur = List<int>.from(after.slots);
    final pos = List<int>.filled(n, 0);
    for (var s = 0; s < n; s++) {
      pos[cur[s]] = s;
    }
    final moved = [for (var s = 0; s < n; s++) if (cur[s] != before.slots[s]) s];
    if (moved.isEmpty) return (board: after, swaps: const []);
    bool joined(int s, int t) => tiling.direction(cur[s], cur[t]) == tiling.direction(s, t);
    bool joinedAny(int s) => tiling.neighbours(s).any((t) => joined(s, t));
    // A loose card: not in place and not joined to any neighbour (a group of one).
    bool loose(int s) => cur[s] != s && !joinedAny(s);
    final swaps = <(int, int)>[];
    void trade(int s, int t) {
      final c = cur[s];
      cur[s] = cur[t];
      cur[t] = c;
      pos[cur[s]] = s;
      pos[cur[t]] = t;
    }

    // Trades the identities of the cards at [s] and [t] when both are loose; true when it did.
    bool tryTrade(int s, int t) {
      if (s == t || !loose(s) || !loose(t)) return false;
      trade(s, t);
      swaps.add((cur[s], cur[t]));
      return true;
    }

    // Placed: the card on its twin's place takes that place's identity.
    for (final s in moved) {
      if (cur[s] != s && same(cur[s], s)) tryTrade(s, pos[s]);
    }
    // Joined: the card or its new neighbour takes the identity of a twin that joins.
    for (final s in moved) {
      for (final t in tiling.neighbours(s)) {
        if (joined(s, t)) continue;
        final d = tiling.direction(s, t)!;
        final x = _twinBefore(tiling, cur[s], cur[t], d);
        if (x != null && tryTrade(s, pos[x])) continue;
        final y = _twinAfter(tiling, cur[s], cur[t], d);
        if (y != null) tryTrade(t, pos[y]);
      }
    }
    // Every card looks in place: the picture is complete, so the board is.
    var looksDone = true;
    for (var s = 0; s < n && looksDone; s++) {
      looksDone = same(cur[s], s);
    }
    if (looksDone) {
      for (var s = 0; s < n; s++) {
        if (cur[s] == s) continue;
        final t = pos[s];
        trade(s, t);
        swaps.add((cur[t], s));
      }
    }
    return (board: swaps.isEmpty ? after : Board(after.spec, cur), swaps: swaps);
  }
}

/// The part of a picture a board shows (its crop), as RGBA pixels row by row: what [TwinFinder]
/// measures.
class TwinPicture {
  const TwinPicture(this.width, this.height, this.rgba);
  final int width;
  final int height;
  final Uint8List rgba;
}

/// How alike two cards are: the CIEDE2000 colour differences between matching samples of the two
/// cards (boxes of about 2 pt on screen inside the card, and thin strips along its outline).
/// [edge] is the 95th percentile along the outline, the part a player compares with neighbours;
/// [speck] the biggest difference in how far a sample's darkest or lightest pixel stands out from
/// its mean (a thin wire, a bird or a speck of dust shows there while the mean hides it), and
/// [grain] how far they usually stand out on the grainier of the two cards (a photo's grain, which
/// hides faint specks from the eye as well).
class TwinPair {
  const TwinPair(this.a, this.b, {required this.mean, required this.p95, required this.max, required this.edge, required this.speck, required this.grain});
  final int a;
  final int b;
  final double mean;
  final double p95;
  final double max;
  final double edge;
  final double speck;
  final double grain;

  /// The [speck] two cards with this [grain] may differ by ([TwinFinder.speckLimit]).
  double get speckAllowed => math.max(TwinFinder.speckLimit, TwinFinder.speckGrain * grain);

  /// How close to the limits: twins at 1 or less ([TwinFinder.meanLimit], [TwinFinder.p95Limit]
  /// for the whole card and its outline, [TwinFinder.maxLimit], [speckAllowed]).
  double get score => math.max(
        math.max(mean / TwinFinder.meanLimit, max / TwinFinder.maxLimit),
        math.max(math.max(p95, edge) / TwinFinder.p95Limit, speck / speckAllowed),
      );

  bool get twins => score <= 1;
}

/// Finds the twin cards of a board in its picture (docs/twins.md).
///
/// Each card is sampled the same way: a grid of small boxes over it (about 30 across, each the
/// mean colour of its pixels, so noise and JPEG grain average out) and thin strips along its
/// outline (the outermost two pixels, then the band inside them), where a line or the start of
/// a neighbouring shape shows. Two cards of the same shape are compared sample by sample in
/// CIELAB with the CIEDE2000 difference. They are twins only when they cannot be told apart: the
/// mean difference is at most [meanLimit] (about one just-noticeable difference), 95% of the
/// samples, and 95% of the outline's, are at most [p95Limit], and none exceeds [maxLimit], so a
/// faint cloud or a change in a gradient on one card and not the other keeps them apart. Each
/// sample also notes how far its darkest and lightest pixels stand out from its mean, so a thin
/// wire, a bird or a speck that the mean would hide keeps them apart too ([speckLimit]).
/// Twin classes are built so that every two cards of a class are twins. Cards are first sorted by
/// their mean colour, so only near neighbours are compared (a 666-piece board compares a few
/// thousand pairs).
class TwinFinder {
  TwinFinder(this.picture, this.spec) : tiling = spec.tiling {
    _sample();
  }

  final TwinPicture picture;
  final BoardSpec spec;
  final Tiling tiling;

  /// Mean CIEDE2000 difference two twins may have (about one just-noticeable difference).
  static const meanLimit = 1.0;

  /// Difference 95% of the samples (and 95% of the outline's) stay within.
  static const p95Limit = 1.8;

  /// Difference no sample may exceed.
  static const maxLimit = 3.0;

  /// How much more (in lightness, 0 to 100) a sample's darkest or lightest pixel may stand out
  /// on one card than on the other: below a faint wire or speck on a clean sky. Grainy cards may
  /// differ by [speckGrain] times their grain (how far a box's extremes usually stand out), which
  /// hides as much from the eye.
  static const speckLimit = 1.6;
  static const speckGrain = 3.0;

  /// Boxes across a card's longer side: from [minBoxes] to [maxBoxes], about one per 4 pixels.
  static const minBoxes = 12;
  static const maxBoxes = 32;

  late final Size _size = Size(picture.width.toDouble(), picture.height.toDouble());

  /// Per shape class: the boxes inside the card and the strips along its outline (pixel points),
  /// both relative to the cell's bounds.
  final _boxes = <int, List<Rect>>{};
  final _strips = <int, List<List<Offset>>>{};

  /// Per card: L, a, b and how far the darkest and the lightest pixel stand out, of every sample
  /// (boxes, then strips), and the card's mean colour.
  late final List<Float64List> _lab;
  late final List<(double, double, double)> _mean;

  /// Per card: how far a box's darkest and lightest pixels usually stand out (the median).
  late final Float64List _grain;

  /// Per card: the mean colour of each part of a 4 x 4 grid over it (L, a, b), and per shape class
  /// the part each box lies in and how many boxes each part has. Two cards whose parts differ
  /// more than their samples may are told apart without comparing every sample.
  late final List<Float64List> _parts;
  final _partOf = <int, Int32List>{};
  final _partBoxes = <int, Int32List>{};
  static const _grid = 4;

  void _sample() {
    final n = tiling.cells;
    _lab = List.filled(n, Float64List(0));
    _mean = List.filled(n, (0.0, 0.0, 0.0));
    _grain = Float64List(n);
    _parts = List.filled(n, Float64List(0));
    for (var card = 0; card < n; card++) {
      final cls = tiling.classOf(card);
      if (!_boxes.containsKey(cls)) _layout(card, cls);
      final boxes = _boxes[cls]!, strips = _strips[cls]!;
      final origin = tiling.cellBounds(card, _size).topLeft;
      final lab = Float64List((boxes.length + strips.length) * _stride);
      var ml = 0.0, ma = 0.0, mb = 0.0;
      for (var i = 0; i < boxes.length; i++) {
        _store(lab, i, _boxPixels(boxes[i].shift(origin)));
        ml += lab[_stride * i];
        ma += lab[_stride * i + 1];
        mb += lab[_stride * i + 2];
      }
      for (var j = 0; j < strips.length; j++) {
        _store(lab, boxes.length + j, _pointPixels(strips[j], origin));
      }
      final k = math.max(1, boxes.length);
      _lab[card] = lab;
      _mean[card] = (ml / k, ma / k, mb / k);
      final spread = [for (var i = 0; i < boxes.length; i++) (lab[_stride * i + 3] + lab[_stride * i + 4]) / 2]..sort();
      _grain[card] = spread.isEmpty ? 0 : spread[spread.length ~/ 2];
      final partOf = _partOf[cls]!, partBoxes = _partBoxes[cls]!;
      final parts = Float64List(_grid * _grid * 3);
      for (var i = 0; i < boxes.length; i++) {
        final q = 3 * partOf[i];
        parts[q] += lab[_stride * i] / partBoxes[partOf[i]];
        parts[q + 1] += lab[_stride * i + 1] / partBoxes[partOf[i]];
        parts[q + 2] += lab[_stride * i + 2] / partBoxes[partOf[i]];
      }
      _parts[card] = parts;
    }
  }

  /// The samples of shape class [cls], laid out on [card]'s cell. Boxes: a grid over the cell's
  /// bounds (a rectangle is covered edge to edge; other shapes keep the boxes wholly inside).
  /// Strips: each edge in pieces one box long, two pixels deep at the edge and the band inside.
  void _layout(int card, int cls) {
    final bounds = tiling.cellBounds(card, _size);
    final poly = [for (final p in tiling.polygon(card, _size)) p - bounds.topLeft];
    final long = math.max(bounds.width, bounds.height);
    final rect = tiling is GridTiling;
    var across = (long / 4).round().clamp(minBoxes, maxBoxes);
    var boxes = <Rect>[];
    var step = long / across;
    // Thin pieces (half triangles, cut hexagons) get a finer grid until enough boxes fit.
    for (var tries = 0; tries < 4; tries++) {
      step = long / across;
      boxes = [];
      if (rect) {
        final cols = math.max(1, (bounds.width / step).round()), rows = math.max(1, (bounds.height / step).round());
        final w = bounds.width / cols, h = bounds.height / rows;
        for (var r = 0; r < rows; r++) {
          for (var c = 0; c < cols; c++) {
            boxes.add(Rect.fromLTWH(c * w, r * h, w, h));
          }
        }
      } else {
        final cols = math.max(1, (bounds.width / step).floor()), rows = math.max(1, (bounds.height / step).floor());
        final sx = (bounds.width - cols * step) / 2, sy = (bounds.height - rows * step) / 2;
        for (var r = 0; r < rows; r++) {
          for (var c = 0; c < cols; c++) {
            final box = Rect.fromLTWH(sx + c * step, sy + r * step, step, step);
            if (_inside(box.topLeft, poly) && _inside(box.topRight, poly) && _inside(box.bottomLeft, poly) && _inside(box.bottomRight, poly)) boxes.add(box);
          }
        }
      }
      if (boxes.length >= 24 || across >= maxBoxes * 2) break;
      across = (across * 1.5).round();
    }
    // Strips: points one pixel apart along each edge, at depths 0.5 and 1.5 px (the outermost
    // pixels) and from 2.5 px to the box size (the band the boxes may not reach).
    var cx = 0.0, cy = 0.0;
    for (final p in poly) {
      cx += p.dx / poly.length;
      cy += p.dy / poly.length;
    }
    final centre = Offset(cx, cy);
    final strips = <List<Offset>>[];
    for (var e = 0; e < poly.length; e++) {
      final p = poly[e], q = poly[(e + 1) % poly.length];
      final length = (q - p).distance;
      if (length < 1) continue;
      final along = (q - p) / length;
      var normal = Offset(-along.dy, along.dx);
      if (((centre - p).dx * normal.dx + (centre - p).dy * normal.dy) < 0) normal = -normal;
      final pieces = math.max(1, (length / step).round());
      final perPiece = math.max(1, (length / pieces).ceil());
      for (var k = 0; k < pieces; k++) {
        for (final depths in [
          const [0.5, 1.5],
          [for (var d = 2.5; d < math.max(3.0, step + 0.5); d += 1) d],
        ]) {
          final points = <Offset>[];
          for (var j = 0; j < perPiece; j++) {
            final at = p + along * (length * (k + (j + 0.5) / perPiece) / pieces);
            for (final d in depths) {
              final point = at + normal * d;
              if (_inside(point, poly)) points.add(point);
            }
          }
          if (points.isNotEmpty) strips.add(points);
        }
      }
    }
    _boxes[cls] = boxes;
    final partOf = Int32List(boxes.length), partBoxes = Int32List(_grid * _grid);
    for (var i = 0; i < boxes.length; i++) {
      final c = boxes[i].center;
      final q = (c.dy / bounds.height * _grid).floor().clamp(0, _grid - 1) * _grid + (c.dx / bounds.width * _grid).floor().clamp(0, _grid - 1);
      partOf[i] = q;
      partBoxes[q]++;
    }
    _partOf[cls] = partOf;
    _partBoxes[cls] = partBoxes;
    _strips[cls] = strips;
  }

  static bool _inside(Offset p, List<Offset> poly) {
    var sign = 0;
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      final cross = (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx);
      if (cross.abs() < 1e-6) continue;
      final s = cross > 0 ? 1 : -1;
      if (sign == 0) {
        sign = s;
      } else if (s != sign) {
        return false;
      }
    }
    return true;
  }

  /// Values kept per sample: L, a, b, and how far the darkest and the lightest pixel stand out.
  static const _stride = 5;

  void _store(Float64List into, int i, _Pixels p) {
    final k = math.max(1, p.count);
    final (l, a, b) = lab(p.r / k, p.g / k, p.b / k);
    final luma = p.luma / k;
    into[_stride * i] = l;
    into[_stride * i + 1] = a;
    into[_stride * i + 2] = b;
    into[_stride * i + 3] = luma - p.darkest;
    into[_stride * i + 4] = p.lightest - luma;
  }

  /// The pixels in [r].
  _Pixels _boxPixels(Rect r) {
    final w = picture.width, h = picture.height;
    final x0 = r.left.round().clamp(0, w - 1), y0 = r.top.round().clamp(0, h - 1);
    final x1 = math.max(x0 + 1, r.right.round().clamp(0, w)), y1 = math.max(y0 + 1, r.bottom.round().clamp(0, h));
    final p = _Pixels();
    for (var y = y0; y < y1; y++) {
      var i = (y * w + x0) * 4;
      for (var x = x0; x < x1; x++) {
        p.add(picture.rgba, i);
        i += 4;
      }
    }
    return p;
  }

  /// The pixels under [points] (shifted by [origin]).
  _Pixels _pointPixels(List<Offset> points, Offset origin) {
    final w = picture.width, h = picture.height;
    final p = _Pixels();
    for (final q in points) {
      final x = (q.dx + origin.dx).floor().clamp(0, w - 1), y = (q.dy + origin.dy).floor().clamp(0, h - 1);
      p.add(picture.rgba, (y * w + x) * 4);
    }
    return p;
  }

  /// CIELAB (D65) of an sRGB colour given as 0-255 channels.
  static (double, double, double) lab(double r, double g, double b) {
    double lin(double c) {
      final v = c / 255;
      return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    final lr = lin(r), lg = lin(g), lb = lin(b);
    final x = (0.4124564 * lr + 0.3575761 * lg + 0.1804375 * lb) / 0.95047;
    final y = 0.2126729 * lr + 0.7151522 * lg + 0.0721750 * lb;
    final z = (0.0193339 * lr + 0.1191920 * lg + 0.9503041 * lb) / 1.08883;
    double f(double t) => t > 216 / 24389 ? math.pow(t, 1 / 3).toDouble() : (24389 / 27 * t + 16) / 116;
    final fx = f(x), fy = f(y), fz = f(z);
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
  }

  /// The CIEDE2000 difference between two CIELAB colours (Sharma, Wu and Dalal, 2005), with the
  /// hue terms from one sine and cosine.
  static double deltaE00(double l1, double a1, double b1, double l2, double a2, double b2) {
    const pow25 = 6103515625.0; // 25^7
    const cos30 = 0.8660254037844387, cos6 = 0.9945218953682733, sin6 = 0.10452846326765347;
    const cos63 = 0.45399049973954675, sin63 = 0.8910065241883679;
    final c1 = math.sqrt(a1 * a1 + b1 * b1), c2 = math.sqrt(a2 * a2 + b2 * b2);
    final cm = (c1 + c2) / 2, cm2 = cm * cm, cm7 = cm2 * cm2 * cm2 * cm;
    final g = 0.5 * (1 - math.sqrt(cm7 / (cm7 + pow25)));
    final ap1 = a1 * (1 + g), ap2 = a2 * (1 + g);
    final cp1 = math.sqrt(ap1 * ap1 + b1 * b1), cp2 = math.sqrt(ap2 * ap2 + b2 * b2);
    double hue(double b, double a) {
      if (a == 0 && b == 0) return 0;
      final h = math.atan2(b, a);
      return h >= 0 ? h : h + 2 * math.pi;
    }

    final hp1 = hue(b1, ap1), hp2 = hue(b2, ap2);
    final dl = l2 - l1, dc = cp2 - cp1;
    var dh = 0.0;
    if (cp1 * cp2 != 0) {
      dh = hp2 - hp1;
      if (dh > math.pi) dh -= 2 * math.pi;
      if (dh < -math.pi) dh += 2 * math.pi;
    }
    final dH = 2 * math.sqrt(cp1 * cp2) * math.sin(dh / 2);
    final lm = (l1 + l2) / 2, cpm = (cp1 + cp2) / 2;
    var hm = hp1 + hp2;
    if (cp1 * cp2 != 0) {
      if ((hp1 - hp2).abs() > math.pi) hm += hm < 2 * math.pi ? 2 * math.pi : -2 * math.pi;
      hm /= 2;
    }
    final ch = math.cos(hm), sh = math.sin(hm);
    final c2h = 2 * ch * ch - 1, s2h = 2 * sh * ch;
    final c3h = ch * (4 * ch * ch - 3), s3h = sh * (3 - 4 * sh * sh);
    final c4h = 2 * c2h * c2h - 1, s4h = 2 * s2h * c2h;
    // 1 - 0.17 cos(h - 30°) + 0.24 cos(2h) + 0.32 cos(3h + 6°) - 0.20 cos(4h - 63°)
    final t = 1 - 0.17 * (ch * cos30 + sh * 0.5) + 0.24 * c2h + 0.32 * (c3h * cos6 - s3h * sin6) - 0.20 * (c4h * cos63 + s4h * sin63);
    final e = (hm * 180 / math.pi - 275) / 25;
    final dTheta = math.pi / 6 * math.exp(-e * e);
    final cpm2 = cpm * cpm, cpm7 = cpm2 * cpm2 * cpm2 * cpm;
    final rc = 2 * math.sqrt(cpm7 / (cpm7 + pow25));
    final lm50 = (lm - 50) * (lm - 50);
    final sl = 1 + 0.015 * lm50 / math.sqrt(20 + lm50), sc = 1 + 0.045 * cpm, shue = 1 + 0.015 * cpm * t;
    final rt = -math.sin(2 * dTheta) * rc;
    final x = dl / sl, y = dc / sc, z = dH / shue;
    return math.sqrt(x * x + y * y + z * z + rt * y * z);
  }

  /// How alike cards [a] and [b] are (same shape class). With [stopEarly] the comparison ends as
  /// soon as the two cannot be twins, and the percentiles of twins are not worked out (the numbers
  /// are then partial; [TwinPair.twins] is right either way).
  TwinPair compare(int a, int b, {bool stopEarly = false}) {
    final la = _lab[a], lb = _lab[b];
    final cls = tiling.classOf(a);
    if (stopEarly) {
      // A part's colour differs no more than its samples do (on average and at most), so parts
      // that differ too much settle it at once.
      final pa = _parts[a], pb = _parts[b], weights = _partBoxes[cls]!;
      var sum = 0.0, count = 0;
      for (var q = 0; q < weights.length; q++) {
        if (weights[q] == 0) continue;
        final d = deltaE00(pa[3 * q], pa[3 * q + 1], pa[3 * q + 2], pb[3 * q], pb[3 * q + 1], pb[3 * q + 2]);
        if (d > maxLimit) return TwinPair(a, b, mean: d, p95: d, max: d, edge: d, speck: 0, grain: 0);
        sum += d * weights[q];
        count += weights[q];
      }
      if (count > 0 && sum / count > 1.15 * meanLimit) return TwinPair(a, b, mean: sum / count, p95: 0, max: 0, edge: 0, speck: 0, grain: 0);
    }
    final boxes = _boxes[cls]!.length, total = boxes + _strips[cls]!.length;
    final allowedOver = (total * 0.05).floor(), allowedEdgeOver = ((total - boxes) * 0.05).floor();
    var sum = 0.0, worst = 0.0, speck = 0.0;
    final grain = math.max(_grain[a], _grain[b]);
    final speckAllowed = math.max(speckLimit, speckGrain * grain);
    var over = 0, edgeOver = 0;
    final diffs = stopEarly ? null : Float64List(total);
    for (var i = 0; i < total; i++) {
      final j = _stride * i;
      final d = deltaE00(la[j], la[j + 1], la[j + 2], lb[j], lb[j + 1], lb[j + 2]);
      diffs?[i] = d;
      sum += d;
      if (d > worst) worst = d;
      if (d > p95Limit) {
        over++;
        if (i >= boxes) edgeOver++;
      }
      final s = math.max((la[j + 3] - lb[j + 3]).abs(), (la[j + 4] - lb[j + 4]).abs());
      if (s > speck) speck = s;
      if (stopEarly && (d > maxLimit || over > allowedOver || edgeOver > allowedEdgeOver || speck > speckAllowed || sum > meanLimit * total)) {
        return TwinPair(a, b, mean: sum / (i + 1), p95: d, max: worst, edge: d, speck: speck, grain: grain);
      }
    }
    final mean = total == 0 ? 0.0 : sum / total;
    // Stopped early or not, the counts above say whether 95% stay within the limit.
    if (diffs == null) return TwinPair(a, b, mean: mean, p95: 0, max: worst, edge: 0, speck: speck, grain: grain);
    double p95(Float64List xs) {
      if (xs.isEmpty) return 0;
      final s = Float64List.fromList(xs)..sort();
      return s[math.min(s.length - 1, (s.length * 0.95).ceil() - 1)];
    }

    return TwinPair(a, b, mean: mean, p95: p95(diffs), max: worst, edge: p95(Float64List.sublistView(diffs, boxes)), speck: speck, grain: grain);
  }

  /// Pairs worth comparing: same shape class, and mean colours no further apart than the mean
  /// difference allows (with some room: for colours this close CIEDE2000 behaves like a distance,
  /// and the mean of the differences is at least the difference of the means). Cards are scanned
  /// in order of lightness, within the CIE76 distance that can hold such a pair.
  Iterable<(int, int)> candidates({double reach = 6 * meanLimit}) sync* {
    final n = tiling.cells;
    final order = List<int>.generate(n, (i) => i)..sort((x, y) => _mean[x].$1.compareTo(_mean[y].$1));
    for (var i = 0; i < n; i++) {
      final a = order[i];
      final (la, aa, ba) = _mean[a];
      for (var j = i + 1; j < n; j++) {
        final b = order[j];
        final (lb, ab, bb) = _mean[b];
        if (lb - la > reach) break;
        if (tiling.classOf(a) != tiling.classOf(b)) continue;
        final d2 = (lb - la) * (lb - la) + (ab - aa) * (ab - aa) + (bb - ba) * (bb - ba);
        if (d2 > reach * reach || deltaE00(la, aa, ba, lb, ab, bb) > 1.15 * meanLimit) continue;
        yield a < b ? (a, b) : (b, a);
      }
    }
  }

  /// The twin classes: every two cards of a class are twins. Cards join the first class (in
  /// card order) whose every card is their twin.
  Twins find() {
    final pairs = <int, Set<int>>{};
    for (final (a, b) in candidates()) {
      if (compare(a, b, stopEarly: true).twins) {
        (pairs[a] ??= {}).add(b);
        (pairs[b] ??= {}).add(a);
      }
    }
    if (pairs.isEmpty) return Twins.none;
    final classes = <List<int>>[];
    for (final c in pairs.keys.toList()..sort()) {
      final mine = pairs[c]!;
      List<int>? home;
      for (final k in classes) {
        if (k.every(mine.contains)) {
          home = k;
          break;
        }
      }
      if (home != null) {
        home.add(c);
      } else {
        classes.add([c]);
      }
    }
    return Twins.fromClasses(tiling.cells, classes);
  }
}

/// [TwinFinder.find] for [spec] on [picture], as one call (for an isolate).
Twins findTwins((TwinPicture, BoardSpec) job) => TwinFinder(job.$1, job.$2).find();

/// Sums of a sample's pixels: colour, lightness (0 to 100, from the gamma-encoded values) and its
/// extremes.
class _Pixels {
  int count = 0;
  int r = 0, g = 0, b = 0;
  double luma = 0, darkest = double.infinity, lightest = double.negativeInfinity;

  void add(Uint8List px, int i) {
    final pr = px[i], pg = px[i + 1], pb = px[i + 2];
    r += pr;
    g += pg;
    b += pb;
    final y = (0.2126 * pr + 0.7152 * pg + 0.0722 * pb) / 2.55;
    luma += y;
    if (y < darkest) darkest = y;
    if (y > lightest) lightest = y;
    count++;
  }
}
