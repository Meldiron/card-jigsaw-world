import 'package:carden/models/models.dart';
import 'package:carden/state/rewards.dart';
import 'package:flutter_test/flutter_test.dart';

/// The level is derived from XP in one place. Every screen (HUD, profile,
/// league rows, other players' profiles) and the mirrored `level` column
/// must agree, whatever a row happens to store.
void main() {
  test('levelForXp follows the xpForLevel curve', () {
    expect(LevelRewards.levelForXp(0), 1);
    expect(LevelRewards.levelForXp(99), 1);
    expect(LevelRewards.levelForXp(100), 2);
    // 100 + 160 = 260 XP reaches level 3.
    expect(LevelRewards.levelForXp(259), 2);
    expect(LevelRewards.levelForXp(260), 3);
    var total = 0;
    for (var level = 1; level < 40; level++) {
      total += Profile.xpForLevel(level);
      expect(LevelRewards.levelForXp(total - 1), level, reason: 'one XP short of level ${level + 1}');
      expect(LevelRewards.levelForXp(total), level + 1, reason: 'exactly enough for level ${level + 1}');
    }
    expect(LevelRewards.xpIntoLevel(0), 0);
    expect(LevelRewards.xpIntoLevel(100), 0);
    expect(LevelRewards.xpIntoLevel(150), 50);
  });

  test('a profile row with a stale level column reads the level derived from its XP', () {
    // 1829 XP: 100 + 160 + 220 + 280 + 340 + 400 = 1500 reaches level 7,
    // 1500 + 460 = 1960 would reach level 8. The row says 9; the HUD, the
    // league row and everyone else must say 7.
    final p = Profile.fromRow('u1', {'userId': 'u1', 'xp': 1829, 'level': 9});
    expect(p.level, 7);
    expect(p.level, LevelRewards.levelForXp(p.xp));
    expect(p.xpIntoLevel, 329);
    expect(p.levelProgress, closeTo(329 / Profile.xpForLevel(7), 1e-9));
    // What is written back mirrors the derived level, not the stale one.
    expect(p.toData()['level'], 7);
  });

  test('aggregate counters round-trip through the row', () {
    final p = Profile.fromRow('u1', {'userId': 'u1', 'totalMoves': 120, 'totalSeconds': 900, 'solvedByMode': '{"cards":3,"hexagons":1}'});
    expect(p.totalMoves, 120);
    expect(p.totalSeconds, 900);
    expect(p.solvedByMode, {'cards': 3, 'hexagons': 1});
    expect(p.toData()['solvedByMode'], '{"cards":3,"hexagons":1}');
    expect(Profile.fromRow('u2', {'userId': 'u2', 'solvedByMode': 'garbage'}).solvedByMode, isEmpty);
    expect(Profile.fromRow('u3', {'userId': 'u3'}).toData()['solvedByMode'], isNull);
  });
}
