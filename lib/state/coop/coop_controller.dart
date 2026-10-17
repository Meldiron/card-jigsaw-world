import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics.dart';
import '../../data/coop_repository.dart';
import '../auth.dart';
import '../settings.dart';
import 'board_change.dart';
import 'coop_backend.dart';
import 'coop_log.dart';
import 'coop_models.dart';

/// Where this device stands in Play together.
enum CoopPhase {
  /// Not in a game.
  none,

  /// In a game, playing its current board.
  playing,

  /// The game ended (the host ended it or left, a day without play): the board stays on screen
  /// behind the alert, nothing more is shared.
  ended,

  /// The host removed this player.
  removed,
}

/// Cards other players are holding or just moved, by card number, with the player's id: the board
/// draws their colour and initial on them.
@immutable
class CoopMarks {
  const CoopMarks({this.held = const {}, this.moved = const {}});
  final Map<int, String> held;
  final Map<int, String> moved;

  bool get isEmpty => held.isEmpty && moved.isEmpty;

  /// The player marking [card]: who holds it, else who just moved it.
  String? on(int card) => held[card] ?? moved[card];
}

/// What the game screen and the co-op sheets read.
@immutable
class CoopState {
  const CoopState({
    this.phase = CoopPhase.none,
    this.game,
    this.me,
    this.layout = const [],
    this.presences = const {},
    this.marks = const CoopMarks(),
    this.placedACard = false,
    this.solved = false,
  });

  final CoopPhase phase;
  final CoopGame? game;
  final String? me;

  /// The board this device shows (`layout[slot]` is the card).
  final List<int> layout;

  /// Who is here, by user id (this game's presences; a player without one is away).
  final Map<String, CoopPresence> presences;
  final CoopMarks marks;

  /// This player locked at least one card with a move of their own on this board: a guest earns the
  /// board's rewards only then.
  final bool placedACard;

  /// Every device agrees the board is whole.
  final bool solved;

  bool get playing => phase == CoopPhase.playing && game != null;
  bool get isHost => game != null && me != null && game!.isHost(me!);

  /// A guest: the board is the host's, the guest's own quests, achievements and pack progress do
  /// not count it.
  bool get isGuest => playing && !isHost;

  /// Whether [userId] has the game open now (their app is in front and connected).
  bool isHere(String userId) {
    final p = presences[userId];
    return p != null && !p.away;
  }

  CoopState copyWith({
    CoopPhase? phase,
    CoopGame? game,
    List<int>? layout,
    Map<String, CoopPresence>? presences,
    CoopMarks? marks,
    bool? placedACard,
    bool? solved,
  }) =>
      CoopState(
        phase: phase ?? this.phase,
        game: game ?? this.game,
        me: me,
        layout: layout ?? this.layout,
        presences: presences ?? this.presences,
        marks: marks ?? this.marks,
        placedACard: placedACard ?? this.placedACard,
        solved: solved ?? this.solved,
      );
}

/// Something the players should hear about (a toast or an alert).
sealed class CoopNotice {
  const CoopNotice();
}

class CoopJoined extends CoopNotice {
  const CoopJoined(this.userId);
  final String userId;
}

class CoopLeft extends CoopNotice {
  const CoopLeft(this.userId);
  final String userId;
}

/// The host removed this player.
class CoopRemoved extends CoopNotice {
  const CoopRemoved(this.game);
  final CoopGame game;
}

/// The game ended for everyone (see [CoopGame.endReason]).
class CoopEnded extends CoopNotice {
  const CoopEnded(this.game);
  final CoopGame game;
}

/// The host opened the next board: guests move onto it ([CoopGame.route]).
class CoopNextBoard extends CoopNotice {
  const CoopNextBoard(this.game);
  final CoopGame game;
}

/// A change of the board shown, for the board to animate: the [LogUpdate] (before, after, other
/// players' changes, this device's changes that slid back).
@immutable
class CoopBoardUpdate {
  const CoopBoardUpdate(this.board, this.update);

  /// The game's board number.
  final int board;
  final LogUpdate update;
}

/// The timings, so tests can run them fast.
@immutable
class CoopTiming {
  const CoopTiming({
    this.presenceGap = const Duration(seconds: 3),
    this.keepAlive = const Duration(seconds: 60),
    this.safetyCatchUp = const Duration(minutes: 2),
    this.markFor = const Duration(milliseconds: 2500),
    this.retryFirst = const Duration(seconds: 1),
    this.retryMax = const Duration(seconds: 30),
  });

