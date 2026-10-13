import 'package:appwrite/models.dart' as models;
import 'package:card_jigsaw_world/core/theme/app_theme.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/features/gallery/library_screen.dart';
import 'package:card_jigsaw_world/features/gallery/pack_card.dart';
import 'package:card_jigsaw_world/features/gallery/pack_progress.dart';
import 'package:card_jigsaw_world/features/home/home_pack_rows.dart';
import 'package:card_jigsaw_world/features/home/home_screen.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/auth.dart';
import 'package:card_jigsaw_world/state/catalog.dart';
import 'package:card_jigsaw_world/state/profile.dart';
import 'package:card_jigsaw_world/state/progress.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 10, 13, 9);

Pack _pack(String id, {String category = 'Nature', int sortOrder = 0, Map<String, dynamic> extra = const {}}) =>
    Pack.fromRow(id, {'name': 'Pack $id', 'category': category, 'sortOrder': sortOrder, 'imageCount': 4, ...extra});

List<Puzzle> _pictures(String packId, int n, {DateTime? firstDay}) => [
      for (var i = 1; i <= n; i++)
        Puzzle.fromRow('$packId-$i', {
          'packId': packId,
          'title': 'Picture $i',
          'sortOrder': i,
          if (firstDay != null) 'date': firstDay.add(Duration(days: i - 1)).toIso8601String(),
        }),
    ];

PuzzleProgress _row(String puzzleId, {bool completed = true, int stars = 3, DateTime? at, String layout = ''}) => PuzzleProgress.fromRow('row-$puzzleId', {
      'userId': 'u',
      'puzzleId': puzzleId,
      'gridSize': 16,
      'completed': completed,
      'stars': stars,
      'layout': layout,
      'completedAt': ?at?.toIso8601String(),
    });

Map<String, PackProgress> _progressOf(List<Pack> packs, List<Puzzle> pictures, Map<String, PuzzleProgress> rows) => {
      for (final p in packs) p.id: PackProgress.of(pictures.where((z) => z.packId == p.id).toList(), rows),
    };

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

