// Play together as the host, on the live backend (docs/multiplayer.md): the app on the simulator
// starts a game from the pause sheet and tools/dev/coop_bot.mjs joins it with the shared link. The
// share sheet is replaced by a recorder (a test cannot tap the system's). Through the real game
// screen: the invite, the friend's toast and cards in their colour, this player's move shared, the
// host's normal completion card, Next puzzle moving the friend onto the next board, Remove, and End
// game for everyone.
//
//   node tools/dev/coop_bot.mjs &
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart --target=integration_test/coop_host_test.dart -d <simulator>
import 'dart:convert';
import 'dart:io';

import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/coop/players_sheet.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/router.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/coop/coop_controller.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/progress.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/widgets/icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps what the app shares instead of opening the system share sheet.
class _Recorder extends SharePlatform {
  final shared = <String>[];
  @override
  Future<ShareResult> share(ShareParams params) async {
    shared.add(params.text ?? '');
    return const ShareResult('recorded', ShareResultStatus.success);
  }
}

Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
  await tester.pump(const Duration(milliseconds: 50));
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<Map<String, dynamic>> bot(String path, {bool get = false}) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('http://127.0.0.1:8787$path');
    final req = get ? await client.getUrl(uri) : await client.postUrl(uri);
    final res = await req.close();
    return jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final recorder = _Recorder();
  SharePlatform.instance = recorder;

  Future<void> shot(WidgetTester tester, String name, [int ms = 600]) async {
    await settle(tester, ms);
    await binding.takeScreenshot(name);
  }

  Future<bool> until(WidgetTester tester, bool Function() done, {int seconds = 20}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (!done() && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    return done();
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.last, warnIfMissed: false);
    await settle(tester, ms);
  }

  testWidgets('play together as the host: share, friend joins, shared moves, completion, next board, remove, end', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    store.onboarded = true;
    await FirstSteps.skipFor(store);
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(overrides: [localStoreProvider.overrideWithValue(store)], child: const CardenApp()));
    await settle(tester, 3000);
    final c = ProviderScope.containerOf(tester.element(find.byType(CardenApp)));
    CoopState s() => c.read(coopProvider);
    final router = c.read(routerProvider);
    List<int> board() => tester.widget<BoardWidget>(find.byType(BoardWidget).first).state.board.slots;
    bool boardOn() => find.byType(BoardWidget).evaluate().isNotEmpty;
    Future<void> tapCard(int card) async {
      await tester.tapAt(tester.getCenter(find.byKey(ValueKey('card-$card'))));
      await tester.pump(const Duration(milliseconds: 60));
    }

    Future<List<int>> friendBoard() async => ((await bot('/moves?as=friend', get: true))['board'] as List).cast<int>();
    expect(c.read(settingsProvider).onboarded, isTrue);
    final pictures = (await c.read(allPuzzlesProvider.future)).where((p) => p.packId == 'pack-owls').toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final picture = pictures.first;
    router.push('/game/${picture.id}/cards-3x3t0');
    expect(await until(tester, boardOn, seconds: 60), isTrue);
    await settle(tester, 2000);

    debugPrint('COOP_STEP 1');
    // 1. Pause > Play together: the game starts on this board and the invite is shared.
    await tester.tap(find.byIcon(AppIcons.pauseFill));
    await settle(tester, 1200);
    await shot(tester, 'coop2h_01_pause_play_together', 100);
    await tester.tap(find.byKey(const ValueKey('pause-play-together')));
    expect(await until(tester, () => recorder.shared.isNotEmpty, seconds: 60), isTrue, reason: 'the invite went to the share sheet');
    final text = recorder.shared.single;
    debugPrint('COOP_NOTE shared: $text');
    expect(text, startsWith('Play ${picture.title} with me in Carden'));
    final code = RegExp(r'play\.carden\.page/join/([A-Z0-9]{8})').firstMatch(text)!.group(1)!;
    expect(s().playing && s().isHost, isTrue);
    await settle(tester, 1500);
    expect(find.byKey(const ValueKey('coop-players-chip')), findsOneWidget);
    final hostBoard = board();

    debugPrint('COOP_STEP 2');
    // 2. The friend opens the link: a toast, two players, the same board.
    await bot('/friend?code=$code');
    expect(await until(tester, () => find.textContaining('joined').evaluate().isNotEmpty, seconds: 30), isTrue);
    await shot(tester, 'coop2h_02_friend_joined', 100);
    expect(await friendBoard(), hostBoard);

    debugPrint('COOP_STEP 3');
    // 3. The friend's cards in the friend's colour, and the card the friend holds.
    final before = board();
    await bot('/swap?as=friend');
    expect(await until(tester, () => !listEquals(board(), before)), isTrue);
    final loose = [for (var i = 0; i < board().length; i++) if (board()[i] != i) board()[i]];
    await bot('/hold?as=friend&card=${loose.first}');
    expect(await until(tester, () => find.byKey(ValueKey('coop-mark-${loose.first}')).evaluate().isNotEmpty), isTrue);
    await shot(tester, 'coop2h_03_friend_marks', 200);

    debugPrint('COOP_STEP 4');
    // 4. The host's move reaches the friend.
    final b = board();
    for (final k in b.where((k) => b[k] != k && b.indexOf(k) != k).toList()) {
      await tapCard(k);
      await tapCard(b[k]);
      if (await until(tester, () => !listEquals(board(), b), seconds: 3)) break;
    }
    await settle(tester, 2000);
    expect(await friendBoard(), board());

    debugPrint('COOP_STEP 5');
    // 5. The player list as the host.
    showCoopPlayersSheet(rootNavigatorKey.currentContext!);
    await shot(tester, 'coop2h_04_players_host', 2000);
    Navigator.of(rootNavigatorKey.currentContext!).pop();
    await settle(tester, 800);

    debugPrint('COOP_STEP 6');
    // 6. The friend finishes the board: the host's normal completion card, the solve saved as the host's.
    await bot('/solve?as=friend');
    expect(await until(tester, () => find.text('Next puzzle').evaluate().isNotEmpty, seconds: 60), isTrue, reason: 'the completion card');
    await shot(tester, 'coop2h_05_host_completion', 1500);
    expect(await until(tester, () => c.read(progressProvider).value?[picture.id]?.completed == true, seconds: 20), isTrue, reason: 'the host\'s board is the host\'s own');

    debugPrint('COOP_STEP 7');
    // 7. Next puzzle: dealt here, handed to the game, and the friend is on it.
    await tapText(tester, 'Next puzzle', ms: 2000);
    expect(await until(tester, () => s().game?.board == 2, seconds: 60), isTrue, reason: 'the next board went to the game');
    await settle(tester, 2000);
    final next = await bot('/moves?as=friend', get: true);
    expect(next['number'], 2);
    expect(next['puzzleId'], isNot(picture.id));
    expect(await until(tester, boardOn, seconds: 30), isTrue);
    expect((next['board'] as List).cast<int>(), board(), reason: 'the friend has this board');
    await shot(tester, 'coop2h_06_next_board', 500);

    debugPrint('COOP_STEP 8');
    // 8. Remove the friend, after asking.
    showCoopPlayersSheet(rootNavigatorKey.currentContext!);
    await settle(tester, 2000);
    await tester.tap(find.text('Remove').last);
    await settle(tester, 1000);
    await shot(tester, 'coop2h_07_remove_confirm', 100);
    await tester.tap(find.text('Remove').last);
    expect(await until(tester, () => s().game!.playerIds.length == 1, seconds: 30), isTrue);
    await settle(tester, 1500);
    final gone = await bot('/moves?as=friend', get: true);
    expect(gone['error'], isNotNull, reason: 'the removed friend can no longer read the game');
    if (find.text('Players').evaluate().isNotEmpty) Navigator.of(rootNavigatorKey.currentContext!).pop();
    await settle(tester, 800);

    debugPrint('COOP_STEP 9');
    // 9. End game for everyone from the pause sheet: the board stays the host's.
    await tester.tap(find.byIcon(AppIcons.pauseFill));
    await settle(tester, 1200);
    await tester.tap(find.byKey(const ValueKey('pause-end-game')));
    await settle(tester, 1000);
    await shot(tester, 'coop2h_08_end_confirm', 100);
    await tester.tap(find.text('End game').last);
    expect(await until(tester, () => !s().playing, seconds: 30), isTrue);
    expect(await until(tester, () => find.text('Game ended. The board is yours.').evaluate().isNotEmpty, seconds: 10), isTrue);
    await shot(tester, 'coop2h_09_ended_board_kept', 100);
    expect(find.byKey(const ValueKey('coop-players-chip')), findsNothing);
    expect(boardOn(), isTrue);
    await bot('/quit');
  });
}