  /// At most one presence update per [presenceGap]: a socket may send about 32 messages a minute,
  /// and the SDK's heartbeat takes 3.
  final Duration presenceGap;

  /// The presence is sent again this often while nothing changes; its echo on this device's own
  /// socket proves the socket works. A missing echo means events may have been missed: once the
  /// echo is back, the moves are read again. Every presence costs a realtime message per player,
  /// hence a minute.
  final Duration keepAlive;

  /// Moves are read again this often anyway (realtime never replays what it lost).
  final Duration safetyCatchUp;

  /// How long another player's initial stays on cards they moved.
  final Duration markFor;
  final Duration retryFirst;
  final Duration retryMax;
}

final coopTimingProvider = Provider<CoopTiming>((ref) => const CoopTiming());

/// Play together on this device (docs/multiplayer.md): the game, its shared board ([CoopLog]),
/// sending this player's changes in order, realtime events, catching up after a gap, presence.
///
/// The game screen (phase 2) calls [submit] after every board change the player makes and applies
/// [updates] to its board; see `CoopBridge` (`coop_bridge.dart`) for the seam.
class CoopController extends Notifier<CoopState> {
  CoopBackend get _backend {
    final CoopBackend b = _active ?? ref.read<CoopBackend>(coopBackendProvider);
    _active = b;
    return b;
  }

  CoopTiming get _timing => ref.read(coopTimingProvider);

  /// The backend of the game in progress (kept, so stopping never reads a provider).
  CoopBackend? _active;

  CoopLog? _log;
  StreamSubscription<CoopEvent>? _sub;
  final _notices = StreamController<CoopNotice>.broadcast();
  final _updates = StreamController<CoopBoardUpdate>.broadcast();
  final _outbox = <CoopOp>[];
  bool _sending = false;
  bool _catching = false;
  bool _catchAgain = false;
  int _retries = 0;
  int _opCount = 0;
  Timer? _retryTimer;
  Timer? _presenceTimer;
  Timer? _keepAliveTimer;
  Timer? _safetyTimer;
  Timer? _markTimer;
  CoopPresence? _presence;
  DateTime _presenceSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastEcho;
  bool _echoMissed = false;
  final _moved = <int, ({String userId, DateTime until})>{};

  /// Join and leave toasts, removed and ended alerts, the next board.
  Stream<CoopNotice> get notices => _notices.stream;

  /// Every change of the board shown.
  Stream<CoopBoardUpdate> get updates => _updates.stream;

  /// The shared board, for tests and the bridge.
  CoopLog? get log => _log;

  @override
  CoopState build() {
    ref.onDispose(_stop);
    // Read, not watched: the player of a game in progress never changes under it.
    return CoopState(me: ref.read(currentUserIdProvider));
  }

  String? get _me => state.me ?? ref.read(currentUserIdProvider);

  // ---- the game ------------------------------------------------------------------------------

  /// Starts a game on the board the host is playing: [layout] is that board as it is now, and stays
  /// the host's board. Throws [CoopRefusal].
  Future<CoopGame> create({required String puzzleId, required String grid, required List<int> layout, bool painting = false}) async {
    final game = (await _backend.call('create', {'puzzleId': puzzleId, 'grid': grid, 'layout': layout, 'painting': painting}))!;
    await _start(game);
    return game;
  }

  /// Joins the game of the link's [code]. Throws [CoopRefusal] (full, removed, ended, blocked,
  /// offline).
  Future<CoopGame> join(String code) async {
    final game = (await _backend.call('join', {'code': code}))!;
    await _start(game);
    return game;
  }

  /// A guest leaves (their seat frees up); the host leaving ends the game for everyone.
  Future<void> leave() async {
    final g = state.game;
    if (g != null) AppAnalytics.event('coop_game_left', {'role': state.isHost ? 'host' : 'guest', 'players': g.playerIds.length});
    _remember(null);
    _stop();
    state = CoopState(me: _me);
    if (g == null) return;
    try {
      await _backend.call('leave', {'gameId': g.id});
    } on CoopRefusal catch (e) {
      // Offline: the seat stays until the game goes idle; the player is out of it here.
      debugPrint('coop leave: $e');
    }
  }

