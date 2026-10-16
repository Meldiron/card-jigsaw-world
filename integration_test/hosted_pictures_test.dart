import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner feedback AJtnSyS50cjLESDUhBVjJqw: pictures of the World Mental Health
/// Day pack stayed blurred in the grid and on the detail page. Opens that pack,
/// waits for the pictures and captures the grid and one detail page.
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

  testWidgets('hosted pictures load in the event pack grid and detail page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await FirstSteps.skipFor(store); // the whole app; integration_test/first_steps_test.dart plays the first steps
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(overrides: [localStoreProvider.overrideWithValue(store)], child: const CardenApp()));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 6000);
    // Straight to the pack the tester reported.
    GoRouter.of(tester.element(find.text('Library').last)).push('/library/pack/evpack-mental-health-2026');
    await settle(tester, 20000);
    await binding.takeScreenshot('30_hosted_event_grid');
    final grid = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).last;
    await tester.dragUntilVisible(find.textContaining('Bonsai'), grid, const Offset(0, -200));
    await settle(tester, 6000);
    await binding.takeScreenshot('30b_hosted_event_grid_bonsai');
    await tapText(tester, 'Bonsai', ms: 12000);
    await binding.takeScreenshot('30c_hosted_detail_bonsai');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
