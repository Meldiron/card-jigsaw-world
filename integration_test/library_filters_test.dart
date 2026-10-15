// Library QA: filter chips with icons (All, Finished, Started, Unlocked,
// Daily, categories), the Hide finished toggle, search, and every place a
// ticket sits on a filled button (pack unlock, past month, access sheet,
// Lucky Wheel, piggy bank, streak restore), in light and dark.
//   xcrun simctl uninstall <udid> com.matejbaco.cardjigsawworld
//   flutter drive --dart-define=CJW_MUTE=true --dart-define=CJW_QA=true \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/library_filters_test.dart -d <udid>
// Captures land in screenshots/lib_*.png.
//
// A fresh guest has no progress, so the test writes progress rows through the
// app's own ProgressNotifier (the save a finished game makes): the smallest
// unlocked library pack finished, one picture of another pack solved. The
// piggy bank and the lost streak are set on the local profile only.
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/daily/daily_reward_sheet.dart';
import 'package:carden/features/daily/piggy_sheet.dart';
import 'package:carden/features/gallery/library_screen.dart';
import 'package:carden/models/models.dart';
import 'package:carden/router.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/progress.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/widgets/icons.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show MaterialApp, ThemeMode;
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
    await settle(tester, 600);
    await binding.takeScreenshot(name);
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

  Future<void> go(WidgetTester tester, String path, {int ms = 3000}) async {
    container(tester).read(routerProvider).go(path);
    await settle(tester, ms);
  }

  Finder chip(String label) => find.byKey(ValueKey('library-chip-$label'));
  Finder inLibrary(Finder f) => find.descendant(of: find.byType(LibraryScreen), matching: f);

  /// The Library back at the top (a drag on the chip row can nudge the page).
  Future<void> toTop(WidgetTester tester) async {
    await tester.fling(inLibrary(find.byType(CustomScrollView)).first, const Offset(0, 1500), 3000);
    await settle(tester, 1200);
  }

  Future<void> tapChip(WidgetTester tester, String label) async {
    final chips = find.descendant(of: find.byKey(const ValueKey('library-chips')), matching: find.byType(Scrollable)).first;
    // Back to the start of the row, then along it until the chip shows.
    await tester.drag(chips, const Offset(3000, 0));
    await settle(tester, 600);
    await tester.dragUntilVisible(chip(label), chips, const Offset(-120, 0));
    await settle(tester, 300);
    await tester.tap(chip(label), warnIfMissed: false);
    await settle(tester, 1200);
    await toTop(tester);
  }

  /// Types into the search field. Tapping it first matters: scrolling the
  /// Library dismisses the keyboard, and enterText alone does not reconnect.
  Future<void> search(WidgetTester tester, String text) async {
    final field = find.byKey(const ValueKey('library-search'));
    await tester.tap(field, warnIfMissed: false);
    await settle(tester, 400);
    await tester.enterText(field, text);
    await settle(tester, 1500);
  }

  /// Local-only profile change (not written to the server), for states a
  /// fresh guest cannot reach in a test: coins in the piggy bank, a lost streak.
  void patchProfile(WidgetTester tester, Map<String, dynamic> patch) {
    final c = container(tester);
    final p = c.read(profileProvider).value!;
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    c.read(profileProvider.notifier).state = AsyncData(Profile.fromRow(p.id, {...p.toData(), ...patch}));
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(200, 60));
    await settle(tester, 1000);
  }

  testWidgets('Library filters, search and tickets on filled buttons', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const CardenApp(),
    ));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 6000); // catalogue and covers

    // A new player: no finished packs yet.
    await go(tester, '/library', ms: 4000);
    expect(find.text('Hide finished'), findsOneWidget);
    expect(chip('Events'), findsNothing);
    await shot(tester, 'lib_01_all_new_player');
    await tapChip(tester, LibraryFilter.finished);
    expect(find.text('No finished packs yet'), findsOneWidget);
    expect(find.text('0 finished'), findsOneWidget);
    await shot(tester, 'lib_02_finished_empty');

    // Progress, written the way a finished game writes it.
    final c = container(tester);
    final packs = await c.read(packsProvider.future);
    final puzzles = await c.read(allPuzzlesProvider.future);
    final profile = c.read(profileProvider.notifier);
    List<Puzzle> of(Pack p) => puzzles.where((z) => z.packId == p.id).toList();
    final library = packs.where((p) => !p.isDaily && !p.hasWindow && profile.isUnlocked(p) && of(p).length >= 4).toList()
      ..sort((a, b) => of(a).length.compareTo(of(b).length));
    expect(library.length, greaterThanOrEqualTo(2), reason: 'two unlocked library packs');
    final finished = library.first, begun = library.last;
    debugPrint('library QA: finished ${finished.id} "${finished.name}" (${of(finished).length}), begun ${begun.id} "${begun.name}"');
    final progress = c.read(progressProvider.notifier);
    Future<void> solve(Puzzle z) async => progress.complete(z.id, gridSize: 9, mode: 'cards', moves: 12, seconds: 60, hints: 0, stars: 3, session: 'qa-${z.id}', resumed: false);
    for (final z in of(finished)) {
      await solve(z);
    }
    await solve(of(begun).first);
    await settle(tester, 2500);

    // Finished: the count in place of the toggle.
    expect(find.text('Hide finished'), findsNothing);
    expect(find.text('1 finished'), findsOneWidget);
    expect(inLibrary(find.text(finished.name)), findsOneWidget);
    await shot(tester, 'lib_03_finished');

    await tapChip(tester, LibraryFilter.started);
    expect(inLibrary(find.text(begun.name)), findsOneWidget);
    expect(inLibrary(find.text(finished.name)), findsNothing);
    await shot(tester, 'lib_04_started');

    await tapChip(tester, LibraryFilter.unlocked);
    await shot(tester, 'lib_05_unlocked');

    await tapChip(tester, LibraryFilter.all);
    expect(inLibrary(find.text(finished.name)), findsOneWidget);
    await shot(tester, 'lib_06_all_toggle_off');
    await tester.tap(find.byKey(const ValueKey('library-hide-finished')));
    await settle(tester, 1500);
    expect(inLibrary(find.text(finished.name)), findsNothing);
    expect(c.read(settingsProvider).hideFinished, isTrue);
    await shot(tester, 'lib_07_all_toggle_on');

    // The finished pack's own category, with the toggle on: nothing left
    // unless the category has other packs.
    await tapChip(tester, finished.category);
    await shot(tester, 'lib_08_category_toggle_on');
    await tester.tap(find.byKey(const ValueKey('library-hide-finished')));
    await settle(tester, 1200);
    await tapChip(tester, LibraryFilter.daily);
    await shot(tester, 'lib_09_daily');
    await tapChip(tester, LibraryFilter.all);

    // Search: a word from the finished pack's name, then nonsense.
    final word = finished.name.split(' ').firstWhere((w) => w.length >= 4, orElse: () => finished.name);
    await search(tester, word.toUpperCase());
    expect(inLibrary(find.text(finished.name)), findsOneWidget);
    await shot(tester, 'lib_10_search_results');
    await search(tester, 'zzqx');
    expect(find.text('Nothing found'), findsOneWidget);
    await shot(tester, 'lib_11_search_none');
    await tapChip(tester, LibraryFilter.started);
    await search(tester, word);
    expect(find.text('Search all packs'), findsOneWidget);
    await shot(tester, 'lib_12_search_in_started_none');
    await search(tester, '');
    expect(find.text('No packs found'), findsNothing);
    await tapChip(tester, LibraryFilter.all);

    // Ticket-priced packs: the price chip on the cover sits on a dark scrim.
    final premium = packs.where((p) => p.priceTickets > 0 && !p.hasWindow && !p.isDaily).firstOrNull;
    if (premium != null) {
      await tapChip(tester, premium.category);
      await shot(tester, 'lib_13_ticket_priced_category');
      await tapChip(tester, LibraryFilter.all);
    }

    // Tickets on filled buttons. A locked ticket pack: "Unlock for [ticket] N",
    // no lock icon, a white ticket on the cobalt button.
    final ticketPack = packs.where((p) => p.priceTickets > 0 && !p.hasWindow && !profile.isUnlocked(p)).firstOrNull;
    if (ticketPack != null) {
      await go(tester, '/library/pack/${ticketPack.id}', ms: 4000);
      expect(find.byIcon(AppIcons.unlock), findsNothing);
      await shot(tester, 'lib_20_ticket_pack_unlock');
      // A locked picture opens the same card in a sheet.
      await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -320));
      await settle(tester, 1500);
      final tiles = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_PuzzleTile');
      if (tiles.evaluate().isNotEmpty) {
        await tester.tap(tiles.first, warnIfMissed: false);
        await settle(tester, 1500);
        await shot(tester, 'lib_21_ticket_pack_sheet');
        await closeSheet(tester);
      }
    }
    // A past month: "Unlock for" as the tinted secondary button.
    final pastMonth = packs.where((p) => p.isDaily && !p.isCurrentMonth && !profile.isUnlocked(p)).firstOrNull;
    if (pastMonth != null) {
      await go(tester, '/library/pack/${pastMonth.id}', ms: 4000);
      await shot(tester, 'lib_22_past_month_unlock');
    }
    // A coin pack, for comparison.
    final coinPack = packs.where((p) => p.priceTickets == 0 && p.priceCoins > 0 && !p.hasWindow && !p.isDaily && !profile.isUnlocked(p)).firstOrNull;
    if (coinPack != null) {
      await go(tester, '/library/pack/${coinPack.id}', ms: 4000);
      await shot(tester, 'lib_23_coin_pack_unlock');
    }

    // Lucky Wheel: "Spin for [ticket] 1".
    await go(tester, '/home', ms: 2500);
    c.read(routerProvider).push('/wheel');
    await settle(tester, 2500);
    await shot(tester, 'lib_24_wheel');
    await tester.tap(find.byIcon(CupertinoIcons.xmark).first, warnIfMissed: false);
    await settle(tester, 1200);

    // Piggy bank with coins inside: "Open for [ticket] 1".
    patchProfile(tester, {'piggyCoins': 120});
    await settle(tester, 300);
    showPiggySheet(tester.element(find.byType(Navigator).last));
    await settle(tester, 1500);
    await shot(tester, 'lib_25_piggy');
    await closeSheet(tester);

    // A streak lost to a missed day (001 B): "Restore [ticket] N" restores it with today's claim.
    patchProfile(tester, {
      'streak': 9,
      'longestStreak': 9,
      'lastDailyClaim': DateTime.now().subtract(const Duration(days: 2)).toUtc().toIso8601String(),
      'lastStreakRestore': null,
    });
    await settle(tester, 300);
    showDailyRewardSheet(tester.element(find.byType(Navigator).last));
    await settle(tester, 1800);
    expect(find.descendant(of: find.byType(DailyRewardSheet), matching: find.text('Restore')), findsOneWidget);
    await shot(tester, 'lib_26_streak_restore');
    await closeSheet(tester);

    // Dark theme: the chips (selected and plain) and the cobalt buttons.
    c.read(settingsProvider.notifier).setThemeMode(ThemeMode.dark);
    await go(tester, '/library', ms: 2500);
    await tapChip(tester, LibraryFilter.finished);
    await shot(tester, 'lib_30_dark_finished');
    await tapChip(tester, LibraryFilter.all);
    await shot(tester, 'lib_31_dark_all');
    await tapChip(tester, LibraryFilter.started);
    await shot(tester, 'lib_31b_dark_started');
    if (ticketPack != null) {
      await go(tester, '/library/pack/${ticketPack.id}', ms: 3000);
      await shot(tester, 'lib_32_dark_ticket_pack_unlock');
    }
    if (pastMonth != null) {
      await go(tester, '/library/pack/${pastMonth.id}', ms: 3000);
      await shot(tester, 'lib_33_dark_past_month_unlock');
    }
    await go(tester, '/home', ms: 2000);
    c.read(routerProvider).push('/wheel');
    await settle(tester, 2500);
    await shot(tester, 'lib_34_dark_wheel');
    await tester.tap(find.byIcon(CupertinoIcons.xmark).first, warnIfMissed: false);
    await settle(tester, 1200);
    showPiggySheet(tester.element(find.byType(Navigator).last));
    await settle(tester, 1500);
    await shot(tester, 'lib_35_dark_piggy');
    await closeSheet(tester);
    showDailyRewardSheet(tester.element(find.byType(Navigator).last));
    await settle(tester, 1800);
    await shot(tester, 'lib_36_dark_streak_restore');
    await closeSheet(tester);
    c.read(settingsProvider.notifier).setThemeMode(ThemeMode.system);
  }, timeout: const Timeout(Duration(minutes: 12)));
}