  bool _endingHere = false;

  /// The host ends the game for everyone.
  Future<void> endForEveryone() async {
    final g = state.game;
    if (g == null) return;
    // The ended row often arrives over realtime before the function answers: this player ended it,
    // so no "Game ended" alert here.
    _endingHere = true;
    try {
      await _backend.call('end', {'gameId': g.id});
    } finally {
      _endingHere = false;
    }
    AppAnalytics.event('coop_game_ended', {'by': 'host', 'players': g.playerIds.length, 'board': g.board});
    _remember(null);
    _stop();
    state = CoopState(me: _me);
  }

  /// The host removes [userId]; they cannot come back to this game.
  Future<void> remove(String userId) async {
    final g = state.game;
    if (g == null) return;
    final updated = await _backend.call('remove', {'gameId': g.id, 'userId': userId});
    AppAnalytics.event('coop_player_removed', {'players': updated?.playerIds.length});
    if (updated != null) _onGame(updated);
  }

  /// The host opens the next board for everyone: [layout] as dealt on this device.
  Future<CoopGame> nextBoard({required String puzzleId, required String grid, required List<int> layout, bool painting = false}) async {
    final g = state.game;
    if (g == null) throw const CoopRefusal(CoopRefusalReason.ended);
    final updated = (await _backend.call('next', {'gameId': g.id, 'puzzleId': puzzleId, 'grid': grid, 'layout': layout, 'painting': painting}))!;
    AppAnalytics.event('coop_next_board', {'board': updated.board, 'cards': layout.length, 'players': updated.playerIds.length});
    _onGame(updated);
    return updated;
  }

  /// Back to no game on this device (after the removed or ended alert). [forget] false keeps the
  /// game remembered for Return to game (what an app that was closed finds on its next start).
  void clear({bool forget = true}) {
    if (forget) _remember(null);
    _stop();
    state = CoopState(me: _me);
  }

  Future<void> _start(CoopGame game) async {
    _stop();
    final me = _me;
    if (me == null) throw const CoopRefusal(CoopRefusalReason.auth);
    _newBoard(game);
    _remember(game);
    state = CoopState(phase: CoopPhase.playing, game: game, me: me, layout: game.layout);
    _sub = _backend.listen(game.id).listen(_onEvent);
    _presence = CoopPresence(userId: me, gameId: game.id, board: game.board);
    _sendPresence();
    _keepAliveTimer = Timer.periodic(_timing.keepAlive, (_) => _keepAlive());
    _safetyTimer = Timer.periodic(_timing.safetyCatchUp, (_) => catchUp());
    await Future.wait([catchUp(), _loadPresences()]);
  }

  void _newBoard(CoopGame game) {
    _outbox.removeWhere((op) => op.board != game.board);
    _moved.clear();
    _log = CoopLog(gameId: game.id, board: game.board, base: game.layout, me: _me ?? '');
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    final backend = _active;
    if (backend != null) unawaited(backend.close());
    _log = null;
    _outbox.clear();
    _retries = 0;
    for (final t in [_retryTimer, _presenceTimer, _keepAliveTimer, _safetyTimer, _markTimer]) {
      t?.cancel();
    }
    _retryTimer = _presenceTimer = _keepAliveTimer = _safetyTimer = _markTimer = null;
    _presence = null;
    _lastEcho = null;
    _echoMissed = false;
    _moved.clear();
  }

  // ---- Return to game ------------------------------------------------------------------------

  /// Where the game this device is in is remembered, so a player who closed the app can go back to
  /// it (docs/multiplayer.md, "Return to game").
  static const memoryKey = 'coop.active';

  void _remember(CoopGame? game) {
    try {
      final store = ref.read(localStoreProvider);
      if (game == null) {
        unawaited(store.remove(memoryKey));
      } else {
        unawaited(store.setJson(memoryKey, {'id': game.id, 'code': game.code}));
      }
    } catch (_) {
      // No store (tests without one): nothing to remember.
    }
  }

  /// The remembered game when it is still on and this player still has a seat in it; null
  /// otherwise (and then it is forgotten). Without a connection it stays remembered for later.
  Future<CoopGame?> rememberedGame() async {
    if (state.playing) return null;
    Map<String, dynamic>? m;
    try {
      m = ref.read(localStoreProvider).getJson(memoryKey);
    } catch (_) {
      return null;
    }
    final id = m?['id'];
    if (id is! String) return null;
    try {
      final g = await _backend.readGame(id);
      final me = _me;
      if (g == null || g.ended || me == null || !g.players.contains(me)) {
        _remember(null);
        return null;
      }
      return g;
    } catch (e) {
      debugPrint('coop remembered game: $e');
      return null;
    }
  }

