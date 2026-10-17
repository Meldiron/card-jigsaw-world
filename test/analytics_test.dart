// Usage analytics (Appwrite Analytics, lib/core/analytics.dart; docs/analytics.md): what is sent,
// and when nothing is (the player's switch, debug builds, QA runs), and screen views from every
// navigator of a router shaped like the app's (root pages over a tab shell, a page inside a tab).
import 'package:appwrite/appwrite.dart';
import 'package:carden/core/analytics.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A client that is never asked for anything (the fake service answers first).
class _NoClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('no network in unit tests');
}

typedef _Sent = ({String name, String url, Map<String, String> props, int? engagementTime});

/// Records every event instead of sending it.
class _FakeAnalytics extends Analytics {
  _FakeAnalytics() : super(_NoClient());
  final sent = <_Sent>[];

  List<String> get names => [for (final e in sent) e.name];
  List<String> get screens => [for (final e in sent) if (e.name == 'screen_view') e.props['screen']!];

  @override
  Future createEvent({
    required String propertyId,
    required String name,
    required String url,
    String? domain,
    String? referrer,
    int? screenWidth,
    String? sessionHash,
    int? scrollDepth,
    int? engagementTime,
    List<String>? props,
    String? userId,
    String? ip,
    String? userAgent,
  }) async {
    expect(propertyId, AppAnalytics.trackingId);
    expect(userId, isNull, reason: 'the app never names a player');
    final list = props ?? const <String>[];
    sent.add((name: name, url: url, props: {for (var i = 0; i + 1 < list.length; i += 2) list[i]: list[i + 1]}, engagementTime: engagementTime));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeAnalytics fake;
  setUp(() => fake = _FakeAnalytics());
  tearDown(AppAnalytics.debugReset);

  group('sending', () {
    test('an event goes to the Carden property with its props as text, null ones left out', () {
      AppAnalytics.debugAttach(fake);
      AppAnalytics.event('tool_used', {'tool': 'hint', 'paid': 'stock', 'giant': false, 'cards': null});
      expect(fake.sent.single.name, 'tool_used');
      expect(fake.sent.single.props, {'tool': 'hint', 'paid': 'stock', 'giant': 'false'});
    });

    test('Share usage data off sends nothing, and on again sends', () {
      AppAnalytics.debugAttach(fake, shareUsage: false);
      AppAnalytics.event('puzzle_started');
      expect(fake.sent, isEmpty);
      AppAnalytics.shareUsage = true;
      AppAnalytics.event('puzzle_started');
      expect(fake.names, ['puzzle_started']);
      AppAnalytics.shareUsage = false;
      AppAnalytics.event('puzzle_completed');
      expect(fake.names, ['puzzle_started']);
    });

    test('lifecycle events follow the switch: off stops them at once', () {
      AppAnalytics.debugAttach(fake);
      final binding = TestWidgetsFlutterBinding.instance;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(fake.names, ['app_backgrounded']);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(fake.names, ['app_backgrounded', 'app_foregrounded']);
      AppAnalytics.shareUsage = false;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(fake.names, ['app_backgrounded', 'app_foregrounded']);
    });

    test('debug builds (the tests run as one) send nothing', () {
      AppAnalytics.debugAttach(fake, build: null);
      expect(AppAnalytics.sending, isFalse);
      AppAnalytics.event('puzzle_started');
      expect(fake.sent, isEmpty);
    });

    test('only release builds outside QA runs send, unless forced with CJW_ANALYTICS', () {
      expect(AppAnalytics.buildSends(release: true, qa: false, forced: false), isTrue);
      expect(AppAnalytics.buildSends(release: true, qa: true, forced: false), isFalse, reason: 'QA runs (CJW_QA)');
      expect(AppAnalytics.buildSends(release: false, qa: false, forced: false), isFalse, reason: 'debug and profile builds');
      expect(AppAnalytics.buildSends(release: false, qa: true, forced: true), isTrue, reason: 'a deliberate verification run');
      expect(AppAnalytics.forced, isFalse, reason: 'never set for the unit tests');
    });

    test('nothing is attached until the app attaches its client: no observers, no events', () {
      expect(AppAnalytics.observers(), isEmpty);
      AppAnalytics.event('puzzle_started');
      expect(AppAnalytics.sending, isFalse);
    });

    test('the switch is a setting, on by default and kept on the device', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final container = ProviderContainer(overrides: [localStoreProvider.overrideWithValue(store)]);
      addTearDown(container.dispose);
      expect(container.read(settingsProvider).shareUsage, isTrue);
      expect(AppAnalytics.shareUsage, isTrue);
      container.read(settingsProvider.notifier).setShareUsage(false);
      expect(AppAnalytics.shareUsage, isFalse);
      expect(store.shareUsage, isFalse);
      // The next launch reads it before anything is sent.
      AppAnalytics.shareUsage = true;
      final next = ProviderContainer(overrides: [localStoreProvider.overrideWithValue(store)]);
      addTearDown(next.dispose);
      expect(next.read(settingsProvider).shareUsage, isFalse);
      expect(AppAnalytics.shareUsage, isFalse);
    });

    test('accessibility changes are reported, one event per option changed', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final container = ProviderContainer(overrides: [localStoreProvider.overrideWithValue(store)]);
      addTearDown(container.dispose);
      container.read(settingsProvider);
      AppAnalytics.debugAttach(fake);
      final n = container.read(settingsProvider.notifier);
      n.setAccessibility(const Accessibility(textSize: TextSize.largest, reduceMotion: true));
      expect(fake.sent.map((e) => e.props), [
        {'setting': 'text_size', 'value': 'largest'},
        {'setting': 'reduce_motion', 'value': 'true'},
      ]);
    });
  });

  group('screen names', () {
    test('every path of the app has a readable name, never an id', () {
      expect(screenNameFor('/library/pack/:packId'), 'pack');
      expect(screenNameFor('/play/:puzzleId'), 'play_setup');
      expect(screenNameFor('/game/:puzzleId/:grid'), 'game');
      expect(screenNameFor('/player/:userId'), 'player');
      expect(screenNameFor('/events'), 'quests');
      expect(screenNameFor('/profile/my-puzzles'), 'my_puzzles');
      for (final name in screenNames.values) {
        expect(name, matches(RegExp(r'^[a-z_]+$')));
      }
    });

    test('a route added later is named after its last fixed part', () {
      expect(screenNameFor('/join/:code'), 'join');
      expect(screenNameFor('/profile/some-page'), 'some_page');
      expect(screenNameFor(null), 'home');
    });
  });

  testWidgets('screen views from the root navigator and every tab, none for sheets', (tester) async {
    AppAnalytics.debugAttach(fake);
    Page<void> page(Widget child, GoRouterState s) => CupertinoPage<void>(key: s.pageKey, name: screenNameFor(s.fullPath), child: child);
    Widget screen(String text) => Scaffold(body: Center(child: Text(text)));
    final rootKey = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: rootKey,
      initialLocation: '/home',
      observers: AppAnalytics.observers(),
      routes: [
        StatefulShellRoute.indexedStack(
          notifyRootObserver: false,
          builder: (context, state, shell) {
            AppAnalytics.showTab(shell.currentIndex);
            return Scaffold(body: shell);
          },
          branches: [
            StatefulShellBranch(observers: AppAnalytics.observers(tab: 0), routes: [GoRoute(path: '/home', pageBuilder: (c, s) => page(screen('Home page'), s))]),
            StatefulShellBranch(observers: AppAnalytics.observers(tab: 1), routes: [
              GoRoute(
                path: '/library',
                pageBuilder: (c, s) => page(screen('Library page'), s),
                routes: [GoRoute(path: 'pack/:packId', pageBuilder: (c, s) => page(screen('Pack ${s.pathParameters['packId']}'), s))],
              ),
            ]),
          ],
        ),
        GoRoute(path: '/play/:puzzleId', parentNavigatorKey: rootKey, pageBuilder: (c, s) => page(screen('Setup'), s)),
        GoRoute(path: '/game/:puzzleId/:grid', parentNavigatorKey: rootKey, pageBuilder: (c, s) => page(screen('Game'), s)),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(fake.screens, ['home']);

    router.go('/library');
    await tester.pumpAndSettle();
    router.go('/library/pack/pack-tropical-beaches');
    await tester.pumpAndSettle();
    expect(fake.screens, ['home', 'library', 'pack']);

    // Back to a tab seen before: its navigator does not change, the shell reports it.
    router.go('/home');
    await tester.pumpAndSettle();
    expect(fake.screens.last, 'home');
    expect(fake.sent.last.props['trigger'], 'tab');

    // A page above the tabs, then one replacing it, then back to the tab under them.
    router.push('/play/p-1');
    await tester.pumpAndSettle();
    expect(fake.sent.last.props, {'screen': 'play_setup', 'trigger': 'push', 'previous': 'home'});
    router.pushReplacement('/game/p-1/4x4');
    await tester.pumpAndSettle();
    expect(fake.screens.last, 'game');

    // A sheet over the game opens and closes: not a screen, and the game is not counted again.
    final before = fake.sent.length;
    showModalBottomSheet<void>(context: rootKey.currentContext!, builder: (_) => const SizedBox(height: 200, child: Text('Pause')));
    await tester.pumpAndSettle();
    Navigator.of(rootKey.currentContext!).pop();
    await tester.pumpAndSettle();
    expect(fake.sent.length, before);

    router.pop();
    await tester.pumpAndSettle();
    expect(fake.screens.last, 'home');
    expect(fake.sent.last.props['previous'], 'game');

    // The Library tab comes back on the page it was left on.
    router.go('/library/pack/pack-tropical-beaches');
    await tester.pumpAndSettle();
    expect(fake.screens.last, 'pack');

    expect(fake.screens, everyElement(isIn(screenNames.values)));
    for (final e in fake.sent) {
      expect(e.url, isNot(contains('p-1')), reason: 'no ids in the address');
      expect(e.url, isNot(contains('pack-tropical-beaches')));
      expect(e.props.values, isNot(contains('p-1')));
    }
  });
}
