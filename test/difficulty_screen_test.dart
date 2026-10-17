import 'dart:io';
import 'dart:ui' as ui;

import 'package:appwrite/models.dart' as models;
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/difficulty_screen.dart';
import 'package:carden/game/board.dart';
import 'package:carden/game/image_loader.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/profile.dart' show Economy;
import 'package:carden/state/rewards.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/social.dart';
import 'package:carden/state/unlocks.dart';
import 'package:carden/widgets/cached_url_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/seed_save.dart';

class _NoAuth extends AuthNotifier {
  @override
  Future<models.User?> build() async => null;
}

/// The pre-game screen offline: the rewards row lays out at 320 pt without
/// overflowing, square boards in every mode, Expand for a picture of another
/// shape, and a board in progress pins the choice behind Continue / Discard
/// progress until the save is thrown away.
void main() {
  Future<void> settle(WidgetTester tester, [int frames = 8]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  late LocalStore store;

  /// With [picture] (width x height), the screen has a decoded picture of that shape.
  Future<GlobalKey> pumpScreen(WidgetTester tester, {required double width, required double height, Map<String, PuzzleProgress> progress = const {}, OpenFeatures open = OpenFeatures.all, Map<String, Object> prefs = const {}, bool router = false, (int, int)? picture, double textScale = 1}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({...seededSave(progress: {for (final e in progress.entries) e.key: e.value.toData()}), ...prefs});
    store = await LocalStore.open();
    final image = picture == null ? null : await tester.runAsync(() => createTestImage(width: picture.$1, height: picture.$2));
    // The preview's own copy of the picture comes from the image cache, not the network.
    if (image != null) {
      imageCache.clear();
      imageCache.putIfAbsent(const CachedUrlImage('test://picture'), () => OneFrameImageStreamCompleter(SynchronousFuture(ImageInfo(image: image.clone()))));
    }
    final key = GlobalKey();
    // With [router], Play can leave for the game (a stand-in page).
    final routes = GoRouter(initialLocation: '/play/p1', routes: [
      GoRoute(path: '/play/:id', builder: (_, s) => DifficultyScreen(puzzleId: s.pathParameters['id']!)),
      GoRoute(path: '/game/:id/:grid', builder: (_, s) => Scaffold(body: Text('game ${s.uri}'))),
    ]);
    if (router) addTearDown(routes.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        authProvider.overrideWith(_NoAuth.new),
        resolvedPuzzleProvider.overrideWith((ref, id) => Puzzle.custom(id: id, title: 'Test picture', imageUrl: image == null ? '' : 'test://picture')),
        if (image != null) puzzleImageProvider.overrideWith((ref, url) async => image),
        // Offline: the catalogue is empty instead of a network call.
        packsProvider.overrideWith((ref) async => const <Pack>[]),
        allPuzzlesProvider.overrideWith((ref) async => const <Puzzle>[]),
        publicPacksProvider.overrideWith((ref) async => const <Pack>[]),
        publicPuzzlesProvider.overrideWith((ref) async => const <Puzzle>[]),
        // Every shape and option open unless a test says otherwise (they open as levels rise).
        openFeaturesProvider.overrideWithValue(open),
        // No first-time intro sheets over the choices.
        pendingUnlockIntroProvider.overrideWithValue(null),
      ],
      child: RepaintBoundary(
        key: key,
        child: MediaQuery(
          data: MediaQueryData(size: Size(width, height), textScaler: TextScaler.linear(textScale)),
          child: router ? MaterialApp.router(theme: AppTheme.light(), routerConfig: routes) : MaterialApp(theme: AppTheme.light(), home: const DifficultyScreen(puzzleId: 'p1')),
        ),
      ),
    ));
    await settle(tester, 12);
    return key;
  }

  Future<void> dump(WidgetTester tester, GlobalKey key, String name) async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final img = await boundary.toImage();
      final png = (await img.toByteData(format: ui.ImageByteFormat.png))!;
      final dir = Directory(Platform.environment['CJW_RENDER_DIR'] ?? 'build/board_shapes');
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png').writeAsBytes(png.buffer.asUint8List());
    });
  }

  for (final (w, h) in [(320.0, 700.0), (402.0, 874.0)]) {
    testWidgets('rewards row fits at ${w.toInt()} pt', (tester) async {
      final key = await pumpScreen(tester, width: w, height: h);
      expect(find.text('Mode'), findsOneWidget);
      // The rewards sit in the footer, next to Play, without scrolling.
      expect(find.textContaining('up to'), findsOneWidget);
      expect(find.textContaining(' XP'), findsOneWidget);
      expect(find.text('+5'), findsOneWidget);
      // Just the word: no icon, no count (owner, 2026-10-17).
      expect(find.text('Play'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('play-board')), matching: find.byType(Icon)), findsNothing);
      expect(find.text('Discard progress'), findsNothing);
      await dump(tester, key, 'difficulty_${w.toInt()}');
      expect(tester.takeException(), isNull, reason: 'no layout overflow');
    });
  }

  /// The rewards line's XP: it names the board chosen.
  Finder xpOf(BoardSpec spec, {bool painting = false}) => find.text('${Economy.completionXp(spec.cells, 3, mode: spec.mode, painting: painting)} XP');

  testWidgets('tier tiles name the square boards in every mode', (tester) async {
    final key = await pumpScreen(tester, width: 402, height: 874);
    for (final mode in GameMode.values) {
      await tester.tap(find.text(mode.label));
      await settle(tester);
      // The first sizes (the row scrolls sideways).
      for (final t in BoardSpec.squareTiers(mode).take(3)) {
        expect(find.text(t.size), findsWidgets, reason: '${mode.code} ${t.label} shows ${t.size}');
        expect(t.size, '${t.rows}x${t.rows}');
      }
      // No picture yet: no Expand.
      expect(find.byKey(const ValueKey('expand-option')), findsNothing);
      // Relaxed, or the size next to it (Hexagons start at 5x5).
      expect(xpOf(BoardSpec.forPicture(mode, 2, BoardSpec.referenceAspect)), findsOneWidget, reason: mode.code);
      await dump(tester, key, 'difficulty_mode_${mode.code}');
    }
    expect(tester.takeException(), isNull);
  });

  bool paintingOn(WidgetTester tester) => tester.widget<CupertinoSwitch>(find.descendant(of: find.byKey(const ValueKey('painting-option')), matching: find.byType(CupertinoSwitch))).value;

  testWidgets('a new picture opens on the board chosen last: mode, size and Painting', (tester) async {
    await pumpScreen(tester, width: 402, height: 874, prefs: {'lastBoard': '{"mode":"squares","tier":0,"painting":true}'});
    final cozy = BoardSpec.squareTiers(GameMode.squares)[0];
    expect(xpOf(cozy, painting: true), findsOneWidget, reason: 'Squares ${cozy.code} is preselected');
    expect(paintingOn(tester), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a board chosen yet the screen opens on Cards, Relaxed, no Painting', (tester) async {
    await pumpScreen(tester, width: 402, height: 874);
    final relaxed = BoardSpec.squareTiers(GameMode.cards)[1];
    expect(relaxed.code, '4x4');
    expect(xpOf(relaxed), findsOneWidget);
    expect(paintingOn(tester), isFalse);
  });

  testWidgets('Play remembers the mode, size and Painting for the next picture', (tester) async {
    await pumpScreen(tester, width: 402, height: 874, router: true);
    await tester.tap(find.text('Triangles'));
    await settle(tester);
    final relaxed = BoardSpec.squareTiers(GameMode.triangles)[0];
    expect(relaxed.size, '4x4');
    await tester.tap(find.text(relaxed.size).first);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('painting-option')));
    await settle(tester);
    await tester.tap(find.text('Play'));
    await settle(tester);
    expect(find.text('game /game/p1/triangles-9x4t2?painting=1'), findsOneWidget);
    final last = LastBoard.fromJson(store.getJson('lastBoard'));
    expect(last, const LastBoard(mode: 'triangles', tier: 2, painting: true));
  });

  test('the last board survives a round trip through the store', () {
    const giant = LastBoard(mode: 'squares', tier: 3, giantTier: BoardSpec.firstGiantTier + 1, painting: true);
    expect(LastBoard.fromJson(giant.toJson()), giant);
    expect(LastBoard.fromJson(const {'mode': 'cards'}), isNull, reason: 'an incomplete entry is ignored');
  });

  testWidgets('a saved board pins the choice; Discard progress reopens it', (tester) async {
    final saved = PuzzleProgress.fromRow('r1', {
      'userId': 'local',
      'puzzleId': 'p1',
      'gridSize': 20,
      'mode': 'squares',
      'layout': List.generate(20, (i) => (i + 1) % 20).join(','),
      'moves': 7,
      'elapsedSeconds': 40,
    });
    expect(saved.inProgress, isTrue);
    final key = await pumpScreen(tester, width: 402, height: 874, progress: {'p1': saved});
    expect(find.text('Continue'), findsOneWidget);
    expect(find.textContaining('7 moves'), findsOneWidget, reason: 'the moves are on the card above');
    expect(find.text('Discard progress'), findsOneWidget);
    expect(find.byKey(const ValueKey('board-in-progress')), findsOneWidget);
    expect(find.textContaining('Squares · 4x5'), findsOneWidget, reason: 'a 4x5 board saved before square boards resumes as it was');
    await dump(tester, key, 'difficulty_in_progress');
    // The pickers wait until the save is discarded.
    expect(find.text('Hexagons'), findsNothing);

    await tester.tap(find.text('Discard progress'));
    await settle(tester);
    expect(find.text('Discard progress?'), findsOneWidget);
    await dump(tester, key, 'difficulty_discard_alert');
    await tester.tap(find.text('Discard'));
    await settle(tester, 15);
    expect(find.text('Discard progress'), findsNothing);
    expect(find.text('Play'), findsOneWidget);
    expect(find.textContaining('board is in progress'), findsNothing);
    // The choice is open again: another mode can be picked.
    await tester.tap(find.text('Hexagons'));
    await settle(tester);
    expect(find.text('5x5'), findsWidgets);
    expect(find.text('Play'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a level 1 player sees the other shapes and Painting locked with their levels', (tester) async {
    final key = await pumpScreen(tester, width: 402, height: 874, open: OpenFeatures.forPlayer(level: 1));
    expect(find.text('Level ${Unlock.squares.level}'), findsOneWidget);
    expect(find.text('Level ${Unlock.triangles.level}'), findsOneWidget);
    expect(find.text('Level ${Unlock.hexagons.level}'), findsOneWidget);
    // Painting: a "[lock] Level 8" chip, and one line on what it is.
    expect(find.text('Level ${Unlock.painting.level}'), findsOneWidget);
    expect(find.text('Black and white until cards lock'), findsOneWidget);
    await dump(tester, key, 'difficulty_level1_locked');
    // A locked shape explains itself instead of being picked.
    await tester.tap(find.byKey(const ValueKey('mode-squares')));
    await settle(tester);
    expect(find.text('Squares open at level ${Unlock.squares.level}'), findsOneWidget);
    expect(find.textContaining('XP to go'), findsOneWidget);
    await dump(tester, key, 'difficulty_locked_info');
    await tester.tap(find.text('Got it'));
    await settle(tester);
    expect(xpOf(BoardSpec.squareTiers(GameMode.cards)[1]), findsOneWidget, reason: 'still on Cards');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a shape used before stays open below its level', (tester) async {
    final used = PuzzleProgress.fromRow('r2', {'userId': 'local', 'puzzleId': 'old', 'gridSize': 20, 'mode': 'hexagons', 'completed': true, 'stars': 3, 'completedAt': '2026-10-01T10:00:00Z'});
    await pumpScreen(tester, width: 402, height: 874, open: OpenFeatures.forPlayer(level: 1, progress: [used]));
    expect(find.text('Level ${Unlock.hexagons.level}'), findsNothing);
    expect(find.text('Level ${Unlock.squares.level}'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mode-hexagons')));
    await settle(tester);
    // Hexagons start at 5x5 (Tricky, level 3): a shape's smallest size is always open.
    expect(xpOf(BoardSpec.squareTiers(GameMode.hexagons).first), findsOneWidget);
  });

  bool expandOn(WidgetTester tester) => tester.widget<CupertinoSwitch>(find.descendant(of: find.byKey(const ValueKey('expand-option')), matching: find.byType(CupertinoSwitch))).value;

  testWidgets('a tall picture: square boards crop it, Expand lays the sizes out for it and is remembered', (tester) async {
    final key = await pumpScreen(tester, width: 402, height: 874, router: true, picture: (900, 1200), prefs: {'lastBoard': '{"mode":"squares","tier":2,"painting":false}'});
    const aspect = 900 / 1200;
    // Squares: 4x4 is preselected, the preview is the square crop, and Expand is offered, off.
    expect(find.byKey(const ValueKey('expand-option')), findsOneWidget);
    expect(expandOn(tester), isFalse);
    for (final t in BoardSpec.squareTiers(GameMode.squares).take(3)) {
      expect(find.text(t.size), findsOneWidget);
    }
    expect(xpOf(BoardSpec.squareTiers(GameMode.squares)[1]), findsOneWidget);
    await dump(tester, key, 'difficulty_tall_square');
    // Expand: the same sizes laid out for the picture.
    await tester.tap(find.byKey(const ValueKey('expand-option')));
    await settle(tester);
    expect(expandOn(tester), isTrue);
    final expand = BoardSpec.expandTiers(GameMode.squares, aspect);
    for (final t in expand.take(3)) {
      expect(find.text(t.size), findsOneWidget, reason: '${t.label} becomes ${t.size}');
    }
    final relaxed = expand.firstWhere((t) => t.tier == 2);
    expect(xpOf(relaxed), findsOneWidget, reason: 'Relaxed stays chosen');
    await dump(tester, key, 'difficulty_tall_expand');
    // Cards suit a 3:4 picture: no Expand there.
    await tester.tap(find.text('Cards'));
    await settle(tester);
    expect(find.byKey(const ValueKey('expand-option')), findsNothing);
    expect(find.text('4x4'), findsOneWidget);
    await tester.tap(find.text('Squares'));
    await settle(tester);
    await tester.tap(find.text('Play'));
    await settle(tester);
    expect(find.text('game /game/p1/${BoardCode.toPath(relaxed.fullCode)}?expand=1'), findsOneWidget);
    expect(LastBoard.fromJson(store.getJson('lastBoard')), const LastBoard(mode: 'squares', tier: 2, expand: true));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a square picture in Squares has no Expand; Expand remembered on stays chosen for the next picture', (tester) async {
    await pumpScreen(tester, width: 402, height: 874, router: true, picture: (1000, 1000), prefs: {'lastBoard': '{"mode":"squares","tier":2,"painting":false,"expand":true}'});
    expect(find.byKey(const ValueKey('expand-option')), findsNothing);
    expect(find.text('4x4'), findsOneWidget);
    await tester.tap(find.text('Play'));
    await settle(tester);
    expect(find.text('game /game/p1/squares-4x4t2?expand=1'), findsOneWidget);
  });

  testWidgets('a wide picture (a My Puzzles photo): square boards in Squares and Hexagons, Expand for Cards', (tester) async {
    final key = await pumpScreen(tester, width: 402, height: 874, picture: (1500, 1000), prefs: {'lastBoard': '{"mode":"squares","tier":2,"painting":false}'});
    // Expand would crop a landscape picture to a square board too: not offered in Squares.
    expect(find.byKey(const ValueKey('expand-option')), findsNothing);
    await dump(tester, key, 'difficulty_wide_squares');
    // A square honeycomb is wide already.
    await tester.tap(find.text('Hexagons'));
    await settle(tester);
    expect(find.byKey(const ValueKey('expand-option')), findsNothing);
    await dump(tester, key, 'difficulty_wide_hexagons');
    // Cards: 5:7 boards crop a wide picture by half; Expand lays them out square.
    await tester.tap(find.text('Cards'));
    await settle(tester);
    expect(find.byKey(const ValueKey('expand-option')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('expand-option')));
    await settle(tester);
    final relaxed = BoardSpec.expandTiers(GameMode.cards, 1.5).firstWhere((t) => t.tier == 2);
    expect(relaxed.cols, greaterThan(relaxed.rows));
    expect(xpOf(relaxed), findsOneWidget);
    await dump(tester, key, 'difficulty_wide_cards_expand');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Expand at the largest text on the SE frame', (tester) async {
    final key = await pumpScreen(tester, width: 375, height: 667, picture: (900, 1200), textScale: 2, prefs: {'lastBoard': '{"mode":"squares","tier":2,"painting":false,"expand":true}'});
    expect(find.byKey(const ValueKey('expand-option')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('expand-option')), 100, scrollable: find.byType(Scrollable).first);
    await settle(tester);
    await dump(tester, key, 'difficulty_expand_se_largest');
    expect(tester.takeException(), isNull, reason: 'no layout overflow');
  });
}
