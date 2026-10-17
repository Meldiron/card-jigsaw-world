// An invite link opens the game, on the live backend (docs/multiplayer.md, "Invite links"): the app on
// the simulator is a fresh install, tools/dev/coop_bot.mjs hosts a game, and the shared link,
// https://join.carden.page/<code>, reaches the app the way iOS hands it a universal link (the
// `pushRouteInformation` message of `flutter/navigation`, FlutterDeepLinkingEnabled). The app joins
// and shows the shared board; the link the app itself would share for the game is the same address.
//
//   node tools/dev/coop_bot.mjs &
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart --target=integration_test/invite_link_test.dart -d <simulator>
import 'dart:convert';
import 'dart:io';

import 'package:carden/app.dart';
import 'package:carden/core/app_links.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/features/game/game_screen.dart';
import 'package:carden/state/coop/coop_controller.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  GameScreen.dealPreview = false;

  Future<bool> until(WidgetTester tester, bool Function() done, {int seconds = 20}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (!done() && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    return done();
  }

  testWidgets('the shared link https://join.carden.page/<code> opens the game in the app', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(overrides: [localStoreProvider.overrideWithValue(store)], child: const CardenApp()));
    await settle(tester, 2500);
    final c = ProviderScope.containerOf(tester.element(find.byType(CardenApp)));
    CoopState s() => c.read(coopProvider);
    try {
      final g = await bot('/game?cells=20');
      final code = g['code'] as String;
      final link = AppLink.joinUrl(code).toString();
      expect(link, 'https://join.carden.page/$code');
      debugPrint('INVITE_LINK $link');
      await settle(tester, 600);
      await binding.takeScreenshot('invite_00_welcome');

      // What iOS sends Flutter for a universal link the app claims (applinks:join.carden.page).
      const codec = JSONMethodCodec();
      await binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation',
        codec.encodeMethodCall(MethodCall('pushRouteInformation', {'location': link, 'state': null})),
        (_) {},
      );
      expect(await until(tester, () => s().playing && s().game!.code == code, seconds: 40), isTrue, reason: 'joined from the link');
      expect(await until(tester, () => find.byType(BoardWidget).evaluate().isNotEmpty, seconds: 40), isTrue, reason: 'the shared board is on screen');
      await settle(tester, 1500);
      expect(s().isHost, isFalse);
      expect(find.byKey(const ValueKey('coop-players-chip')), findsOneWidget);
      await settle(tester, 600);
      await binding.takeScreenshot('invite_01_joined_from_link');
      debugPrint('INVITE_JOINED ${s().game!.players.where((p) => p.isNotEmpty).length} players');
    } finally {
      try {
        await bot('/quit');
      } catch (_) {}
    }
  });
}
