// Pack codes on the live backend: a hidden pack stays out of the Library, a wrong code says so,
// a right code (QA_PACK_CODE, a code made for the QA run with tools/dev/pack_codes.py) opens the
// pack, its private pictures load through the signed-in client, a giant board plays them, and
// redeeming the same code again is harmless.
//
// Run: tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//        --target=integration_test/pack_codes_test.dart -d <simulator> \
//        --dart-define=QA_PACK_CODE=XXXX-XXXX-XXXX-XXXX --dart-define=QA_PACK_ID=pack-...
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/features/game/game_screen.dart';
import 'package:carden/router.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/unlocks.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _code = String.fromEnvironment('QA_PACK_CODE');
const _packId = String.fromEnvironment('QA_PACK_ID', defaultValue: 'pack-hidden-object-test');

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
  // Boards here are played the moment they show: no picture before the deal (GameScreen.dealPreview).
  GameScreen.dealPreview = false;

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, 500);
    await binding.takeScreenshot(name);
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(CardenApp)));

  Future<void> openRedeem(WidgetTester tester) async {
    container(tester).read(routerProvider).go('/profile/settings');
    await settle(tester, 2500);
    await tester.dragUntilVisible(find.byKey(const ValueKey('settings-redeem-pack-code')), find.byType(Scrollable).first, const Offset(0, -200));
    await tester.tap(find.byKey(const ValueKey('settings-redeem-pack-code')), warnIfMissed: false);
    await settle(tester, 1200);
    expect(find.byKey(const ValueKey('redeem-code-field')), findsOneWidget);
  }

  Future<void> redeem(WidgetTester tester, String code) async {
    await tester.enterText(find.byKey(const ValueKey('redeem-code-field')), code);
    await settle(tester, 300);
    await tester.tap(find.byKey(const ValueKey('redeem-code-button')), warnIfMissed: false);
    for (var i = 0; i < 40; i++) {
      await settle(tester, 500);
      if (find.byKey(const ValueKey('redeem-code-error')).evaluate().isNotEmpty) return;
      if (find.byKey(const ValueKey('redeem-code-field')).evaluate().isEmpty) return;
    }
  }

  testWidgets('pack codes open a hidden pack with private pictures', (tester) async {
    expect(_code, isNotEmpty, reason: 'pass --dart-define=QA_PACK_CODE=...');
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

    // Hidden: in the catalogue, not in the Library.
    final rows = await container(tester).read(packRowsProvider.future);
    expect(rows.any((p) => p.id == _packId && p.hidden), isTrue, reason: 'the hidden pack row is in the catalogue');
    expect((await container(tester).read(packsProvider.future)).any((p) => p.id == _packId), isFalse, reason: 'not listed before a code');

    // A wrong code says so.
    await openRedeem(tester);
    await shot(tester, 'pc_01_redeem_sheet');
    await redeem(tester, 'AAAA-BBBB-CCCC-DDDD');
    expect(find.text('This code is not valid. Check it and try again.'), findsOneWidget);
    await shot(tester, 'pc_02_wrong_code');

    // The right code opens the pack.
    await redeem(tester, _code.toLowerCase().replaceAll('-', ' '));
    await settle(tester, 4000);
    expect(container(tester).read(profileProvider).value?.unlockedPacks.contains(_packId), isTrue);
    expect((await container(tester).read(packsProvider.future)).any((p) => p.id == _packId), isTrue, reason: 'listed after the code');
    expect(find.text('Hidden Object Adventure'), findsWidgets, reason: 'the pack screen opened');
    await settle(tester, 6000);
    await shot(tester, 'pc_03_pack_opened');

    // A private picture on a giant board.
    final pictures = (await container(tester).read(allPuzzlesProvider.future)).where((p) => p.packId == _packId).toList();
    expect(pictures, hasLength(7));
    container(tester).read(routerProvider).push('/play/${pictures.first.id}');
    await settle(tester, 8000);
    await tapText(tester, 'Cards', ms: 800);
    await tester.dragUntilVisible(find.text('Large'), find.byType(Scrollable).first, const Offset(0, -200));
    await tapText(tester, 'Large', ms: 800);
    await shot(tester, 'pc_04_difficulty');
    await tester.tap(find.byKey(const ValueKey('play-board')), warnIfMissed: false);
    for (var i = 0; i < 40 && find.byType(BoardWidget).evaluate().isEmpty; i++) {
      await settle(tester, 500);
    }
    await settle(tester, 2500);
    if (find.text('Got it').evaluate().isNotEmpty) await tapText(tester, 'Got it');
    expect(find.byType(BoardWidget), findsOneWidget, reason: 'the private picture loaded and dealt');
    await shot(tester, 'pc_05_giant_board');
    await tester.tap(find.byIcon(CupertinoIcons.pause_fill), warnIfMissed: false);
    await settle(tester, 900);
    await tapText(tester, 'Save & quit', ms: 2500);

    // Redeeming again is harmless (a second device, a retry).
    await openRedeem(tester);
    await redeem(tester, _code);
    await settle(tester, 3000);
    expect(find.byKey(const ValueKey('redeem-code-error')), findsNothing, reason: 'a repeat claim is accepted');
    await shot(tester, 'pc_06_repeat');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