  /// Back into [game] (Return to game): the seat is still this player's, so no join is needed.
  Future<void> rejoin(CoopGame game) => _start(game);

  // ---- this player's changes -----------------------------------------------------------------

  /// Shares a change the player made on this device: [before] and [after] are the board before and
  /// after it. Returns what it did to the board shown (it shows at once), or null when there is no
  /// game or it does not fit the shared board (the board changed under it: nothing is sent).
  LogUpdate? submit(CoopOpKind kind, List<int> before, List<int> after) {
    final log = _log;
    final g = state.game;
    final me = _me;
    if (log == null || g == null || me == null || !state.playing) return null;
    final op = CoopOp(id: _newOpId(me), gameId: g.id, board: log.board, userId: me, kind: kind, change: BoardChange.between(before, after));
    final update = log.addLocal(op);
    if (update == null) return null;
    _outbox.add(op);
    _emit(update);
    unawaited(_pump());
    return update;
  }

  /// A move's row id, made here so a retry after a lost answer cannot add it twice: the player, the
  /// time and a counter, hashed to 20 characters.
  String _newOpId(String me) => md5.convert(utf8.encode('$me:${DateTime.now().microsecondsSinceEpoch}:${_opCount++}')).toString().substring(0, 20);

  /// Sends the waiting changes one after another, in the order they were made (a change builds on
  /// the one before it, so the server must take them in that order).
  Future<void> _pump() async {
    if (_sending) return;
    _sending = true;
    try {
      while (_outbox.isNotEmpty) {
        final op = _outbox.first;
        final Map<String, dynamic> row;
        try {
          row = await _backend.createMove(op);
        } on CoopRefusal {
          // No longer in the game: nothing more can be shared, and the game row says why.
          final log = _log;
          for (final o in List.of(_outbox)) {
            if (log != null && log.board == o.board) _emit(log.reject(o.id));
          }
          _outbox.clear();
          unawaited(_refreshGame());
          return;
        } catch (e) {
          debugPrint('coop send: $e');
          _retryLater();
          return;
        }
        _retries = 0;
        if (_outbox.isNotEmpty && _outbox.first.id == op.id) _outbox.removeAt(0);
        final seq = int.tryParse('${row[r'$sequence']}');
        final log = _log;
        if (seq != null && log != null && log.board == op.board) _emit(log.confirm(op.id, seq));
      }
    } finally {
      _sending = false;
    }
  }

  void _retryLater() {
    _retryTimer?.cancel();
    final wait = _timing.retryFirst * (1 << _retries.clamp(0, 5));
    _retries++;
    _retryTimer = Timer(wait > _timing.retryMax ? _timing.retryMax : wait, () => unawaited(_pump()));
  }

  /// The card this player holds (picked up, not yet placed), or null: the others see their colour on
  /// it. Sent at most once per [CoopTiming.presenceGap].
  void hold(int? card) {
    final p = _presence;
    if (p == null || p.held == card) return;
    _presence = CoopPresence(userId: p.userId, gameId: p.gameId, board: p.board, held: card, away: p.away);
    _sendPresence();
  }

  // ---- what comes from the server ------------------------------------------------------------

  void _onEvent(CoopEvent e) {
    switch (e) {
      case CoopMoveEvent(:final row):
        final log = _log;
        if (log == null) return;
        final op = CoopOp.fromRow(row, cells: log.base.length);
        if (op != null) _emit(log.addRemote(op));
      case CoopGameEvent(:final row, :final deleted):
        if (deleted) {
          _gone();
        } else {
          _onGame(CoopGame.fromMap(row));
        }
      case CoopPresenceEvent(:final presence, :final deleted):
        _onPresence(presence, deleted: deleted);
      case CoopConnectionEvent():
        _echoMissed = true;
    }
  }

