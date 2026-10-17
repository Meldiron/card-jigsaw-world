import 'coop_models.dart';

/// What reaches a game's players live (Appwrite Realtime): a move row, the game row, a presence.
sealed class CoopEvent {
  const CoopEvent();
}

/// A row of `coop_moves` was created.
class CoopMoveEvent extends CoopEvent {
  const CoopMoveEvent(this.row);
  final Map<String, dynamic> row;
}

/// The game row changed, or went ([deleted]: the cleanup deleted an ended game).
class CoopGameEvent extends CoopEvent {
  const CoopGameEvent(this.row, {this.deleted = false});
  final Map<String, dynamic> row;
  final bool deleted;
}

/// A player's presence was set, or went ([deleted]: their socket closed).
class CoopPresenceEvent extends CoopEvent {
  const CoopPresenceEvent(this.presence, {this.deleted = false});
  final Map<String, dynamic> presence;
  final bool deleted;
}

/// The realtime connection reported an error (the SDK reconnects by itself; what was missed in
/// between is read again, see `CoopController.catchUp`).
class CoopConnectionEvent extends CoopEvent {
  const CoopConnectionEvent();
}

/// The server side of Play together (docs/multiplayer.md), behind an interface so the engine runs
/// against an in-memory server in tests (`test/support/fake_coop.dart`). The app's is
/// `AppwriteCoopBackend` (`lib/data/coop_repository.dart`).
abstract class CoopBackend {
  /// Calls the `coop-game` function: `create`, `join`, `leave`, `remove`, `end` or `next`. Returns
  /// the game (null for `leave`); throws [CoopRefusal] when the function refuses or cannot be
  /// reached ([CoopRefusalReason.offline]).
  Future<CoopGame?> call(String action, Map<String, dynamic> body);

  /// The game row as the player can read it now; null when it is gone or no longer readable (the
  /// player was removed, the game was deleted). Throws when the server cannot be reached.
  Future<CoopGame?> readGame(String gameId);

  /// Creates the row of [op] (its id is fixed, so a retry after a lost answer finds the row instead
  /// of making a second one) and returns it as the server has it, `$sequence` included. Throws
  /// [CoopRefusal] with [CoopRefusalReason.removed] when the player may no longer add moves.
  Future<Map<String, dynamic>> createMove(CoopOp op);

  /// The moves of [board] in game [gameId] after the server order [afterSeq], in that order (every
  /// page, cursor pagination).
  Future<List<Map<String, dynamic>>> movesAfter(String gameId, int board, int afterSeq);

  /// Live events of game [gameId]: its moves (filtered on the server by `gameId`), its row and the
  /// presences this player can read. The stream ends with [close].
  Stream<CoopEvent> listen(String gameId);

  /// Sets this player's presence in game [gameId] (sent over the realtime socket, resent by the SDK
  /// after a reconnect, gone when the socket closes).
  void setPresence(String presenceId, CoopPresence presence);

  /// The presences of [userIds] this player can read (every page).
  Future<List<Map<String, dynamic>>> presences(List<String> userIds);

  /// Stops listening.
  Future<void> close();
}
