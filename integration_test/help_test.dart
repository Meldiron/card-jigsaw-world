// Settings > Help on the real app (live Appwrite backend, a QA guest): Contact support (the
// simulator has no mail app, so the address is copied) and Send feedback, whose row lands in the
// `feedback` table. Keep the player to look at the row, then purge it:
//
//   QA_KEEP=1 tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/help_test.dart -d <simulator>
//   python3 tools/dev/feedback.py            the message, from a [QA] player
//   python3 tools/dev/purge_test_players.py purge --apply
import 'package:card_jigsaw_world/app.dart';
import 'package:card_jigsaw_world/core/sfx.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
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

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> shot(WidgetTester tester, String name, {int wait = 300}) async {
    if (wait > 0) await settle(tester, wait);
    await binding.takeScreenshot(name);
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  testWidgets('Settings > Help: Contact support and Send feedback', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(overrides: [localStoreProvider.overrideWithValue(store)], child: const CardJigsawApp()));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 4000);

    // Profile > Settings > Help.
    await tapText(tester, 'Profile', ms: 2500);
    await tester.tap(find.byIcon(CupertinoIcons.gear_alt_fill).first, warnIfMissed: false);
    await settle(tester, 2000);
    await tester.dragUntilVisible(find.byKey(const ValueKey('settings-feedback')), find.byType(Scrollable).first, const Offset(0, -250));
    await settle(tester, 800);
    await shot(tester, 'help_01_settings');

    // Contact support: no mail app on the simulator, so the address is copied.
    await tester.tap(find.byKey(const ValueKey('settings-support')), warnIfMissed: false);
    await settle(tester, 1500);
    expect(find.text('Email address copied: support@almostapps.eu'), findsOneWidget);
    expect((await Clipboard.getData('text/plain'))?.text, 'support@almostapps.eu');
    await shot(tester, 'help_02_support_copied', wait: 0);
    await settle(tester, 2500);

    // Send feedback.
    await tester.tap(find.byKey(const ValueKey('settings-feedback')), warnIfMissed: false);
    await settle(tester, 1500);
    expect(find.byKey(const ValueKey('feedback-field')), findsOneWidget);
    await shot(tester, 'help_03_feedback_empty');
    await tester.enterText(find.byKey(const ValueKey('feedback-field')), 'QA run: the feedback sheet works. More Giant packs, please.');
    await settle(tester, 800);
    await shot(tester, 'help_04_feedback_written');
    await tester.tap(find.byKey(const ValueKey('feedback-send')), warnIfMissed: false);
    await settle(tester, 2500);
    expect(find.byKey(const ValueKey('feedback-field')), findsNothing, reason: 'the sheet closes once sent');
    expect(find.text('Thank you. Your feedback was sent.'), findsOneWidget);
    await shot(tester, 'help_05_feedback_sent', wait: 0);
    await settle(tester, 2500);
  });
}
