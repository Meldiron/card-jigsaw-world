import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Live picks and drags (docs/multiplayer.md, "Live picks and drags"): every player has one row in
/// `coop_drags` per game, made by the `api` function when they start or join it (read(team) and
/// update(user)). It holds what the player does with a card right now: the card picked with a tap,
/// or the card being dragged and where it is (a fraction of the board, so any screen size works).
/// A pick, a put-down, the start and the end of a drag are sent at once; a drag's position at a
/// steady rate while the finger moves ([LiveSender]). The others play a drag back smoothly
/// ([DragPath], [LiveTracks]).
enum LivePhase {
  /// Nothing in hand.
  none(''),

  /// A card picked with a tap.
  pick('pick'),

  /// A card being dragged; x and y are its centre.
  drag('drag'),

  /// The drag ended on another place: the move follows (in `coop_moves`).
  drop('drop'),

  /// The drag ended where it started, or was cancelled: the card goes back.
  cancel('cancel');

  const LivePhase(this.code);
  final String code;

  static LivePhase fromCode(Object? code) => values.firstWhere((p) => p.code == code, orElse: () => none);
}

/// One state of a player's live row.
@immutable
class CoopLive {
  const CoopLive({required this.userId, required this.board, required this.phase, this.card = -1, this.x = 0, this.y = 0, this.drag = 0, this.seq = 0, this.t = 0});

  final String userId;

  /// The game's board number (a state of another board is not shown).
  final int board;
  final LivePhase phase;

  /// The card picked or dragged (-1: none).
  final int card;

  /// The dragged card's centre, as a fraction of the board's width and height.
  final double x;
  final double y;

  /// The drag's id (the time it started, in ms), the same for every state of one drag.
  final int drag;

  /// Increases with every state the player sends (milliseconds, so a restarted app still sends
  /// higher numbers): the others drop states that arrive after a newer one.
  final int seq;

  /// Milliseconds since the drag started, when the finger was here: the others play the path back
  /// at the pace it was made, whatever the network did to it.
  final int t;

  bool get dragging => phase == LivePhase.drag || phase == LivePhase.drop || phase == LivePhase.cancel;

  CoopLive copyWith({int? seq}) => CoopLive(userId: userId, board: board, phase: phase, card: card, x: x, y: y, drag: drag, seq: seq ?? this.seq, t: t);

  Map<String, dynamic> toData() => {'board': board, 'phase': phase.code, 'card': card, 'x': x, 'y': y, 'drag': drag, 'seq': seq, 't': t};

  /// The row's id: one per player and game (the `api` function makes the same, md5 of
  /// `live:<game>:<player>`).
  static String rowId(String gameId, String userId) => md5.convert(utf8.encode('live:$gameId:$userId')).toString();

  /// The permissions the function gives the row: the game's players read it, its player writes it.
  static List<String> permissionsFor(String gameId, String userId) => ['read("team:$gameId")', 'update("user:$userId")'];

