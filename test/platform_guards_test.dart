// Platform guards for the web build.
//
// Runs on the VM (`flutter test`) and in a browser
// (`flutter test --platform chrome test/platform_guards_test.dart`), where
// `kIsWeb` is true and the plugin-free code paths are exercised for real.
import 'dart:io' show Directory;

import 'package:appwrite/appwrite.dart';
import 'package:card_jigsaw_world/app.dart';
import 'package:card_jigsaw_world/core/platform.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/data/purchases.dart';
import 'package:card_jigsaw_world/features/ads/house_ads.dart';
import 'package:card_jigsaw_world/features/profile/settings_screen.dart';
import 'package:card_jigsaw_world/features/store/store_screen.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/auth.dart';
import 'package:card_jigsaw_world/state/profile.dart';
import 'package:card_jigsaw_world/state/purchases.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:card_jigsaw_world/core/theme/app_theme.dart';
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

/// A store that is never reachable, so the iOS layout can be pumped without
/// the billing plugin.
class _NoStore extends PurchaseService {
  _NoStore() : super(Client());
  @override
  Future<void> start() async {}
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<Map<String, ProductDetails>> queryProducts() async => const {};
}

Future<Widget> _app(Widget home, {required PlatformCaps caps}) async {
  SharedPreferences.setMockInitialValues({'onboarded': true});
  final store = await LocalStore.open();
  return ProviderScope(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      platformCapsProvider.overrideWithValue(caps),
      profileProvider.overrideWith(_GuestProfile.new),
      isGuestProvider.overrideWithValue(true),
      purchaseServiceProvider.overrideWith((ref) => _NoStore()),
      storeAvailableProvider.overrideWith((ref) => false),
      productsProvider.overrideWith((ref) => const <String, ProductDetails>{}),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: home),
  );
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

  group('capability flags', () {
    test('follow kIsWeb', () {
      expect(isWeb, kIsWeb);
      expect(supportsPurchases, !kIsWeb);
      expect(supportsQuickActions, !kIsWeb);
      expect(supportsNotifications, !kIsWeb);
      if (kIsWeb) {
        expect(supportsGiftCodes, isFalse);
        expect(supportsWidgets, isFalse);
        expect(supportsNativeAppleSignIn, isFalse);
      }
    });

    test('gift codes and widgets are Apple-only', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(supportsGiftCodes, isFalse);
      expect(supportsWidgets, isFalse);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(supportsGiftCodes, !kIsWeb);
      expect(supportsWidgets, !kIsWeb);
      debugDefaultTargetPlatformOverride = null;
    });

    test('PlatformCaps.web turns every native feature off', () {
      const w = PlatformCaps.web;
      expect(w.isWeb, isTrue);
      expect([w.purchases, w.giftCodes, w.quickActions, w.widgets, w.notifications, w.nativeAppleSignIn], everyElement(isFalse));
      expect(PlatformCaps.current().isWeb, kIsWeb);
    });
  });

  group('PurchaseService without a store', () {
    // The VM has no StoreKit either, so these are the same answers the web
    // build gives; on `--platform chrome` the early returns are what runs.
    late final PurchaseService service;
    setUpAll(() => service = PurchaseService(Client()));

    test('start() and isAvailable() are safe on web', () async {
      // The VM picks the Android billing plugin, which has no channel here.
      if (!kIsWeb) return;
      await service.start();
      expect(await service.isAvailable(), isFalse);
    });

    test('presentCodeRedemptionSheet() is false off Apple platforms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await service.presentCodeRedemptionSheet(), isFalse);
      debugDefaultTargetPlatformOverride = null;
    });

    test('queryProducts() is empty on web', () async {
      if (!kIsWeb) return;
      expect(await service.queryProducts(), isEmpty);
    });

    test('restorePurchases() reports zero on web', () async {
      if (!kIsWeb) return;
      final events = <PurchaseEvent>[];
      final sub = service.events.listen(events.add);
      await service.restorePurchases();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(events.whereType<RestoreFinished>().single.count, 0);
    });
  });

  group('creatives', () {
    test('store creatives are the ones that sell a purchase', () {
      const vip = Creative(id: 'x', kind: CreativeKind.vip, headline: '', body: '', cta: '', route: '/store');
      const piggy = Creative(id: 'y', kind: CreativeKind.piggy, headline: '', body: '', cta: '', route: '/home');
      expect(vip.sellsPurchase, isTrue);
      expect(piggy.sellsPurchase, isFalse);
    });
  });

  group('Store on web', () {
    testWidgets('shows the notice, hides prices, keeps free sources and VIP info', (tester) async {
      await tester.pumpWidget(await _app(const StoreScreen(), caps: PlatformCaps.web));
      await tester.pumpAndSettle();
      expect(find.text(StoreWebNotice.message), findsOneWidget);
      expect(find.text('Free coins'), findsOneWidget);
      expect(find.textContaining('Free coins: daily quests'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(find.text('Card Jigsaw World VIP'), findsOneWidget);
      expect(find.text('Available on iPhone'), findsOneWidget);
      expect(find.text(StoreProducts.grant(ProductIds.coins1000).label), findsNothing);
      expect(find.text('Start 7-day free trial'), findsNothing);
      expect(find.text('Have a gift code? Redeem it'), findsNothing);
    });

    testWidgets('on iOS the grids and buy buttons are back', (tester) async {
      await tester.pumpWidget(await _app(const StoreScreen(), caps: PlatformCaps.ios));
      await tester.pumpAndSettle();
      expect(find.text(StoreWebNotice.message), findsNothing);
      expect(find.text(StoreProducts.grant(ProductIds.coins1000).label), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(find.text('Available on iPhone'), findsNothing);
      expect(find.text('Have a gift code? Redeem it'), findsOneWidget);
      expect(find.text('Start 7-day free trial'), findsOneWidget);
    });
  });

  group('Settings on web', () {
    testWidgets('hides restore, gift codes and reminders', (tester) async {
      await tester.pumpWidget(await _app(const SettingsScreen(), caps: PlatformCaps.web));
      await tester.pumpAndSettle();
      expect(find.text('Restore purchases'), findsNothing);
      expect(find.text('Redeem a gift code'), findsNothing);
      expect(find.text('Daily reminders'), findsNothing);
      expect(find.text('Sign in or create account'), findsOneWidget);
    });

    testWidgets('keeps them on iOS', (tester) async {
      await tester.pumpWidget(await _app(const SettingsScreen(), caps: PlatformCaps.ios));
      await tester.pumpAndSettle();
      expect(find.text('Daily reminders'), findsOneWidget);
      expect(find.text('Restore purchases'), findsOneWidget);
      expect(find.text('Redeem a gift code'), findsOneWidget);
    });
  });

  group('PhoneFrame', () {
    Widget probe(Size window) => MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(size: window),
            child: Builder(
              builder: (context) => PhoneFrame(
                mediaQuery: MediaQuery.of(context),
                child: Builder(builder: (context) => Text('w=${MediaQuery.sizeOf(context).width.round()}')),
              ),
            ),
          ),
        );

    testWidgets('caps the layout at 520 px on a wide window', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(probe(const Size(1400, 900)));
      expect(find.text('w=520'), findsOneWidget);
      expect(tester.getSize(find.byType(Text)).width, lessThanOrEqualTo(PhoneFrame.maxWidth));
      expect(tester.getRect(find.byType(Text)).left, closeTo((1400 - PhoneFrame.maxWidth) / 2, 1));
    });

    testWidgets('leaves phone-width windows alone', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(probe(const Size(390, 844)));
      expect(find.text('w=390'), findsOneWidget);
    });
  });
}
