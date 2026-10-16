// Social > Inbox on the real app (live Appwrite, a QA guest). The messages come from outside the
// app, as in real life: while this test waits on the inbox, send some to its guest with
//   python3 tools/dev/inbox.py send --qa --subject "Welcome to Carden" --body "..." --coins 500 --tickets 2 \
//     --cta-label "Open Impressionists" --cta-link /library/pack/pack-impressionists --yes
//   python3 tools/dev/inbox.py send --qa --subject "How is Carden so far?" --body "..." \
//     --cta-label "Send feedback" --cta-link /feedback --yes
// It then opens the welcome message, claims its gift (the button turns to Close), follows the
// feedback button, and deletes a message.
//
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart --target=integration_test/inbox_test.dart -d <simulator>
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/state/inbox.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/material.dart';
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

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, 400);
    await binding.takeScreenshot(name);
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  testWidgets('inbox: list, open, claim, button, delete', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(overrides: [localStoreProvider.overrideWithValue(store)], child: const CardenApp()));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 4000);
    final c = ProviderScope.containerOf(tester.element(find.byType(CardenApp)));
    debugPrint('INBOX_QA_USER ${c.read(profileProvider).value?.userId}');

    await tapText(tester, 'Social', ms: 2500);
    await tapText(tester, 'Inbox', ms: 2000);
    await shot(tester, 'ib_00_empty');

    // Wait for the messages sent from outside (up to 4 minutes), reading the inbox again as a pull would.
    for (var i = 0; i < 80 && find.text('Welcome to Carden').evaluate().isEmpty; i++) {
      c.invalidate(inboxMessagesProvider);
      await settle(tester, 3000);
    }
    expect(find.text('Welcome to Carden'), findsWidgets);
    await settle(tester, 2000);
    expect(c.read(inboxUnseenProvider), isTrue, reason: 'new messages: the Social tab has its dot');
    await shot(tester, 'ib_01_list');

    // Open the welcome message: Claim, then Close.
    final coins = c.read(profileProvider).value!.coins;
    await tapText(tester, 'Welcome to Carden', ms: 1500);
    expect(find.byKey(const ValueKey('message-claim')), findsOneWidget);
    await shot(tester, 'ib_02_message');
    await tester.tap(find.byKey(const ValueKey('message-claim')), warnIfMissed: false);
    await settle(tester, 2500);
    expect(find.byKey(const ValueKey('message-close')), findsOneWidget, reason: 'claimed: the button says Close');
    expect(c.read(profileProvider).value!.coins, coins + 500);
    await shot(tester, 'ib_03_claimed');
    await tester.tap(find.byKey(const ValueKey('message-close')), warnIfMissed: false);
    await settle(tester, 1500);

    // The feedback message's button opens Send feedback.
    if (find.text('How is Carden so far?').evaluate().isNotEmpty) {
      await tapText(tester, 'How is Carden so far?', ms: 1500);
      await tester.tap(find.byKey(const ValueKey('message-cta')), warnIfMissed: false);
      await settle(tester, 2500);
      expect(find.byKey(const ValueKey('feedback-field')), findsOneWidget, reason: 'the button opened the feedback sheet');
      await shot(tester, 'ib_04_feedback');
      Navigator.of(tester.element(find.byKey(const ValueKey('feedback-field')))).pop();
      await settle(tester, 1500);
    }

    // Delete the welcome message (asks first).
    await tapText(tester, 'Welcome to Carden', ms: 1500);
    await tester.tap(find.byKey(const ValueKey('message-delete')), warnIfMissed: false);
    await settle(tester, 1200);
    await tapText(tester, 'Delete', ms: 2000);
    expect(find.text('Welcome to Carden'), findsNothing);
    await shot(tester, 'ib_05_deleted');
  });
}
