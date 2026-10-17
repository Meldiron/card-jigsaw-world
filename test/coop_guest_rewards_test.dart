// A guest's shared board in Play together (docs/multiplayer.md, "What players see", Rewards): the
// guest gets the board's coins, XP, level and piggy bank, and nothing else. Owner, 2026-10-17: it must
// never count toward the guest's achievements. Achievements read the player's own finished pictures
// (progress rows) and the profile's totals; the guest's reward (sync op `coopReward`) writes neither.
import 'package:carden/data/sync/changes.dart';
import 'package:carden/data/sync/ops.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/achievements.dart';
import 'package:carden/state/rewards.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a guest\'s shared board never counts toward the guest\'s achievements', () {
    final row = <String, dynamic>{
      'userId': 'guest',
      'xp': 900,
      'level': LevelRewards.levelForXp(900),
      'coins': 1000,
      'totalStars': 40,
      'puzzlesCompleted': 12,
      'piggyCoins': 10,
      'piggyLevel': 0,
      'tickets': 1,
      'hints': 2,
      'longestStreak': 3,
    };
    final op = SyncOp.coopReward(gameId: 'g', board: 1, coins: 80, xp: 400, piggy: 5);
    expect(op.target, OpTarget.profile, reason: 'no progress row: the picture is not the guest\'s');
    final plan = op.build(row);
    expect(plan.changes.keys.toSet().difference({'coins', 'xp', 'level', 'piggyCoins', 'tickets', 'hints'}), isEmpty, reason: 'only the rewards');
    final before = Profile.fromRow('guest', row), after = Profile.fromRow('guest', applyChanges(row, plan.changes));
    expect(after.xp, greaterThan(before.xp), reason: 'the rewards arrived');
    expect(after.coins, greaterThan(before.coins));
    expect((after.puzzlesCompleted, after.totalStars), (before.puzzlesCompleted, before.totalStars));

    // The guest's own finished pictures stay what they were; so does every achievement that counts
    // pictures, stars, modes, sizes, packs or times. Only what the rewards are (the level, the coins
    // held, the piggy bank) moves, as it would with any reward.
    const rewardsThemselves = {'level', 'rich', 'piggy'};
    final factsBefore = AchievementFacts(before, const [], 2), factsAfter = AchievementFacts(after, const [], 2);
    for (final f in achievementFamilies) {
      if (rewardsThemselves.contains(f.id)) continue;
      expect(f.progress(factsAfter), f.progress(factsBefore), reason: f.id);
    }
  });
}
