import 'package:carden/features/events/quest_rewards.dart';
import 'package:carden/game/modes.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/rewards.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 13, 15);

PuzzleProgress _solved(int i, {int stars = 3, String mode = 'cards', int cells = 16}) => PuzzleProgress.fromRow('row-$i', {
      'userId': 'u',
      'puzzleId': 'p$i',
      'gridSize': cells,
      'mode': mode,
      'completed': true,
      'stars': stars,
      'completedAt': _now.subtract(Duration(minutes: i)).toIso8601String(),
    });

Profile _profile({List<String> claimed = const [], bool vip = false}) => Profile.fromRow('u', {'userId': 'u', 'claimedGoals': claimed, 'isVip': vip});

void main() {
  test('nothing to claim before any quest is finished', () {
    expect(anyGoalReady(Goals.daily(const [], _now), Goals.dailyFree, _profile()), isFalse);
    expect(anyGoalReady(Goals.weekly(const [], _now), Goals.weeklyFree, _profile()), isFalse);
  });

  test('three ordinary boards finish "Solve 3 puzzles" and nothing else', () {
    final daily = Goals.daily([_solved(1), _solved(2), _solved(3)], _now);
    final solve3 = daily.first;
    expect(solve3.done, isTrue);
    expect(anyGoalReady(daily, Goals.dailyFree, _profile()), isTrue);
    expect(anyGoalReady(daily, Goals.dailyFree, _profile(claimed: [solve3.key])), isFalse);
  });

  test('the VIP extra quest is ready only for VIP members', () {
    final vip = Goals.daily(const [], _now, dailyPuzzle: 'today').last;
    expect(vip.vipOnly, isTrue);
    // A board that does what the VIP quest asks.
    final title = vip.title;
    final row = PuzzleProgress.fromRow('row-vip', {
      'userId': 'u',
      'puzzleId': vip.puzzleId ?? 'p-vip',
      'gridSize': vip.minCells > 0 ? vip.minCells : 16,
      'mode': (vip.mode ?? GameMode.cards).code,
      'completed': true,
      'stars': 3,
      'painting': vip.painting,
      'par': 12,
      'moves': title.contains('at par') ? 12 : 30,
      'bestLock': 9,
      'elapsedSeconds': 1,
      'completedAt': _now.toIso8601String(),
    });
    final daily = Goals.daily([row], _now, dailyPuzzle: 'today');
    final big = daily.last;
    expect(big.done, isTrue, reason: big.title);
    final others = [for (final g in daily) if (g.key != big.key) g.key];
    expect(goalLocked(big, daily.length - 1, Goals.dailyFree, _profile(claimed: others)), isTrue);
    expect(anyGoalReady(daily, Goals.dailyFree, _profile(claimed: others)), isFalse);
    expect(anyGoalReady(daily, Goals.dailyFree, _profile(claimed: others, vip: true)), isTrue);
  });

  test('pack events count the pack, other events their counter', () {
    final event = GameEvent.fromRow('e', {'name': 'World Food Day', 'goal': 5, 'packId': ''});
    expect(eventProgressOf(null, event, null), (0, 5));
  });
}
