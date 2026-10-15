import 'package:carden/core/platform.dart';
import 'package:carden/features/ads/house_ads.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Owner feedback 2026-10-13: tapping an ad break's offer must leave the game
/// for the offer, not move on to the next puzzle.
void main() {
  const caps = PlatformCaps(isWeb: false, purchases: true, giftCodes: true, quickActions: true, widgets: true, notifications: true, nativeAppleSignIn: true);

  Future<GoRouter> pumpGame(WidgetTester tester, void Function(BuildContext, WidgetRef) onTap) async {
    final router = GoRouter(initialLocation: '/home', routes: [
      GoRoute(path: '/home', builder: (_, _) => const Text('home')),
      GoRoute(path: '/events', builder: (_, _) => const Text('events')),
      GoRoute(path: '/store', builder: (_, _) => const Text('store')),
      GoRoute(
        path: '/game',
        builder: (_, _) => Consumer(builder: (context, ref, _) => TextButton(onPressed: () => onTap(context, ref), child: const Text('offer'))),
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [platformCapsProvider.overrideWithValue(caps)],
      child: MaterialApp.router(routerConfig: router),
    ));
    router.push('/game');
    await tester.pumpAndSettle();
    expect(find.text('offer'), findsOneWidget);
    return router;
  }

  testWidgets('a store offer closes the game and opens the store over Home', (tester) async {
    final store = houseCreatives.firstWhere((c) => c.route == '/store');
    final router = await pumpGame(tester, (context, ref) => leaveGameForCreative(context, ref, store));
    await tester.tap(find.text('offer'));
    await tester.pumpAndSettle();
    expect(find.text('store'), findsOneWidget);
    expect(find.text('offer'), findsNothing);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget, reason: 'closing the store lands on Home, not back in the game');
  });

  testWidgets('a tab offer closes the game and opens that tab', (tester) async {
    final events = houseCreatives.firstWhere((c) => c.route == '/events');
    await pumpGame(tester, (context, ref) => leaveGameForCreative(context, ref, events));
    await tester.tap(find.text('offer'));
    await tester.pumpAndSettle();
    expect(find.text('events'), findsOneWidget);
    expect(find.text('offer'), findsNothing);
  });
}
