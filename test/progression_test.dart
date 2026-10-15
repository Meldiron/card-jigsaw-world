import 'dart:math';

import 'package:card_jigsaw_world/data/sync/changes.dart';
import 'package:card_jigsaw_world/data/sync/ops.dart';
import 'package:card_jigsaw_world/game/board.dart';
import 'package:card_jigsaw_world/game/game_controller.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/merge.dart';
import 'package:card_jigsaw_world/state/profile.dart';
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

    test('giant boards opened early with tickets are open at any level; nothing else is', () {
      final early = OpenFeatures.forPlayer(level: 3, unlockedTiers: [Unlocks.earlyKey(Unlock.giant), 'cards:4']);
      expect(early.giant, isTrue);
      expect(early.painting, isFalse);
      expect(early.mode(GameMode.hexagons), isFalse);
      expect(early.used, isEmpty, reason: 'bought, not played: the intro still greets the first giant board');
      // Early board tiers (`<mode>:<index>`) share the list and open no feature.
      expect(OpenFeatures.forPlayer(level: 3, unlockedTiers: ['cards:4', 'squares:5']).giant, isFalse);
    });

    test('opening giant boards early: the usual price plus 1 ticket a level to go', () {
      expect(Economy.giantEarlyTicketsPerLevel, 1);
      expect(Economy.giantEarlyFee(7), 3, reason: 'level 7: 12 + 3 = 15 for a 12-ticket pack');
      expect(Economy.giantEarlyFee(1), 9);
      expect(Economy.giantEarlyFee(9), 1);
      expect(Economy.giantEarlyFee(10), 0);
      expect(Economy.giantEarlyFee(24), 0);
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
    // A player's history: [n] boards finished yesterday, slower than [seconds] at best.
    List<PuzzleProgress> history({String mode = 'cards', int cells = 16, int n = 20, bool painting = false, int seconds = 60}) => [
          for (var i = 0; i < n; i++)
            PuzzleProgress.fromRow('h$i', {
              'userId': 'u', 'puzzleId': 'h$i', 'gridSize': cells, 'mode': mode, 'completed': true, 'stars': 3, 'moves': 30, 'par': 12,
              'painting': painting, 'elapsedSeconds': seconds + i, 'completedAt': now.subtract(Duration(days: 1, minutes: i)).toUtc().toIso8601String(),
            }),
        ];
    PuzzleProgress board(String id, DateTime at, {String mode = 'cards', int cells = 16, bool painting = false, bool atPar = false, int lock = 0, int seconds = 600, String? puzzle}) =>
        PuzzleProgress.fromRow('row-$id', {
          'userId': 'u', 'puzzleId': puzzle ?? id, 'gridSize': cells, 'mode': mode, 'completed': true, 'stars': 3, 'par': 12, 'moves': atPar ? 12 : 30,
          'painting': painting, 'bestLock': lock, 'elapsedSeconds': seconds, 'completedAt': at.toUtc().toIso8601String(),
        });
    final players = {
      'level 3, Cards 4x4': (3, history()),
      'level 9, Cards 4x4': (9, history()),
      'level 20, Hexagons 5x5': (20, history(mode: 'hexagons', cells: 25)),
      'level 20, Cards 3x3': (20, history(cells: 9, seconds: 15)),
    };

    test('rewards stay the same per slot, and many kinds turn up', () {
      final daily = <String>{}, weekly = <String>{};
      for (var d = 0; d < 28; d++) {
        final day = DateTime(2026, 10, 1 + d, 12);
        final goals = Goals.daily(const [], day);
        expect(goals.length, Goals.dailyFree + 1);
        expect([for (final g in goals.take(Goals.dailyFree)) g.coins], [60, 80, 100], reason: '$day');
        expect(goals.last.vipOnly, isTrue);
        expect({for (final g in goals) g.title}.length, goals.length, reason: 'no quest twice: $day');
        daily.addAll(goals.map(_type));
        final week = Goals.weekly(const [], day);
        expect([for (final g in week.take(Goals.weeklyFree)) g.tickets], [1, 1, 2, 2, 2], reason: '$day');
        expect(week.last.vipOnly, isTrue);
        expect({for (final g in week) g.title}.length, week.length, reason: 'no quest twice: $day');
        weekly.addAll(week.map(_type));
      }
      expect(daily, containsAll(['solve3', 'mode', 'size', 'paint', 'par', 'lock']));
      expect(weekly, containsAll(['solve10', 'days4', 'modes', 'size', 'paint', 'par', 'lock']));
    });

    test('playing as usual finishes "Solve 3 puzzles" and nothing else', () {
      for (final e in players.entries) {
        final (level, past) = e.value;
        final usual = past.first;
        for (var d = 0; d < 28; d++) {
          final day = DateTime(now.year, now.month, now.day + d, 15);
          final today = [for (var i = 0; i < 6; i++) board('t$d-$i', day.subtract(Duration(minutes: i)), mode: usual.mode, cells: usual.gridSize, seconds: 999)];
          final goals = Goals.daily([...past, ...today], day, open: OpenFeatures.forPlayer(level: level), level: level, dailyPuzzle: 'daily-$d');
          expect([for (final g in goals) if (g.done) _type(g)], ['solve3'], reason: '${e.key}, $day: ${[for (final g in goals) g.title]}');
        }
      }
    });

    test('a board that changes one thing finishes at most one of the day\'s quests', () {
      for (final e in players.entries) {
        final (level, past) = e.value;
        final usual = past.first;
        final other = usual.mode == 'cards' ? 'triangles' : 'cards';
        for (var d = 0; d < 28; d++) {
          final day = DateTime(now.year, now.month, now.day + d, 15);
          final boards = {
            'shape': board('a', day, mode: other, cells: usual.gridSize),
            'big': board('b', day, mode: usual.mode, cells: 48),
            'big with 8 locked': board('c', day, mode: usual.mode, cells: 48, lock: 8),
            'painting': board('d', day, mode: usual.mode, cells: usual.gridSize, painting: true),
            'at par': board('e', day, mode: usual.mode, cells: max(16, usual.gridSize), atPar: true),
            'fast': board('f', day, mode: usual.mode, cells: usual.gridSize, seconds: 1),
            'daily puzzle': board('g', day, mode: usual.mode, cells: usual.gridSize, puzzle: 'daily-$d'),
          };
          for (final b in boards.entries) {
            final goals = Goals.daily([...past, b.value], day, open: OpenFeatures.forPlayer(level: level), level: level, dailyPuzzle: 'daily-$d');
            final done = [for (final g in goals.skip(1)) if (g.done) g.title];
            expect(done.length, lessThanOrEqualTo(1), reason: '${e.key}, $day, ${b.key}: $done');
          }
        }
      }
    });

    test('quests ask for what the player does not usually do', () {
      for (var d = 0; d < 28; d++) {
        final day = DateTime(now.year, now.month, now.day + d, 15);
        // A Hexagons player on 5x5 is never asked for Hexagons or a board they already play, and
        // gets the bigger lock (5 comes by itself on their boards).
        final hex = Goals.daily(history(mode: 'hexagons', cells: 25), day, level: 20);
        for (final g in hex) {
          expect(g.mode, isNot(GameMode.hexagons), reason: g.title);
          if (_type(g) == 'size') expect(g.minCells, greaterThan(25), reason: g.title);
          if (_type(g) == 'lock') expect(g.title, 'Lock ${Goals.bigLockRun} cards in one move');
        }
        // A Painting player is not asked for Painting.
        expect(Goals.daily(history(painting: true), day, level: 20).where((g) => g.painting), isEmpty);
        // A 4x4 player: lock 5, and the time to beat is their second-best 4x4 time.
        for (final g in Goals.daily(history(seconds: 40), day, level: 20)) {
          if (_type(g) == 'lock') expect(g.title, 'Lock ${Goals.lockRun} cards in one move');
          if (_type(g) == 'fast') expect(g.title, 'Solve a 4x4 board in under 41 seconds');
        }
      }
    });

    test('a level 1 player is never asked for a shape or Painting they do not have', () {
      final open = OpenFeatures.forPlayer(level: 1);
      for (var d = 0; d < 28; d++) {
        final day = DateTime(2026, 10, 1 + d, 12);
        for (final g in [...Goals.daily(const [], day, open: open, level: 1), ...Goals.weekly(const [], day, open: open, level: 1)]) {
          expect(g.mode == null || g.mode == GameMode.cards, isTrue, reason: '${g.key} asks for ${g.mode}');
          expect(g.painting, isFalse, reason: g.key);
          expect(g.title.toLowerCase(), isNot(contains('every mode')), reason: g.key);
          // Nothing bigger than the level has: Relaxed (4x4) at level 1.
          if (g.minCells > 0) expect(g.minCells, GridSpec.tiers[2].cells, reason: g.key);
        }
      }
      final two = OpenFeatures.forPlayer(level: 2);
      Goal modes(OpenFeatures open, int level) => [
            for (var w = 0; w < 6; w++) ...Goals.weekly(const [], now.add(Duration(days: 7 * w)), open: open, level: level),
          ].firstWhere((g) => g.key.endsWith(':modes'));
      expect(modes(two, 2).target, 2);
      expect(modes(two, 2).title, 'Play 2 modes this week');
      expect(modes(OpenFeatures.all, 99).title, 'Play every mode once');
    });

    test('each kind counts the boards it asks for', () {
      final k = Goals.dayKey(now);
      final today = [
        board('a', now, mode: 'squares'),
        board('b', now, cells: 25, lock: 5),
        board('c', now, painting: true),
        board('d', now, cells: 9, atPar: true), // par on the smallest boards does not count
        board('e', now, cells: 16, atPar: true, seconds: 30),
        board('f', now, cells: 36, lock: 8, puzzle: 'today'),
      ];
      int progress(String kind) => Goals.daily(today, now, claimed: {'d:$k:s2:$kind'}, dailyPuzzle: 'today')[1].progress;
      expect(progress('mode-squares'), 1);
      expect(progress('size-5x5'), 2);
      expect(progress('paint'), 1);
      expect(progress('par'), 1);
      expect(progress('lock-5'), 2);
      expect(progress('lock-8'), 1);
      expect(progress('fast-4x4-41'), 1);
      expect(progress('daily'), 1);
      final daily = Goals.daily(today, now, claimed: {'d:$k:s4:daily'}, dailyPuzzle: 'today').last;
      expect(daily.puzzleId, 'today', reason: 'Play opens the daily puzzle');
    });

    test('a slot keeps the quest already claimed in it, and the others make room', () {
      for (var d = 0; d < 14; d++) {
        final day = DateTime(now.year, now.month, now.day + d, 15);
        final k = Goals.dayKey(day);
        // Claimed at level 2, before level 3 opens 5x5 and the lock quest.
        final before = Goals.daily(const [], day, open: OpenFeatures.forPlayer(level: 2), level: 2);
        final claimed = {before[1].key, before[2].key};
        final after = Goals.daily(const [], day, open: OpenFeatures.forPlayer(level: 3), level: 3, claimed: claimed);
        expect([after[1].key, after[2].key], [before[1].key, before[2].key], reason: '$day');
        expect({for (final g in after) _type(g)}.length, after.length, reason: 'no lane twice: ${after.map((g) => g.key)}');
        expect(after[1].key, startsWith('d:$k:s2:'));
      }
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
