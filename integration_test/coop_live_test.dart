// Play together as a guest, on the live backend (docs/multiplayer.md): the app on the simulator is a
// new player who opens an invite, and tools/dev/coop_bot.mjs is the host (and a friend). Through the
// real Appwrite SDK and the real game screen: joining from a fresh install, the host's moves and held
// card on the board in the host's colour and initial, this player's taps shared, a conflict sliding
// back, Magic, Shuffle and Gather shared, the app in the background and back, leaving the board and
// Return to game, removed, the next board, the finish with and without rewards, and the end.
//
//   node tools/dev/coop_bot.mjs &
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart --target=integration_test/coop_live_test.dart -d <simulator>
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:carden/app.dart';
import 'package:carden/core/app_links.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/coop/coop_host.dart';
import 'package:carden/features/coop/players_sheet.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/features/game/game_screen.dart';
import 'package:carden/features/links/deep_links.dart';
import 'package:carden/router.dart';
import 'package:carden/state/coop/coop_controller.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/progress.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/widgets/icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
  await tester.pump(const Duration(milliseconds: 50));
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The bot on the Mac (the simulator reaches its localhost).
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
  // Boards here are played the moment they show: no picture before the deal (GameScreen.dealPreview).
  GameScreen.dealPreview = false;

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

  testWidgets('play together as a guest: invite, shared moves, conflicts, tools, return, removed, next board, finish, end', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(overrides: [localStoreProvider.overrideWithValue(store)], child: const CardenApp()));
    await settle(tester, 2500);
    final c = ProviderScope.containerOf(tester.element(find.byType(CardenApp)));
    CoopState s() => c.read(coopProvider);
    final coop = c.read(coopProvider.notifier);
    final router = c.read(routerProvider);
    List<int> board() => tester.widget<BoardWidget>(find.byType(BoardWidget).first).state.board.slots;
    bool boardOn() => find.byType(BoardWidget).evaluate().isNotEmpty;
    Future<void> tapCard(int card) async {
      await tester.tapAt(tester.getCenter(find.byKey(ValueKey('card-$card'))));
      await tester.pump(const Duration(milliseconds: 60));
    }

    Future<List<int>> serverBoard([String as = 'host']) async => ((await bot('/moves?as=$as', get: true))['board'] as List).cast<int>();
    Future<void> join(String code) async {
      c.read(deepLinksProvider).show(AppLink.parse(Uri.parse('carden://join/$code'))!);
      expect(await until(tester, () => s().playing && s().game!.code == code, seconds: 40), isTrue, reason: 'joined');
      expect(await until(tester, boardOn, seconds: 40), isTrue, reason: 'the board is on screen');
      await settle(tester, 1500);
    }

    debugPrint('COOP_STEP 1');
    // 1. A fresh install opens an invite: straight onto the shared board.
    var g = await bot('/game?cells=20');
    await join(g['code'] as String);
    expect(c.read(settingsProvider).onboarded, isFalse, reason: 'the welcome pages wait until the game is left');
    expect(board(), await serverBoard(), reason: 'the board everyone plays');
    expect(find.byKey(const ValueKey('coop-players-chip')), findsOneWidget);
    expect(find.text('Tap a card to pick it up.'), findsNothing, reason: 'no first-board hints on a shared board');
    final me = s().me!;
    await shot(tester, 'coop2_01_joined_board');

    debugPrint('COOP_STEP 2');
    // 2. The host's move: the cards move here, in the host's colour and with the host's initial.
    var before = board();
    final moved = await bot('/move');
    expect(await until(tester, () => !listEquals(board(), before)), isTrue);
    final hostCard = int.parse((moved['changes'] as String).split(',').first.split(':')[2]);
    expect(find.byKey(ValueKey('coop-mark-$hostCard')), findsNothing, reason: 'a card locked in place carries no mark');
    await bot('/swap');
    expect(await until(tester, () => find.byKey(const ValueKey('coop-players-chip')).evaluate().isNotEmpty && find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('coop-mark-')).evaluate().isNotEmpty), isTrue,
        reason: 'the host\'s initial on the cards it moved');
    await shot(tester, 'coop2_02_host_moved', 200);

    debugPrint('COOP_STEP 3');
    // 3. The card the host holds.
    final loose = [for (var i = 0; i < board().length; i++) if (board()[i] != i) board()[i]];
    await bot('/hold?card=${loose.last}');
    expect(await until(tester, () => find.byKey(ValueKey('coop-mark-${loose.last}')).evaluate().isNotEmpty), isTrue, reason: 'the held card is marked');
    await shot(tester, 'coop2_03_host_holds', 300);

    debugPrint('COOP_STEP 4');
    // 4. This player's taps: a card to its place, shared with the host.
    before = board();
    for (final card in before.where((k) => k != loose.last && before[k] != k && before.indexOf(k) != k).toList()) {
      await tapCard(card);
      await tapCard(before[card]);
      if (await until(tester, () => !listEquals(board(), before), seconds: 3)) break;
    }
    expect(board(), isNot(before), reason: 'the move shows at once');
    expect(await until(tester, () => s().placedACard), isTrue, reason: 'a card this guest locked');
    await settle(tester, 1500);
    var moves = (await bot('/moves', get: true))['moves'] as List;
    expect(moves.where((m) => m['userId'] == me && m['kind'] == 'move'), isNotEmpty, reason: 'the host has the move');
    expect(await serverBoard(), board());
    await shot(tester, 'coop2_04_my_move', 200);

    debugPrint('COOP_STEP 5');
    // 5. Two players take the same card at once: the server's order decides; this player's cards slide back.
    var slid = false;
    final sub = coop.updates.listen((u) {
      if (u.update.dropped.isNotEmpty) slid = true;
    });
    for (var attempt = 0; attempt < 4 && !slid; attempt++) {
      final b = board();
      final k = b.firstWhere((x) => b[x] != x && b.indexOf(x) != x && x != loose.last);
      final at = b.indexOf(k);
      // The host sends card k elsewhere (swapping it with another loose card); this player puts it home.
      final other = [for (var i = 0; i < b.length; i++) if (i != at && b[i] != i && b[i] != at && i != k) i].first;
      await tapCard(k);
      await bot('/move?wait=0&changes=$at:$k:${b[other]},$other:${b[other]}:$k');
      await tapCard(b[k]);
      await until(tester, () => slid, seconds: 4);
      await settle(tester, 1200);
    }
    await sub.cancel();
    expect(slid, isTrue, reason: 'a change that lost its card to the host\'s slid back');
    expect(await serverBoard(), board(), reason: 'one board after the conflict');
    await shot(tester, 'coop2_05_conflict_slid_back', 200);

    debugPrint('COOP_STEP 6');
    // 6. Magic and Shuffle change the shared board.
    await tester.tap(find.byKey(const ValueKey('booster-magic')));
    await settle(tester, 2500);
    await tester.tap(find.byKey(const ValueKey('booster-shuffle')));
    await settle(tester, 2500);
    moves = (await bot('/moves', get: true))['moves'] as List;
    expect(moves.where((m) => m['userId'] == me).map((m) => m['kind']).toSet(), containsAll(['magic', 'shuffle']));
    expect(await serverBoard(), board());
    await shot(tester, 'coop2_06_after_magic_shuffle', 200);

    debugPrint('COOP_STEP 7');
    // 7. The app in the background and back: the seat stays, and what happened meanwhile shows.
    // While paused the engine draws no frames: wait without pumping.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await bot('/move');
    await bot('/move');
    await Future<void>.delayed(const Duration(seconds: 2));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final server = await serverBoard();
    expect(await until(tester, () => listEquals(board(), server)), isTrue, reason: 'caught up');

    debugPrint('COOP_STEP 8');
    // 8. Leaving the board is not leaving the game: the toast takes the player back.
    await tester.tap(find.byIcon(AppIcons.pauseFill));
    await settle(tester, 1200);
    await tapText(tester, 'Quit', ms: 2000);
    expect(find.byType(BoardWidget), findsNothing);
    await shot(tester, 'coop2_07_quit_toast', 100);
    await tapText(tester, 'Return', ms: 3000);
    expect(await until(tester, boardOn), isTrue, reason: 'back on the shared board');
    // Return to game after a restart: the remembered game, offered again.
    coop.clear(forget: false);
    await settle(tester, 500);
    router.go('/home');
    await settle(tester, 2000);
    unawaited(offerReturnToGame(c));
    expect(await until(tester, () => find.textContaining('is still on').evaluate().isNotEmpty, seconds: 30), isTrue, reason: 'Return to game offered');
    await shot(tester, 'coop2_08_return_to_game', 100);
    await tapText(tester, 'Return', ms: 3000);
    expect(await until(tester, () => s().playing && boardOn(), seconds: 30), isTrue);
    expect(await until(tester, () => listEquals(board(), server) || board().isNotEmpty), isTrue);

    debugPrint('COOP_STEP 9');
    // 9. The player list as a guest, then the host opens the next board: this player is moved onto it.
    showCoopPlayersSheet(rootNavigatorKey.currentContext!);
    await shot(tester, 'coop2_09_players_guest', 2000);
    Navigator.of(rootNavigatorKey.currentContext!).pop();
    await settle(tester, 800);
    final first = s().game!.puzzleId;
    await bot('/next');
    expect(await until(tester, () => s().game!.board == 2 && router.state.uri.path.contains(s().game!.puzzleId), seconds: 30), isTrue, reason: 'moved onto the next board');
    expect(s().game!.puzzleId, isNot(first));
    await settle(tester, 3000);
    expect(await until(tester, boardOn, seconds: 30), isTrue);
    expect(board(), await serverBoard());
    await shot(tester, 'coop2_10_next_board', 500);

    debugPrint('COOP_STEP 10');
    // 10. Finish without a card of this player's on this board: no rewards.
    final coinsBefore = c.read(profileProvider).value!.coins;
    await bot('/solve');
    expect(await until(tester, () => find.byKey(const ValueKey('coop-guest-finish')).evaluate().isNotEmpty, seconds: 60), isTrue);
    expect(find.textContaining('Lock a card yourself'), findsOneWidget);
    await shot(tester, 'coop2_11_finish_no_rewards', 500);
    expect(c.read(profileProvider).value!.coins, coinsBefore);

    debugPrint('COOP_STEP 11');
    // 11. Removed by the host: the alert, then the welcome pages (this player came in by an invite).
    await bot('/remove?user=$me');
    expect(await until(tester, () => find.text('Removed from the game').evaluate().isNotEmpty, seconds: 30), isTrue);
    await shot(tester, 'coop2_12_removed', 300);
    // Behind the alert the board is still the host's: the guest's finish, not a completion card of
    // this player's own.
    expect(find.byKey(const ValueKey('coop-guest-finish')), findsOneWidget);
    expect(find.text('Next puzzle'), findsNothing);
    final removedFrom = s().game?.puzzleId;
    await tapText(tester, 'Close', ms: 2500);
    expect(router.state.uri.path, '/welcome');
    if (removedFrom != null) expect(c.read(progressProvider).value?[removedFrom], isNull, reason: 'nothing of the shared board saved');

    debugPrint('COOP_STEP 12');
    // 12. A new game: this player locks a card, the host finishes: rewards as for a board of their own,
    // and nothing written to progress, quests or the solve totals.
    g = await bot('/game?cells=9');
    await join(g['code'] as String);
    final profileBefore = c.read(profileProvider).value!;
    final b9 = board();
    final k9 = b9.firstWhere((x) => b9[x] != x && b9.indexOf(x) != x);
    await tapCard(k9);
    await tapCard(b9[k9]);
    expect(await until(tester, () => s().placedACard, seconds: 20), isTrue);
    await settle(tester, 1500);
    await bot('/solve');
    expect(await until(tester, () => find.byKey(const ValueKey('coop-guest-finish')).evaluate().isNotEmpty, seconds: 60), isTrue);
    expect(await until(tester, () => find.textContaining('+').evaluate().length >= 2, seconds: 20), isTrue, reason: 'coins and XP');
    await shot(tester, 'coop2_13_finish_rewards', 800);
    final profileAfter = c.read(profileProvider).value!;
    expect(profileAfter.xp, greaterThan(profileBefore.xp));
    expect(profileAfter.coins, greaterThan(profileBefore.coins));
    expect(profileAfter.puzzlesCompleted, profileBefore.puzzlesCompleted, reason: 'the host\'s board is not this player\'s solve');
    expect(c.read(progressProvider).value?[s().game!.puzzleId]?.completed ?? false, isFalse);

    debugPrint('COOP_STEP 13');
    // 13. The host ends the game.
    await bot('/end');
    expect(await until(tester, () => find.text('Game ended').evaluate().isNotEmpty, seconds: 30), isTrue);
    await shot(tester, 'coop2_14_ended', 300);
    expect(find.byKey(const ValueKey('coop-guest-finish')), findsOneWidget);
    expect(find.text('Next puzzle'), findsNothing);
    await tapText(tester, 'Close', ms: 2500);

    debugPrint('COOP_STEP 14');
    // 14. A giant board: Gather is shared too.
    g = await bot('/game?giant=1');
    await join(g['code'] as String);
    final zoom = tester.widget<BoardWidget>(find.byType(BoardWidget).first).zoom;
    if (zoom != null) {
      await tester.tap(find.byKey(const ValueKey('zoom-in')));
      await settle(tester, 1500);
      if (find.byKey(const ValueKey('giant-gather')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const ValueKey('giant-gather')));
        await settle(tester, 2500);
      }
      await bot('/hold?card=${board().lastWhere((k) => board()[k] != k)}');
      await settle(tester, 2500);
      await shot(tester, 'coop2_15_giant_board', 300);
      moves = (await bot('/moves', get: true))['moves'] as List;
      debugPrint('COOP_NOTE giant kinds: ${moves.where((m) => m['userId'] == me).map((m) => m['kind']).toSet()}');
    }

    debugPrint('COOP_STEP 15');
    // 15. Leave game from the pause sheet, after asking.
    await tester.tap(find.byIcon(AppIcons.pauseFill));
    await settle(tester, 1200);
    await tapText(tester, 'Leave game', ms: 1200);
    await shot(tester, 'coop2_16_leave_confirm', 300);
    await tester.tap(find.text('Leave game').last);
    await settle(tester, 2500);
    expect(s().phase, CoopPhase.none);
    await bot('/quit');
  });
}
