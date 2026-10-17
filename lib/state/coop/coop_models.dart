import 'package:flutter/foundation.dart';

import '../../core/app_links.dart';
import 'board_change.dart';

/// Most players in one game, the host included (function coop-game, `MAX_PLAYERS`).
const coopMaxPlayers = 5;

/// A game of Play together (docs/multiplayer.md): a row of `coop_games`, readable by its players.
@immutable
class CoopGame {
  const CoopGame({
    required this.id,
    required this.code,
    required this.hostId,
    required this.players,
    required this.removed,
    required this.ended,
    required this.board,
    required this.puzzleId,
    required this.grid,
    required this.painting,
    required this.layout,
    this.endReason,
  });

  /// Reads the function's answer (`id`, layout as text) or the row itself (`$id`, from a read or a
  /// realtime event).
  factory CoopGame.fromMap(Map<String, dynamic> m) {
    List<String> strings(Object? v) => v is List ? [for (final x in v) '${x ?? ''}'] : const [];
    return CoopGame(
      id: '${m['id'] ?? m[r'$id']}',
      code: '${m['code'] ?? ''}',
      hostId: '${m['hostId'] ?? ''}',
      players: strings(m['players']),
      removed: strings(m['removed']),
      ended: m['status'] == 'ended',
      board: (m['board'] as num?)?.toInt() ?? 1,
      puzzleId: '${m['puzzleId'] ?? ''}',
      grid: '${m['grid'] ?? ''}',
      painting: m['painting'] == true,
      layout: parseLayout(m['layout']),
      endReason: m['endReason'] as String?,
    );
  }

  final String id;

  /// The join code in the link (`https://play.carden.page/join/<code>`).
  final String code;
  final String hostId;

  /// The user id in each seat ('' for an empty seat). Seat 0 is the host's; a seat keeps its
  /// player while they stay, so colours never move.
  final List<String> players;

  /// Players the host removed: they cannot come back.
  final List<String> removed;
  final bool ended;

  /// Which board of the game this is (1, then 2 when the host opens the next board, ...). Moves
  /// carry it, so moves of an earlier board never touch the new one.
  final int board;
  final String puzzleId;

  /// The board in its path form (`cards-4x5t3`), as the game route takes it.
  final String grid;
  final bool painting;

  /// The board as dealt: `layout[slot]` is the card in that slot. Empty when the row had none.
  final List<int> layout;

  /// Why the game ended: `host` (ended for everyone), `host-left`, `idle` (a day without play),
  /// `replaced` (the host started another game).
  final String? endReason;

  /// Players in seat order.
  List<String> get playerIds => [for (final p in players) if (p.isNotEmpty) p];

  int seatOf(String userId) => players.indexOf(userId);

  bool isHost(String userId) => hostId == userId;

  bool get isFull => playerIds.length >= coopMaxPlayers;

  /// The address to share: opens the app where it is installed, the web game elsewhere.
  Uri get joinUrl => AppLink.joinUrl(code);

  /// Where the game screen shows this game's current board.
  String get route => Uri(path: '/game/$puzzleId/$grid', queryParameters: {'coop': id, if (painting) 'painting': '1'}).toString();

  CoopGame copyWith({List<String>? players, List<String>? removed, bool? ended, String? endReason}) => CoopGame(
        id: id,
        code: code,
        hostId: hostId,
        players: players ?? this.players,
        removed: removed ?? this.removed,
        ended: ended ?? this.ended,
        board: board,
        puzzleId: puzzleId,
        grid: grid,
        painting: painting,
        layout: layout,
        endReason: endReason ?? this.endReason,
      );

  /// The stored layout (`3,0,1,...`, or a list of numbers) as card numbers; empty when it is not one.
  static List<int> parseLayout(Object? v) {
    final parts = v is List ? v.map((e) => '$e') : v is String && v.isNotEmpty ? v.split(',') : const <String>[];
    final out = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p.trim());
      if (n == null) return const [];
      out.add(n);
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is CoopGame &&
      other.id == id &&
      other.board == board &&
      other.ended == ended &&
      other.puzzleId == puzzleId &&
      other.grid == grid &&
      listEquals(other.players, players) &&
      listEquals(other.removed, removed) &&
      other.endReason == endReason;

  @override
  int get hashCode => Object.hash(id, board, ended, puzzleId, grid, Object.hashAll(players), Object.hashAll(removed), endReason);
}

/// What a shared change was. Stored by name; a kind this build does not know (from a later build)
/// still changes the board, as [other].
enum CoopOpKind {
  /// A card (and its group) the player moved.
  move,

