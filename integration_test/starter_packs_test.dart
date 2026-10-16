// Six starter packs on the real app (live Appwrite backend): a new player has exactly six free
// library packs, one per category; a pack that was free until 2026-10-14 (Owls) shows its price in
// the Library and on its page, and stays open for a player who had played it.
//
// Run: tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//        --target=integration_test/starter_packs_test.dart -d <simulator>
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/router.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/progress.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/starter_packs.dart';
import 'package:carden/state/unlocks.dart';
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

const _starters = {'wild-nature', 'pack-butterflies', 'pack-paris', 'pack-fruit-markets', 'pack-impressionists', 'pack-tropical-beaches'};

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, 400);
    await binding.takeScreenshot(name);
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(CardenApp)));

  testWidgets('six starter packs; a formerly free pack stays open once played', (tester) async {
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
      ],
      child: const CardenApp(),
    ));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 5000);

    // ---- A new player: six free library packs, one per category.
    final packs = await container(tester).read(packsProvider.future);
    final profile = container(tester).read(profileProvider.notifier);
    final library = packs.where((p) => !p.hasWindow && p.category != 'Daily' && !p.hidden).toList();
    final open = library.where(profile.isUnlocked).toList();
    debugPrint('QA_STARTERS ${library.length} library packs, open: ${open.map((p) => '${p.name} (${p.category})').join(', ')}');
    expect(open.map((p) => p.id).toSet(), _starters);
    expect(open.map((p) => p.category).toSet(), hasLength(6), reason: 'one per category');

    await tapText(tester, 'Library', ms: 3500);
    await shot(tester, 'sp_01_library');

    // ---- Owls was free until today: now it has a price.
    final owls = packs.firstWhere((p) => p.id == 'pack-owls');
    expect(formerlyFreePacks, contains(owls.id));
    expect(owls.isFree, isFalse);
    expect(owls.priceCoins, greaterThanOrEqualTo(2000));
    container(tester).read(routerProvider).push('/library/pack/pack-owls');
    await settle(tester, 2500);
    expect(find.textContaining('Unlock for'), findsWidgets);
    await shot(tester, 'sp_02_owls_priced');
    await tester.tap(find.byIcon(CupertinoIcons.back).first, warnIfMissed: false);
    await settle(tester, 1200);

    // ---- A player who had played Owls before: the pack stays open.
    final owl = (await container(tester).read(allPuzzlesProvider.future)).firstWhere((z) => z.packId == 'pack-owls');
    container(tester).read(progressProvider.notifier).complete(owl.id, gridSize: 20, mode: 'cards', moves: 30, seconds: 120, hints: 0, stars: 3, session: 'qa-before', resumed: false);
    await settle(tester, 2500);
    expect(container(tester).read(playedPacksProvider), contains('pack-owls'));
    expect(profile.isUnlocked(owls), isTrue);
    container(tester).read(routerProvider).push('/library/pack/pack-owls');
    await settle(tester, 2500);
    expect(find.textContaining('Unlock for'), findsNothing);
    await shot(tester, 'sp_03_owls_kept_open');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
