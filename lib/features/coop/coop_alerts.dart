import 'package:flutter/material.dart';

import '../../state/coop/coop_models.dart';
import '../../widgets/ui.dart';

/// The co-op confirmations and alerts (docs/multiplayer.md). Every action that takes someone out
/// of a game asks first.

/// The host's Remove on a player.
Future<bool> confirmRemovePlayer(BuildContext context, String name) => showAppAlert(
      context,
      title: 'Remove $name?',
      message: 'They leave the game and cannot join it again.',
      confirmLabel: 'Remove',
      destructive: true,
    );

/// The host's End game for everyone (the player list and the pause menu).
Future<bool> confirmEndForEveryone(BuildContext context) => showAppAlert(
      context,
      title: 'End game for everyone?',
      message: 'The others leave the board. You keep playing it on your own.',
      confirmLabel: 'End game',
      destructive: true,
    );

/// A guest's Leave game (the player list, the pause menu, the finished board).
Future<bool> confirmLeaveGame(BuildContext context) => showAppAlert(
      context,
      title: 'Leave game?',
      message: 'You can come back with the invite link while the game is on.',
      confirmLabel: 'Leave game',
      destructive: true,
    );

/// Joining another game while in one: the player is in one game at a time.
Future<bool> confirmSwitchGame(BuildContext context) => showAppAlert(
      context,
      title: 'Join the other game?',
      message: 'You leave the game you are in now.',
      confirmLabel: 'Join game',
      cancelLabel: 'Stay',
    );

/// The host removed this player.
Future<void> showRemovedAlert(BuildContext context, String hostName) => showAppAlert(
      context,
      title: 'Removed from the game',
      message: '$hostName removed you from the game. The board stays with them.',
      confirmLabel: 'Close',
      cancelLabel: null,
    );

/// The game ended for everyone.
Future<void> showEndedAlert(BuildContext context, CoopGame game, String hostName) => showAppAlert(
      context,
      title: 'Game ended',
      message: endedMessage(game.endReason, hostName),
      confirmLabel: 'Close',
      cancelLabel: null,
    );

/// Why a game ended, in a line.
String endedMessage(String? reason, String hostName) => switch (reason) {
      'host' => '$hostName ended the game for everyone.',
      'host-left' => '$hostName left, so the game ended.',
      'replaced' => '$hostName started another game.',
      'idle' => 'The game ended after a day without play.',
      _ => 'This game has ended.',
    };

/// Title and line of an alert for a refusal of the `coop-game` function.
({String title, String message, bool retry}) refusalText(CoopRefusal r) => switch (r.reason) {
      CoopRefusalReason.full => (title: 'This game is full', message: 'Up to $coopMaxPlayers players can play together.', retry: false),
      CoopRefusalReason.removed => (title: 'You cannot join this game', message: 'The host removed you from it.', retry: false),
      CoopRefusalReason.ended => (title: 'This game has ended', message: 'Ask for a new invite to play together.', retry: false),
      CoopRefusalReason.blocked => (title: 'You cannot join this game', message: 'This invite does not work for you.', retry: false),
      CoopRefusalReason.picture => (title: 'This picture cannot be shared', message: 'Only pictures from the Library can be played together.', retry: false),
      CoopRefusalReason.board => (title: 'This board cannot be shared', message: 'Start a new board and try again.', retry: false),
      CoopRefusalReason.host => (title: 'Only the host can do this', message: 'Ask the host of the game.', retry: false),
      CoopRefusalReason.offline => (title: 'No connection', message: 'Playing together needs a connection. Check it and try again.', retry: true),
      CoopRefusalReason.auth || CoopRefusalReason.server => (title: 'Something went wrong', message: 'Try again in a moment.', retry: true),
    };

/// Shows [r]; true when the player chose Try again.
Future<bool> showRefusal(BuildContext context, CoopRefusal r) {
  final t = refusalText(r);
  return showAppAlert(
    context,
    title: t.title,
    message: t.message,
    confirmLabel: t.retry ? 'Try again' : 'Close',
    cancelLabel: t.retry ? 'Cancel' : null,
  ).then((ok) => t.retry && ok);
}
