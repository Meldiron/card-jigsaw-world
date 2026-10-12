import 'package:appwrite/models.dart' as models;
import 'package:card_jigsaw_world/core/theme/app_theme.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/features/events/events_screen.dart';
import 'package:card_jigsaw_world/features/gallery/pack_progress.dart';
import 'package:card_jigsaw_world/features/home/home_screen.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/auth.dart';
import 'package:card_jigsaw_world/state/catalog.dart';
import 'package:card_jigsaw_world/state/profile.dart';
import 'package:card_jigsaw_world/state/progress.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:card_jigsaw_world/widgets/glass.dart';
import 'package:card_jigsaw_world/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoAuth extends AuthNotifier {
  @override
  Future<models.User?> build() async => null;
}

class _GuestProfile extends ProfileNotifier {
  @override
  Future<Profile> build() async => Profile.guest('local');
}

class _Rows extends ProgressNotifier {
  _Rows(this.rows);
  final Map<String, PuzzleProgress> rows;
  @override
  Future<Map<String, PuzzleProgress>> build() async => rows;
}

List<Puzzle> _pictures(String packId, int n) => [
      for (var i = 1; i <= n; i++) Puzzle.fromRow('$packId-$i', {'packId': packId, 'title': 'Picture $i', 'sortOrder': i}),
    ];

PuzzleProgress _solved(String puzzleId, int stars) =>
    PuzzleProgress.fromRow('row-$puzzleId', {'userId': 'local', 'puzzleId': puzzleId, 'gridSize': 16, 'completed': true, 'stars': stars});

Widget _host(Widget child, {double width = 400}) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: SizedBox(width: width, child: child))),
    );