  void _onGame(CoopGame g) {
    final old = state.game;
    final me = _me;
    if (old == null || g.id != old.id || me == null || state.phase != CoopPhase.playing) return;
    if (g.removed.contains(me)) {
      _remember(null);
      _stop();
      state = state.copyWith(phase: CoopPhase.removed, game: g);
      _notices.add(CoopRemoved(g));
      return;
    }
    if (g.ended) {
      _remember(null);
      _stop();
      if (_endingHere) {
        state = CoopState(me: _me);
        return;
      }
      state = state.copyWith(phase: CoopPhase.ended, game: g);
      _notices.add(CoopEnded(g));
      return;
    }
    final joined = [for (final p in g.playerIds) if (!old.players.contains(p) && p != me) p];
    final left = [for (final p in old.playerIds) if (!g.players.contains(p) && p != me) p];
    if (g.board != old.board) {
      if (g.board < old.board) return; // an older row arriving late
      _newBoard(g);
      final p = _presence;
      if (p != null) {
        _presence = CoopPresence(userId: p.userId, gameId: p.gameId, board: g.board, away: p.away);
        _sendPresence();
      }
      state = state.copyWith(game: g, layout: g.layout, marks: const CoopMarks(), placedACard: false, solved: false);
      _notices.add(CoopNextBoard(g));
      unawaited(catchUp());
    } else {
      state = state.copyWith(game: g, presences: {for (final e in state.presences.entries) if (g.players.contains(e.key)) e.key: e.value});
    }
    for (final p in joined) {
      _notices.add(CoopJoined(p));
    }
    for (final p in left) {
      _notices.add(CoopLeft(p));
    }
  }

  /// The game row cannot be read any more while this device was in it: deleted (ended an hour ago)
  /// or this player is out of the team.
  void _gone() {
    final g = state.game;
    if (g == null || state.phase != CoopPhase.playing) return;
    _remember(null);
    _stop();
    final ended = g.copyWith(ended: true, endReason: g.endReason ?? 'ended');
    state = state.copyWith(phase: CoopPhase.ended, game: ended);
    _notices.add(CoopEnded(ended));
  }

  Future<void> _refreshGame() async {
    final g = state.game;
    if (g == null) return;
    try {
      final fresh = await _backend.readGame(g.id);
      if (state.game?.id != g.id) return;
      if (fresh == null) {
        _gone();
      } else {
        _onGame(fresh);
      }
    } catch (e) {
      debugPrint('coop game read: $e');
    }
  }

  void _onPresence(Map<String, dynamic> map, {required bool deleted}) {
    final g = state.game;
    final p = CoopPresence.fromMap(map);
    if (g == null || p == null || p.gameId != g.id) return;
    if (p.userId == _me) {
      if (deleted) return;
      // This device's own presence came back over its socket: the socket works. Events may have
      // been missed while it did not. An echo nobody asked for is the SDK sending the presence again
      // after it reconnected: events were missed in between.
      final unasked = DateTime.now().difference(_presenceSentAt) > _timing.presenceGap * 3;
      if (_echoMissed || unasked) {
        _echoMissed = false;
        unawaited(catchUp());
      }
      _lastEcho = DateTime.now();
      return;
    }
    if (!g.players.contains(p.userId)) return;
    final presences = Map.of(state.presences);
    if (deleted) {
      presences.remove(p.userId);
    } else {
      presences[p.userId] = p;
    }
    state = state.copyWith(presences: presences, marks: _marks(state.layout, presences));
  }

  Future<void> _loadPresences() async {
    final g = state.game;
    final me = _me;
    if (g == null) return;
    try {
      final list = await _backend.presences([for (final p in g.playerIds) if (p != me) p]);
      if (state.game?.id != g.id) return;
      final presences = Map.of(state.presences);
      for (final m in list) {
        final p = CoopPresence.fromMap(m);
        if (p != null && p.gameId == g.id) presences[p.userId] = p;
      }
      state = state.copyWith(presences: presences, marks: _marks(state.layout, presences));
    } catch (e) {
      debugPrint('coop presences: $e');
    }
  }

