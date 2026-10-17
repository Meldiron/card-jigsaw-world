// Play together without the network: a server in memory that keeps games, teams, move rows (with
// a table-wide `$sequence`, as Appwrite) and presences, and "devices" that talk to it. Realtime
// delivery can be held and released in any order, and a device can lose its connection.
import 'dart:async';
import 'dart:math';

import 'package:carden/state/coop/coop_backend.dart';
import 'package:carden/state/coop/coop_models.dart';

/// The join codes' alphabet (function coop-game).
const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

class FakeCoopServer {
  /// The moves table's `$sequence`, shared with every other game (it starts high and skips, as
  /// rows of other games take numbers too).
  int _seq = 5000;
  int _ids = 0;
  final games = <String, Map<String, dynamic>>{};
  final teams = <String, List<String>>{};
  final moves = <Map<String, dynamic>>[];
  final presences = <String, Map<String, dynamic>>{};
  final devices = <FakeCoopBackend>[];

  /// Realtime events wait here while [hold] is on, until [release].
  bool hold = false;
  final _held = <(FakeCoopBackend, CoopEvent)>[];

  /// Games the server knows by code.
  String? gameOfCode(String code) => games.entries.where((e) => e.value['code'] == code).firstOrNull?.key;

  void _broadcast(String gameId, CoopEvent e) {
    final members = teams[gameId] ?? const [];
    for (final d in devices) {
      if (!d.listening || d.listeningTo != gameId || !d.connected || !members.contains(d.userId)) continue;
      if (hold) {
        _held.add((d, e));
      } else {
        d._deliver(e);
      }
    }
  }

  /// Delivers the held events, shuffled by [random] when given (realtime keeps no order).
  void release({Random? random}) {
    final list = List.of(_held);
    _held.clear();
    if (random != null) list.shuffle(random);
    for (final (d, e) in list) {
      if (d.connected && d.listening) d._deliver(e);
    }
  }

  Map<String, dynamic> _row(String id) => {r'$id': id, ...games[id]!};

  Map<String, dynamic> handle(String userId, String action, Map<String, dynamic> body) {
    switch (action) {
      case 'create':
        for (final g in games.entries.where((g) => g.value['status'] == 'playing' && (g.value['players'] as List).contains(userId)).toList()) {
          handle(userId, 'leave', {'gameId': g.key});
        }
        final id = 'game${++_ids}';
        games[id] = {
          'code': 'GAME${[for (var i = 0; i < 4; i++) _alphabet[(_ids ~/ pow(31, i)) % 31]].join()}',
          'hostId': userId,
          'players': [userId, '', '', '', ''],
          'removed': <String>[],
          'status': 'playing',
          'board': 1,
          'puzzleId': body['puzzleId'],
          'grid': body['grid'],
          'painting': body['painting'] == true,
          'layout': (body['layout'] as List).join(','),
        };
        teams[id] = [userId];
        return _row(id);
      case 'join':
        final id = gameOfCode(body['code'] as String);
        if (id == null) throw const CoopRefusal(CoopRefusalReason.ended);
        final g = games[id]!;
        if (g['status'] != 'playing') throw const CoopRefusal(CoopRefusalReason.ended);
        if ((g['removed'] as List).contains(userId)) throw const CoopRefusal(CoopRefusalReason.removed);
        final players = List<String>.from(g['players'] as List);
        if (players.contains(userId)) return _row(id);
        final seat = players.indexOf('');
        if (seat < 0) throw const CoopRefusal(CoopRefusalReason.full);
        players[seat] = userId;
        teams[id]!.add(userId);
        _update(id, {'players': players});
        return _row(id);
      case 'leave':
        final id = body['gameId'] as String;
        final g = games[id];
        if (g == null) return const {};
        if (g['hostId'] == userId) {
          _update(id, {'status': 'ended', 'endReason': 'host-left'});
        } else {
          _update(id, {'players': [for (final p in g['players'] as List) p == userId ? '' : p]});
          teams[id]!.remove(userId);
        }
        return const {};
      case 'remove':
        final id = body['gameId'] as String;
        final g = games[id]!;
        if (g['hostId'] != userId) throw const CoopRefusal(CoopRefusalReason.host);
        final target = body['userId'] as String;
        _update(id, {
          'players': [for (final p in g['players'] as List) p == target ? '' : p],
          'removed': [...g['removed'] as List, target],
        });
        teams[id]!.remove(target);
        return _row(id);
      case 'end':
        final id = body['gameId'] as String;
        if (games[id]!['hostId'] != userId) throw const CoopRefusal(CoopRefusalReason.host);
        _update(id, {'status': 'ended', 'endReason': 'host'});
        return _row(id);
      case 'next':
        final id = body['gameId'] as String;
        final g = games[id]!;
        if (g['hostId'] != userId) throw const CoopRefusal(CoopRefusalReason.host);
        _update(id, {'board': (g['board'] as int) + 1, 'puzzleId': body['puzzleId'], 'grid': body['grid'], 'layout': (body['layout'] as List).join(',')});
        return _row(id);
    }
    throw StateError('unknown action $action');
  }

