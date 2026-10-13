import 'package:card_jigsaw_world/data/sync/changes.dart';
import 'package:card_jigsaw_world/data/sync/ops.dart';
import 'package:card_jigsaw_world/game/board.dart';
import 'package:card_jigsaw_world/game/game_controller.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/merge.dart';
import 'package:card_jigsaw_world/state/rewards.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

PuzzleProgress _row(String id, {String mode = 'cards', int cells = 16, int stars = 3, DateTime? at, bool painting = false, int par = 0, int moves = 10, bool peeked = false, int bestLock = 0, String layout = ''}) =>
    PuzzleProgress.fromRow('row-$id', {
      'userId': 'u',
      'puzzleId': id,
      'gridSize': cells,
      'mode': mode,
      'completed': at != null,
      'completedAt': at?.toUtc().toIso8601String(),
      'stars': stars,
      'moves': moves,
      'painting': painting,
      'par': par,
      'peeked': peeked,
      'bestLock': bestLock,
      'layout': layout,
    });

/// Quest type of a key ("d:2026-10-13:stars2" -> "stars2", "w2026-10-12:par3" -> "par3").
String _type(Goal g) => g.key.split(':').last.replaceFirst(RegExp(r'-.*'), '');

dynamic _written(SyncOp op, String key, [Map<String, dynamic> row = const {}]) => (op.build(row).changes[key] as Put).value;

