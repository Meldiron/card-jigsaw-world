import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory;

import 'package:appwrite/appwrite.dart';
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/data/purchases.dart';
import 'package:carden/features/store/purchase_host.dart';
import 'package:carden/models/models.dart';
import 'package:carden/router.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/purchases.dart';
import 'package:carden/state/sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'support/fake_sync.dart';

/// The App Store and the verify-purchase function in memory. A check adds the grant to the fake
/// server's profile once per transaction, as the function does, and answers with what it gave.
class _FakeStore extends PurchaseService {
  _FakeStore(this.server) : super(Client());
  final FakeServer server;
  int sends = 0;

  /// Answers to give before the real one, in order: 'offline' (no answer) or an HTTP status.
  final answers = <Object>[];

  /// When set, a check waits for it after the grant (the answer is on its way).
  Completer<void>? gate;
  final _granted = <String>{};

  @override
  Future<void> start() async {}

  @override
  void warmUp() {}

  @override
  Future<bool> buy(ProductDetails product) async => true;

  @override
  Future<(int, String)> sendForVerification(String jws, String productId) async {
    sends++;
    if (answers.isNotEmpty) {
      final a = answers.removeAt(0);
      if (a == 'offline') throw AppwriteException('Failed host lookup');
      return (a as int, jsonEncode({'ok': false, 'error': 'Transaction could not be verified'}));
    }
    final g = StoreProducts.grant(productId);
    final vip = ProductIds.isSubscription(productId);
    final expires = DateTime.now().add(const Duration(days: 30)).toUtc().toIso8601String();
    final grant = vip ? {'vipExpiresAt': expires} : {if (g.coins > 0) 'coins': g.coins, if (g.tickets > 0) 'tickets': g.tickets, if (g.hints > 0) 'hints': g.hints};
    final already = !_granted.add(jws);
    if (!already) {
      server.profiles['player1'] = server.write(server.profiles['player1'], {
        for (final e in grant.entries) e.key: e.value is int ? Operator.increment(e.value as int) : e.value,
      }, 'player1');
    }
    await gate?.future;
    final row = server.profiles['player1']!;
    return (200, jsonEncode({
      'ok': true,
      if (already) 'alreadyApplied': true,
      'grant': grant,
      if (!already) 'balances': {'coins': row['coins'], 'tickets': row['tickets'], 'hints': row['hints']},
    }));
  }
}

ProductDetails _product(String id) => ProductDetails(id: id, title: id, description: '', price: '\$1.99', rawPrice: 1.99, currencyCode: 'USD');

/// A transaction as StoreKit hands it over; the fake function reads its id from the "JWS".
PurchaseDetails _paid(String productId, String tx, {PurchaseStatus status = PurchaseStatus.purchased}) => PurchaseDetails(
      productID: productId,
      purchaseID: tx,
      verificationData: PurchaseVerificationData(localVerificationData: '', serverVerificationData: tx, source: 'app_store'),
      transactionDate: '0',
      status: status,
    );

