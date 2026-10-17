import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/a11y.dart';
import '../../core/haptics.dart';
import '../../core/theme/tokens.dart';
import '../../state/catalog.dart';
import '../../state/coop/coop_controller.dart';
import '../../state/coop/coop_models.dart';
import '../../state/social.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import 'coop_alerts.dart';
import 'coop_players.dart';
import 'coop_routes.dart';
import 'share_invite.dart';

/// The players chip in the game's top bar (phase 2 puts it in the HUD): people and a count. Opens
/// the player list.
class CoopPlayersChip extends ConsumerWidget {
  const CoopPlayersChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(coopProvider);
    if (!s.playing) return const SizedBox.shrink();
    final count = s.game!.playerIds.length;
    final accent = context.accent;
    return Semantics(
      button: true,
      label: '$count ${count == 1 ? 'player' : 'players'}. Show players',
      excludeSemantics: true,
      child: Pressable(
        key: const ValueKey('coop-players-chip'),
        onTap: () => showCoopPlayersSheet(context),
        scale: 0.94,
        child: TapTarget(
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: context.colors.accentTint,
              borderRadius: BorderRadius.circular(Radii.pill),
              border: A11y.increaseContrastOf(context) ? Border.all(color: accent) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.players, size: 16, color: accent),
                const SizedBox(width: 5),
                Text('$count', style: TextStyle(fontSize: TypeSize.callout, fontWeight: FontWeight.w700, color: accent, fontFeatures: tabularFigures)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The player list: who plays, their colour and initial, Host and You, here or away. A tap on
/// another player opens their profile (Report and Block are there). The host removes players,
/// invites while there is a free seat and ends the game for everyone; a guest leaves.
Future<void> showCoopPlayersSheet(BuildContext context) => showAppSheet(context, builder: (_) => const CoopPlayersPanel());

class CoopPlayersPanel extends ConsumerWidget {
  const CoopPlayersPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(coopProvider);
    final g = s.game;
    if (g == null || !s.playing) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: SheetHeader(title: 'Players', subtitle: 'This game has ended.'),
      );
    }
    final seats = coopSeats(s);
    final host = s.isHost;
    final free = coopMaxPlayers - seats.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(title: 'Players', subtitle: '${seats.length} of $coopMaxPlayers playing this board'),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(color: c.card.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(Radii.md)),
            child: Column(
              children: [
                for (final (i, seat) in seats.indexed) ...[
                  if (i > 0) Divider(height: 1, thickness: 0.5, indent: 68, color: c.stroke),
                  _PlayerRow(seat: seat, canRemove: host && !seat.isMe),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (host && free > 0) ...[
            Builder(
              builder: (context) => BigButton(
                key: const ValueKey('coop-invite'),
                label: 'Invite',
                icon: AppIcons.invite,
                kind: ButtonKind.secondary,
                onTap: () => shareInvite(context, g, pictureTitle: ref.read(puzzleByIdProvider(g.puzzleId))?.title),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              free == 1 ? 'One more player can join.' : '$free more players can join.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary),
            ),
            const SizedBox(height: 12),
          ],
          if (host)
            _DangerRow(key: const ValueKey('coop-end'), icon: AppIcons.endGame, label: 'End game for everyone', onTap: () => _end(context, ref))
          else
            _DangerRow(key: const ValueKey('coop-leave'), icon: AppIcons.leaveGame, label: 'Leave game', onTap: () => _leave(context, ref)),
        ],
      ),
    );
  }

  Future<void> _end(BuildContext context, WidgetRef ref) async {
    if (!await confirmEndForEveryone(context) || !context.mounted) return;
    try {
      await ref.read(coopProvider.notifier).endForEveryone();
      Haptics.success();
      if (context.mounted) {
        Navigator.of(context).pop();
        showToast(context, 'Game ended. The board is yours.', icon: AppIcons.players);
      }
    } on CoopRefusal catch (e) {
      if (context.mounted) await showRefusal(context, e);
    }
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    if (!await confirmLeaveGame(context) || !context.mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    Navigator.of(context).pop();
    await container.read(coopProvider.notifier).leave();
    CoopRoutes.exit(container);
  }
}

class _PlayerRow extends ConsumerWidget {
  const _PlayerRow({required this.seat, required this.canRemove});
  final CoopSeat seat;
  final bool canRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final profile = ref.watch(playerProfileProvider(seat.userId)).value;
    final name = profile?.displayName ?? 'Player';
    final color = seat.colorOf(context);
    final status = [if (seat.isHost) 'Host', if (seat.isMe) 'You' else (seat.here ? 'Here' : 'Away')].join(' · ');
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          // The avatar in the player's ring, their initial at its corner: colour and letter together.
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 2.5)),
                  child: AvatarCircle(avatarKey: profile?.avatar, size: 35),
                ),
                Positioned(right: -4, bottom: -4, child: PlayerInitialBadge(initial: coopInitial(name), color: color, onColor: seat.onColorOf(context), size: 20)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w600)),
                const SizedBox(height: 1),
                Row(
                  children: [
                    // Here or away is said in words; the dot only repeats it.
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: seat.here ? c.success : Colors.transparent,
                        border: seat.here ? null : Border.all(color: c.textTertiary, width: 1.2),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary))),
                  ],
                ),
              ],
            ),
          ),
          if (canRemove)
            Pressable(
              key: ValueKey('coop-remove-${seat.userId}'),
              onTap: () => _remove(context, ref, name),
              child: TapTarget(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('Remove', style: TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w600, color: c.danger)),
                ),
              ),
            )
          else if (!seat.isMe)
            Icon(AppIcons.chevronRight, size: 16, color: c.textTertiary),
        ],
      ),
    );
    if (seat.isMe) return Semantics(label: '$name, you${seat.isHost ? ', host' : ''}', excludeSemantics: true, child: row);
    return Semantics(
      button: true,
      label: '$name, ${status.toLowerCase()}. Show profile',
      child: Pressable(
        key: ValueKey('coop-player-${seat.userId}'),
        scale: 0.99,
        onTap: () {
          final router = GoRouter.of(context);
          Navigator.of(context).pop();
          router.push('/player/${seat.userId}');
        },
        child: row,
      ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, String name) async {
    if (!await confirmRemovePlayer(context, name) || !context.mounted) return;
    try {
      await ref.read(coopProvider.notifier).remove(seat.userId);
      if (context.mounted) showToast(context, '$name was removed', icon: AppIcons.players);
    } on CoopRefusal catch (e) {
      if (context.mounted) await showRefusal(context, e);
    }
  }
}

/// A red row at the end of the list: End game for everyone, Leave game (both ask first).
class _DangerRow extends StatelessWidget {
  const _DangerRow({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      child: Pressable(
        onTap: onTap,
        scale: 0.99,
        child: Container(
          height: 50,
          decoration: BoxDecoration(color: c.card.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(Radii.md)),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(icon, size: 20, color: c.danger),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: TextStyle(fontSize: TypeSize.callout, fontWeight: FontWeight.w500, color: c.danger))),
            ],
          ),
        ),
      ),
    );
  }
}
