// Pre-set pieces (owner, 2026-10-17; docs/boards.md) on the real app with a QA guest: the sizes
// they fill on the difficulty screen (Triangles 3x3, Hexagons 4x4 and 6x6, no 3x3 honeycomb), what
// each pays (its played pieces only), a 3x3 triangle board played to the end by dragging (its two
// pre-set halves in place from the start and never picked, "0/19 locked"), and the 4x4 and 6x6
// honeycombs dealt, saved and shown in progress.
//
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/preset_pieces_test.dart -d <simulator>
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/features/game/difficulty_screen.dart';
import 'package:carden/features/game/game_screen.dart';
import 'package:carden/game/board.dart';
import 'package:carden/router.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/giant.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/progress.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/unlocks.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show kPanSlop;
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
  final play = find.byKey(const ValueKey('play-board'));
  final expandTile = find.byKey(const ValueKey('expand-option'));

  Offset onScreen(WidgetTester tester, int slot) {
    final w = board(tester);
    final rect = tester.getRect(find.byType(BoardWidget).first);
    return rect.topLeft + w.state.board.tiling.cellCenter(slot, Size(w.width, w.height));
  }

  /// Drags the card at [from] (and its group) onto [to], as a finger does.
  Future<void> drag(WidgetTester tester, int from, int to) async {
    // The card follows the finger once it has moved the pan slop, so the finger goes that much further.
    final start = onScreen(tester, from), aim = onScreen(tester, to);
    final end = aim + (aim - start) / (aim - start).distance * kPanSlop;
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 80));
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset.lerp(start, end, i / 10)!);
      await tester.pump(const Duration(milliseconds: 24));
    }
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.up();
    await settle(tester, 650);
  }

  Future<void> open(WidgetTester tester, String path, {int ms = 5000}) async {
    container(tester).read(routerProvider).push(path);
    await settle(tester, ms);
  }

  Future<void> pickMode(WidgetTester tester, GameMode mode) async {
    await tester.tap(find.byKey(ValueKey('mode-${mode.code}')), warnIfMissed: false);
    await settle(tester, 900);
  }

  Future<void> expandOff(WidgetTester tester) async {
    if (expandTile.evaluate().isEmpty) return;
    await tester.ensureVisible(expandTile);
    await settle(tester, 400);
    final on = tester.widget<CupertinoSwitch>(find.descendant(of: expandTile, matching: find.byType(CupertinoSwitch))).value;
    if (on) {
      await tester.tap(expandTile, warnIfMissed: false);
      await settle(tester, 900);
    }
  }

  Future<void> pickSize(WidgetTester tester, String size) async {
    final chip = find.text(size).first;
    await tester.ensureVisible(chip);
    await settle(tester, 400);
    // The size row runs to the screen's edges, but only the part inside the page's margins takes
    // taps: bring the chip to the middle of the screen first.
    final row = find.ancestor(of: chip, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right)).first;
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final dx = width / 2 - tester.getCenter(chip).dx;
    if (dx.abs() > 40) {
      await tester.drag(row, Offset(dx, 0));
      await settle(tester, 600);
    }
    await tester.tap(chip, warnIfMissed: false);
    await settle(tester, 900);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
    await settle(tester, 500);
  }

  /// The sizes on screen, read from the chips' codes.
  Set<String> shownCodes(WidgetTester tester) => {
        for (final t in tester.widgetList<Text>(find.byType(Text)))
          if (RegExp(r'^\d+x\d+$').hasMatch(t.data ?? '')) t.data!,
      };

  Finder pays(BoardSpec spec) => find.text('${Economy.completionXp(spec.playableCells, 3, mode: spec.mode)} XP');

  /// The XP the rewards line names (for the log when a check fails).
  String xpShown(WidgetTester tester) => [
        for (final t in tester.widgetList<Text>(find.byType(Text)))
          if ((t.data ?? '').endsWith(' XP')) t.data!,
      ].join(', ');

  testWidgets('boards with pre-set pieces: the new sizes, a 3x3 triangle board played to the end', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await FirstSteps.skipFor(store); // the whole app; integration_test/first_steps_test.dart plays the first steps
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        // Every shape open (they open at levels 2 to 10), without intro sheets.
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

    final c = container(tester);
    // Every size open (Expert at level 7): level 10 through the completion call a solve makes.
    for (var i = 0; i < 4; i++) {
      await c.read(profileProvider.notifier).recordCompletion(puzzleId: 'qa-xp-pp-$i', cells: 300, stars: 3, firstTime: true);
      await settle(tester, 1500);
    }
    final packs = c.read(packsProvider).value!;
    final free = {for (final p in packs) if (p.isFree && !p.hasWindow && !isGiantPack(p)) p.id};
    final pictures = [
      ...c.read(allPuzzlesProvider).value!.where((z) => z.id == 'pack-tropical-beaches-01'),
      ...c.read(allPuzzlesProvider).value!.where((z) => free.contains(z.packId) && z.id != 'pack-tropical-beaches-01'),
    ];
    expect(pictures.length, greaterThanOrEqualTo(3));
    final tri = BoardSpec.squareTiers(GameMode.triangles).first;
    final hex4 = BoardSpec.squareTiers(GameMode.hexagons).first;
    final hex6 = BoardSpec.squareTiers(GameMode.hexagons).firstWhere((t) => t.size == '6x6');
    debugPrint('QA preset: pictures ${pictures.take(3).map((z) => z.id).join(', ')}; ${tri.fullCode} ${hex4.fullCode} ${hex6.fullCode}');

    // ---- The difficulty screen: the new sizes and what they pay (their played pieces).
    await open(tester, '/play/${pictures[0].id}');
    expect(find.byType(DifficultyScreen), findsOneWidget);
    await pickMode(tester, GameMode.triangles);
    await expandOff(tester);
    expect(shownCodes(tester), contains('3x3'), reason: 'Triangles have a 3x3 board');
    await pickSize(tester, '3x3');
    await shot(tester, 'pp_difficulty_triangles_3x3');
    debugPrint('QA preset: triangles 3x3 shows ${xpShown(tester)}');
    expect(pays(tri), findsOneWidget, reason: '3 stars pay for 19 pieces');
    await pickMode(tester, GameMode.hexagons);
    await expandOff(tester);
    expect(shownCodes(tester).contains('3x3'), isFalse, reason: 'no 3x3 honeycomb');
    await pickSize(tester, '4x4');
    await shot(tester, 'pp_difficulty_hexagons_4x4');
    debugPrint('QA preset: hexagons 4x4 shows ${xpShown(tester)}');
    expect(pays(hex4), findsOneWidget, reason: '3 stars pay for 14 pieces');
    await pickSize(tester, '6x6');
    await shot(tester, 'pp_difficulty_hexagons_6x6');
    debugPrint('QA preset: hexagons 6x6 shows ${xpShown(tester)}');
    expect(pays(hex6), findsOneWidget, reason: '3 stars pay for 37 pieces');

    // ---- A 3x3 triangle board played to the end, by dragging.
    await pickMode(tester, GameMode.triangles);
    await pickSize(tester, '3x3');
    await tester.tap(play, warnIfMissed: false);
    await settle(tester, 6000);
    var b = board(tester).state.board;
    expect(b.spec, tri);
    expect(b.cells, 21);
    expect([for (var s = 0; s < b.cells; s++) if (b.isPreset(s)) s], [7, 13]);
    expect(b.slots[7], 7);
    expect(b.slots[13], 13);
    expect(b.lockedCount, 0, reason: 'no playable card starts in place');
    expect(find.text('0/19 locked'), findsOneWidget);
    await shot(tester, 'pp_triangles_3x3_board');
    // A pre-set piece is never picked: a tap leaves nothing selected, a drag moves nothing.
    await tester.tapAt(onScreen(tester, 7));
    await settle(tester, 500);
    expect(board(tester).state.selected, isNull);
    final before = board(tester).state.board.slots;
    await drag(tester, 13, 12);
    expect(board(tester).state.board.slots, before, reason: 'a pre-set piece does not move');
    expect(board(tester).state.moves, 0, reason: 'not a move');
    var shotMid = false;
    for (var guard = 0; guard < 60; guard++) {
      b = board(tester).state.board;
      if (b.isSolved) break;
      final slot = List.generate(b.cells, (i) => i).firstWhere((i) => !b.isLocked(i));
      await drag(tester, slot, b.homeOf(slot));
      final now = board(tester).state.board;
      expect(now.slots[7], 7);
      expect(now.slots[13], 13);
      if (!shotMid && now.lockedCount >= 9 && !now.isSolved) {
        shotMid = true;
        expect(find.textContaining('${now.lockedCount}/19 locked'), findsOneWidget);
        await shot(tester, 'pp_triangles_3x3_mid');
      }
    }
    await settle(tester, 4000);
    expect(find.text('Picture complete'), findsOneWidget);
    await shot(tester, 'pp_triangles_3x3_complete');
    final row = c.read(progressProvider).value![pictures[0].id]!;
    expect(row.completed, isTrue);
    expect(row.gridSize, 21, reason: 'the save names the board by every piece');
    expect(row.mode, 'triangles');
    await tapText(tester, 'Back to pack', ms: 3000);

    // ---- The 4x4 and 6x6 honeycombs dealt, saved and shown in progress.
    for (final (spec, picture) in [(hex4, pictures[1]), (hex6, pictures[2])]) {
      await open(tester, '/play/${picture.id}');
      await pickMode(tester, GameMode.hexagons);
      await expandOff(tester);
      await pickSize(tester, spec.size);
      await tester.tap(play, warnIfMissed: false);
      await settle(tester, 6000);
      final dealt = board(tester).state.board;
      expect(dealt.spec, spec);
      expect(dealt.lockedCount, 0);
      for (var s = 0; s < dealt.cells; s++) {
        if (dealt.isPreset(s)) expect(dealt.slots[s], s);
      }
      expect(dealt.joinCount, spec.tiling.unavoidableJoins);
      expect(find.textContaining('0/${spec.playableCells} locked'), findsOneWidget);
      await shot(tester, 'pp_hexagons_${spec.size}_board');
      await tester.tap(find.byIcon(CupertinoIcons.pause_fill), warnIfMissed: false);
      await settle(tester, 800);
      await tapText(tester, 'Save & quit', ms: 2500);
      await open(tester, '/play/${picture.id}');
      expect(find.byKey(const ValueKey('board-in-progress')), findsOneWidget);
      expect(find.text('0 of ${spec.playableCells} in place'), findsOneWidget);
      await shot(tester, 'pp_hexagons_${spec.size}_in_progress');
      expect(c.read(progressProvider).value![picture.id]!.gridSize, spec.cells);
      await tester.tap(find.byIcon(CupertinoIcons.back).first, warnIfMissed: false);
      await settle(tester, 1500);
    }
  });
}