void main() {
  final now = DateTime(2026, 10, 14, 15);

  group('Unlocks', () {
    test('open one at a time as levels rise, Cards from the start', () {
      expect(OpenFeatures.forPlayer(level: 1).modes, [GameMode.cards]);
      expect(OpenFeatures.forPlayer(level: 1).painting, isFalse);
      expect(OpenFeatures.forPlayer(level: 2).modes, [GameMode.cards, GameMode.squares]);
      expect(OpenFeatures.forPlayer(level: 6).modes, GameMode.values);
      expect(OpenFeatures.forPlayer(level: 7).painting, isFalse);
      expect(OpenFeatures.forPlayer(level: 8).painting, isTrue);
      expect(OpenFeatures.forPlayer(level: 9).giant, isFalse);
      expect(OpenFeatures.forPlayer(level: 10).giant, isTrue);
      // Strictly increasing, each on its own level.
      final levels = [for (final u in Unlock.values) u.level];
      expect(levels, [...levels]..sort());
      expect(levels.toSet().length, levels.length);
    });

    test('anything used before stays open whatever the level', () {
      final rows = [
        _row('a', mode: 'hexagons', at: now),
        _row('b', painting: true, layout: '1,0'), // a Painting board in progress
        _row('c', cells: BoardLayouts.giantFloor(GameMode.cards), at: now),
      ];
      final open = OpenFeatures.forPlayer(level: 1, progress: rows);
      expect(open.mode(GameMode.hexagons), isTrue);
      expect(open.mode(GameMode.squares), isFalse);
      expect(open.painting, isTrue);
      expect(open.giant, isTrue);
      expect(open.used, {Unlock.hexagons, Unlock.painting, Unlock.giant});
      // The public mode counts on the profile count as used too.
      expect(OpenFeatures.forPlayer(level: 1, solvedByMode: {'triangles': 2}).mode(GameMode.triangles), isTrue);
      // Rows with nothing played (a discarded board) do not.
      expect(OpenFeatures.forPlayer(level: 1, progress: [_row('d', mode: 'squares')]).mode(GameMode.squares), isFalse);
    });

    test('level rewards name what opens', () {
      expect(LevelRewards.forLevel(Unlock.squares.level).unlocks, [Unlock.squares]);
      expect(LevelRewards.forLevel(Unlock.squares.level).lines.first, 'Squares');
      expect(LevelRewards.forLevel(3).unlocks, isEmpty);
      expect(LevelRewards.xpToReach(1), 0);
      expect(LevelRewards.xpToReach(2), 100);
      expect(LevelRewards.levelForXp(LevelRewards.xpToReach(Unlock.giant.level)), Unlock.giant.level);
      expect(LevelRewards.levelForXp(LevelRewards.xpToReach(Unlock.giant.level) - 1), Unlock.giant.level - 1);
    });
  });

  group('Quest pools', () {
    test('six or more kinds turn up across a few weeks, rewards stay the same per slot', () {
      final daily = <String>{}, weekly = <String>{};
      for (var d = 0; d < 28; d++) {
        final day = DateTime(2026, 10, 1 + d, 12);
        final goals = Goals.daily(const [], day);
        expect(goals.length, Goals.dailyFree + 1);
        expect([for (final g in goals.take(Goals.dailyFree)) g.coins], [60, 80, 100], reason: '$day');
        expect(goals.last.vipOnly, isTrue);
        daily.addAll(goals.map(_type));
        final week = Goals.weekly(const [], day);
        expect([for (final g in week.take(Goals.weeklyFree)) g.tickets], [1, 1, 2, 2, 2], reason: '$day');
        expect(week.last.vipOnly, isTrue);
        weekly.addAll(week.map(_type));
      }
      expect(daily.length, greaterThanOrEqualTo(6), reason: '$daily');
      expect(daily, containsAll(['nopeek2', 'par1', 'lock5', 'paint1', 'mode']));
      expect(weekly, containsAll(['nopeek5', 'par3', 'lock5x3', 'paint3']));
    });

    test('a level 1 player is never asked for a shape or Painting they do not have', () {
      final open = OpenFeatures.forPlayer(level: 1);
      for (var d = 0; d < 28; d++) {
        final day = DateTime(2026, 10, 1 + d, 12);
        for (final g in [...Goals.daily(const [], day, open: open, level: 1), ...Goals.weekly(const [], day, open: open, level: 1)]) {
          expect(g.mode == null || g.mode == GameMode.cards, isTrue, reason: '${g.key} asks for ${g.mode}');
          expect(g.painting, isFalse, reason: g.key);
          expect(g.title.toLowerCase(), isNot(contains('every mode')), reason: g.key);
          // Big boards follow the level: Relaxed (4x4) until Tricky opens.
          if (g.minCells > 0) expect(g.minCells, GridSpec.tiers[2].cells, reason: g.key);
        }
      }
      final two = OpenFeatures.forPlayer(level: 2);
      final modes = Goals.weekly(const [], now, open: two, level: 2).firstWhere((g) => g.key.endsWith(':modes'));
      expect(modes.target, 2);
      expect(modes.title, 'Play 2 modes this week');
      expect(Goals.weekly(const [], now).firstWhere((g) => g.key.endsWith(':modes')).title, 'Play every mode once');
    });

    test('new quest kinds count what the finished boards did', () {
      final today = [
        _row('a', at: now, peeked: false, par: 10, moves: 10, bestLock: 5),
        _row('b', at: now, peeked: true, par: 8, moves: 12, painting: true),
        _row('c', at: now, peeked: false, par: 0, moves: 3), // an older row: par unknown
      ];
      int progressOf(List<Goal> goals, String type) => goals.firstWhere((g) => _type(g) == type).progress;
      // Find days that rotate each kind in, then check its progress.
      for (var d = 0; d < 3; d++) {
        final day = DateTime(now.year, now.month, now.day + d, 15);
        final rows = [for (final r in today) _row(r.puzzleId, at: day, peeked: r.peeked, par: r.par, moves: r.moves, bestLock: r.bestLock, painting: r.painting)];
        final goals = Goals.daily(rows, day);
        final types = goals.map(_type).toSet();
        if (types.contains('nopeek2')) expect(progressOf(goals, 'nopeek2'), 2);
        if (types.contains('par1')) expect(progressOf(goals, 'par1'), 1);
        if (types.contains('lock5')) expect(progressOf(goals, 'lock5'), 1);
        if (types.contains('paint1')) expect(progressOf(goals, 'paint1'), 1);
      }
    });

    test('a slot keeps the quest already claimed in it', () {
      final goals = Goals.daily(const [], now);
      final k = Goals.dayKey(now);
      final shown = goals[1].key;
      final others = ['d:$k:stars2', 'd:$k:nopeek2', 'd:$k:par1'].where((key) => key != shown).toList();
      final kept = Goals.daily(const [], now, claimed: {others.first});
      expect(kept[1].key, others.first);
    });

    test('week keys do not move across a daylight saving change', () {
      // Europe goes back an hour on Sunday 25 October 2026.
      expect(Goals.weekKey(DateTime(2026, 10, 25, 23, 30)), 'w2026-10-19');
      expect(Goals.weekKey(DateTime(2026, 10, 26, 0, 30)), 'w2026-10-26');
      expect(Goals.weekIndex(DateTime(2026, 10, 25, 23, 30)), Goals.weekIndex(DateTime(2026, 10, 19, 0, 10)));
    });
  });

  group('The play-through feeds the quests', () {
    const spec = GridSpec(3, 3, 'Cozy', tier: 0);

    GameController controllerFor(ProviderContainer c, GameArgs args) {
      c.read(gameControllerProvider(args));
      return c.read(gameControllerProvider(args).notifier);
    }

    test('Peek, the longest lock by the player and the dealt par are tracked; Magic does not count', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      // Cards 0,1,3,4,6,7 sit one slot right of home as one group; 2, 5 and 8 fill the rest.
      const layout = [2, 0, 1, 5, 3, 4, 8, 6, 7];
      final args = GameArgs(puzzleId: 'p', spec: spec, layout: layout, moves: 4, par: 11);
      final ctrl = controllerFor(c, args);
      expect(c.read(gameControllerProvider(args)).basePar, 11, reason: 'a resumed board keeps its dealt par');
      expect(c.read(gameControllerProvider(args)).peeked, isFalse);
      ctrl.peek();
      expect(c.read(gameControllerProvider(args)).peeked, isTrue);
      ctrl.drop(1, 0);
      expect(c.read(gameControllerProvider(args)).bestLock, greaterThanOrEqualTo(Goals.lockRun));

      final swap = GameArgs(puzzleId: 'q', spec: spec, layout: const [1, 0, 2, 3, 4, 5, 6, 7, 8]);
      final magic = controllerFor(c, swap);
      expect(c.read(gameControllerProvider(swap)).basePar, c.read(gameControllerProvider(swap)).par, reason: 'no saved par: the recomputed one');
      magic.magicLock();
      expect(c.read(gameControllerProvider(swap)).bestLock, 0, reason: 'Magic locks are not the player\'s');
    });

    test('board and win ops write par, Peek and the longest lock; a discard clears them', () {
      final board = SyncOp.board(puzzleId: 'p', gridSize: 16, mode: 'cards', layout: '1,0', moves: 3, seconds: 9, hints: 0, session: 's', resumed: false, par: 12, peeked: true, bestLock: 4);
      expect(_written(board, 'par'), 12);
      expect(_written(board, 'peeked'), isTrue);
      expect(_written(board, 'bestLock'), 4);
      final win = SyncOp.win(puzzleId: 'p', gridSize: 16, mode: 'cards', moves: 12, seconds: 9, hints: 0, stars: 3, session: 's', resumed: true, par: 12, bestLock: 6);
      expect(_written(win, 'par'), 12);
      expect(_written(win, 'peeked'), isFalse);
      expect(_written(win, 'bestLock'), 6);
      // Ops queued by older builds carry none of them.
      final legacy = SyncOp.fromJson({...board.toJson(), 'args': {...board.args}..remove('par')..remove('peeked')..remove('bestLock')});
      expect(_written(legacy, 'par'), 0);
      expect(_written(legacy, 'peeked'), isFalse);
      final discard = SyncOp.discard('p');
      expect(_written(discard, 'par'), 0);
      expect(_written(discard, 'bestLock'), 0);
      // Rows read them back, and a sign-in merge keeps the kept board's.
      final row = PuzzleProgress.fromRow('r', {'puzzleId': 'p', 'par': 9, 'peeked': true, 'bestLock': 5});
      expect((row.par, row.peeked, row.bestLock), (9, true, 5));
      expect(PuzzleProgress.fromRow('r', row.toData()).bestLock, 5);
      final merged = mergeProgressRow(
        {'puzzleId': 'p', 'par': 9, 'peeked': true, 'bestLock': 5, r'$updatedAt': '2026-10-02T10:00:00Z'},
        {'puzzleId': 'p', 'par': 3, r'$updatedAt': '2026-10-01T10:00:00Z'},
      );
      expect((merged['par'], merged['peeked'], merged['bestLock']), (9, true, 5));
    });
  });
}
