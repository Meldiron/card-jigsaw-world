// Captures the raw App Store marketing screens (live Appwrite backend).
// Meant for the iPhone 17 Pro Max simulator (6.9", 1320x2868):
//   xcrun simctl uninstall D03644FB-6169-4E87-8E0F-CCFC884FBE78 com.matejbaco.cardjigsawworld
//   tools/dev/qa-run.sh drive --driver=test_driver/store_screenshots.dart \
//     --target=integration_test/store_screenshots_test.dart \
//     -d D03644FB-6169-4E87-8E0F-CCFC884FBE78
// Output lands in store/raw/. Then run tools/store/compose_screenshots.py.
//
// The app runs in its dark theme (the slides are dark); pass
// --dart-define=CJW_STORE_THEME=light for light captures, which are written
// with a `_light` suffix. Navigation goes through the router so a changed
// pack order or a moved button does not derail the run; every board is set
// up by tapping real moves on the live board.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:carden/app.dart';
import 'package:carden/core/appwrite.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/data/repositories.dart';
import 'package:carden/features/gallery/library_screen.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/game/board.dart';
import 'package:carden/router.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/unlocks.dart';
import 'package:carden/state/social.dart';
import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pictures used on the slides (people-free, vivid, free packs).
const heroPuzzle = 'p-b4a82e61538b'; // Butterflies: Monarch butterfly
const modesPuzzle = 'p-00df45e91273'; // Tropical Beaches: Bora Bora lagoon
const hexPuzzle = 'p-06ae2d7ad942'; // Sunsets: Key West sunset
const galleryPack = 'pack-butterflies';

/// The glass set (tools/store/compose_glass.py): boards mid-build (some cards locked, some loose,
/// some joined) for slide 1, the Painting slide (an Impressionist painting, mostly still grey) and
/// the dark finale, and a giant board of the real Giant pack (the guest gets the pack's tickets and
/// unlocks it) shown whole, in tiny cards, with only a small part solved. No AI pictures anywhere.
const brightHeroPuzzle = 'p-e667552c4e66'; // Butterflies: Painted lady butterfly
const paintingPuzzle = 'p-2f9f0b647f9f'; // Impressionists: Monet chrysanthemums
const giantPack = 'pack-colourful-houses';
const giantPuzzle = 'p-86961eb4f439'; // Colourful Houses: Hölderlin Tower, Tübingen

/// Past days of the current daily month solved before the calendar capture
/// (stars on their tiles). Ids are `daily-YYYY-MM-DD`.
const dailyDaysToSolve = [1, 3, 6, 8, 10];

/// Photos uploaded through My Puzzles, oldest first (the grid shows newest
/// first). Catalogue pictures with a CC0 or public-domain licence and no
/// people: Macarons, Chania lighthouse, Tuxedo kitten II, Corgi puppy. The
/// last one is played as a puzzle.
const myPhotos = ['pack-pastries-09', 'p-3b694ec057be', 'p-de0b799403de', 'p-62ce633fc70a'];

const theme = String.fromEnvironment('CJW_STORE_THEME', defaultValue: 'dark');

/// `--dart-define=CJW_STORE_SKIP_UPLOAD=true` skips the My Puzzles uploads
/// (and their two captures) on a rerun, so live Storage gets no duplicates.
const skipUpload = bool.fromEnvironment('CJW_STORE_SKIP_UPLOAD');
const suffix = theme == 'light' ? '_light' : '';

