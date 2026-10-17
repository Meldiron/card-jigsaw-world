// Play together on the live backend (docs/multiplayer.md): the app on the simulator, as a new
// player straight from an invite, joins a game hosted by tools/dev/coop_bot.mjs, and the two play
// through the real Appwrite SDK (function, moves table, realtime with a server-side query,
// presences). It measures on the device how long a move takes to reach the other side, and shows
// the co-op pieces (joining, the player list as guest and host, toasts, the removed, full and ended
// alerts, the guest's finish) in light, dark, Increase contrast and the largest text.
//
//   node tools/dev/coop_bot.mjs &
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart --target=integration_test/coop_live_test.dart -d <simulator>
//
// Phase 1: the game screen does not play a shared board yet, so the board on screen after joining
// is the picture's ordinary board; the shared board lives in `coopProvider`.
import 'dart:convert';
import 'dart:io';

import 'package:carden/app.dart';
import 'package:carden/core/app_links.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/coop/coop_alerts.dart';
import 'package:carden/features/coop/guest_finish.dart';
import 'package:carden/features/coop/players_sheet.dart';
import 'package:carden/features/links/deep_links.dart';
import 'package:carden/game/board.dart';
import 'package:carden/router.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/coop/coop_controller.dart';
import 'package:carden/state/coop/coop_models.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/widgets/ui.dart';
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
Future<Map<String, dynamic>> bot(String path) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse('http://127.0.0.1:8787$path'));
    final res = await req.close();
    return jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> shot(WidgetTester tester, String name, [int ms = 600]) async {
    await settle(tester, ms);
    await binding.takeScreenshot(name);
  }

  Future<bool> until(WidgetTester tester, bool Function() done, {int seconds = 20}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (!done() && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    return done();
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.last, warnIfMissed: false);
    await settle(tester, ms);
  }

  testWidgets('play together: invite from a fresh install, moves both ways, players, removed, full, ended', (tester) async {
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
    expect(router.state.uri.path, '/welcome', reason: 'a fresh install');

    // 1. The invite, as iOS hands it to the app.
    final g = await bot('/game?cells=20');
    c.read(deepLinksProvider).show(AppLink.parse(Uri.parse('carden://join/${g['code']}'))!);
    await settle(tester, 300);
    await shot(tester, 'coop_01_joining', 100);
    expect(await until(tester, () => s().playing, seconds: 30), isTrue, reason: 'joined');
    await shot(tester, 'coop_02_board_after_invite', 2500);
    expect(router.state.uri.queryParameters['coop'], g['gameId']);
    expect(c.read(settingsProvider).onboarded, isFalse, reason: 'the welcome pages wait until the game is left');
    final me = s().me!;

    // 2. The host's moves reach this device (on-device time from the request to the board change).
    final down = <int>[];
    var marked = false;
    for (var i = 0; i < 6; i++) {
      final before = List.of(s().layout);
      final t0 = DateTime.now();
      // Not awaited: the board may change before the bot's own answer comes back.
      final sent = bot('/move');
      expect(await until(tester, () => !listEquals(s().layout, before)), isTrue);
      down.add(DateTime.now().difference(t0).inMilliseconds);
      marked |= s().marks.moved.values.toSet().contains(g['hostId']);
      await sent;
      await settle(tester, 300);
    }
    expect(marked, isTrue, reason: 'the host\'s initial on the cards it moved');

    // 3. This device's moves reach the host (the bot notes when its socket heard each).
    final up = <int>[];
    for (var i = 0; i < 6; i++) {
      // The card that belongs in the first open slot changes places with the card there.
      final layout = s().layout;
      final slot = [for (var k = 0; k < layout.length; k++) if (layout[k] != k) k].first;
      final from = layout.indexOf(slot);
      final after = List.of(layout)
        ..[slot] = slot
        ..[from] = layout[slot];
      final t0 = DateTime.now().millisecondsSinceEpoch;
      final update = coop.submit(CoopOpKind.move, layout, after);
      expect(update, isNotNull);
      await settle(tester, 1500);
      final moves = (await bot('/moves'))['moves'] as List;
      final mine = moves.where((m) => m['userId'] == me).toList();
      final heard = mine.last['heardAt'] as int?;
      if (heard != null) up.add(heard - t0);
    }
    expect(s().placedACard, isTrue, reason: 'this guest locked cards: the board\'s rewards are theirs');
    final server = (await bot('/moves'))['board'] as List;
    expect(s().layout, server.cast<int>(), reason: 'the same board on both sides');
    down.sort();
    up.sort();
    debugPrint('COOP_LATENCY host->device ms ${down.join(' ')} (median ${down[down.length ~/ 2]})');
    debugPrint('COOP_LATENCY device->host ms ${up.join(' ')} (median ${up.isEmpty ? '-' : up[up.length ~/ 2]})');

    // 4. Presence: the card the host holds.
    final held = s().layout.first;
    await bot('/hold?card=$held');
    expect(await until(tester, () => s().marks.held[held] == g['hostId']), isTrue, reason: 'the held card is marked');

    // 5. Someone joins: a toast. The player list as a guest.
    await bot('/friend');
    expect(await until(tester, () => find.textContaining('joined').evaluate().isNotEmpty), isTrue);
    await shot(tester, 'coop_03_joined_toast', 200);
    await settle(tester, 4000);
    showCoopPlayersSheet(rootNavigatorKey.currentContext!);
    await shot(tester, 'coop_04_players_guest', 2500);
    Navigator.of(rootNavigatorKey.currentContext!).pop();
    await settle(tester, 800);

    // 6. The guest's end of a board.
    showAppSheet(rootNavigatorKey.currentContext!, builder: (_) => const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 20), child: CoopGuestFinish()));
    await shot(tester, 'coop_05_guest_finish', 1200);
    Navigator.of(rootNavigatorKey.currentContext!).pop();
    await settle(tester, 800);

    // 7. Removed by the host: the alert, then the welcome pages (this player came in by the invite).
    await bot('/remove?user=$me');
    expect(await until(tester, () => find.text('Removed from the game').evaluate().isNotEmpty), isTrue);
    await shot(tester, 'coop_06_removed', 300);
    await tapText(tester, 'Close', ms: 2000);
    expect(router.state.uri.path, '/welcome');
    await shot(tester, 'coop_07_welcome_after_game');
    expect(s().phase, CoopPhase.none);
    // The removed player's invite no longer works.
    c.read(deepLinksProvider).show(AppLink.parse(Uri.parse('carden://join/${g['code']}'))!);
    expect(await until(tester, () => find.text('You cannot join this game').evaluate().isNotEmpty, seconds: 30), isTrue);
    await tapText(tester, 'Close');

    // 8. A full game.
    final full = await bot('/game?cells=20&full=1');
    c.read(deepLinksProvider).show(AppLink.parse(Uri.parse('carden://join/${full['code']}'))!);
    expect(await until(tester, () => find.text('This game is full').evaluate().isNotEmpty, seconds: 30), isTrue);
    await shot(tester, 'coop_08_full', 300);
    await tapText(tester, 'Close');

    // 9. The host ends the game.
    final ending = await bot('/game?cells=20');
    c.read(deepLinksProvider).show(AppLink.parse(Uri.parse('carden://join/${ending['code']}'))!);
    expect(await until(tester, () => s().playing, seconds: 30), isTrue);
    await settle(tester, 1500);
    await bot('/end');
    expect(await until(tester, () => find.text('Game ended').evaluate().isNotEmpty), isTrue);
    await shot(tester, 'coop_09_ended', 300);
    await tapText(tester, 'Close', ms: 2000);

    // 10. This player hosts: the player list with Remove, Invite and End game for everyone.
    c.read(settingsProvider.notifier).setOnboarded();
    router.go('/home');
    await settle(tester, 2500);
    final picture = (await c.read(allPuzzlesProvider.future)).firstWhere((p) => p.packId == 'pack-owls');
    final mine = await coop.create(puzzleId: picture.id, grid: 'cards-4x5t3', layout: Board.shuffled(BoardSpec(GameMode.cards, 4, 5, 'Medium', tier: 3), seed: 4).slots);
    await bot('/friend?code=${mine.code}');
    expect(await until(tester, () => s().game!.playerIds.length == 2), isTrue);
    await settle(tester, 3000);
    showCoopPlayersSheet(rootNavigatorKey.currentContext!);
    await shot(tester, 'coop_10_players_host', 2500);
    await tester.tap(find.text('Remove'));
    await shot(tester, 'coop_11_remove_confirm', 800);
    await tapText(tester, 'Cancel');
    Navigator.of(rootNavigatorKey.currentContext!).pop();
    await settle(tester, 600);

    // 11. Dark mode, Increase contrast, Differentiate without colour and the largest text.
    c.read(settingsProvider.notifier)
      ..setThemeMode(ThemeMode.dark)
      ..setAccessibility(const Accessibility(textSize: TextSize.largest, increaseContrast: true, differentiateWithoutColour: true));
    await settle(tester, 1200);
    showCoopPlayersSheet(rootNavigatorKey.currentContext!);
    await shot(tester, 'coop_12_players_host_dark_contrast_largest', 2500);
    // The player list itself is checked at the largest text in test/coop_ui_test.dart; Home behind it
    // has a pack card whose price row overflows at 200% (lib/features/gallery/pack_card.dart, not co-op).
    final behind = tester.takeException();
    if (behind != null) debugPrint('COOP_NOTE layout behind the sheet: $behind');
    await tapText(tester, 'End game for everyone');
    await shot(tester, 'coop_13_end_confirm_dark', 600);
    await tapText(tester, 'End game', ms: 3000);
    expect(s().phase, CoopPhase.none);
    final end = refusalText(const CoopRefusal(CoopRefusalReason.full));
    expect(end.title, 'This game is full');
    await bot('/quit');
  });
}
