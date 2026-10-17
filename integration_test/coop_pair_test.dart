// Play together between two simulators, on the live backend (docs/multiplayer.md): the same suite runs
// as the host on one simulator and as the guest on another, and they hand codes and boards to each
// other through tools/dev/coop_bot.mjs's relay. Both are the real app: the host starts the game from the
// pause sheet, the guest (a fresh install) joins by the link, each sees the other's moves and held card,
// the host drags a card slowly with the finger and the guest sees it travel (live drags), the host
// finishes (the guest gets its rewards: it locked a card), Next puzzle moves the guest, and the host
// ends the game. Delays between the two simulators (one Mac clock) are printed as `COOP_TIMING`.
//
//   node tools/dev/coop_bot.mjs &
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart --target=integration_test/coop_pair_test.dart \
//     -d <first simulator> --dart-define=CJW_COOP_ROLE=host
//   # once the host's log says "COOP_PAIR waiting for the guest":
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart --target=integration_test/coop_pair_test.dart \
//     -d <second simulator> --dart-define=CJW_COOP_ROLE=guest
import 'dart:convert';
import 'dart:io';

import 'package:carden/app.dart';
import 'package:carden/core/app_links.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/features/game/game_screen.dart';
import 'package:carden/features/links/deep_links.dart';
import 'package:carden/router.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/coop/coop_controller.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/widgets/icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

const role = String.fromEnvironment('CJW_COOP_ROLE', defaultValue: 'host');

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
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final uri = Uri.parse('http://127.0.0.1:8787$path');
    final req = get ? await client.getUrl(uri) : await client.postUrl(uri);
    final res = await req.close().timeout(const Duration(seconds: 30));
    return jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<void> relaySet(String key, String value) => bot('/relay?key=pair-$key&value=${Uri.encodeQueryComponent(value)}');
