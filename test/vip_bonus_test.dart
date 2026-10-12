import 'package:card_jigsaw_world/state/rewards.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VIP weekly bonus is a VIP-only weekly quest worth 500 coins, keyed per week', () {
    final a = Goals.weekly(const [], DateTime(2026, 10, 12));
    final b = Goals.weekly(const [], DateTime(2026, 10, 19));
    final bonusA = a.last;
    expect(bonusA.vipOnly, isTrue);
    expect(bonusA.done, isTrue);
    expect(bonusA.coins, Goals.vipWeeklyBonus);
    expect(bonusA.coins, 500);
    expect(bonusA.key, isNot(b.last.key));
    // free players still get exactly the first five weekly quests
    expect(a.where((g) => !g.vipOnly).length, Goals.weeklyFree);
  });
}
