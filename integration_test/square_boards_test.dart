// Square boards and Expand (owner, 2026-10-17) on the real app with a QA guest: the difficulty
// screen for a tall, a wide and a square picture in every mode (square boards crop the picture,
// the preview shows the part played; Expand lays the sizes out for the picture and is hidden
// where the square boards already suit it), a 3x3 board played to the end, a 3x4 board saved by
// an older build resumed as it was, and a Giant pack picture.
//
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/square_boards_test.dart -d <simulator>
import 'dart:ui' as ui;

import 'package:carden/app.dart';
import 'package:carden/core/image_files.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/data/sync/ops.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/features/game/difficulty_screen.dart';
import 'package:carden/game/board.dart';
import 'package:carden/models/models.dart';
import 'package:carden/router.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/giant.dart';
import 'package:carden/state/progress.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/settings.dart';
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

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

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
  BoardWidget board(WidgetTester tester) => tester.widget<BoardWidget>(find.byType(BoardWidget).first);
  final expandTile = find.byKey(const ValueKey('expand-option'));
  final play = find.byKey(const ValueKey('play-board'));

  bool expandOn(WidgetTester tester) => tester.widget<CupertinoSwitch>(find.descendant(of: expandTile, matching: find.byType(CupertinoSwitch))).value;

  Offset onScreen(WidgetTester tester, int slot) {
    final w = board(tester);
    final rect = tester.getRect(find.byType(BoardWidget).first);
    return rect.topLeft + w.state.board.tiling.cellCenter(slot, Size(w.width, w.height));
  }

  /// Sends every misplaced card home, one tap-tap move at a time.
  Future<void> solve(WidgetTester tester) async {
    for (var guard = 0; guard < 80; guard++) {
      final b = board(tester).state.board;
      if (b.isSolved) return;
      final slot = List.generate(b.cells, (i) => i).firstWhere((i) => !b.isLocked(i));
      await tester.tapAt(onScreen(tester, slot));
      await settle(tester, 250);
      await tester.tapAt(onScreen(tester, b.homeOf(slot)));
      await settle(tester, 450);
    }
  }

  Future<void> open(WidgetTester tester, String path, {int ms = 5000}) async {
    container(tester).read(routerProvider).push(path);
    await settle(tester, ms);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byIcon(CupertinoIcons.back).first, warnIfMissed: false);
    await settle(tester, 1500);
  }

  Future<void> pickMode(WidgetTester tester, GameMode mode) async {
    await tester.tap(find.byKey(ValueKey('mode-${mode.code}')), warnIfMissed: false);
    await settle(tester, 900);
  }

  /// The Expand row brought into view (it sits under the sizes), or false when the picture has none.
  Future<bool> showExpand(WidgetTester tester) async {
    if (expandTile.evaluate().isEmpty) return false;
    await tester.ensureVisible(expandTile);
    await settle(tester, 500);
    return true;
  }

  Future<void> setExpand(WidgetTester tester, bool on) async {
    if (!await showExpand(tester) || expandOn(tester) == on) return;
    await tester.tap(expandTile, warnIfMissed: false);
    await settle(tester, 900);
    expect(expandOn(tester), on);
  }

  /// The sizes on screen, read from the chips' codes.
  Set<String> shownCodes(WidgetTester tester) => {
        for (final t in tester.widgetList<Text>(find.byType(Text)))
          if (RegExp(r'^\d+x\d+$').hasMatch(t.data ?? '')) t.data!,
      };

  testWidgets('square boards, Expand and old boards on real pictures', (tester) async {
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

    // Pictures by shape, from the sizes in their files' headers (nothing decoded): the two known
    // ones first (a 2:3 beach and a square butterfly), then the free packs, then the rest.
    final c = container(tester);
    final packs = c.read(packsProvider).value!;
    final all = c.read(allPuzzlesProvider).value!;
    final giantPacks = {for (final p in packs) if (isGiantPack(p)) p.id};
    final free = {for (final p in packs) if (p.isFree && !p.hasWindow && !isGiantPack(p)) p.id};
    Future<double?> aspectOf(Puzzle z) async {
      try {
        return await tester.runAsync(() async {
          final bytes = await ImageFiles.bytes(z.thumbUrl.isEmpty ? z.imageUrl : z.thumbUrl).timeout(const Duration(seconds: 15));
          final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
          final d = await ui.ImageDescriptor.encoded(buffer);
          final a = d.width / d.height;
          d.dispose();
          buffer.dispose();
          return a;
        });
      } catch (e) {
        debugPrint('QA square boards: no size for ${z.id}: $e');
        return null;
      }
    }

    Puzzle? tall, wide, square;
    final aspects = <String, double>{};
    final candidates = [
      ...all.where((z) => z.id == 'pack-tropical-beaches-01' || z.id == 'pack-butterflies-01'),
      ...all.where((z) => free.contains(z.packId)),
      ...all.where((z) => !free.contains(z.packId) && !giantPacks.contains(z.packId)),
    ];
    for (final z in candidates.take(60)) {
      if (tall != null && wide != null && square != null) break;
      if (aspects.containsKey(z.id)) continue;
      final a = await aspectOf(z);
      if (a == null) continue;
      aspects[z.id] = a;
      if (tall == null && a > 0.6 && a < 0.7) tall = z;
      if (wide == null && a > 1.2 && a < 1.8) wide = z;
      if (square == null && (a - 1).abs() < 0.02) square = z;
    }
    debugPrint('QA square boards: tall ${tall?.id} ${aspects[tall?.id]}, wide ${wide?.id} ${aspects[wide?.id]}, square ${square?.id} ${aspects[square?.id]}');
    expect(tall, isNotNull, reason: 'a tall (2:3) picture among the free packs');

    // ---- A tall picture: every mode, square (cropped) and with Expand.
    await open(tester, '/play/${tall!.id}');
    expect(find.byType(DifficultyScreen), findsOneWidget);
    final ta = aspects[tall.id]!;
    for (final mode in GameMode.values) {
      await pickMode(tester, mode);
      await setExpand(tester, false);
      final sq = BoardSpec.squareTiers(mode);
      expect(shownCodes(tester).intersection({for (final t in sq) t.code}), isNotEmpty, reason: '${mode.code}: square sizes');
      expect(shownCodes(tester).every((code) => sq.any((t) => t.code == code)), isTrue, reason: '${mode.code}: only square sizes, ${shownCodes(tester)}');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
      await settle(tester, 600);
      await shot(tester, 'sb_tall_${mode.code}_square');
      final offered = BoardSpec.offersExpand(mode, ta);
      expect(await showExpand(tester), offered, reason: '${mode.code} on $ta: Expand ${offered ? 'offered' : 'hidden'}');
      if (offered) {
        await setExpand(tester, true);
        final ex = {for (final t in BoardSpec.expandTiers(mode, ta)) t.code};
        expect(shownCodes(tester).intersection(ex), isNotEmpty, reason: '${mode.code}: Expand sizes $ex, shown ${shownCodes(tester)}');
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
        await settle(tester, 600);
        await shot(tester, 'sb_tall_${mode.code}_expand');
        await setExpand(tester, false);
      }
    }
    await back(tester);

    // ---- A wide picture (the catalogue is portrait or square, docs/content-rules.md; My Puzzles photos
    // can be wide): Expand where it shows more. test/difficulty_screen_test.dart covers it offline.
    if (wide != null) {
      final wa = aspects[wide.id]!;
      await open(tester, '/play/${wide.id}');
      for (final mode in [GameMode.squares, GameMode.cards, GameMode.hexagons]) {
        await pickMode(tester, mode);
        await setExpand(tester, false);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
        await settle(tester, 600);
        await shot(tester, 'sb_wide_${mode.code}_square');
        expect(await showExpand(tester), BoardSpec.offersExpand(mode, wa), reason: '${mode.code} on $wa');
        if (expandTile.evaluate().isNotEmpty) {
          await setExpand(tester, true);
          await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
          await settle(tester, 600);
          await shot(tester, 'sb_wide_${mode.code}_expand');
          await setExpand(tester, false);
        }
      }
      await back(tester);
    }

    // ---- A square picture: no Expand in Squares; Cards offer it.
    if (square != null) {
      await open(tester, '/play/${square.id}');
      await pickMode(tester, GameMode.squares);
      expect(expandTile, findsNothing, reason: 'a square picture plays whole on square boards');
      await shot(tester, 'sb_square_squares');
      await pickMode(tester, GameMode.cards);
      expect(await showExpand(tester), isTrue);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
      await settle(tester, 600);
      await shot(tester, 'sb_square_cards');
      await back(tester);
    }

    // ---- A 3x3 Cards board played to the end (on the tall picture: cropped to the board).
    await open(tester, '/play/${tall.id}');
    await pickMode(tester, GameMode.cards);
    await setExpand(tester, false);
    await tester.dragUntilVisible(find.text('3x3'), find.byType(Scrollable).first, const Offset(0, -200));
    await tapText(tester, '3x3', ms: 700);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
    await settle(tester, 600);
    expect(find.descendant(of: play, matching: find.text('Play')), findsOneWidget, reason: 'the button says Play, nothing more');
    await shot(tester, 'sb_3x3_chosen');
    await tester.tap(play, warnIfMissed: false);
    await settle(tester, 6000);
    if (find.text('Got it').evaluate().isNotEmpty) await tapText(tester, 'Got it');
    expect(board(tester).state.board.spec.code, '3x3');
    await shot(tester, 'sb_3x3_board');
    await solve(tester);
    await settle(tester, 4000);
    expect(find.text('Picture complete'), findsOneWidget);
    await shot(tester, 'sb_3x3_complete');
    expect(c.read(progressProvider).value![tall.id]!.gridSize, 9);

    // ---- A board an older build saved: the first of its sizes for this picture that is not square, three moves in.
    final other = all.firstWhere((z) => z.id != tall!.id && free.contains(z.packId) && aspects[z.id] != null && (aspects[z.id]! - ta).abs() < 0.02, orElse: () => tall!);
    final oa = aspects[other.id]!;
    final old = BoardSpec.tiers(GameMode.cards, oa).firstWhere((t) => t.cols != t.rows);
    debugPrint('QA old board: ${other.id} on $oa, ${old.fullCode}');
    final layout = Board.shuffled(old, seed: 4).slots;
    c.read(progressProvider.notifier).saveBoard(other.id, gridSize: old.cells, mode: 'cards', layout: layout, moves: 3, seconds: 20, hints: 0, session: SyncOp.newId(), resumed: false);
    await settle(tester, 2500);
    await open(tester, '/play/${other.id}');
    expect(find.byKey(const ValueKey('board-in-progress')), findsOneWidget);
    expect(find.textContaining('Cards · ${old.code}'), findsOneWidget, reason: 'the old board is kept: ${old.code}');
    expect(find.descendant(of: play, matching: find.text('Continue')), findsOneWidget);
    await shot(tester, 'sb_old_board_difficulty');
    await tester.tap(play, warnIfMissed: false);
    await settle(tester, 6000);
    final resumed = board(tester).state.board;
    expect(resumed.spec.code, old.code, reason: 'resumed as it was saved');
    expect(resumed.slots, layout);
    expect(board(tester).state.moves, 3);
    await shot(tester, 'sb_old_board_resumed');
    await tester.tap(find.byIcon(CupertinoIcons.pause_fill), warnIfMissed: false);
    await settle(tester, 800);
    await tapText(tester, 'Save & quit', ms: 2500);

    // ---- A Giant pack picture: square giant sizes, Expand where the picture asks for it.
    final giantPack = packs.where(isGiantPack).firstOrNull;
    if (giantPack != null) {
      final g = all.firstWhere((z) => z.packId == giantPack.id);
      await open(tester, '/play/${g.id}', ms: 9000);
      for (final label in BoardSpec.giantLabels) {
        expect(find.text(label), findsWidgets, reason: 'giant ladder shows $label');
      }
      final sq = BoardSpec.squareGiantTiers(GameMode.cards);
      expect(find.text(sq.first.code), findsWidgets, reason: 'Large is ${sq.first.code}');
      await shot(tester, 'sb_giant_square');
      debugPrint('QA giant: ${giantPack.id} ${g.id}, Expand in Cards ${expandTile.evaluate().isNotEmpty}');
      // Squares: square giant boards, and Expand for a picture that is not square.
      await pickMode(tester, GameMode.squares);
      expect(find.text(BoardSpec.squareGiantTiers(GameMode.squares).first.code), findsWidgets);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
      await settle(tester, 600);
      await shot(tester, 'sb_giant_squares_square');
      if (await showExpand(tester)) {
        await setExpand(tester, true);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
        await settle(tester, 600);
        await shot(tester, 'sb_giant_squares_expand');
        // Play deals the giant Expand board.
        await tester.tap(play, warnIfMissed: false);
        await settle(tester, 9000);
        final spec = board(tester).state.board.spec;
        debugPrint('QA giant Expand board: ${spec.fullCode} ${spec.cells}');
        expect(spec.isGiant, isTrue);
        await shot(tester, 'sb_giant_squares_expand_board');
      }
    }
  });
}
