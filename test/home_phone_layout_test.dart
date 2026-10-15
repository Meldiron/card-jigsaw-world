// The real Home screen at phone sizes (SE and Pro), in both themes, at the default and the largest
// text size the app allows (1.35), in four player states: it renders and scrolls to the end without
// a layout error (overflow, unbounded flex). The test font is wider than SF, so a pass here leaves
// room on a phone.
import 'package:appwrite/models.dart' as models;
import 'package:card_jigsaw_world/core/theme/app_theme.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/features/home/home_screen.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/auth.dart';
import 'package:card_jigsaw_world/state/catalog.dart';
import 'package:card_jigsaw_world/state/profile.dart';
import 'package:card_jigsaw_world/state/progress.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:card_jigsaw_world/state/unlocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

Pack _pack(String id, {String category = 'Nature', int sortOrder = 0, Map<String, dynamic> extra = const {}}) =>
    Pack.fromRow(id, {'name': 'Pack $id', 'category': category, 'sortOrder': sortOrder, 'imageCount': 4, ...extra});

List<Puzzle> _pictures(String packId, int n) => [
      for (var i = 1; i <= n; i++) Puzzle.fromRow('$packId-$i', {'packId': packId, 'title': 'Picture $i', 'sortOrder': i}),
    ];

class _NoAuth extends AuthNotifier {
  @override
  Future<models.User?> build() async => null;
}

Map<String, dynamic> _patch = const {};

class _Profile extends ProfileNotifier {
  @override
  Future<Profile> build() async {
    final g = Profile.guest('local');
    return Profile.fromRow(g.id, {...g.toData(), ..._patch});
  }
}

class _Rows extends ProgressNotifier {
  _Rows(this.rows);
  final Map<String, PuzzleProgress> rows;
  @override
  Future<Map<String, PuzzleProgress>> build() async => rows;
}

void main() {
  final now = DateTime.now();
  final library = [for (var i = 1; i <= 7; i++) _pack('lib$i', sortOrder: 10 - i)];
  final event = _pack('evpack-ocean', sortOrder: 0, extra: {
    'startAt': now.subtract(const Duration(days: 1)).toIso8601String(),
    'endAt': now.add(const Duration(days: 3)).toIso8601String(),
  });
  final month = _pack('daily-2026-10', category: 'Daily', sortOrder: -1);
  final packs = [month, event, ...library];
  final pictures = [for (final p in packs) ..._pictures(p.id, 4)];
  final rows = {
    'lib1-1': PuzzleProgress.fromRow('r1', {'userId': 'u', 'puzzleId': 'lib1-1', 'gridSize': 16, 'completed': true, 'stars': 2, 'completedAt': now.toIso8601String()}),
    'lib2-1': PuzzleProgress.fromRow('r2', {'userId': 'u', 'puzzleId': 'lib2-1', 'gridSize': 16, 'completed': false, 'stars': 0, 'layout': '1,0,2,3,4,5,6,7,8,9,10,11,12,13,14,15', 'mode': 'cards', 'moves': 3}),
  };
  String ago(int days) => now.subtract(Duration(days: days)).toUtc().toIso8601String();
  final states = <String, Map<String, dynamic>>{
    'new guest': const {},
    'missed day, restore offered': {'streak': 46, 'longestStreak': 60, 'lastDailyClaim': ago(2), 'tickets': 12, 'coins': 1234567, 'xp': 90500, 'level': 24, 'piggyCoins': 500},
    'claimed today': {'streak': 6, 'longestStreak': 6, 'lastDailyClaim': now.toUtc().toIso8601String(), 'tickets': 3, 'coins': 18950},
    'VIP': {'isVip': true, 'streak': 3, 'lastDailyClaim': ago(1)},
  };
  for (final size in const [Size(375, 667), Size(402, 874)]) {
    for (final dark in [false, true]) {
      for (final scale in const [1.0, 1.35]) {
        for (final s in states.entries) {
          testWidgets('Home ${size.width.toInt()}x${size.height.toInt()} ${dark ? 'dark' : 'light'} text ${scale}x: ${s.key}', (tester) async {
            _patch = s.value;
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
            final router = GoRouter(initialLocation: '/home', routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]);
            await tester.pumpWidget(ProviderScope(
              overrides: [
                localStoreProvider.overrideWithValue(store),
                authProvider.overrideWith(_NoAuth.new),
                profileProvider.overrideWith(_Profile.new),
                progressProvider.overrideWith(() => _Rows(rows)),
                packsProvider.overrideWith((ref) async => packs),
                allPuzzlesProvider.overrideWith((ref) async => pictures),
                eventsProvider.overrideWith((ref) async => const <GameEvent>[]),
                // A level-24 player would first see the intro sheet of a feature that just opened.
                pendingUnlockIntroProvider.overrideWithValue(null),
              ],
              child: MediaQuery(
                data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
                child: MaterialApp.router(theme: dark ? AppTheme.dark() : AppTheme.light(), routerConfig: router),
              ),
            ));
            await tester.pumpAndSettle();
            expect(find.byType(CustomScrollView), findsWidgets, reason: 'Home renders');
            // Scroll through the whole page; every card builds on the way.
            var sawTiles = false;
            for (var i = 0; i < 14; i++) {
              sawTiles |= find.text('Lucky Wheel').evaluate().isNotEmpty && find.text('Piggy bank').evaluate().isNotEmpty;
              await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -500));
              await tester.pumpAndSettle();
            }
            FlutterError.onError = previous;
            expect(sawTiles, isTrue, reason: 'the Lucky Wheel and Piggy bank tiles were on the page');
            expect(errors, isEmpty);
          });
        }
      }
    }
  }
}
