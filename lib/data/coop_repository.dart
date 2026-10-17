import 'dart:async';
import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as enums;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/appwrite.dart';
import '../state/coop/coop_backend.dart';
import '../state/coop/coop_live.dart';
import '../state/coop/coop_models.dart';
import 'repositories.dart';

/// Play together on Appwrite (docs/multiplayer.md): `/coop/<action>` on the `api` function for the game itself,
/// rows of `coop_moves` for the moves, Realtime for what other players do and Presences for who is
/// here. One realtime socket per game (the SDK's `Realtime`), closed when the player leaves it.
class AppwriteCoopBackend implements CoopBackend {
  AppwriteCoopBackend(this._client)
      : _tables = TablesDB(_client),
        _functions = Functions(_client),
        _presences = Presences(_client);

  final Client _client;
  final TablesDB _tables;
  final Functions _functions;
  final Presences _presences;
  Realtime? _realtime;
  final _subscriptions = <RealtimeSubscription>[];
  StreamController<CoopEvent>? _events;

  static const functionId = AppwriteConfig.apiFunction;
  static const games = 'coop_games';
  static const moves = 'coop_moves';
  static const live = 'coop_drags';

  @override
  Future<CoopGame?> call(String action, Map<String, dynamic> body) async {
    final Map<String, dynamic> out;
    try {
      final exec = await _functions.createExecution(functionId: functionId, body: jsonEncode(body), method: enums.ExecutionMethod.pOST, path: '/coop/$action');
      out = exec.responseBody.isEmpty ? <String, dynamic>{} : jsonDecode(exec.responseBody) as Map<String, dynamic>;
    } on AppwriteException catch (e) {
      throw CoopRefusal(e.code == 401 ? CoopRefusalReason.auth : CoopRefusalReason.server, e.message ?? '');
    } catch (e) {
      throw CoopRefusal(CoopRefusalReason.offline, '$e');
    }
    if (out['ok'] != true) throw CoopRefusal.fromReason(out['reason'] as String?, out['error'] as String?);
    final game = out['game'];
    return game is Map<String, dynamic> ? CoopGame.fromMap(game) : null;
  }

  @override
  Future<CoopGame?> readGame(String gameId) async {
    try {
      final row = await _tables.getRow(databaseId: AppwriteConfig.databaseId, tableId: games, rowId: gameId);
      return CoopGame.fromMap(row.data);
    } on AppwriteException catch (e) {
      // Gone, or no longer the player's to read (removed, left).
      if (e.code == 404 || e.code == 401) return null;
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> createMove(CoopOp op) async {
    try {
      final row = await _tables.createRow(
        databaseId: AppwriteConfig.databaseId,
        tableId: moves,
        rowId: op.id,
        data: op.toData(),
        permissions: CoopOp.permissionsFor(op.gameId, op.userId),
      );
      return row.data;
    } on AppwriteException catch (e) {
      // Already there: an earlier try reached the server and lost its answer.
      if (e.code == 409) return (await _tables.getRow(databaseId: AppwriteConfig.databaseId, tableId: moves, rowId: op.id)).data;
      // Not in the game's team any more: it may not grant read(team).
      if (e.code == 401 || e.code == 403) throw CoopRefusal(CoopRefusalReason.removed, e.message ?? '');
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> movesAfter(String gameId, int board, int afterSeq) async {
    final rows = await listAllRows(_tables, moves, [
      Query.equal('gameId', [gameId]),
      Query.equal('board', [board]),
      // Appwrite refuses a `$sequence` below 1 in a query (400, checked live): from the start, no filter.
      if (afterSeq > 0) Query.greaterThan(r'$sequence', afterSeq),
      Query.orderAsc(r'$sequence'),
    ]);
    return [for (final r in rows) r.data];
  }

  @override
  Future<void> updateLive(String gameId, CoopLive state) async {
    try {
      await _tables.updateRow(databaseId: AppwriteConfig.databaseId, tableId: live, rowId: CoopLive.rowId(gameId, state.userId), data: state.toData());
    } on AppwriteException catch (e) {
      if (e.code == 429) throw const LiveRateLimited();
      if (e.code == 404 || e.code == 401 || e.code == 403) throw const LiveRowMissing();
      rethrow;
    }
  }

  @override
  Stream<CoopEvent> listen(String gameId, {String? me}) {
    unawaited(close());
    final controller = StreamController<CoopEvent>.broadcast();
    _events = controller;
    final realtime = _realtime = Realtime(_client);
    void forward(RealtimeSubscription sub, CoopEvent? Function(RealtimeMessage m) read) {
      _subscriptions.add(sub);
      sub.stream.listen(
        (m) {
          final e = read(m);
          if (e != null && !controller.isClosed) controller.add(e);
        },
        onError: (Object e) {
          debugPrint('coop realtime: $e');
          if (!controller.isClosed) controller.add(const CoopConnectionEvent());
        },
      );
    }

    bool deleted(RealtimeMessage m) => m.events.any((e) => e.endsWith('.delete'));
    // Moves: filtered on the server to this game, so the socket carries only its own game's rows.
    forward(
      realtime.subscribe(['tablesdb.${AppwriteConfig.databaseId}.tables.$moves.rows'], queries: [Query.equal('gameId', [gameId])]),
      (m) => m.events.any((e) => e.endsWith('.create')) ? CoopMoveEvent(m.payload) : null,
    );
    forward(realtime.subscribe(['tablesdb.${AppwriteConfig.databaseId}.tables.$games.rows.$gameId']), (m) => CoopGameEvent(m.payload, deleted: deleted(m)));
    // The others' live rows (picks and drags): this game's, without this player's own echo.
    forward(
      realtime.subscribe(['tablesdb.${AppwriteConfig.databaseId}.tables.$live.rows'], queries: [
        Query.equal('gameId', [gameId]),
        if (me != null) Query.notEqual('userId', [me]),
      ]),
      (m) => m.events.any((e) => e.endsWith('.update') || e.endsWith('.create')) ? CoopLiveEvent(m.payload) : null,
    );
    // Presences on their own subscription: a query on a subscription applies to every channel in it.
    forward(realtime.subscribe(['presences']), (m) => CoopPresenceEvent(m.payload, deleted: deleted(m)));
    return controller.stream;
  }

  @override
  void setPresence(String presenceId, CoopPresence presence) {
    try {
      _realtime?.upsertPresence(
        status: presence.away ? 'away' : 'online',
        presenceId: presenceId,
        permissions: ['read("team:${presence.gameId}")'],
        metadata: presence.metadata,
      );
    } catch (e) {
      // No socket yet: the next call sends it.
      debugPrint('coop presence: $e');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> presences(List<String> userIds) async {
    if (userIds.isEmpty) return const [];
    final list = await listAllPresences(_presences, [Query.equal('userId', userIds)]);
    return [for (final p in list) p.toMap()];
  }

  @override
  Future<void> close() async {
    final subs = List.of(_subscriptions);
    _subscriptions.clear();
    final realtime = _realtime;
    _realtime = null;
    final events = _events;
    _events = null;
    for (final s in subs) {
      try {
        await s.unsubscribe();
      } catch (_) {}
    }
    try {
      await realtime?.disconnect();
    } catch (_) {}
    await events?.close();
  }
}

final coopBackendProvider = Provider<CoopBackend>((ref) {
  final backend = AppwriteCoopBackend(ref.watch(appwriteClientProvider));
  ref.onDispose(backend.close);
  return backend;
});
