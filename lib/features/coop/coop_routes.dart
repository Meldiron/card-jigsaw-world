import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../state/settings.dart';

/// Where a shared board lives: the game route with `?coop=<game id>` (`CoopGame.route`). The game
/// screen reads the query to play the board with the others (phase 2).
class CoopRoutes {
  CoopRoutes._();

  /// The query key of a shared board.
  static const param = 'coop';

  static bool isCoop(Uri uri) => uri.path.startsWith('/game/') && uri.queryParameters.containsKey(param);

  /// The route on top now, or null before the first route.
  static Uri? top(GoRouter router) => router.routerDelegate.currentConfiguration.isEmpty ? null : router.state.uri;

  /// Leaves the shared board's screen when it is on top: to Home, or to the welcome pages for a player
  /// who came straight in from an invite before ever opening the app (their start begins now).
  static void exit(ProviderContainer container) {
    final router = container.read(routerProvider);
    final at = top(router);
    if (at == null || !isCoop(at)) return;
    router.go(container.read(settingsProvider).onboarded ? '/home' : '/welcome');
  }
}
