import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'board.dart';

/// Zones of a giant board: the board cut into a few areas about the size of
/// a normal board, and a shuffle that keeps every card inside its own zone.
///
/// A giant board shuffled across all of its 100 to 300 cards cannot be read
/// on a phone: zoomed in, the cards in view could belong anywhere. Dealt by
/// zone, everything in view belongs within a few cards of where it lies, and
/// one huge puzzle becomes a handful of normal ones that build one picture
/// (the way jigsaw players sort pieces into areas first). See
/// docs/giant-boards.md.
class BoardZones {
  BoardZones._(this.cols, this.rows, this.zoneOf, this.pools, this.poolOf);

  /// The zone grid: [cols] zones across, [rows] down.
  final int cols;
  final int rows;

  /// Zone of every slot (row-major zone index).
  final List<int> zoneOf;

  /// Shuffle pools: the slots a card may be dealt to (same zone and shape
  /// class). A pool too small to shuffle (a corner piece alone in its zone)
  /// is merged with the nearest pool of its class, so those few cards may be
  /// dealt one zone over.
  final List<List<int>> pools;

  /// Pool of every slot.
  final List<int> poolOf;

  int get count => cols * rows;

  late final List<List<int>> members = () {
    final m = List.generate(count, (_) => <int>[]);
    for (var s = 0; s < zoneOf.length; s++) {
      m[zoneOf[s]].add(s);
    }
    return m;
  }();

  /// Cards each zone aims for: about a Relaxed to Tricky board of the shape
  /// (cards 30, squares 48, triangles 66, hexagons 52), so the smallest
  /// giant size has four zones and the largest about twelve.
  static double targetFor(GameMode mode) => BoardSpec.giantTargets[mode]!.first * 0.3;

  /// Fewest cards a pool needs to shuffle with no card in place and no pair
  /// still joined. Three is not enough: three half pieces down a triangle
  /// board's edge have only two ways to leave home, and both can leave a
  /// pair joined with the half pieces next to them.
  static const minPool = 5;

  static final _cache = <String, BoardZones>{};

  /// The zones of [spec]; they depend only on the board (shape and size), so
  /// a saved board finds the same zones again.
  static BoardZones of(BoardSpec spec) => _cache.putIfAbsent('${spec.mode.code}:${spec.cols}x${spec.rows}', () => _build(spec));

  /// Whether [spec] is dealt by zone (the giant sizes).
  static bool appliesTo(BoardSpec spec) => spec.isGiant;

  static BoardZones _build(BoardSpec spec) {
    final tiling = spec.tiling;
    final aspect = tiling.naturalAspect;
    final size = Size(aspect, 1);
    final n = spec.cells;
    final (zc, zr) = gridFor(n, aspect, targetFor(spec.mode));
    final centres = [for (var s = 0; s < n; s++) tiling.cellCenter(s, size)];
    final zoneOf = [
      for (final c in centres)
        (c.dy / size.height * zr).floor().clamp(0, zr - 1) * zc + (c.dx / size.width * zc).floor().clamp(0, zc - 1),
    ];
    // Pools: zone x shape class, small ones merged into the nearest pool of
    // their class until every pool can be shuffled (or the class is one pool).
    final groups = <(int, int), List<int>>{};
    for (var s = 0; s < n; s++) {
      groups.putIfAbsent((zoneOf[s], tiling.classOf(s)), () => []).add(s);
    }
    final pools = groups.values.map((g) => List<int>.from(g)).toList();
    final classOf = [for (final p in pools) tiling.classOf(p.first)];
    Offset centreOf(List<int> pool) {
      var x = 0.0, y = 0.0;
      for (final s in pool) {
        x += centres[s].dx;
        y += centres[s].dy;
      }
      return Offset(x / pool.length, y / pool.length);
    }

    while (true) {
      var small = -1;
      for (var i = 0; i < pools.length; i++) {
        if (pools[i].length >= minPool) continue;
        if (!pools.indexed.any((e) => e.$1 != i && classOf[e.$1] == classOf[i])) continue;
        if (small < 0 || pools[i].length < pools[small].length) small = i;
      }
      if (small < 0) break;
      final at = centreOf(pools[small]);
      var into = -1;
      var best = double.infinity;
      for (var i = 0; i < pools.length; i++) {
        if (i == small || classOf[i] != classOf[small]) continue;
        final d = (centreOf(pools[i]) - at).distanceSquared;
        if (d < best) {
          best = d;
          into = i;
        }
      }
      pools[into].addAll(pools[small]);
      pools.removeAt(small);
      classOf.removeAt(small);
    }
    for (final p in pools) {
      p.sort();
    }
    final poolOf = List<int>.filled(n, 0);
    for (var i = 0; i < pools.length; i++) {
      for (final s in pools[i]) {
        poolOf[s] = i;
      }
    }
    return BoardZones._(zc, zr, List.unmodifiable(zoneOf), List.unmodifiable(pools.map(List<int>.unmodifiable)), List.unmodifiable(poolOf));
  }

  /// The zone grid for a board of [cells] cards and [aspect] (width ÷
  /// height): zones close to [target] cards each and close to square on
  /// screen, at least two.
  static (int, int) gridFor(int cells, double aspect, double target) {
    var best = (1, 2);
    var bestScore = double.infinity;
    for (var zc = 1; zc <= 6; zc++) {
      for (var zr = 1; zr <= 6; zr++) {
        if (zc * zr < 2) continue;
        final per = cells / (zc * zr);
        final shape = (aspect / zc) / (1 / zr);
        final score = math.log(per / target).abs() + 0.5 * math.log(shape).abs();
        if (score < bestScore) {
          bestScore = score;
          best = (zc, zr);
        }
      }
    }
    return best;
  }

