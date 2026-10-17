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
import 'dart:async';
import 'dart:math' show max, min;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:carden/app.dart';
import 'package:carden/core/appwrite.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/coop_repository.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/store/store_screen.dart';
import 'package:carden/data/repositories.dart';
import 'package:carden/data/sync/ops.dart';
import 'package:carden/features/gallery/library_screen.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/features/game/game_screen.dart';
import 'package:carden/game/board.dart';
import 'package:carden/models/models.dart';
import 'package:carden/router.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/paged.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/unlocks.dart';
import 'package:carden/state/social.dart';
import 'package:carden/state/sync.dart';
import 'package:carden/state/coop/board_change.dart';
import 'package:carden/state/coop/coop_backend.dart';
import 'package:carden/state/coop/coop_controller.dart';
import 'package:carden/state/coop/coop_live.dart';
import 'package:carden/state/coop/coop_models.dart';
import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
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
const brightHeroPuzzle = 'pack-tulip-fields-08'; // Tulip Fields 8 (CC0): every card a different colour
const paintingPuzzle = 'p-2f9f0b647f9f'; // Impressionists: Monet chrysanthemums
const giantPack = 'pack-colourful-houses';
const giantPuzzle = 'p-86961eb4f439'; // Colourful Houses: Hölderlin Tower, Tübingen

/// The Library as the screenshots show it: these packs first (the strongest covers, no AI), in this
/// order; the rest follow in the catalogue's order. Only the order changes (`packsProvider` override).
const libraryFirst = [
  'pack-northern-lights', 'pack-tulip-fields', 'pack-parrots', 'pack-hot-air-balloons', 'pack-cherry-blossom', 'pack-kyoto',
  'pack-santorini', 'pack-japanese-prints', 'pack-lavender', 'pack-nebulae', 'pack-venice', 'pack-sunflowers',
];

/// Past days of the current daily month solved before the calendar capture
/// (stars on their tiles). Ids are `daily-YYYY-MM-DD`.
const dailyDaysToSolve = [1, 3, 6, 8, 10];

/// Photos uploaded through My Puzzles, oldest first (the grid shows newest
/// first). Catalogue pictures with a CC0 or public-domain licence and no
/// people: Macarons, Lagoon islets, Chania lighthouse, Tuxedo kitten II, Corgi puppy (five, so the
/// grid with its Add photo tile has no gap). The last one is played as a puzzle.
const myPhotos = ['pack-pastries-09', 'pack-islands-09', 'p-3b694ec057be', 'p-de0b799403de', 'p-62ce633fc70a'];

const theme = String.fromEnvironment('CJW_STORE_THEME', defaultValue: 'dark');

/// `--dart-define=CJW_STORE_SKIP_UPLOAD=true` skips the My Puzzles uploads
/// (and their two captures) on a rerun, so live Storage gets no duplicates.
const skipUpload = bool.fromEnvironment('CJW_STORE_SKIP_UPLOAD');
const suffix = theme == 'light' ? '_light' : '';

/// `--dart-define=CJW_STORE_ONLY=25_hero,27_giant` re-takes only those glass-set captures (15_library, 22_social_league, 25-35)
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

/// The league as the screenshots show it: the real players plus these made-up ones (name, XP,
/// avatar), so the board is full and varied; players on the default avatar get another one.
const leagueExtras = [
  ('Quiet Heron', 8640, 'rocket'), ('Brave Otter', 7320, 'heart'), ('Gentle Lynx', 6180, 'sun'),
  ('Sunny Koala', 5240, 'palette'), ('Calm Finch', 3760, 'moon'), ('Bright Ibis', 3180, 'music'),
  ('Lucky Puffin', 1940, 'camera'), ('Swift Marten', 1380, 'anchor'), ('Clever Wren', 860, 'snow'), ('Happy Gecko', 410, 'pizza'),
];
const leagueAvatars = ['wave', 'cake', 'globe', 'bike', 'coffee', 'umbrella', 'key', 'mountain'];

/// Play together for the store (`32_coop_board`): a game played on this device with two made-up
/// players, scripted here instead of the live backend, so the slide shows a calm moment of a shared
/// board (the players chip, a card one friend holds and a card the other just moved).
const coopPuzzle = 'p-00df45e91273'; // Tropical Beaches: Bora Bora lagoon
const coopFriends = {'stage-ava': ('Ava', 'flower'), 'stage-leo': ('Leo', 'sun')};

