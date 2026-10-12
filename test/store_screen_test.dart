import 'dart:io' show Directory;

import 'package:appwrite/appwrite.dart';
import 'package:card_jigsaw_world/core/platform.dart';
import 'package:card_jigsaw_world/core/theme/app_theme.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/data/purchases.dart';
import 'package:card_jigsaw_world/features/store/store_screen.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/auth.dart';
import 'package:card_jigsaw_world/state/profile.dart';
import 'package:card_jigsaw_world/state/purchases.dart';
import 'package:card_jigsaw_world/state/settings.dart';
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

  testWidgets('tiles show the catalogue amounts and fallback prices', (tester) async {
    await _pumpStore(tester);
    for (final id in [ProductIds.coins1000, ProductIds.coins3000]) {
      expect(find.text(StoreProducts.grant(id).label), findsOneWidget, reason: id);
    }
    expect(find.text(StoreProducts.price(ProductIds.coins3000)), findsOneWidget);
    expect(find.text('+${StoreProducts.coinBonusPercent(ProductIds.coins5500)}%'), findsOneWidget);
  });

  testWidgets('the last row scrolls clear of the home indicator', (tester) async {
    await _pumpStore(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -6000));
    await tester.pumpAndSettle();
    // The footer line is the list's last row (debug wording: no store in tests).
    final footer = find.textContaining('Store unavailable on this device');
    expect(footer, findsOneWidget);
    final bottom = tester.getBottomLeft(footer).dy;
    expect(bottom, lessThanOrEqualTo(874 - _homeIndicator - 8), reason: 'footer ends at $bottom');
  });
}
