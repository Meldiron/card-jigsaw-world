// Play together between two simulators, on the live backend (docs/multiplayer.md): the same suite runs
// as the host on one simulator and as the guest on another, and they hand codes and boards to each
// other through tools/dev/coop_bot.mjs's relay. Both are the real app: the host starts the game from the
// pause sheet, the guest (a fresh install) joins by the link, each sees the other's moves and held card,
// the host finishes (the guest gets its rewards: it locked a card), Next puzzle moves the guest, and
// the host ends the game.
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
    List<int> decode(String v) => [for (final x in v.split(',')) int.parse(x)];

    if (role == 'host') {
      for (final k in ['code', 'h-moved', 'g-moved', 'h-holds', 'g-saw-hold', 'h-done', 'g-finish', 'h-next', 'g-next', 'h-ended', 'g-ended']) {
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
      await relaySet('h-holds', '$held');
      await wait(tester, 'g-saw-hold');
      await tapCard(held);
      await settle(tester, 800);

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

    final held = int.parse(await wait(tester, 'h-holds'));
    expect(await until(tester, () => find.byKey(ValueKey('coop-mark-$held')).evaluate().isNotEmpty, seconds: 30), isTrue, reason: 'the host\'s held card');
    await shot(tester, 'pair_g03_host_holds', 300);
    await relaySet('g-saw-hold', '1');

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
