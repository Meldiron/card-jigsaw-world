// The economy changes of 2026-10-17 on the real app (live Appwrite backend, a QA guest): the level
// card's capped level-up coins, the Lucky Wheel's ×5 spin and its odds, the store's booster bundles
// (a purchase through a stand-in App Store, granted on the profile row the way verify-purchase does),
// a piggy bank upgrade from 500 to 600 for 5,000 coins, and a quest swap for a ticket.
//
// Run: tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//        --target=integration_test/economy_extras_test.dart -d <simulator>
import 'dart:async';
import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:carden/app.dart';
import 'package:carden/core/appwrite.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/data/purchases.dart';
import 'package:carden/data/sync/backend.dart';
import 'package:carden/features/daily/wheel_screen.dart';
import 'package:carden/features/events/events_screen.dart';
import 'package:carden/models/models.dart';
import 'package:carden/router.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/purchases.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/sync.dart';
import 'package:carden/state/unlocks.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The App Store and the verify-purchase function for QA: paid after a moment, the grant added to
/// the profile row with atomic increments (Peeks and Magic included), the answer as the function's.
class _QaStore extends PurchaseService {
  _QaStore(this.ref) : super(ref.read(appwriteClientProvider));
  final Ref ref;
  int _tx = 0;

  @override
  Future<void> start() async {}

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Map<String, ProductDetails>> queryProducts() async => {
        for (final id in ProductIds.all) id: ProductDetails(id: id, title: id, description: '', price: StoreProducts.price(id), rawPrice: double.parse(StoreProducts.usdPrices[id]!), currencyCode: 'USD'),
      };

  @override
  void warmUp() {}