/// The store player's name where other players see it (the co-op player list), instead of the random
/// guest name; the name the design QA presets use. Its initial differs from the friends' (M, A, L).
const storePlayerName = 'Mia';

class _StageCoop implements CoopBackend {
  final _events = StreamController<CoopEvent>.broadcast();
  CoopGame? game;
  String me = '';
  var _seq = 100;

  @override
  Future<CoopGame?> call(String action, Map<String, dynamic> body) async {
    if (action != 'create') return null;
    final layout = (body['layout'] as List).cast<int>();
    game = CoopGame(id: 'stage', code: 'GAMEABCD', hostId: me, players: [me, '', '', '', ''], removed: const [], ended: false, board: 1, puzzleId: '${body['puzzleId']}', grid: '${body['grid']}', painting: false, layout: layout);
    return game;
  }

  Map<String, dynamic> _row() => {
        r'$id': 'stage',
        'code': game!.code,
        'hostId': me,
        'players': game!.players,
        'removed': const <String>[],
        'status': 'playing',
        'board': 1,
        'puzzleId': game!.puzzleId,
        'grid': game!.grid,
        'layout': game!.layout.join(','),
      };

  /// The two friends take their seats.
  void seat() {
    game = game!.copyWith(players: [me, ...coopFriends.keys, '', '']);
    _events.add(CoopGameEvent(_row()));
  }

  /// A friend's move: [before] to [after].
  void move(String userId, List<int> before, List<int> after) => _events.add(CoopMoveEvent({
        r'$id': 'stage-${++_seq}',
        r'$sequence': '$_seq',
        r'$permissions': CoopOp.permissionsFor('stage', userId),
        ...CoopOp(id: 'x', gameId: 'stage', board: 1, userId: userId, kind: CoopOpKind.move, change: BoardChange.between(before, after)).toData(),
      }));

  /// A friend picks a card up.
  void hold(String userId, int card) => _events.add(CoopPresenceEvent({'userId': userId, 'status': 'online', 'metadata': {'g': 'stage', 'b': 1, 'h': card}}));

  @override
  Future<CoopGame?> readGame(String gameId) async => game;
  @override
  Future<Map<String, dynamic>> createMove(CoopOp op) async => {r'$id': op.id, r'$sequence': '${++_seq}', r'$permissions': CoopOp.permissionsFor(op.gameId, op.userId), ...op.toData()};
  @override
  Future<List<Map<String, dynamic>>> movesAfter(String gameId, int board, int afterSeq) async => const [];
  @override
  Stream<CoopEvent> listen(String gameId, {String? me}) => _events.stream;
  @override
  Future<void> updateLive(String gameId, CoopLive state) async {}
  @override
  void setPresence(String presenceId, CoopPresence presence) {}
  @override
  Future<List<Map<String, dynamic>>> presences(List<String> userIds) async => [
        for (final id in coopFriends.keys)
          if (userIds.contains(id)) {'userId': id, 'status': 'online', 'metadata': {'g': 'stage', 'b': 1, 'h': -1}},
      ];
  @override
  Future<void> close() async {}
}

/// The share sheet is the system's: the store capture keeps what would be shared instead.
class _NoShare extends SharePlatform {
  @override
  Future<ShareResult> share(ShareParams params) async => const ShareResult('stage', ShareResultStatus.success);
}

