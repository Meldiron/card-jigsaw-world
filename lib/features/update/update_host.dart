import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../state/app_update.dart';
import '../../state/sync.dart';
import '../../widgets/ui.dart';

/// Asks the player to update when a newer build is out (web and iPhone, see [UpdatePolicy]):
/// between screens, never during a game, a sign-in or the welcome screens. "Later" closes it for
/// an hour; a reload or a new launch asks again; it stops only on the newest build.
class UpdateHost extends ConsumerStatefulWidget {
  const UpdateHost({super.key, required this.child});
  final Widget child;

  /// When the player last answered the prompt. In memory only, so every reload or launch asks
  /// again. Static so a rebuilt host keeps it.
  static DateTime? lastAsked;

  @override
  ConsumerState<UpdateHost> createState() => _UpdateHostState();
}

class _UpdateHostState extends ConsumerState<UpdateHost> {
  GoRouter? _router;
  bool _showing = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The hour after "Later" passes without anything else changing.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => _maybeAsk());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _router?.routerDelegate.removeListener(_maybeAsk);
    super.dispose();
  }

  bool get _calm {
    final path = _router?.routerDelegate.currentConfiguration.uri.path ?? '';
    return path.isNotEmpty && !path.startsWith('/game/') && !path.startsWith('/auth/') && !path.startsWith('/welcome');
  }

  Future<void> _maybeAsk() async {
    final update = ref.read(appUpdateProvider);
    if (_showing || !mounted || update == null || !_calm) return;
    if (!UpdatePolicy.askDue(lastAsked: UpdateHost.lastAsked, now: DateTime.now())) return;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    _showing = true;
    final go = await showAppAlert(ctx, title: 'Update available', message: update.message, confirmLabel: update.action, cancelLabel: 'Later');
    UpdateHost.lastAsked = DateTime.now();
    _showing = false;
    if (!go || !mounted) return;
    // Anything still queued for the server goes first: on the web the page reloads.
    try {
      await ref.read(syncProvider.notifier).flush().timeout(const Duration(seconds: 4));
    } catch (_) {}
    await ref.read(appUpdateProvider.notifier).update();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    if (router != _router) {
      _router?.routerDelegate.removeListener(_maybeAsk);
      _router = router..routerDelegate.addListener(_maybeAsk);
    }
    ref.listen(appUpdateProvider, (_, u) {
      if (u != null) Future.delayed(const Duration(milliseconds: 600), _maybeAsk);
    });
    return widget.child;
  }
}
