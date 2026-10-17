import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/a11y.dart';
import '../../core/theme/tokens.dart';
import '../../state/coop/coop_controller.dart';
import '../../state/social.dart';

/// A player of the game, as the co-op screens show them.
@immutable
class CoopSeat {
  const CoopSeat({required this.userId, required this.seat, required this.isMe, required this.isHost, required this.here, this.colour});

  final String userId;
  final int seat;
  final bool isMe;
  final bool isHost;

  /// The player has the game open now (this device's player always does).
  final bool here;

  /// Index into [PlayerColors] (0 to 3); null for this device's player, who is the accent (cobalt).
  final int? colour;

  Color colorOf(BuildContext context) => colour == null ? context.accent : context.playerColor(colour!);
  Color onColorOf(BuildContext context) => colour == null ? context.onAccent : context.onPlayerColor;
}

/// The other players' colours on this device: the four [PlayerColors] go round the seats after this
/// player's own, so they never change while those players stay. 0 to 3.
int coopColourIndex(int seat, int mySeat) => mySeat < 0 ? seat % PlayerColors.count : ((seat - mySeat - 1) % 5 + 5) % 5 % PlayerColors.count;

/// The game's players in seat order (the host first).
List<CoopSeat> coopSeats(CoopState s) {
  final g = s.game;
  if (g == null) return const [];
  final me = s.me;
  final mine = me == null ? -1 : g.seatOf(me);
  return [
    for (var i = 0; i < g.players.length; i++)
      if (g.players[i].isNotEmpty)
        CoopSeat(
          userId: g.players[i],
          seat: i,
          isMe: g.players[i] == me,
          isHost: g.isHost(g.players[i]),
          here: g.players[i] == me || s.isHere(g.players[i]),
          colour: g.players[i] == me ? null : coopColourIndex(i, mine),
        ),
  ];
}

/// A player's name (their public profile), "Player" until it loads or when it cannot.
String coopName(WidgetRef ref, String userId) => ref.watch(playerProfileProvider(userId)).value?.displayName ?? 'Player';

/// The same, read once (for toasts and alerts raised outside a build).
Future<String> coopNameOnce(ProviderContainer container, String userId) async {
  try {
    final p = await container.read(playerProfileProvider(userId).future).timeout(const Duration(seconds: 4));
    return p?.displayName ?? 'Player';
  } catch (_) {
    return 'Player';
  }
}

/// The first letter of a name, for the marks on cards and the player list.
String coopInitial(String name) {
  final t = name.trim();
  return t.isEmpty ? '?' : String.fromCharCode(t.runes.first).toUpperCase();
}

/// A player's initial in their colour: the mark on a card they hold or just moved (the board draws it
/// in a corner, phase 2) and beside their name in the player list. The initial goes with the colour
/// everywhere, so the player is told apart without colour too.
class PlayerInitialBadge extends StatelessWidget {
  const PlayerInitialBadge({super.key, required this.initial, required this.color, required this.onColor, this.size = 22});
  final String initial;
  final Color color;
  final Color onColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final contrast = A11y.increaseContrastOf(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        // A thin ring in the card's colour keeps the badge apart from the picture under it.
        border: Border.all(color: contrast ? onColor : context.colors.cardFace, width: size >= 20 ? 1.5 : 1),
      ),
      child: Text(
        initial,
        // Fixed size: a mark on a card does not grow with the text size (it would cover the card).
        textScaler: TextScaler.noScaling,
        style: TextStyle(color: onColor, fontSize: size * 0.52, fontWeight: FontWeight.w700, height: 1),
      ),
    );
  }
}

/// How the board marks a card another player holds or just moved: an outline in the player's
/// colour and their initial in a corner (phase 2 draws it in `board_widget.dart`).
@immutable
class CoopCardMark {
  const CoopCardMark({required this.userId, required this.initial, required this.color, required this.onColor, required this.held});
  final String userId;
  final String initial;
  final Color color;
  final Color onColor;

  /// Held (picked up) rather than just moved: a solid outline; a moved card's outline fades.
  final bool held;
}

/// Another player's card being dragged ([LiveTracks] in `coop_live.dart`): drawn lifted at [at] (a
/// fraction of the board, where their finger has it), outlined in their colour with their initial.
@immutable
class CoopGhost {
  const CoopGhost({required this.card, required this.at, required this.mark});
  final int card;
  final Offset at;
  final CoopCardMark mark;
}

/// Each other player's colour and initial, for their dragged cards.
Map<String, CoopCardMark> coopPlayerMarks(BuildContext context, WidgetRef ref, CoopState s) => {
      for (final seat in coopSeats(s))
        if (!seat.isMe) seat.userId: CoopCardMark(userId: seat.userId, initial: coopInitial(coopName(ref, seat.userId)), color: seat.colorOf(context), onColor: seat.onColorOf(context), held: true),
    };

/// The marks for the board: card number to mark, for every card another player holds or moved a
/// moment ago ([CoopState.marks]). Names come from the players' profiles.
Map<int, CoopCardMark> coopCardMarks(BuildContext context, WidgetRef ref, CoopState s) {
  if (s.marks.isEmpty) return const {};
  final seats = {for (final seat in coopSeats(s)) seat.userId: seat};
  CoopCardMark? mark(String userId, bool held) {
    final seat = seats[userId];
    if (seat == null || seat.isMe) return null;
    return CoopCardMark(userId: userId, initial: coopInitial(coopName(ref, userId)), color: seat.colorOf(context), onColor: seat.onColorOf(context), held: held);
  }

  return {
    for (final e in s.marks.moved.entries) e.key: ?mark(e.value, false),
    for (final e in s.marks.held.entries) e.key: ?mark(e.value, true),
  };
}
