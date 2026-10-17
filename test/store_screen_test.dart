import 'dart:io' show Directory, File;

import 'package:appwrite/appwrite.dart';
import 'package:carden/core/links.dart';
import 'package:carden/core/platform.dart';
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/data/purchases.dart';
import 'package:carden/features/store/store_screen.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/purchases.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// An App Store that answers without products for its first [emptyAnswers] queries (no network,
/// or Apple not serving them yet after the Paid Apps agreement), then with Coins 2,500.
class _LateStore extends PurchaseService {
  _LateStore({required this.emptyAnswers}) : super(Client());
  final int emptyAnswers;
  int queries = 0;
  ProductDetails? bought;
  @override
  Future<void> start() async {}
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<Map<String, ProductDetails>> queryProducts() async {
    queries++;
    if (queries <= emptyAnswers) return const {};
    return {
      ProductIds.coins1000: ProductDetails(id: ProductIds.coins1000, title: 'Coins', description: '', price: '1,09 €', rawPrice: 1.09, currencyCode: 'EUR'),
    };
  }

  @override
  Future<bool> buy(ProductDetails product) async {
    bought = product;
    return true;
  }
}

/// iPhone 17 Pro portrait: 402 x 874 pt, 62 pt status bar, 34 pt home indicator.
const _homeIndicator = 34.0;

