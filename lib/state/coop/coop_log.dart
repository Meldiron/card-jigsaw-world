import 'package:flutter/foundation.dart';

import 'coop_models.dart';

/// What one step of the [CoopLog] did to the board this device shows.
@immutable
class LogUpdate {
  const LogUpdate({required this.before, required this.after, this.applied = const [], this.dropped = const []});

  /// The board shown before and after the step.
  final List<int> before;
  final List<int> after;

  /// Other players' changes that reached the board in this step (their cards carry the player's
  /// initial for a moment).
  final List<CoopOp> applied;

  /// This device's changes that no longer apply: a change made earlier in the server's order took
  /// one of their cards, so their cards slide back.
  final List<CoopOp> dropped;

  bool get changed => !listEquals(before, after);

  /// Slots whose card changed.
  Set<int> get changedSlots => {for (var s = 0; s < after.length; s++) if (s < before.length && before[s] != after[s]) s};
}

class _Entry {
  _Entry(this.op);
  final CoopOp op;
  bool applied = false;
  int locked = 0;
}

/// The shared board of one game's board (Play together, docs/multiplayer.md): the dealt layout and
/// every change, in the server's order (`$sequence`), plus this device's changes still on their way.
///
/// - **Deterministic**: a change applies when every one of its slots holds the card it expects,
///   else the whole change is skipped. Every device applies the same changes in the same order, so
///   every device shows the same board, whatever order the changes arrived in.
/// - **Arrival order does not matter**: realtime events can arrive out of order (measured: 6 of 30
///   in a burst) and the catch-up after a reconnect brings changes twice. A change is kept once (by
///   row id); one that belongs before changes already applied undoes those, takes its place and
///   applies them again.
/// - **Own changes show at once** (pending, [addLocal]) and are applied after the confirmed ones.
///   When the server's order puts another player's change first and it took one of their cards, they
///   no longer fit: they leave the board shown (their cards slide back, [LogUpdate.dropped]).
class CoopLog {
  CoopLog({required this.gameId, required this.board, required List<int> base, required this.me, DateTime Function()? clock})
      : base = List.unmodifiable(base),
        _board = List.of(base),
        _local = List.of(base),
        _clock = clock ?? DateTime.now;

  final String gameId;

  /// The game's board number this log is for (changes of another board are ignored).
  final int board;

  /// The board as dealt.
  final List<int> base;

  /// This device's player.
  final String me;
  final DateTime Function() _clock;

  final _log = <_Entry>[];
  final _ids = <String>{};
  final _pending = <CoopOp>[];
  final _locks = <String, int>{};
  final _receivedAt = <String, DateTime>{};
  List<int> _board;
  List<int> _local;
  Set<String> _shown = {};

  /// The board every device agrees on: the confirmed changes only.
  List<int> get confirmed => List.unmodifiable(_board);

  /// The board this device shows: the confirmed changes, then its own pending ones that still fit.
  List<int> get layout => List.unmodifiable(_local);

  /// Changes in the server's order.
  List<CoopOp> get ops => [for (final e in _log) e.op];

  /// This device's changes still on their way, in the order made.
  List<CoopOp> get pending => List.unmodifiable(_pending);

  /// Highest server order seen.
  int get lastSeq => _log.isEmpty ? 0 : _log.last.op.seq!;

  bool get isSolved => _isSolved(_board);

  static bool _isSolved(List<int> b) {
    for (var i = 0; i < b.length; i++) {
      if (b[i] != i) return false;
    }
    return b.isNotEmpty;
  }

  /// Cards [userId]'s own moves locked in place (Magic, Shuffle and Gather do not count): a guest
  /// earns the board's rewards with at least one.
  int locksBy(String userId) => _locks[userId] ?? 0;

  /// Whether the server skipped change [id] (it no longer fit when its turn came).
  bool wasSkipped(String id) => _log.any((e) => e.op.id == id && !e.applied);

  bool knows(String id) => _ids.contains(id) || _pending.any((p) => p.id == id);

