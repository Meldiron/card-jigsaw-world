// Drives the real app (live Appwrite backend) and captures screenshots.
// Run: flutter drive --dart-define=CJW_MUTE=true --driver=test_driver/integration_test.dart \
//        --target=integration_test/screenshots_test.dart -d <simulator>
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
    await settle(tester, 400);
    await binding.takeScreenshot(name);
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  testWidgets('capture screens', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const CardJigsawApp(),
    ));
    await settle(tester, 1500);
    await shot(tester, '01_onboarding');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await shot(tester, '01b_onboarding_3');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 5000); // let catalog + images load
    await shot(tester, '02_home');

    // Daily gift sheet via the streak card's Claim button.
    await tapText(tester, 'Claim');
    await shot(tester, '03_daily_gift');
    if (find.textContaining('Claim day').evaluate().isNotEmpty) {
      await tester.tap(find.textContaining('Claim day'), warnIfMissed: false);
      await settle(tester, 1500);
      await shot(tester, '03b_daily_gift_claimed');
    }
    await tester.tapAt(const Offset(200, 60));
    await settle(tester, 800);

    // Library + this month's daily pack (calendar view).
    await tapText(tester, 'Library', ms: 3000);
    await shot(tester, '04_library');
    await tapText(tester, 'Daily', ms: 1500);
    await shot(tester, '04b_library_daily');
    await tapText(tester, 'October 2026', ms: 4000);
    await shot(tester, '04c_daily_month');
    await tester.tap(find.byIcon(CupertinoIcons.back).first, warnIfMissed: false);
    await settle(tester, 1200);
    // An older month is locked for non-VIP players.
    await tapText(tester, 'September 2026', ms: 3000);
    await shot(tester, '04d_daily_locked');
    await tester.tap(find.byIcon(CupertinoIcons.back).first, warnIfMissed: false);
    await settle(tester, 1200);
    await tapText(tester, 'All', ms: 1200);
    await tapText(tester, 'Wild Nature', ms: 4000);
    await shot(tester, '05_pack');
    // Open first puzzle tile via its title.
    await tapText(tester, 'Hidden Waterfall', ms: 4000);
    await shot(tester, '06_difficulty');
    await tester.dragUntilVisible(find.text('3x3'), find.byType(Scrollable).first, const Offset(0, -200));
    await settle(tester, 600);
    await tapText(tester, '3x3');
    await settle(tester, 500);
    await tester.tap(find.textContaining('Play'), warnIfMissed: false);
    await settle(tester, 6000);
    if (find.text('Got it').evaluate().isNotEmpty) {
      await shot(tester, '07_tutorial');
      await tapText(tester, 'Got it');
    }
    await shot(tester, '08_game_start');
    // Perform a couple of swaps via taps on board cells.
    final boardFinder = find.byWidgetPredicate((w) => w.runtimeType.toString() == 'BoardWidget');
    if (boardFinder.evaluate().isNotEmpty) {
      final rect = tester.getRect(boardFinder.first);
      final cw = rect.width / 3, ch = rect.height / 3;
      Offset cell(int c, int r) => Offset(rect.left + cw * (c + 0.5), rect.top + ch * (r + 0.5));
      await tester.tapAt(cell(0, 0));
      await settle(tester, 300);
      await shot(tester, '09_game_selected');
      await tester.tapAt(cell(1, 1));
      await settle(tester, 800);
      // Build a floating group: put card 1 directly right of card 0 wherever card 0 is.
      {
        final bw = tester.widget<BoardWidget>(boardFinder.first);
        final b = bw.state.board;
        final s0 = b.slotOfCard(0);
        if (!b.isLocked(s0) && s0 % 3 < 2) {
          final s1 = b.slotOfCard(1);
          if (s1 != s0 + 1 && !b.isLocked(s0 + 1)) {
            await tester.tapAt(cell(s1 % 3, s1 ~/ 3));
            await settle(tester, 250);
            await tester.tapAt(cell((s0 + 1) % 3, (s0 + 1) ~/ 3));
            await settle(tester, 900);
          }
        }
      }
      await shot(tester, '09b_game_group');
      // Drag a card onto another.
      await tester.timedDragFrom(cell(2, 2), cell(0, 2) - cell(2, 2), const Duration(milliseconds: 500));
      await settle(tester, 900);
      await shot(tester, '10_game_progress');
    }
    // Pause sheet.
    await tester.tap(find.byIcon(CupertinoIcons.pause_fill), warnIfMissed: false);
    await settle(tester, 900);
    await shot(tester, '11_pause');
    await tapText(tester, 'Resume', ms: 800);

    // Solve the board optimally by sending each misplaced card home.
    for (var guard = 0; guard < 20; guard++) {
      final bf = find.byType(BoardWidget);
      if (bf.evaluate().isEmpty) break;
      final bw = tester.widget<BoardWidget>(bf.first);
      final board = bw.state.board;
      if (board.isSolved) break;
      final rect = tester.getRect(bf.first);
      final cw = rect.width / board.spec.cols, ch = rect.height / board.spec.rows;
      Offset center(int slot) => Offset(rect.left + cw * (slot % board.spec.cols + 0.5), rect.top + ch * (slot ~/ board.spec.cols + 0.5));
      final slot = List.generate(board.cells, (i) => i).firstWhere((i) => !board.isLocked(i));
      await tester.tapAt(center(slot));
      await settle(tester, 250);
      await tester.tapAt(center(board.homeOf(slot)));
      await settle(tester, 450);
    }
    await settle(tester, 2500);
    await shot(tester, '11b_complete');
    await tapText(tester, 'Back to pack', ms: 2000);

    // Store (full-screen modal) from the home header coin pill.
    await tapText(tester, 'Home', ms: 2000);
    await tester.tap(find.byIcon(CupertinoIcons.plus).last, warnIfMissed: false);
    await settle(tester, 1500);
    await shot(tester, '12_store');
    // Rewarded house ad: open, capture, then close early (reward forfeited).
    if (find.text('Watch').evaluate().isNotEmpty) {
      await tapText(tester, 'Watch', ms: 2500);
      await shot(tester, '12b_rewarded_offer');
      await tester.tap(find.textContaining('Reward in'), warnIfMissed: false);
      await settle(tester, 800);
      await shot(tester, '12c_rewarded_close_dialog');
      await tapText(tester, 'Close', ms: 1200);
    }
    await tester.tap(find.byIcon(CupertinoIcons.xmark).first, warnIfMissed: false);
    await settle(tester, 1000);

    // Home → wheel.
    await tapText(tester, 'Home', ms: 2000);
    await tapText(tester, 'Wheel', ms: 1500);
    await shot(tester, '13_wheel');
    if (find.text('Spin for 1 ticket').evaluate().isNotEmpty) {
      await tapText(tester, 'Spin for 1 ticket', ms: 5500);
      await shot(tester, '13b_wheel_result');
    }
    await tester.tap(find.byIcon(CupertinoIcons.xmark).first, warnIfMissed: false);
    await settle(tester, 1000);
    await tapText(tester, 'Piggy bank', ms: 1200);
    await shot(tester, '14_piggy');
    await tester.tapAt(const Offset(200, 60));
    await settle(tester, 800);

    // Quests, Social, Profile, Settings.
    await tapText(tester, 'Quests', ms: 3000);
    await shot(tester, '15_events');
    await tester.fling(find.byType(CustomScrollView).last, const Offset(0, -2200), 2500);
    await settle(tester, 2500);
    await shot(tester, '15b_events_live');
    await tapText(tester, 'Social', ms: 3000);
    await shot(tester, '16_social_league');
    await tapText(tester, 'Friends', ms: 1500);
    await shot(tester, '17_social_friends');
    await tapText(tester, 'Profile', ms: 2000);
    await shot(tester, '18_profile');
    await tester.tap(find.byIcon(CupertinoIcons.gear_alt_fill).first, warnIfMissed: false);
    await settle(tester, 1200);
    await shot(tester, '19_settings');
    // Dark mode.
    await tapText(tester, 'Dark', ms: 1200);
    await shot(tester, '20_settings_dark');
    await tester.tap(find.byIcon(CupertinoIcons.back).first, warnIfMissed: false);
    await settle(tester, 1000);
    await shot(tester, '21_profile_dark');
    await tapText(tester, 'Save progress · create account', ms: 1500);
    await shot(tester, '22_account_dark');
    await tester.tap(find.byIcon(CupertinoIcons.xmark).first, warnIfMissed: false);
    await settle(tester, 800);
    await tapText(tester, 'Home', ms: 2500);
    await shot(tester, '23_home_dark');
    await tapText(tester, 'Library', ms: 2500);
    await tapText(tester, 'Wild Nature', ms: 3000);
    await shot(tester, '24_pack_dark');
    await tapText(tester, 'Hidden Waterfall', ms: 3000);
    if (find.text('4x4').evaluate().isNotEmpty) {
      await tester.dragUntilVisible(find.text('4x4'), find.byType(Scrollable).first, const Offset(0, -200));
      await settle(tester, 600);
      await tapText(tester, '4x4');
      await tester.tap(find.textContaining('Play'), warnIfMissed: false);
    }
    await settle(tester, 6000);
    await shot(tester, '25_game_dark');

    // Each tiling mode on the difficulty screen and its board (dark theme).
    await tester.tap(find.byIcon(CupertinoIcons.pause_fill), warnIfMissed: false);
    await settle(tester, 800);
    await tapText(tester, 'Save & quit', ms: 2000);
    // The last entry picks the smallest honeycomb (Cozy 3x4), which once
    // collapsed into a strip on a handscroll picture and must stay regular.
    for (final (mode, title, tier) in [
      ('Squares', 'Green Valley', null),
      ('Triangles', 'Snowy Peaks', null),
      ('Hexagons', 'Fjord View', null),
      ('Hexagons', 'Canyon Glow', '3x4'),
    ]) {
      await tester.dragUntilVisible(find.text(title), find.byType(Scrollable).first, const Offset(0, -150));
      await settle(tester, 500);
      await tapText(tester, title, ms: 3000);
      if (find.text(mode).evaluate().isEmpty) break;
      await tapText(tester, mode, ms: 800);
      final suffix = tier == null ? mode.toLowerCase() : '${mode.toLowerCase()}_$tier';
      if (tier != null) {
        await tester.dragUntilVisible(find.text(tier), find.byType(Scrollable).first, const Offset(0, -200));
        await settle(tester, 600);
        await tapText(tester, tier);
      }
      await shot(tester, '26_difficulty_$suffix');
      await tester.tap(find.textContaining('Play'), warnIfMissed: false);
      await settle(tester, 6000);
      if (find.text('Got it').evaluate().isNotEmpty) await tapText(tester, 'Got it');
      final bf = find.byType(BoardWidget);
      if (bf.evaluate().isNotEmpty) {
        final rect = tester.getRect(bf.first);
        await tester.tapAt(rect.center);
        await settle(tester, 500);
        await shot(tester, '27_game_$suffix');
        await tester.tapAt(rect.center); // deselect
        await settle(tester, 300);
        // Build one group in this tiling: find a free cell with a cell to its
        // right, and move the picture-right neighbour of its card there.
        final board = tester.widget<BoardWidget>(bf.first).state.board;
        final tiling = board.tiling;
        Offset center(int slot) => rect.topLeft + tiling.cellCenter(slot, rect.size);
        for (var s = 0; s < board.cells; s++) {
          final right = tiling.col(s) < tiling.cols - 1 ? s + 1 : null;
          if (right == null || board.isLocked(s) || board.isLocked(right)) continue;
          final card = board.slots[s];
          if (tiling.col(card) >= tiling.cols - 1) continue;
          final from = board.slotOfCard(card + 1);
          if (from == right || board.groupOf(from).length > 1) continue;
          await tester.tapAt(center(from));
          await settle(tester, 300);
          await tester.tapAt(center(right));
          await settle(tester, 900);
          break;
        }
        await shot(tester, '27b_game_group_$suffix');
      }
      await tester.tap(find.byIcon(CupertinoIcons.pause_fill), warnIfMissed: false);
      await settle(tester, 800);
      await tapText(tester, 'Save & quit', ms: 2000);
    }
    // Profile achievements + avatar picker.
    await tapText(tester, 'Profile', ms: 2000);
    await tester.fling(find.byType(CustomScrollView).last, const Offset(0, -900), 2000);
    await settle(tester, 1500);
    await shot(tester, '28_achievements');
  }, timeout: const Timeout(Duration(minutes: 12)));
}
