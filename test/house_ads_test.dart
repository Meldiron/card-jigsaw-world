import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/core/numbers.dart';
import 'package:carden/data/purchases.dart';
import 'package:carden/features/ads/house_ads.dart';
import 'package:carden/state/profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pushes the rewarded card and returns a reader for what it popped with.
Future<bool? Function()> _openRewarded(WidgetTester tester) async {
  bool? result;
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<bool>(MaterialPageRoute(
                builder: (_) => HouseAdScreen(creative: houseCreatives.first, coverUrl: null, rewarded: true, rewardCoins: Economy.adRewardCoins),
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return () => result;
}

void main() {
  test('house ad policy numbers are sane', () {
    expect(HouseAdPolicy.rewardedDuration.inSeconds, inInclusiveRange(15, 30));
    expect(HouseAdPolicy.interstitialCloseDelay.inSeconds, inInclusiveRange(3, 5));
    expect(HouseAdPolicy.everyNthCompletion, inInclusiveRange(2, 8));
    expect(HouseAdPolicy.maxPerSession, greaterThanOrEqualTo(1));
    expect(HouseAdPolicy.minGap.inMinutes, greaterThanOrEqualTo(2));
    expect(HouseAdPolicy.skipFirstCompletions, greaterThanOrEqualTo(2));
  });

  group('creatives promise what the store sells', () {
    Creative byId(String id) => houseCreatives.firstWhere((c) => c.id == id);

    test('VIP price line uses the monthly price and the trial length', () {
      final vip = byId('vip-all');
      expect(vip.price, '${StoreProducts.vipTrialDays} days free, then ${StoreProducts.price(ProductIds.vipMonthly)}/month');
      expect(vip.price, isNot(contains('4.99')));
    });

    test('bundle creatives name the current amounts and prices', () {
      for (final (id, product) in const [
        ('coins-3000', ProductIds.coins3000),
        ('coins-1000', ProductIds.coins1000),
        ('tickets-5', ProductIds.tickets5),
        ('hints-15', ProductIds.hints15),
      ]) {
        final c = byId(id);
        final grant = StoreProducts.grant(product);
        expect(c.cta, 'Get ${grant.label}', reason: id);
        expect(c.price, StoreProducts.price(product), reason: id);
        expect(c.body, contains(formatCount(grant.coins + grant.tickets + grant.hints)), reason: id);
      }
    });

    test('coin creatives keep their claims true', () {
      final coins = StoreProducts.grant(ProductIds.coins3000).coins;
      expect(byId('coins-3000').body, contains('${coins ~/ Economy.magicLockCostCoins} Magic Locks'));
      expect(StoreProducts.grant(ProductIds.coins1000).coins, greaterThanOrEqualTo(PackPricePolicy.standardPackCoins));
    });

    test('piggy creative states the real fill rate', () {
      expect(byId('piggy').body, contains('adds ${Economy.piggyPerPuzzle} coins'));
    });

    test('every purchase creative opens the store', () {
      for (final c in houseCreatives.where((c) => c.price != null)) {
        expect(c.route, '/store', reason: c.id);
      }
    });
  });

  group('rewarded card', () {
    final seconds = HouseAdPolicy.rewardedDuration.inSeconds;

    testWidgets('closing early asks first, Keep watching stays, Close leaves without the reward', (tester) async {
      final result = await _openRewarded(tester);
      await tester.tap(find.textContaining('Reward in'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Close and lose the reward?'), findsOneWidget);
      await tester.tap(find.text('Keep watching'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Close and lose the reward?'), findsNothing);
      expect(find.byType(HouseAdScreen), findsOneWidget);

      await tester.tap(find.textContaining('Reward in'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(HouseAdScreen), findsNothing);
      expect(result(), isFalse);
    });

    testWidgets('the reward can only be collected after the full countdown', (tester) async {
      final result = await _openRewarded(tester);
      // Disabled until the countdown ends: tapping it does nothing.
      await tester.tap(find.textContaining('Collect ${Economy.adRewardCoins} coins in'), warnIfMissed: false);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(HouseAdScreen), findsOneWidget);
      expect(result(), isNull);

      await tester.pump(Duration(seconds: seconds));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Collect ${Economy.adRewardCoins} coins'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(HouseAdScreen), findsNothing);
      expect(result(), isTrue);
    });
  });
}
