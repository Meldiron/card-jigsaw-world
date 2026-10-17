// QA of a feedback round (owner, 2026-10-17) on a fresh QA guest against the live backend, in this order:
// confetti when the daily gift is claimed, Store > Earn for free > Play a puzzle starting Quick play,
// the Home title's spacing (default and Largest text), Packs in progress just above the live events,
// and the one done badge on finished packs (covers, Finished packs rows, the See all page, the pack
// page; light and dark).
//   xcrun simctl uninstall <udid> com.matejbaco.cardjigsawworld
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/home_store_gift_test.dart -d <udid>
// Captures land in screenshots/hsg_*.png.
//
// Progress is written through the app's own ProgressNotifier (the save a finished game makes), as in
// integration_test/home_rows_test.dart: one pack with three stars everywhere, one finished short of
// stars, two started.
import 'dart:async';

import 'package:carden/app.dart';
import 'package:carden/core/app_links.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/difficulty_screen.dart';
import 'package:carden/features/links/deep_links.dart';
import 'package:carden/features/store/store_screen.dart';
import 'package:carden/game/modes.dart';
import 'package:carden/models/models.dart';
import 'package:carden/router.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/progress.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/unlocks.dart';
import 'package:carden/state/rewards.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
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

  Future<void> shot(WidgetTester tester, String name, {int ms = 600}) async {
    await settle(tester, ms);
    await binding.takeScreenshot('hsg_$name');
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

  /// Scrolls the page until [f] sits at [alignment] of the viewport.
  Future<void> scrollTo(WidgetTester tester, Finder f, {double alignment = 0.12, Finder? within}) async {
    await tester.scrollUntilVisible(f, 250, scrollable: within ?? find.byType(Scrollable).first, maxScrolls: 60);
    await settle(tester, 600);
    unawaited(Scrollable.ensureVisible(tester.element(f), alignment: alignment, duration: const Duration(milliseconds: 300)));
    await settle(tester, 1500);
  }

  testWidgets('Home, Store and daily gift feedback round', (tester) async {
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
    await settle(tester, 6000); // catalogue and covers
    final c = container(tester);

    // ---- Daily gift: confetti over the sheet once the gift is claimed.
    if (find.textContaining('Claim day').evaluate().isEmpty) {
      unawaited(c.read(deepLinksProvider).show(AppLink.parse(Uri(path: '/gift'))!));
      await settle(tester, 2000);
    }
    expect(find.textContaining('Claim day'), findsOneWidget, reason: 'the daily gift is ready for a new guest');
    await shot(tester, '01_gift_before');
    await tester.tap(find.textContaining('Claim day'), warnIfMissed: false);
    // The claim is saved first (the sync queue), then the burst starts.
    for (var i = 0; i < 80 && find.byType(ConfettiWidget).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(ConfettiWidget), findsOneWidget, reason: 'a claim plays the confetti');
    await shot(tester, '02_gift_confetti', ms: 350);
    await shot(tester, '03_gift_confetti_later', ms: 600);
    await settle(tester, 4000);
    await tapText(tester, 'Close', ms: 1500);
    // The reminder question may follow the first claim.
    if (find.text('Not now').evaluate().isNotEmpty) await tapText(tester, 'Not now');

    await go(tester, '/home', ms: 2000);
    // ---- Store > Earn for free > Play a puzzle: the Store closes and Quick play opens a picture.
    unawaited(c.read(routerProvider).push('/store'));
    await settle(tester, 3000);
    final row = find.byKey(const ValueKey('store-play-puzzle'));
    await scrollTo(tester, find.text('Earn for free'), alignment: 0.15, within: find.descendant(of: find.byType(StoreScreen), matching: find.byType(Scrollable)).first);
    expect(row, findsOneWidget);
    await shot(tester, '02b_store_earn_for_free');
    await tester.tap(row, warnIfMissed: false);
    await settle(tester, 4000);
    expect(find.byType(StoreScreen), findsNothing, reason: 'the Store closed');
    expect(find.byType(DifficultyScreen), findsOneWidget, reason: 'Quick play opened a picture');
    await shot(tester, '02c_store_quick_play');

    // ---- Home's large title: the date and the greeting with room around them.
    await go(tester, '/home');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await settle(tester, 1500);
    await shot(tester, '04_home_title');
    final settings = c.read(settingsProvider.notifier);
    settings.setAccessibility(const Accessibility(textSize: TextSize.largest));
    await shot(tester, '05_home_title_largest', ms: 1500);
    expect(tester.takeException(), isNull);
    settings.setAccessibility(const Accessibility());
    await settle(tester, 1000);

    // ---- Progress, written the way a finished game writes it.
    final packs = await c.read(packsProvider.future);
    final puzzles = await c.read(allPuzzlesProvider.future);
    final profile = c.read(profileProvider.notifier);
    final library = packs.where((p) => !p.isDaily && !p.hasWindow && profile.isUnlocked(p)).toList();
    List<Puzzle> of(Pack p) => puzzles.where((z) => z.packId == p.id).toList();
    final usable = library.where((p) => of(p).length >= 4).toList();
    expect(usable.length, greaterThanOrEqualTo(4), reason: 'four unlocked library packs');
    final bySize = [...usable]..sort((a, b) => of(a).length.compareTo(of(b).length));
    final perfect = bySize[0], short = bySize[1];
    final started = usable.where((p) => p != perfect && p != short && of(p).length >= 6).take(2).toList();
    expect(started, hasLength(2), reason: 'two larger unlocked library packs');
    debugPrint('hsg packs: perfect ${perfect.id} ${perfect.name}, short ${short.id} ${short.name}, started ${started.map((p) => p.id).join(', ')}');
    final progress = c.read(progressProvider.notifier);
    var minute = 0;
    Future<void> solve(Puzzle z, int stars) async => progress.complete(
          z.id,
          gridSize: 16,
          mode: GameMode.cards.code,
          moves: 30,
          seconds: 90,
          hints: 0,
          stars: stars,
          session: 'qa-${z.id}',
          resumed: false,
          at: DateTime.now().subtract(Duration(minutes: 300 - minute++)),
        );
    for (final z in of(perfect)) {
      await solve(z, 3);
    }
    final shortPictures = of(short);
    for (var i = 0; i < shortPictures.length; i++) {
      await solve(shortPictures[i], i < 3 ? 2 : 3);
    }
    for (final (i, p) in started.indexed) {
      for (final z in of(p).take(i == 0 ? 3 : 1)) {
        await solve(z, 3);
      }
    }
    await go(tester, '/home', ms: 3000);

    // ---- Packs in progress: after the Lucky Wheel, piggy bank and level, just above the live events.
    double top(Finder f) => tester.getTopLeft(f).dy;
    await scrollTo(tester, find.text('Packs in progress'), alignment: 0.5);
    await shot(tester, '06_packs_in_progress');
    final liveEvents = find.text('Live events');
    if (liveEvents.evaluate().isNotEmpty) {
      expect(top(find.text('Packs in progress')), lessThan(top(liveEvents)));
    }
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 300));
    await shot(tester, '07_above_packs_in_progress');

    // ---- The done badge: Missing stars covers (finished, short of stars), Finished packs rows.
    await scrollTo(tester, find.text('Missing stars'));
    await shot(tester, '08_missing_stars_covers');
    await scrollTo(tester, find.text('Finished packs'));
    await shot(tester, '09_finished_rows_light');
    settings.setThemeMode(ThemeMode.dark);
    await shot(tester, '10_finished_rows_dark', ms: 1500);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 8000));
    await settle(tester, 1000);
    await scrollTo(tester, find.text('Missing stars'));
    await shot(tester, '11_missing_stars_covers_dark');

    // See all: the Library on Finished, the pack cards with the badge.
    await scrollTo(tester, find.text('Finished packs'));
    await tester.tap(find.text('See all').last, warnIfMissed: false);
    await settle(tester, 3500);
    await shot(tester, '12_library_finished_dark');
    settings.setThemeMode(ThemeMode.light);
    await shot(tester, '13_library_finished_light', ms: 1500);

    // The pack page of the pack with every star.
    await go(tester, '/library/pack/${perfect.id}', ms: 3500);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await shot(tester, '14_pack_page_perfect', ms: 1200);
  }, timeout: const Timeout(Duration(minutes: 15)));
}