void main() {
  group('homePackRows', () {
    // a: 2/4 solved, played on the 10th. b: 1/4, played on the 12th.
    // c: complete, 10/12 stars. d: complete, 11/12 stars. e: perfect.
    // f: complete but locked now (bought on another account, say).
    // g: started on a board only. h: locked, started. October: every open day solved.
    final packs = [
      for (final (i, id) in ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'].indexed) _pack(id, sortOrder: i + 1),
      _pack('daily-2026-10', category: 'Daily'),
      _pack('daily-2026-09', category: 'Daily'),
    ];
    final pictures = [
      for (final id in ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']) ..._pictures(id, 4),
      ..._pictures('daily-2026-10', 31, firstDay: DateTime(2026, 10, 1)),
      ..._pictures('daily-2026-09', 30, firstDay: DateTime(2026, 9, 1)),
    ];
    Map<String, PuzzleProgress> baseRows() => {
          'a-1': _row('a-1', at: DateTime(2026, 10, 9)),
          'a-2': _row('a-2', at: DateTime(2026, 10, 10)),
          'b-1': _row('b-1', at: DateTime(2026, 10, 12)),
          for (var i = 1; i <= 4; i++) 'c-$i': _row('c-$i', stars: i <= 2 ? 2 : 3, at: DateTime(2026, 10, i)),
          for (var i = 1; i <= 4; i++) 'd-$i': _row('d-$i', stars: i == 1 ? 2 : 3, at: DateTime(2026, 9, 20 + i)),
          for (var i = 1; i <= 4; i++) 'e-$i': _row('e-$i', at: DateTime(2026, 10, 11)),
          for (var i = 1; i <= 4; i++) 'f-$i': _row('f-$i', stars: 1, at: DateTime(2026, 10, 5)),
          'g-1': _row('g-1', completed: false, stars: 0, layout: '1,0,2,3'),
          'h-1': _row('h-1', at: DateTime(2026, 10, 12)),
          for (var i = 1; i <= 13; i++) 'daily-2026-10-$i': _row('daily-2026-10-$i', at: DateTime(2026, 10, i)),
        };
    bool unlocked(Pack p) => p.id != 'f' && p.id != 'h' && p.id != 'daily-2026-09';
    HomePackRows rowsFor(Map<String, PuzzleProgress> rows) => homePackRows(
          packs: packs,
          puzzles: pictures,
          rows: rows,
          progress: _progressOf(packs, pictures, rows),
          isUnlocked: unlocked,
          now: _now,
        );

    test('in progress: started, unfinished, playable now, most recently played first', () {
      final r = rowsFor(baseRows());
      expect(r.inProgress.map((p) => p.id), ['b', 'a', 'g'], reason: 'h is locked; October has no open day left to solve');
    });

    test('a daily month with an open day unsolved is in progress', () {
      final rows = baseRows()..remove('daily-2026-10-5');
      expect(rowsFor(rows).inProgress.map((p) => p.id), contains('daily-2026-10'));
    });

    test('missing stars: finished, not perfect, playable, fewest stars missing first', () {
      final r = rowsFor(baseRows());
      expect(r.missingStars.map((p) => p.id), ['d', 'c'], reason: 'd misses 1 star, c misses 2; f is locked; e is perfect');
    });

    test('finished: every complete pack, most recently finished first, with totals', () {
      final r = rowsFor(baseRows());
      expect(r.finished.map((p) => p.id), ['e', 'f', 'c', 'd']);
      expect(r.stats, const FinishedStats(packs: 4, perfect: 1, pictures: 16));
    });

    test('a new player has no pack rows', () {
      final r = rowsFor(const {});
      expect(r.inProgress, isEmpty);
      expect(r.missingStars, isEmpty);
      expect(r.finished, isEmpty);
      expect(r.stats, const FinishedStats(packs: 0, perfect: 0, pictures: 0));
    });
  });

  group('Home', () {
    final now = DateTime.now();
    // Seven library packs (Featured shows six), a live event pack and a daily month.
    final library = [for (var i = 1; i <= 7; i++) _pack('lib$i', sortOrder: 10 - i)];
    final event = _pack('evpack-ocean', sortOrder: 0, extra: {
      'startAt': now.subtract(const Duration(days: 1)).toIso8601String(),
      'endAt': now.add(const Duration(days: 3)).toIso8601String(),
    });
    final month = _pack('daily-2026-01', category: 'Daily', sortOrder: -1);
    final packs = [month, event, ...library];
    final pictures = [for (final p in packs) ..._pictures(p.id, 4)];

    Future<ProviderContainer> pumpHome(WidgetTester tester, Map<String, PuzzleProgress> rows) async {
      tester.view.physicalSize = const Size(600, 5200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final router = GoRouter(initialLocation: '/home', routes: [
        GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
        GoRoute(path: '/library', builder: (_, _) => const Scaffold(body: Text('Library page'))),
      ]);
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
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ));
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    }

    testWidgets('a new player: Quick play, no pack rows; Featured is six library packs in order', (tester) async {
      await pumpHome(tester, const {});
      expect(find.text('Quick play'), findsOneWidget);
      expect(find.text('A picture you have not played yet'), findsOneWidget);
      expect(find.text('Packs in progress'), findsNothing);
      expect(find.text('Missing stars'), findsNothing);
      expect(find.text('Finished packs'), findsNothing);
      final featured = tester.widgetList<PackCard>(find.byType(PackCard)).map((c) => c.pack.id).toList();
      expect(featured, ['lib7', 'lib6', 'lib5', 'lib4', 'lib3', 'lib2']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with progress: the three pack rows, and See all opens the Library on Finished', (tester) async {
      final rows = {
        'lib1-1': _row('lib1-1', at: DateTime(2026, 10, 1)),
        for (var i = 1; i <= 4; i++) 'lib2-$i': _row('lib2-$i', stars: i == 1 ? 1 : 3, at: DateTime(2026, 10, 2)),
        for (var i = 1; i <= 4; i++) 'lib3-$i': _row('lib3-$i', at: DateTime(2026, 10, 3)),
      };
      final container = await pumpHome(tester, rows);
      expect(find.text('Packs in progress'), findsOneWidget);
      expect(find.text('1 pack to finish'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('home-packs-in-progress')), matching: find.text('Pack lib1')), findsOneWidget);
      expect(find.text('Missing stars'), findsOneWidget);
      expect(find.text('2 stars to earn in 1 pack'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('home-missing-stars')), matching: find.text('Pack lib2')), findsOneWidget);
      expect(find.text('Finished packs'), findsOneWidget);
      final finished = find.byKey(const ValueKey('home-finished-packs'));
      expect(find.descendant(of: finished, matching: find.text('Packs finished')), findsOneWidget);
      expect(find.descendant(of: finished, matching: find.text('Pictures solved')), findsOneWidget);
      expect(find.descendant(of: finished, matching: find.text('8')), findsOneWidget);
      expect(find.descendant(of: finished, matching: find.text('Pack lib3')), findsOneWidget);
      expect(find.descendant(of: finished, matching: find.text('Pack lib2')), findsOneWidget);
      expect(find.text('A picture you have not played yet'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('See all').last);
      await tester.tap(find.text('See all').last);
      await tester.pumpAndSettle();
      expect(container.read(libraryFilterProvider), LibraryFilter.finished);
      expect(find.text('Library page'), findsOneWidget);
    });
  });
}
