// Links into the game (docs/deep-links.md): the web address, the carden:// scheme and the bare
// path read the same (AppLink.parse); the apple-app-site-association file sends every one of them
// to the iPhone app and keeps the web sign-in in the browser; DeepLinks puts each kind on screen.
import 'dart:convert';
import 'dart:io';

import 'package:appwrite/models.dart' as models;
import 'package:carden/core/app_links.dart';
import 'package:carden/core/links.dart';
import 'package:carden/core/platform.dart';
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/data/coop_repository.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/gallery/library_screen.dart';
import 'package:carden/features/links/deep_links.dart';
import 'package:carden/features/onboarding/onboarding_screen.dart';
import 'package:carden/features/social/social_screen.dart';
import 'package:carden/models/models.dart';
import 'package:carden/router.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/coop/coop_controller.dart';
import 'package:carden/state/coop/coop_models.dart';
import 'package:carden/state/inbox.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/progress.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/social.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_coop.dart';

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
  '/inbox': (LinkKind.page, '/social?tab=inbox'),
  '/messages': (LinkKind.page, '/social?tab=inbox'),
  '/social?tab=inbox': (LinkKind.page, '/social?tab=inbox'),
  '/inbox?message=6ad35c7d000375999a49': (LinkKind.action, '/inbox?message=6ad35c7d000375999a49'),
  '/inbox/6ad35c7d000375999a49': (LinkKind.action, '/inbox?message=6ad35c7d000375999a49'),
  '/messages/6ad35c7d000375999a49': (LinkKind.action, '/inbox?message=6ad35c7d000375999a49'),
  '/inbox?message=bad%20id': (LinkKind.page, '/social?tab=inbox'),
  '/feedback': (LinkKind.action, '/feedback'),
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
  '/join/K7QH2MXP': (LinkKind.action, '/join/K7QH2MXP'),
  '/join/k7qh-2mxp': (LinkKind.action, '/join/K7QH2MXP'),
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
        final app = _parse('carden:/$input');
        final appSlash = _parse('carden://$input');
        final legacy = _parse('cardjigsaw://$input');
        final oldSite = _parse('https://card-jigsaw-world.appwrite.network$input');
        final firstCarden = _parse('https://carden.appwrite.network$input');
        expect(web, bare, reason: 'web $input');
        expect(app, bare, reason: 'carden:/$input');
        expect(appSlash, bare, reason: 'carden://$input');
        expect(legacy, bare, reason: 'cardjigsaw://$input (the first name)');
        expect(oldSite, bare, reason: 'the old web address $input');
        expect(firstCarden, bare, reason: 'the first Carden web address $input');
        // Sharing round trips: the address a link shares opens the same screen.
        expect(_parse(bare!.webUrl.toString()), bare, reason: 'webUrl $input');
        expect(_parse(bare.appUrl.toString()), bare, reason: 'appUrl $input');
      }
    });

    test('links already in use: the widget and the In-App Events', () {
      expect(_parse('carden://play/abc123'), _parse('/play/abc123'));
      expect(_parse('carden://library/pack/evpack-coffee-2026')!.location.toString(), '/library/pack/evpack-coffee-2026');
      expect(_parse('carden://')!.location.toString(), '/home');
      expect(_parse('Carden://Store')!.location.toString(), '/store');
      // Links made while the game was Card Jigsaw World.
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
        '/inbox/a/b',
        '/inbox/bad%20id',
        '/join',
        '/join/K7QH2MX',
        '/join/K7QH2MX0',
        '/join/a/b',
      ]) {
        expect(_parse(input), isNull, reason: input);
      }
      // A code too long to be one opens the empty code sheet.
      expect(_parse('/redeem/${'X' * 65}')!.location.toString(), '/redeem');
    });
  });

  test('the invite page offers the same Get Carden link as the app', () {
    final html = File('web/index.html').readAsStringSync();
    expect(RegExp(r"var GET_CARDEN = '([^']+)'").firstMatch(html)?.group(1), AppLinks.getCarden.toString());
    expect(html.contains("flutter_bootstrap.js' async") || html.contains('<script src="flutter_bootstrap.js"'), isFalse,
        reason: 'the game loads from the invite script, so an invite opened in the app never loads it in the browser too');
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

    /// Pack codes are redeemed on the web only: their links stay in the browser.
    bool isPackCode(String path) => path == '/redeem' || path == '/code' || path.startsWith('/redeem/') || path.startsWith('/code/');

    test('every link opens the app, except pack codes', () {
      for (final input in _links.keys) {
        final path = Uri.parse(input).path;
        expect(opensApp(path), !isPackCode(path), reason: path);
      }
    });

    test('pack code links stay in the browser', () {
      for (final path in ['/redeem', '/redeem/ABCD-EFGH-JKLM-NPQR', '/code', '/code/abcdefghjklmnpqr']) {
        expect(opensApp(path), isFalse, reason: path);
      }
    });

    test('the web sign-in callback, site files and unknown paths stay in the browser', () {
      for (final path in ['/auth/callback', '/main.dart.js', '/flutter_bootstrap.js', '/assets/x.png', '/app-version.json', '/canvaskit/canvaskit.wasm', '/welcome']) {
        expect(opensApp(path), isFalse, reason: path);
      }
    });

    test('every component the file lists is a link the app reads', () {
      for (final c in components.where((c) => c['exclude'] != true)) {
        // An invite's code is 8 characters of its own alphabet.
        final sample = (c['/'] as String).replaceAll('*', c['/'] == '/join/*' ? 'K7QH2MXP' : 'abc123');
        expect(_parse(sample), isNotNull, reason: c['/'] as String);
      }
    });
  });

  group('DeepLinks', () {
    final packs = [
      Pack.fromRow('free', {'name': 'Free pack', 'category': 'Nature', 'imageCount': 2, 'isFree': true}),
      Pack.fromRow('owls', {'name': 'Owls', 'category': 'Animals', 'imageCount': 2, 'isFree': false, 'priceCoins': 2000}),
      Pack.fromRow('houses', {'name': 'Colourful Houses', 'category': 'Giant', 'imageCount': 1, 'isFree': true}),
    ];
    final now = DateTime.now();
    final pictures = [
      Puzzle.fromRow('free-1', {'packId': 'free', 'title': 'Fields', 'imageUrl': 'https://example.invalid/1.jpg', 'date': DateTime(now.year, now.month, now.day).toIso8601String()}),
      Puzzle.fromRow('free-2', {'packId': 'free', 'title': 'Hills', 'imageUrl': 'https://example.invalid/2.jpg'}),
      Puzzle.fromRow('owls-1', {'packId': 'owls', 'title': 'Barn owl', 'imageUrl': 'https://example.invalid/3.jpg'}),
      Puzzle.fromRow('houses-1', {'packId': 'houses', 'title': 'Canal houses', 'imageUrl': 'https://example.invalid/4.jpg'}),
    ];

    Future<(ProviderContainer, GoRouter)> pump(WidgetTester tester, {bool onboarded = true, PlatformCaps caps = PlatformCaps.ios, FakeCoopServer? coop, List<InboxMessage> messages = const []}) async {
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
          route('/game/:puzzleId/:grid'),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          platformCapsProvider.overrideWithValue(caps),
          localStoreProvider.overrideWithValue(store),
          routerProvider.overrideWithValue(router),
          authProvider.overrideWith(_NoAuth.new),
          profileProvider.overrideWith(_GuestProfile.new),
          progressProvider.overrideWith(_NoRows.new),
          packsProvider.overrideWith((ref) async => packs),
          allPuzzlesProvider.overrideWith((ref) async => pictures),
          inboxMessagesProvider.overrideWith((ref) async => messages),
          currentUserIdProvider.overrideWithValue('guest-1'),
          coopBackendProvider.overrideWithValue(FakeCoopBackend(coop ?? FakeCoopServer(), 'guest-1')),
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
      await open(tester, container, 'carden://');
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
      await open(tester, container, '/library?filter=event');
      expect(container.read(libraryFilterProvider), LibraryFilter.all, reason: 'events have no Library chip');
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
      await open(tester, container, '/play/houses-1');
      expect(top(router), '/library/pack/houses', reason: 'giant boards open at level 10: the pack shows the gate');
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

    testWidgets('on the web a pack code link opens the code sheet with the code filled in', (tester) async {
      final (container, router) = await pump(tester, caps: PlatformCaps.web);
      await open(tester, container, '/redeem/abcdefghjklmnpqr');
      expect(top(router), '/home');
      final field = tester.widget<CupertinoTextField>(find.byKey(const ValueKey('redeem-code-field')));
      expect(field.controller!.text, 'ABCD-EFGH-JKLM-NPQR');
    });

    testWidgets('on iPhone a pack code link only opens Home: codes are redeemed on the web', (tester) async {
      final (container, router) = await pump(tester);
      router.go('/library');
      await tester.pumpAndSettle();
      await open(tester, container, '/redeem/abcdefghjklmnpqr');
      await tester.pumpAndSettle();
      expect(top(router), '/library', reason: 'a code link on iPhone does not move the player');
      expect(find.byKey(const ValueKey('redeem-code-field')), findsNothing);
      expect(find.text('Redeem a pack code'), findsNothing);
    });

    testWidgets("a gift notification's link opens its message in Social > Inbox", (tester) async {
      final now = DateTime.now();
      final gift = InboxMessage(
        id: 'm1',
        subject: 'Anna sent you a gift',
        body: 'Anna sent you 1 ticket. Claim it within 24 hours.',
        sentAt: now.subtract(const Duration(minutes: 1)),
        expiresAt: now.add(const Duration(hours: 24)),
        tickets: 1,
        fromUserId: 'u-anna',
        fromName: 'Anna',
      );
      final (container, router) = await pump(tester, messages: [gift]);
      router.go('/library');
      await tester.pumpAndSettle();
      await open(tester, container, '/inbox?message=m1');
      expect(top(router), '/social');
      expect(container.read(socialTabProvider), SocialTab.inbox);
      expect(find.byKey(const ValueKey('message-sheet-m1')), findsOneWidget);
      expect(find.text('A gift from Anna'), findsOneWidget);
      expect(find.byKey(const ValueKey('message-claim')), findsOneWidget);
    });

    testWidgets('an invite from a fresh install opens the shared board above the welcome pages', (tester) async {
      final server = FakeCoopServer();
      final game = CoopGame.fromMap(server.handle('host-1', 'create', {'puzzleId': 'free-2', 'grid': 'cards-3x3t0', 'layout': [1, 2, 0, 4, 5, 3, 7, 8, 6]}));
      final (container, router) = await pump(tester, onboarded: false, coop: server);
      container.read(deepLinksProvider).show(_parse('/join/${game.code}')!);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(top(router), '/game/free-2/cards-3x3t0?coop=${game.id}');
      expect(container.read(settingsProvider).onboarded, isFalse, reason: 'the welcome pages begin after the game');
      expect(container.read(coopProvider).game?.id, game.id);
      expect(server.games[game.id]!['players'], ['host-1', 'guest-1', '', '', '']);
      router.pop();
      await tester.pumpAndSettle();
      expect(top(router), '/welcome');
      container.read(coopProvider.notifier).clear();
    });

    testWidgets('an invite to a full game says so', (tester) async {
      final server = FakeCoopServer();
      final game = CoopGame.fromMap(server.handle('host-1', 'create', {'puzzleId': 'free-2', 'grid': 'cards-3x3t0', 'layout': [1, 2, 0, 4, 5, 3, 7, 8, 6]}));
      for (final id in ['b', 'c', 'd', 'e']) {
        server.handle(id, 'join', {'code': game.code});
      }
      final (container, router) = await pump(tester, coop: server);
      container.read(deepLinksProvider).show(_parse('/join/${game.code}')!);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('This game is full'), findsOneWidget);
      expect(top(router), '/home');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
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
          // The welcome pages load the first board's picture from the catalogue.
          allPuzzlesProvider.overrideWith((ref) async => const <Puzzle>[]),
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
