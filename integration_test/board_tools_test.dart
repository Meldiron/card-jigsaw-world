// The toolbar on a normal board (owner, 2026-10-17), on the real app with a QA guest: Shuffle (the
// free round button where Undo was) moves every loose card and leaves cards in place and joined
// groups alone; Magic puts the selected card and its picture neighbours in place, one move each,
// without the "×2 DOUBLE LOCK"; and a card moved onto a pair pushes the pair aside whole.
//
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/board_tools_test.dart -d <simulator>
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/game/board.dart';
import 'package:carden/router.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/giant.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/unlocks.dart';
import 'package:carden/widgets/icons.dart';
import 'package:carden/widgets/ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
  await tester.pump(const Duration(milliseconds: 50));
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
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
  BoardWidget widget(WidgetTester tester) => tester.widget<BoardWidget>(find.byType(BoardWidget).first);
  Board board(WidgetTester tester) => widget(tester).state.board;
  int coins(WidgetTester tester) => container(tester).read(profileProvider).value?.coins ?? 0;

  Offset onScreen(WidgetTester tester, int slot) {
    final w = widget(tester);
    return tester.getRect(find.byType(BoardWidget).first).topLeft + w.state.board.tiling.cellCenter(slot, Size(w.width, w.height));
  }

  Future<void> tapSlot(WidgetTester tester, int slot, {int ms = 400}) async {
    await tester.tapAt(onScreen(tester, slot));
    await settle(tester, ms);
  }

  /// Moves the card at [from] onto [to] the way a player does: tap it, tap the place.
  Future<void> move(WidgetTester tester, int from, int to, {int ms = 900}) async {
    await tapSlot(tester, from, ms: 300);
    await tapSlot(tester, to, ms: ms);
  }

  /// Where the cards of [g] (slots on [before]) went: the common lattice step, or null when the
  /// group was broken up.
  (int, int)? stepOf(Board before, Board after, List<int> g) {
    final t = before.tiling.delta(g.first, after.slotOfCard(before.slots[g.first]));
    if (t == null) return null;
    for (final s in g) {
      if (before.tiling.apply(s, t.$1, t.$2) != after.slotOfCard(before.slots[s])) return null;
    }
    return t;
  }

  bool loose(Board b, int s) => !b.isLocked(s) && b.groupOf(s).length == 1;

  /// Joins two picture neighbours into a loose pair with one tap-tap move: the right-hand card goes
  /// beside the left one. Returns the pair's slots.
  Future<List<int>> makePair(WidgetTester tester) async {
    final b = board(tester);
    final t = b.tiling;
    for (var card = 0; card < b.cells; card++) {
      final right = t.apply(card, 1, 0);
      if (right == null) continue;
      final at = b.slotOfCard(card), from = b.slotOfCard(right);
      final to = t.apply(at, 1, 0);
      if (to == null || to == from || !loose(b, at) || !loose(b, from) || !loose(b, to)) continue;
      final after = b.moveTo(from, to);
      if (after == null) continue;
      final pair = after.groupOf(after.slotOfCard(card));
      if (pair.length != 2 || after.isLocked(pair.first)) continue;
      await move(tester, from, to);
      expect(board(tester).slots, after.slots);
      return pair;
    }
    fail('no pair could be made');
  }

  testWidgets('normal board: Shuffle, Magic and its neighbours, a pushed pair stays whole', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await FirstSteps.skipFor(store); // the whole app; integration_test/first_steps_test.dart plays the first steps
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          openFeaturesProvider.overrideWithValue(OpenFeatures.all),
          pendingUnlockIntroProvider.overrideWithValue(null),
        ],
        child: const CardenApp(),
      ),
    );
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 5000);
    await container(tester).read(profileProvider.notifier).addCoins(2000, reason: 'qa:tools');
    await settle(tester, 800);

    // A picture of a free pack on Cards, Relaxed (4x4 for most pictures).
    final packs = await container(tester).read(packsProvider.future);
    final all = await container(tester).read(allPuzzlesProvider.future);
    final free = {for (final k in packs) if (k.isFree && !isGiantPack(k)) k.id};
    final picture = all.firstWhere((p) => !p.isLockedByDate && free.contains(p.packId));
    container(tester).read(routerProvider).push('/play/${picture.id}');
    await settle(tester, 5000);
    await tapText(tester, 'Cards', ms: 800);
    await tester.dragUntilVisible(find.text('Relaxed'), find.byType(Scrollable).first, const Offset(0, -200));
    await tapText(tester, 'Relaxed', ms: 800);
    await tester.tap(find.textContaining('· Play'), warnIfMissed: false);
    for (var i = 0; i < 30 && find.byType(BoardWidget).evaluate().isEmpty; i++) {
      await settle(tester, 500);
    }
    await settle(tester, 1500);
    if (find.text('Got it').evaluate().isNotEmpty) await tapText(tester, 'Got it');
    expect(find.text('Undo'), findsNothing, reason: 'Shuffle took the place of Undo');
    expect(find.byKey(const ValueKey('booster-shuffle')), findsOneWidget);
    debugPrint('QA_TOOLS board ${board(tester).spec.code} (${board(tester).cells} cards)');
    await shot(tester, 'bt_01_dealt');

    // ---- Shuffle: one card in place and a joined pair first; they stay, every loose card moves.
    final b0 = board(tester);
    final placed = List.generate(b0.cells, (i) => i).firstWhere((s) => loose(b0, s) && loose(b0, b0.homeOf(s)));
    final placedCard = b0.slots[placed];
    await move(tester, placed, b0.homeOf(placed));
    expect(board(tester).isLocked(placedCard), isTrue);
    final pair = await makePair(tester);
    final before = board(tester);
    final movesBefore = widget(tester).state.moves;
    await shot(tester, 'bt_02_before_shuffle');
    await tester.tap(find.byKey(const ValueKey('booster-shuffle')), warnIfMissed: false);
    await settle(tester, 900);
    final after = board(tester);
    var moved = 0, stayed = 0;
    for (var s = 0; s < before.cells; s++) {
      if (before.isLocked(s) || before.groupOf(s).length > 1) {
        expect(after.slots[s], before.slots[s], reason: 'slot $s is in place or in the pair');
        stayed++;
      } else {
        expect(after.slots[s], isNot(before.slots[s]), reason: 'loose slot $s moves');
        moved++;
      }
    }
    debugPrint('QA_SHUFFLE $moved loose cards moved, $stayed stayed (in place or joined: pair $pair)');
    expect(widget(tester).state.moves, movesBefore, reason: 'Shuffle is not a move');
    expect(after.lockedCount, before.lockedCount);
    await shot(tester, 'bt_03_shuffled');

    // ---- Magic on a selected card whose place is inside the board: it and its four neighbours.
    final b1 = board(tester);
    final inner = [for (var c = 0; c < b1.cells; c++) if (b1.tiling.neighbours(c).length == 4 && !b1.isLocked(b1.slotOfCard(c)) && loose(b1, b1.slotOfCard(c))) c];
    expect(inner, isNotEmpty);
    final card = inner.first;
    var expected = b1.moveTo(b1.slotOfCard(card), card)!;
    var sent = 1;
    for (final n in b1.tiling.neighbours(card)) {
      if (expected.isLocked(n)) continue;
      expected = expected.moveTo(expected.slotOfCard(n), n)!;
      sent++;
    }
    final wallet = coins(tester);
    final moves1 = widget(tester).state.moves;
    await tapSlot(tester, b1.slotOfCard(card));
    expect(widget(tester).state.selected, b1.slotOfCard(card));
    await shot(tester, 'bt_04_magic_selected', wait: 0);
    await tester.tap(find.byKey(const ValueKey('booster-magic')), warnIfMissed: false);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('×2 DOUBLE LOCK'), findsNothing, reason: 'Magic is not the player\'s chain');
    }
    await settle(tester, 1200);
    expect(find.textContaining('locked in one move'), findsNothing);
    expect(board(tester).slots, expected.slots);
    for (final c in [card, ...b1.tiling.neighbours(card)]) {
      expect(board(tester).isLocked(c), isTrue, reason: 'card $c is in place');
    }
    expect(widget(tester).state.moves, moves1 + sent, reason: 'one move per card Magic sends');
    expect(wallet - coins(tester), Economy.magicLockCostCoins);
    debugPrint('QA_MAGIC card $card: $sent cards sent, moves $moves1 -> ${widget(tester).state.moves}');
    await shot(tester, 'bt_05_magic_done');

    // ---- A card moved onto a pair: the pair moves aside whole.
    await tester.tap(find.byKey(const ValueKey('booster-shuffle')), warnIfMissed: false);
    await settle(tester, 900);
    final pair2 = await makePair(tester);
    final b2 = board(tester);
    int? pusher, onto;
    for (final cell in pair2) {
      for (var x = 0; x < b2.cells && pusher == null; x++) {
        if (!loose(b2, x) || pair2.contains(x)) continue;
        final t = b2.tiling.delta(x, cell);
        // A neighbour of the pair, so the push is easy to follow.
        if (t == null || t.$1.abs() + t.$2.abs() != 1) continue;
        final next = b2.moveTo(x, cell);
        if (next == null || stepOf(b2, next, pair2) == null || next.isLocked(next.slotOfCard(b2.slots[pair2.first]))) continue;
        pusher = x;
        onto = cell;
      }
    }
    expect(pusher, isNotNull, reason: 'a loose card beside the pair');
    await tapSlot(tester, pusher!, ms: 300);
    await shot(tester, 'bt_06_before_push', wait: 0);
    await tapSlot(tester, onto!, ms: 1000);
    final b3 = board(tester);
    final step = stepOf(b2, b3, pair2);
    expect(step, isNotNull, reason: 'the pair stays whole');
    expect(b3.slots[onto], b2.slots[pusher]);
    debugPrint('QA_PUSH card at $pusher onto $onto: pair $pair2 moved by $step');
    await shot(tester, 'bt_07_pushed');

    // ---- Largest text: the toolbar keeps its labels whole, and a toast with an action (Gather's
    // Undo) lays out without errors.
    final settings = container(tester).read(settingsProvider.notifier);
    final a11y = container(tester).read(settingsProvider).accessibility;
    settings.setAccessibility(a11y.copyWith(textSize: TextSize.largest));
    await settle(tester, 800);
    final ctx = tester.element(find.byType(BoardWidget).first);
    var undone = false;
    showToast(ctx, '12 cards gathered', icon: AppIcons.gather, action: (label: 'Undo', onTap: () => undone = true));
    await settle(tester, 600);
    expect(tester.takeException(), isNull, reason: 'no layout error at Largest');
    expect(tester.getSize(find.byKey(const ValueKey('toast-action'))).height, greaterThanOrEqualTo(44));
    await shot(tester, 'bt_08_largest_text_toast', wait: 0);
    await tester.tap(find.byKey(const ValueKey('toast-action')), warnIfMissed: false);
    await settle(tester, 600);
    expect(undone, isTrue);
    expect(find.byKey(const ValueKey('toast-action')), findsNothing, reason: 'the action closes the toast');
    settings.setAccessibility(a11y);
    await settle(tester, 600);

    await tester.tap(find.byIcon(CupertinoIcons.pause_fill), warnIfMissed: false);
    await settle(tester, 900);
    await tapText(tester, 'Save & quit', ms: 2500);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
