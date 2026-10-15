// Links into the game (docs/deep-links.md): the web address, the cardjigsaw:// scheme and the bare
// path read the same (AppLink.parse); the apple-app-site-association file sends every one of them
// to the iPhone app and keeps the web sign-in in the browser; DeepLinks puts each kind on screen.
import 'dart:convert';
import 'dart:io';

import 'package:appwrite/models.dart' as models;
import 'package:card_jigsaw_world/core/app_links.dart';
import 'package:card_jigsaw_world/core/theme/app_theme.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/features/gallery/library_screen.dart';
import 'package:card_jigsaw_world/features/links/deep_links.dart';
import 'package:card_jigsaw_world/features/onboarding/onboarding_screen.dart';
import 'package:card_jigsaw_world/features/social/social_screen.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/router.dart';
import 'package:card_jigsaw_world/state/auth.dart';
import 'package:card_jigsaw_world/state/catalog.dart';
import 'package:card_jigsaw_world/state/profile.dart';
import 'package:card_jigsaw_world/state/progress.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:card_jigsaw_world/state/social.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppLink? _parse(String s) => AppLink.parse(Uri.parse(s));

/// Every link form the game answers, with what it opens (kind and route).
const _links = <String, (LinkKind, String)>{
  '/': (LinkKind.page, '/home'),
  '/home': (LinkKind.page, '/home'),
  '/library': (LinkKind.page, '/library'),
  '/library?filter=Giant': (LinkKind.page, '/library?filter=Giant'),
  '/library/pack/pack-owls': (LinkKind.page, '/library/pack/pack-owls'),
  '/pack/pack-owls': (LinkKind.page, '/library/pack/pack-owls'),
  '/packs/pack-owls': (LinkKind.page, '/library/pack/pack-owls'),
  '/play/abc123': (LinkKind.overlay, '/play/abc123'),
  '/play/abc123?grid=hexagons-5x6&utm_source=x': (LinkKind.overlay, '/play/abc123?grid=hexagons-5x6'),
  '/picture/abc123': (LinkKind.overlay, '/play/abc123'),
  '/puzzle/abc123': (LinkKind.overlay, '/play/abc123'),
  '/game/abc123/4x5': (LinkKind.overlay, '/play/abc123?grid=4x5'),
  '/events': (LinkKind.page, '/events'),
  '/quests': (LinkKind.page, '/events'),
  '/social': (LinkKind.page, '/social'),
  '/leaderboard': (LinkKind.page, '/social'),
  '/league': (LinkKind.page, '/social'),
  '/friends': (LinkKind.page, '/social?tab=friends'),
  '/social?tab=friends': (LinkKind.page, '/social?tab=friends'),
  '/add-friend': (LinkKind.action, '/add-friend'),
  '/add-friend?code=6acbbf8a8898f585d3ca': (LinkKind.action, '/add-friend?code=6acbbf8a8898f585d3ca'),
  '/friend': (LinkKind.action, '/add-friend'),
  '/friend/6acbbf8a8898f585d3ca': (LinkKind.action, '/add-friend?code=6acbbf8a8898f585d3ca'),
  '/profile': (LinkKind.page, '/profile'),
  '/profile/settings': (LinkKind.page, '/profile/settings'),
  '/profile/account': (LinkKind.overlay, '/account'),
  '/profile/my-puzzles': (LinkKind.page, '/profile/my-puzzles'),
  '/settings': (LinkKind.page, '/profile/settings'),
  '/my-puzzles': (LinkKind.page, '/profile/my-puzzles'),
  '/account': (LinkKind.overlay, '/account'),
  '/sign-in': (LinkKind.overlay, '/account'),
  '/player/6acbbf8a8898f585d3ca': (LinkKind.overlay, '/player/6acbbf8a8898f585d3ca'),
  '/user/6acbbf8a8898f585d3ca': (LinkKind.overlay, '/player/6acbbf8a8898f585d3ca'),
  '/store': (LinkKind.overlay, '/store'),
  '/store?vip=1': (LinkKind.overlay, '/store?vip=1'),
  '/shop': (LinkKind.overlay, '/store'),
  '/vip': (LinkKind.overlay, '/store?vip=1'),
  '/wheel': (LinkKind.overlay, '/wheel'),
  '/lucky-wheel': (LinkKind.overlay, '/wheel'),
  '/redeem': (LinkKind.action, '/redeem'),
  '/redeem?code=ABCD-EFGH-JKLM-NPQR': (LinkKind.action, '/redeem?code=ABCD-EFGH-JKLM-NPQR'),
  '/redeem/ABCD-EFGH-JKLM-NPQR': (LinkKind.action, '/redeem?code=ABCD-EFGH-JKLM-NPQR'),
  '/code': (LinkKind.action, '/redeem'),
  '/code/abcdefghjklmnpqr': (LinkKind.action, '/redeem?code=abcdefghjklmnpqr'),
  '/daily': (LinkKind.action, '/daily'),
  '/today': (LinkKind.action, '/daily'),
  '/quick': (LinkKind.action, '/quick'),
  '/quick-play': (LinkKind.action, '/quick'),
  '/gift': (LinkKind.action, '/gift'),
  '/daily-gift': (LinkKind.action, '/gift'),
  '/piggy': (LinkKind.action, '/piggy'),
  '/piggy-bank': (LinkKind.action, '/piggy'),
};