void main() {
  group('PackProgress', () {
    test('counts solved pictures and stars from the progress rows', () {
      final pictures = _pictures('daily-2026-09', 30);
      final rows = {
        for (var i = 1; i <= 30; i++) 'daily-2026-09-$i': _solved('daily-2026-09-$i', i <= 28 ? 3 : 2),
        'other-pack-1': _solved('other-pack-1', 3),
      };
      final p = PackProgress.of(pictures, rows);
      expect(p, const PackProgress(solved: 30, total: 30, stars: 88));
      expect(p.complete, isTrue);
      expect(p.perfect, isFalse);
      expect(p.maxStars, 90);
    });

    test('an unsolved row with stars from an earlier run still counts its stars', () {
      final pictures = _pictures('p', 2);
      final replay = PuzzleProgress.fromRow('r', {'userId': 'local', 'puzzleId': 'p-1', 'gridSize': 16, 'completed': false, 'stars': 2, 'layout': '1,0'});
      final p = PackProgress.of(pictures, {'p-1': replay});
      expect(p.solved, 0);
      expect(p.stars, 2);
      expect(p.complete, isFalse);
    });

    test('falls back to the catalogue count while pictures load', () {
      final p = PackProgress.of(const [], const {}, fallbackTotal: 24);
      expect(p.total, 24);
      expect(p.complete, isFalse);
      expect(const PackProgress(solved: 0, total: 0, stars: 0).complete, isFalse);
    });
  });

  group('PackProgressLine and PackDoneBadges', () {
    testWidgets('in progress: solved count, no badges', (tester) async {
      const p = PackProgress(solved: 9, total: 31, stars: 20);
      await tester.pumpWidget(_host(const Column(children: [PackDoneBadges(progress: p), PackProgressLine(progress: p)])));
      expect(find.text('9/31'), findsOneWidget);
      expect(find.byKey(const ValueKey('pack-done-badge')), findsNothing);
      expect(find.byKey(const ValueKey('pack-perfect-badge')), findsNothing);
    });

    testWidgets('complete: check badge, star bar and both counts where they fit', (tester) async {
      const p = PackProgress(solved: 30, total: 30, stars: 88);
      await tester.pumpWidget(_host(const Column(children: [PackDoneBadges(progress: p), PackProgressLine(progress: p)])));
      expect(find.byKey(const ValueKey('pack-done-badge')), findsOneWidget);
      expect(find.byKey(const ValueKey('pack-perfect-badge')), findsNothing);
      expect(find.text('30/30 · 88/90'), findsOneWidget);
      final bar = tester.widget<ProgressBar>(find.byType(ProgressBar));
      expect(bar.value, closeTo(88 / 90, 1e-9), reason: 'the bar tracks stars once every picture is solved');
    });

    testWidgets('complete on a narrow tile: the star count stays, nothing overflows', (tester) async {
      const p = PackProgress(solved: 30, total: 30, stars: 88);
      await tester.pumpWidget(_host(const PackProgressLine(progress: p, onImage: true, fontSize: 10.5), width: 112));
      expect(find.text('88/90'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('three stars everywhere adds the star badge', (tester) async {
      const p = PackProgress(solved: 30, total: 30, stars: 90);
      await tester.pumpWidget(_host(const PackDoneBadges(progress: p)));
      expect(find.byKey(const ValueKey('pack-perfect-badge')), findsOneWidget);
      expect(find.byKey(const ValueKey('pack-done-badge')), findsOneWidget);
    });
  });

  testWidgets('Home: live event and month tiles show pack progress; a finished month reads as complete', (tester) async {
    tester.view.physicalSize = const Size(600, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final now = DateTime.now();
    final packs = [
      Pack.fromRow('evpack-mental-health', {
        'name': 'World Mental Health Day',
        'category': 'Nature',
        'imageCount': 14,
        'startAt': now.subtract(const Duration(days: 4)).toIso8601String(),
        'endAt': now.add(const Duration(days: 2)).toIso8601String(),
      }),
      Pack.fromRow('daily-2026-10', {'name': 'October 2026', 'category': 'Daily', 'imageCount': 31, 'sortOrder': 0}),
      Pack.fromRow('daily-2026-09', {'name': 'September 2026', 'category': 'Daily', 'imageCount': 30, 'sortOrder': 1}),
    ];
    final pictures = [..._pictures('evpack-mental-health', 14), ..._pictures('daily-2026-10', 31), ..._pictures('daily-2026-09', 30)];
    final rows = {
      for (var i = 1; i <= 3; i++) 'evpack-mental-health-$i': _solved('evpack-mental-health-$i', 3),
      for (var i = 1; i <= 9; i++) 'daily-2026-10-$i': _solved('daily-2026-10-$i', 3),
      for (var i = 1; i <= 30; i++) 'daily-2026-09-$i': _solved('daily-2026-09-$i', i <= 28 ? 3 : 2),
    };
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        authProvider.overrideWith(_NoAuth.new),
        profileProvider.overrideWith(_GuestProfile.new),
        progressProvider.overrideWith(() => _Rows(rows)),
        packsProvider.overrideWith((ref) async => packs),
        allPuzzlesProvider.overrideWith((ref) async => pictures),
        eventsProvider.overrideWith((ref) async => const <GameEvent>[]),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const HomeScreen()),
    ));
    await tester.pumpAndSettle();

    Finder tile(String name) => find.ancestor(of: find.text(name), matching: find.byType(Pressable)).first;
    Finder inTile(String name, Finder f) => find.descendant(of: tile(name), matching: f);

    // Live event: progress instead of a bare picture count.
    expect(inTile('World Mental Health Day', find.text('3/14')), findsOneWidget);
    expect(inTile('World Mental Health Day', find.byKey(const ValueKey('pack-done-badge'))), findsNothing);
    // This month, in progress.
    expect(inTile('October 2026', find.text('9/31')), findsOneWidget);
    expect(inTile('October 2026', find.byKey(const ValueKey('pack-done-badge'))), findsNothing);
    // September 2026, every picture solved: check badge and the star count.
    expect(inTile('September 2026', find.byKey(const ValueKey('pack-done-badge'))), findsOneWidget);
    expect(inTile('September 2026', find.byKey(const ValueKey('pack-perfect-badge'))), findsNothing);
    expect(inTile('September 2026', find.textContaining('88/90')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Quests: event cards and Coming up rows show the same pack progress', (tester) async {
    tester.view.physicalSize = const Size(600, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final now = DateTime.now();
    final events = [
      GameEvent.fromRow('ev-live', {
        'name': 'World Mental Health Day',
        'description': 'Calm pictures',
        'type': 'seasonal',
        'startAt': now.subtract(const Duration(days: 4)).toIso8601String(),
        'endAt': now.add(const Duration(days: 2)).toIso8601String(),
        'rewardCoins': 200,
        'packId': 'evpack-mental-health',
      }),
      GameEvent.fromRow('ev-next', {
        'name': 'World Food Day',
        'description': 'Kitchens and markets',
        'type': 'seasonal',
        'startAt': now.add(const Duration(days: 1)).toIso8601String(),
        'endAt': now.add(const Duration(days: 8)).toIso8601String(),
        'rewardCoins': 200,
        'packId': 'evpack-food',
      }),
    ];
    final pictures = [..._pictures('evpack-mental-health', 14), ..._pictures('evpack-food', 10)];
    final rows = {for (var i = 1; i <= 14; i++) 'evpack-mental-health-$i': _solved('evpack-mental-health-$i', 3)};
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        authProvider.overrideWith(_NoAuth.new),
        profileProvider.overrideWith(_GuestProfile.new),
        progressProvider.overrideWith(() => _Rows(rows)),
        packsProvider.overrideWith((ref) async => const <Pack>[]),
        allPuzzlesProvider.overrideWith((ref) async => pictures),
        eventsProvider.overrideWith((ref) async => events),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const EventsScreen()),
    ));
    await tester.pumpAndSettle();

    // Finished pack, three stars everywhere: both badges, star count, Claim.
    expect(find.byKey(const ValueKey('pack-done-badge')), findsOneWidget);
    expect(find.byKey(const ValueKey('pack-perfect-badge')), findsOneWidget);
    expect(find.text('14/14 · 42/42'), findsOneWidget);
    expect(find.text('Claim'), findsOneWidget);
    // The upcoming event's pack, not started.
    final upcoming = find.ancestor(of: find.text('World Food Day'), matching: find.byType(Pressable)).first;
    expect(find.descendant(of: upcoming, matching: find.text('0/10')), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Dispose the screen so its countdown timer stops.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('scrollEndPadding clears the tab bar inside the shell and the home indicator outside it', (tester) async {
    late double inside;
    late double outside;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(padding: EdgeInsets.only(bottom: 34)),
      child: Column(
        children: [
          Builder(builder: (context) {
            outside = GlassTabBar.scrollEndPadding(context);
            return const SizedBox();
          }),
          // The shell's Scaffold consumes the safe inset and reports the bar slot instead.
          MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.zero),
            child: GlassTabBarScope(
              child: Builder(builder: (context) {
                inside = GlassTabBar.scrollEndPadding(context);
                return const SizedBox();
              }),
            ),
          ),
        ],
      ),
    ));
    expect(outside, 34 + 16);
    final safe = tester.view.padding.bottom / tester.view.devicePixelRatio;
    expect(inside, GlassTabBar.slotHeight(safe) + 16);
    expect(inside, greaterThanOrEqualTo(GlassTabBar.barHeight + 16));
  });
}