  /// Whether [board] was dealt by zone: nearly every card not in place lies
  /// in its own pool. A board shuffled across the whole board (saved before
  /// zones) has most cards elsewhere and plays on without zone lines; a few
  /// cards moved across a zone line by the player do not count.
  bool dealtIn(Board board) {
    var misplaced = 0, away = 0;
    for (var s = 0; s < board.cells; s++) {
      final card = board.slots[s];
      if (card == s) continue;
      misplaced++;
      if (poolOf[card] != poolOf[s]) away++;
    }
    return misplaced == 0 || away <= misplaced * 0.35;
  }

  /// Whether every slot of zone [z] holds its own card.
  bool complete(Board board, int z) => members[z].every(board.isLocked);

  /// Zones whose every card is in place.
  Set<int> completeZones(Board board) => {for (var z = 0; z < count; z++) if (complete(board, z)) z};

  /// The edges between two zones, as segments in a board of [size]: the
  /// shared side of every pair of neighbouring cells in different zones.
  /// [skip] leaves out the edges between two zones it names (both finished).
  List<(Offset, Offset)> borders(Tiling tiling, Size size, {Set<int> skip = const {}}) {
    final out = <(Offset, Offset)>[];
    for (var s = 0; s < zoneOf.length; s++) {
      final edges = tiling.edgeNeighbours(s);
      List<Offset>? poly;
      for (var k = 0; k < edges.length; k++) {
        final nb = edges[k];
        if (nb == null || nb < s || zoneOf[nb] == zoneOf[s]) continue;
        if (skip.contains(zoneOf[nb]) && skip.contains(zoneOf[s])) continue;
        poly ??= tiling.polygon(s, size);
        out.add((poly[k], poly[(k + 1) % poly.length]));
      }
    }
    return out;
  }

  /// The bounding box of zone [z] in a board of [size].
  Rect bounds(Tiling tiling, Size size, int z) {
    Rect? r;
    for (final s in members[z]) {
      final b = tiling.cellBounds(s, size);
      r = r == null ? b : r.expandToInclude(b);
    }
    return r ?? Rect.zero;
  }
}

/// Gather: brings every card that belongs in [view] (board coordinates,
/// the same [size] the board is laid out at) into it. Each card in view that
/// belongs elsewhere trades places with one that belongs here, chosen so the
/// card leaving goes as close to its own place as it can, and so that no
/// pair ends up joined where another choice avoids it. Cards already in
/// place, cards in a joined group and trades that would put a card straight
/// into its place are left alone: Gather sorts, it never solves. Null when
/// there is nothing to gather.
Board? gatherInto(Board board, Rect view, Size size) {
  final tiling = board.tiling;
  bool inView(int slot) => view.contains(tiling.cellCenter(slot, size));
  bool single(int slot) => !board.isLocked(slot) && board.groupOf(slot).length == 1;
  final here = <int>{for (var s = 0; s < board.cells; s++) if (inView(s)) s};
  // Slots in view holding a card that belongs outside it, and slots outside
  // holding a card that belongs in view.
  final foreign = [for (final s in here) if (single(s) && !here.contains(board.homeOf(s))) s];
  final missing = <int>[for (var s = 0; s < board.cells; s++) if (!here.contains(s) && single(s) && here.contains(board.homeOf(s))) s];
  if (foreign.isEmpty || missing.isEmpty) return null;
  final next = List<int>.from(board.slots);
  bool joinsAt(int slot) {
    for (final nb in tiling.neighbours(slot)) {
      if (tiling.direction(next[slot], next[nb]) == tiling.direction(slot, nb)) return true;
    }
    return false;
  }

  final taken = <int>{};
  var moved = 0;
  for (final f in foreign) {
    final cls = tiling.classOf(f);
    final goal = tiling.cellCenter(next[f], size);
    // Candidates nearest first: the card leaving lands as close to its place as it can.
    final candidates = [
      for (final m in missing)
        // Neither card may land in its own place.
        if (!taken.contains(m) && tiling.classOf(m) == cls && board.homeOf(m) != f && board.homeOf(f) != m) m,
    ]..sort((a, b) => (tiling.cellCenter(a, size) - goal).distanceSquared.compareTo((tiling.cellCenter(b, size) - goal).distanceSquared));
    if (candidates.isEmpty) continue;
    // The nearest trade that joins no pair, else the nearest.
    int? pick;
    for (final m in candidates) {
      final a = next[f], b = next[m];
      next[f] = b;
      next[m] = a;
      final joins = joinsAt(f) || joinsAt(m);
      next[f] = a;
      next[m] = b;
      if (!joins) {
        pick = m;
        break;
      }
    }
    pick ??= candidates.first;
    taken.add(pick);
    final t = next[f];
    next[f] = next[pick];
    next[pick] = t;
    moved++;
  }
  return moved == 0 ? null : Board(board.spec, next);
}

/// A new board for [spec]: dealt by zone on the giant sizes, across the
/// whole board otherwise.
Board dealBoard(BoardSpec spec, {int? seed}) =>
    BoardZones.appliesTo(spec) ? Board.shuffled(spec, seed: seed, pools: BoardZones.of(spec).pools) : Board.shuffled(spec, seed: seed);
