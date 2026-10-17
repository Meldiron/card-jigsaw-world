// Twin cards in the dark (owner, TestFlight build 124: "Top right corner is all black, as the
// picture is. The system that makes cards work when they are similar enough is not working"), on
// the real app with a QA guest: Sydney Opera House night on 7x7 Cards (Master), whose night sky and
// dark water are near-black cards with noise and faint stars. Since the middle option (owner,
// 2026-10-17: a few pin-point stars do not keep a card apart) the corner cards 7 and 14, a few stars
// on the black, are twins of the black sky too, and the bridge's edge, truss and lamp (4, 5, 6, 12,
// 13) stay apart. Card 0 (black sky) is dragged onto card 7's place and locks there; then a card of
// the truss is dragged onto a black card's place and does not. Screenshots before, while the card is
// held over its target, just after the drop and after, for both drops.
//
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/twins_night_test.dart -d <simulator>
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/features/game/game_screen.dart';
import 'package:carden/router.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/unlocks.dart';
import 'package:flutter/gestures.dart' show kPanSlop;
import 'package:flutter/material.dart';
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
  // Boards here are played the moment they show: no picture before the deal (GameScreen.dealPreview).
  GameScreen.dealPreview = false;

  const puzzle = 'p-a55d13313304';

  Future<void> shot(WidgetTester tester, String name, {int ms = 500}) async {
    if (ms > 0) await settle(tester, ms);
    await binding.takeScreenshot(name);
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(CardenApp)));
  BoardWidget board(WidgetTester tester) => tester.widget<BoardWidget>(find.byType(BoardWidget).first);

  Offset onScreen(WidgetTester tester, int slot) {
    final w = board(tester);
    final rect = tester.getRect(find.byType(BoardWidget).first);
    return rect.topLeft + w.state.board.tiling.cellCenter(slot, Size(w.width, w.height));
  }

  testWidgets('twin cards at night: a black card on another black card\'s place locks', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await FirstSteps.skipFor(store);
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

    container(tester).read(routerProvider).push('/game/$puzzle/cards-7x7t7');
    for (var i = 0; i < 40 && (find.byType(BoardWidget).evaluate().isEmpty || board(tester).state.twins == null); i++) {
      await settle(tester, 500);
    }
    var state = board(tester).state;
    final twins = state.twins!;
    debugPrint('QA twins night: ${state.board.spec.code}: ${twins.classes}');
    expect(state.board.spec.code, '7x7');
    // The plain night sky in the top left and the dark water: one class of black cards (the
    // report finds 0, 1, 2, 3, 7, 8, 11, 14, 35, 42 and 48).
    final black = twins.classes.reduce((a, b) => a.length >= b.length ? a : b);
    const plain = {0, 1, 2, 3, 8, 11, 35, 42, 48};
    expect(black.where(plain.contains).length, greaterThanOrEqualTo(6), reason: 'the black cards of the sky and the water are twins');
    // A few pin-point stars (cards 7 and 14) do not keep a card apart; the bridge's edge, truss and
    // lamp (4, 5, 6, 12, 13) do.
    for (final speckled in [7, 14]) {
      expect(black.contains(speckled), isTrue, reason: 'card $speckled has only a few pin-point stars');
    }
    for (final apart in [4, 5, 6, 12, 13]) {
      expect(black.contains(apart), isFalse, reason: 'card $apart shows the bridge');
    }
    await shot(tester, 'twins_night_1_dealt', ms: 800);

    // Drags the card at slot [from] onto slot [to] the way a finger does, with screenshots while it
    // is held over the target and just after the drop.
    Future<void> drag(int from, int to, String name) async {
      // The card starts following the finger once it has moved the pan slop, so the finger goes
      // that much further for the card to land on the target's centre.
      final start = onScreen(tester, from), aim = onScreen(tester, to);
      final end = aim + (aim - start) / (aim - start).distance * kPanSlop;
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 1; i <= 12; i++) {
        await gesture.moveTo(Offset.lerp(start, end, i / 12)!);
        await tester.pump(const Duration(milliseconds: 30));
      }
      await settle(tester, 400);
      await shot(tester, '${name}_held', ms: 0);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 60));
      await shot(tester, '${name}_dropped', ms: 0);
      await settle(tester, 1500);
    }

    // Card 0, black sky, onto card 7's place (a few stars): it counts as placed.
    var b = state.board;
    final from0 = b.slotOfCard(0);
    expect(b.isLocked(7), isFalse);
    debugPrint('QA twins night: card 0 from slot $from0 to slot 7 (card 7\'s place)');
    await drag(from0, 7, 'twins_night_2_card0_on_7');
    state = board(tester).state;
    expect(state.board.isLocked(7), isTrue, reason: 'the black card counts as placed on the place of the card with a few stars');
    await shot(tester, 'twins_night_3_after');

    // A card of the bridge's truss onto a black card's place: it does not.
    b = state.board;
    final truss = b.slotOfCard(5);
    final target = black.firstWhere((t) => t != 7 && !b.isLocked(t) && b.slots[t] != 5 && t != truss);
    debugPrint('QA twins night: card 5 (truss) from slot $truss to slot $target (card $target\'s place)');
    await drag(truss, target, 'twins_night_4_truss');
    state = board(tester).state;
    expect(state.board.isLocked(target), isFalse, reason: 'the truss card does not count as placed on a black card\'s place');
    await shot(tester, 'twins_night_5_after');
  });
}
