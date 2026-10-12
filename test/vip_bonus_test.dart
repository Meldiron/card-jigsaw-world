import 'package:card_jigsaw_world/state/rewards.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VIP has exactly one extra weekly quest; the weekly bonus is not a quest', () {
    final week = Goals.weekly(const [], DateTime(2026, 10, 12));
    expect(week.length, Goals.weeklyFree + 1);
    expect(week.where((g) => g.vipOnly).length, 1);
    expect(week.any((g) => g.key.endsWith(':vipbonus')), isFalse);
  });

  test('the VIP bonus is paid once per week', () {
    expect(Goals.vipWeeklyBonus, 500);
    expect(Goals.vipBonusKey(DateTime(2026, 10, 12)), Goals.vipBonusKey(DateTime(2026, 10, 18)));
    expect(Goals.vipBonusKey(DateTime(2026, 10, 12)), isNot(Goals.vipBonusKey(DateTime(2026, 10, 19))));
  });
}
