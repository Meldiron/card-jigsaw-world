import 'package:appwrite/models.dart' as models;
import 'package:card_jigsaw_world/core/theme/app_theme.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/features/profile/achievement_order.dart';
import 'package:card_jigsaw_world/features/profile/profile_screen.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/achievements.dart';
import 'package:card_jigsaw_world/state/auth.dart';
import 'package:card_jigsaw_world/state/catalog.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/seed_save.dart';

AchievementFamily _family(String id, List<int> thresholds) => AchievementFamily(
      id: id,
      title: id,
      icon: Icons.star,
      describe: (t) => 'Reach $t',
      steps: [for (final t in thresholds) AchievementStep(t, coins: 10)],
      progress: (_) => 0,
    );

AchievementStatus _status(String id, {required List<int> thresholds, required int claimed, required int progress}) =>
    AchievementStatus(family: _family(id, thresholds), stepIndex: claimed, progress: progress, claimedSteps: claimed);

class _NoAuth extends AuthNotifier {
  @override
  Future<models.User?> build() async => null;
}

void main() {
  group('achievementOrder', () {
    test('claimable first, then in progress by closeness, then fully claimed', () {
      final list = [
        _status('done', thresholds: [5], claimed: 1, progress: 9), // all tiers claimed
        _status('far', thresholds: [10, 50], claimed: 0, progress: 1), // 10 %
        _status('ready', thresholds: [5, 20], claimed: 1, progress: 25), // tier 2 claimable
        _status('close', thresholds: [10], claimed: 0, progress: 8), // 80 %
        _status('alsoDone', thresholds: [1, 2], claimed: 2, progress: 2),
        _status('alsoReady', thresholds: [3], claimed: 0, progress: 3),
        _status('zero', thresholds: [10], claimed: 0, progress: 0),
      ];
      expect(achievementStage(list[0]), AchievementStage.complete);
      expect(achievementStage(list[2]), AchievementStage.claimable);
      expect(achievementStage(list[3]), AchievementStage.inProgress);
      expect(achievementOrder(list), ['ready', 'alsoReady', 'close', 'far', 'zero', 'done', 'alsoDone']);
    });

    test('ties keep catalogue order', () {
      final list = [
        _status('b', thresholds: [10], claimed: 0, progress: 5),
        _status('a', thresholds: [20], claimed: 0, progress: 10),
        _status('c', thresholds: [4], claimed: 0, progress: 2),
      ];
      expect(achievementOrder(list), ['b', 'a', 'c']);
    });

    test('a frozen order keeps a claimed card in place and updates it', () {
      final before = [
        _status('x', thresholds: [10], claimed: 0, progress: 3),
        _status('y', thresholds: [5, 50], claimed: 0, progress: 6),
        _status('z', thresholds: [1], claimed: 1, progress: 1),
      ];
      final order = achievementOrder(before);
      expect(order, ['y', 'x', 'z']);

      // Claim y's first tier: it is now in progress towards 50 (12 %),
      // which would sort it after x (30 %) if the list were sorted again.
      final after = [
        before[0],
        _status('y', thresholds: [5, 50], claimed: 1, progress: 6),
        before[2],
      ];
      expect(achievementOrder(after), ['x', 'y', 'z']);
      final shown = applyAchievementOrder(after, order);
      expect([for (final s in shown) s.family.id], ['y', 'x', 'z']);
      expect(shown.first.claimedSteps, 1, reason: 'the card shows its next tier in place');
    });

    test('families missing from a frozen order follow at the end', () {
      final live = [
        _status('a', thresholds: [1], claimed: 0, progress: 0),
        _status('new', thresholds: [1], claimed: 0, progress: 1),
        _status('b', thresholds: [1], claimed: 0, progress: 0),
      ];
      expect([for (final s in applyAchievementOrder(live, ['b', 'a', 'gone'])) s.family.id], ['b', 'a', 'new']);
    });
  });

  testWidgets('Profile: claiming keeps the card in place; the list re-sorts on return', (tester) async {
    // Wide enough for the stat labels in the test font (every glyph is 1 em).
    tester.view.physicalSize = const Size(520, 7000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 6000 coins: Well Off (hold 5000) is ready. VIP and Piggy Breaker are
    // fully claimed. Twelve three-star solves make several tiers ready.
    SharedPreferences.setMockInitialValues(seededSave(
      profile: {'coins': 6000, 'claimedAchievements': ['vip:1', 'piggy:1']},
      progress: {
        for (var i = 1; i <= 12; i++) 'pack${i % 3}-$i': {'gridSize': 16, 'completed': true, 'stars': 3},
      },
    ));
    final store = await LocalStore.open();
    final visible = ValueNotifier(true);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        authProvider.overrideWith(_NoAuth.new),
        // Offline: the catalogue is empty instead of a network call.
        packsProvider.overrideWith((ref) async => const <Pack>[]),
        allPuzzlesProvider.overrideWith((ref) async => const <Puzzle>[]),
        publicPacksProvider.overrideWith((ref) async => const <Pack>[]),
        publicPuzzlesProvider.overrideWith((ref) async => const <Puzzle>[]),
        eventsProvider.overrideWith((ref) async => const <GameEvent>[]),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (_, on, child) => TickerMode(enabled: on, child: child!),
          child: const ProfileScreen(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(find.byType(ProfileScreen)));
    List<String> shownOrder() {
      final ids = [for (final f in achievementFamilies) f.id];
      for (final id in ids) {
        expect(find.byKey(ValueKey(id)), findsOneWidget, reason: '$id card is built');
      }
      return ids..sort((a, b) => tester.getTopLeft(find.byKey(ValueKey(a))).dy.compareTo(tester.getTopLeft(find.byKey(ValueKey(b))).dy));
    }

    Map<String, AchievementStage> stages() => {for (final s in container.read(achievementsProvider)) s.family.id: achievementStage(s)};

    void expectGrouped(List<String> order) {
      final st = stages();
      final groups = [for (final id in order) st[id]!.index];
      expect(groups, [...groups]..sort(), reason: 'claimable, then in progress, then done: $order');
    }

    final initial = shownOrder();
    expect(stages()['rich'], AchievementStage.claimable);
    expect(initial.sublist(initial.length - 2), containsAll(['vip', 'piggy']));
    expectGrouped(initial);

    // Claim Well Off: it becomes fully claimed but stays where it was.
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('rich')), matching: find.text('Claim')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(stages()['rich'], AchievementStage.complete);
    expect(find.descendant(of: find.byKey(const ValueKey('rich')), matching: find.text('Done')), findsOneWidget);
    expect(shownOrder(), initial, reason: 'no card moves while the player is on the screen');

    // Claim the first tier of Solver: the card updates to its next tier in place.
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('solver')), matching: find.text('Claim')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(shownOrder(), initial);

    // Leave (another tab or a page on top) and come back: the list re-sorts.
    visible.value = false;
    await tester.pump();
    visible.value = true;
    await tester.pump();
    final resorted = shownOrder();
    expectGrouped(resorted);
    expect(resorted.indexOf('rich'), greaterThan(resorted.indexOf('streak')), reason: 'Well Off joins the fully claimed cards');
    expect(tester.takeException(), isNull);
  });
}
