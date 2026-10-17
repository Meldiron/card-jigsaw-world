// Twin cards (docs/twins.md) on the real app with a QA guest: a catalogue picture with a plain sky
// (a long-tail boat on a beach, 5x5 Cards: the five sky cards of the top row are twins). One sky
// card is dragged onto another sky card's place and locks there without a visible change; another
// is put above the card that belongs under a third sky card and joins it. Screenshots before,
// while the card is held over its target, just after the drop (during the cross-fade) and after.
//
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/twins_test.dart -d <simulator>
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/router.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/unlocks.dart';
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

  const puzzle = 'p-952b19c3ce8f';

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

  /// Drags the card at [from] onto [to] with a real finger, holding it over the target for a
  /// screenshot ([held]) and taking one just after the drop ([dropped]).
  Future<void> drag(WidgetTester tester, int from, int to, {required String held, required String dropped}) async {
    final start = onScreen(tester, from), end = onScreen(tester, to);
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 1; i <= 12; i++) {
      await gesture.moveTo(Offset.lerp(start, end, i / 12)!);
      await tester.pump(const Duration(milliseconds: 30));
    }
    await settle(tester, 400);
    await shot(tester, held, ms: 0);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 60));
    await shot(tester, dropped, ms: 0);
    await settle(tester, 1500);
  }

  testWidgets('twin cards: placed and joined by an identity swap', (tester) async {
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

    container(tester).read(routerProvider).push('/game/$puzzle/cards-5x5t4');
    // The picture is decoded and measured, then the board is dealt with its twins.
    for (var i = 0; i < 40 && (find.byType(BoardWidget).evaluate().isEmpty || board(tester).state.twins == null); i++) {
      await settle(tester, 500);
    }
    var state = board(tester).state;
    final twins = state.twins!;
    debugPrint('QA twins: ${twins.classes}');
    expect(twins.classes.any((k) => k.toSet().containsAll([0, 1, 2, 3, 4])), isTrue, reason: 'the five sky cards of the top row are twins');
    // Dealt with them: no card on a twin's place, no pair looking joined.
    var b = state.board;
    for (var s = 0; s < b.cells; s++) {
      expect(twins.looksPlaced(b.slots[s], s), isFalse, reason: 'slot $s');
      for (final t in b.tiling.neighbours(s)) {
        expect(twins.looksJoined(b.tiling, s, b.slots[s], t, b.slots[t]), isFalse, reason: 'slots $s and $t');
      }
    }
    await shot(tester, 'twins_1_dealt', ms: 800);

    // ---- Placed: a sky card dragged onto another sky card's place locks.
    late int from, to;
    search:
    for (from = 0; from < b.cells; from++) {
      if (b.slots[from] > 4) continue;
      for (to = 0; to < 5; to++) {
        final moved = to == b.slots[from] ? null : b.moveTo(from, to);
        if (moved != null && twins.settle(b, moved).board.isLocked(to)) break search;
      }
    }
    expect(from, lessThan(b.cells), reason: 'a sky card that can go to another sky card\'s place');
    final dropped = b.slots[from];
    debugPrint('QA twins: card $dropped from slot $from to slot $to (card $to\'s place)');
    await drag(tester, from, to, held: 'twins_2_place_held', dropped: 'twins_3_place_dropped');
    state = board(tester).state;
    expect(state.board.isLocked(to), isTrue, reason: 'the sky card counts as placed');
    expect(state.cardKeys?[to], dropped, reason: 'the widget of the card that was dropped is the one in place');
    await shot(tester, 'twins_4_place_after');

    // ---- Joined: a sky card put above the card that belongs under another sky card joins it.
    b = state.board;
    int? jFrom, jTo, under;
    for (var m = 5; m < 10 && jFrom == null; m++) {
      // Card m belongs under card m - 5 (a sky card): any other loose sky card put above m joins.
      final p = b.slotOfCard(m);
      final above = p - 5;
      if (p < 5 || b.isLocked(p) || b.isLocked(above) || b.groupOf(p).length > 1) continue;
      for (var c = 0; c < 5; c++) {
        final at = b.slotOfCard(c);
        if (c == m - 5 || b.isLocked(at) || b.groupOf(at).length > 1 || at == above) continue;
        final moved = b.moveTo(at, above);
        if (moved == null) continue;
        final settled = twins.settle(b, moved).board;
        if (settled.joined(above, p) && settled.slots[p] == m) {
          jFrom = at;
          jTo = above;
          under = p;
          break;
        }
      }
    }
    expect(jFrom, isNotNull, reason: 'a sky card that can go above a card of the second row');
    debugPrint('QA twins: card ${b.slots[jFrom!]} from slot $jFrom to slot $jTo, above card ${b.slots[under!]}');
    await drag(tester, jFrom, jTo!, held: 'twins_5_join_held', dropped: 'twins_6_join_dropped');
    state = board(tester).state;
    expect(state.board.joined(jTo, under), isTrue, reason: 'the sky card joins the card under it');
    await shot(tester, 'twins_7_join_after');
  });
}
