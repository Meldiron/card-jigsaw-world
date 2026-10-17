// Quests during a replay (2026-10-17), on the real app (live Appwrite backend, a QA guest): a picture
// finished today in Hexagons with Painting, then replayed on Cards without Painting. The replay's
// board, once saved, holds the progress row's board fields (mode, size, Painting); the shape and
// Painting quests must still count the finish as it was finished (`progress.finishes`). The path a
// player takes: Quests (both quests ready) > the picture > Cards > a move > Save & quit > Quests.
//
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/quest_replay_test.dart -d <simulator>
//
// Captures screenshots/qr_*.png.
import 'dart:convert';

import 'package:carden/app.dart';
import 'package:carden/core/appwrite.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/data/sync/backend.dart';
import 'package:carden/data/sync/ops.dart';
import 'package:carden/features/events/quest_rewards.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/features/game/game_screen.dart';
import 'package:carden/game/board.dart';
import 'package:carden/models/models.dart';
import 'package:carden/router.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/progress.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/sync.dart';
import 'package:carden/state/unlocks.dart';
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

/// Bora Bora lagoon (Tropical Beaches), a free library picture.
const picture = 'p-00df45e91273';

/// Stands in for the `progress.finishes` column until the live table has it (it is added on the
/// server before the build that writes it ships): the log written for a row is put back on the rows
/// the server returns without it. Once the column exists the server's rows carry it and this passes
/// them through.
class _FinishColumn implements SyncBackend {
  _FinishColumn(this.inner);
  final SyncBackend inner;
  final logs = <String, String>{};
  var simulated = false;

  Map<String, dynamic> _with(Map<String, dynamic> row) {
    final log = logs['${row['puzzleId']}'];
    if (row.containsKey('finishes') || log == null) return row;
    simulated = true;
    return {...row, 'finishes': log};
  }

  @override
  Future<Map<String, dynamic>> upsertProgress(String userId, String puzzleId, Map<String, dynamic> data) async {
    if (data['finishes'] is String) logs[puzzleId] = data['finishes'] as String;
    return _with(await inner.upsertProgress(userId, puzzleId, data));
  }

  @override
  Future<Map<String, dynamic>?> getProgress(String userId, String puzzleId) async {
    final row = await inner.getProgress(userId, puzzleId);
    return row == null ? null : _with(row);
  }

  @override
  Future<List<Map<String, dynamic>>> progressRows(String userId, {String? since}) async => [for (final r in await inner.progressRows(userId, since: since)) _with(r)];
  @override
  Future<Map<String, dynamic>?> getProfile(String userId) => inner.getProfile(userId);
  @override
  Future<Map<String, dynamic>> createProfile(String userId, Map<String, dynamic> data) => inner.createProfile(userId, data);
  @override
  Future<Map<String, dynamic>> updateProfile(String userId, Map<String, dynamic> data) => inner.updateProfile(userId, data);
  @override
  Future<void> upsertEvent(String userId, String eventId, Map<String, dynamic> data) => inner.upsertEvent(userId, eventId, data);
  @override
  Future<Map<String, dynamic>?> getEvent(String userId, String eventId) => inner.getEvent(userId, eventId);
  @override
  Future<void> createLedger(String userId, String rowId, Map<String, dynamic> data) => inner.createLedger(userId, rowId, data);
  @override
  Future<bool> signedIn() => inner.signedIn();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  GameScreen.dealPreview = false;

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

