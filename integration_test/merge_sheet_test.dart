// Renders the save-merge sheet with sample stats in both themes so a human
// can check it. Captures land in store/raw/ via test_driver/store_screenshots.dart:
//   tools/dev/qa-run.sh drive --driver=test_driver/store_screenshots.dart \
//     --target=integration_test/merge_sheet_test.dart -d CDD7317C-19D6-486D-B258-8AB8A607297D
import 'package:card_jigsaw_world/core/theme/app_theme.dart';
import 'package:card_jigsaw_world/core/theme/tokens.dart';
import 'package:card_jigsaw_world/features/profile/merge_sheet.dart';
import 'package:card_jigsaw_world/state/merge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

SaveSnapshot sample(String user, {required int solved, required int xp, required int level, required int coins, required int tickets, required int hints, required String name, required String avatar, required Duration ago}) {
  final at = DateTime.now().subtract(ago);
  return SaveSnapshot(
    userId: user,
    profile: {'xp': xp, 'level': level, 'coins': coins, 'tickets': tickets, 'hints': hints, 'displayName': name, 'avatar': avatar},
    progress: [for (var i = 0; i < solved; i++) {'puzzleId': 'p$i', 'completed': true, 'stars': 2 + i % 2, '\$updatedAt': at.toIso8601String()}],
    updatedAt: at,
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  final device = sample('g', solved: 41, xp: 3180, level: 9, coins: 2450, tickets: 4, hints: 7, name: 'Quiet Otter', avatar: 'leaf', ago: const Duration(hours: 5));
  final account = sample('a', solved: 23, xp: 4020, level: 11, coins: 310, tickets: 9, hints: 2, name: 'Nia', avatar: 'solver@2', ago: const Duration(days: 12));

  for (final dark in [false, true]) {
    testWidgets('merge sheet ${dark ? 'dark' : 'light'}', (tester) async {
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.canvas)),
      ));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(Scaffold));
      // ignore: unawaited_futures
      showMergeSheet(context, device: device, account: account);
      await tester.pumpAndSettle();
      expect(find.text('Two saves found'), findsOneWidget);
      expect(find.text("Keep this device's"), findsOneWidget);
      expect(find.text("Keep account's"), findsOneWidget);
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('merge_sheet_${dark ? 'dark' : 'light'}');
    });
  }
}
