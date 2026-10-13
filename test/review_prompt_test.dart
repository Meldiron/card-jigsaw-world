import 'dart:io';

import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/account_deletion.dart';
import 'package:card_jigsaw_world/state/review_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 14, 20);

PuzzleProgress _row(String id, {bool completed = true, int stars = 3, DateTime? at}) => PuzzleProgress.fromRow('row-$id', {
      'userId': 'u',
      'puzzleId': id,
      'gridSize': 16,
      'mode': 'cards',
      'completed': completed,
      'stars': stars,
      'completedAt': ?at?.toUtc().toIso8601String(),
    });

Puzzle _pic(String id, String pack) => Puzzle.fromRow(id, {'packId': pack, 'title': id});

void main() {
  group('when to ask for a rating', () {
    bool ask({bool happy = true, int solved = 8, DateTime? lastAskedAt, String? lastAskedVersion, DateTime? lastAdAt}) => ReviewRules.shouldAsk(
          happy: happy,
          solved: solved,
          now: _now,
          version: '1.7.0',
          lastAskedAt: lastAskedAt,
          lastAskedVersion: lastAskedVersion,
          lastAdAt: lastAdAt,
        );

    test('after a happy moment once the player has solved five pictures', () {
      expect(ask(), isTrue);
      expect(ask(happy: false), isFalse);
      expect(ask(solved: 4), isFalse);
      expect(ask(solved: 5), isTrue);
    });

    test('once per app version and at most every 120 days', () {
      expect(ask(lastAskedVersion: '1.7.0'), isFalse);
      expect(ask(lastAskedVersion: '1.6.0', lastAskedAt: _now.subtract(const Duration(days: 30))), isFalse);
      expect(ask(lastAskedVersion: '1.6.0', lastAskedAt: _now.subtract(const Duration(days: 121))), isTrue);
    });

    test('never right after an ad break', () {
      expect(ask(lastAdAt: _now.subtract(const Duration(seconds: 30))), isFalse);
      expect(ask(lastAdAt: _now.subtract(const Duration(minutes: 10))), isTrue);
    });
  });

  group('happy moments', () {
    test('a picture finished just now, not one synced from earlier', () {
      final prev = {'a': _row('a', completed: false), 'b': _row('b', at: _now.subtract(const Duration(days: 1)))};
      final next = {
        'a': _row('a', at: _now.subtract(const Duration(seconds: 3))),
        'b': _row('b', at: _now.subtract(const Duration(days: 1))),
        'c': _row('c', at: _now.subtract(const Duration(hours: 2))), // arrived from another device
      };
      expect([for (final r in ReviewRules.justFinished(prev, next, _now)) r.puzzleId], ['a']);
    });

    test('a replay finished again counts again', () {
      final prev = {'a': _row('a', at: _now.subtract(const Duration(days: 2)))};
      final next = {'a': _row('a', at: _now.subtract(const Duration(seconds: 5)))};
      expect(ReviewRules.justFinished(prev, next, _now), hasLength(1));
    });

    test('three stars, or the first solve that finishes a pack', () {
      final pack = [_pic('a', 'p'), _pic('b', 'p')];
      final threeStars = _row('a', stars: 3, at: _now);
      expect(ReviewRules.isHappy(threeStars, before: null, pack: pack, progress: {'a': threeStars}), isTrue);

      final oneStar = _row('b', stars: 1, at: _now);
      // b finishes the pack (a was solved before).
      expect(ReviewRules.isHappy(oneStar, before: _row('b', completed: false), pack: pack, progress: {'a': threeStars, 'b': oneStar}), isTrue);
      // A one-star solve that leaves the pack unfinished is not a happy moment.
      expect(ReviewRules.isHappy(oneStar, before: null, pack: pack, progress: {'b': oneStar}), isFalse);
      // Replaying a picture of a pack finished long ago is not "finishing" it.
      expect(ReviewRules.isHappy(oneStar, before: _row('b', stars: 1, at: _now.subtract(const Duration(days: 9))), pack: pack, progress: {'a': threeStars, 'b': oneStar}), isFalse);
    });
  });

  test('account deletion clears the save under the keys the sync stores it with', () {
    // SyncController._key in lib/state/sync.dart is private; keep AccountDeletion.deviceSaveKeys in step.
    final source = File('lib/state/sync.dart').readAsStringSync();
    expect(source, contains(r"static String _key(String userId, String part) => 'sync.v1.$userId.$part';"));
    expect(AccountDeletion.deviceSaveKeys('u1'), ['sync.v1.u1.ops', 'sync.v1.u1.rows']);
  });
}