  /// Reads the moves this device may have missed (on start, after a gap, on resume) and the game
  /// row. What comes twice is kept once.
  Future<void> catchUp() async {
    final log = _log;
    if (log == null) return;
    if (_catching) {
      _catchAgain = true;
      return;
    }
    _catching = true;
    try {
      final rows = await _backend.movesAfter(log.gameId, log.board, log.catchUpFrom());
      if (_log != log) return;
      final updates = <LogUpdate>[];
      for (final row in rows) {
        final op = CoopOp.fromRow(row, cells: log.base.length);
        if (op != null) updates.add(log.addRemote(op));
      }
      if (updates.isNotEmpty) {
        _emit(LogUpdate(
          before: updates.first.before,
          after: updates.last.after,
          applied: [for (final u in updates) ...u.applied],
          dropped: [for (final u in updates) ...u.dropped],
        ));
      }
    } catch (e) {
      debugPrint('coop catch-up: $e');
      _echoMissed = true;
    } finally {
      _catching = false;
    }
    await _refreshGame();
    if (_catchAgain) {
      _catchAgain = false;
      await catchUp();
    }
  }

  // ---- the board shown -----------------------------------------------------------------------

  void _emit(LogUpdate u) {
    final log = _log;
    if (log == null) return;
    final now = DateTime.now();
    for (final op in u.applied) {
      for (final c in op.change.slots) {
        _moved[c.after] = (userId: op.userId, until: now.add(_timing.markFor));
      }
    }
    if (u.applied.isNotEmpty) _scheduleMarks();
    final me = _me ?? '';
    state = state.copyWith(
      layout: log.layout,
      marks: _marks(log.layout, state.presences),
      placedACard: log.locksBy(me) > 0,
      solved: log.isSolved,
    );
    if (u.changed || u.dropped.isNotEmpty || u.applied.isNotEmpty) _updates.add(CoopBoardUpdate(log.board, u));
  }

  CoopMarks _marks(List<int> layout, Map<String, CoopPresence> presences) {
    final now = DateTime.now();
    _moved.removeWhere((_, m) => !m.until.isAfter(now));
    final board = _log?.board;
    return CoopMarks(
      held: {
        for (final p in presences.values)
          if (!p.away && p.held != null && p.board == board) p.held!: p.userId,
      },
      moved: {for (final e in _moved.entries) e.key: e.value.userId},
    );
  }

  void _scheduleMarks() {
    _markTimer?.cancel();
    if (_moved.isEmpty) return;
    final next = _moved.values.map((m) => m.until).reduce((a, b) => a.isBefore(b) ? a : b);
    var wait = next.difference(DateTime.now());
    if (wait.isNegative) wait = Duration.zero;
    _markTimer = Timer(wait + const Duration(milliseconds: 10), () {
      if (_log == null) return;
      state = state.copyWith(marks: _marks(state.layout, state.presences));
      _scheduleMarks();
    });
  }

  // ---- presence and the app's life -----------------------------------------------------------

  /// The presence's id: one per player and game.
  static String presenceId(String gameId, String userId) => md5.convert(utf8.encode('coop:$gameId:$userId')).toString();

  void _sendPresence({bool now = false}) {
    final p = _presence;
    if (p == null) return;
    final since = DateTime.now().difference(_presenceSentAt);
    if (!now && since < _timing.presenceGap) {
      _presenceTimer ??= Timer(_timing.presenceGap - since, () {
        _presenceTimer = null;
        _sendPresence();
      });
      return;
    }
    _presenceTimer?.cancel();
    _presenceTimer = null;
    _presenceSentAt = DateTime.now();
    _backend.setPresence(presenceId(p.gameId, p.userId), p);
  }

  void _keepAlive() {
    if (_presence == null) return;
    final echo = _lastEcho;
    if (echo == null || DateTime.now().difference(echo) > _timing.keepAlive * 2) _echoMissed = true;
    if (DateTime.now().difference(_presenceSentAt) >= _timing.keepAlive - const Duration(seconds: 1)) _sendPresence(now: true);
  }

  /// The app came back to the front: here again, and whatever was missed is read.
  void onResume() {
    final p = _presence;
    if (p == null) return;
    if (p.away) _presence = CoopPresence(userId: p.userId, gameId: p.gameId, board: p.board, held: p.held, away: false);
    _sendPresence(now: true);
    unawaited(catchUp());
    unawaited(_loadPresences());
  }

  /// The app went to the background: the seat stays, the others see this player away.
  void onPause() {
    final p = _presence;
    if (p == null || p.away) return;
    _presence = CoopPresence(userId: p.userId, gameId: p.gameId, board: p.board, away: true);
    _sendPresence(now: true);
  }
}

final coopProvider = NotifierProvider<CoopController, CoopState>(CoopController.new);
