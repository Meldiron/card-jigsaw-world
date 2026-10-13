import 'dart:math';

import 'package:card_jigsaw_world/game/board.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/quick_play.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 13, 9);

Pack _pack(String id, {String category = 'Nature'}) => Pack.fromRow(id, {'name': id, 'category': category});

List<Puzzle> _pictures(String packId, int n, {DateTime? firstDay}) => [
      for (var i = 1; i <= n; i++)
        Puzzle.fromRow('$packId-$i', {
          'packId': packId,
          'title': 'Picture $i',
          'sortOrder': i,
          if (firstDay != null) 'date': firstDay.add(Duration(days: i - 1)).toIso8601String(),
        }),
    ];

PuzzleProgress _row(String puzzleId, {bool completed = true, int stars = 3, String mode = 'cards', int cells = 16, DateTime? at, String layout = ''}) =>
    PuzzleProgress.fromRow('row-$puzzleId', {
      'userId': 'u',
      'puzzleId': puzzleId,
      'gridSize': cells,
      'mode': mode,
      'completed': completed,
      'stars': stars,
      'layout': layout,
      'completedAt': ?at?.toIso8601String(),
    });

void main() {
  final open = _pack('open');
  final locked = _pack('locked');
  final month = _pack('daily-2026-10', category: 'Daily');
  final packs = [open, locked, month];
  final pictures = [..._pictures('open', 4), ..._pictures('locked', 4), ..._pictures('daily-2026-10', 31, firstDay: DateTime(2026, 10, 1))];
  bool unlocked(Pack p) => p.id != 'locked';
  QuickPlayPool? pool(Map<String, PuzzleProgress> rows) =>
      quickPlayPool(packs: packs, puzzles: pictures, progress: rows, isUnlocked: unlocked, now: _now);

  group('quickPlayPool', () {
    test('prefers pictures never played, from unlocked packs, open today', () {
      final p = pool({'open-1': _row('open-1', stars: 1)})!;
      expect(p.tier, QuickPlayTier.fresh);
      final ids = p.puzzles.map((z) => z.id).toSet();
      expect(ids, containsAll(['open-2', 'open-3', 'open-4', 'daily-2026-10-1', 'daily-2026-10-13']));
      expect(ids, isNot(contains('open-1')), reason: 'already played');
      expect(ids.where((id) => id.startsWith('locked-')), isEmpty, reason: 'pack not unlocked');
      expect(ids, isNot(contains('daily-2026-10-14')), reason: 'tomorrow is locked by date');
      expect(p.puzzles, hasLength(3 + 13));
    });

    test('then pictures played with fewer than three stars, a board in progress included', () {
      final rows = {
        for (final z in pictures) z.id: _row(z.id),
        'open-2': _row('open-2', stars: 2),
        'open-3': _row('open-3', completed: false, stars: 0, layout: '1,0,2,3'),
        'locked-1': _row('locked-1', stars: 0),
        'daily-2026-10-20': _row('daily-2026-10-20', stars: 1),
      };
      final p = pool(rows)!;
      expect(p.tier, QuickPlayTier.improve);
      expect(p.puzzles.map((z) => z.id), unorderedEquals(['open-2', 'open-3']), reason: 'locked pack and future day stay out');
    });

    test('then any playable picture once everything has three stars', () {
      final p = pool({for (final z in pictures) z.id: _row(z.id)})!;
      expect(p.tier, QuickPlayTier.any);
      expect(p.puzzles, hasLength(4 + 13));
    });

    test('null when no pack is playable', () {
      expect(quickPlayPool(packs: packs, puzzles: pictures, progress: const {}, isUnlocked: (_) => false, now: _now), isNull);
      expect(quickPlayPool(packs: const [], puzzles: const [], progress: const {}, isUnlocked: unlocked, now: _now), isNull);
    });
  });

  test('pickQuickPlay draws from the pool only, at random', () {
    final p = pool(const {})!;
    final random = Random(7);
    final seen = <String>{};
    for (var i = 0; i < 200; i++) {
      final z = pickQuickPlay(p, random)!;
      expect(p.puzzles, contains(z));
      seen.add(z.id);
    }
    expect(seen.length, greaterThan(10), reason: 'not stuck on one picture');
    expect(pickQuickPlay(null, random), isNull);
    expect(pickQuickPlay(const QuickPlayPool(QuickPlayTier.any, []), random), isNull);
  });

  group('lastFinishedBoard', () {
    test('mode and tier of the most recently finished game', () {
      final hex = BoardSpec.tiers(GameMode.hexagons)[4];
      final rows = {
        'a': _row('a', mode: 'cards', cells: 9, at: DateTime(2026, 10, 1)),
        'b': _row('b', mode: 'hexagons', cells: hex.cells, at: DateTime(2026, 10, 12)),
        'c': _row('c', mode: 'squares', cells: 12, completed: false, layout: '1,0'),
      };
      final board = lastFinishedBoard(rows)!;
      expect(board.mode, GameMode.hexagons);
      expect(board.tierIndex, 4);
    });

    test('null before the first finished game', () {
      expect(lastFinishedBoard(const {}), isNull);
      expect(lastFinishedBoard({'c': _row('c', completed: false, layout: '1,0')}), isNull);
    });
  });

  group('quickPlayRoute', () {
    final z = pictures.first;
    final squares = BoardSpec.tiers(GameMode.squares)[3];

    test('opens the difficulty screen with the last board preselected', () {
      final uri = Uri.parse(quickPlayRoute(z, board: squares));
      expect(uri.path, '/play/${z.id}');
      final spec = BoardSpec.fromCode(uri.queryParameters['grid']!);
      expect(spec.mode, GameMode.squares);
      expect(spec.tierIndex, 3);
    });

    test('never starts a game by itself', () {
      final saved = _row(z.id, completed: false, mode: 'triangles', cells: BoardSpec.tiers(GameMode.triangles)[2].cells, layout: '1,0,2');
      for (final route in [quickPlayRoute(z), quickPlayRoute(z, board: squares), quickPlayRoute(z, saved: saved, board: squares)]) {
        expect(route, startsWith('/play/${z.id}'));
      }
    });

    test('a board in progress opens on its own mode, not the last board', () {
      final saved = _row(z.id, completed: false, mode: 'triangles', cells: BoardSpec.tiers(GameMode.triangles)[2].cells, layout: '1,0,2');
      expect(quickPlayRoute(z, saved: saved, board: squares), '/play/${z.id}');
    });

    test('opens the plain difficulty screen without a last board', () {
      expect(quickPlayRoute(z), '/play/${z.id}');
      expect(quickPlayRoute(z, saved: _row(z.id, stars: 2)), '/play/${z.id}');
    });
  });
}
