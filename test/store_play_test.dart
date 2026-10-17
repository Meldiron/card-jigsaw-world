// Store > Earn for free > Play a puzzle (owner feedback, 2026-10-17): the first free way closes the
// Store and starts Quick play; in the guided start, before Quick play opens, it opens the picture Home
// suggests, or Home itself.
import 'dart:io' show Directory;

import 'package:appwrite/appwrite.dart';
import 'package:carden/core/app_links.dart';
import 'package:carden/core/platform.dart';
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/data/purchases.dart';
import 'package:carden/features/links/deep_links.dart';
import 'package:carden/features/store/store_screen.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/purchases.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _GuestProfile extends ProfileNotifier {
  @override
  Future<Profile> build() async => Profile.guest('local');
}

class _NoStore extends PurchaseService {
  _NoStore() : super(Client());
  @override
  Future<void> start() async {}
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<Map<String, ProductDetails>> queryProducts() async => const {};
}

/// Records the links it is asked to show instead of showing them.
class _Links extends DeepLinks {
  _Links(super.ref);
  final shown = <AppLink>[];
  @override
  Future<void> show(AppLink link) async => shown.add(link);
}

Future<_Links> _pumpStore(WidgetTester tester, {required Set<Reveal> open, NextStep? next}) async {
  SharedPreferences.setMockInitialValues({'onboarded': true});
  final store = await LocalStore.open();
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  late _Links links;
  final router = GoRouter(initialLocation: '/home', routes: [
    GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: Text('Home page'))),
    GoRoute(path: '/library', builder: (_, _) => const Scaffold(body: Text('Library page'))),
    GoRoute(path: '/store', builder: (_, _) => const StoreScreen()),
    GoRoute(path: '/play/:id', builder: (_, s) => Scaffold(body: Text('Picture ${s.pathParameters['id']}'))),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      platformCapsProvider.overrideWithValue(PlatformCaps.ios),
      profileProvider.overrideWith(_GuestProfile.new),
      isGuestProvider.overrideWithValue(true),
      purchaseServiceProvider.overrideWith((ref) => _NoStore()),
      storeAvailableProvider.overrideWith((ref) => false),
      productsProvider.overrideWith((ref) => const <String, ProductDetails>{}),
      revealsProvider.overrideWithValue(open),
      nextStepProvider.overrideWithValue(next),
      deepLinksProvider.overrideWith((ref) => links = _Links(ref)),
    ],
    child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
  ));
  await tester.pumpAndSettle();
  router.push('/store');
  await tester.pumpAndSettle();
  final row = find.byKey(const ValueKey('store-play-puzzle'));
  await tester.scrollUntilVisible(row, 400, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  // The first way to earn for free, above the daily gift.
  expect(tester.getTopLeft(row).dy, lessThan(tester.getTopLeft(find.text('Daily gift')).dy));
  expect(find.descendant(of: row, matching: find.text('Coins for every picture, more with 3 stars')), findsOneWidget);
  await tester.tap(row);
  await tester.pumpAndSettle();
  // The Store has closed.
  expect(find.byType(StoreScreen), findsNothing);
  return links;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    // The Appwrite IO client asks path_provider for its cookie jar folder.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.createTempSync('cjw-test').path,
    );
  }

  testWidgets('Play a puzzle starts Quick play, as on Home', (tester) async {
    final links = await _pumpStore(tester, open: Reveal.values.toSet());
    expect(links.shown, [AppLink.parse(Uri(path: '/quick'))]);
    expect(find.text('Home page'), findsOneWidget);
  });

  testWidgets('before Quick play opens it plays the picture Home suggests', (tester) async {
    final links = await _pumpStore(
      tester,
      open: {Reveal.library},
      next: const NextStep(key: 'pack', label: 'Next in Tropical Beaches', title: 'Palm Cove', subtitle: '', route: '/play/p-2'),
    );
    expect(links.shown, isEmpty);
    expect(find.text('Picture p-2'), findsOneWidget);
  });

  testWidgets('before Quick play opens, with no picture to suggest, it goes Home', (tester) async {
    final links = await _pumpStore(tester, open: const {});
    expect(links.shown, isEmpty);
    expect(find.text('Home page'), findsOneWidget);
  });
}
