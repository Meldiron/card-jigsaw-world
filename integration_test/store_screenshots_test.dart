// Captures the raw App Store marketing screens (live Appwrite backend).
// Meant for the iPhone 17 Pro Max simulator (6.9", 1320x2868):
//   flutter drive --dart-define=CJW_MUTE=true --driver=test_driver/store_screenshots.dart \
//     --target=integration_test/store_screenshots_test.dart \
//     -d D03644FB-6169-4E87-8E0F-CCFC884FBE78
// Output lands in store/raw/. Then run tools/store/compose_screenshots.py.
import 'package:card_jigsaw_world/app.dart';
import 'package:card_jigsaw_world/core/sfx.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/features/game/board_widget.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
  // The app has infinite animations (shimmer, pulses), so pump for a fixed time.
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

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byIcon(CupertinoIcons.back).first, warnIfMissed: false);
    await settle(tester, 1200);
  }

  /// Makes sure the "Wild Nature" pack gallery is showing. "Back to pack" and
  /// "Save & quit" can land on the Library list instead, so navigate there
  /// explicitly: Library tab, scroll to the top, open the pack.
  Future<void> ensurePack(WidgetTester tester) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (find.textContaining('tap any picture').evaluate().isNotEmpty) return;
      // A scrolled pack grid hides the header text, and its in-progress tile
      // carries a "Continue" badge that the label sweep below would tap.
      if (find.byType(Scrollable).evaluate().isNotEmpty) {
        await tester.fling(find.byType(Scrollable).first, const Offset(0, 6000), 4000, warnIfMissed: false);
        await settle(tester, 1200);
        if (find.textContaining('tap any picture').evaluate().isNotEmpty) return;
      }
      await binding.takeScreenshot('zz_diag_not_pack_$attempt');
      for (final label in ['Got it', 'Continue', 'Collect', 'Claim', 'Not now', 'Close', 'OK', 'Done']) {
        if (find.text(label).evaluate().isNotEmpty) {
          await tapText(tester, label, ms: 1500);
          break;
        }
      }
      if (find.byIcon(CupertinoIcons.xmark).evaluate().isNotEmpty) {
        await tester.tap(find.byIcon(CupertinoIcons.xmark).first, warnIfMissed: false);
        await settle(tester, 1200);
      }
      if (find.text('Library').evaluate().isNotEmpty) {
        await tapText(tester, 'Library', ms: 2500);
      }
      if (find.text('Wild Nature').evaluate().isEmpty && find.byType(Scrollable).evaluate().isNotEmpty) {
        await tester.fling(find.byType(Scrollable).first, const Offset(0, 6000), 4000);
        await settle(tester, 1500);
      }
      if (find.text('All').evaluate().isNotEmpty) await tapText(tester, 'All', ms: 1000);
      if (find.text('Wild Nature').evaluate().isNotEmpty) {
        await tapText(tester, 'Wild Nature', ms: 4000);
      }
    }
  }

  /// Sends misplaced cards home one by one (cards/squares grids only) until
  /// [targetLocked] cells are locked or the board is solved.
  Future<void> solveUntil(WidgetTester tester, {int targetLocked = 999}) async {
    for (var guard = 0; guard < 60; guard++) {
      final bf = find.byType(BoardWidget);
      if (bf.evaluate().isEmpty) break;
      final board = tester.widget<BoardWidget>(bf.first).state.board;
      if (board.isSolved) break;
      final locked = List.generate(board.cells, (i) => i).where(board.isLocked).length;
      if (locked >= targetLocked) break;
      final rect = tester.getRect(bf.first);
      final cw = rect.width / board.spec.cols, ch = rect.height / board.spec.rows;
      Offset center(int slot) => Offset(rect.left + cw * (slot % board.spec.cols + 0.5), rect.top + ch * (slot ~/ board.spec.cols + 0.5));
      final slot = List.generate(board.cells, (i) => i).firstWhere((i) => !board.isLocked(i));
      await tester.tapAt(center(slot));
      await settle(tester, 250);
      await tester.tapAt(center(board.homeOf(slot)));
      await settle(tester, 500);
    }
  }

  /// Opens [title] in the current pack, picks [mode] (and optionally a size
  /// chip) and starts the game, dismissing the tutorial if it shows.
  Future<void> startGame(WidgetTester tester, String title, {String? mode, String? size}) async {
    try {
      await tester.dragUntilVisible(find.text(title), find.byType(Scrollable).first, const Offset(0, -150));
    } catch (_) {
      await binding.takeScreenshot('zz_diag_missing_${title.replaceAll(' ', '_')}');
      await ensurePack(tester);
      await tester.dragUntilVisible(find.text(title), find.byType(Scrollable).first, const Offset(0, -150));
    }
    await settle(tester, 500);
    await tapText(tester, title, ms: 3500);
    if (mode != null && find.text(mode).evaluate().isNotEmpty) {
      await tapText(tester, mode, ms: 800);
    }
    if (size != null && find.text(size).evaluate().isNotEmpty) {
      await tester.dragUntilVisible(find.text(size), find.byType(Scrollable).first, const Offset(0, -200));
      await settle(tester, 500);
      await tapText(tester, size, ms: 500);
    }
    await tester.tap(find.textContaining('Play'), warnIfMissed: false);
    await settle(tester, 6000);
    if (find.text('Got it').evaluate().isNotEmpty) await tapText(tester, 'Got it');
  }

  /// Reaches a tab by label, popping pushed pages (back / close) until the
  /// tab bar is visible. Returns false when it never shows up.
  Future<bool> goTab(WidgetTester tester, String label) async {
    for (var i = 0; i < 4; i++) {
      if (find.text(label).evaluate().isNotEmpty) {
        await tapText(tester, label, ms: 2000);
        return true;
      }
      await binding.takeScreenshot('zz_diag_no_tab_${label.toLowerCase()}_$i');
      for (final icon in [CupertinoIcons.xmark, CupertinoIcons.back]) {
        if (find.byIcon(icon).evaluate().isNotEmpty) {
          await tester.tap(find.byIcon(icon).first, warnIfMissed: false);
          await settle(tester, 1200);
          break;
        }
      }
    }
    return false;
  }

  Future<void> quitGame(WidgetTester tester) async {
    // The pause sheet slides in; a tap that lands before it settles hits the
    // barrier and only closes the sheet, so retry while the HUD is still up.
    for (var attempt = 0; attempt < 3 && find.byIcon(CupertinoIcons.pause_fill).evaluate().isNotEmpty; attempt++) {
      await tester.tap(find.byIcon(CupertinoIcons.pause_fill), warnIfMissed: false);
      await settle(tester, 1200);
      if (find.text('Save & quit').evaluate().isEmpty) continue;
      await tapText(tester, 'Save & quit', ms: 2500);
    }
    await ensurePack(tester);
  }

  testWidgets('capture store screens', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const CardJigsawApp(),
    ));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 5000); // let catalog + images load

    // Claim the daily gift so the streak card shows a 1-day streak.
    if (find.text('Claim').evaluate().isNotEmpty) {
      await tapText(tester, 'Claim');
      if (find.textContaining('Claim day').evaluate().isNotEmpty) {
        await tester.tap(find.textContaining('Claim day'), warnIfMissed: false);
        await settle(tester, 1500);
      }
      await tester.tapAt(const Offset(220, 80));
      await settle(tester, 1000);
    }
    await shot(tester, '01_home');

    // Content-sized glass sheet (piggy bank).
    await tapText(tester, 'Piggy bank', ms: 1200);
    await shot(tester, '18_sheet_piggy');
    await tester.tapAt(const Offset(220, 80));
    await settle(tester, 1000);

    // Daily calendar of the current month.
    await tapText(tester, 'Library', ms: 3000);
    await shot(tester, '02_library');
    await tapText(tester, 'Daily', ms: 1500);
    final month = find.textContaining(' 2026');
    if (month.evaluate().isNotEmpty) {
      await tester.tap(month.first, warnIfMissed: false);
      await settle(tester, 4000);
      await shot(tester, '03_daily_month');
      await back(tester);
    }
    await tapText(tester, 'All', ms: 1200);
    await tapText(tester, 'Wild Nature', ms: 4000);
    await shot(tester, '04_pack');

    // Cards mode: partially solved board with a card selected, then the win screen.
    await startGame(tester, 'Hidden Waterfall', size: '3x3');
    await solveUntil(tester, targetLocked: 5);
    {
      final bf = find.byType(BoardWidget);
      if (bf.evaluate().isNotEmpty) {
        final board = tester.widget<BoardWidget>(bf.first).state.board;
        final rect = tester.getRect(bf.first);
        final cw = rect.width / board.spec.cols, ch = rect.height / board.spec.rows;
        final slot = List.generate(board.cells, (i) => i).firstWhere((i) => !board.isLocked(i), orElse: () => -1);
        if (slot >= 0) {
          await tester.tapAt(Offset(rect.left + cw * (slot % board.spec.cols + 0.5), rect.top + ch * (slot ~/ board.spec.cols + 0.5)));
          await settle(tester, 400);
        }
      }
    }
    await shot(tester, '05_game_cards');
    await solveUntil(tester);
    await settle(tester, 2500);
    await shot(tester, '06_complete');
    if (find.text('Back to pack').evaluate().isNotEmpty) {
      await tapText(tester, 'Back to pack', ms: 2500);
      await ensurePack(tester);
    } else {
      // Board logic in flux: leave through the pause menu instead.
      await quitGame(tester);
    }

    // Hexagons and triangles (one card selected so the highlight shows).
    for (final (mode, title, name) in [('Hexagons', 'Fjord View', '07_game_hexagons'), ('Triangles', 'Snowy Peaks', '08_game_triangles')]) {
      await startGame(tester, title, mode: mode);
      final bf = find.byType(BoardWidget);
      if (bf.evaluate().isNotEmpty) {
        await tester.tapAt(tester.getRect(bf.first).center);
        await settle(tester, 500);
      }
      await shot(tester, name);
      await quitGame(tester);
    }

    // Events and the league.
    await tapText(tester, 'Events', ms: 3500);
    await shot(tester, '09_events');
    await tapText(tester, 'Social', ms: 3500);
    await shot(tester, '10_social_league');

    // Store, then scrolled to the VIP card.
    await tapText(tester, 'Home', ms: 2000);
    await tester.tap(find.byIcon(CupertinoIcons.plus).last, warnIfMissed: false);
    await settle(tester, 2000);
    await shot(tester, '11_store');
    await tester.dragUntilVisible(find.text('Card Jigsaw VIP'), find.byType(Scrollable).first, const Offset(0, -300));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await settle(tester, 1200);
    await shot(tester, '12_store_vip');
    await tester.tap(find.byIcon(CupertinoIcons.xmark).first, warnIfMissed: false);
    await settle(tester, 1000);

    // Achievements (profile, scrolled).
    await tapText(tester, 'Profile', ms: 2500);
    await shot(tester, '13_profile');

    // System alert: rename.
    await tester.tap(find.byIcon(CupertinoIcons.pencil).first, warnIfMissed: false);
    await settle(tester, 1200);
    await shot(tester, '19_rename_alert');
    await tapText(tester, 'Cancel', ms: 1000);
    await tester.fling(find.byType(CustomScrollView).last, const Offset(0, -900), 2000);
    await settle(tester, 1500);
    await shot(tester, '14_achievements');

    // Dark theme variants of the tiling modes and achievements.
    await tester.fling(find.byType(CustomScrollView).last, const Offset(0, 3000), 3000);
    await settle(tester, 1200);
    await tester.tap(find.byIcon(CupertinoIcons.gear_alt_fill).first, warnIfMissed: false);
    await settle(tester, 1200);
    await tapText(tester, 'Dark', ms: 1200);
    await back(tester);
    await tester.fling(find.byType(CustomScrollView).last, const Offset(0, -900), 2000);
    await settle(tester, 1500);
    await shot(tester, '15_achievements_dark');
    await tapText(tester, 'Library', ms: 2500);
    await tapText(tester, 'Wild Nature', ms: 3500);
    for (final (mode, title, name) in [('Hexagons', 'Canyon Glow', '16_game_hexagons_dark'), ('Triangles', 'Northern Lights', '17_game_triangles_dark')]) {
      await startGame(tester, title, mode: mode);
      final bf = find.byType(BoardWidget);
      if (bf.evaluate().isNotEmpty) {
        await tester.tapAt(tester.getRect(bf.first).center);
        await settle(tester, 500);
      }
      await shot(tester, name);
      await quitGame(tester);
    }

    // Dark variants of the tab bar, the sheet and the alert. Best effort:
    // a miss here must not discard the captures above.
    try {
      if (await goTab(tester, 'Home')) {
        await shot(tester, '20_home_dark');
        await tapText(tester, 'Piggy bank', ms: 1200);
        await shot(tester, '21_sheet_piggy_dark');
        await tester.tapAt(const Offset(220, 80));
        await settle(tester, 1000);
      }
      if (await goTab(tester, 'Profile')) {
        // The tab is still scrolled to the achievements; bring the name row back.
        await tester.fling(find.byType(CustomScrollView).last, const Offset(0, 3000), 3000, warnIfMissed: false);
        await settle(tester, 1200);
        await tester.tap(find.byIcon(CupertinoIcons.pencil).first, warnIfMissed: false);
        await settle(tester, 1200);
        await shot(tester, '22_rename_alert_dark');
        await tapText(tester, 'Cancel', ms: 1000);
      }
    } catch (e) {
      await binding.takeScreenshot('zz_diag_dark_extras_failed');
    }
  }, timeout: const Timeout(Duration(minutes: 14)));
}
