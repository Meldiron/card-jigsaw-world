import 'package:card_jigsaw_world/features/events/quest_rewards.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/rewards.dart';
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

  test('a finished quest is ready until it is claimed', () {
    final daily = Goals.daily([_solved(1), _solved(2), _solved(3)], _now);
    final solve3 = daily.first;
    expect(solve3.done, isTrue);
    expect(anyGoalReady(daily, Goals.dailyFree, _profile()), isTrue);
    // "Earn 3 stars twice" is done too: both have to be claimed.
    expect(anyGoalReady(daily, Goals.dailyFree, _profile(claimed: [solve3.key])), isTrue);
    expect(anyGoalReady(daily, Goals.dailyFree, _profile(claimed: [solve3.key, daily[1].key])), isFalse);
  });

  test('the VIP extra quest is ready only for VIP members', () {
    final daily = Goals.daily([_solved(1, cells: 25, stars: 1)], _now);
    final big = daily.last;
    expect(big.vipOnly && big.done, isTrue);
    // Its mode quest may be done as well; claim everything else first.
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
