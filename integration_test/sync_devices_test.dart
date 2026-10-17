// One save on two devices (live Appwrite backend, fresh QA guest):
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/sync_devices_test.dart -d CDD7317C-19D6-486D-B258-8AB8A607297D
// The app is the player's iPhone. A second save sync in the same process, with its own storage
// and the same session, is the player's laptop on the web site. Covers: what the laptop did
// shows on the iPhone after it comes back to the foreground; play without a connection is sent
// later and adds up with the laptop's; two different boards of one picture ask the player; the
// laptop going on with the board open on the iPhone reloads it there; the laptop finishing that
// board closes it on the iPhone, whose later save of the old board leaves the win alone. Captures
// screenshots/sync_*.png; facts go to build/integration_response_data.json.
import 'package:carden/app.dart';
import 'package:carden/core/appwrite.dart';
import 'package:carden/core/qa.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/data/sync/backend.dart';
import 'package:carden/game/board.dart';
import 'package:carden/models/models.dart';
import 'package:carden/router.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/progress.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/sync.dart';
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

/// The laptop's own storage (a browser's localStorage).
class _MemPrefs implements SharedPreferences {
  final values = <String, Object>{};
  @override
  String? getString(String key) => values[key] as String?;
  @override
  Future<bool> setString(String key, String value) async => (values[key] = value) == value;
  @override
  bool? getBool(String key) => values[key] as bool?;
  @override
  Future<bool> setBool(String key, bool value) async => (values[key] = value) == value;
  @override
  int? getInt(String key) => values[key] as int?;
  @override
  Future<bool> setInt(String key, int value) async => (values[key] = value) == value;
  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  bool containsKey(String key) => values.containsKey(key);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('${invocation.memberName}');
}

/// The iPhone's connection, which the test can cut.
class _Network implements SyncBackend {
  _Network(this.inner);
  final SyncBackend inner;
  bool online = true;

  Future<T> _go<T>(Future<T> Function() f) {
    if (!online) throw Exception('The Internet connection appears to be offline.');
    return f();
  }

