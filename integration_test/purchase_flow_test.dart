// The purchase flow on the real app (live Appwrite backend, a QA guest) with a stand-in App Store:
// the tapped tile waits while the "App Store sheet" is open, the purchase sheet says "Adding 10
// tickets", the grant lands on the profile row the way verify-purchase writes it (a server change
// this device did not make), and the sheet says "10 tickets added" once the header shows them. Then
// a slow check (three tries without an answer), a refused one, and a purchase that arrives on its
// own (a toast). StoreKit itself cannot be driven here: its sheet is another process, and the
// simulator's Xcode-signed transactions do not verify on the server.
//
// Run: tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//        --target=integration_test/purchase_flow_test.dart -d <simulator>
import 'dart:async';
import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:carden/app.dart';
import 'package:carden/core/appwrite.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/data/purchases.dart';
import 'package:carden/data/sync/backend.dart';
import 'package:carden/router.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/purchases.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The App Store and the verify-purchase function for QA.
class _QaStore extends PurchaseService {
  _QaStore(this.ref) : super(ref.read(appwriteClientProvider));
  final Ref ref;

  /// Answers to give before the real one: 'offline' (no answer) or an HTTP status.
  final answers = <Object>[];
  int _tx = 0;

  @override
  Future<void> start() async {}

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Map<String, ProductDetails>> queryProducts() async => {
        for (final id in ProductIds.all) id: ProductDetails(id: id, title: id, description: '', price: StoreProducts.price(id), rawPrice: 0, currencyCode: 'USD'),
      };

  @override
  void warmUp() {}

  /// The App Store sheet: open for a moment, then paid.
  @override
  Future<bool> buy(ProductDetails product) async {
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    unawaited(debugDeliver([paid(product.id)]));
    return true;
  }

  PurchaseDetails paid(String productId) {
    final id = 'qa${++_tx}';
    return PurchaseDetails(
      productID: productId,
      purchaseID: id,
      verificationData: PurchaseVerificationData(localVerificationData: '', serverVerificationData: id, source: 'app_store'),
      transactionDate: '0',
      status: PurchaseStatus.purchased,
    );
  }

  /// verify-purchase, warm: about a second and a half, then the grant on the profile row.
  @override
  Future<(int, String)> sendForVerification(String jws, String productId) async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (answers.isNotEmpty) {
      final a = answers.removeAt(0);
      if (a == 'offline') throw AppwriteException('Failed host lookup');
      return (a as int, jsonEncode({'ok': false, 'error': 'Transaction could not be verified'}));
    }
    final g = StoreProducts.grant(productId);
    final grant = {if (g.coins > 0) 'coins': g.coins, if (g.tickets > 0) 'tickets': g.tickets, if (g.hints > 0) 'hints': g.hints};
    final uid = ref.read(authProvider).value!.$id;
    final row = await ref.read(syncBackendProvider).updateProfile(uid, {for (final e in grant.entries) e.key: Operator.increment(e.value)});
    return (200, jsonEncode({'ok': true, 'grant': grant, 'balances': {'coins': row['coins'], 'tickets': row['tickets'], 'hints': row['hints']}}));
  }
}

Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
  await tester.pump(const Duration(milliseconds: 50));
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> shot(WidgetTester tester, String name, {int wait = 300}) async {
    if (wait > 0) await settle(tester, wait);
    await binding.takeScreenshot(name);
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  /// Scrolls [text] to the middle of the store (clear of the glass bar).
  Future<void> centre(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(find.text(text), 200, scrollable: find.byType(Scrollable).last, maxScrolls: 20);
    await Scrollable.ensureVisible(tester.element(find.text(text)), alignment: 0.5);
    await settle(tester, 600);
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(CardenApp)));

  testWidgets('buying tickets: the tile waits, the sheet adds them, the header shows them', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    late _QaStore qa;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        purchaseServiceProvider.overrideWith((ref) => qa = _QaStore(ref)),
      ],
      child: const CardenApp(),
    ));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 5000);
    int tickets() => container(tester).read(profileProvider).value?.tickets ?? -1;

    container(tester).read(routerProvider).push('/store');
    await settle(tester, 2500);
    await centre(tester, '10 tickets');
    await shot(tester, 'pf_01_store', wait: 400);

    // ---- Paid and added.
    final before = tickets();
    await tester.tap(find.text('10 tickets'));
    await settle(tester, 1000);
    expect(container(tester).read(purchaseFlowProvider).stage, PurchaseStage.paying);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget, reason: 'the tapped tile waits');
    await shot(tester, 'pf_02_tile_waits', wait: 0);
    await settle(tester, 2200);
    expect(find.text('Adding 10 tickets'), findsOneWidget);
    await shot(tester, 'pf_03_adding', wait: 0);
    await settle(tester, 3500);
    expect(find.text('10 tickets added'), findsOneWidget);
    expect(find.text('You now have ${before + 10} tickets.'), findsOneWidget);
    expect(tickets(), before + 10, reason: 'the header has them when the sheet says added');
    await shot(tester, 'pf_04_added', wait: 600);
    await tapText(tester, 'Done');
    expect(find.text('10 tickets added'), findsNothing);
    await shot(tester, 'pf_05_store_after');

    // ---- Slow: three checks without an answer (retries after 2, 4 and 8 s).
    qa.answers.addAll(['offline', 'offline', 'offline']);
    final slowBefore = tickets();
    await tester.tap(find.text('30 tickets'));
    await settle(tester, 4500);
    expect(find.text('Adding 30 tickets'), findsOneWidget);
    await settle(tester, 9000);
    expect(find.textContaining('taking longer than usual'), findsOneWidget);
    await shot(tester, 'pf_06_slow', wait: 0);
    await settle(tester, 12000);
    expect(find.text('30 tickets added'), findsOneWidget);
    expect(tickets(), slowBefore + 30);
    await shot(tester, 'pf_07_slow_added', wait: 400);
    await tapText(tester, 'Done');

    // ---- Refused by the server.
    qa.answers.add(400);
    await tester.scrollUntilVisible(find.text('2,500 coins'), -200, scrollable: find.byType(Scrollable).last, maxScrolls: 20);
    await Scrollable.ensureVisible(tester.element(find.text('2,500 coins')), alignment: 0.5);
    await settle(tester, 600);
    await tester.tap(find.text('2,500 coins'));
    await settle(tester, 5000);
    expect(find.text('Not added yet'), findsOneWidget);
    await shot(tester, 'pf_08_not_added', wait: 400);
    await tapText(tester, 'Close');

    // ---- Paid while the app was closed: it arrives on its own and a toast says so.
    final hintsBefore = container(tester).read(profileProvider).value!.hints;
    unawaited(qa.debugDeliver([qa.paid(ProductIds.hints5)]));
    await settle(tester, 2600);
    expect(find.text('Added 16 hints'), findsOneWidget);
    await shot(tester, 'pf_09_toast', wait: 0);
    expect(container(tester).read(profileProvider).value!.hints, hintsBefore + 16);
    await settle(tester, 2500);
  });
}
