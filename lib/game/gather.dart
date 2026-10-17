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
/// there is nothing to gather. With [twins] a twin's place counts as the
/// card's own and a twin's join as a join (docs/twins.md).
Board? gatherInto(Board board, Rect view, Size size, {Twins? twins}) {
  final tw = twins ?? Twins.none;
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
      if (tw.looksJoined(tiling, slot, next[slot], nb, next[nb])) return true;
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
        if (!taken.contains(m) && tiling.classOf(m) == cls && !tw.looksPlaced(board.homeOf(m), f) && !tw.looksPlaced(board.homeOf(f), m)) m,
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

/// Whether [gatherInto] has anything to do for [view]: a loose card in view that belongs outside it
/// can trade places with a loose card outside that belongs in it, without either landing in its
/// own place. The Gather button is off otherwise. The same test as the gather's, without its
/// sorting, so the game screen can ask whenever the view settles.
bool canGather(Board board, Rect view, Size size, {Twins? twins}) {
  final tw = twins ?? Twins.none;
  final tiling = board.tiling;
  final here = List<bool>.generate(board.cells, (s) => view.contains(tiling.cellCenter(s, size)));
  bool single(int slot) => !board.isLocked(slot) && board.groupOf(slot).length == 1;
  final missing = <int, List<int>>{};
  for (var s = 0; s < board.cells; s++) {
    if (!here[s] && single(s) && here[board.homeOf(s)]) (missing[tiling.classOf(s)] ??= []).add(s);
  }
  if (missing.isEmpty) return false;
  for (var f = 0; f < board.cells; f++) {
    if (!here[f] || !single(f) || here[board.homeOf(f)]) continue;
    for (final m in missing[tiling.classOf(f)] ?? const <int>[]) {
      if (!tw.looksPlaced(board.homeOf(m), f) && !tw.looksPlaced(board.homeOf(f), m)) return true;
    }
  }
  return false;
}

/// Shuffle (owner, 2026-10-17: the round button left of the tools, free): the loose cards trade
/// places among themselves at random, so the board can be read afresh. Only slots [where] allows
/// take part (every slot without it). Cards in place and joined groups (even ones not yet in place)
/// stay exactly where they are; every loose card moves, none lands in its own place and, where
/// another order allows it, no pair ends up joined. Each shape class shuffles within itself (up and
/// down triangles, the half cells on hexagon edges). Null when nothing can move (fewer than two
/// loose cards of a shape). With [twins] a twin counts as the card itself: no card lands on a
/// twin's place or next to a neighbour a twin would join (docs/twins.md).
Board? shuffleLoose(Board board, {bool Function(int slot)? where, Random? random, Twins? twins}) {
  final tw = twins ?? Twins.none;
  final rng = random ?? Random();
  final tiling = board.tiling;
  bool loose(int slot) => !board.isLocked(slot) && board.groupOf(slot).length == 1;
  final byClass = <int, List<int>>{};
  for (var s = 0; s < board.cells; s++) {
    if (loose(s) && (where == null || where(s))) (byClass[tiling.classOf(s)] ??= []).add(s);
  }
  final next = List<int>.from(board.slots);
  // The card may go to [slot]: it moves, and not into its own place.
  bool fits(int slot, int card) => card != board.slots[slot] && !tw.looksPlaced(card, slot);
  int joinsAt(int slot) {
    var n = 0;
    for (final nb in tiling.neighbours(slot)) {
      if (tw.looksJoined(tiling, slot, next[slot], nb, next[nb])) n++;
    }
    return n;
  }

  void swap(int a, int b) {
    final t = next[a];
    next[a] = next[b];
    next[b] = t;
  }

  // Twins look joined in many more places: a joined card trades with the best of its shape's
  // cards (each one on a small board, a few on a big one), now and then for an even trade.
  void untangle(List<int> slots) {
    var joined = <int>[];
    for (var round = 0; round < slots.length * 12; round++) {
      if (round % 16 == 0) joined = [for (final s in slots) if (joinsAt(s) > 0) s];
      if (joined.isEmpty) break;
      final a = joined[rng.nextInt(joined.length)];
      var best = -1, bestGain = -1 << 30;
      final few = slots.length > 48;
      for (var k = 0; k < (few ? 6 : slots.length); k++) {
        final b = few ? slots[rng.nextInt(slots.length)] : slots[k];
        if (a == b || !fits(a, next[b]) || !fits(b, next[a])) continue;
        final before = joinsAt(a) + joinsAt(b);
        swap(a, b);
        final gain = before - joinsAt(a) - joinsAt(b);
        swap(a, b);
        if (gain > bestGain) {
          bestGain = gain;
          best = b;
        }
      }
      if (best >= 0 && (bestGain > 0 || (bestGain == 0 && rng.nextInt(4) == 0))) swap(a, best);
    }
  }

  var moved = 0;
  final dealt = <List<int>>[];
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
    // Twins make such an order rare when many look alike: trade cards until every one fits.
    if (order == null && !tw.isEmpty) order = _fitting(slots, [for (final s in slots) board.slots[s]], fits, rng);
    // No such order (two cards that belong in each other's places, say): leave this class alone.
    if (order == null) continue;
    for (var i = 0; i < slots.length; i++) {
      next[slots[i]] = order[i];
    }
    // A random order joins a pair or two on a big board: a joined card trades places with another
    // loose card whenever that leaves fewer joins around the two.
    if (tw.isEmpty) {
      for (var round = 0; round < slots.length * 8; round++) {
        final joined = [for (final s in slots) if (joinsAt(s) > 0) s];
        if (joined.isEmpty) break;
        final a = joined[rng.nextInt(joined.length)], b = slots[rng.nextInt(slots.length)];
        if (a == b || !fits(a, next[b]) || !fits(b, next[a])) continue;
        final before = joinsAt(a) + joinsAt(b);
        swap(a, b);
        if (joinsAt(a) + joinsAt(b) >= before) swap(a, b);
      }
    } else {
      untangle(slots);
      dealt.add(slots);
    }
    moved += slots.length;
  }
  // A shape shuffled later can join a card of one shuffled before: once more round every shape.
  for (final slots in dealt) {
    untangle(slots);
  }
  return moved == 0 ? null : Board(board.spec, next);
}

