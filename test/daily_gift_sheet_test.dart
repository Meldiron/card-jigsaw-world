// The Daily gift sheet (107 B, 001 B, 100 A) at phone sizes (SE and Pro Max), in both themes, at the
// default and the largest text size the app allows (1.35), in the states a player meets: day 1, mid-week,
// day 7, claimed today, and a lost streak that can be restored with today's claim. It renders without a
// layout error, lists the whole week, marks today, and the claim stays reachable.
import 'package:card_jigsaw_world/core/theme/app_theme.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/features/daily/daily_reward_sheet.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/profile.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:card_jigsaw_world/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _patch = const {};

class _Profile extends ProfileNotifier {
  @override
  Future<Profile> build() async {
    final g = Profile.guest('local');
    return Profile.fromRow(g.id, {...g.toData(), ..._patch});
  }
}

void main() {
  final now = DateTime.now();
  String ago(int days) => now.subtract(Duration(days: days)).toUtc().toIso8601String();
  // State: profile columns, the claim button's label (null: claimed today), the tag on today's row.
  final states = <String, (Map<String, dynamic>, String?, String)>{
    'new player, day 1': (const {}, 'Claim day 1 gift', 'Today'),
    'mid-week, day 4': ({'streak': 3, 'longestStreak': 3, 'lastDailyClaim': ago(1)}, 'Claim day 4 gift', 'Today'),
    'day 7': ({'streak': 6, 'longestStreak': 6, 'lastDailyClaim': ago(1)}, 'Claim day 7 gift', 'Today'),
    'claimed today': ({'streak': 4, 'longestStreak': 4, 'lastDailyClaim': now.toUtc().toIso8601String()}, null, 'Claimed'),
    'missed days, restore offered': ({'streak': 6, 'longestStreak': 6, 'lastDailyClaim': ago(3), 'tickets': 8}, 'Claim day 1 gift', 'Today'),
  };
  for (final size in const [Size(375, 667), Size(440, 956)]) {
    for (final dark in [false, true]) {
      for (final scale in const [1.0, 1.35]) {
        for (final s in states.entries) {
          testWidgets('Daily gift ${size.width.toInt()}x${size.height.toInt()} ${dark ? 'dark' : 'light'} text ${scale}x: ${s.key}', (tester) async {
            final (patch, claim, tag) = s.value;
            _patch = patch;
            final errors = <String>{};
            final previous = FlutterError.onError;
            FlutterError.onError = (d) {
              final where = RegExp(r'lib/[a-z_/]+\.dart:\d+').firstMatch(d.toString())?.group(0) ?? '?';
              errors.add('${d.exceptionAsString().split('\n').first} @ $where');
            };
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            SharedPreferences.setMockInitialValues({});
            final store = await LocalStore.open();
            late BuildContext host;
            await tester.pumpWidget(ProviderScope(
              overrides: [
                localStoreProvider.overrideWithValue(store),
                profileProvider.overrideWith(_Profile.new),
              ],
              child: MediaQuery(
                data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
                child: MaterialApp(
                  theme: dark ? AppTheme.dark() : AppTheme.light(),
                  home: Scaffold(
                    body: Builder(builder: (context) {
                      host = context;
                      return const SizedBox.expand();
                    }),
                  ),
                ),
              ),
            ));
            await tester.pumpAndSettle();
            showAppSheet(host, builder: (_) => const DailyRewardSheet());
            await tester.pumpAndSettle();
            FlutterError.onError = previous;
            expect(errors, isEmpty);

            final sheet = find.byType(DailyRewardSheet);
            for (var day = 1; day <= 7; day++) {
              expect(find.descendant(of: sheet, matching: find.text('Day $day')), findsOneWidget, reason: 'the whole week is listed');
            }
            expect(find.descendant(of: sheet, matching: find.text(tag)), findsOneWidget);
            if (claim == null) {
              expect(find.descendant(of: sheet, matching: find.text('Tomorrow')), findsOneWidget);
              expect(find.descendant(of: sheet, matching: find.text('Done')), findsOneWidget);
            } else {
              // The claim may sit below the fold at the largest text size; the sheet scrolls to it (100 A).
              final button = find.descendant(of: sheet, matching: find.text(claim));
              await tester.ensureVisible(button);
              await tester.pumpAndSettle();
              expect(tester.getRect(button).bottom, lessThanOrEqualTo(size.height), reason: 'the claim can be reached');
            }
            final restore = find.descendant(of: sheet, matching: find.text('Restore'));
            expect(restore, s.key.startsWith('missed') ? findsOneWidget : findsNothing);
          });
        }
      }
    }
  }
}