  @override
  Future<Map<String, dynamic>?> getProfile(String userId) => _go(() => inner.getProfile(userId));
  @override
  Future<Map<String, dynamic>> createProfile(String userId, Map<String, dynamic> data) => _go(() => inner.createProfile(userId, data));
  @override
  Future<Map<String, dynamic>> updateProfile(String userId, Map<String, dynamic> data) => _go(() => inner.updateProfile(userId, data));
  @override
  Future<List<Map<String, dynamic>>> progressRows(String userId, {String? since}) => _go(() => inner.progressRows(userId, since: since));
  @override
  Future<Map<String, dynamic>?> getProgress(String userId, String puzzleId) => _go(() => inner.getProgress(userId, puzzleId));
  @override
  Future<Map<String, dynamic>> upsertProgress(String userId, String puzzleId, Map<String, dynamic> data) =>
      _go(() => inner.upsertProgress(userId, puzzleId, data));
  @override
  Future<void> upsertEvent(String userId, String eventId, Map<String, dynamic> data) => _go(() => inner.upsertEvent(userId, eventId, data));
  @override
  Future<Map<String, dynamic>?> getEvent(String userId, String eventId) => _go(() => inner.getEvent(userId, eventId));
  @override
  Future<void> createLedger(String userId, String rowId, Map<String, dynamic> data) => _go(() => inner.createLedger(userId, rowId, data));
  @override
  Future<bool> signedIn() => _go(() => inner.signedIn());
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, 700);
    await binding.takeScreenshot(name);
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  /// An alert's button: the alert is on top, so its label is the last match (Home behind it can
  /// show the same word, as the Continue card of a board in progress).
  Future<void> tapAlert(WidgetTester tester, String label, {int ms = 1200}) async {
    final f = find.text(label);
    expect(f, findsWidgets, reason: 'expected "$label" on screen');
    await tester.tap(f.last, warnIfMissed: false);
    await settle(tester, ms);
  }

  /// The iPhone leaves the foreground and comes back (what a player switching devices does).
  /// Only as far as inactive: hidden and paused stop the frames the test pumps, and inactive is
  /// where the app already saves and syncs.
  Future<void> background(WidgetTester tester) async {
    // ignore: invalid_use_of_protected_member
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await settle(tester, 1500);
  }

  Future<void> foreground(WidgetTester tester, {int ms = 6000}) async {
    // ignore: invalid_use_of_protected_member
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester, ms);
  }

  testWidgets('one save on an iPhone and a laptop', (tester) async {
    expect(QaRun.enabled, isTrue, reason: 'run through tools/dev/qa-run.sh');
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await FirstSteps.skipFor(store); // the whole app; integration_test/first_steps_test.dart plays the first steps
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    late _Network net;
    await tester.pumpWidget(ProviderScope(overrides: [
      localStoreProvider.overrideWithValue(store),
      syncBackendProvider.overrideWith((ref) => net = _Network(AppwriteSyncBackend(ref.watch(tablesProvider), ref.watch(accountProvider)))),
    ], child: const CardenApp()));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 4000);
    if (find.text('Claim').evaluate().isNotEmpty) {
      await tapText(tester, 'Claim');
      if (find.textContaining('Claim day').evaluate().isNotEmpty) {
        await tester.tap(find.textContaining('Claim day'), warnIfMissed: false);
        await settle(tester, 1500);
      }
      await tester.tapAt(const Offset(220, 80));
      await settle(tester, 1000);
    }

    debugPrint('QA sync: onboarded');
    final phone = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    await phone.read(syncProvider.notifier).flush();
    final me = await phone.read(profileProvider.future);
    final facts = <String, Object?>{'userId': me.id, 'runId': QaRun.id, 'start': me.coins};

    debugPrint('QA sync: phone ready ${me.id} ${me.coins}');
    // The laptop: same player (the session is shared), its own storage.
    final laptop = ProviderContainer(overrides: [localStoreProvider.overrideWithValue(LocalStore(_MemPrefs()))]);
    addTearDown(laptop.dispose);
    laptop.listen(profileProvider, (_, _) {});
    laptop.listen(progressProvider, (_, _) {});
    await (() async {
      await laptop.read(profileProvider.future);
      await laptop.read(progressProvider.future);
      await laptop.read(syncProvider.notifier).flush();
    })();
    expect(laptop.read(profileProvider).value!.id, me.id, reason: 'the laptop plays the same save');
    expect(laptop.read(profileProvider).value!.coins, me.coins);

    debugPrint('QA sync: laptop ready');
    final packs = await phone.read(packsProvider.future);
    final puzzles = await phone.read(allPuzzlesProvider.future);
    List<Puzzle> of(Pack p) => puzzles.where((z) => z.packId == p.id && !z.isLockedByDate).toList();
    final free = packs.where((p) => p.isFree && !p.hasWindow && !p.isDaily && of(p).length >= 4).first;
    final pics = of(free);
    final paid = packs.where((p) => !p.isFree && !p.hasWindow && !p.isDaily && p.priceTickets == 0 && p.priceCoins > 0).toList()
      ..sort((a, b) => a.priceCoins.compareTo(b.priceCoins));
    final pack = paid.first;

    // 1. The laptop earns, unlocks and solves while the iPhone is in the background.
    await background(tester);
    final lp = laptop.read(profileProvider.notifier);
    await (() async {
      await lp.addCoins(pack.priceCoins, reason: 'qa');
      expect(await lp.unlockPack(pack), isTrue);
      laptop.read(progressProvider.notifier).complete(pics[0].id, gridSize: 16, mode: 'cards', moves: 22, seconds: 70, hints: 0, stars: 3, session: 'laptop-1', resumed: false);
      await lp.recordCompletion(puzzleId: pics[0].id, cells: 16, stars: 3, firstTime: true, moves: 22, seconds: 70);
      await laptop.read(syncProvider.notifier).flush();
    })();
    final afterLaptop = laptop.read(profileProvider).value!;
    expect(phone.read(profileProvider).value!.coins, me.coins, reason: 'the iPhone has not looked yet');

    debugPrint('QA sync: laptop played');
    await foreground(tester);
    expect(find.text('Synced from another device'), findsOneWidget);
    expect(find.text('Unlocked: ${pack.name}'), findsOneWidget);
    expect(find.text('1 picture solved'), findsOneWidget);
    await shot(tester, 'sync_01_from_laptop');
    await tapAlert(tester, 'Continue');
    expect(phone.read(profileProvider).value!.coins, afterLaptop.coins);
    expect(phone.read(profileProvider).value!.unlockedPacks, contains(pack.id));
    expect(phone.read(progressProvider).value![pics[0].id]?.completed, isTrue);
    facts['afterLaptop'] = afterLaptop.coins;

    // 2. The iPhone loses its connection and keeps playing; the laptop spends and plays the
    //    same picture on another board.
    net.online = false;
    final pp = phone.read(profileProvider.notifier);
    await pp.addCoins(100, reason: 'qa');
    phone.read(progressProvider.notifier).saveBoard(pics[1].id, gridSize: 16, mode: 'cards', layout: [for (var i = 15; i >= 0; i--) i], moves: 5, seconds: 30, hints: 0, session: 'phone-2', resumed: false);
    await settle(tester, 1500);
    expect(phone.read(syncProvider).pending, greaterThan(0), reason: 'queued on the iPhone');
    await background(tester);
    await (() async {
      await laptop.read(syncProvider.notifier).sync();
      expect(await lp.spendCoins(75, reason: 'peek'), isTrue);
      laptop.read(progressProvider.notifier).saveBoard(pics[1].id, gridSize: 16, mode: 'cards', layout: [for (var i = 0; i < 16; i++) (i + 1) % 16], moves: 11, seconds: 64, hints: 0, session: 'laptop-2', resumed: false);
      await laptop.read(syncProvider.notifier).flush();
    })();
    debugPrint('QA sync: offline phase played');
    net.online = true;
    await foreground(tester, ms: 4000);
    expect(find.text('Two boards in progress'), findsOneWidget);
    await shot(tester, 'sync_02_two_boards');
    await tester.tap(find.byKey(const ValueKey('keep-other-board')), warnIfMissed: false);
    await settle(tester, 4000);
    expect(find.text('Synced from another device'), findsOneWidget);
    await shot(tester, 'sync_03_after_offline');
    await tapAlert(tester, 'Continue');
    expect(find.text('Synced from another device'), findsNothing);
    await laptop.read(syncProvider.notifier).sync();
    final expected = afterLaptop.coins + 100 - 75;
    expect(phone.read(profileProvider).value!.coins, expected, reason: 'offline play and the laptop add up');
    expect(laptop.read(profileProvider).value!.coins, expected);
    expect(phone.read(progressProvider).value![pics[1].id]!.moves, 11, reason: "the laptop's board was kept");
    expect(phone.read(syncProvider).pending, 0);
    facts['afterOffline'] = expected;

    // 3. A board open on the iPhone, continued on the laptop: the iPhone reloads it.
    debugPrint('QA sync: offline phase checked');
    final spec = BoardSpec.fromCells(GameMode.cards, 16);
    phone.read(routerProvider).push('/game/${pics[2].id}/${BoardCode.toPath(spec.fullCode)}');
    await settle(tester, 6000);
    await background(tester);
    await settle(tester, 2000);
    final saved = phone.read(progressProvider).value![pics[2].id];
    expect(saved?.inProgress, isTrue, reason: 'going to the background saves the board');
    await (() async {
      await laptop.read(syncProvider.notifier).sync();
      final row = laptop.read(progressProvider).value![pics[2].id]!;
      final next = [...row.layout!];
      final t = next[0];
      next[0] = next[1];
      next[1] = t;
      laptop.read(progressProvider.notifier).saveBoard(pics[2].id, gridSize: row.gridSize, mode: row.mode, layout: next, moves: row.moves + 6, seconds: row.elapsedSeconds + 40, hints: 0, session: row.session, resumed: true);
      await laptop.read(syncProvider.notifier).flush();
    })();
    await foreground(tester, ms: 7000);
    expect(find.text('Board updated'), findsOneWidget);
    await shot(tester, 'sync_04_board_updated');
    await tapText(tester, 'Continue', ms: 2000);
    expect(phone.read(progressProvider).value![pics[2].id]!.moves, saved!.moves + 6);
    if (find.text('Got it').evaluate().isNotEmpty) await tapText(tester, 'Got it');
    // The game on screen is the laptop's board: its move count is in the HUD.
    expect(find.text('${saved.moves + 6}'), findsWidgets);
    await shot(tester, 'sync_05_game_after');

    // 4. The laptop finishes that same board while the iPhone still has it open. Later the iPhone
    //    leaves the foreground, and its game saves the old board: the win stays, and the game closes.
    debugPrint('QA sync: board reload checked');
    final open = phone.read(progressProvider).value![pics[2].id]!;
    await (() async {
      await laptop.read(syncProvider.notifier).sync();
      laptop.read(progressProvider.notifier).complete(pics[2].id, gridSize: open.gridSize, mode: open.mode, moves: open.moves + 9, seconds: open.elapsedSeconds + 50, hints: 0, stars: 3, session: open.session, resumed: true);
      await laptop.read(syncProvider.notifier).flush();
    })();
    // Hours later on the player's clock: the iPhone has not heard from the server since.
    SyncController.boardFreshFor = Duration.zero;
    addTearDown(() => SyncController.boardFreshFor = const Duration(seconds: 30));
    await background(tester);
    await foreground(tester, ms: 5000);
    expect(find.text('Solved on another device'), findsOneWidget);
    await shot(tester, 'sync_06_solved_elsewhere');
    await tapAlert(tester, 'Close board', ms: 3000);
    // What the laptop did while the game was open shows once the board is closed.
    expect(find.text('Synced from another device'), findsOneWidget);
    expect(find.text('1 picture solved'), findsOneWidget);
    await shot(tester, 'sync_07_solved_notice');
    await tapAlert(tester, 'Continue');
    await phone.read(syncProvider.notifier).flush();
    await laptop.read(syncProvider.notifier).sync();
    for (final (name, device) in [('iPhone', phone), ('laptop', laptop)]) {
      final row = device.read(progressProvider).value![pics[2].id]!;
      expect(row.completed, isTrue, reason: 'solved on the $name');
      expect(row.inProgress, isFalse, reason: 'no old board on the $name');
      expect(row.moves, open.moves + 9, reason: "the laptop's win on the $name");
    }
    expect(phone.read(syncProvider).pending, 0);
    expect(find.text('Solved on another device'), findsNothing);
    expect(find.text('Synced from another device'), findsNothing);
    await shot(tester, 'sync_08_after_close');
    facts['solvedElsewhere'] = open.moves + 9;

    binding.reportData = {...?binding.reportData, 'facts': facts};
  });
}
