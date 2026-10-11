import 'package:card_jigsaw_world/features/ads/house_ads.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('house ad policy numbers are sane', () {
    expect(HouseAdPolicy.rewardedDuration.inSeconds, inInclusiveRange(15, 30));
    expect(HouseAdPolicy.interstitialCloseDelay.inSeconds, inInclusiveRange(3, 5));
    expect(HouseAdPolicy.everyNthCompletion, inInclusiveRange(4, 8));
    expect(HouseAdPolicy.maxPerSession, lessThanOrEqualTo(3));
    expect(HouseAdPolicy.minGap.inMinutes, greaterThanOrEqualTo(2));
    expect(HouseAdPolicy.skipFirstCompletions, greaterThanOrEqualTo(2));
  });
}
