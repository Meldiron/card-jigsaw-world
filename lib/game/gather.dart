import 'dart:math' show Random;
import 'dart:ui' show Rect, Size;

import 'board.dart';

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

/// Shuffle (a Gather that has nothing to bring in): the loose cards in [view] trade places among
/// themselves at random, so the view can be read afresh. Cards in place and joined groups (even
/// ones not yet in place) stay exactly where they are; every loose card moves, none lands in its
/// own place and, where another order allows it, no pair ends up joined. Each shape class shuffles
/// within itself (up and down triangles, the half cells on hexagon edges). Null when fewer than two
/// loose cards are in view.
Board? shuffleInView(Board board, Rect view, Size size, {Random? random}) {
  final rng = random ?? Random();
  final tiling = board.tiling;
  bool loose(int slot) => !board.isLocked(slot) && board.groupOf(slot).length == 1;
  final byClass = <int, List<int>>{};
  for (var s = 0; s < board.cells; s++) {
    if (loose(s) && view.contains(tiling.cellCenter(s, size))) (byClass[tiling.classOf(s)] ??= []).add(s);
  }
  final next = List<int>.from(board.slots);
  // The card may go to [slot]: it moves, and not into its own place.
  bool fits(int slot, int card) => card != board.slots[slot] && card != slot;
  int joinsAt(int slot) {
    var n = 0;
    for (final nb in tiling.neighbours(slot)) {
      if (tiling.direction(next[slot], next[nb]) == tiling.direction(slot, nb)) n++;
    }
    return n;
  }

  void swap(int a, int b) {
    final t = next[a];
    next[a] = next[b];
    next[b] = t;
  }

  var moved = 0;
  for (final slots in byClass.values) {
    if (slots.length < 2) continue;
    // A random order in which every card moves and none goes home (about one in seven is).
    List<int>? order;
    for (var attempt = 0; attempt < 80 && order == null; attempt++) {
      final o = [for (final s in slots) board.slots[s]]..shuffle(rng);
      var ok = true;
      for (var i = 0; i < slots.length && ok; i++) {
        ok = fits(slots[i], o[i]);
      }
      if (ok) order = o;
    }
    // No such order (two cards that belong in each other's places, say): leave this class alone.
    if (order == null) continue;
    for (var i = 0; i < slots.length; i++) {
      next[slots[i]] = order[i];
    }
    // A random order joins a pair or two on a big board: a joined card trades places with another
    // loose card whenever that leaves fewer joins around the two.
    for (var round = 0; round < slots.length * 8; round++) {
      final joined = [for (final s in slots) if (joinsAt(s) > 0) s];
      if (joined.isEmpty) break;
      final a = joined[rng.nextInt(joined.length)], b = slots[rng.nextInt(slots.length)];
      if (a == b || !fits(a, next[b]) || !fits(b, next[a])) continue;
      final before = joinsAt(a) + joinsAt(b);
      swap(a, b);
      if (joinsAt(a) + joinsAt(b) >= before) swap(a, b);
    }
    moved += slots.length;
  }
  return moved == 0 ? null : Board(board.spec, next);
}
