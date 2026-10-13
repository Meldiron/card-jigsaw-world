import 'package:card_jigsaw_world/app.dart';
import 'package:card_jigsaw_world/core/sfx.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/state/settings.dart';
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
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(overrides: [localStoreProvider.overrideWithValue(store)], child: const CardJigsawApp()));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 8000);
    await tapText(tester, 'Social', ms: 2500);
    await tapText(tester, 'League', ms: 5000);
    expect(find.textContaining('XP'), findsWidgets);
    await binding.takeScreenshot('41_league');
    final list = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).last;
    await tester.drag(list, const Offset(0, -2000));
    await settle(tester, 3000);
    await binding.takeScreenshot('41b_league_end');
    GoRouter.of(tester.element(find.text('Social').last)).push('/profile/my-puzzles');
    await settle(tester, 5000);
    expect(find.text('Add photo'), findsOneWidget);
    await binding.takeScreenshot('41c_my_puzzles');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