Future<void> _pumpStore(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'onboarded': true});
  final store = await LocalStore.open();
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: _homeIndicator * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      platformCapsProvider.overrideWithValue(PlatformCaps.ios),
      profileProvider.overrideWith(_GuestProfile.new),
      isGuestProvider.overrideWithValue(true),
      purchaseServiceProvider.overrideWith((ref) => _NoStore()),
      storeAvailableProvider.overrideWith((ref) => false),
      productsProvider.overrideWith((ref) => const <String, ProductDetails>{}),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: const StoreScreen()),
  ));
  await tester.pumpAndSettle();
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

  testWidgets('without App Store prices nothing is for sale: one panel says why, and the free ways stay', (tester) async {
    await _pumpStore(tester);
    expect(find.text('Purchases are unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // No bundle, no placeholder price and no VIP plan is offered while the App Store is away.
    for (final id in ProductIds.consumables) {
      expect(find.text(StoreProducts.grant(id).label), findsNothing, reason: id);
      expect(find.text(StoreProducts.price(id)), findsNothing, reason: id);
    }
    expect(find.text('Start 7-day free trial'), findsNothing);
    // The free video and the free sources are still there.
    expect(find.text('Earn for free'), findsOneWidget);
    expect(find.text('Watch'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -6000));
    await tester.pumpAndSettle();
    expect(find.text('Lucky Wheel'), findsOneWidget);
  });

  testWidgets('terms of use and privacy policy are linked where VIP is sold', (tester) async {
    await _pumpStore(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -6000));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('store-terms')), findsOneWidget);
    expect(find.byKey(const ValueKey('store-privacy')), findsOneWidget);
    // The same address as the App Store listing's privacy policy URL.
    expect(AppLinks.privacyPolicy.toString(), File('store/metadata/en-US/privacy_url.txt').readAsStringSync().trim());
  });

  testWidgets('the last row scrolls clear of the home indicator', (tester) async {
    await _pumpStore(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -6000));
    await tester.pumpAndSettle();
    // The Terms and Privacy links are the list's last row (no store in tests: the unavailable layout).
    final footer = find.byKey(const ValueKey('store-terms'));
    expect(footer, findsOneWidget);
    final bottom = tester.getBottomLeft(footer).dy;
    expect(bottom, lessThanOrEqualTo(874 - _homeIndicator - 8), reason: 'footer ends at $bottom');
  });

  group('products asked for again', () {
    Future<ProviderContainer> pumpLate(WidgetTester tester, _LateStore service) async {
      SharedPreferences.setMockInitialValues({'onboarded': true});
      final store = await LocalStore.open();
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(overrides: [
        localStoreProvider.overrideWithValue(store),
        platformCapsProvider.overrideWithValue(PlatformCaps.ios),
        profileProvider.overrideWith(_GuestProfile.new),
        isGuestProvider.overrideWithValue(true),
        purchaseServiceProvider.overrideWith((ref) => service),
      ]);
      addTearDown(container.dispose);
      // Earlier in the launch (Home, say) the App Store answered without products.
      expect(await container.read(productsProvider.future), isEmpty);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light(), home: const StoreScreen()),
      ));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('opening the store asks again, so the App Store prices show', (tester) async {
      final service = _LateStore(emptyAnswers: 1);
      await pumpLate(tester, service);
      expect(service.queries, 2);
      expect(find.text('1,09 €'), findsOneWidget);
    });

    testWidgets('Try again asks the App Store again; the bundles come back and a tap buys', (tester) async {
      final service = _LateStore(emptyAnswers: 2);
      await pumpLate(tester, service);
      expect(find.text('1,09 €'), findsNothing, reason: 'still no products when the store opened');
      expect(find.text('Purchases are unavailable'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(service.queries, 3);
      expect(find.text('Purchases are unavailable'), findsNothing);
      expect(find.text('1,09 €'), findsOneWidget);
      await tester.tap(find.text(StoreProducts.grant(ProductIds.coins1000).label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(service.bought?.id, ProductIds.coins1000);
      expect(find.textContaining('not available right now'), findsNothing);
      // The tapped tile waits for the App Store with a spinner in place of its price.
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.text('1,09 €'), findsNothing);
      // The App Store sheet closes without a purchase: the price is back.
      await service.debugDeliver([
        PurchaseDetails(productID: ProductIds.coins1000, verificationData: PurchaseVerificationData(localVerificationData: '', serverVerificationData: '', source: 'app_store'), transactionDate: null, status: PurchaseStatus.canceled),
      ]);
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.text('1,09 €'), findsOneWidget);
    });
  });

  group('booster bundles', () {
    // An iPhone SE (320 x 568 pt) at the default size and at Largest (200%): the tiles list Peek, Hint
    // and Magic with their counts, and no product tile overflows (the test font is wider than SF Pro,
    // so only the tiles are checked here).
    for (final scale in const [1.0, 2.0]) {
      testWidgets('tiles show the three helpers, text ${scale}x on an SE', (tester) async {
        SharedPreferences.setMockInitialValues({'onboarded': true});
        final store = await LocalStore.open();
        final errors = <String>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (d) => errors.add(d.toString());
        addTearDown(() => FlutterError.onError = previous);
        tester.view.physicalSize = const Size(320 * 2, 568 * 2);
        tester.view.devicePixelRatio = 2;
        tester.view.padding = const FakeViewPadding(top: 20 * 2);
        addTearDown(tester.view.reset);
        final products = {
          for (final id in ProductIds.all)
            id: ProductDetails(id: id, title: id, description: '', price: StoreProducts.price(id), rawPrice: double.parse(StoreProducts.usdPrices[id]!), currencyCode: 'USD'),
        };
        await tester.pumpWidget(ProviderScope(
          overrides: [
            localStoreProvider.overrideWithValue(store),
            platformCapsProvider.overrideWithValue(PlatformCaps.ios),
            profileProvider.overrideWith(_GuestProfile.new),
            isGuestProvider.overrideWithValue(true),
            purchaseServiceProvider.overrideWith((ref) => _NoStore()),
            storeAvailableProvider.overrideWith((ref) => true),
            productsProvider.overrideWith((ref) => products),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
            home: const StoreScreen(),
          ),
        ));
        await tester.pumpAndSettle();
        final seen = <String>{};
        for (var i = 0; i < 30; i++) {
          for (final t in tester.widgetList<Text>(find.byType(Text))) {
            seen.add(t.data ?? t.textSpan?.toPlainText() ?? '');
          }
          await tester.drag(find.byType(ListView), const Offset(0, -250));
          await tester.pumpAndSettle();
        }
        FlutterError.onError = previous;
        expect([for (final e in errors) if (e.contains('_ProductTile') || e.contains('_HelperCounts')) e.split('\n').first], isEmpty);
        expect(seen, containsAll(['Boosters', 'Peek, Hint and Magic for any board', '15', '10', '5', '50', '30', 'Peeks', 'Hints', 'Magic']));
        expect(seen, contains(StoreProducts.price(ProductIds.hints15)));
        // The better of the two names its saving (counting each helper at its price in a game).
        expect(seen, contains('+19% more'));
      });
    }
  });
}