  /// Reads a row (or a realtime payload) of a board of [cells] cards; null when it is not a state
  /// this device can show, or its author is not proven by its permissions.
  static CoopLive? fromRow(Map<String, dynamic> row, {required int cells}) {
    final userId = row['userId'];
    if (userId is! String || userId.isEmpty) return null;
    final perms = (row[r'$permissions'] as List?)?.map((p) => '$p') ?? const <String>[];
    if (!perms.contains('update("user:$userId")')) return null;
    final phase = LivePhase.fromCode(row['phase']);
    final card = (row['card'] as num?)?.toInt() ?? -1;
    final x = (row['x'] as num?)?.toDouble() ?? 0, y = (row['y'] as num?)?.toDouble() ?? 0;
    if (phase != LivePhase.none && (card < 0 || card >= cells)) return null;
    if (!x.isFinite || !y.isFinite || x < -1 || x > 2 || y < -1 || y > 2) return null;
    return CoopLive(
      userId: userId,
      board: (row['board'] as num?)?.toInt() ?? 0,
      phase: phase,
      card: phase == LivePhase.none ? -1 : card,
      x: x,
      y: y,
      drag: (row['drag'] as num?)?.toInt() ?? 0,
      seq: (row['seq'] as num?)?.toInt() ?? 0,
      t: (row['t'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() => 'CoopLive($userId ${phase.name} card $card drag $drag seq $seq t $t (${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}))';
}

/// The live row refused an update for now (Appwrite's rate limit: 120 updates a minute per player).
class LiveRateLimited implements Exception {
  const LiveRateLimited();
}

/// The live row is not there (a game made before live rows, or the player is out of it): nothing
/// more is sent for this game.
class LiveRowMissing implements Exception {
  const LiveRowMissing();
}

/// Sends this player's live state ([CoopLive]), one update at a time and always the latest:
///
/// - a pick, a put-down, the start and the end of a drag go at once (the end of a drag is never
///   folded into what follows, so the others always learn how it ended);
/// - a drag's position goes every [interval] while the finger moves (5 a second while the minute's
///   budget is fresh, fewer as it runs low), only where it is now;
/// - Appwrite allows 120 row updates a minute per player (measured: `X-RateLimit-Limit: 120`, a
///   fixed one-minute window): the sender keeps under [budget] in any minute, sends no positions when
///   the budget is spent, and waits [blockFor] after a refusal.
class LiveSender {
  LiveSender({
    required this.userId,
    required this.board,
    required this.send,
    DateTime Function()? clock,
    this.budget = 110,
    this.window = const Duration(seconds: 60),
    this.blockFor = const Duration(seconds: 10),
  }) : _clock = clock ?? DateTime.now;

  final String userId;
  int board;
  final Future<void> Function(CoopLive state) send;
  final DateTime Function() _clock;
  final int budget;
  final Duration window;
  final Duration blockFor;

  /// No row for this game: nothing is sent.
  bool disabled = false;

  final _queue = <CoopLive>[];
  final _sent = Queue<DateTime>();
  bool _busy = false;
  DateTime? _blockedUntil;
  Timer? _wake;
  Timer? _positionTimer;
  DateTime _positionAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _positionDirty = false;
  int _seq = 0;
  int? _picked;
  int? _dragCard;
  int _drag = 0;
  DateTime? _dragStart;
  double _x = 0, _y = 0;
  bool _disposed = false;

  /// Updates sent in the last [window].
  int get used {
    final since = _clock().subtract(window);
    while (_sent.isNotEmpty && !_sent.first.isAfter(since)) {
      _sent.removeFirst();
    }
    return _sent.length;
  }

  /// How often a drag's position goes now: 5 a second while the budget is fresh, then 3, 2 and 1;
  /// null once it is nearly spent (picks and drag ends keep the rest).
  Duration? get interval {
    final n = used;
    if (n < budget * 0.45) return const Duration(milliseconds: 200);
    if (n < budget * 0.7) return const Duration(milliseconds: 334);
    if (n < budget * 0.85) return const Duration(milliseconds: 500);
    if (n < budget * 0.95) return const Duration(seconds: 1);
    return null;
  }

  bool get dragging => _dragCard != null;

  /// The card picked with a tap, or null when it was put down or placed.
  void pick(int? card) {
    if (card == _picked) return;
    _picked = card;
    if (dragging) return; // the drag's own states show what is in hand; its end sends the pick
    _enqueue(_state(card == null ? LivePhase.none : LivePhase.pick, card: card ?? -1));
  }

  /// The finger took [card] at ([x], [y]) (fractions of the board).
  void dragStart(int card, double x, double y) {
    final now = _clock();
    _dragCard = card;
    _dragStart = now;
    _drag = math.max(_drag + 1, now.millisecondsSinceEpoch);
    _x = x;
    _y = y;
    _positionDirty = false;
    _positionAt = now;
    _enqueue(_state(LivePhase.drag, card: card));
  }

  /// The dragged card's centre is at ([x], [y]) now.
  void dragMove(double x, double y) {
    if (!dragging) return;
    _x = x;
    _y = y;
    _positionDirty = true;
    _schedulePosition();
  }

  /// The drag ended: [dropped] when it moved the card (a move follows), else it goes back.
  void dragEnd({required bool dropped}) {
    if (!dragging) return;
    _positionTimer?.cancel();
    _positionTimer = null;
    _positionDirty = false;
    final end = _state(dropped ? LivePhase.drop : LivePhase.cancel, card: _dragCard!);
    _dragCard = null;
    _enqueue(end);
    // A card still picked shows again after a cancelled drag.
    if (!dropped && _picked != null) _enqueue(_state(LivePhase.pick, card: _picked!));
  }

  /// A new board: nothing is in hand.
  void reset(int board) {
    this.board = board;
    _positionTimer?.cancel();
    _positionTimer = null;
    _dragCard = null;
    _picked = null;
    _queue.clear();
  }

  void dispose() {
    _disposed = true;
    _positionTimer?.cancel();
    _wake?.cancel();
    _queue.clear();
  }

  CoopLive _state(LivePhase phase, {required int card}) {
    final start = _dragStart;
    final drag = phase == LivePhase.none || phase == LivePhase.pick;
    return CoopLive(
      userId: userId,
      board: board,
      phase: phase,
      card: card,
      x: drag ? 0 : _x,
      y: drag ? 0 : _y,
      drag: drag ? 0 : _drag,
      t: drag || start == null ? 0 : _clock().difference(start).inMilliseconds,
    );
  }

  void _schedulePosition() {
    if (_positionTimer != null || disabled || _disposed) return;
    final every = interval;
    final since = _clock().difference(_positionAt);
    // Budget spent: look again in a second (the minute moves on).
    final wait = every == null ? const Duration(seconds: 1) : (every - since);
    _positionTimer = Timer(wait.isNegative ? Duration.zero : wait, () {
      _positionTimer = null;
      if (!dragging || !_positionDirty) return;
      if (interval == null) return _schedulePosition();
      _positionDirty = false;
      _positionAt = _clock();
      _enqueue(_state(LivePhase.drag, card: _dragCard!));
    });
  }

  /// Folds [s] into the last waiting state when only the newest of the two matters: positions of
  /// one drag, picks and put-downs, a pick followed by a drag. The end of a drag always stays.
  void _enqueue(CoopLive s) {
    if (disabled || _disposed) return;
    if (_queue.isNotEmpty) {
      final last = _queue.last;
      final lastLoose = last.phase == LivePhase.none || last.phase == LivePhase.pick;
      final sameDrag = last.phase == LivePhase.drag && s.phase == LivePhase.drag && last.drag == s.drag;
      if (sameDrag || (lastLoose && (s.phase == LivePhase.none || s.phase == LivePhase.pick || s.phase == LivePhase.drag))) {
        _queue[_queue.length - 1] = s;
        unawaited(_pump());
        return;
      }
    }
    _queue.add(s);
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_busy || _disposed) return;
    _busy = true;
    try {
      while (_queue.isNotEmpty && !disabled && !_disposed) {
        final now = _clock();
        final blocked = _blockedUntil;
        if (blocked != null && now.isBefore(blocked)) {
          _wakeAt(blocked.difference(now));
          return;
        }
        final head = _queue.first;
        final position = head.phase == LivePhase.drag;
        if (used >= budget) {
          // Out of budget: positions wait for the next drag move; the rest waits for the minute.
          if (position && _queue.length > 1) {
            _queue.removeAt(0);
            continue;
          }
          _wakeAt(_sent.first.add(window).difference(now) + const Duration(milliseconds: 50));
          return;
        }
        _queue.removeAt(0);
        _seq = math.max(_seq + 1, now.millisecondsSinceEpoch);
        final s = head.copyWith(seq: _seq);
        _sent.add(now);
        try {
          await send(s);
        } on LiveRowMissing {
          disabled = true;
          _queue.clear();
          return;
        } on LiveRateLimited {
          _blockedUntil = _clock().add(blockFor);
          if (!position && !_queue.any((q) => q.phase != LivePhase.drag)) _queue.insert(0, head);
        } catch (e) {
          debugPrint('coop live: $e');
          // Offline for a moment: what is in hand goes again; an old position does not.
          if (!position && _queue.isEmpty) _queue.add(head);
          _blockedUntil = _clock().add(const Duration(seconds: 2));
        }
      }
    } finally {
      _busy = false;
    }
  }

  void _wakeAt(Duration wait) {
    _wake?.cancel();
    _wake = Timer(wait.isNegative ? Duration.zero : wait, () {
      _wake = null;
      unawaited(_pump());
    });
  }
}

/// A drag of another player, as it arrives: the positions with the time the finger was there
/// (sender time) and the time each arrived here. Played back [delay] behind the newest arrival, so
/// it glides at the pace it was made, not in network jumps.
class DragPath {
  DragPath({required this.userId, required this.drag, required this.card});

  final String userId;
  final int drag;
  final int card;
  final _samples = <({int t, double x, double y, int at})>[];

  /// When the last state of this drag arrived here.
  DateTime lastHeard = DateTime.fromMillisecondsSinceEpoch(0);

  /// The drag ended with a drop; the move is on its way.
  DateTime? droppedAt;
  double _played = double.negativeInfinity;
  int? _base;

  bool get dropped => droppedAt != null;
  int get samples => _samples.length;
  ({double x, double y}) get latest => (x: _samples.last.x, y: _samples.last.y);

  void add(int t, double x, double y, DateTime at) {
    final ms = at.millisecondsSinceEpoch;
    lastHeard = at;
    // Out of order within the drag (the newest state wins on the row, but realtime keeps no
    // order): the sample still goes in its place on the path.
    var i = _samples.length;
    while (i > 0 && _samples[i - 1].t > t) {
      i--;
    }
    if (i > 0 && _samples[i - 1].t == t) {
      _samples[i - 1] = (t: t, x: x, y: y, at: ms);
    } else {
      _samples.insert(i, (t: t, x: x, y: y, at: ms));
    }
    final rel = ms - t;
    _base = _base == null ? rel : math.min(_base!, rel);
  }

  /// How far behind the drag is played: one gap between positions, plus how late the latest ones
  /// arrived compared with the earliest (network jitter), within 150 to 600 ms.
  int get delay {
    final base = _base;
    if (base == null) return 150;
    var late = 0;
    for (final s in _samples.reversed.take(8)) {
      late = math.max(late, s.at - s.t - base);
    }
    return (late + 120).clamp(150, 600);
  }

  /// Where the card is drawn at [now]: on the path, [delay] behind; the newest position when
  /// [latest] (Reduce motion: no glide).
  ({double x, double y}) positionAt(DateTime now, {bool latest = false}) {
    if (latest || _samples.length == 1) return this.latest;
    final play = math.max(_played, (now.millisecondsSinceEpoch - _base! - delay).toDouble());
    _played = play;
    final first = _samples.first, last = _samples.last;
    if (play <= first.t) return (x: first.x, y: first.y);
    if (play >= last.t) return (x: last.x, y: last.y);
    for (var i = 1; i < _samples.length; i++) {
      final b = _samples[i];
      if (play <= b.t) {
        final a = _samples[i - 1];
        final f = b.t == a.t ? 1.0 : (play - a.t) / (b.t - a.t);
        return (x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f);
      }
    }
    return (x: last.x, y: last.y);
  }
}

/// Where another player's dragged card is drawn now.
@immutable
class LiveGhost {
  const LiveGhost({required this.userId, required this.card, required this.x, required this.y});
  final String userId;
  final int card;
  final double x;
  final double y;
}

class _PlayerLive {
  int seq = 0;
  CoopLive? current;
  final paths = <int, DragPath>{};
  final done = <int>{};

  void finish(int drag) {
    paths.remove(drag);
    done.add(drag);
    if (done.length > 64) done.remove(done.first);
  }
}

/// The other players' live states as they arrive ([CoopLive]): who has which card picked, and their
/// drags to play back ([ghosts]). A drag ends when its move arrives ([onMove]), when it is
/// cancelled, or when nothing more is heard of it for [staleAfter] (the card goes back).
class LiveTracks {
  LiveTracks({this.staleAfter = const Duration(seconds: 2)});

  final Duration staleAfter;
  final _players = <String, _PlayerLive>{};

  /// Players whose live row this device has heard: their picks come from it, not from presence.
  Iterable<String> get heard => _players.keys;

  /// Card picked with a tap, by player.
  Map<String, int> get picks => {
        for (final e in _players.entries)
          if (e.value.current?.phase == LivePhase.pick) e.key: e.value.current!.card,
      };

  bool get hasGhosts => _players.values.any((p) => p.paths.isNotEmpty);

  /// Takes a state heard at [at]; true when what others hold changed (a pick, a drag that
  /// started or ended), false for a position or a state already superseded.
  bool add(CoopLive s, DateTime at) {
    final p = _players.putIfAbsent(s.userId, _PlayerLive.new);
    if (s.seq <= p.seq) return false;
    p.seq = s.seq;
    final before = p.current?.phase;
    p.current = s;
    switch (s.phase) {
      case LivePhase.drag:
        if (p.done.contains(s.drag)) return false;
        // A newer drag: an older one still moving was never heard to end.
        p.paths.removeWhere((d, path) => d != s.drag && !path.dropped);
        final path = p.paths.putIfAbsent(s.drag, () => DragPath(userId: s.userId, drag: s.drag, card: s.card));
        final fresh = path.samples == 0;
        path.add(s.t, s.x, s.y, at);
        return fresh || before != LivePhase.drag;
      case LivePhase.drop:
        if (p.done.contains(s.drag)) return true;
        final path = p.paths.putIfAbsent(s.drag, () => DragPath(userId: s.userId, drag: s.drag, card: s.card));
        path.add(s.t, s.x, s.y, at);
        path.droppedAt = at;
        return true;
      case LivePhase.cancel:
        p.finish(s.drag);
        return true;
      case LivePhase.pick:
      case LivePhase.none:
        // A drag still moving is over (its end was folded away); one that dropped waits for its move.
        p.paths.removeWhere((_, path) => !path.dropped);
        return true;
    }
  }

  /// [userId]'s move arrived and changed [cards]: their drags of those cards are over (the board
  /// takes the cards from where they are drawn to their slots). True when a drag ended.
  bool onMove(String userId, Iterable<int> cards) {
    final p = _players[userId];
    if (p == null || p.paths.isEmpty) return false;
    final set = cards.toSet();
    final over = [for (final e in p.paths.entries) if (set.contains(e.value.card)) e.key];
    for (final d in over) {
      p.finish(d);
    }
    return over.isNotEmpty;
  }

  /// [userId] left or is away: nothing of theirs is shown.
  void forget(String userId) => _players.remove(userId);

  void clear() => _players.clear();

  /// The drags to draw at [now] ([latest]: at their newest position, no glide). Drags not heard
  /// from for [staleAfter], and drops whose move did not come in that time, end here.
  List<LiveGhost> ghosts(DateTime now, {bool latest = false}) {
    final out = <LiveGhost>[];
    for (final p in _players.values) {
      for (final path in p.paths.values.toList()) {
        final since = now.difference(path.droppedAt ?? path.lastHeard);
        if (since > staleAfter) {
          p.finish(path.drag);
          continue;
        }
        final at = path.positionAt(now, latest: latest);
        out.add(LiveGhost(userId: path.userId, card: path.card, x: at.x, y: at.y));
      }
    }
    return out;
  }
}