Future<(Device, _FakeStore)> _phone() async {
  final server = FakeServer();
  final store = _FakeStore(server);
  final phone = await Device(server, testUser('player1'), overrides: [purchaseServiceProvider.overrideWithValue(store)]).open();
  phone.container.listen(purchaseFlowProvider, (_, _) {});
  phone.container.read(syncNoticeProvider.notifier).take();
  return (phone, store);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The Appwrite IO client asks path_provider for its cookie jar folder.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => Directory.systemTemp.createTempSync('cjw-test').path,
  );

  test('a purchase shows as added once the header has it, and never as news from another device', () async {
    final (phone, store) = await _phone();
    final before = phone.me.tickets;
    final seen = <(PurchaseStage, int)>[];
    phone.container.listen(purchaseFlowProvider, (_, s) => seen.add((s.stage, phone.me.tickets)));

    await phone.container.read(purchaseFlowProvider.notifier).buy(_product(ProductIds.tickets5));
    store.gate = Completer();
    unawaited(store.debugDeliver([_paid(ProductIds.tickets5, 't1')]));
    await phone.settle();
    expect(phone.container.read(purchaseFlowProvider).stage, PurchaseStage.adding);

    // The App Store sheet closes: the app comes back and reads the save while the answer is on its way.
    await phone.resume();
    expect(phone.container.read(syncNoticeProvider).isEmpty, isTrue, reason: 'a purchase on this device is not news from another one');

    store.gate!.complete();
    await phone.settle();
    final s = phone.container.read(purchaseFlowProvider);
    expect(s.stage, PurchaseStage.added);
    expect(s.grant!.tickets, 10);
    expect(s.balances!.tickets, before + 10);
    expect(phone.me.tickets, before + 10);
    expect(seen.map((e) => e.$1), [PurchaseStage.paying, PurchaseStage.adding, PurchaseStage.added]);
    expect(seen.last.$2, before + 10, reason: '"added" shows when the header already has the tickets');
    expect(phone.container.read(syncNoticeProvider).isEmpty, isTrue);
  });

  test('a check that does not get through is tried again, and the purchase is added once', () async {
    final (phone, store) = await _phone();
    final before = phone.me.tickets;
    final events = <PurchaseEvent>[];
    store.events.listen(events.add);
    store.answers.add('offline');

    await phone.container.read(purchaseFlowProvider.notifier).buy(_product(ProductIds.tickets5));
    await store.debugDeliver([_paid(ProductIds.tickets5, 't2')]);
    await phone.settle();
    expect(events.whereType<PurchaseRetrying>().single.wait, const Duration(seconds: 2));
    expect(phone.container.read(purchaseFlowProvider).stage, PurchaseStage.adding);

    // The app comes back (or the retry timer fires): checked again at once.
    await store.checkOpenPurchases();
    await phone.settle();
    expect(store.sends, 2);
    expect(phone.container.read(purchaseFlowProvider).stage, PurchaseStage.added);
    expect(phone.me.tickets, before + 10);
    expect(phone.server.profiles['player1']!['tickets'], before + 10);
  });

  test('a purchase the server refuses says so and is not sent again this session', () async {
    final (phone, store) = await _phone();
    store.answers.add(400);
    await phone.container.read(purchaseFlowProvider.notifier).buy(_product(ProductIds.coins1000));
    await store.debugDeliver([_paid(ProductIds.coins1000, 't3')]);
    await phone.settle();
    final s = phone.container.read(purchaseFlowProvider);
    expect(s.stage, PurchaseStage.notAdded);
    expect(s.message, 'Transaction could not be verified');
    await store.checkOpenPurchases();
    expect(store.sends, 1);
  });

  test('one transaction handed over twice is checked once', () async {
    final (phone, store) = await _phone();
    final before = phone.me.tickets;
    store.gate = Completer();
    unawaited(store.debugDeliver([_paid(ProductIds.tickets5, 't4')]));
    unawaited(store.debugDeliver([_paid(ProductIds.tickets5, 't4')]));
    await phone.settle();
    expect(store.sends, 1);
    store.gate!.complete();
    await phone.settle();
    await store.debugDeliver([_paid(ProductIds.tickets5, 't4')]);
    expect(store.sends, 1, reason: 'added this session: only finished');
    expect(phone.me.tickets, before + 10);
  });

  test('a purchase paid while the app was closed ends in a toast; a VIP renewal stays quiet', () async {
    final (phone, store) = await _phone();
    await store.debugDeliver([_paid(ProductIds.hints5, 't5')]);
    await phone.settle();
    var s = phone.container.read(purchaseFlowProvider);
    expect(s.stage, PurchaseStage.added);
    expect(s.watching, isFalse, reason: 'nobody follows it: PurchaseHost shows a toast');
    expect(s.grant!.hints, 16);
    phone.container.read(purchaseFlowProvider.notifier).clear();

    await store.debugDeliver([_paid(ProductIds.vipMonthly, 't6')]);
    await phone.settle();
    expect(phone.container.read(purchaseFlowProvider).stage, PurchaseStage.added, reason: 'VIP is new: worth a toast');
    phone.container.read(purchaseFlowProvider.notifier).clear();
    expect(phone.me.isVip, isTrue);

    await store.debugDeliver([_paid(ProductIds.vipMonthly, 't7')]);
    await phone.settle();
    s = phone.container.read(purchaseFlowProvider);
    expect(s.stage, PurchaseStage.idle, reason: 'a renewal is not news');
  });

  test('closing the App Store sheet without paying ends the purchase', () async {
    final (phone, store) = await _phone();
    await phone.container.read(purchaseFlowProvider.notifier).buy(_product(ProductIds.tickets15));
    expect(phone.container.read(purchaseFlowProvider).busy, isTrue);
    await store.debugDeliver([_paid(ProductIds.tickets15, '', status: PurchaseStatus.canceled)]);
    await phone.settle();
    expect(phone.container.read(purchaseFlowProvider).stage, PurchaseStage.idle);
    expect(store.sends, 0);
  });

  testWidgets('the purchase sheet goes from "Adding" to "added" with the new balance', (tester) async {
    final server = FakeServer();
    server.profiles['player1'] = server.write(null, Profile.guest('player1').toData(), 'player1');
    final before = Profile.guest('player1').tickets;
    final store = _FakeStore(server);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        purchaseServiceProvider.overrideWithValue(store),
        syncProvider.overrideWith(_InstantSync.new),
        profileProvider.overrideWith(_Guest.new),
      ],
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        theme: AppTheme.light(),
        builder: (_, child) => PurchaseHost(child: child!),
        home: const Scaffold(),
      ),
    ));
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    // The store, under the sheet.
    unawaited(rootNavigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Store page')))));
    await tester.pumpAndSettle();

    store.gate = Completer();
    await container.read(purchaseFlowProvider.notifier).buy(_product(ProductIds.tickets5));
    unawaited(store.debugDeliver([_paid(ProductIds.tickets5, 't8')]));
    // The spinner keeps animating while it adds: pump through the sheet's slide-in instead of settling.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Adding 10 tickets'), findsOneWidget);
    expect(find.text('Payment received. This takes a few seconds.'), findsOneWidget);

    store.gate!.complete();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('10 tickets added'), findsOneWidget);
    expect(find.text('You now have ${before + 10} tickets.'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('10 tickets added'), findsNothing);
    expect(find.text('Store page'), findsOneWidget, reason: 'Done closes the sheet, not the store under it');
    expect(container.read(purchaseFlowProvider).stage, PurchaseStage.idle);
  });
}

/// The save sync without a server: reads finish at once.
class _InstantSync extends SyncController {
  @override
  SyncState build() => const SyncState();

  @override
  Future<void> sync({bool full = false, bool silent = false}) async {}
}

class _Guest extends ProfileNotifier {
  @override
  Future<Profile> build() async => Profile.guest('player1');
}