/// Apple's component pattern: `*` any run of characters, `?` one character.
bool _matches(String pattern, String path) =>
    RegExp('^${pattern.split('').map((ch) => ch == '*' ? '.*' : ch == '?' ? '.' : RegExp.escape(ch)).join()}\$').hasMatch(path);

void main() {
  group('AppLink.parse', () {
    test('every link reads to its screen', () {
      for (final MapEntry(key: input, value: (kind, location)) in _links.entries) {
        final link = _parse(input);
        expect(link, isNotNull, reason: input);
        expect(link!.kind, kind, reason: input);
        expect(link.location.toString(), location, reason: input);
      }
    });

    test('the web address, the app scheme and the bare path agree', () {
      for (final input in _links.keys) {
        final bare = _parse(input);
        final web = _parse('${AppLink.webOrigin}$input');
        final app = _parse('cardjigsaw:/$input');
        final appSlash = _parse('cardjigsaw://$input');
        expect(web, bare, reason: 'web $input');
        expect(app, bare, reason: 'cardjigsaw:/$input');
        expect(appSlash, bare, reason: 'cardjigsaw://$input');
        // Sharing round trips: the address a link shares opens the same screen.
        expect(_parse(bare!.webUrl.toString()), bare, reason: 'webUrl $input');
        expect(_parse(bare.appUrl.toString()), bare, reason: 'appUrl $input');
      }
    });

    test('links already in use: the widget and the In-App Events', () {
      expect(_parse('cardjigsaw://play/abc123'), _parse('/play/abc123'));
      expect(_parse('cardjigsaw://library/pack/evpack-coffee-2026')!.location.toString(), '/library/pack/evpack-coffee-2026');
      expect(_parse('cardjigsaw://')!.location.toString(), '/home');
      expect(_parse('CardJigsaw://Store')!.location.toString(), '/store');
    });

    test('ids keep their case; keywords do not care', () {
      expect(_parse('/PLAYER/AbC123')!.location.toString(), '/player/AbC123');
      expect(_parse('/Library/Pack/Pack-Owls')!.location.toString(), '/library/pack/Pack-Owls');
    });

    test('what is not a game link', () {
      for (final input in [
        'appwrite-callback-6acb4de5003e38d5ebd9://auth?secret=x',
        'mailto:someone@example.com',
        '/auth/callback?userId=u&secret=s',
        '/welcome',
        '/main.dart.js',
        '/assets/fonts/x.ttf',
        '/app-version.json',
        '/.well-known/apple-app-site-association',
        '/library/pack',
        '/library/pack/a/b',
        '/play',
        '/play/a/b',
        '/play/${'x' * 65}',
        '/play/bad%20id',
        '/player/%3Cscript%3E',
        '/store/extra',
      ]) {
        expect(_parse(input), isNull, reason: input);
      }
      // A code too long to be one opens the empty code sheet.
      expect(_parse('/redeem/${'X' * 65}')!.location.toString(), '/redeem');
    });
  });

  group('apple-app-site-association', () {
    final aasa = jsonDecode(File('web/.well-known/apple-app-site-association').readAsStringSync()) as Map<String, dynamic>;
    final details = (aasa['applinks']['details'] as List).single as Map<String, dynamic>;
    final components = (details['components'] as List).cast<Map<String, dynamic>>();

    /// The first component that matches decides, as on iPhone.
    bool opensApp(String path) {
      for (final c in components) {
        if (_matches(c['/'] as String, path)) return c['exclude'] != true;
      }
      return false;
    }

    test('names the app', () {
      expect(details['appIDs'], ['C24QP73SQM.com.matejbaco.cardjigsawworld']);
    });

    test('every link opens the app', () {
      for (final input in _links.keys) {
        final path = Uri.parse(input).path;
        expect(opensApp(path), isTrue, reason: path);
      }
    });

    test('the web sign-in callback, site files and unknown paths stay in the browser', () {
      for (final path in ['/auth/callback', '/main.dart.js', '/flutter_bootstrap.js', '/assets/x.png', '/app-version.json', '/canvaskit/canvaskit.wasm', '/welcome']) {
        expect(opensApp(path), isFalse, reason: path);
      }
    });

    test('every component the file lists is a link the app reads', () {
      for (final c in components.where((c) => c['exclude'] != true)) {
        final sample = (c['/'] as String).replaceAll('*', 'abc123');
        expect(_parse(sample), isNotNull, reason: c['/'] as String);
      }
    });
  });

  group('DeepLinks', () {
    final packs = [
      Pack.fromRow('free', {'name': 'Free pack', 'category': 'Nature', 'imageCount': 2, 'isFree': true}),
      Pack.fromRow('owls', {'name': 'Owls', 'category': 'Animals', 'imageCount': 2, 'isFree': false, 'priceCoins': 2000}),
    ];
    final now = DateTime.now();
    final pictures = [
      Puzzle.fromRow('free-1', {'packId': 'free', 'title': 'Fields', 'imageUrl': 'https://example.invalid/1.jpg', 'date': DateTime(now.year, now.month, now.day).toIso8601String()}),
      Puzzle.fromRow('free-2', {'packId': 'free', 'title': 'Hills', 'imageUrl': 'https://example.invalid/2.jpg'}),
      Puzzle.fromRow('owls-1', {'packId': 'owls', 'title': 'Barn owl', 'imageUrl': 'https://example.invalid/3.jpg'}),
    ];

    Future<(ProviderContainer, GoRouter)> pump(WidgetTester tester, {bool onboarded = true}) async {
      SharedPreferences.setMockInitialValues({'onboarded': onboarded});
      final store = await LocalStore.open();
      Widget page(String name) => Scaffold(body: Center(child: Text(name)));
      GoRoute route(String path, [List<RouteBase> routes = const []]) =>
          GoRoute(path: path, builder: (_, s) => page(s.uri.toString()), routes: routes);
      final router = GoRouter(
        navigatorKey: rootNavigatorKey,
        initialLocation: onboarded ? '/home' : '/welcome',
        routes: [
          route('/welcome'),
          route('/home'),
          route('/library', [route('pack/:packId')]),
          route('/events'),
          route('/social'),
          route('/profile', [route('settings'), route('my-puzzles')]),
          route('/play/:puzzleId'),
          route('/store'),
          route('/wheel'),
          route('/account'),
          route('/player/:userId'),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          routerProvider.overrideWithValue(router),
          authProvider.overrideWith(_NoAuth.new),
          profileProvider.overrideWith(_GuestProfile.new),
          progressProvider.overrideWith(_NoRows.new),
          packsProvider.overrideWith((ref) async => packs),
          allPuzzlesProvider.overrideWith((ref) async => pictures),
        ],
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ));
      await tester.pumpAndSettle();
      return (ProviderScope.containerOf(tester.element(find.byType(Scaffold).first)), router);
    }

    // A link that opens a sheet finishes when the sheet closes: pump until it is done or on screen.
    Future<void> open(WidgetTester tester, ProviderContainer container, String link) async {
      var done = false;
      container.read(deepLinksProvider).show(_parse(link)!).whenComplete(() => done = true);
      for (var i = 0; i < 30 && !done; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    String top(GoRouter router) => router.state.uri.toString();

    testWidgets('a page above the tabs opens on Home, once, even from the welcome screens', (tester) async {
      final (container, router) = await pump(tester, onboarded: false);
      expect(top(router), '/welcome');
      await open(tester, container, '/store');
      expect(container.read(settingsProvider).onboarded, isTrue);
      expect(top(router), '/store');
      await open(tester, container, '/store');
      router.pop();
      await tester.pumpAndSettle();
      expect(top(router), '/home');
    });

    testWidgets('a plain Home link leaves a new player on the welcome screens', (tester) async {
      final (container, router) = await pump(tester, onboarded: false);
      await open(tester, container, 'cardjigsaw://');
      expect(top(router), '/welcome');
      expect(container.read(settingsProvider).onboarded, isFalse);
    });

    testWidgets('pages replace what is on screen; their query sets the screen', (tester) async {
      final (container, router) = await pump(tester);
      await open(tester, container, '/pack/owls');
      expect(top(router), '/library/pack/owls');
      await open(tester, container, '/library?filter=animals');
      expect(top(router), '/library');
      expect(container.read(libraryFilterProvider), 'Animals');
      await open(tester, container, '/library?filter=finished');
      expect(container.read(libraryFilterProvider), LibraryFilter.finished);
      await open(tester, container, '/friends');
      expect(top(router), '/social');
      expect(container.read(socialTabProvider), SocialTab.friends);
      await open(tester, container, '/quests');
      expect(top(router), '/events');
    });

    testWidgets('a picture opens when the player has its pack, else its pack shows', (tester) async {
      final (container, router) = await pump(tester);
      await open(tester, container, '/play/owls-1');
      expect(top(router), '/library/pack/owls', reason: 'Owls is not unlocked: its price shows, not a free board');
      await open(tester, container, '/play/free-2?grid=4x5');
      expect(top(router), '/play/free-2?grid=4x5');
      router.pop();
      await tester.pumpAndSettle();
      expect(top(router), '/library/pack/owls', reason: 'it opened above what was on screen');
      await open(tester, container, '/play/unknown-id');
      expect(top(router), '/play/unknown-id', reason: 'the picture screen says it is not available');
    });

    testWidgets("today's picture and Quick play", (tester) async {
      final (container, router) = await pump(tester);
      await open(tester, container, '/daily');
      expect(top(router), '/play/free-1');
      router.go('/home');
      await tester.pumpAndSettle();
      await open(tester, container, '/quick');
      expect(top(router), startsWith('/play/free-'));
      expect(top(router), contains('from=quick'));
    });

    testWidgets('a pack code link opens the code sheet with the code filled in', (tester) async {
      final (container, router) = await pump(tester);
      await open(tester, container, '/redeem/abcdefghjklmnpqr');
      expect(top(router), '/home');
      final field = tester.widget<CupertinoTextField>(find.byKey(const ValueKey('redeem-code-field')));
      expect(field.controller!.text, 'ABCD-EFGH-JKLM-NPQR');
    });

    testWidgets('a friend link opens Social > Friends with the code filled in', (tester) async {
      final (container, router) = await pump(tester);
      await open(tester, container, '/add-friend?code=6acbbf8a8898f585d3ca');
      expect(top(router), '/social');
      expect(container.read(socialTabProvider), SocialTab.friends);
      expect(find.text('Add friend by code'), findsOneWidget);
      final field = tester.widget<CupertinoTextField>(find.byKey(const ValueKey('add-friend-field')));
      expect(field.controller!.text, '6acbbf8a8898f585d3ca');
    });
  });

  group('routerProvider', () {
    testWidgets('one router: a link counts as onboarding, and a deleted account goes back to the welcome screens', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          authProvider.overrideWith(_NoAuth.new),
          profileProvider.overrideWith(_GuestProfile.new),
          packsProvider.overrideWith((ref) async => const <Pack>[]),
          playerProfileProvider.overrideWith((ref, id) async => null),
        ],
        child: Consumer(builder: (context, ref, _) => MaterialApp.router(theme: AppTheme.light(), routerConfig: ref.watch(routerProvider))),
      ));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(OnboardingScreen)));
      final router = container.read(routerProvider);
      expect(router.state.uri.toString(), '/welcome');

      // A mistyped address is not a link: the welcome screens stay.
      router.go('/no-such-page');
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).onboarded, isFalse);
      expect(router.state.uri.toString(), '/welcome');

      router.go('/player/6acbbf8a8898f585d3ca');
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).onboarded, isTrue);
      expect(container.read(routerProvider), same(router), reason: 'not rebuilt: the link keeps its screen');
      expect(router.state.uri.toString(), '/player/6acbbf8a8898f585d3ca');
      expect(find.text('Player not found'), findsOneWidget);

      // AccountDeletion.startOver: the flag goes back to false and the settings are read again.
      store.onboarded = false;
      container.invalidate(settingsProvider);
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), '/welcome');
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });
  });
}

class _NoAuth extends AuthNotifier {
  @override
  Future<models.User?> build() async => null;
}

class _GuestProfile extends ProfileNotifier {
  @override
  Future<Profile> build() async => Profile.guest('local');
}

class _NoRows extends ProgressNotifier {
  @override
  Future<Map<String, PuzzleProgress>> build() async => const {};
}
