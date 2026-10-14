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