  /// Magic: a card put in its place (the player who used it paid).
  magic,

  /// Shuffle: the loose cards mixed.
  shuffle,

  /// Gather: cards brought into view on a giant board.
  gather,
  other;

  static CoopOpKind fromName(String? name) => values.where((k) => k.name == name && k != other).firstOrNull ?? other;
}

/// One shared change (a row of `coop_moves`). [seq] is the server's order (`$sequence`), null
/// while this device's own change is on its way.
@immutable
class CoopOp {
  const CoopOp({required this.id, required this.gameId, required this.board, required this.userId, required this.kind, required this.change, this.seq});

  final String id;
  final String gameId;
  final int board;
  final String userId;
  final CoopOpKind kind;
  final BoardChange change;
  final int? seq;

  CoopOp withSeq(int seq) => CoopOp(id: id, gameId: gameId, board: board, userId: userId, kind: kind, change: change, seq: seq);

  /// The columns of its row.
  Map<String, dynamic> toData() => {'gameId': gameId, 'board': board, 'userId': userId, 'kind': kind.name, 'changes': change.encode()};

  /// The row's permissions: the game's players read it, and `read(user:<author>)` proves the
  /// author (Appwrite lets a client grant only roles it holds).
  static List<String> permissionsFor(String gameId, String userId) => ['read("team:$gameId")', 'read("user:$userId")'];

  /// Reads a row of `coop_moves` for a board of [cells] cards; null when it is not a valid change
  /// of it or its author is not proven by its permissions (a row claiming another player's name).
  static CoopOp? fromRow(Map<String, dynamic> row, {required int cells}) {
    final userId = row['userId'];
    final id = row[r'$id'];
    final seq = int.tryParse('${row[r'$sequence']}');
    if (userId is! String || id is! String || seq == null) return null;
    final perms = (row[r'$permissions'] as List?)?.map((p) => '$p') ?? const <String>[];
    if (!perms.contains('read("user:$userId")')) return null;
    final change = BoardChange.decode('${row['changes'] ?? ''}', cells);
    if (change == null) return null;
    return CoopOp(
      id: id,
      gameId: '${row['gameId']}',
      board: (row['board'] as num?)?.toInt() ?? 0,
      userId: userId,
      kind: CoopOpKind.fromName(row['kind'] as String?),
      change: change,
      seq: seq,
    );
  }

  @override
  String toString() => 'CoopOp($id #$seq $userId ${kind.name} $change)';
}

/// Who is here: a player's presence (Appwrite Presences over the realtime socket, readable by the
/// game's team). It goes when their socket closes; `away` while their app is in the background.
@immutable
class CoopPresence {
  const CoopPresence({required this.userId, required this.gameId, required this.board, this.held, this.away = false});

  /// Reads a presence (`status`, `metadata: {g, b, h}`); null when it is not one of a game.
  static CoopPresence? fromMap(Map<String, dynamic> m) {
    final meta = m['metadata'];
    final userId = m['userId'];
    if (meta is! Map || userId is! String || meta['g'] is! String) return null;
    final held = (meta['h'] as num?)?.toInt();
    return CoopPresence(
      userId: userId,
      gameId: meta['g'] as String,
      board: (meta['b'] as num?)?.toInt() ?? 0,
      held: held == null || held < 0 ? null : held,
      away: m['status'] == 'away',
    );
  }

  final String userId;
  final String gameId;
  final int board;

  /// The card the player holds (picked up, not yet placed), as a card number.
  final int? held;
  final bool away;

  Map<String, dynamic> get metadata => {'g': gameId, 'b': board, 'h': held ?? -1};

  @override
  bool operator ==(Object other) => other is CoopPresence && other.userId == userId && other.gameId == gameId && other.board == board && other.held == held && other.away == away;

  @override
  int get hashCode => Object.hash(userId, gameId, board, held, away);
}

/// Why the function refused (its `reason`): the app picks the alert by it.
enum CoopRefusalReason { full, removed, ended, blocked, picture, board, host, auth, server, offline }

class CoopRefusal implements Exception {
  const CoopRefusal(this.reason, [this.message = '']);

  factory CoopRefusal.fromReason(String? reason, String? message) =>
      CoopRefusal(CoopRefusalReason.values.where((r) => r.name == reason).firstOrNull ?? CoopRefusalReason.server, message ?? '');

  final CoopRefusalReason reason;
  final String message;

  @override
  String toString() => 'CoopRefusal(${reason.name}: $message)';
}
