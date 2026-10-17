// Friend gifts on the real app (live Appwrite, a QA guest; docs/friend-gifts.md). The friend comes
// from outside the app, as in real life. While this test waits (it prints GIFT_QA_USER <id> and the
// run id), make a QA friend in the same run and later let the friend send a gift:
//   python3 tools/dev/gift_qa.py friend --to <id> --run <run id>      (when it prints GIFT_QA_USER)
//   python3 tools/dev/gift_qa.py send --kind tickets                  (when it prints GIFT_QA_WAITING)
// It sends the friend 150 coins from the friend's profile, receives the friend's ticket in the
// inbox, opens it through the notification's link (`/inbox?message=<id>`, what a tap opens) and
// claims it. With GIFT_QA_LEAVE_UNCLAIMED=true it stops before Claim and leaves notifications
// unasked: the iOS prompt and the notification banner need a tap outside Flutter, which the
// RunnerUITests check in docs/friend-gifts.md ("Checking it") does on the same install.
//
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart --target=integration_test/friend_gifts_test.dart -d <simulator>
import 'dart:async';

import 'package:carden/app.dart';
import 'package:carden/core/app_links.dart';
import 'package:carden/core/qa.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/links/deep_links.dart';
import 'package:carden/router.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/friend_gifts.dart';
import 'package:carden/state/inbox.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/social.dart';
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

  testWidgets('friend gifts: send one, receive one, open it from its link, claim it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await FirstSteps.skipFor(store); // the whole app; integration_test/first_steps_test.dart plays the first steps
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(overrides: [localStoreProvider.overrideWithValue(store)], child: const CardenApp()));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 4000);
    final c = ProviderScope.containerOf(tester.element(find.byType(CardenApp)));
    final me = c.read(profileProvider).value!.userId;
    debugPrint('GIFT_QA_USER $me run ${QaRun.id}');

    // Wait for the friend made from outside (up to 4 minutes).
    await tapText(tester, 'Social', ms: 2500);
    await tapText(tester, 'Friends', ms: 2000);
    bool hasFriend() => (c.read(friendsProvider).value ?? const []).isNotEmpty;
    for (var i = 0; i < 80 && !hasFriend(); i++) {
      c.invalidate(friendsProvider);
      await settle(tester, 3000);
    }
    expect(hasFriend(), isTrue, reason: 'gift_qa.py friend made a friend');
    final friend = c.read(friendsProvider).value!.first;
    await settle(tester, 1500);
    await tapText(tester, friend.name, ms: 3000);

    // Send a gift: the action sheet, 150 coins, then "Next gift tomorrow".
    expect(find.byKey(const ValueKey('gift-send')), findsOneWidget);
    await shot(tester, 'gift_01_profile');
    await tester.tap(find.byKey(const ValueKey('gift-send')), warnIfMissed: false);
    await settle(tester, 1200);
    expect(find.byKey(const ValueKey('gift-tickets')), findsOneWidget);
    await shot(tester, 'gift_02_choose');
    await tester.tap(find.byKey(const ValueKey('gift-coins')), warnIfMissed: false);
    await settle(tester, 300);
    for (var i = 0; i < 30 && find.byKey(const ValueKey('gift-sent')).evaluate().isEmpty; i++) {
      await settle(tester, 500);
    }
    expect(find.byKey(const ValueKey('gift-sent')), findsOneWidget, reason: 'the button now reads Next gift tomorrow');
    expect(find.text('Next gift tomorrow'), findsOneWidget);
    // The first gift asks once about gift notifications. Not now: the iOS prompt cannot be tapped
    // here (and a quiet yes would answer it for the RunnerUITests check).
    expect(find.text('Know when a gift arrives?'), findsOneWidget);
    await binding.takeScreenshot('gift_03_sent');
    await tapText(tester, 'Not now');
    // A second gift the same day is refused by the server too.
    final again = await c.read(friendGiftRepositoryProvider).send(friend.friendId, GiftKind.tickets);
    expect((again.ok, again.error), (false, 'already'));

    // Back to the inbox; the friend sends a ticket, which arrives while the game is open.
    c.read(routerProvider).pop();
    await settle(tester, 1500);
    await tapText(tester, 'Inbox', ms: 2000);
    final tickets = c.read(profileProvider).value!.tickets;
    debugPrint('GIFT_QA_WAITING');
    InboxItem? gift() => c.read(inboxProvider).where((i) => i.message.fromUserId == friend.friendId).firstOrNull;
    for (var i = 0; i < 240 && gift() == null; i++) {
      await settle(tester, 1500);
      // Notifications are not allowed on this run: the inbox is read as a pull would.
      if (i % 4 == 3) c.invalidate(inboxMessagesProvider);
    }
    expect(gift(), isNotNull, reason: 'the gift reached the inbox');
    await settle(tester, 600);
    await binding.takeScreenshot('gift_04_inbox');
    final m = gift()!.message;
    expect((m.tickets, m.sender, m.expiresAt!.difference(m.sentAt).inHours), (1, friend.name, 24));

    // The notification's link opens the message (the tap's path from DeepLinks on). The link
    // finishes when its sheet closes, so it is not awaited.
    unawaited(c.read(deepLinksProvider).show(AppLink.parse(Uri.parse('/inbox?message=${m.id}'))!));
    await settle(tester, 3000);
    expect(find.byKey(ValueKey('message-sheet-${m.id}')), findsOneWidget);
    expect(find.text('A gift from ${friend.name}'), findsOneWidget);
    await shot(tester, 'gift_05_message');
    debugPrint('GIFT_QA_MESSAGE ${m.id}');
    if (const bool.fromEnvironment('GIFT_QA_LEAVE_UNCLAIMED')) return;
    await tester.tap(find.byKey(const ValueKey('message-claim')), warnIfMissed: false);
    await settle(tester, 2500);
    expect(find.byKey(const ValueKey('message-claimed')), findsOneWidget);
    expect(c.read(profileProvider).value!.tickets, tickets + 1);
    await shot(tester, 'gift_06_claimed');
  });
}
