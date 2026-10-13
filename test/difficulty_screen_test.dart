import 'dart:io';
import 'dart:ui' as ui;

import 'package:appwrite/models.dart' as models;
import 'package:card_jigsaw_world/core/theme/app_theme.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/features/game/difficulty_screen.dart';
import 'package:card_jigsaw_world/game/board.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/auth.dart';
import 'package:card_jigsaw_world/state/catalog.dart';
import 'package:card_jigsaw_world/state/rewards.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:card_jigsaw_world/state/social.dart';
import 'package:card_jigsaw_world/state/unlocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  Future<GlobalKey> pumpScreen(WidgetTester tester, {required double width, required double height, Map<String, PuzzleProgress> progress = const {}, OpenFeatures open = OpenFeatures.all}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(seededSave(progress: {for (final e in progress.entries) e.key: e.value.toData()}));
    final store = await LocalStore.open();
    final key = GlobalKey();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        authProvider.overrideWith(_NoAuth.new),
        resolvedPuzzleProvider.overrideWith((ref, id) => Puzzle.custom(id: id, title: 'Test picture', imageUrl: '')),
        // Offline: the catalogue is empty instead of a network call.
        packsProvider.overrideWith((ref) async => const <Pack>[]),
        allPuzzlesProvider.overrideWith((ref) async => const <Puzzle>[]),
        // Every shape and option open unless a test says otherwise (they open as levels rise).
        openFeaturesProvider.overrideWithValue(open),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(theme: AppTheme.light(), home: const DifficultyScreen(puzzleId: 'p1')),
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
      expect(find.text('Choose a mode'), findsOneWidget);
      // Scroll the rewards card into view.
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -900));
      await settle(tester);
      expect(find.text('Rewards'), findsOneWidget);
      expect(find.textContaining('up to '), findsOneWidget);
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
    expect(find.textContaining('board is in progress'), findsOneWidget);
    await dump(tester, key, 'difficulty_in_progress');
    // Mode tiles do not react while the save exists.
    await tester.tap(find.text('Hexagons'));
    await settle(tester);
    expect(find.textContaining('A squares 4x5 board is in progress'), findsOneWidget);

    await tester.tap(find.text('Discard progress'));
    await settle(tester);
    expect(find.text('Discard progress?'), findsOneWidget);
    await dump(tester, key, 'difficulty_discard_alert');
    await tester.tap(find.text('Discard'));
    await settle(tester, 15);
    expect(find.text('Discard progress'), findsNothing);
    expect(find.textContaining('· Play'), findsOneWidget);
    expect(find.text('Every mode cuts the picture differently. Trickier shapes pay more.'), findsOneWidget);
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
    expect(find.textContaining('Opens at level ${Unlock.painting.level}'), findsOneWidget);
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