  /// A game row change, heard by its team (a removed player hears the change that removes them).
  void _update(String id, Map<String, dynamic> data) {
    games[id] = {...games[id]!, ...data};
    _broadcast(id, CoopGameEvent(_row(id)));
  }

  /// Rows of other games take sequence numbers too.
  void otherGamesWrite(int rows) => _seq += rows;
}

/// One device: a player's connection to the [FakeCoopServer].
class FakeCoopBackend implements CoopBackend {
  FakeCoopBackend(this.server, this.userId) {
    server.devices.add(this);
  }

  final FakeCoopServer server;
  final String userId;

  /// Off: requests fail as without a network, and realtime events are lost (not queued).
  bool connected = true;

  /// The next create reaches the server but its answer is lost (the device sees an error).
  bool loseNextAnswer = false;

  StreamController<CoopEvent>? _events;
  String? listeningTo;
  bool get listening => _events != null && !_events!.isClosed;
  int creates = 0;

  /// How long the function's answers take after the server acted (its realtime events go first).
  Duration answerAfter = Duration.zero;

  void _deliver(CoopEvent e) => _events?.add(e);

  void _online() {
    if (!connected) throw Exception('offline');
  }

  @override
  Future<CoopGame?> call(String action, Map<String, dynamic> body) async {
    await Future<void>.delayed(Duration.zero);
    if (!connected) throw const CoopRefusal(CoopRefusalReason.offline);
    final out = server.handle(userId, action, body);
    // The function's answer can come after its realtime events.
    if (answerAfter > Duration.zero) await Future<void>.delayed(answerAfter);
    return out.isEmpty ? null : CoopGame.fromMap(out);
  }

  @override
  Future<CoopGame?> readGame(String gameId) async {
    _online();
    if (!(server.teams[gameId] ?? const []).contains(userId) || server.games[gameId] == null) return null;
    return CoopGame.fromMap(server._row(gameId));
  }

  @override
  Future<Map<String, dynamic>> createMove(CoopOp op) async {
    await Future<void>.delayed(Duration.zero);
    _online();
    creates++;
    if (!(server.teams[op.gameId] ?? const []).contains(userId) || op.userId != userId) throw const CoopRefusal(CoopRefusalReason.removed);
    final existing = server.moves.where((m) => m[r'$id'] == op.id).firstOrNull;
    if (existing != null) return existing;
    final row = <String, dynamic>{
      r'$id': op.id,
      r'$sequence': '${++server._seq}',
      r'$permissions': CoopOp.permissionsFor(op.gameId, op.userId),
      ...op.toData(),
    };
    server.moves.add(row);
    server._broadcast(op.gameId, CoopMoveEvent(row));
    if (loseNextAnswer) {
      loseNextAnswer = false;
      throw Exception('answer lost');
    }
    return row;
  }

  @override
  Future<List<Map<String, dynamic>>> movesAfter(String gameId, int board, int afterSeq) async {
    _online();
    if (!(server.teams[gameId] ?? const []).contains(userId)) return const [];
    return [
      for (final m in server.moves)
        if (m['gameId'] == gameId && m['board'] == board && int.parse(m[r'$sequence'] as String) > afterSeq) m,
    ]..sort((a, b) => int.parse(a[r'$sequence'] as String).compareTo(int.parse(b[r'$sequence'] as String)));
  }

  @override
  Stream<CoopEvent> listen(String gameId) {
    _events?.close();
    final c = _events = StreamController<CoopEvent>.broadcast();
    listeningTo = gameId;
    return c.stream;
  }

  @override
  void setPresence(String presenceId, CoopPresence presence) {
    if (!connected) return;
    final m = {r'$id': presenceId, 'userId': userId, 'status': presence.away ? 'away' : 'online', 'metadata': presence.metadata};
    _lastPresence = m;
    server.presences[presenceId] = m;
    server._broadcast(presence.gameId, CoopPresenceEvent(m));
  }

  @override
  Future<List<Map<String, dynamic>>> presences(List<String> userIds) async {
    _online();
    return [for (final p in server.presences.values) if (userIds.contains(p['userId'])) p];
  }

  /// The connection is back: the SDK subscribes again and sends this device's presence again (its
  /// echo is how the controller notices a reconnect).
  void reconnect() {
    connected = true;
    final mine = server.presences.values.where((p) => p['userId'] == userId).lastOrNull ?? _lastPresence;
    if (mine == null) return;
    server.presences['${mine[r'$id']}'] = mine;
    server._broadcast((mine['metadata'] as Map)['g'] as String, CoopPresenceEvent(mine));
  }

  Map<String, dynamic>? _lastPresence;

  /// The socket closes: the presence goes, and the others hear it.
  void dropSocket() {
    connected = false;
    for (final e in server.presences.entries.where((e) => e.value['userId'] == userId).toList()) {
      server.presences.remove(e.key);
      final g = (e.value['metadata'] as Map)['g'] as String;
      server._broadcast(g, CoopPresenceEvent(e.value, deleted: true));
    }
  }

  @override
  Future<void> close() async {
    // Let go at once: a listen right after a close keeps its new stream.
    final events = _events;
    _events = null;
    listeningTo = null;
    await events?.close();
  }
}
