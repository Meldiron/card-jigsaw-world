import 'dart:io';
import 'dart:ui' as ui;

import 'package:appwrite/models.dart' as models;
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/game/difficulty_screen.dart';
import 'package:carden/game/board.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/social.dart';
import 'package:carden/state/unlocks.dart';
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
/// overflowing, and a board in progress pins the choice behind Continue /
/// Discard progress until the save is thrown away.
void main() {
  Future<void> settle(WidgetTester tester, [int frames = 8]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  late LocalStore store;

  Future<GlobalKey> pumpScreen(WidgetTester tester, {required double width, required double height, Map<String, PuzzleProgress> progress = const {}, OpenFeatures open = OpenFeatures.all, Map<String, Object> prefs = const {}, bool router = false}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({...seededSave(progress: {for (final e in progress.entries) e.key: e.value.toData()}), ...prefs});
    store = await LocalStore.open();
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
        resolvedPuzzleProvider.overrideWith((ref, id) => Puzzle.custom(id: id, title: 'Test picture', imageUrl: '')),
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
        child: router ? MaterialApp.router(theme: AppTheme.light(), routerConfig: routes) : MaterialApp(theme: AppTheme.light(), home: const DifficultyScreen(puzzleId: 'p1')),
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
      expect(find.textContaining('· Play'), findsOneWidget);
      expect(find.text('Discard progress'), findsNothing);
      await dump(tester, key, 'difficulty_${w.toInt()}');
      expect(tester.takeException(), isNull, reason: 'no layout overflow');
    });
  }

  testWidgets('tier tiles name the boards dealt for the picture, in every mode', (tester) async {
    final key = await pumpScreen(tester, width: 402, height: 874);
    for (final mode in GameMode.values) {
      await tester.tap(find.text(mode.label));
      await settle(tester);
      // No picture in this test: the 3:4 reference ladder is shown.
      final tiers = BoardSpec.tiers(mode, BoardSpec.referenceAspect);
      for (final t in tiers.take(3)) {
        expect(find.text(t.code), findsWidgets, reason: '${mode.code} ${t.label} shows ${t.code}');
      }
      final relaxed = tiers[2];
      expect(find.textContaining('${relaxed.cells} '), findsWidgets, reason: 'the Play button counts the pieces of ${relaxed.fullCode}');
      await dump(tester, key, 'difficulty_mode_${mode.code}');
    }
    expect(tester.takeException(), isNull);
  });

  bool paintingOn(WidgetTester tester) => tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value;

  testWidgets('a new picture opens on the board chosen last: mode, size and Painting', (tester) async {
    await pumpScreen(tester, width: 402, height: 874, prefs: {'lastBoard': '{"mode":"squares","tier":0,"painting":true}'});
    final cozy = BoardSpec.tiers(GameMode.squares, BoardSpec.referenceAspect)[0];
    expect(find.text('${cozy.cells} squares · Play'), findsOneWidget, reason: 'Squares ${cozy.code} is preselected');
    expect(paintingOn(tester), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a board chosen yet the screen opens on Cards, Relaxed, no Painting', (tester) async {
    await pumpScreen(tester, width: 402, height: 874);
    final relaxed = BoardSpec.tiers(GameMode.cards, BoardSpec.referenceAspect)[2];
    expect(find.text('${relaxed.cells} cards · Play'), findsOneWidget);
    expect(paintingOn(tester), isFalse);
  });

  testWidgets('Play remembers the mode, size and Painting for the next picture', (tester) async {
    await pumpScreen(tester, width: 402, height: 874, router: true);
    await tester.tap(find.text('Triangles'));
    await settle(tester);
    final cozy = BoardSpec.tiers(GameMode.triangles, BoardSpec.referenceAspect)[0];
    await tester.tap(find.text(cozy.code).first);
    await settle(tester);
    await tester.tap(find.byType(CupertinoSwitch));
    await settle(tester);
    await tester.tap(find.text('${cozy.cells} triangles · Play'));
    await settle(tester);
    expect(find.textContaining('game /game/p1/'), findsOneWidget);
    final last = LastBoard.fromJson(store.getJson('lastBoard'));
    expect(last, const LastBoard(mode: 'triangles', tier: 0, painting: true));
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
    expect(find.textContaining('Continue · 7 moves in'), findsOneWidget);
    expect(find.text('Discard progress'), findsOneWidget);
    expect(find.byKey(const ValueKey('board-in-progress')), findsOneWidget);
    expect(find.textContaining('Squares · 4x5'), findsOneWidget);
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
    expect(find.textContaining('· Play'), findsOneWidget);
    expect(find.textContaining('board is in progress'), findsNothing);
    // The choice is open again: another mode can be picked.
    await tester.tap(find.text('Hexagons'));
    await settle(tester);
    expect(find.textContaining('hexagons · Play'), findsOneWidget);
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
    expect(find.textContaining('cards · Play'), findsOneWidget, reason: 'still on Cards');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a shape used before stays open below its level', (tester) async {
    final used = PuzzleProgress.fromRow('r2', {'userId': 'local', 'puzzleId': 'old', 'gridSize': 20, 'mode': 'hexagons', 'completed': true, 'stars': 3, 'completedAt': '2026-10-01T10:00:00Z'});
    await pumpScreen(tester, width: 402, height: 874, open: OpenFeatures.forPlayer(level: 1, progress: [used]));
    expect(find.text('Level ${Unlock.hexagons.level}'), findsNothing);
    expect(find.text('Level ${Unlock.squares.level}'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mode-hexagons')));
    await settle(tester);
    expect(find.textContaining('hexagons · Play'), findsOneWidget);
  });
}
