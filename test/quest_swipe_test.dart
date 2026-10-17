// Quests tab: a quest is swapped with a swipe to the left (TestFlight, 2026-10-17: "Swap should not be
// a button, it should be a swipe action, like deleting a friend. Don't forget to keep the
// confirmation afterwards."), asked first, with a VoiceOver action and a line that explains it until
// the first swipe.
import 'package:appwrite/models.dart' as models;
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/events/events_screen.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/progress.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoAuth extends AuthNotifier {
  @override
  Future<models.User?> build() async => null;
}

/// A guest (3 tickets) whose swaps are recorded instead of sent.
class _Guest extends ProfileNotifier {
  final swapped = <Goal>[];

  @override
  Future<Profile> build() async => Profile.guest('local');

  @override
  Future<bool> swapQuest(Goal goal) async {
    swapped.add(goal);
    return true;
  }
}

class _Rows extends ProgressNotifier {
  _Rows(this.rows);
  final Map<String, PuzzleProgress> rows;
  @override
  Future<Map<String, PuzzleProgress>> build() async => rows;
}

void main() {
  Finder swipeRows(String prefix) => find.byWidgetPredicate((w) => w is Dismissible && (w.key! as ValueKey<String>).value.startsWith(prefix));

  Future<(_Guest, LocalStore)> pump(WidgetTester tester, {Map<String, PuzzleProgress> rows = const {}}) async {
    tester.view.physicalSize = const Size(430, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final guest = _Guest();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        authProvider.overrideWith(_NoAuth.new),
        profileProvider.overrideWith(() => guest),
        progressProvider.overrideWith(() => _Rows(rows)),
        packsProvider.overrideWith((ref) async => const <Pack>[]),
        allPuzzlesProvider.overrideWith((ref) async => const <Puzzle>[]),
        eventsProvider.overrideWith((ref) async => const <GameEvent>[]),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const EventsScreen()),
    ));
    await tester.pumpAndSettle();
    return (guest, store);
  }

  testWidgets('a quest swipes left to its swap, which asks first; the row stays', (tester) async {
    final semantics = tester.ensureSemantics();
    final (guest, store) = await pump(tester);
    final daily = swipeRows('quest-swap-d:');
    final weekly = swipeRows('quest-swap-w');
    expect(daily, findsWidgets, reason: 'daily quests can be swiped');
    expect(weekly, findsWidgets, reason: 'weekly quests can be swiped');
    // No button on the row; the action shows only while swiping.
    expect(find.text('Swap'), findsNothing);
    expect(find.byKey(const ValueKey('quest-swipe-hint')), findsOneWidget);
    expect(find.text('Swipe left on a quest to swap it for another. A swap costs 1 ticket.'), findsOneWidget);

    // VoiceOver: the row offers the swap as an action.
    expect(tester.getSemantics(find.descendant(of: daily.first, matching: find.byType(ColoredBox)).first), isSemantics(customActions: [const CustomSemanticsAction(label: 'Swap for 1 ticket')]));

    // Part of the way: the action shows, nothing is asked.
    final gesture = await tester.startGesture(tester.getCenter(daily.first));
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    expect(find.text('Swap'), findsOneWidget);
    await gesture.moveBy(const Offset(90, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Swap this quest?'), findsNothing);

    // All the way: the confirmation, and Cancel keeps the quest.
    final before = tester.widget<Dismissible>(daily.first).key;
    await tester.drag(daily.first, const Offset(-320, 0));
    await tester.pumpAndSettle();
    expect(find.text('Swap this quest?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(guest.swapped, isEmpty);
    expect(tester.widget<Dismissible>(daily.first).key, before, reason: 'the row slid back');
    // The player found the swipe: the line is gone for good.
    expect(find.byKey(const ValueKey('quest-swipe-hint')), findsNothing);
    expect(store.questSwipeSeen, isTrue);

    // A weekly quest, confirmed.
    await tester.drag(weekly.at(1), const Offset(-320, 0));
    await tester.pumpAndSettle();
    expect(find.text('Swap this quest?'), findsOneWidget);
    expect(find.text('Swap for 1 ticket'), findsOneWidget);
    await tester.tap(find.text('Swap for 1 ticket'));
    await tester.pumpAndSettle();
    expect(guest.swapped.single.key, startsWith(Goals.weekKey(DateTime.now())));
    expect(weekly, findsWidgets, reason: 'the row is still there');
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a finished or claimed quest does not swipe', (tester) async {
    final now = DateTime.now();
    final rows = {
      for (var i = 0; i < 3; i++)
        'p$i': PuzzleProgress.fromRow('row-$i', {
          'userId': 'local', 'puzzleId': 'p$i', 'gridSize': 16, 'mode': 'cards', 'completed': true, 'stars': 3, 'elapsedSeconds': 90,
          'completedAt': now.subtract(Duration(minutes: i + 1)).toUtc().toIso8601String(),
        }),
    };
    await pump(tester, rows: rows);
    // "Solve 3 puzzles" is ready to claim: Claim, no swipe.
    expect(find.text('Claim'), findsWidgets);
    expect(swipeRows('quest-swap-d:${Goals.dayKey(now)}:s1'), findsNothing);
    expect(swipeRows('quest-swap-d:${Goals.dayKey(now)}:s2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
