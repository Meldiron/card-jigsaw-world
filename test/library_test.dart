import 'package:appwrite/models.dart' as models;
import 'package:card_jigsaw_world/core/theme/app_theme.dart';
import 'package:card_jigsaw_world/core/theme/tokens.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/features/gallery/giant_gate.dart';
import 'package:card_jigsaw_world/features/gallery/library_screen.dart';
import 'package:card_jigsaw_world/features/gallery/pack_progress.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/auth.dart';
import 'package:card_jigsaw_world/state/catalog.dart';
import 'package:card_jigsaw_world/state/profile.dart';
import 'package:card_jigsaw_world/state/progress.dart';
import 'package:card_jigsaw_world/state/rewards.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:card_jigsaw_world/widgets/icons.dart';
import 'package:card_jigsaw_world/widgets/ui.dart';
import 'package:flutter/cupertino.dart';
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

Pack _pack(String id, String name, {String category = 'Nature', String description = '', int images = 4, DateTime? startAt, DateTime? endAt}) => Pack.fromRow(id, {
      'name': name,
      'category': category,
      'description': description,
      'imageCount': images,
      'isFree': true,
      'startAt': startAt?.toIso8601String(),
      'endAt': endAt?.toIso8601String(),
    });

List<Puzzle> _pictures(String packId, int n) => [
      for (var i = 1; i <= n; i++) Puzzle.fromRow('$packId-$i', {'packId': packId, 'title': 'Picture $i', 'sortOrder': i}),
    ];

PuzzleProgress _solved(String puzzleId) =>
    PuzzleProgress.fromRow('row-$puzzleId', {'userId': 'local', 'puzzleId': puzzleId, 'gridSize': 9, 'completed': true, 'stars': 3});

PuzzleProgress _playing(String puzzleId) =>
    PuzzleProgress.fromRow('row-$puzzleId', {'userId': 'local', 'puzzleId': puzzleId, 'gridSize': 9, 'completed': false, 'layout': '1,0,2,3,4,5,6,7,8', 'moves': 3});