class _StoreLeaderboard extends LeaderboardNotifier {
  @override
  Future<PageResult<Profile>> fetchPage(String? after) async {
    final page = await super.fetchPage(after);
    if (after != null || page.items.isEmpty) return page;
    final me = ref.read(currentUserIdProvider);
    var n = 0;
    final real = [
      for (final p in page.items) p.userId == me || p.avatar != 'fox' ? p : p.copyWith(avatar: leagueAvatars[n++ % leagueAvatars.length]),
    ];
    final made = [
      for (final (i, (name, xp, avatar)) in leagueExtras.indexed)
        page.items.first.copyWith(id: 'store-$i', userId: 'store-$i', displayName: name, xp: xp, avatar: avatar, puzzlesCompleted: xp ~/ 70, totalStars: xp ~/ 26, isTest: false),
    ];
    return (items: [...real, ...made]..sort((a, b) => b.xp.compareTo(a.xp)), lastId: null);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  // Boards here are played the moment they show: no picture before the deal (GameScreen.dealPreview).
  GameScreen.dealPreview = false;

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

  /// Records the rectangle of one card of the board on screen (physical px, grown by [pad] logical px)
  /// as [name] in store/raw/boards.json, so the composer can lift exactly that card.
  void recordCell(WidgetTester tester, String name, int slot, {double pad = 0}) {
    final rect = tester.getRect(find.byType(BoardWidget).first);
    final poly = tester.widget<BoardWidget>(find.byType(BoardWidget).first).state.board.tiling.polygon(slot, rect.size);
    final xs = poly.map((p) => p.dx), ys = poly.map((p) => p.dy);
    final r = Rect.fromLTRB(xs.reduce(min), ys.reduce(min), xs.reduce(max), ys.reduce(max)).shift(rect.topLeft).inflate(pad);
    final dpr = tester.view.devicePixelRatio;
    binding.reportData ??= <String, dynamic>{};
    final map = (binding.reportData!['boards'] ??= <String, dynamic>{}) as Map<String, dynamic>;
    map['$name$suffix'] = [r.left * dpr, r.top * dpr, r.width * dpr, r.height * dpr];
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

  /// Locks the cards whose home is one of [homes] (in that order), moving only single pieces.
  Future<void> lockHomes(WidgetTester tester, List<int> homes) async {
    for (final home in homes) {
      final b = board(tester);
      if (home >= b.cells || b.isLocked(home)) continue;
      final from = b.slotOfCard(home);
      if (!single(b, from) || !single(b, home)) continue;
      await move(tester, from, home);
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

  /// (Board sizes past Relaxed open with levels: a quick CJW_STORE_ONLY run plays a level-1 guest.)
  /// The Library scrolled one row down, so the grid starts with packs (the My Puzzles tile, the
  /// first of the All grid, has no picture of its own).
  Future<void> libraryPacksFirst(WidgetTester tester) async {
    final tile = find.byKey(const ValueKey('library-my-puzzles'));
    if (tile.evaluate().isEmpty) return;
    // The glass bar ends at y 111; a drag stops about 17 short, so this leaves the row under the bar.
    await tester.drag(find.byType(Scrollable).first, Offset(0, -(tester.getRect(tile).bottom - 84)));
    await settle(tester, 2500);
  }

  /// Sets the player's XP (and the level it gives), avatar and streak through the save sync, so the
  /// screenshots show the player growing from slide to slide.
  Future<void> setProgress(WidgetTester tester, {int? xp, String? avatar, int? streak}) async {
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(syncProvider.notifier).enqueue(SyncOp.put({
      'xp': ?xp,
      'level': ?(xp == null ? null : LevelRewards.levelForXp(xp)),
      // Solved pictures in step with the XP (the league lists players who have solved one).
      'puzzlesCompleted': ?(xp == null ? null : xp ~/ 70),
      'totalStars': ?(xp == null ? null : xp ~/ 26),
      'avatar': ?avatar,
      'streak': ?streak,
      'longestStreak': ?streak,
    }));
    await settle(tester, 3500);
  }

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
    // The screen remembers Painting from the last board (the Painting capture comes before the giant
    // one): set it to what this capture asks for.
    final paintingOption = find.byKey(const ValueKey('painting-option'));
    if (paintingOption.evaluate().isNotEmpty && find.byKey(const ValueKey('painting-bonus')).evaluate().isNotEmpty != painting) {
      await tester.ensureVisible(paintingOption);
      await settle(tester, 400);
      await tester.tap(paintingOption, warnIfMissed: false);
      await settle(tester, 700);
    }
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
    await settle(tester, 700);
    if (difficultyShot != null) await shot(tester, difficultyShot);
    await tester.tap(find.byKey(const ValueKey('play-board')), warnIfMissed: false);
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

  /// The store scrolled to its Tickets and Boosters sections, every booster tile whole: the App
  /// Review screenshot of the ticket and booster products (store/review/iap-review-boosters.png; the
  /// coin products keep the top of the store, 11_store).
  Future<void> storeBoosters(WidgetTester tester) async {
    final list = find.descendant(of: find.byType(StoreScreen), matching: find.byType(Scrollable)).first;
    final tickets = find.descendant(of: find.byType(StoreScreen), matching: find.text('Tickets'));
    await tester.dragUntilVisible(tickets, list, const Offset(0, -200));
    await settle(tester, 800);
    // The Tickets heading a little under the bar (exactly: a drag loses some to the touch slop).
    final position = tester.state<ScrollableState>(list).position;
    void scrollBy(double dy) => position.jumpTo((position.pixels + dy).clamp(position.minScrollExtent, position.maxScrollExtent));
    scrollBy(tester.getTopLeft(tickets.first).dy - 168);
    await settle(tester, 1200);
    final grids = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ProductGrid');
    final floor = tester.view.physicalSize.height / tester.view.devicePixelRatio - 24;
    final boosters = tester.getRect(grids.at(2));
    if (boosters.bottom > floor) {
      scrollBy(boosters.bottom - floor);
      await settle(tester, 1200);
    }
    expect(tester.getRect(grids.at(2)).bottom, lessThanOrEqualTo(floor + 1), reason: 'every booster tile whole');
    expect(tester.getTopLeft(tickets.first).dy, greaterThan(100), reason: 'the Tickets heading below the bar');
    await shot(tester, '35_store_boosters');
  }

  testWidgets('capture store screens', (tester) async {
    final stage = _StageCoop();
    SharePlatform.instance = _NoShare();
    SharedPreferences.setMockInitialValues({
      'themeMode': theme,
      // No break offers between the captured completions.
      'lifetimeCompletions': -50,
    });
    final store = await LocalStore.open();
    await FirstSteps.skipFor(store); // the whole app; integration_test/first_steps_test.dart plays the first steps
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        // Shapes and options open as levels rise (lib/state/unlocks.dart); these suites play every one, so all are open and no intro sheet interrupts them.
        openFeaturesProvider.overrideWithValue(OpenFeatures.all),
        pendingUnlockIntroProvider.overrideWithValue(null),
        // Play together's slide: a scripted game with two made-up friends (their profiles below), and
        // their moved cards marked long enough to be captured.
        coopBackendProvider.overrideWithValue(stage),
        coopTimingProvider.overrideWithValue(const CoopTiming(markFor: Duration(minutes: 2))),
        playerProfileProvider.overrideWith((ref, id) async {
          final friend = coopFriends[id];
          if (friend != null) return Profile.guest(id).copyWith(displayName: friend.$1, avatar: friend.$2);
          if (id == ref.watch(currentUserIdProvider)) {
            final mine = ref.watch(profileProvider).value;
            if (mine != null) return mine.copyWith(displayName: storePlayerName);
          }
          return ref.watch(profileRepositoryProvider).findByUserId(id);
        }),
        // A full, varied league (leagueExtras) and its count.
        leaderboardProvider.overrideWith(_StoreLeaderboard.new),
        leaderboardRankProvider.overrideWith((ref) async {
          final rows = (await ref.watch(leaderboardProvider.future)).items;
          final me = ref.watch(currentUserIdProvider);
          final i = rows.indexWhere((p) => p.userId == me);
          return i < 0 ? null : (rank: i + 1, total: rows.length);
        }),
        // The Library's first packs are the curated ones (libraryFirst); nothing else changes.
        packsProvider.overrideWith((ref) async {
          final rows = await ref.watch(packRowsProvider.future);
          final now = DateTime.now();
          final visible = rows.where((p) => p.visibleTo(const {}, now)).toList();
          int rank(Pack p) => libraryFirst.contains(p.id) ? libraryFirst.indexOf(p.id) : libraryFirst.length;
          final order = [for (final (i, p) in visible.indexed) (i, p)]..sort((a, b) => rank(a.$2) != rank(b.$2) ? rank(a.$2) - rank(b.$2) : a.$1 - b.$1);
          return [for (final e in order) e.$2];
        }),
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

    // Glass set, slide 3: a long streak on Home (the gift was claimed today, so it stays alive).
    if (want('31_home_streak')) {
      await setProgress(tester, streak: 23, xp: 300, avatar: 'leaf');
      await go(tester, '/home', ms: 3000);
      await shot(tester, '31_home_streak');
    }

    // Glass set, slide 1: a bright picture mid-build: about half locked, two joined groups, one
    // loose card selected.
    if (want('25_hero')) {
      try {
        await startGame(tester, brightHeroPuzzle, 'Cards', 'Relaxed');
        await midBuild(tester, 0.3, 3);
        await selectOne(tester);
        await shot(tester, '25_hero');
        await saveAndQuit(tester);
      } catch (e) {
        await binding.takeScreenshot('zz_diag_hero');
        await go(tester, '/home', ms: 2000);
      }
    }

    // Play together: a shared board mid-game, the host's view, with two friends: the players chip,
    // the card Ava holds and the card Leo just moved, each in their colour and with their initial.
    if (want('32_coop_board') || want('33_coop_players')) {
      try {
        // A big board, as friends play one: Cards 7x7 (Master), opened on its route (a capture run's
        // guest has not reached Master's level; the game screen does not ask).
        await push(tester, '/game/$coopPuzzle/cards-7x7t7', ms: 6000);
        for (var i = 0; i < 20 && boardFinder().evaluate().isEmpty; i++) {
          await settle(tester, 500);
        }
        await tapIfShown(tester, 'Got it');
        expect(boardFinder(), findsOneWidget, reason: 'co-op board');
        // Several locked areas (the middle, two corners) and a few joined groups among the loose cards.
        final n = board(tester).tiling.cols;
        int at(int r, int c) => r * n + c;
        await lockHomes(tester, [
          for (var r = 2; r <= 4; r++)
            for (var c = 2; c <= 4; c++) at(r, c),
          at(0, 0), at(0, 1), at(1, 0), at(1, 1),
          at(5, 5), at(5, 6), at(6, 5), at(6, 6),
        ]);
        for (var g = 0; g < 4; g++) {
          if (!await buildAnyGroup(tester)) break;
        }
        stage.me = ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(currentUserIdProvider) ?? '';
        await tester.tap(find.byIcon(CupertinoIcons.pause_fill), warnIfMissed: false);
        await settle(tester, 1200);
        await tester.tap(find.byKey(const ValueKey('pause-play-together')), warnIfMissed: false);
        await settle(tester, 3000);
        stage.seat();
        // The join toasts come and go before the capture.
        await settle(tester, 7000);
        // The same board before the friends' moves, without their marks (the homepage draws its own
        // live cursors and marks on it), and which cards are locked there (they cannot be held).
        await shot(tester, '34_coop_clean');
        final clean = board(tester);
        binding.reportData ??= <String, dynamic>{};
        ((binding.reportData!['boards'] ??= <String, dynamic>{}) as Map<String, dynamic>)['34_coop_locked$suffix'] = [
          for (var s = 0; s < clean.cells; s++)
            if (clean.isLocked(s)) s.toDouble(),
        ];
        // Leo makes two moves (four cards with his purple "L"); Ava holds a card in an open area (no
        // locked or marked card around it), so her orange outline reads at this card size. Single
        // cards first; a board that left fewer than two uses any loose card instead.
        final leo = <int>{};
        for (var k = 0; k < 2; k++) {
          final b = board(tester);
          final loose = [for (var s = 0; s < b.cells; s++) if (!b.isLocked(s) && !leo.contains(s)) s];
          final singles = loose.where((s) => single(b, s)).toList();
          final pool = singles.length >= 2 ? singles : loose;
          if (pool.length < 2) break;
          // A move that locks neither card, so Leo's marks stay on loose cards (first such pair).
          var from = pool.first, to = pool[pool.length ~/ 2];
          search:
          for (final a in pool) {
            for (final c in pool.reversed) {
              final m = a == c ? null : b.moveTo(a, c);
              if (m != null && !m.isLocked(a) && !m.isLocked(c)) {
                (from, to) = (a, c);
                break search;
              }
            }
          }
          final after = b.moveTo(from, to);
          if (after != null) stage.move('stage-leo', b.slots, after.slots);
          leo.addAll([from, to]);
          await settle(tester, 1500);
        }
        final now = board(tester);
        final cols = now.tiling.cols;
        List<int> around(int s) => [
              for (var dr = -1; dr <= 1; dr++)
                for (var dc = -1; dc <= 1; dc++)
                  if ((dr != 0 || dc != 0) && s ~/ cols + dr >= 0 && s ~/ cols + dr < now.cells ~/ cols && s % cols + dc >= 0 && s % cols + dc < cols) (s ~/ cols + dr) * cols + s % cols + dc,
            ];
        int crowd(int s) => around(s).where((x) => now.isLocked(x) || leo.contains(x)).length;
        final free = [for (var s = 0; s < now.cells; s++) if (!now.isLocked(s) && !leo.contains(s)) s];
        final freeSingles = free.where((s) => single(now, s)).toList()..sort((a, b) => crowd(a).compareTo(crowd(b)));
        final held = freeSingles.isNotEmpty ? freeSingles.first : (free.isNotEmpty ? free.last : null);
        if (held != null) {
          stage.hold('stage-ava', now.slots[held]);
          // The store slide lifts Ava's card with her outline (drawn just outside the card).
          recordCell(tester, '32_coop_held', held, pad: 1.5);
        } else {
          stage.hold('stage-ava', -1);
        }
        await settle(tester, 1500);
        await shot(tester, '32_coop_board');
        // The player list from the players chip: everyone's avatar in their colour ring, Host and You,
        // Remove on the friends (the store slide lifts its rows). Taken with 32, from the same game.
        // Leo is still at the board (his presence would otherwise read Away by now).
        stage.hold('stage-leo', -1);
        await settle(tester, 800);
        await tester.tap(find.byKey(const ValueKey('coop-players-chip')), warnIfMissed: false);
        await settle(tester, 1800);
        await shot(tester, '33_coop_players');
        await tester.tapAt(const Offset(200, 120));
        await settle(tester, 1200);
        final c = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
        c.read(coopProvider.notifier).clear();
        await saveAndQuit(tester);
      } catch (e) {
        await binding.takeScreenshot('zz_diag_coop');
        await go(tester, '/home', ms: 2000);
      }
    }

    // Glass set, slide 5: Painting on Monet's chrysanthemums, mostly still grey: a few cards locked
    // (in colour) in the middle, two joined groups among the grey ones.
    if (want('26_painting')) {
      try {
        await startGame(tester, paintingPuzzle, 'Cards', 'Relaxed', painting: true);
        await midBuild(tester, 0.2, 2);
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
        await startGame(tester, giantPuzzle, 'Squares', 'Giant');
        await midBuild(tester, 0.1, 3);
        await shot(tester, '27_giant');
        // Zoomed in on the edge of the solved part, so the overview map shows in the corner.
        await tester.tap(find.byKey(const ValueKey('zoom-in')), warnIfMissed: false);
        await settle(tester, 1200);
        final w = tester.widget<BoardWidget>(boardFinder().first);
        final t = board(tester).tiling;
        w.zoom?.lookAt(t.cellCenter((t.rows * 0.42).round() * t.cols + (t.cols * 0.3).round(), Size(w.width, w.height)));
        // The map's first-use hint ("Tap a card to see its place on the map") fades out over the header.
        await settle(tester, 6000);
        await shot(tester, '30_giant_zoom');
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
        await midBuild(tester, 0.3, 3);
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
      if (want('15_library')) {
        await setProgress(tester, xp: 600, avatar: 'leaf');
        await go(tester, '/library', ms: 4500);
        await libraryPacksFirst(tester);
        await shot(tester, '15_library');
      }
      if (want('22_social_league')) {
        await setProgress(tester, xp: 9000, avatar: 'diamond');
        await go(tester, '/social', ms: 4500);
        await shot(tester, '22_social_league');
      }
      if (want('35_store_boosters')) {
        await push(tester, '/store', ms: 4000);
        try {
          await storeBoosters(tester);
        } catch (e) {
          debugPrint('store boosters: $e');
          await binding.takeScreenshot('zz_diag_store_boosters');
        }
        await tester.tap(find.byIcon(CupertinoIcons.xmark).first, warnIfMissed: false);
        await settle(tester, 1200);
      }
      return;
    }


    // Hero: the Monarch on a 12-card board, mostly placed, one fused group,
    // one card lifted. Then finish it (pack progress, quest progress).
    await startGame(tester, heroPuzzle, 'Cards', 'Relaxed', difficultyShot: '02_difficulty');
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
    await startGame(tester, hexPuzzle, 'Hexagons', 'Tricky');
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
      ('Cards', 'Relaxed', '06_mode_cards'),
      ('Squares', 'Relaxed', '07_mode_squares'),
      ('Triangles', 'Relaxed', '08_mode_triangles'),
      ('Hexagons', 'Tricky', '09_mode_hexagons'),
    ]) {
      try {
        await startGame(tester, modesPuzzle, mode, tier);
        await midBuild(tester, 0.4, 3);
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
    await storeBoosters(tester);
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
    // Glass set: the player grows from slide to slide (level 4 in the Library, 9 on Quests, 17 on the
    // leaderboard), each time with another avatar.
    await setProgress(tester, xp: 2700, avatar: 'flower');
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
    await setProgress(tester, xp: 600, avatar: 'leaf');
    await go(tester, '/library', ms: 3500);
    await libraryPacksFirst(tester);
    await shot(tester, '15_library');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1500));
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
          await startGame(tester, lastId, 'Squares', 'Relaxed');
          await midBuild(tester, 0.35, 2);
          await selectOne(tester);
          await shot(tester, '21_my_puzzle_game');
          await saveAndQuit(tester);
        } catch (e) {
          await binding.takeScreenshot('zz_diag_my_puzzle');
        }
      }
    }

    // League.
    await setProgress(tester, xp: 9000, avatar: 'diamond');
    await go(tester, '/social', ms: 4500);
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
