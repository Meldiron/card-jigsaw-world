// Account deletion, the App Store rating prompt and event reminders, on the real app (live
// Appwrite backend).
//
// Run: tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//        --target=integration_test/account_review_test.dart -d <simulator>
//
// Prints for the host:
//   QA_MARK:review          the StoreKit rating prompt was requested: take a simulator screenshot
//   QA_DELETED_USER <id>    the deleted player: check from the host that the user, their rows and
//                           their photo are gone (tools/dev/cjw_admin.py)
// Integration runs ask iOS for quiet (provisional) notification permission, so no prompt is left
// on the simulator; the rating prompt belongs to the app and goes when the run ends.
import 'package:carden/app.dart';
import 'package:carden/core/image_files.dart';
import 'package:carden/core/reminders.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/data/repositories.dart';
import 'package:carden/features/onboarding/onboarding_screen.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/reminders.dart';
import 'package:carden/state/review_prompt.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
  // The app has infinite animations (shimmer, pulses), so pump for a fixed time.
  await tester.pump(const Duration(milliseconds: 50));
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

PuzzleProgress _done(String id, DateTime at, {int stars = 3}) => PuzzleProgress.fromRow('row-$id', {
      'userId': 'qa',
      'puzzleId': id,
      'gridSize': 16,
      'mode': 'cards',
      'completed': true,
      'stars': stars,
      'completedAt': at.toUtc().toIso8601String(),
    });

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, 400);
    await binding.takeScreenshot(name);
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200, bool last = false}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(last ? f.last : f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(CardenApp)));

  testWidgets('rating prompt, event reminders, delete account', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const CardenApp(),
    ));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 5000);
    // Today's gift writes the profile row, so the deletion has a profile to remove.
    if (find.text('Claim').evaluate().isNotEmpty) {
      await tapText(tester, 'Claim', ms: 1500);
      if (find.textContaining('Claim day').evaluate().isNotEmpty) {
        await tester.tap(find.textContaining('Claim day').first, warnIfMissed: false);
        await settle(tester, 2000);
      }
      await tester.tapAt(const Offset(200, 60));
      await settle(tester, 1500);
    }
    final c = container(tester);
    final userId = c.read(currentUserIdProvider)!;

    // A My Puzzles photo, so the deletion has a private file to remove.
    final picture = (await c.read(allPuzzlesProvider.future)).first;
    final photo = await c.read(uploadRepositoryProvider).upload(userId, bytes: await ImageFiles.bytes(picture.imageUrl), filename: 'photo.jpg', title: 'QA delete-account photo');
    debugPrint('QA_PHOTO ${photo.id} ${photo.fileId}');
    await shot(tester, 'ar_01_home');

    // Rating prompt: a 3-star solve as the sixth solved picture is a happy moment.
    ReviewPrompter.allowInIntegrationRuns = true;
    final now = DateTime.now();
    final earlier = {for (var i = 0; i < 5; i++) 'qa-$i': _done('qa-$i', now.subtract(Duration(days: i + 1)))};
    c.read(reviewPromptProvider).onProgress(earlier, {...earlier, 'qa-new': _done('qa-new', now)});
    await settle(tester, ReviewRules.delay.inMilliseconds + 2500);
    expect(store.getText('reviewAskedVersion'), isNotNull, reason: 'StoreKit was asked for the rating prompt');
    debugPrint('QA_MARK:review');
    await settle(tester, 6000);
    // A second happy moment in the same version does not ask again.
    final askedAt = store.getText('reviewAskedAt');
    c.read(reviewPromptProvider).onProgress({...earlier, 'qa-new': _done('qa-new', now)}, {...earlier, 'qa-new': _done('qa-new', now), 'qa-2nd': _done('qa-2nd', DateTime.now())});
    await settle(tester, ReviewRules.delay.inMilliseconds + 1500);
    expect(store.getText('reviewAskedAt'), askedAt);
    ReviewPrompter.allowInIntegrationRuns = false;

    // Settings > Daily reminders: event notes stay off (explicit opt-in), then New events turns
    // them on: notes for events at least five days away.
    await tapText(tester, 'Profile', ms: 2500);
    await tester.tap(find.byIcon(CupertinoIcons.gear_alt_fill).first, warnIfMissed: false);
    await settle(tester, 1500);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('settings-reminders')), matching: find.byType(CupertinoSwitch)), warnIfMissed: false);
    await settle(tester, 4000);
    expect(c.read(settingsProvider).reminders, isTrue);
    expect(find.byKey(const ValueKey('settings-event-reminders')), findsOneWidget);
    expect(c.read(eventRemindersProvider), isFalse, reason: 'promotional notes need their own yes');
    await c.read(remindersProvider).refresh();
    expect((await ReminderChannel.pending()).where((n) => '${n['id']}'.startsWith('event-')), isEmpty);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('settings-event-reminders')), matching: find.byType(CupertinoSwitch)), warnIfMissed: false);
    await settle(tester, 2500);
    expect(c.read(eventRemindersProvider), isTrue);
    await shot(tester, 'ar_02_settings_new_events');
    await c.read(remindersProvider).refresh();
    final pending = await ReminderChannel.pending();
    final events = pending.where((n) => '${n['id']}'.startsWith('event-')).toList();
    for (final n in events) {
      debugPrint('QA_EVENT_NOTE $n');
    }
    expect(events, isNotEmpty, reason: 'upcoming world-day events get a note');
    final soonest = events.map((n) => DateTime.fromMillisecondsSinceEpoch((n['at'] as num).toInt())).reduce((a, b) => a.isBefore(b) ? a : b);
    expect(soonest.isAfter(DateTime.now().add(eventReminderLead - const Duration(minutes: 1))), isTrue);
    // New events off: only the daily reminders stay.
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('settings-event-reminders')), matching: find.byType(CupertinoSwitch)), warnIfMissed: false);
    await settle(tester, 2500);
    await c.read(remindersProvider).refresh();
    expect((await ReminderChannel.pending()).where((n) => '${n['id']}'.startsWith('event-')), isEmpty);
    await tester.tap(find.byIcon(CupertinoIcons.back).first, warnIfMissed: false);
    await settle(tester, 1500);

    // Profile > Account > Delete account.
    final profileList = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
    await tester.dragUntilVisible(find.text('Account'), profileList, const Offset(0, -250));
    await settle(tester, 800);
    await tapText(tester, 'Account', ms: 2500);
    final accountList = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).last;
    await tester.dragUntilVisible(find.byKey(const ValueKey('account-delete')), accountList, const Offset(0, -300));
    await settle(tester, 1000);
    await shot(tester, 'ar_03_account_delete_button');
    await tester.tap(find.byKey(const ValueKey('account-delete')), warnIfMissed: false);
    await settle(tester, 2500);
    // The deletion sheet lists what goes; its red button asks a last time in an alert.
    expect(find.text('Delete your account?'), findsOneWidget);
    await shot(tester, 'ar_04_delete_sheet');
    await tester.tap(find.byKey(const ValueKey('account-delete-continue')), warnIfMissed: false);
    await settle(tester, 1500);
    expect(find.text('Delete account for good?'), findsOneWidget);
    await shot(tester, 'ar_04b_delete_alert');
    await tapText(tester, 'Delete account', last: true, ms: 500);
    debugPrint('QA_DELETED_USER $userId');
    // The function deletes everything, then the app starts over on the welcome screens.
    for (var i = 0; i < 40 && find.byType(OnboardingScreen).evaluate().isEmpty; i++) {
      await settle(tester, 500);
    }
    await settle(tester, 2500);
    await shot(tester, 'ar_05_after_delete_welcome');
    expect(find.byType(OnboardingScreen), findsOneWidget, reason: 'a fresh start on the welcome screens');
    final guest = container(tester).read(currentUserIdProvider);
    expect(guest, isNotNull);
    expect(guest, isNot(userId));
    expect(store.getJsonList('sync.v1.$userId.ops'), isNull);
    expect(store.getJson('sync.v1.$userId.rows'), isNull);
    expect((await ReminderChannel.pending()), isEmpty, reason: 'reminders are off after a deletion');
    // The new guest plays on: onboarding works again.
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 4000);
    await shot(tester, 'ar_06_new_guest_home');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
