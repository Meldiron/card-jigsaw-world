// Twin cards in the dark (owner, TestFlight build 124: "Top right corner is all black, as the
// picture is. The system that makes cards work when they are similar enough is not working"), on
// the real app with a QA guest: Sydney Opera House night on 7x7 Cards (Master), whose night sky and
// dark water are near-black cards with noise and faint stars. A black card is dragged onto another
// black card's place and locks there; the cards with a visible star, lamp or the bridge's truss are
// not among the twins. Screenshots before, while the card is held over its target, just after the
// drop and after.
//
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/twins_night_test.dart -d <simulator>
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/board_widget.dart';
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
    // report finds 0, 1, 2, 3, 8, 11, 35, 42 and 48).
    final black = twins.classes.reduce((a, b) => a.length >= b.length ? a : b);
    const plain = {0, 1, 2, 3, 8, 11, 35, 42, 48};
    expect(black.where(plain.contains).length, greaterThanOrEqualTo(6), reason: 'the black cards of the sky and the water are twins');
    // A visible star (card 7) and the bridge's truss (cards 5 and 6, top right) stay apart.
    for (final apart in [5, 6, 7]) {
      expect(black.contains(apart), isFalse, reason: 'card $apart shows something');
    }
    await shot(tester, 'twins_night_1_dealt', ms: 800);

    // A black card dragged onto another black card's place.
    final b = state.board;
    late int from, to;
    search:
    for (from = 0; from < b.cells; from++) {
      if (!black.contains(b.slots[from])) continue;
      for (final t in black) {
        final moved = t == b.slots[from] ? null : b.moveTo(from, t);
        if (moved != null && twins.settle(b, moved).board.isLocked(t)) {
          to = t;
          break search;
        }
      }
    }
    expect(from, lessThan(b.cells), reason: 'a black card that can go to another black card\'s place');
    debugPrint('QA twins night: card ${b.slots[from]} from slot $from to slot $to (card $to\'s place)');
    // The card starts following the finger once it has moved the pan slop, so the finger goes that
    // much further for the card to land on the target's centre.
    final start = onScreen(tester, from), aim = onScreen(tester, to);
    final end = aim + (aim - start) / (aim - start).distance * kPanSlop;
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 1; i <= 12; i++) {
      await gesture.moveTo(Offset.lerp(start, end, i / 12)!);
      await tester.pump(const Duration(milliseconds: 30));
    }
    await settle(tester, 400);
    await shot(tester, 'twins_night_2_held', ms: 0);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 60));
    await shot(tester, 'twins_night_3_dropped', ms: 0);
    await settle(tester, 1500);
    state = board(tester).state;
    expect(state.board.isLocked(to), isTrue, reason: 'the black card counts as placed');
    await shot(tester, 'twins_night_4_after');
  });
}
