// Extra captures for the social / profile / gallery feedback round
// (live Appwrite backend, fresh guest). Runs on the iPhone 17 Pro Max simulator:
//   flutter drive --dart-define=CJW_MUTE=true --driver=test_driver/store_screenshots.dart \
//     --target=integration_test/social_profile_test.dart \
//     -d D03644FB-6169-4E87-8E0F-CCFC884FBE78
// Output lands in store/raw/s*.png.
import 'package:card_jigsaw_world/app.dart';
import 'package:card_jigsaw_world/core/sfx.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/features/social/social_screen.dart';
import 'package:card_jigsaw_world/state/auth.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:card_jigsaw_world/state/social.dart';
import 'package:card_jigsaw_world/widgets/icons.dart';
import 'package:flutter/cupertino.dart';
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
    await settle(tester, 500);
    await binding.takeScreenshot(name);
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  Future<void> back(WidgetTester tester) async {
    final f = find.byIcon(CupertinoIcons.back);
    if (f.evaluate().isEmpty) {
      await binding.takeScreenshot('zz_diag_no_back');
      return;
    }
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, 1200);
  }

  testWidgets('capture social, player, gallery and statistics screens', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const CardJigsawApp(),
    ));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 5000);
    if (find.text('Claim').evaluate().isNotEmpty) {
      await tapText(tester, 'Claim');
      if (find.textContaining('Claim day').evaluate().isNotEmpty) {
        await tester.tap(find.textContaining('Claim day'), warnIfMissed: false);
        await settle(tester, 1500);
      }
      await tester.tapAt(const Offset(220, 80));
      await settle(tester, 1000);
    }

    // Library cards, then the unlock confirmation on the first locked pack.
    await tapText(tester, 'Library', ms: 3000);
    await shot(tester, 's01_library');
    if (find.text('Unlocked').evaluate().isNotEmpty) {
      await tapText(tester, 'Unlocked', ms: 1200);
      await shot(tester, 's01b_library_unlocked');
      await tapText(tester, 'All', ms: 1000);
    }
    final lock = find.byIcon(AppIcons.lock);
    if (lock.evaluate().isNotEmpty) {
      await tester.tap(lock.first, warnIfMissed: false);
      await settle(tester, 3500);
      if (find.text('Unlock for').evaluate().isNotEmpty) {
        await tapText(tester, 'Unlock for', ms: 1200);
        await shot(tester, 's02_unlock_alert');
        if (find.text('Cancel').evaluate().isNotEmpty) {
          await tapText(tester, 'Cancel', ms: 800);
        } else if (find.byIcon(CupertinoIcons.xmark).evaluate().isNotEmpty) {
          await tester.tap(find.byIcon(CupertinoIcons.xmark).first, warnIfMissed: false);
          await settle(tester, 1000);
        }
      }
      await shot(tester, 's03_pack_locked');
      await back(tester);
    }

    // Daily month: today's tile outline.
    await tapText(tester, 'Daily', ms: 1500);
    final month = find.textContaining(' 2026');
    if (month.evaluate().isNotEmpty) {
      await tester.tap(month.first, warnIfMissed: false);
      await settle(tester, 4000);
      await shot(tester, 's04_daily_month');
      await back(tester);
    }
    await tapText(tester, 'All', ms: 1200);

    // League row opens the player's profile.
    await tapText(tester, 'Social', ms: 3500);
    final chevron = find.byIcon(CupertinoIcons.chevron_right);
    if (chevron.evaluate().isNotEmpty) {
      await tester.tap(chevron.first, warnIfMissed: false);
      await settle(tester, 3000);
      await shot(tester, 's05_player');
      await back(tester);
    }

    // Friends: add the league leader by code, then the remove confirmation.
    await tapText(tester, 'Friends', ms: 1500);
    final container = ProviderScope.containerOf(tester.element(find.byType(SocialScreen)));
    final me = container.read(currentUserIdProvider);
    final leaders = container.read(leaderboardProvider).value ?? const [];
    final other = leaders.where((p) => p.userId != me).firstOrNull;
    await tapText(tester, 'Add friend by code', ms: 1200);
    await shot(tester, 's06_add_friend_alert');
    if (other != null) {
      await tester.enterText(find.byType(CupertinoTextField).last, other.userId);
      await settle(tester, 400);
      await tapText(tester, 'Add friend', ms: 3500);
      final row = find.byType(Dismissible);
      if (row.evaluate().isNotEmpty) {
        await shot(tester, 's07_friends');
        await tester.drag(row.first, const Offset(-500, 0));
        await settle(tester, 1500);
        await shot(tester, 's08_remove_friend_alert');
        await tapText(tester, 'Cancel', ms: 1200);
        await shot(tester, 's09_friends_kept');
        await tester.tap(find.byType(Dismissible).first, warnIfMissed: false);
        await settle(tester, 3000);
        await shot(tester, 's10_friend_profile');
        await back(tester);
        // Leave the guest tidy: remove the friend for real.
        await tester.drag(find.byType(Dismissible).first, const Offset(-500, 0));
        await settle(tester, 1500);
        if (find.text('Remove').evaluate().isNotEmpty) await tapText(tester, 'Remove', ms: 2500);
      }
    } else {
      await tapText(tester, 'Not now', ms: 800);
    }

    // Profile statistics.
    await tapText(tester, 'Profile', ms: 2500);
    await shot(tester, 's11_profile');
    await tester.dragUntilVisible(find.text('Hexagons'), find.byType(CustomScrollView).last, const Offset(0, -200));
    await settle(tester, 1500);
    await shot(tester, 's12_profile_stats');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
