import 'package:flutter/foundation.dart';

/// One slot of a [BoardChange]: the card the slot held before and the card it holds after.
@immutable
class SlotChange {
  const SlotChange(this.slot, this.before, this.after);
  final int slot;
  final int before;
  final int after;

  @override
  bool operator ==(Object other) => other is SlotChange && other.slot == slot && other.before == before && other.after == after;

  @override
  int get hashCode => Object.hash(slot, before, after);

  @override
  String toString() => '$slot:$before>$after';
}

/// A change to a shared board (Play together, docs/multiplayer.md): every slot whose card changed,
/// with the card it held before and the card it holds after. A move of one card, a group pushed
/// with the cards it displaced, Magic, Shuffle and Gather are all one change.
///
/// A change applies only to a board where every one of its slots still holds the card it expects
/// ([fits]); otherwise the whole change is skipped. Every player applies the same changes in the
/// server's order with this rule, so every board ends up the same.
@immutable
class BoardChange {
  BoardChange(List<SlotChange> slots) : slots = List.unmodifiable(slots);

  /// The change from [before] to [after] (two layouts of one board: `layout[slot]` is the card).
  factory BoardChange.between(List<int> before, List<int> after) {
    assert(before.length == after.length);
    return BoardChange([
      for (var s = 0; s < before.length; s++)
        if (before[s] != after[s]) SlotChange(s, before[s], after[s]),
    ]);
  }

  final List<SlotChange> slots;

  bool get isEmpty => slots.isEmpty;

  /// The slots this change touches.
  Set<int> get slotSet => {for (final c in slots) c.slot};

  /// Whether every slot of this change holds the card the change expects in [layout].
  bool fits(List<int> layout) {
    for (final c in slots) {
      if (c.slot >= layout.length || layout[c.slot] != c.before) return false;
    }
    return true;
  }

  /// [layout] with this change made (call only when it [fits]).
  List<int> applyTo(List<int> layout) {
    final next = List<int>.of(layout);
    for (final c in slots) {
      next[c.slot] = c.after;
    }
    return next;
  }

  /// The change undone: the cards go back.
  BoardChange get inverse => BoardChange([for (final c in slots) SlotChange(c.slot, c.after, c.before)]);

  /// Slots that hold their own card after this change and did not before (cards it locked).
  Set<int> get locks => {for (final c in slots) if (c.after == c.slot && c.before != c.slot) c.slot};

  /// As the move row stores it: `slot:before:after` per slot, separated by commas.
  String encode() => slots.map((c) => '${c.slot}:${c.before}:${c.after}').join(',');

  /// Reads [text] back for a board of [cells] cards; null when it is not a change of that board:
  /// a slot out of range or twice, or cards that do not trade places among the change's own slots
  /// (a change must keep the board a permutation).
  static BoardChange? decode(String text, int cells) {
    if (text.isEmpty) return null;
    final out = <SlotChange>[];
    final seen = <int>{};
    for (final part in text.split(',')) {
      final f = part.split(':');
      if (f.length != 3) return null;
      final s = int.tryParse(f[0]), b = int.tryParse(f[1]), a = int.tryParse(f[2]);
      if (s == null || b == null || a == null) return null;
      if (s < 0 || s >= cells || b < 0 || b >= cells || a < 0 || a >= cells || !seen.add(s)) return null;
      out.add(SlotChange(s, b, a));
    }
    final before = [for (final c in out) c.before]..sort();
    final after = [for (final c in out) c.after]..sort();
    if (!listEquals(before, after)) return null;
    if (before.toSet().length != before.length) return null;
    return BoardChange(out);
  }

  @override
  bool operator ==(Object other) => other is BoardChange && listEquals(other.slots, slots);

  @override
  int get hashCode => Object.hashAll(slots);

  @override
  String toString() => 'BoardChange(${encode()})';
}
