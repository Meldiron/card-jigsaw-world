import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../router.dart';
import '../../state/coop/coop_controller.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import 'coop_alerts.dart';
import 'coop_players.dart';
import 'coop_routes.dart';

/// Play together above every screen (lib/app.dart): toasts when a player joins or leaves, the
/// removed and ended alerts, guests moved onto the host's next board, and the app's life (away in
/// the background, here again and caught up on return).
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
