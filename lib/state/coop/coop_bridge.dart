import 'dart:async';

import 'package:flutter/foundation.dart';

import 'coop_controller.dart';
import 'coop_log.dart';
import 'coop_models.dart';

/// The board on screen, as Play together sees it. The game screen gives one (an adapter over its
/// `GameController`) to a [CoopBridge].
abstract interface class CoopBoardTarget {
  /// The board shown now: `layout[slot]` is the card in that slot.
  List<int> get layout;

  /// Shows the shared board [CoopBoardUpdate.update]`.after`: other players' changes (their cards
  /// move, [LogUpdate.applied] names who moved what), and this player's own changes that lost to an
  /// earlier one (their cards slide back, [LogUpdate.dropped]). Not a move of this player's: it
  /// counts no move and is never undone.
  void showShared(CoopBoardUpdate update);
}

/// The seam between a board on screen and the shared game (phase 2 wires it into the game screen):
///
/// - after every change the player makes on this device (a move, Magic, Shuffle, Gather), the
///   screen calls [localChange] with the board before and after it; the change is shared as the
///   slots whose card changed, with the card expected before and the card after;
/// - every change from the server reaches [CoopBoardTarget.showShared], except the player's own
///   changes, which the screen shows already.
///
/// Hint and Peek do not change the board and are never shared; there is no Undo in a shared game.
class CoopBridge {
  CoopBridge(this._coop, this._target) {
    _sub = _coop.updates.listen(_onUpdate);
  }

  final CoopController _coop;
  final CoopBoardTarget _target;
  late final StreamSubscription<CoopBoardUpdate> _sub;

  /// Shares the change the player just made: [before] and [after] are the board before and after
  /// it. Returns false when it was not shared: no game, or the shared board had changed under it
  /// (the screen is then put back on the shared board).
  bool localChange(CoopOpKind kind, List<int> before, List<int> after) {
    if (listEquals(before, after)) return true;
    final update = _coop.submit(kind, before, after);
    if (update != null) return true;
    resync();
    return false;
  }

  /// Puts the screen on the shared board when it shows anything else.
  void resync() {
    final log = _coop.log;
    if (log == null || listEquals(_target.layout, log.layout)) return;
    _target.showShared(CoopBoardUpdate(log.board, LogUpdate(before: List.of(_target.layout), after: log.layout)));
  }

  void _onUpdate(CoopBoardUpdate u) {
    // The player's own change: on screen already.
    if (listEquals(_target.layout, u.update.after)) return;
    if (listEquals(_target.layout, u.update.before)) {
      _target.showShared(u);
    } else {
      // The screen and the shared board parted (a change of the screen's own the bridge never
      // heard of): show the shared board from where the screen is.
      _target.showShared(CoopBoardUpdate(u.board, LogUpdate(before: List.of(_target.layout), after: u.update.after, applied: u.update.applied, dropped: u.update.dropped)));
    }
  }

  void dispose() => _sub.cancel();
}