  Future<bool> tapIfShown(WidgetTester tester, String text, {int ms = 1200}) async {
    if (find.text(text).evaluate().isEmpty) return false;
    await tapText(tester, text, ms: ms);
    return true;
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(CardenApp)));

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 40 && container(tester).read(syncProvider.notifier).debugOps.isNotEmpty; i++) {
      await settle(tester, 500);
    }
  }

  Finder boardFinder() => find.byType(BoardWidget);
  Board board(WidgetTester tester) => tester.widget<BoardWidget>(boardFinder().first).state.board;
  Offset center(WidgetTester tester, int slot) {
    final rect = tester.getRect(boardFinder().first);
    return rect.topLeft + board(tester).tiling.cellCenter(slot, rect.size);
  }

  testWidgets('a replay in progress leaves the shape and Painting quests of today\'s finish', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await FirstSteps.skipFor(store);
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    late _FinishColumn column;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        syncBackendProvider.overrideWith((ref) => column = _FinishColumn(AppwriteSyncBackend(ref.watch(tablesProvider), ref.watch(accountProvider)))),
      ],
      child: const CardenApp(),
    ));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 5000);
    final c = container(tester);
    final now = DateTime.now();
    final day = 'd:${Goals.dayKey(now)}';

    // Finished an hour ago: Hexagons 5x5 (27 hexagons) with Painting.
    c.read(progressProvider.notifier).complete(picture,
        gridSize: 27, mode: 'hexagons', moves: 24, seconds: 140, hints: 0, stars: 3, session: SyncOp.newId(), resumed: false, painting: true, par: 20,
        at: now.subtract(const Duration(hours: 1)));
    await settle(tester, 1500);
    await flush(tester);

    // Today's second and third quests as the shape and Painting ones (a swap names what a slot shows;
    // the first dealt stays first).
    List<Goal> daily() => questsFor((c.read(progressProvider).value ?? const {}).values, c.read(profileProvider).value, c.read(openFeaturesProvider), DateTime.now()).daily;
    final dealt = daily();
    String kind(Goal g) => g.key.split(':').last;
    c.read(syncProvider.notifier).enqueue(SyncOp.put({
      'questSwaps': jsonEncode({
        '$day:s2': [kind(dealt[1]), 'mode-hexagons'],
        '$day:s3': [kind(dealt[2]), 'paint'],
      }),
    }));
    await settle(tester, 1500);
    await flush(tester);

    Goal quest(String title) => daily().firstWhere((g) => g.title == title, orElse: () => throw StateError('no quest "$title" in ${[for (final g in daily()) g.title]}'));
    void expectReady(String when) {
      for (final title in ['Finish a board in Hexagons', 'Solve a Painting board']) {
        expect(quest(title).done, isTrue, reason: '$title, $when');
        expect(find.text(title), findsOneWidget, reason: '$title on the Quests tab, $when');
      }
    }

    c.read(routerProvider).go('/events');
    await settle(tester, 3000);
    expectReady('after the finish');
    await shot(tester, 'qr_01_quests_finished');

    // The replay: the picture again, on Cards without Painting; one move, then Save & quit.
    c.read(routerProvider).push('/play/$picture');
    await settle(tester, 3500);
    await tapText(tester, 'Cards', ms: 900);
    await tester.dragUntilVisible(find.text('Cozy'), find.byType(Scrollable).first, const Offset(0, -200));
    await settle(tester, 500);
    await tapText(tester, 'Cozy', ms: 900);
    final painting = find.byKey(const ValueKey('painting-option'));
    if (painting.evaluate().isNotEmpty && find.byKey(const ValueKey('painting-bonus')).evaluate().isNotEmpty) {
      await tester.ensureVisible(painting);
      await settle(tester, 400);
      await tester.tap(painting, warnIfMissed: false);
      await settle(tester, 700);
    }
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
    await settle(tester, 700);
    await shot(tester, 'qr_02_replay_board_picked');
    await tester.tap(find.byKey(const ValueKey('play-board')), warnIfMissed: false);
    await settle(tester, 6000);
    for (var i = 0; i < 20 && boardFinder().evaluate().isEmpty; i++) {
      await settle(tester, 500);
    }
    await tapIfShown(tester, 'Got it');
    expect(boardFinder(), findsOneWidget, reason: 'the replay board');
    final b = board(tester);
    final loose = [for (var s = 0; s < b.cells; s++) if (!b.isLocked(s) && b.groupOf(s).length == 1) s];
    await tester.tapAt(center(tester, loose[0]));
    await settle(tester, 300);
    await tester.tapAt(center(tester, loose[1]));
    await settle(tester, 900);
    await shot(tester, 'qr_03_replay_in_progress');
    for (var attempt = 0; attempt < 3 && find.byIcon(CupertinoIcons.pause_fill).evaluate().isNotEmpty; attempt++) {
      await tester.tap(find.byIcon(CupertinoIcons.pause_fill), warnIfMissed: false);
      await settle(tester, 1200);
      await tapIfShown(tester, 'Save & quit', ms: 2500);
    }
    await flush(tester);

    // The row on the server holds the replay's board now: Cards 3x3, no Painting, in progress.
    final userId = (await c.read(authProvider.future))!.$id;
    final server = await c.read(syncBackendProvider).getProgress(userId, picture);
    final row = PuzzleProgress.fromRow('', server!);
    expect((row.inProgress, row.mode, row.painting), (true, 'cards', false), reason: 'the replay is saved over the board fields');
    expect(row.gridSize, isNot(27));
    expect([for (final f in row.finishes) (f.mode, f.gridSize, f.painting)], [('hexagons', 27, true)], reason: 'the finish as it was');

    c.read(routerProvider).go('/events');
    await settle(tester, 3000);
    expectReady('with the replay in progress');
    await shot(tester, 'qr_04_quests_replay_in_progress');
    debugPrint('QA_QR finishes column on the server: ${column.simulated ? 'not yet (stood in for by the test)' : 'yes'}; row ${server['mode']} ${server['gridSize']} painting=${server['painting']}');
  });
}
