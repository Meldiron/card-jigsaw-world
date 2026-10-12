import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:card_jigsaw_world/data/purchases.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/profile.dart';
import 'package:card_jigsaw_world/state/rewards.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards for the economy described in docs/economy.md.
///
/// * What a purchase gives is written in three places (the app, the server
///   grant, the App Store metadata); they must say the same.
/// * The pack prices in the database come from tools/store/apply_pack_prices.py,
///   which is calibrated on the regular player's earnings. If a change to the
///   rewards moves those earnings, the model test below fails: re-run the
///   model in docs/economy.md, update the script's constants, and re-apply
///   the prices.
void main() {
  group('purchase grants agree', () {
    final serverGrants = _serverGrants();
    final metadata = jsonDecode(File('store/metadata/subscriptions/consumables.json').readAsStringSync()) as Map<String, dynamic>;
    final products = (metadata['products'] as List).cast<Map<String, dynamic>>();

    test('every consumable has one grant in the app and on the server', () {
      expect(StoreProducts.grants.keys.toSet(), ProductIds.consumables);
      expect(serverGrants.keys.toSet(), ProductIds.consumables);
      for (final id in ProductIds.consumables) {
        final app = StoreProducts.grant(id);
        expect(serverGrants[id], {if (app.coins > 0) 'coins': app.coins, if (app.tickets > 0) 'tickets': app.tickets, if (app.hints > 0) 'hints': app.hints}, reason: id);
      }
    });

    test('App Store names and prices match the app', () {
      expect(products.map((p) => p['productId']).toSet(), ProductIds.consumables);
      for (final p in products) {
        final id = p['productId'] as String;
        final grant = StoreProducts.grant(id);
        expect(p['name'], grant.label, reason: '$id display name');
        expect(p['customerPrice'], StoreProducts.usdPrices[id], reason: '$id price');
        expect((p['name'] as String).length, lessThanOrEqualTo(30), reason: '$id name length');
        expect((p['description'] as String).length, lessThanOrEqualTo(45), reason: '$id description length');
        final amount = grant.coins + grant.tickets + grant.hints;
        expect(p['reviewNote'], contains(groupThousands(amount)), reason: '$id review note names the amount');
      }
      for (final id in ProductIds.subscriptions) {
        final sub = jsonDecode(File('store/metadata/subscriptions/$id.json').readAsStringSync()) as Map<String, dynamic>;
        expect((sub['price'] as Map)['customerPrice'], StoreProducts.usdPrices[id], reason: '$id price');
      }
    });
  });

  group('bundle value', () {
    double coinValue(String id) {
      final g = StoreProducts.grant(id);
      return (g.coins + g.tickets * StoreProducts.ticketCoinValue + g.hints * Economy.hintCostCoins) / double.parse(StoreProducts.usdPrices[id]!);
    }

    final base = coinValue(ProductIds.coins1000);

    test('every bundle is worth about the same per dollar as the smallest coin bundle', () {
      for (final id in ProductIds.consumables) {
        expect(coinValue(id) / base, inInclusiveRange(0.9, 1.3), reason: id);
      }
    });

    test('bigger bundles never give less per dollar', () {
      for (final ladder in const [
        [ProductIds.coins1000, ProductIds.coins3000, ProductIds.coins5500, ProductIds.coins12000],
        [ProductIds.tickets5, ProductIds.tickets15],
        [ProductIds.hints5, ProductIds.hints15],
      ]) {
        for (var i = 1; i < ladder.length; i++) {
          expect(coinValue(ladder[i]), greaterThanOrEqualTo(coinValue(ladder[i - 1])), reason: '${ladder[i]} vs ${ladder[i - 1]}');
        }
      }
    });

    test('the smallest coin bundle buys a standard pack', () {
      expect(StoreProducts.grant(ProductIds.coins1000).coins, greaterThanOrEqualTo(PackPricePolicy.standardPackCoins));
      expect(StoreProducts.grant(ProductIds.tickets5).tickets, greaterThanOrEqualTo(PackPricePolicy.ticketPackTickets[1]));
      expect(StoreProducts.coinBonusPercent(ProductIds.coins1000), 0);
      expect(StoreProducts.coinBonusPercent(ProductIds.coins5500), inInclusiveRange(5, 30));
    });
  });

  group('pack price policy', () {
    final script = File('tools/store/apply_pack_prices.py').readAsStringSync();
    num constant(String name) => num.parse(RegExp('^$name = ([\\d.]+)', multiLine: true).firstMatch(script)!.group(1)!);
    num tierShare(String table, String tier) =>
        num.parse(RegExp('^$table = \\{[^}]*"$tier": ([\\d.]+)', multiLine: true).firstMatch(script)!.group(1)!);

    test('the app mirrors the script', () {
      expect(constant('MIN_COINS'), PackPricePolicy.minCoins);
      expect(constant('MAX_COINS'), PackPricePolicy.maxCoins);
      final perPicture = tierShare('TIER_PACK_COINS', 'standard') / constant('REFERENCE_PICTURES');
      expect((24 * perPicture / 100).round() * 100, PackPricePolicy.standardPackCoins);
      final tickets = constant('REGULAR_TICKETS_PER_WEEK');
      expect([for (final t in ['standard', 'plus', 'special']) (tierShare('TICKET_TIER_WEEKS', t) * tickets).round()], PackPricePolicy.ticketPackTickets);
    });

    test('the script is calibrated on the current earnings', () {
      final m = _regularPlayerSteadyState();
      expect(m.coinsPerHour, closeTo(constant('REGULAR_COINS_PER_HOUR'), constant('REGULAR_COINS_PER_HOUR') * 0.1),
          reason: 'earnings changed: re-run the model in docs/economy.md and update apply_pack_prices.py');
      expect(m.ticketsPerWeek, closeTo(constant('REGULAR_TICKETS_PER_WEEK'), 2),
          reason: 'ticket income changed: re-run the model in docs/economy.md and update apply_pack_prices.py');
    });
  });
}

