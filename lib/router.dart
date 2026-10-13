import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/daily/wheel_screen.dart';
import 'features/events/events_screen.dart';
import 'features/gallery/library_screen.dart';
import 'features/gallery/pack_screen.dart';
import 'features/game/game_screen.dart';
import 'features/game/difficulty_screen.dart';
import 'features/home/home_screen.dart';
import 'features/home/home_shell.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/profile/account_screen.dart';
import 'features/profile/my_puzzles_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/profile/settings_screen.dart';
import 'features/social/player_screen.dart';
import 'features/social/social_screen.dart';
import 'features/store/store_screen.dart';
import 'state/settings.dart';

/// The app's root navigator (alerts and sheets raised outside a screen, e.g. by the save sync).
final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final onboarded = ref.watch(settingsProvider.select((s) => s.onboarded));
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: onboarded ? '/home' : '/welcome',
    // Unknown paths (typed URLs on web, stale links) land on Home instead of
    // the framework's error page. `/auth/callback` is reserved for the
    // Appwrite OAuth redirect; until its handler is registered it also
    // falls back here.
    onException: (context, state, router) => router.go(onboarded ? '/home' : '/welcome'),
    redirect: (context, state) {
      // Widget deep links arrive as /play/<id>; let them through even for new installs.
      if (!onboarded && state.uri.path.startsWith('/play/')) {
        ref.read(settingsProvider.notifier).setOnboarded();
      }
      return null;
    },
    routes: [
      GoRoute(path: '/welcome', pageBuilder: (c, s) => _fade(const OnboardingScreen(), s)),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', pageBuilder: (c, s) => _noAnim(const HomeScreen(), s))]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/library',
              pageBuilder: (c, s) => _noAnim(const LibraryScreen(), s),
              routes: [
                GoRoute(path: 'pack/:packId', pageBuilder: (c, s) => _cupertino(PackScreen(packId: s.pathParameters['packId']!), s)),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/events', pageBuilder: (c, s) => _noAnim(const EventsScreen(), s))]),
          StatefulShellBranch(routes: [GoRoute(path: '/social', pageBuilder: (c, s) => _noAnim(const SocialScreen(), s))]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/profile',
              pageBuilder: (c, s) => _noAnim(const ProfileScreen(), s),
              routes: [
                GoRoute(path: 'settings', pageBuilder: (c, s) => _cupertino(const SettingsScreen(), s)),
                GoRoute(path: 'account', pageBuilder: (c, s) => _cupertino(const AccountScreen(), s)),
                GoRoute(path: 'my-puzzles', pageBuilder: (c, s) => _cupertino(const MyPuzzlesScreen(), s)),
              ],
            ),
          ]),
        ],
      ),
      // Full-screen routes above the tab shell.
      GoRoute(
        path: '/play/:puzzleId',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (c, s) => _cupertino(
          DifficultyScreen(
            puzzleId: s.pathParameters['puzzleId']!,
            initialGrid: s.uri.queryParameters['grid'],
            initialMode: s.uri.queryParameters['mode'],
            initialPainting: s.uri.queryParameters['painting'] == '1',
          ),
          s,
        ),
      ),
      GoRoute(
        // :grid is a BoardCode path form, e.g. hexagons-5x6 or 4x4 (cards); `?painting=1` starts a
        // new board in Painting (a saved board resumes as it was saved).
        path: '/game/:puzzleId/:grid',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (c, s) => _fade(GameScreen(puzzleId: s.pathParameters['puzzleId']!, gridCode: s.pathParameters['grid']!, painting: s.uri.queryParameters['painting'] == '1'), s),
      ),
      GoRoute(path: '/store', parentNavigatorKey: rootNavigatorKey, pageBuilder: (c, s) => _sheet(StoreScreen(showVip: s.uri.queryParameters['vip'] == '1'), s)),
      GoRoute(path: '/wheel', parentNavigatorKey: rootNavigatorKey, pageBuilder: (c, s) => _sheet(const WheelScreen(), s)),
      GoRoute(path: '/account', parentNavigatorKey: rootNavigatorKey, pageBuilder: (c, s) => _sheet(const AccountScreen(), s)),
      GoRoute(path: '/auth/callback', parentNavigatorKey: rootNavigatorKey, pageBuilder: (c, s) => _fade(AuthCallbackScreen(query: s.uri.queryParameters), s)),
      GoRoute(path: '/player/:userId', parentNavigatorKey: rootNavigatorKey, pageBuilder: (c, s) => _cupertino(PlayerScreen(userId: s.pathParameters['userId']!), s)),
    ],
  );
});

Page<T> _cupertino<T>(Widget child, GoRouterState s) => CupertinoPage<T>(key: s.pageKey, child: child);
Page<T> _noAnim<T>(Widget child, GoRouterState s) => NoTransitionPage<T>(key: s.pageKey, child: child);
Page<T> _fade<T>(Widget child, GoRouterState s) => CustomTransitionPage<T>(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 320),
      transitionsBuilder: (_, a, _, c) => FadeTransition(opacity: CurveTween(curve: Curves.easeOut).animate(a), child: c),
    );
Page<T> _sheet<T>(Widget child, GoRouterState s) => _SheetPage<T>(key: s.pageKey, child: child);

/// iOS stacked sheet (UISheetPresentationController look): slides up to just
/// below the status bar, the page behind scales back, drag down to dismiss.
class _SheetPage<T> extends Page<T> {
  const _SheetPage({required this.child, super.key});
  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => CupertinoSheetRoute<T>(settings: this, scrollableBuilder: (_, _) => child);
}
