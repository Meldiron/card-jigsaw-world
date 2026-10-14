// The Lucky Wheel's booster prizes on the real app (live Appwrite backend): the odds sheet lists
// 5 and 10 Peeks and 1 and 3 Magic, spins until a Peek or a Magic is won, the stock reaches the
// profile row on the server, and in a game the booster bar shows "N left" and uses the stock
// before coins.
//
// Run: tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//        --target=integration_test/wheel_boosters_test.dart -d <simulator>
import 'package:card_jigsaw_world/app.dart';
import 'package:card_jigsaw_world/core/appwrite.dart';
import 'package:card_jigsaw_world/core/sfx.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/features/game/board_widget.dart';
import 'package:card_jigsaw_world/router.dart';
import 'package:card_jigsaw_world/state/auth.dart';
import 'package:card_jigsaw_world/state/catalog.dart';
import 'package:card_jigsaw_world/state/profile.dart';
import 'package:card_jigsaw_world/state/rewards.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:card_jigsaw_world/state/sync.dart';
import 'package:card_jigsaw_world/state/unlocks.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(CardJigsawApp)));

  testWidgets('Lucky Wheel pays Peeks and Magic into the stock', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        openFeaturesProvider.overrideWithValue(OpenFeatures.all),
        pendingUnlockIntroProvider.overrideWithValue(null),
      ],
      child: const CardJigsawApp(),
    ));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 5000);

    final profile = container(tester).read(profileProvider.notifier);
    await profile.addTickets(10, reason: 'qa:wheel');
    await settle(tester, 1500);

    // ---- The wheel and its odds.
    container(tester).read(routerProvider).push('/wheel');
    await settle(tester, 2500);
    await shot(tester, 'wb_01_wheel');
    await tapText(tester, 'See odds', ms: 1500);
    expect(find.text('Lucky Wheel odds'), findsOneWidget);
    expect(find.text('Peeks'), findsNWidgets(2));
    expect(find.text('Magic'), findsNWidgets(2));
    expect(find.text('Hints'), findsOneWidget);
    await shot(tester, 'wb_02_odds');
    await tester.tapAt(const Offset(200, 60));
    await settle(tester, 1200);

    // ---- Spin until a Peek or a Magic is won (43% a spin).
    int peeks() => container(tester).read(profileProvider).value?.peeks ?? 0;
    int magics() => container(tester).read(profileProvider).value?.magics ?? 0;
    var spins = 0;
    while (spins < 10 && peeks() == 0 && magics() == 0) {
      await tester.tap(find.text('Spin for'), warnIfMissed: false);
      spins++;
      await settle(tester, 5600);
      final won = find.text('You won').evaluate().isNotEmpty;
      debugPrint('QA_WHEEL spin $spins: won $won, peeks ${peeks()}, magics ${magics()}');
    }
    expect(peeks() + magics(), greaterThan(0), reason: 'a booster in $spins spins');
    await shot(tester, 'wb_03_won_booster');
    final wonPeeks = peeks(), wonMagics = magics();

    // ---- The stock is on the server.
    for (var i = 0; i < 20 && container(tester).read(syncProvider.notifier).debugOps.isNotEmpty; i++) {
      await settle(tester, 500);
    }
    final userId = (await container(tester).read(authProvider.future))!.$id;
    final row = await container(tester).read(tablesProvider).getRow(databaseId: AppwriteConfig.databaseId, tableId: AppwriteConfig.profiles, rowId: userId);
    debugPrint('QA_WHEEL server peeks ${row.data['peeks']} magics ${row.data['magics']}');
    expect(row.data['peeks'], wonPeeks);
    expect(row.data['magics'], wonMagics);

    await tester.tap(find.byIcon(CupertinoIcons.xmark).first, warnIfMissed: false);
    await settle(tester, 1500);

    // ---- A game: the booster bar shows the stock and uses it before coins.
    final packs = await container(tester).read(packsProvider.future);
    final all = await container(tester).read(allPuzzlesProvider.future);
    final free = all.firstWhere((p) => !p.isLockedByDate && (packs.where((k) => k.id == p.packId).firstOrNull?.isFree ?? false));
    container(tester).read(routerProvider).push('/play/${free.id}');
    await settle(tester, 5000);
    await tester.tap(find.textContaining('· Play'), warnIfMissed: false);
    for (var i = 0; i < 30 && find.byType(BoardWidget).evaluate().isEmpty; i++) {
      await settle(tester, 500);
    }
    await settle(tester, 1500);
    if (find.text('Got it').evaluate().isNotEmpty) await tapText(tester, 'Got it');
    if (wonPeeks > 0) expect(find.text('$wonPeeks left'), findsWidgets);
    if (wonMagics > 0) expect(find.text('$wonMagics left'), findsWidgets);
    await shot(tester, 'wb_04_booster_bar_stock');

    final coins = container(tester).read(profileProvider).value!.coins;
    if (wonPeeks > 0) {
      await tester.tap(find.byKey(const ValueKey('booster-peek')), warnIfMissed: false);
      await settle(tester, 4000);
      expect(peeks(), wonPeeks - 1);
      expect(container(tester).read(profileProvider).value!.coins, coins, reason: 'a Peek from stock costs no coins');
    }
    if (wonMagics > 0) {
      await tester.tap(find.byKey(const ValueKey('booster-magic')), warnIfMissed: false);
      await settle(tester, 2500);
      expect(magics(), wonMagics - 1);
      expect(container(tester).read(profileProvider).value!.coins, coins, reason: 'a Magic from stock costs no coins');
    }
    await shot(tester, 'wb_05_after_using_stock');
    debugPrint('QA_WHEEL used stock: peeks ${peeks()} magics ${magics()} coins ${container(tester).read(profileProvider).value!.coins}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