  @override
  Future<bool> buy(ProductDetails product) async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final id = 'qa-ee${++_tx}';
    unawaited(debugDeliver([
      PurchaseDetails(
        productID: product.id,
        purchaseID: id,
        verificationData: PurchaseVerificationData(localVerificationData: '', serverVerificationData: id, source: 'app_store'),
        transactionDate: '0',
        status: PurchaseStatus.purchased,
      ),
    ]));
    return true;
  }

  @override
  Future<(int, String)> sendForVerification(String jws, String productId) async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final g = StoreProducts.grant(productId);
    final grant = {if (g.coins > 0) 'coins': g.coins, if (g.tickets > 0) 'tickets': g.tickets, if (g.hints > 0) 'hints': g.hints, if (g.peeks > 0) 'peeks': g.peeks, if (g.magics > 0) 'magics': g.magics};
    final uid = ref.read(authProvider).value!.$id;
    final row = await ref.read(syncBackendProvider).updateProfile(uid, {for (final e in grant.entries) e.key: Operator.increment(e.value)});
    return (200, jsonEncode({'ok': true, 'grant': grant, 'balances': {for (final k in const ['coins', 'tickets', 'hints', 'peeks', 'magics']) k: row[k] ?? 0}}));
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

  Future<void> shot(WidgetTester tester, String name, {int wait = 400}) async {
    if (wait > 0) await settle(tester, wait);
    await binding.takeScreenshot(name);
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(CardenApp)));

  /// Waits until the device has sent every queued change, then reads the profile row on the server.
  Future<Map<String, dynamic>> serverRow(WidgetTester tester) async {
    for (var i = 0; i < 30 && container(tester).read(syncProvider.notifier).debugOps.isNotEmpty; i++) {
      await settle(tester, 500);
    }
    final userId = (await container(tester).read(authProvider.future))!.$id;
    final row = await container(tester).read(tablesProvider).getRow(databaseId: AppwriteConfig.databaseId, tableId: AppwriteConfig.profiles, rowId: userId);
    return row.data;
  }

  testWidgets('level card, wheel ×5, booster bundles, piggy upgrade, quest swap', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await FirstSteps.skipFor(store); // the whole app; integration_test/first_steps_test.dart plays the first steps
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        openFeaturesProvider.overrideWithValue(OpenFeatures.all),
        pendingUnlockIntroProvider.overrideWithValue(null),
        purchaseServiceProvider.overrideWith((ref) => _QaStore(ref)),
      ],
      child: const CardenApp(),
    ));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 5000);
    final profile = container(tester).read(profileProvider.notifier);
    Profile me() => container(tester).read(profileProvider).value!;

    // ---- B4: level 8, so the card shows 300 next and the 500 of level 10 coming up.
    for (var i = 0; i < 3; i++) {
      await profile.recordCompletion(puzzleId: 'qa-ee-xp-$i', cells: 300, stars: 3, firstTime: true);
      await settle(tester, 1500);
    }
    expect(me().level, 8);
    await tester.dragUntilVisible(find.text('Next: level 9'), find.byType(Scrollable).first, const Offset(0, -250));
    await Scrollable.ensureVisible(tester.element(find.text('Next: level 9')), alignment: 0.35);
    await settle(tester, 800);
    expect(find.text('Level 10'), findsOneWidget);
    expect(find.text('Level 11'), findsOneWidget);
    expect(LevelRewards.forLevel(9).coins, 300);
    expect(LevelRewards.forLevel(10).coins, 500);
    await shot(tester, 'ee_01_level_card');
    await tester.fling(find.byType(Scrollable).first, const Offset(0, 4000), 3000);
    await settle(tester, 1000);

    // ---- C1: the wheel's ×5 spin.
    await profile.addTickets(12, reason: 'qa:economy-extras');
    await settle(tester, 1500);
    container(tester).read(routerProvider).push('/wheel');
    await settle(tester, 2500);
    await shot(tester, 'ee_02_wheel_x1');
    await tapText(tester, '×5', ms: 1200);
    expect(find.text('Spin ×5 for'), findsOneWidget);
    expect(find.text('5,000'), findsWidgets, reason: 'the jackpot slice and line show 5,000');
    await shot(tester, 'ee_03_wheel_x5');
    await tapText(tester, 'See odds', ms: 1500);
    expect(find.textContaining('A ×5 spin costs 5 tickets and pays the prize it lands on five times'), findsOneWidget);
    await shot(tester, 'ee_04_wheel_odds');
    await tester.tapAt(const Offset(200, 60));
    await settle(tester, 1200);
    final w0 = me();
    await tester.tap(find.descendant(of: find.byType(WheelScreen), matching: find.text('Spin ×5 for')), warnIfMissed: false);
    await settle(tester, 5800);
    final w1 = me();
    expect(w1.tickets, w0.tickets - 5, reason: 'a ×5 spin costs 5 tickets');
    final gained = {
      'coins': w1.coins - w0.coins,
      'hints': w1.hints - w0.hints,
      'peeks': w1.peeks - w0.peeks,
      'magics': w1.magics - w0.magics,
    }..removeWhere((_, v) => v == 0);
    debugPrint('QA_EE wheel x5 won $gained');
    final prizes = {for (final s in wheelSegments) '${s.kind.name}:${s.amount * 5}'};
    expect(gained.length, 1, reason: 'one prize');
    expect(prizes, contains('${gained.keys.single}:${gained.values.single}'), reason: 'five times a slice: $gained');
    expect(find.text('You won'), findsOneWidget);
    await shot(tester, 'ee_05_wheel_x5_won');
    await tester.tap(find.byIcon(CupertinoIcons.xmark).first, warnIfMissed: false);
    await settle(tester, 1500);

    // ---- C2: the booster bundles, bought through the stand-in App Store.
    container(tester).read(routerProvider).push('/store');
    await settle(tester, 2500);
    await tester.scrollUntilVisible(find.text('Peek, Hint and Magic for any board'), 200, scrollable: find.byType(Scrollable).last, maxScrolls: 20);
    await Scrollable.ensureVisible(tester.element(find.text('Peek, Hint and Magic for any board')), alignment: 0.3);
    await settle(tester, 800);
    await shot(tester, 'ee_06_store_boosters');
    final b0 = me();
    await tester.tap(find.text('Peeks').first, warnIfMissed: false);
    await settle(tester, 2600);
    expect(find.text('Adding 15 Peeks, 10 Hints, 5 Magic'), findsOneWidget);
    await shot(tester, 'ee_07_adding_boosters', wait: 0);
    for (var i = 0; i < 20 && find.text('15 Peeks, 10 Hints, 5 Magic added').evaluate().isEmpty; i++) {
      await settle(tester, 500);
    }
    expect(find.text('15 Peeks, 10 Hints, 5 Magic added'), findsOneWidget);
    final b1 = me();
    expect((b1.peeks, b1.hints, b1.magics), (b0.peeks + 15, b0.hints + 10, b0.magics + 5));
    expect(find.text('You now have ${b1.peeks} Peeks, ${b1.hints} Hints and ${b1.magics} Magic.'), findsOneWidget);
    await shot(tester, 'ee_08_boosters_added', wait: 600);
    await tapText(tester, 'Done');
    await tester.tap(find.byIcon(CupertinoIcons.xmark).first, warnIfMissed: false);
    await settle(tester, 1500);

    // ---- C6: the piggy bank from 500 to 600 for 5,000 coins.
    await profile.addCoins(6000, reason: 'qa:economy-extras');
    await settle(tester, 1500);
    await tester.dragUntilVisible(find.text('Piggy bank'), find.byType(Scrollable).first, const Offset(0, -200));
    await settle(tester, 600);
    await tester.tap(find.text('Piggy bank').first, warnIfMissed: false);
    await settle(tester, 1500);
    expect(find.text('Upgrade to 600 for'), findsOneWidget);
    await shot(tester, 'ee_09_piggy_sheet');
    final p0 = me();
    await tester.tap(find.byKey(const ValueKey('piggy-upgrade')), warnIfMissed: false);
    await settle(tester, 1200);
    expect(find.text('Upgrade the piggy bank?'), findsOneWidget);
    await shot(tester, 'ee_10_piggy_confirm');
    await tapText(tester, 'Pay 5,000 coins', ms: 1500);
    final p1 = me();
    expect(p1.coins, p0.coins - Economy.piggyUpgradeCoins);
    expect(p1.piggyCapacity, 600);
    expect(find.text('of 600'), findsOneWidget);
    expect(find.text('Upgrade to 700 for'), findsOneWidget);
    await shot(tester, 'ee_11_piggy_600');
    final piggyRow = await serverRow(tester);
    expect(piggyRow['piggyLevel'], 1);
    expect(piggyRow['coins'], p1.coins);
    // Below the toast, above the sheet: the dim behind the sheet closes it.
    await tester.tapAt(const Offset(200, 260));
    await settle(tester, 1500);
    expect(find.text('Upgrade to 700 for'), findsNothing, reason: 'the sheet closed');
    await shot(tester, 'ee_12_home_piggy_600');

    // ---- C7: a quest swapped for a ticket.
    container(tester).read(routerProvider).go('/events');
    await settle(tester, 2500);
    final swaps = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('quest-swap-d:'));
    expect(swaps, findsWidgets, reason: 'daily quests can be swapped');
    await shot(tester, 'ee_13_quests');
    // The quest lines on the tab (the balances in the header are numbers only and change too).
    Set<String> titles() => {
          for (final t in tester.widgetList<Text>(find.descendant(of: find.byType(EventsScreen), matching: find.byType(Text))))
            if (RegExp('[A-Za-z]').hasMatch(t.data ?? '')) t.data!,
        };
    final before = titles();
    final q0 = me();
    // A swipe to the left, as far as the swap (TestFlight, 2026-10-17: a swipe, not a button).
    await tester.drag(swaps.at(1), const Offset(-320, 0), warnIfMissed: false);
    await settle(tester, 1200);
    expect(find.text('Swap this quest?'), findsOneWidget);
    await shot(tester, 'ee_14_swap_confirm');
    await tapText(tester, 'Swap for 1 ticket', ms: 1500);
    final q1 = me();
    expect(q1.tickets, q0.tickets - 1, reason: 'a swap costs a ticket');
    expect(q1.questSwaps, hasLength(1));
    final after = titles();
    expect(before.difference(after), hasLength(1), reason: 'one quest went: ${before.difference(after)}');
    expect(after.difference(before), hasLength(1), reason: 'one quest came: ${after.difference(before)}');
    await shot(tester, 'ee_15_quest_swapped');
    final swapRow = await serverRow(tester);
    expect(Goals.decodeSwaps(swapRow['questSwaps']), q1.questSwaps);
    expect(swapRow['tickets'], q1.tickets);
    debugPrint('QA_EE swapped ${q1.questSwaps}');
  });
}
