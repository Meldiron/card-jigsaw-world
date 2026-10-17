// Play together, live picks and drags (docs/multiplayer.md, "Live picks and drags"), on the live
// backend: the app on the simulator is a guest and tools/dev/coop_bot.mjs is the host. Through the
// real game screen: the host's pick shows at once and goes at once; the host's drag glides across
// this board (a sequence of screenshots mid-path) and settles into its slot with the move; a
// cancelled drag goes back; this player's own pick and drag reach the host; on a giant board the
// others' drags show on the off-screen pointer and the map. Every delay is measured and printed
// (`COOP_TIMING`): the simulator and the bot share the Mac's clock.
//
//   node tools/dev/coop_bot.mjs &
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart --target=integration_test/coop_drag_test.dart -d <simulator>
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

String stats(List<int> ms) {
  if (ms.isEmpty) return 'none';
  final v = [...ms]..sort();
  return 'n ${v.length} min ${v.first} p50 ${v[v.length ~/ 2]} p90 ${v[(v.length * 0.9).floor().clamp(0, v.length - 1)]} max ${v.last} ms';
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump();
    await binding.takeScreenshot(name);
  }

  Future<int?> until(WidgetTester tester, bool Function() done, {int seconds = 20}) async {
    final start = DateTime.now();
    final end = start.add(Duration(seconds: seconds));
    while (!done() && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    return done() ? DateTime.now().millisecondsSinceEpoch : null;
  }

  testWidgets('play together live: picks and drags both ways, with their delays', (tester) async {
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
    final coop = c.read(coopProvider.notifier);
    List<int> board() => tester.widget<BoardWidget>(find.byType(BoardWidget).first).state.board.slots;
    bool boardOn() => find.byType(BoardWidget).evaluate().isNotEmpty;
    Future<void> join(String code) async {
      c.read(deepLinksProvider).show(AppLink.parse(Uri.parse('carden://join/$code'))!);
      expect(await until(tester, () => s().playing && s().game!.code == code, seconds: 40), isNotNull, reason: 'joined');
      expect(await until(tester, boardOn, seconds: 40), isNotNull);
      // The api function makes every player's live row on join; until it is deployed with them, the
      // bot makes them as it would.
      await bot('/liverows');
      await settle(tester, 2000);
    }

    debugPrint('COOP_STEP 1');
    // 1. Join the bot's game.
    var g = await bot('/game?cells=20');
    await join(g['code'] as String);
    final me = s().me!;

    debugPrint('COOP_STEP 2');
    // 2. The host picks cards with taps: each shows in their colour at once, and goes at once.
    final pickDelays = <int>[], unpickDelays = <int>[];
    final loose = [for (var i = 0; i < board().length; i++) if (board()[i] != i) board()[i]];
    for (final card in loose.take(5)) {
      final sent = await bot('/pick?card=$card');
      final seen = await until(tester, () => s().marks.held[card] != null, seconds: 10);
      expect(seen, isNotNull, reason: 'the pick of $card shows');
      pickDelays.add(seen! - (sent['sentAt'] as int));
      if (card == loose.first) await shot(tester, 'live_01_host_pick');
      final put = await bot('/pick?card=-1');
      final gone = await until(tester, () => s().marks.held[card] == null, seconds: 10);
      expect(gone, isNotNull, reason: 'the put-down of $card shows');
      unpickDelays.add(gone! - (put['sentAt'] as int));
      await settle(tester, 300);
    }
    debugPrint('COOP_TIMING host pick -> shown here: ${stats(pickDelays)}');
    debugPrint('COOP_TIMING host put-down -> gone here: ${stats(unpickDelays)}');

    debugPrint('COOP_STEP 3');
    // 3. The host drags a card across the board: it glides here, then settles into its slot.
    var b = board();
    final card = b.firstWhere((k) => b[k] != k && b.indexOf(k) > 11);
    final target = card; // its own place
    final started = await bot('/drag?card=$card&to=$target&ms=2600&rate=5&wait=0');
    final firstSeen = await until(tester, () => find.byKey(ValueKey('coop-drag-$card')).evaluate().isNotEmpty, seconds: 10);
    expect(firstSeen, isNotNull, reason: 'the dragged card is drawn where their finger is');
    debugPrint('COOP_TIMING host drag start -> lifted here: ${firstSeen! - (started['startedAt'] as int)} ms');
    final path = <Offset>[];
    for (var i = 0; i < 5; i++) {
      await settle(tester, 380);
      final f = find.byKey(ValueKey('card-$card'));
      if (f.evaluate().isNotEmpty) path.add(tester.getCenter(f));
      await shot(tester, 'live_02_host_drag_${i + 1}');
    }
    final settled = await until(tester, () => board()[target] == card && find.byKey(ValueKey('coop-drag-$card')).evaluate().isEmpty, seconds: 15);
    expect(settled, isNotNull, reason: 'the move settles the card into its slot');
    await settle(tester, 500);
    await shot(tester, 'live_03_host_drop_settled');
    final drag = (await bot('/live', get: true))['lastDrag'] as Map<String, dynamic>?;
    if (drag != null) debugPrint('COOP_NOTE screenshot drag: ${(drag['sent'] as List).length} updates sent over 2.6 s');
    debugPrint('COOP_NOTE drag path on screen: ${path.map((p) => '(${p.dx.round()},${p.dy.round()})').join(' ')}');
    expect(path.toSet().length, greaterThanOrEqualTo(3), reason: 'it moved across the board, not in one jump');

    // 3b. The same without screenshots, timed from the host's own sends: lifted, landed.
    final lifts = <int>[], lands = <int>[];
    for (var round = 0; round < 3; round++) {
      b = board();
      final k = b.firstWhere((x) => b[x] != x && b.indexOf(x) != x);
      await bot('/drag?card=$k&to=$k&ms=1000&rate=5&wait=0');
      final lifted = await until(tester, () => find.byKey(ValueKey('coop-drag-$k')).evaluate().isNotEmpty, seconds: 10);
      final landed = await until(tester, () => board()[k] == k && find.byKey(ValueKey('coop-drag-$k')).evaluate().isEmpty, seconds: 15);
      await settle(tester, 1200);
      final last = (await bot('/live', get: true))['lastDrag'] as Map<String, dynamic>;
      final first = ((last['sent'] as List).first as Map<String, dynamic>)['sentAt'] as int;
      if (lifted != null) lifts.add(lifted - first);
      if (landed != null) lands.add(landed - (last['moveAt'] as int));
    }
    debugPrint('COOP_TIMING host drag start (first update sent) -> lifted here: ${stats(lifts)}');
    debugPrint('COOP_TIMING host move sent -> landed here: ${stats(lands)}');

    debugPrint('COOP_STEP 4');
    // 4. A drag the host cancels goes back where it was.
    b = board();
    final other = b.firstWhere((k) => b[k] != k);
    final home = b.indexOf(other);
    final otherFrom = tester.getTopLeft(find.byKey(ValueKey('card-$other')));
    await bot('/drag?card=$other&to=${(home + 7) % b.length}&ms=1200&rate=5&end=cancel&wait=0');
    expect(await until(tester, () => find.byKey(ValueKey('coop-drag-$other')).evaluate().isNotEmpty, seconds: 10), isNotNull);
    await settle(tester, 600);
    await shot(tester, 'live_04_host_drag_to_cancel');
    expect(await until(tester, () => find.byKey(ValueKey('coop-drag-$other')).evaluate().isEmpty, seconds: 10), isNotNull);
    await settle(tester, 800);
    expect(tester.getTopLeft(find.byKey(ValueKey('card-$other'))), otherFrom, reason: 'back in its slot');
    expect(board().indexOf(other), home);

    debugPrint('COOP_STEP 5');
    // 5. This player's pick and put-down reach the host.
    b = board();
    final mine = b.firstWhere((k) => b[k] != k);
    final heardBefore = ((await bot('/live', get: true))['heard'] as List).length;
    await tester.tapAt(tester.getCenter(find.byKey(ValueKey('card-$mine'))));
    await settle(tester, 1200);
    await tester.tapAt(tester.getCenter(find.byKey(ValueKey('card-$mine'))));
    await settle(tester, 1500);
    final heard = ((await bot('/live', get: true))['heard'] as List).cast<Map<String, dynamic>>().skip(heardBefore).where((h) => h['userId'] == me).toList();
    final pick = heard.where((h) => h['phase'] == 'pick' && h['card'] == mine).toList();
    final put = heard.where((h) => h['phase'] == '').toList();
    expect(pick, isNotEmpty, reason: 'the host heard the pick');
    expect(put, isNotEmpty, reason: 'the host heard the put-down');
    debugPrint('COOP_TIMING my pick -> heard by the host: ${stats([for (final h in [...pick, ...put]) (h['heardAt'] as int) - (h['seq'] as int)])}');

    debugPrint('COOP_STEP 6');
    // 6. This player's drag: positions reach the host while the finger moves, then the drop and the move.
    b = board();
    final dragged = b.firstWhere((k) => b[k] != k && b.indexOf(k) < 8);
    final from = tester.getCenter(find.byKey(ValueKey('card-$dragged')));
    final to = tester.getCenter(find.byKey(ValueKey('card-${b[dragged]}')));
    final mark = ((await bot('/live', get: true))['heard'] as List).length;
    final gesture = await tester.startGesture(from);
    const steps = 90; // about 1.5 s
    for (var i = 1; i <= steps; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / steps)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settle(tester, 2500);
    final mineHeard = ((await bot('/live', get: true))['heard'] as List).cast<Map<String, dynamic>>().skip(mark).where((h) => h['userId'] == me).toList();
    final positions = mineHeard.where((h) => h['phase'] == 'drag').toList();
    debugPrint('COOP_TIMING my drag -> heard by the host: ${stats([for (final h in mineHeard) (h['heardAt'] as int) - (h['seq'] as int)])}; positions ${positions.length} over ~1.5 s; phases ${mineHeard.map((h) => h['phase']).join(',')}');
    expect(positions.length, greaterThanOrEqualTo(4), reason: 'a steady stream while the finger moves');
    expect(mineHeard.last['phase'], 'drop');
    final moves = ((await bot('/moves', get: true))['moves'] as List).where((m) => m['userId'] == me).toList();
    expect(moves, isNotEmpty, reason: 'the move followed the drop');

    debugPrint('COOP_STEP 7');
    // 7. A giant board, zoomed in: the host's drag far away shows on the off-screen pointer and the map.
    await bot('/end');
    expect(await until(tester, () => find.text('Game ended').evaluate().isNotEmpty, seconds: 30), isNotNull);
    await tester.tap(find.text('Close').last);
    await settle(tester, 2500);
    g = await bot('/game?giant=1');
    await join(g['code'] as String);
    if (tester.widget<BoardWidget>(find.byType(BoardWidget).first).zoom != null) {
      await tester.tap(find.byKey(const ValueKey('zoom-in')));
      await settle(tester, 1500);
      b = board();
      final far = b.lastWhere((k) => b[k] != k && b.indexOf(k) > 80);
      await bot('/drag?card=$far&to=${b.indexOf(far) - 10}&ms=3000&rate=5&wait=0');
      expect(await until(tester, () => coop.liveTracks.hasGhosts, seconds: 10), isNotNull);
      await settle(tester, 1200);
      final initial = find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.endsWith('-drag'));
      debugPrint('COOP_NOTE giant off-screen pointer for the drag: ${initial.evaluate().length}');
      await shot(tester, 'live_05_giant_offscreen_drag');
      await settle(tester, 3000);
    }

    await bot('/quit');
  });
}