Future<String?> relayGet(String key) async => (await bot('/relay?key=pair-$key', get: true))['value'] as String?;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  // Boards here are played the moment they show: no picture before the deal (GameScreen.dealPreview).
  GameScreen.dealPreview = false;
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

  /// Waits for the other simulator to hand over [key].
  Future<String> wait(WidgetTester tester, String key, {int seconds = 120}) async {
    debugPrint('COOP_PAIR waiting for $key');
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(end)) {
      final v = await relayGet(key);
      if (v != null && v.isNotEmpty) return v;
      await settle(tester, 700);
    }
    fail('the other simulator did not send $key');
  }

  testWidgets('play together between two simulators ($role)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    if (role == 'host') {
      store.onboarded = true;
      await FirstSteps.skipFor(store);
    }
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

    /// One misplaced card to its place (a lock), by two taps.
    Future<void> placeOne({Set<int> skip = const {}}) async {
      final b = board();
      for (final k in b.where((k) => b[k] != k && b.indexOf(k) != k && !skip.contains(k)).toList()) {
        await tapCard(k);
        await tapCard(b[k]);
        if (await until(tester, () => !listEquals(board(), b), seconds: 3)) return;
      }
    }

    String encode(List<int> b) => b.join(',');

    /// Both simulators grab [card] at the same moment ([at], ms on the Mac's clock, which both share)
    /// and drag it towards its place for about 2.5 s. First grab wins: the other's drag is given up,
    /// the card slides back and a word says who took it. Returns whether this device gave way.
    Future<bool> grabAt(int card, int at, String role) async {
      while (DateTime.now().millisecondsSinceEpoch < at) {
        await tester.pump(const Duration(milliseconds: 4));
      }
      final from = tester.getCenter(find.byKey(ValueKey('card-$card')));
      final b = board();
      final to = tester.getCenter(find.byKey(ValueKey('card-${b[card]}')));
      final gesture = await tester.startGesture(from);
      var lost = false;
      for (var i = 1; i <= 150; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / 150)!);
        await tester.pump(const Duration(milliseconds: 16));
        if (!lost && find.textContaining('took it first').evaluate().isNotEmpty) {
          lost = true;
          debugPrint('COOP_TIMING same card: $role gave way ${DateTime.now().millisecondsSinceEpoch - at} ms after both grabbed');
          await binding.takeScreenshot('pair_${role}_same_card_lost_1');
          await settle(tester, 250);
          await binding.takeScreenshot('pair_${role}_same_card_lost_2');
        }
      }
      await gesture.up();
      await settle(tester, 1500);
      if (!lost) await binding.takeScreenshot('pair_${role}_same_card_won');
      return lost;
    }
    List<int> decode(String v) => [for (final x in v.split(',')) int.parse(x)];

    if (role == 'host') {
      for (final k in ['code', 'h-moved', 'g-moved', 'h-holds', 'g-saw-hold', 'h-drag', 'h-dragged', 'g-saw-drag', 'same', 'h-same', 'g-same', 'h-done', 'g-finish', 'h-next', 'g-next', 'h-ended', 'g-ended']) {
        await relaySet(k, '');
      }
      final pictures = (await c.read(allPuzzlesProvider.future)).where((p) => p.packId == 'pack-owls').toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      router.push('/game/${pictures.first.id}/cards-4x5t3');
      expect(await until(tester, boardOn, seconds: 60), isTrue);
      await settle(tester, 2000);

      // 1. Play together: the code goes to the guest's simulator.
      await tester.tap(find.byIcon(AppIcons.pauseFill));
      await settle(tester, 1200);
      await tester.tap(find.byKey(const ValueKey('pause-play-together')));
      expect(await until(tester, () => recorder.shared.isNotEmpty, seconds: 60), isTrue);
      final code = RegExp(r'play\.carden\.page/join/([A-Z0-9]{8})').firstMatch(recorder.shared.single)!.group(1)!;
      await relaySet('code', '$code@${DateTime.now().millisecondsSinceEpoch}');
      debugPrint('COOP_PAIR waiting for the guest');
      expect(await until(tester, () => (s().game?.playerIds.length ?? 0) == 2, seconds: 900), isTrue, reason: 'the guest joined');
      // The api function makes every player's live row on create and join; until it is deployed with
      // them, the bot makes them as it would.
      await bot('/liverows?game=${s().game!.id}');
      await settle(tester, 4000);
      await shot(tester, 'pair_h01_guest_joined', 100);

      // 2. A move here, then the guest's move arrives.
      await placeOne();
      await settle(tester, 1500);
      await relaySet('h-moved', encode(board()));
      final guestBoard = decode(await wait(tester, 'g-moved'));
      expect(await until(tester, () => listEquals(board(), guestBoard), seconds: 30), isTrue, reason: 'the guest\'s move is here');
      await shot(tester, 'pair_h02_guest_move', 300);

      // 3. A card held here shows there.
      final b = board();
      final held = b.firstWhere((k) => b[k] != k);
      await tapCard(held);
      await settle(tester, 800);
      await relaySet('h-holds', '$held@${DateTime.now().millisecondsSinceEpoch}');
      await wait(tester, 'g-saw-hold');
      await tapCard(held);
      await settle(tester, 800);

      // 3b. A slow drag with the finger (about 3 s): the guest sees the card travel, then land.
      final bd = board();
      final dragged = bd.firstWhere((k) => bd[k] != k && bd.indexOf(k) != k && bd.indexOf(k) < bd.length ~/ 2);
      final from = tester.getCenter(find.byKey(ValueKey('card-$dragged')));
      final to = tester.getCenter(find.byKey(ValueKey('card-${bd[dragged]}')));
      await relaySet('h-drag', '$dragged@${DateTime.now().millisecondsSinceEpoch}');
      final gesture = await tester.startGesture(from);
      for (var i = 1; i <= 180; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / 180)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await relaySet('h-dragged', '${DateTime.now().millisecondsSinceEpoch}');
      await settle(tester, 1500);
      await wait(tester, 'g-saw-drag');

      // 3c. Both grab the same card at the same moment: one keeps it, the other gives way.
      final bs = board();
      final same = bs.firstWhere((k) => bs[k] != k && bs.indexOf(k) != k);
      final at = DateTime.now().millisecondsSinceEpoch + 5000;
      await relaySet('same', '$same@$at');
      final hostLost = await grabAt(same, at, 'h');
      await relaySet('h-same', hostLost ? 'lost' : 'won');
      final guestSaid = await wait(tester, 'g-same');
      debugPrint('COOP_NOTE same card: host ${hostLost ? 'lost' : 'won'}, guest $guestSaid');
      expect({hostLost ? 'lost' : 'won', guestSaid}, {'lost', 'won'}, reason: 'exactly one player keeps the card');
      await settle(tester, 1500);

      // 4. The host finishes: the normal completion card here, the guest's finish there.
      for (var guard = 0; guard < 40 && find.text('Next puzzle').evaluate().isEmpty; guard++) {
        if (!boardOn() || tester.widget<BoardWidget>(find.byType(BoardWidget).first).state.board.isSolved) break;
        await placeOne();
      }
      expect(await until(tester, () => find.text('Next puzzle').evaluate().isNotEmpty, seconds: 40), isTrue);
      await shot(tester, 'pair_h03_completion', 1500);
      await relaySet('h-done', '1');
      await wait(tester, 'g-finish');

      // 5. Next puzzle: the guest is moved onto it.
      await tester.tap(find.text('Next puzzle').last);
      expect(await until(tester, () => s().game?.board == 2, seconds: 60), isTrue);
      expect(await until(tester, boardOn, seconds: 30), isTrue);
      await settle(tester, 2500);
      await relaySet('h-next', encode(board()));
      await wait(tester, 'g-next');
      await shot(tester, 'pair_h04_next_board', 300);

      // 6. End game for everyone.
      await tester.tap(find.byIcon(AppIcons.pauseFill));
      await settle(tester, 1200);
      await tester.tap(find.byKey(const ValueKey('pause-end-game')));
      await settle(tester, 1000);
      await tester.tap(find.text('End game').last);
      expect(await until(tester, () => !s().playing, seconds: 30), isTrue);
      await relaySet('h-ended', '1');
      await wait(tester, 'g-ended');
      await shot(tester, 'pair_h05_ended', 300);
      return;
    }

    // The guest: a fresh install opens the link the host shared.
    final sent = (await wait(tester, 'code', seconds: 600)).split('@');
    expect(DateTime.now().millisecondsSinceEpoch - int.parse(sent[1]), lessThan(20 * 60 * 1000), reason: 'a code of this run');
    c.read(deepLinksProvider).show(AppLink.parse(Uri.parse('https://play.carden.page/join/${sent[0]}'))!);
    expect(await until(tester, () => s().playing, seconds: 60), isTrue, reason: 'joined');
    expect(await until(tester, boardOn, seconds: 40), isTrue);
    await settle(tester, 2500);
    await shot(tester, 'pair_g01_joined', 100);

    final hostBoard = decode(await wait(tester, 'h-moved'));
    expect(await until(tester, () => listEquals(board(), hostBoard), seconds: 30), isTrue, reason: 'the host\'s move is here');
    await shot(tester, 'pair_g02_host_moved', 300);
    await placeOne();
    await settle(tester, 1500);
    expect(s().placedACard, isTrue);
    await relaySet('g-moved', encode(board()));

    final hold = (await wait(tester, 'h-holds')).split('@');
    final held = int.parse(hold[0]);
    expect(await until(tester, () => find.byKey(ValueKey('coop-mark-$held')).evaluate().isNotEmpty, seconds: 30), isTrue, reason: 'the host\'s held card');
    debugPrint('COOP_TIMING host pick -> seen on the guest (incl. the relay poll): ${DateTime.now().millisecondsSinceEpoch - int.parse(hold[1])} ms');
    await shot(tester, 'pair_g03_host_holds', 300);
    await relaySet('g-saw-hold', '1');

    // The host's finger drags a card: it travels here (screens mid-path), then lands.
    final dragInfo = (await wait(tester, 'h-drag')).split('@');
    final dragged = int.parse(dragInfo[0]);
    expect(await until(tester, () => find.byKey(ValueKey('coop-drag-$dragged')).evaluate().isNotEmpty, seconds: 20), isTrue, reason: 'the host\'s dragged card');
    debugPrint('COOP_TIMING host drag start -> lifted on the guest (incl. the relay poll): ${DateTime.now().millisecondsSinceEpoch - int.parse(dragInfo[1])} ms');
    final travel = <Offset>[];
    for (var i = 0; i < 4; i++) {
      await settle(tester, 450);
      travel.add(tester.getCenter(find.byKey(ValueKey('card-$dragged'))));
      await shot(tester, 'pair_g03b_host_drag_${i + 1}', 0);
    }
    debugPrint('COOP_NOTE drag on the guest: ${travel.map((p) => '(${p.dx.round()},${p.dy.round()})').join(' ')}');
    expect(travel.toSet().length, greaterThanOrEqualTo(3), reason: 'it travelled');
    final dropped = int.parse(await wait(tester, 'h-dragged'));
    expect(await until(tester, () => board()[dragged] == dragged && find.byKey(ValueKey('coop-drag-$dragged')).evaluate().isEmpty, seconds: 20), isTrue, reason: 'it landed in its place');
    debugPrint('COOP_TIMING host drop -> landed on the guest: ${DateTime.now().millisecondsSinceEpoch - dropped} ms');
    await shot(tester, 'pair_g03c_host_drag_landed', 600);
    await relaySet('g-saw-drag', '1');

    // Both grab the same card at the same moment.
    final sameInfo = (await wait(tester, 'same')).split('@');
    final guestLost = await grabAt(int.parse(sameInfo[0]), int.parse(sameInfo[1]), 'g');
    await relaySet('g-same', guestLost ? 'lost' : 'won');
    await wait(tester, 'h-same');
    await settle(tester, 1500);

    await wait(tester, 'h-done', seconds: 300);
    expect(await until(tester, () => find.byKey(const ValueKey('coop-guest-finish')).evaluate().isNotEmpty, seconds: 40), isTrue);
    expect(await until(tester, () => find.textContaining('+').evaluate().length >= 2, seconds: 20), isTrue, reason: 'the guest\'s rewards');
    await shot(tester, 'pair_g04_finish', 800);
    await relaySet('g-finish', '1');

    final next = decode(await wait(tester, 'h-next'));
    expect(await until(tester, () => s().game?.board == 2 && boardOn() && listEquals(board(), next), seconds: 60), isTrue, reason: 'moved onto the next board');
    await shot(tester, 'pair_g05_next_board', 500);
    await relaySet('g-next', '1');

    await wait(tester, 'h-ended');
    expect(await until(tester, () => find.text('Game ended').evaluate().isNotEmpty, seconds: 30), isTrue);
    await shot(tester, 'pair_g06_ended', 300);
    await tester.tap(find.text('Close').last);
    await settle(tester, 2500);
    expect(router.state.uri.path, '/welcome', reason: 'a player who came in by the invite starts the welcome pages');
    await relaySet('g-ended', '1');
  });
}
