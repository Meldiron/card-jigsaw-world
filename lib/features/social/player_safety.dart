import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/social.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// Player > Report: pick a reason; the report goes to the developer (table `reports`), and the
/// player is told it was sent. Reporting never blocks by itself.
Future<void> showReportSheet(BuildContext context, Profile player) async {
  final reason = await showAppSheet<ReportReason>(
    context,
    builder: (ctx) {
      final c = ctx.colors;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Report ${player.displayName}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
            const SizedBox(height: 6),
            Text('What is wrong? We read every report.', style: TextStyle(fontSize: 14, color: c.textSecondary)),
            const SizedBox(height: 16),
            for (final r in ReportReason.values) ...[
              BigButton(key: ValueKey('report-${r.code}'), label: r.label, kind: ButtonKind.secondary, height: 48, onTap: () => Navigator.of(ctx).pop(r)),
              const SizedBox(height: 8),
            ],
          ],
        ),
      );
    },
  );
  if (reason == null || !context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await container.read(playerSafetyProvider).report(player, reason);
    Haptics.success();
    if (context.mounted) showToast(context, 'Report sent. Thank you.', icon: AppIcons.report);
  } catch (e) {
    if (context.mounted) showToast(context, 'The report could not be sent. Check your connection and try again.', icon: AppIcons.signal);
  }
}

/// Player > Block, after a confirmation.
Future<void> confirmBlock(BuildContext context, Profile player) async {
  final ok = await showAppAlert(
    context,
    title: 'Block ${player.displayName}?',
    message: 'They no longer show on your leaderboard and leave your friends. Unblock them any time in Settings > Blocked players.',
    confirmLabel: 'Block',
    cancelLabel: 'Cancel',
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await container.read(playerSafetyProvider).block(player);
    Haptics.success();
    if (context.mounted) showToast(context, '${player.displayName} is blocked', icon: AppIcons.block);
  } catch (e) {
    if (context.mounted) showToast(context, 'Could not block. Check your connection and try again.', icon: AppIcons.signal);
  }
}

Future<void> unblockPlayer(BuildContext context, String playerId, String name) async {
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await container.read(playerSafetyProvider).unblock(playerId);
    if (context.mounted) showToast(context, '$name is unblocked', icon: AppIcons.block);
  } catch (e) {
    if (context.mounted) showToast(context, 'Could not unblock. Check your connection and try again.', icon: AppIcons.signal);
  }
}

/// Settings > Blocked players.
Future<void> showBlockedPlayersSheet(BuildContext context) => showAppSheet(context, builder: (_) => const BlockedPlayersPanel());

class BlockedPlayersPanel extends ConsumerWidget {
  const BlockedPlayersPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final blocked = ref.watch(blockedPlayersProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Blocked players', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
          const SizedBox(height: 6),
          Text('They do not show on your leaderboard.', style: TextStyle(fontSize: 14, color: c.textSecondary)),
          const SizedBox(height: 12),
          blocked.when(
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Loader()),
            error: (e, _) => const EmptyState(icon: AppIcons.signal, title: 'Could not load', message: 'Check your connection and try again.'),
            data: (list) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: EmptyState(key: ValueKey('blocked-empty'), icon: AppIcons.block, title: 'Nobody blocked', message: 'Block a player from their profile.'),
                  )
                : Column(
                    children: [
                      for (final b in list)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              AvatarCircle(avatarKey: b.avatar, size: 36),
                              const SizedBox(width: 12),
                              Expanded(child: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                              BigButton(
                                key: ValueKey('unblock-${b.playerId}'),
                                label: 'Unblock',
                                kind: ButtonKind.secondary,
                                height: 36,
                                expand: false,
                                onTap: () => unblockPlayer(context, b.playerId, b.name),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
