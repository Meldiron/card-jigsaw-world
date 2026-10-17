// Build 126's stuck floating card (TestFlight feedback AGyfyDbbHhCGY72W1h5num0), on the live backend:
// this player drags a card and tools/dev/coop_bot.mjs (the host) takes the same card into its place
// in the middle of the drag, as a second player grabbing the same piece would. The screenshot shows
// what the player is left with after letting go (`screenshots/race_*.png`): the drag ended (the host
// heard it), nothing floats, and a word says who placed the card. Build 126 left the card floating.
//
//   node tools/dev/coop_bot.mjs &
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart --target=integration_test/coop_race_test.dart -d <simulator>
import 'dart:convert';
import 'dart:io';

import 'package:carden/app.dart';
import 'package:carden/core/app_links.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/features/links/deep_links.dart';
import 'package:carden/state/coop/coop_controller.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
  await tester.pump(const Duration(milliseconds: 16));
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<Map<String, dynamic>> bot(String path, {bool get = false}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final uri = Uri.parse('http://127.0.0.1:8787$path');
    final req = get ? await client.getUrl(uri) : await client.postUrl(uri);
    final res = await req.close().timeout(const Duration(seconds: 60));
    return jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('another player takes the card under this player\'s finger', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    store.onboarded = true;
    await FirstSteps.skipFor(store);
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(overrides: [localStoreProvider.overrideWithValue(store)], child: const CardenApp()));
    await settle(tester, 3000);
    final c = ProviderScope.containerOf(tester.element(find.byType(CardenApp)));
    final g = await bot('/game?cells=20');
    c.read(deepLinksProvider).show(AppLink.parse(Uri.parse('carden://join/${g['code']}'))!);
    for (var i = 0; i < 400 && !(c.read(coopProvider).playing && find.byType(BoardWidget).evaluate().isNotEmpty); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await bot('/liverows');
    await settle(tester, 2500);
    BoardWidget boardWidget() => tester.widget<BoardWidget>(find.byType(BoardWidget).first);
    List<int> board() => boardWidget().state.board.slots;

    // This player takes a loose card and starts moving it.
    final b = board();
    final x = b.firstWhere((k) => b[k] != k && b.indexOf(k) != k && !boardWidget().state.board.isLocked(b.indexOf(k)));
    final from = b.indexOf(x);
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(ValueKey('card-$x'))));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(4, 3));
      await tester.pump(const Duration(milliseconds: 16));
    }
    // The host puts the same card in its place (as a second player who grabbed it would).
    await bot('/move?changes=$x:${b[x]}:$x,$from:$x:${b[x]}');
    for (var i = 0; i < 300 && board()[x] != x; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(board()[x], x, reason: 'the host\'s move arrived');
    await tester.pump(const Duration(milliseconds: 120));
    await binding.takeScreenshot('race_00_card_taken');
    debugPrint('COOP_RACE word on screen: ${find.textContaining('this card').evaluate().map((e) => (e.widget as Text).data).toList()}');
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(4, 3));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settle(tester, 3000);
    await binding.takeScreenshot('race_01_after_letting_go');

    // What is left: a card drawn away from its slot.
    final now = boardWidget().state.board;
    final origin = tester.getTopLeft(find.byType(BoardWidget).first);
    final size = Size(boardWidget().width, boardWidget().height);
    final floating = <int>[];
    for (var slot = 0; slot < now.cells; slot++) {
      final f = find.byKey(ValueKey('card-${now.slots[slot]}'));
      if (f.evaluate().isEmpty) continue;
      if ((tester.getTopLeft(f) - origin - now.tiling.cellBounds(slot, size).topLeft).distance > 1) floating.add(now.slots[slot]);
    }
    debugPrint('COOP_RACE floating after the other player took the card: $floating (card under the finger was $x in slot $from; slot $from now holds ${now.slots[from]})');
    final live = (await bot('/live', get: true))['heard'] as List;
    final mine = live.where((h) => h['userId'] == c.read(coopProvider).me).map((h) => h['phase']).toList();
    debugPrint('COOP_RACE this player\'s live states the host heard: $mine');
    await bot('/quit');
    expect(floating, isEmpty);
    expect(mine.last, isNot('drag'), reason: 'the drag was reported as over');
  });
}