void main() {
  final now = DateTime.now();
  final packs = [
    _pack('nature', 'Wild Nature', description: 'Waterfalls and forests'),
    _pack('cities', 'Kraków Old Town', category: 'Travel', description: 'Squares and towers'),
    _pack('coast', 'Quiet Coast', category: 'Travel', description: 'Wild beaches at dawn'),
    _pack('ev-live', 'World Food Day', category: 'Food', startAt: now.subtract(const Duration(days: 2)), endAt: now.add(const Duration(days: 3))),
    _pack('ev-old', 'World Tea Day', category: 'Food', startAt: now.subtract(const Duration(days: 30)), endAt: now.subtract(const Duration(days: 23))),
    _pack('daily-2026-10', 'October 2026', category: 'Daily', images: 31),
  ];
  final pictures = [for (final p in packs) ..._pictures(p.id, p.imageCount)];
  final rows = {
    for (var i = 1; i <= 4; i++) 'nature-$i': _solved('nature-$i'), // finished
    for (var i = 1; i <= 4; i++) 'ev-old-$i': _solved('ev-old-$i'), // finished, event over
    'cities-1': _solved('cities-1'), // begun
    'coast-2': _playing('coast-2'), // a board in progress
  };
  final progress = {
    for (final p in packs) p.id: PackProgress.of(pictures.where((z) => z.packId == p.id).toList(), rows),
  };
  List<String> ids(List<Pack> l) => l.map((p) => p.id).toList();
  List<Pack> view(String filter, {bool hide = false, String query = ''}) =>
      libraryPacks(packs, filter: filter, progress: progress, isUnlocked: (p) => p.id != 'coast', hideFinished: hide, query: query);

  group('Library chips', () {
    test('special views first, then Daily and the library categories; no Events chip', () {
      expect(libraryChips(packs, showUnlocked: true), ['All', 'Finished', 'Started', 'Unlocked', 'Daily', 'Nature', 'Travel']);
      expect(libraryChips(packs, showUnlocked: false), ['All', 'Finished', 'Started', 'Daily', 'Nature', 'Travel']);
    });

    test('the kinds of pack lead the categories: Daily, Giant, AI; never Event', () {
      final more = [
        ...packs,
        _pack('abstract', 'Stained Glass', category: 'Abstract'),
        _pack('ai-cats', 'AI Cats', category: 'AI'),
        _pack('houses', 'Colourful Houses', category: 'Giant'),
        _pack('ev-food', 'World Bread Day', category: 'Event', startAt: now.subtract(const Duration(days: 1)), endAt: now.add(const Duration(days: 5))),
        _pack('stray', 'Stray event row', category: 'Event'),
      ];
      expect(libraryChips(more, showUnlocked: false), ['All', 'Finished', 'Started', 'Daily', 'Giant', 'AI', 'Nature', 'Travel', 'Abstract']);
    });

    test('views and the kinds of pack carry an icon; themed categories do not', () {
      for (final chip in [...LibraryFilter.special, ...LibraryFilter.kinds]) {
        expect(libraryChipIcon(chip), isNotNull, reason: chip);
      }
      expect(libraryChipIcon('Travel'), isNull);
      expect(libraryChipIcon('Event'), isNull);
      expect(libraryChipIcon(LibraryFilter.fresh), isNot(AppIcons.category(LibraryFilter.ai)), reason: 'New and AI must not share a mark');
    });
  });

  group('Library filters', () {
    test('Finished: every picture solved, ended events included', () {
      expect(ids(view(LibraryFilter.finished)), ['nature', 'ev-old']);
    });

    test('Started: begun and not finished', () {
      expect(ids(view(LibraryFilter.started)), ['cities', 'coast']);
    });

    test('All and Unlocked keep their order; ended events stay out of All', () {
      expect(ids(view(LibraryFilter.all)), ['nature', 'cities', 'coast', 'ev-live', 'daily-2026-10']);
      expect(ids(view(LibraryFilter.unlocked)), ['nature', 'cities', 'ev-live', 'daily-2026-10']);
    });

    test('Hide finished drops finished packs everywhere except Finished', () {
      expect(ids(view(LibraryFilter.all, hide: true)), ['cities', 'coast', 'ev-live', 'daily-2026-10']);
      expect(ids(view('Nature', hide: true)), isEmpty);
      expect(ids(view(LibraryFilter.finished, hide: true)), ['nature', 'ev-old']);
    });
  });

  group('Library search', () {
    test('folds case, accents and apostrophes', () {
      expect(foldForSearch('Kraków'), 'krakow');
      expect(foldForSearch("World's Café"), 'worlds cafe');
      expect(foldForSearch('Sci-Fi'), 'sci fi');
    });

    test('matches names, categories and descriptions; every word must match; names first', () {
      expect(ids(view(LibraryFilter.all, query: 'KRAKOW')), ['cities']);
      expect(ids(view(LibraryFilter.all, query: 'travel')), ['cities', 'coast']);
      expect(ids(view(LibraryFilter.all, query: 'wild')), ['nature', 'coast'], reason: 'name match first, description match after');
      expect(ids(view(LibraryFilter.all, query: 'wild beaches')), ['coast']);
      expect(ids(view(LibraryFilter.all, query: '  ')), ids(view(LibraryFilter.all)));
      expect(view(LibraryFilter.all, query: 'zebra'), isEmpty);
    });

    test('combines with the filter and the toggle', () {
      expect(ids(view('Travel', query: 'old')), ['cities']);
      expect(ids(view(LibraryFilter.all, query: 'wild', hide: true)), ['coast']);
    });
  });

  group('Library screen', () {
    Future<ProviderContainer> pump(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
      // Wide enough for every chip, tall enough for the whole grid.
      tester.view.physicalSize = const Size(1000, 4200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(prefs);
      final store = await LocalStore.open();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          authProvider.overrideWith(_NoAuth.new),
          profileProvider.overrideWith(_GuestProfile.new),
          progressProvider.overrideWith(() => _Rows(rows)),
          packsProvider.overrideWith((ref) async => packs),
          allPuzzlesProvider.overrideWith((ref) async => pictures),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const LibraryScreen()),
      ));
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)));
    }

    Finder chip(String label) => find.byKey(ValueKey('library-chip-$label'));

    testWidgets('toggle hides finished packs and is replaced by the count in Finished', (tester) async {
      final container = await pump(tester);
      expect(find.text('Hide finished'), findsOneWidget);
      expect(find.textContaining('solved'), findsNothing);
      expect(find.descendant(of: chip('Finished'), matching: find.byIcon(AppIcons.filterFinished)), findsOneWidget);
      expect(find.descendant(of: chip('Travel'), matching: find.byType(Icon)), findsNothing);
      expect(find.text('Wild Nature'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('library-hide-finished')));
      await tester.pumpAndSettle();
      expect(find.text('Wild Nature'), findsNothing);
      expect(container.read(settingsProvider).hideFinished, isTrue);
      expect(container.read(localStoreProvider).getJson('libraryPrefs'), {'hideFinished': true});

      await tester.tap(chip('Finished'));
      await tester.pumpAndSettle();
      expect(find.text('Hide finished'), findsNothing);
      expect(find.text('2 finished'), findsOneWidget);
      expect(find.text('Wild Nature'), findsOneWidget);
      expect(find.text('World Tea Day'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the toggle is remembered, and an emptied view offers to show finished packs', (tester) async {
      final container = await pump(tester, prefs: {'libraryPrefs': '{"hideFinished":true}'});
      expect(container.read(settingsProvider).hideFinished, isTrue);
      await tester.tap(chip('Nature'));
      await tester.pumpAndSettle();
      expect(find.text('Every pack here is finished'), findsOneWidget);
      await tester.tap(find.text('Show finished'));
      await tester.pumpAndSettle();
      expect(find.text('Wild Nature'), findsOneWidget);
      expect(container.read(settingsProvider).hideFinished, isFalse);
    });

    testWidgets('search narrows the grid and explains an empty result', (tester) async {
      final container = await pump(tester);
      await tester.enterText(find.byType(CupertinoSearchTextField), 'krakow');
      await tester.pumpAndSettle();
      expect(find.text('Kraków Old Town'), findsOneWidget);
      expect(find.text('Wild Nature'), findsNothing);
      expect(find.text('My Puzzles'), findsNothing);

      await tester.tap(chip('Nature'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing found'), findsOneWidget);
      await tester.tap(find.text('Search all packs'));
      await tester.pumpAndSettle();
      expect(container.read(libraryFilterProvider), LibraryFilter.all);
      expect(find.text('Kraków Old Town'), findsOneWidget);

      await tester.enterText(find.byType(CupertinoSearchTextField), 'zebra');
      await tester.pumpAndSettle();
      expect(find.text('Nothing found'), findsOneWidget);
      expect(find.textContaining('"zebra"'), findsOneWidget);
    });

    testWidgets('a filter that is no longer offered falls back to All', (tester) async {
      final container = await pump(tester);
      container.read(libraryFilterProvider.notifier).select('Events');
      await tester.pumpAndSettle();
      expect(chip('Events'), findsNothing);
      expect(find.text('Hide finished'), findsOneWidget);
      expect(find.text('Wild Nature'), findsOneWidget);
    });
  });

  group('Ticket on filled buttons', () {
    Future<Color?> inkOf(WidgetTester tester, Widget button) async {
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: Center(child: button))));
      return CurrencyInk.of(tester.element(find.byType(TicketIcon)));
    }

    testWidgets('a ticket on a cobalt or tinted button takes the label colour', (tester) async {
      expect(await inkOf(tester, BigButton.cost(label: 'Unlock for', currency: Currency.tickets, amount: 10, onTap: () {})), Colors.white);
      expect(await inkOf(tester, BigButton.cost(label: 'Unlock for', currency: Currency.tickets, amount: 10, kind: ButtonKind.secondary, onTap: () {})), Brand.accent);
      expect(
        await inkOf(tester, BigButton(label: 'Restore for', trailing: const Amount(currency: Currency.tickets, value: 3, color: Colors.white), onTap: () {})),
        Colors.white,
        reason: 'a trailing Amount is covered too',
      );
    });

    testWidgets('a ticket on a plain surface or a ghost button keeps its colours', (tester) async {
      expect(await inkOf(tester, BigButton.cost(label: 'Spin for', currency: Currency.tickets, amount: 1, kind: ButtonKind.ghost, onTap: () {})), isNull);
      expect(await inkOf(tester, const Amount(currency: Currency.tickets, value: 3)), isNull);
    });
  });

  group('Giant pack gate (027)', () {
    Future<void> pumpGate(WidgetTester tester, GiantGate gate, {VoidCallback? onOpenNow}) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: Scaffold(body: Padding(padding: const EdgeInsets.all(20), child: GiantGateCard(gate: gate, onOpenNow: onOpenNow ?? () {})))));
      await tester.pumpAndSettle();
    }

    testWidgets('level 5: at level 10 for the usual 12, or now for 12 + 5, side by side', (tester) async {
      var tapped = false;
      final xp = LevelRewards.xpToReach(5);
      await pumpGate(tester, GiantGate(xp: xp, price: 12 + Economy.giantEarlyFee(5), packTickets: 12, owned: false, balance: 4), onOpenNow: () => tapped = true);
      expect(find.text('Giant boards open at level 10'), findsOneWidget);
      expect(find.text('Level 5'), findsOneWidget);
      expect(find.text('At level 10'), findsOneWidget);
      expect(find.text('The usual price'), findsOneWidget);
      expect(find.text('Now'), findsOneWidget);
      expect(find.text('5 levels early'), findsOneWidget);
      expect(find.text('17'), findsNWidgets(2), reason: 'the Now tile and the button');
      expect(find.text('You have 4 tickets'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('giant-open-now')));
      expect(tapped, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a pack the player has (VIP): the wait is included, now costs the levels only', (tester) async {
      await pumpGate(tester, GiantGate(xp: LevelRewards.xpToReach(9), price: Economy.giantEarlyFee(9), packTickets: 0, owned: true, balance: 20));
      expect(find.text('Included'), findsOneWidget);
      expect(find.text('1 level early'), findsOneWidget);
      expect(find.textContaining('You have'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
