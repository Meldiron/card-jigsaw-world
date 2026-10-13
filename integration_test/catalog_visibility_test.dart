import 'package:card_jigsaw_world/app.dart';
import 'package:card_jigsaw_world/core/sfx.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/state/catalog.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Against the live catalogue: every pack row reaches the app (the catalogue is larger than one
/// page), future daily months and event packs more than three days away stay hidden, and the
/// Library and Quests screens show only what is live or coming within three days.
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

  testWidgets('catalogue visibility', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(overrides: [localStoreProvider.overrideWithValue(store)], child: const CardJigsawApp()));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 8000);

    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    final rows = await container.read(packRowsProvider.future);
    final packs = await container.read(packsProvider.future);
    final now = DateTime.now();
    debugPrint('catalogue: ${rows.length} pack rows, ${packs.length} visible');
    expect(rows.length, greaterThan(300), reason: 'every pack row loads, not just the first page');
    expect(packs.where((p) => p.category == 'AI').length, 20);
    expect(packs.where((p) => p.category == 'Abstract').length, 20);
    for (final p in packs) {
      final month = p.dailyMonth;
      if (month != null) expect(now.isBefore(month), isFalse, reason: '${p.id} is a future month');
      if (p.startAt != null && now.isBefore(p.startAt!)) {
        expect(p.startAt!.difference(now).inHours, lessThanOrEqualTo(72), reason: '${p.id} opens more than 3 days from now');
      }
    }
    final puzzles = await container.read(allPuzzlesProvider.future);
    final hidden = {for (final p in rows) if (!p.isReleasedAt(now)) p.id};
    expect(puzzles.where((z) => hidden.contains(z.packId)), isEmpty);

    await tapText(tester, 'Library', ms: 4000);
    await binding.takeScreenshot('40_library_all');
    await tapText(tester, 'Events', ms: 4000);
    await binding.takeScreenshot('40b_library_events');
    await tapText(tester, 'Daily', ms: 4000);
    await binding.takeScreenshot('40c_library_daily');
    final chips = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right).first;
    await tester.dragUntilVisible(find.text('AI'), chips, const Offset(-200, 0));
    await settle(tester, 800);
    await tapText(tester, 'AI', ms: 5000);
    await binding.takeScreenshot('40d_library_ai');
    await tester.dragUntilVisible(find.text('Abstract'), chips, const Offset(-200, 0));
    await settle(tester, 800);
    await tapText(tester, 'Abstract', ms: 5000);
    await binding.takeScreenshot('40e_library_abstract');
    await tapText(tester, 'Quests', ms: 5000);
    await binding.takeScreenshot('40f_quests');
    final list = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
    await tester.drag(list, const Offset(0, -1400));
    await settle(tester, 2500);
    await binding.takeScreenshot('40g_quests_events');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
