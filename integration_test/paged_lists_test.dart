import 'package:carden/app.dart';
import 'package:carden/core/image_files.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/repositories.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/social.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The two lists that page while scrolling: Social > League and Profile > My Puzzles.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> settle(WidgetTester tester, int ms) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1500}) async {
    final f = find.textContaining(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  testWidgets('league and my puzzles', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await FirstSteps.skipFor(store); // the whole app; integration_test/first_steps_test.dart plays the first steps
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(overrides: [localStoreProvider.overrideWithValue(store)], child: const CardenApp()));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 8000);
    await tapText(tester, 'Social', ms: 2500);
    await tapText(tester, 'Leaderboard', ms: 5000);
    expect(find.textContaining('XP'), findsWidgets);
    await binding.takeScreenshot('41_league');
    final list = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).last;
    await tester.drag(list, const Offset(0, -2000));
    await settle(tester, 3000);
    await binding.takeScreenshot('41b_league_end');
    GoRouter.of(tester.element(find.text('Social').last)).push('/profile/my-puzzles');
    await settle(tester, 5000);
    expect(find.text('Add photo'), findsOneWidget);
    expect(find.textContaining('5 photos free'), findsOneWidget);
    await binding.takeScreenshot('41c_my_puzzles');

    // Private photos: five uploads (the free limit) must still show for their owner, who loads
    // them through the signed-in client; a sixth is refused with the VIP alert. Cleaned up after.
    final container = ProviderScope.containerOf(tester.element(find.byType(CardenApp)));
    final userId = container.read(currentUserIdProvider)!;
    final repo = container.read(uploadRepositoryProvider);
    final pictures = (await container.read(allPuzzlesProvider.future)).take(5).toList();
    final made = [
      for (final p in pictures) await repo.upload(userId, bytes: await ImageFiles.bytes(p.imageUrl), filename: 'photo.jpg', title: 'My photo QA'),
    ];
    try {
      container.invalidate(myPuzzlesProvider);
      container.invalidate(myPuzzleCountProvider);
      await settle(tester, 8000);
      expect(find.textContaining('All 5 free photos used'), findsOneWidget);
      await binding.takeScreenshot('41d_my_puzzles_private');
      await tapText(tester, 'Add photo', ms: 2500);
      expect(find.text('Photo limit reached'), findsOneWidget);
      await binding.takeScreenshot('41e_photo_limit');
      await tapText(tester, 'Not now');
      GoRouter.of(tester.element(find.text('My Puzzles').last)).push('/play/${made.first.id}');
      await settle(tester, 6000);
      await binding.takeScreenshot('41f_my_photo_difficulty');
    } finally {
      for (final m in made) {
        await repo.delete(m);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
