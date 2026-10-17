import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../state/coop/coop_controller.dart';
import '../../widgets/ui.dart';
import 'coop_alerts.dart';
import 'coop_players.dart';
import 'coop_routes.dart';

/// A guest's end of a shared board (the host sees the usual completion card): their rewards, then
/// "Waiting for `host` to pick the next board" and Leave game. When the host opens the next board,
/// `CoopHost` moves the guest onto it.
///
/// [rewards] is the completion card's rewards row (phase 2 passes it); null when the guest earns
/// none (no card of theirs locked: a guest earns the board's rewards with at least one).
class CoopGuestFinish extends ConsumerWidget {
  const CoopGuestFinish({super.key, this.rewards});
  final Widget? rewards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(coopProvider);
    final host = s.game == null ? 'the host' : coopName(ref, s.game!.hostId);
    return Column(
      key: const ValueKey('coop-guest-finish'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Picture complete', textAlign: TextAlign.center, style: TextStyle(fontSize: TypeSize.title2, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: c.textPrimary)),
        const SizedBox(height: 14),
        if (rewards != null)
          rewards!
        else
          Text(
            'Lock a card yourself to earn a board\'s rewards.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: TypeSize.body, color: c.textSecondary),
          ),
        const SizedBox(height: 22),
        Semantics(
          liveRegion: true,
          child: Column(
            children: [
              const CupertinoActivityIndicator(radius: 9),
              const SizedBox(height: 10),
              Text(
                'Waiting for $host to pick the next board',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w500, color: c.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        BigButton(
          key: const ValueKey('coop-finish-leave'),
          label: 'Leave game',
          kind: ButtonKind.ghost,
          onTap: () async {
            if (!await confirmLeaveGame(context) || !context.mounted) return;
            final container = ProviderScope.containerOf(context, listen: false);
            await container.read(coopProvider.notifier).leave();
            CoopRoutes.exit(container);
          },
        ),
      ],
    );
  }
}
