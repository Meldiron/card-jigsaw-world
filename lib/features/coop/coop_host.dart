import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../router.dart';
import '../../state/auth.dart';
import '../../state/coop/coop_controller.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import 'coop_alerts.dart';
import 'coop_players.dart';
import 'coop_routes.dart';

/// Play together above every screen (lib/app.dart): toasts when a player joins or leaves, the
/// removed and ended alerts, guests moved onto the host's next board, and the app's life (away in
/// the background, here again and caught up on return), and Return to game after a restart.
class CoopHost extends ConsumerStatefulWidget {
  const CoopHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<CoopHost> createState() => _CoopHostState();
}

class _CoopHostState extends ConsumerState<CoopHost> with WidgetsBindingObserver {
  StreamSubscription<CoopNotice>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = ref.read(coopProvider.notifier).notices.listen(_onNotice);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) offerReturnToGame(ProviderScope.containerOf(context, listen: false));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final coop = ref.read(coopProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      coop.onResume();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      coop.onPause();
    }
  }

  Future<void> _onNotice(CoopNotice n) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    switch (n) {
      case CoopJoined(:final userId):
        final name = await coopNameOnce(container, userId);
        if (ctx.mounted) showToast(ctx, '$name joined', icon: AppIcons.players);
      case CoopLeft(:final userId):
        final name = await coopNameOnce(container, userId);
        if (ctx.mounted) showToast(ctx, '$name left', icon: AppIcons.players);
      case CoopRemoved(:final game):
        final host = await coopNameOnce(container, game.hostId);
        if (ctx.mounted) await showRemovedAlert(ctx, host);
        container.read(coopProvider.notifier).clear();
        CoopRoutes.exit(container);
      case CoopEnded(:final game):
        final host = await coopNameOnce(container, game.hostId);
        if (ctx.mounted) await showEndedAlert(ctx, game, host);
        final me = container.read(coopProvider).me;
        container.read(coopProvider.notifier).clear();
        // The host keeps the board (it is their own); a guest goes back.
        if (me != game.hostId) CoopRoutes.exit(container);
      case CoopNextBoard(:final game):
        final me = container.read(coopProvider).me;
        if (me == game.hostId) return;
        final router = container.read(routerProvider);
        final at = CoopRoutes.top(router);
        if (at != null && CoopRoutes.isCoop(at)) {
          router.pushReplacement(game.route);
        } else {
          unawaited(router.push(game.route));
        }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Return to game: a player who closed the app during a game finds it again on the next start, when
/// it is still on and their seat is still theirs. A calm toast with Return, once, as soon as a screen
/// of the app (not the welcome pages, not a board) is on top. `CoopHost` calls it at launch.
Future<void> offerReturnToGame(ProviderContainer container) async {
  try {
    await container.read(authProvider.future).timeout(const Duration(seconds: 20));
  } catch (_) {}
  final coop = container.read(coopProvider.notifier);
  final game = await coop.rememberedGame();
  if (game == null) return;
  final router = container.read(routerProvider);
  for (var i = 0; i < 60; i++) {
    final at = CoopRoutes.top(router);
    if (at != null && at.path != '/welcome' && !at.path.startsWith('/game/') && !at.path.startsWith('/auth/')) break;
    await Future<void>.delayed(const Duration(seconds: 2));
    if (container.read(coopProvider).playing) return;
  }
  final me = container.read(coopProvider).me ?? container.read(currentUserIdProvider);
  final host = game.isHost(me ?? '') ? null : await coopNameOnce(container, game.hostId);
  final ctx = rootNavigatorKey.currentContext;
  if (ctx == null || !ctx.mounted || container.read(coopProvider).playing) return;
  showToast(
    ctx,
    host == null ? 'Your game is still on' : 'Your game with $host is still on',
    icon: AppIcons.players,
    action: (
      label: 'Return',
      onTap: () async {
        await coop.rejoin(game);
        unawaited(router.push(game.route));
      },
    ),
  );
}