  /// Where a catch-up read starts (`$sequence` greater than this). Changes are confirmed out of
  /// order within moments of each other, so a read from the newest one could miss one committed a
  /// moment earlier and lost with a dropped connection. It starts instead from the newest change
  /// received [margin] before the latest one; what comes twice is kept once.
  int catchUpFrom({Duration margin = const Duration(seconds: 30)}) {
    if (_log.isEmpty) return 0;
    var latest = DateTime.fromMillisecondsSinceEpoch(0);
    for (final t in _receivedAt.values) {
      if (t.isAfter(latest)) latest = t;
    }
    final cutoff = latest.subtract(margin);
    var from = 0;
    for (final e in _log) {
      final t = _receivedAt[e.op.id];
      if (t != null && !t.isAfter(cutoff) && e.op.seq! > from) from = e.op.seq!;
    }
    return from;
  }

  /// This device's change [op], made on the board it shows. Null when it does not fit that board
  /// (the board changed under it): nothing to send.
  LogUpdate? addLocal(CoopOp op) {
    if (op.change.isEmpty || !op.change.fits(_local) || knows(op.id)) return null;
    final before = _local;
    _pending.add(op);
    _local = op.change.applyTo(_local);
    _shown = {..._shown, op.id};
    return LogUpdate(before: before, after: _local);
  }

  /// A change from the server: another player's (realtime, catch-up) or this device's own with its
  /// place in the order. Seen before: nothing happens.
  LogUpdate addRemote(CoopOp op) {
    final before = _local;
    if (op.board != board || op.gameId != gameId || op.seq == null || _ids.contains(op.id)) return LogUpdate(before: before, after: before);
    _receivedAt[op.id] = _clock();
    _pending.removeWhere((p) => p.id == op.id);
    final entry = _insert(op);
    final dropped = _rebase();
    final applied = entry.applied && op.userId != me ? [op] : const <CoopOp>[];
    return LogUpdate(before: before, after: _local, applied: applied, dropped: dropped);
  }

  /// The server took this device's change [id] at [seq] (the answer to its create).
  LogUpdate confirm(String id, int seq) {
    final op = _pending.where((p) => p.id == id).firstOrNull;
    if (op == null) return LogUpdate(before: _local, after: _local);
    return addRemote(op.withSeq(seq));
  }

  /// The server will never take this device's change [id] (refused: the player left or was
  /// removed). Its cards go back.
  LogUpdate reject(String id) {
    final before = _local;
    final op = _pending.where((p) => p.id == id).firstOrNull;
    final wasShown = _shown.contains(id);
    _pending.removeWhere((p) => p.id == id);
    final dropped = _rebase();
    return LogUpdate(before: before, after: _local, dropped: [if (op != null && wasShown) op, ...dropped]);
  }

  _Entry _insert(CoopOp op) {
    _ids.add(op.id);
    var i = _log.length;
    while (i > 0 && _log[i - 1].op.seq! > op.seq!) {
      i--;
    }
    // Undo the changes that come after it in the server's order, apply it, then them again.
    for (var k = _log.length - 1; k >= i; k--) {
      _undo(_log[k]);
    }
    final entry = _Entry(op);
    _log.insert(i, entry);
    for (var k = i; k < _log.length; k++) {
      _do(_log[k]);
    }
    return entry;
  }

  void _do(_Entry e) {
    final change = e.op.change;
    if (!change.fits(_board)) {
      e.applied = false;
      e.locked = 0;
      return;
    }
    e.applied = true;
    e.locked = e.op.kind == CoopOpKind.move ? change.locks.length : 0;
    _board = change.applyTo(_board);
    if (e.locked > 0) _locks[e.op.userId] = (_locks[e.op.userId] ?? 0) + e.locked;
  }

  void _undo(_Entry e) {
    if (!e.applied) return;
    _board = e.op.change.inverse.applyTo(_board);
    if (e.locked > 0) _locks[e.op.userId] = (_locks[e.op.userId] ?? 0) - e.locked;
    e.applied = false;
    e.locked = 0;
  }

  /// The board shown again: the confirmed board, then the pending changes that still fit. Returns
  /// this device's changes that were shown and no longer are.
  List<CoopOp> _rebase() {
    var local = _board;
    final shown = <String>{
      for (final e in _log)
        if (e.applied && e.op.userId == me) e.op.id,
    };
    for (final p in _pending) {
      if (p.change.fits(local)) {
        local = p.change.applyTo(local);
        shown.add(p.id);
      }
    }
    final mine = {for (final e in _log) e.op.id: e.op, for (final p in _pending) p.id: p};
    final dropped = [for (final id in _shown) if (!shown.contains(id) && mine[id] != null) mine[id]!];
    _shown = shown;
    _local = local;
    return dropped;
  }
}