/// `GRANTS` in the verify-purchase function, e.g. `coins_1000: { coins: 2500 }`.
Map<String, Map<String, int>> _serverGrants() {
  final js = File('functions/verify-purchase/src/main.js').readAsStringSync();
  final block = RegExp(r'const GRANTS = \{([\s\S]*?)\n\};').firstMatch(js)!.group(1)!;
  final out = <String, Map<String, int>>{};
  for (final m in RegExp(r'^\s*(\w+): \{ ([^}]*) \},?$', multiLine: true).allMatches(block)) {
    final fields = <String, int>{};
    for (final f in RegExp(r'(\w+): (\d+)').allMatches(m.group(2)!)) {
      fields[f.group(1)!] = int.parse(f.group(2)!);
    }
    if (fields.isNotEmpty) out[m.group(1)!] = fields;
  }
  return out;
}

/// The regular player of docs/economy.md (1 hour a day, 5x5 boards, three
/// stars on 75% of boards), averaged over weeks 5 to 8. A compact copy of
/// the model: gameplay, level-ups, daily gift, daily quests, the daily
/// puzzle bonus, three bonus videos a day, events, piggy bank and weekly
/// quests. One-time achievements are left out (about 1% in steady state).
({double coinsPerHour, double ticketsPerWeek}) _regularPlayerSteadyState() {
  const minutesPerDay = 60.0, cells = 25, stars = {3: 0.75, 2: 0.22, 1: 0.03};
  const eventsPerWeek = 76 / 52, adsPerDay = 3, adCoins = 40, eventCoins = 300, dailyPuzzleCoins = 50;
  final secondsPerPuzzle = 20 + cells * (1.3 + 0.1 * cells);
  final puzzlesPerDay = minutesPerDay * 60 / secondsPerPuzzle;
  double avg(int Function(int s) f) => stars.entries.fold(0.0, (s, e) => s + e.value * f(e.key));
  final coinsPerPuzzle = avg((s) => Economy.completionCoins(cells, s));
  final xpPerPuzzle = avg((s) => Economy.completionXp(cells, s));
  final dailyQuests = Goals.daily(const [], DateTime(2026, 10, 12)).where((g) => !g.vipOnly).fold<int>(0, (s, g) => s + g.coins);
  final weeklyTickets = Goals.weekly(const [], DateTime(2026, 10, 12)).where((g) => !g.vipOnly).fold<int>(0, (s, g) => s + g.tickets);
  final giftCoins = Economy.dailyRewards.fold<int>(0, (s, r) => s + r.coins);
  final giftTickets = Economy.dailyRewards.fold<int>(0, (s, r) => s + r.tickets);

  var xp = 0.0, level = 1, levelCoins = 0, levelTickets = 0;
  for (var day = 0; day < 56; day++) {
    xp += puzzlesPerDay * xpPerPuzzle;
    final next = LevelRewards.levelForXp(xp.floor());
    for (var l = level + 1; l <= next; l++) {
      if (day >= 28) {
        levelCoins += LevelRewards.forLevel(l).coins;
        levelTickets += LevelRewards.forLevel(l).tickets;
      }
    }
    level = next;
  }
  final puzzlesPerWeek = puzzlesPerDay * 7;
  final piggyOpens = puzzlesPerWeek * Economy.piggyPerPuzzle / Profile.piggyCapacity;
  final coinsPerWeek = puzzlesPerWeek * coinsPerPuzzle +
      levelCoins / 4 +
      giftCoins +
      dailyQuests * 7 +
      dailyPuzzleCoins * 7 +
      adsPerDay * adCoins * 7 +
      eventsPerWeek * eventCoins +
      piggyOpens * Profile.piggyCapacity;
  final ticketsPerWeek = giftTickets + weeklyTickets + eventsPerWeek + levelTickets / 4;
  return (coinsPerHour: coinsPerWeek / (minutesPerDay * 7 / 60), ticketsPerWeek: math.max(0, ticketsPerWeek).toDouble());
}