/// `--dart-define=CJW_STORE_ONLY=25_hero,27_giant` re-takes only those glass-set captures (25-29)
/// after onboarding and leaves every other file as it is: a quick rerun for one slide.
const only = String.fromEnvironment('CJW_STORE_ONLY');
bool want(String name) => only.isEmpty || only.split(',').contains(name);

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

  /// Captures the screen. On a game screen the board's rectangle (physical
  /// pixels: left, top, width, height) is recorded too; the driver writes
  /// all of them to store/raw/boards.json so the composer can crop boards.
  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, 600);
    final boards = find.byType(BoardWidget);
    if (boards.evaluate().isNotEmpty) {
      final r = tester.getRect(boards.first);
      final dpr = tester.view.devicePixelRatio;
      binding.reportData ??= <String, dynamic>{};
      final map = (binding.reportData!['boards'] ??= <String, dynamic>{}) as Map<String, dynamic>;
      map['$name$suffix'] = [r.left * dpr, r.top * dpr, r.width * dpr, r.height * dpr];
    }
    await binding.takeScreenshot('$name$suffix');
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  Future<bool> tapIfShown(WidgetTester tester, String text, {int ms = 1200}) async {
    if (find.text(text).evaluate().isEmpty) return false;
    await tapText(tester, text, ms: ms);
    return true;
  }

  GoRouter router(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(routerProvider);

  Future<void> go(WidgetTester tester, String path, {int ms = 3000}) async {
    router(tester).go(path);
    await settle(tester, ms);
  }

  Future<void> push(WidgetTester tester, String path, {int ms = 3000}) async {
    router(tester).push(path);
    await settle(tester, ms);
  }

  Finder boardFinder() => find.byType(BoardWidget);
  Board board(WidgetTester tester) => tester.widget<BoardWidget>(boardFinder().first).state.board;
  Offset center(WidgetTester tester, int slot) {
    final rect = tester.getRect(boardFinder().first);
    return rect.topLeft + board(tester).tiling.cellCenter(slot, rect.size);
  }

  bool single(Board b, int slot) => !b.isLocked(slot) && b.groupOf(slot).length == 1;

  Future<void> move(WidgetTester tester, int from, int to) async {
    await tester.tapAt(center(tester, from));
    await settle(tester, 250);
    await tester.tapAt(center(tester, to));
    await settle(tester, 650);
  }

  /// Locks [count] pieces, nearest to the middle of the picture first, so the
  /// subject shows while the edges stay shuffled. Only single pieces move.
  Future<void> lockMiddle(WidgetTester tester, int count) async {
    final b0 = board(tester);
    final rect = tester.getRect(boardFinder().first);
    final mid = rect.size.center(Offset.zero);
    final order = List.generate(b0.cells, (i) => i)
      ..sort((a, c) => (b0.tiling.cellCenter(a, rect.size) - mid).distanceSquared.compareTo((b0.tiling.cellCenter(c, rect.size) - mid).distanceSquared));
    var locked = 0;
    for (final home in order) {
      if (locked >= count) break;
      final b = board(tester);
      if (b.isLocked(home)) {
        locked++;
        continue;
      }
      final from = b.slotOfCard(home);
      if (!single(b, from) || !single(b, home)) continue;
      await move(tester, from, home);
      if (board(tester).isLocked(home)) locked++;
    }
  }

  /// Sends every card home except those whose home is in [open]; the open
  /// cards stay shuffled among the open slots.
  Future<void> lockAllBut(WidgetTester tester, Set<int> open) async {
    for (var pass = 0; pass < 3; pass++) {
      for (var home = 0; home < board(tester).cells; home++) {
        if (open.contains(home)) continue;
        final b = board(tester);
        if (b.isLocked(home)) continue;
        final from = b.slotOfCard(home);
        if (!single(b, from) || !single(b, home)) continue;
        await move(tester, from, home);
      }
    }
  }

  /// Every card home except the two top corners, which end up swapped (the
  /// hero state: one obvious swap left). A move that would put a corner
  /// card home as a side effect sends it to the other corner instead, so
  /// the board never completes here. Best effort: a group that forms by
  /// chance is left as it is (it shows the cobalt group outline).
  Future<void> swapCornersOnly(WidgetTester tester) async {
    final a = 0, c = board(tester).cols - 1;
    for (var pass = 0; pass < 4; pass++) {
      for (var home = 0; home < board(tester).cells; home++) {
        if (home == a || home == c) continue;
        var b = board(tester);
        if (b.isLocked(home)) continue;
        final from = b.slotOfCard(home);
        final there = b.slots[home];
        if ((from == a && there == a) || (from == c && there == c)) {
          // The corner card sits at [home] and [home]'s card at its corner:
          // park the corner card in the other corner first.
          final other = from == a ? c : a;
          if (!single(b, home) || !single(b, other)) continue;
          await move(tester, home, other);
          b = board(tester);
          if (b.isLocked(home)) continue;
        }
        final f = b.slotOfCard(home);
        if (!single(b, f) || !single(b, home)) continue;
        await move(tester, f, home);
      }
    }
  }

  /// Places every piece except a scattered set and one neighbouring pair, so
  /// the board shows its piece shapes all over a recognisable picture. With
  /// [interiorOnly] (triangles, hexagons) the open pieces are whole interior
  /// ones; edge pieces there are halves. Returns the pair (for [buildGroup]).
  Future<List<int>> lockAllButScattered(WidgetTester tester, {bool interiorOnly = true}) async {
    final b0 = board(tester);
    final t = b0.tiling;
    final maxN = List.generate(b0.cells, (i) => t.neighbours(i).length).reduce((a, c) => a > c ? a : c);
    final interior = List.generate(b0.cells, (i) => i).where((i) => !interiorOnly || t.neighbours(i).length == maxN).toList();
    final open = interior.where((i) => (t.row(i) + 2 * t.col(i)) % 3 == 0).toSet();
    // One neighbouring pair of interior pieces stays open for a fused group.
    var pair = <int>[];
    for (final h in interior.where((i) => !open.contains(i))) {
      final n = t.neighbours(h).where((x) => interior.contains(x) && !open.contains(x) && x != h).toList();
      if (n.isNotEmpty) {
        pair = [h, n.first];
        break;
      }
    }
    open.addAll(pair);
    await lockAllBut(tester, open);
    return pair;
  }

  /// Assembles a fused (unlocked) group of the cards that belong at [homes]
  /// somewhere else on the board. Best effort; returns whether it formed.
  Future<bool> buildGroup(WidgetTester tester, List<int> homes) async {
    final tiling = board(tester).tiling;
    int? shifted(int base, int h) {
      if (tiling is TriangleTiling) {
        final c = tiling.col(base) + tiling.col(h) - tiling.col(homes.first), r = tiling.row(base) + tiling.row(h) - tiling.row(homes.first);
        return tiling.inBounds(c, r) ? r * tiling.cols + c : null;
      }
      final d = tiling.delta(homes.first, h);
      return d == null ? null : tiling.apply(base, d.$1, d.$2);
    }

    for (var s = 0; s < board(tester).cells; s++) {
      final b = board(tester);
      if (!single(b, s)) continue;
      final c = b.slots[s];
      if (tiling.classOf(c) != tiling.classOf(homes.first) || tiling.delta(c, s) == null) continue;
      final cards = <int>[], targets = <int>[];
      var ok = true;
      for (final h in homes) {
        final ck = shifted(c, h), tk = shifted(s, h);
        if (ck == null || tk == null || ck == tk) {
          ok = false;
          break;
        }
        cards.add(ck);
        targets.add(tk);
      }
      if (!ok) continue;
      if (cards.any((k) => !single(b, b.slotOfCard(k))) || targets.any((t) => !single(b, t))) continue;
      for (var k = 1; k < homes.length; k++) {
        final from = board(tester).slotOfCard(cards[k]);
        if (from == targets[k]) continue;
        await move(tester, from, targets[k]);
      }
      if (board(tester).groupOf(targets.first).length >= homes.length) return true;
    }
    return false;
  }

  /// Any pair of picture neighbours that are both still unplaced singles.
  Future<bool> buildAnyGroup(WidgetTester tester) async {
    final b = board(tester);
    for (var h = 0; h < b.cells; h++) {
      if (b.isLocked(h)) continue;
      for (final n in b.tiling.neighbours(h)) {
        if (n <= h || b.isLocked(n)) continue;
        if (await buildGroup(tester, [h, n])) return true;
      }
    }
    return false;
  }

  /// Scrolls the Library to the Masterpieces row: from there on the grid shows photographs and
  /// paintings only (the two AI packs sit in the first rows).
  Future<void> libraryPastAi(WidgetTester tester) async {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1660));
    await settle(tester, 3000);
  }

  /// (Board sizes past Relaxed open with levels: a quick CJW_STORE_ONLY run plays a level-1 guest.)
  /// A board mid-build: [frac] of the cards locked from the middle out, then [groups] fused groups
  /// among the loose ones, so locked, loose and joined cards all show.
  Future<void> midBuild(WidgetTester tester, double frac, int groups) async {
    await lockMiddle(tester, (board(tester).cells * frac).round());
    for (var g = 0; g < groups; g++) {
      if (!await buildAnyGroup(tester)) break;
    }
  }

  /// Selects one unplaced single piece away from the edges, so the lifted
  /// highlight shows.
  Future<void> selectOne(WidgetTester tester) async {
    final b = board(tester);
    final rect = tester.getRect(boardFinder().first);
    final mid = rect.size.center(Offset.zero);
    final singles = List.generate(b.cells, (i) => i).where((s) => single(b, s)).toList()
      ..sort((a, c) => (b.tiling.cellCenter(a, rect.size) - mid).distanceSquared.compareTo((b.tiling.cellCenter(c, rect.size) - mid).distanceSquared));
    if (singles.isEmpty) return;
    await tester.tapAt(center(tester, singles[singles.length ~/ 3]));
    await settle(tester, 500);
  }

  /// Sends every misplaced piece home.
  Future<void> solve(WidgetTester tester) async {
    for (var guard = 0; guard < 140; guard++) {
      if (boardFinder().evaluate().isEmpty) break;
      final b = board(tester);
      if (b.isSolved) break;
      final open = List.generate(b.cells, (i) => i).where((i) => !b.isLocked(i)).toList();
      final slot = open.firstWhere((s) => single(b, s), orElse: () => open.first);
      await move(tester, slot, b.homeOf(slot));
    }
  }

  /// Opens a picture's difficulty screen, clears an earlier board of it,
  /// picks [mode] and [tier] and starts the game.
  Future<void> startGame(WidgetTester tester, String puzzleId, String mode, String tier, {String? difficultyShot, bool painting = false}) async {
    await push(tester, '/play/$puzzleId${painting ? '?painting=1' : ''}', ms: 3500);
    if (await tapIfShown(tester, 'Discard progress', ms: 900)) {
      await tapText(tester, 'Discard', ms: 1500);
    }
    await tapText(tester, mode, ms: 900);
    await tester.dragUntilVisible(find.text(tier), find.byType(Scrollable).first, const Offset(0, -200));
    await settle(tester, 500);
    await tapText(tester, tier, ms: 900);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
    await settle(tester, 700);
    if (difficultyShot != null) await shot(tester, difficultyShot);
    await tester.tap(find.textContaining('Play'), warnIfMissed: false);
    await settle(tester, 6000);
    // Giant pictures are 4096 px: the full-size download and decode take a moment longer.
    for (var i = 0; i < 30 && boardFinder().evaluate().isEmpty; i++) {
      await settle(tester, 500);
    }
    await tapIfShown(tester, 'Got it');
    expect(boardFinder(), findsOneWidget, reason: 'board for $puzzleId $mode $tier');
  }

  Future<void> saveAndQuit(WidgetTester tester) async {
    // The pause sheet slides in; a tap that lands before it settles hits the
    // barrier and only closes the sheet, so retry while the HUD is still up.
    for (var attempt = 0; attempt < 3 && find.byIcon(CupertinoIcons.pause_fill).evaluate().isNotEmpty; attempt++) {
      await tester.tap(find.byIcon(CupertinoIcons.pause_fill), warnIfMissed: false);
      await settle(tester, 1200);
      await tapIfShown(tester, 'Save & quit', ms: 2500);
    }
  }

  /// A catalogue picture as the photo picker would hand it over (JPEG, at
  /// most 1600 px), fetched from our own Storage.
  Future<Uint8List> pictureBytes(String puzzleId) async {
    final client = HttpClient();
    try {
      final rowReq = await client.getUrl(Uri.parse('${AppwriteConfig.endpoint}/tablesdb/${AppwriteConfig.databaseId}/tables/${AppwriteConfig.puzzles}/rows/$puzzleId'));
      rowReq.headers.set('X-Appwrite-Project', AppwriteConfig.projectId);
      final row = jsonDecode(await (await rowReq.close()).transform(utf8.decoder).join()) as Map<String, dynamic>;
      final view = row['imageUrl'] as String;
      final req = await client.getUrl(Uri.parse('${view.replaceFirst('/view?', '/preview?')}&width=1600&quality=88'));
      return await consolidateHttpClientResponseBytes(await req.close());
    } finally {
      client.close();
    }
  }

  testWidgets('capture store screens', (tester) async {
    SharedPreferences.setMockInitialValues({
      'themeMode': theme,
      // No break offers between the captured completions.
      'lifetimeCompletions': -50,
    });
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        // Shapes and options open as levels rise (lib/state/unlocks.dart); these suites play every one, so all are open and no intro sheet interrupts them.
        openFeaturesProvider.overrideWithValue(OpenFeatures.all),
        pendingUnlockIntroProvider.overrideWithValue(null),
      ],
      child: const CardenApp(),
    ));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 6000); // let catalog + images load

    // Claim the daily gift so the streak card shows a 1-day streak.
    if (await tapIfShown(tester, 'Claim')) {
      if (find.textContaining('Claim day').evaluate().isNotEmpty) {
        await tester.tap(find.textContaining('Claim day'), warnIfMissed: false);
        await settle(tester, 1500);
      }
      await tester.tapAt(const Offset(220, 80));
      await settle(tester, 1200);
    }
    if (only.isEmpty) await shot(tester, '01_home');

    // Glass set, slide 1: a bright picture mid-build: about half locked, two joined groups, one
    // loose card selected.
    if (want('25_hero')) {
      try {
        await startGame(tester, brightHeroPuzzle, 'Cards', 'Relaxed');
        await midBuild(tester, 0.5, 2);
        await selectOne(tester);
        await shot(tester, '25_hero');
        await saveAndQuit(tester);
      } catch (e) {
        await binding.takeScreenshot('zz_diag_hero');
        await go(tester, '/home', ms: 2000);
      }
    }

    // Glass set, slide 5: Painting on Monet's chrysanthemums, mostly still grey: a few cards locked
    // (in colour) in the middle, two joined groups among the grey ones.
    if (want('26_painting')) {
      try {
        await startGame(tester, paintingPuzzle, 'Cards', 'Relaxed', painting: true);
        await midBuild(tester, 0.3, 2);
        await shot(tester, '26_painting');
        await saveAndQuit(tester);
      } catch (e) {
        await binding.takeScreenshot('zz_diag_painting');
        await go(tester, '/home', ms: 2000);
      }
    }

    // Glass set, slide 6: a giant board of the real Giant pack, the whole picture in tiny cards, a
    // small part of the middle assembled and two joined groups.
    if (want('27_giant')) {
      try {
        final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
        final pack = (await container.read(packsProvider.future)).firstWhere((p) => p.id == giantPack);
        final profile = container.read(profileProvider.notifier);
        await profile.addTickets(pack.priceTickets, reason: 'qa:store-giant');
        await settle(tester, 800);
        await profile.unlockPack(pack);
        await startGame(tester, giantPuzzle, 'Cards', 'Giant');
        await midBuild(tester, 0.12, 2);
        await shot(tester, '27_giant');
        await saveAndQuit(tester);
      } catch (e) {
        await binding.takeScreenshot('zz_diag_giant');
        await go(tester, '/home', ms: 2000);
      }
    }
    // Glass set, last slide (dark run only): the Monarch mid-build in the dark theme.
    if (theme == 'dark' && want('29_dark_board')) {
      try {
        await startGame(tester, heroPuzzle, 'Cards', 'Relaxed');
        await midBuild(tester, 0.45, 2);
        await selectOne(tester);
        await shot(tester, '29_dark_board');
        await saveAndQuit(tester);
      } catch (e) {
        await binding.takeScreenshot('zz_diag_dark_board');
        await go(tester, '/home', ms: 2000);
      }
    }
    await go(tester, '/home', ms: 2000);
    if (only.isNotEmpty) {
      if (want('28_library_more')) {
        await go(tester, '/library', ms: 3500);
        await libraryPastAi(tester);
        await shot(tester, '28_library_more');
      }
      return;
    }


    // Hero: the Monarch on a 12-card board, mostly placed, one fused group,
    // one card lifted. Then finish it (pack progress, quest progress).
    await startGame(tester, heroPuzzle, 'Cards', 'Easy', difficultyShot: '02_difficulty');
    // Everything placed but the two top corners (swapped), the left one lifted.
    await swapCornersOnly(tester);
    await tester.tapAt(center(tester, 0));
    await settle(tester, 500);
    await shot(tester, '03_game_cards');
    await tester.tapAt(center(tester, 0)); // drop the selection
    await settle(tester, 300);
    await solve(tester);
    await settle(tester, 3000);
    await go(tester, '/home', ms: 2500);

    // A finished picture with three stars: Key West sunset in hexagons,
    // solved in the fewest moves.
    await startGame(tester, hexPuzzle, 'Hexagons', 'Cozy');
    await solve(tester);
    await settle(tester, 3500);
    await shot(tester, '04_complete');
    if (await tapIfShown(tester, 'View picture', ms: 1200)) {
      await shot(tester, '05_complete_view');
      await tapIfShown(tester, 'Back to results', ms: 900);
    }
    await go(tester, '/home', ms: 2500);

    // One picture, four ways to cut it (Bora Bora lagoon), each mid-game.
    for (final (mode, tier, name) in [
      ('Cards', 'Easy', '06_mode_cards'),
      ('Squares', 'Easy', '07_mode_squares'),
      ('Triangles', 'Cozy', '08_mode_triangles'),
      ('Hexagons', 'Easy', '09_mode_hexagons'),
    ]) {
      try {
        await startGame(tester, modesPuzzle, mode, tier);
        final pair = await lockAllButScattered(tester, interiorOnly: mode == 'Triangles' || mode == 'Hexagons');
        if (pair.isEmpty || !await buildGroup(tester, pair)) await buildAnyGroup(tester);
        await shot(tester, name);
        if (mode == 'Hexagons') {
          await selectOne(tester);
          await shot(tester, '10_game_hexagons');
        }
        await saveAndQuit(tester);
      } catch (e) {
        await binding.takeScreenshot('zz_diag_$name');
        await go(tester, '/home', ms: 2000);
      }
    }
    await go(tester, '/home', ms: 2000);

    // Store, then scrolled to the VIP card (also the subscription review shot).
    await push(tester, '/store', ms: 2500);
    await shot(tester, '11_store');
    await tester.dragUntilVisible(find.text('Carden VIP'), find.byType(Scrollable).first, const Offset(0, -300));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await settle(tester, 1200);
    // Start the view at the Hints heading, not halfway through its subtitle.
    final hints = find.text('Hints');
    if (hints.evaluate().isNotEmpty) {
      await tester.drag(find.byType(Scrollable).first, Offset(0, 152 - tester.getTopLeft(hints.first).dy));
      await settle(tester, 1200);
    }
    await shot(tester, '12_store_vip');
    await tester.tap(find.byIcon(CupertinoIcons.xmark).first, warnIfMissed: false);
    await settle(tester, 1200);

    // Quests (before the daily solves, so a few quests are still in
    // progress), then the live events further down.
    await go(tester, '/events', ms: 3500);
    await shot(tester, '13_quests');
    try {
      await tester.dragUntilVisible(find.text('Live events'), find.byType(CustomScrollView).last, const Offset(0, -300));
      await tester.drag(find.byType(CustomScrollView).last, const Offset(0, -500));
      await settle(tester, 2500);
      await shot(tester, '14_quests_live');
    } catch (_) {
      await binding.takeScreenshot('zz_diag_live_events');
    }

    // A few past days of this month's daily pack, so the calendar shows stars.
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    for (final day in dailyDaysToSolve.where((d) => d < now.day)) {
      try {
        await go(tester, '/home', ms: 1500);
        await startGame(tester, 'daily-${now.year}-${two(now.month)}-${two(day)}', 'Cards', 'Cozy');
        await solve(tester);
        await settle(tester, 2500);
      } catch (e) {
        await binding.takeScreenshot('zz_diag_daily_$day');
      }
    }

    // Library, the daily calendar (top, then scrolled to the day grid), a pack.
    await go(tester, '/library', ms: 3500);
    await shot(tester, '15_library');
    // Glass set, slide 2: the Library further down, past the AI packs near the top (no AI art in the
    // store screenshots).
    await libraryPastAi(tester);
    await shot(tester, '28_library_more');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1660));
    await settle(tester, 1200);
    // The Daily chip sits past the screen's edge among the other chips; pick it the way a link does
    // (the row then scrolls it into view).
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(libraryFilterProvider.notifier).select(LibraryFilter.daily);
    await settle(tester, 2500);
    {
      await shot(tester, '16_library_daily');
      final month = find.textContaining(' ${now.year}');
      if (month.evaluate().isNotEmpty) {
        await tester.tap(month.first, warnIfMissed: false);
        await settle(tester, 4500);
        await shot(tester, '17_daily_month');
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -330));
        await settle(tester, 2500);
        await shot(tester, '18_daily_month_grid');
      }
    }
    await go(tester, '/library/pack/$galleryPack', ms: 4500);
    await shot(tester, '19_pack');

    // My Puzzles: four photos uploaded to live Storage with the app's own
    // upload (the native photo picker cannot be driven from a test), titled
    // the way the screen titles them; then the newest one played as a puzzle.
    {
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      final userId = skipUpload ? null : container.read(currentUserIdProvider);
      String? lastId;
      if (userId != null) {
        for (final id in myPhotos) {
          final bytes = await pictureBytes(id);
          final made = await container.read(uploadRepositoryProvider).upload(userId, bytes: bytes, filename: 'photo.jpg', title: 'My photo ${now.day}/${now.month}');
          lastId = made.id;
        }
        container.invalidate(myPuzzlesProvider);
      }
      if (!skipUpload) {
        await go(tester, '/profile/my-puzzles', ms: 6000);
        await shot(tester, '20_my_puzzles');
      }
      if (lastId != null) {
        try {
          await startGame(tester, lastId, 'Squares', 'Easy');
          await lockMiddle(tester, (board(tester).cells * 0.6).round());
          await buildAnyGroup(tester);
          await selectOne(tester);
          await shot(tester, '21_my_puzzle_game');
          await saveAndQuit(tester);
        } catch (e) {
          await binding.takeScreenshot('zz_diag_my_puzzle');
        }
      }
    }

    // League.
    await go(tester, '/social', ms: 4000);
    await shot(tester, '22_social_league');

    // Lucky Wheel sheet and the profile.
    await go(tester, '/home', ms: 2000);
    await push(tester, '/wheel', ms: 2500);
    await shot(tester, '23_wheel');
    if (find.byIcon(CupertinoIcons.xmark).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(CupertinoIcons.xmark).first, warnIfMissed: false);
      await settle(tester, 1200);
    }
    await go(tester, '/profile', ms: 3000);
    await shot(tester, '24_profile');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