/// An order of [cards] over [slots] in which every card [fits] its slot, found by trading cards
/// from a random order while that leaves fewer misfits; null when none turns up.
List<int>? _fitting(List<int> slots, List<int> cards, bool Function(int slot, int card) fits, Random rng) {
  final o = List<int>.from(cards)..shuffle(rng);
  int misfits(int i) => fits(slots[i], o[i]) ? 0 : 1;
  List<int> misfitting() => [for (var i = 0; i < slots.length; i++) if (!fits(slots[i], o[i])) i];
  var bad = misfitting();
  for (var round = 0; round < slots.length * 40; round++) {
    if (round % 32 == 31) bad = misfitting();
    if (bad.isEmpty && (bad = misfitting()).isEmpty) return o;
    final i = bad[rng.nextInt(bad.length)], j = rng.nextInt(slots.length);
    if (i == j) continue;
    final before = misfits(i) + misfits(j);
    final t = o[i];
    o[i] = o[j];
    o[j] = t;
    final after = misfits(i) + misfits(j);
    if (after > before || (after == before && rng.nextInt(3) != 0)) {
      o[j] = o[i];
      o[i] = t;
    }
  }
  return misfitting().isEmpty ? o : null;
}

/// Shuffle on a giant board: only the loose cards in [view] (board coordinates at the board's
/// [size]) trade places, so the part being looked at is dealt afresh and the rest stays put.
Board? shuffleInView(Board board, Rect view, Size size, {Random? random, Twins? twins}) =>
    shuffleLoose(board, where: (slot) => view.contains(board.tiling.cellCenter(slot, size)), random: random, twins: twins);
