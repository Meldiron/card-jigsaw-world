import 'dart:async';
import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as enums;
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

import '../core/platform.dart';

/// Product identifiers as configured in App Store Connect / Products.storekit.
/// Apple ids cannot be renamed, so the number in a consumable id is
/// historical: [StoreProducts.grants] says what each one gives.
class ProductIds {
  ProductIds._();
  static const coins1000 = 'coins_1000';
  static const coins3000 = 'coins_3000';
  static const coins5500 = 'coins_5500';
  static const coins12000 = 'coins_12000';
  static const tickets5 = 'tickets_5';
  static const tickets15 = 'tickets_15';
  static const hints5 = 'hints_5';
  static const hints15 = 'hints_15';
  static const vipMonthly = 'vip_monthly';
  static const vipYearly = 'vip_yearly';

  static const consumables = {coins1000, coins3000, coins5500, coins12000, tickets5, tickets15, hints5, hints15};
  static const subscriptions = {vipMonthly, vipYearly};
  static const all = {...consumables, ...subscriptions};

  static bool isSubscription(String id) => subscriptions.contains(id);
}

/// What one consumable purchase gives.
class ProductGrant {
  const ProductGrant({this.coins = 0, this.tickets = 0, this.hints = 0});
  final int coins;
  final int tickets;
  final int hints;

  /// "2,500 coins", "10 tickets", "40 hints".
  String get label => [
        if (coins > 0) '${groupThousands(coins)} coins',
        if (tickets > 0) '${groupThousands(tickets)} ticket${tickets == 1 ? '' : 's'}',
        if (hints > 0) '${groupThousands(hints)} hint${hints == 1 ? '' : 's'}',
      ].join(', ');
}

/// The store catalogue in one place: what each product gives and the USD
/// price shown until StoreKit returns the localised one.
///
/// Three places must agree on the grants (test/economy_test.dart checks
/// them): this table (what the app shows), `GRANTS` in
/// `functions/verify-purchase/src/main.js` (what the server credits) and
/// `store/metadata/subscriptions/consumables.json` (App Store names and
/// prices). The amounts come from the economy model in docs/economy.md:
/// every bundle is worth about the same per dollar, counting a ticket as
/// [ticketCoinValue] coins and a hint as its in-game price of 60 coins, and
/// the bigger bundles add up to about a fifth more.
class StoreProducts {
  StoreProducts._();

  static const grants = <String, ProductGrant>{
    ProductIds.coins1000: ProductGrant(coins: 2500),
    ProductIds.coins3000: ProductGrant(coins: 8000),
    ProductIds.coins5500: ProductGrant(coins: 14000),
    ProductIds.coins12000: ProductGrant(coins: 30000),
    ProductIds.tickets5: ProductGrant(tickets: 10),
    ProductIds.tickets15: ProductGrant(tickets: 30),
    ProductIds.hints5: ProductGrant(hints: 40),
    ProductIds.hints15: ProductGrant(hints: 120),
  };

  /// USD customer prices (consumables.json and vip_*.json `customerPrice`).
  static const usdPrices = <String, String>{
    ProductIds.coins1000: '0.99',
    ProductIds.coins3000: '2.99',
    ProductIds.coins5500: '4.99',
    ProductIds.coins12000: '9.99',
    ProductIds.tickets5: '1.99',
    ProductIds.tickets15: '4.99',
    ProductIds.hints5: '0.99',
    ProductIds.hints15: '2.49',
    ProductIds.vipMonthly: '2.99',
    ProductIds.vipYearly: '14.99',
  };

  /// Length of the free introductory offer on both VIP plans.
  static const vipTrialDays = 7;

  /// What a ticket is worth in coins in the economy model: it opens a full
  /// piggy bank (500 coins), and a 10-ticket pack sits just above the
  /// 5,000-coin showcase packs.
  static const ticketCoinValue = 500;

  static ProductGrant grant(String id) => grants[id] ?? const ProductGrant();

  /// "$0.99": the fallback shown until the App Store price loads.
  static String price(String id) => '\$${usdPrices[id] ?? ''}';

  /// Extra coins per dollar a coin bundle gives over the smallest one, in
  /// whole percent rounded down (so a badge never overstates it).
  static int coinBonusPercent(String id) {
    final base = grant(ProductIds.coins1000).coins / double.parse(usdPrices[ProductIds.coins1000]!);
    final perDollar = grant(id).coins / double.parse(usdPrices[id]!);
    return ((perDollar / base - 1) * 100).floor();
  }

  /// "7 days free, then $2.99/month".
  static String vipTrialLine([String? monthlyPrice]) => '$vipTrialDays days free, then ${monthlyPrice ?? price(ProductIds.vipMonthly)}/month';
}

/// Pack prices as set by `tools/store/apply_pack_prices.py` (docs/economy.md,
/// "Pack prices"). Prices live in the `packs` rows; these mirror the policy
/// for copy such as the house ads. test/economy_test.dart compares them with
/// the script.
class PackPricePolicy {
  PackPricePolicy._();
  static const minCoins = 1000;
  static const maxCoins = 5000;

  /// A 24-picture pack on the standard tier.
  static const standardPackCoins = 2400;

  /// Ticket packs cost 8, 10 or 12 tickets (two fewer for small packs).
  static const ticketPackTickets = [8, 10, 12];
}

/// 12000 -> "12,000".
String groupThousands(int v) {
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// What the server granted for a verified purchase.
class PurchaseGrant {
  const PurchaseGrant({this.coins = 0, this.tickets = 0, this.hints = 0, this.vipExpiresAt});
  final int coins;
  final int tickets;
  final int hints;
  final DateTime? vipExpiresAt;

  factory PurchaseGrant.fromJson(Map<String, dynamic> j) => PurchaseGrant(
        coins: (j['coins'] as num?)?.toInt() ?? 0,
        tickets: (j['tickets'] as num?)?.toInt() ?? 0,
        hints: (j['hints'] as num?)?.toInt() ?? 0,
        vipExpiresAt: j['vipExpiresAt'] == null ? null : DateTime.tryParse(j['vipExpiresAt'].toString())?.toLocal(),
      );
}

/// Events surfaced to the UI.
sealed class PurchaseEvent {
  const PurchaseEvent();
}

class PurchaseVerified extends PurchaseEvent {
  const PurchaseVerified(this.productId, this.grant, {this.alreadyApplied = false, this.restored = false});
  final String productId;
  final PurchaseGrant grant;
  final bool alreadyApplied;
  final bool restored;
}

class PurchaseFailed extends PurchaseEvent {
  const PurchaseFailed(this.message, {this.productId});
  final String message;
  final String? productId;
}

class PurchaseCanceled extends PurchaseEvent {
  const PurchaseCanceled();
}

class PurchasePending extends PurchaseEvent {
  const PurchasePending(this.productId);
  final String productId;
}

class RestoreFinished extends PurchaseEvent {
  const RestoreFinished(this.count);
  final int count;
}

/// Wraps the `in_app_purchase` plugin (StoreKit 2 on iOS) and verifies every
/// completed transaction with the `verify-purchase` Appwrite Function, which
/// applies the grant server-side.
///
/// On web (no plugin implementation) every method is a safe no-op:
/// [start] does nothing, [isAvailable] is false, [queryProducts] is empty,
/// [presentCodeRedemptionSheet] returns false. `InAppPurchase.instance` is
/// never read there.
class PurchaseService {
  PurchaseService(this._client);

  final Client _client;
  // Lazy so the plugin singleton is only touched where it exists.
  late final InAppPurchase _iap = InAppPurchase.instance;
  final _events = StreamController<PurchaseEvent>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _sub;
  bool _started = false;
  bool _restoring = false;
  int _restoredCount = 0;

  Stream<PurchaseEvent> get events => _events.stream;

  /// Idempotent: enables StoreKit 2 and starts listening to the purchase stream.
  Future<void> start() async {
    if (_started || !supportsPurchases) return;
    _started = true;
    // StoreKit 2 is the default transport in in_app_purchase_storekit 0.4+,
    // so verificationData.serverVerificationData is the signed JWS transaction.
    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (e) => _events.add(PurchaseFailed('$e')));
  }

  Future<bool> isAvailable() async {
    if (!supportsPurchases) return false;
    try {
      return await _iap.isAvailable();
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, ProductDetails>> queryProducts() async {
    if (!supportsPurchases) return const {};
    final res = await _iap.queryProductDetails(ProductIds.all);
    if (res.notFoundIDs.isNotEmpty) debugPrint('Products not found: ${res.notFoundIDs}');
    return {for (final p in res.productDetails) p.id: p};
  }

  Future<bool> buy(ProductDetails product) async {
    if (!supportsPurchases) {
      _events.add(PurchaseFailed(purchasesOnIphoneMessage, productId: product.id));
      return false;
    }
    final param = PurchaseParam(productDetails: product);
    try {
      if (ProductIds.isSubscription(product.id)) {
        return await _iap.buyNonConsumable(purchaseParam: param);
      }
      return await _iap.buyConsumable(purchaseParam: param);
    } catch (e) {
      _events.add(PurchaseFailed('$e', productId: product.id));
      return false;
    }
  }

  /// Opens the App Store sheet where a player types a VIP gift code (an
  /// App Store Connect subscription offer code). The resulting subscription
  /// transaction arrives on the purchase stream like any other purchase and is
  /// verified server-side before VIP is granted. iOS and macOS only.
  Future<bool> presentCodeRedemptionSheet() async {
    if (!supportsGiftCodes) return false;
    try {
      await _iap.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>().presentCodeRedemptionSheet();
      return true;
    } catch (e) {
      _events.add(PurchaseFailed('Could not open the code sheet: $e'));
      return false;
    }
  }

  Future<void> restorePurchases() async {
    if (!supportsPurchases) {
      _events.add(const RestoreFinished(0));
      return;
    }
    _restoring = true;
    _restoredCount = 0;
    try {
      await _iap.restorePurchases();
    } catch (e) {
      _events.add(PurchaseFailed('$e'));
    }
    // StoreKit delivers restored transactions on the stream; give it a moment
    // then report. Consumables are never restored, only the subscription.
    await Future.delayed(const Duration(seconds: 2));
    _restoring = false;
    _events.add(RestoreFinished(_restoredCount));
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          _events.add(PurchasePending(p.productID));
        case PurchaseStatus.canceled:
          _events.add(const PurchaseCanceled());
          await _complete(p);
        case PurchaseStatus.error:
          _events.add(PurchaseFailed(p.error?.message ?? 'Purchase failed', productId: p.productID));
          await _complete(p);
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verify(p, restored: p.status == PurchaseStatus.restored);
      }
    }
  }

  Future<void> _verify(PurchaseDetails p, {required bool restored}) async {
    try {
      final functions = Functions(_client);
      final exec = await functions.createExecution(
        functionId: 'verify-purchase',
        body: jsonEncode({'jws': p.verificationData.serverVerificationData, 'productId': p.productID}),
        method: enums.ExecutionMethod.pOST,
        path: '/verify',
      );
      final body = exec.responseBody.isEmpty ? <String, dynamic>{} : jsonDecode(exec.responseBody) as Map<String, dynamic>;
      if (body['ok'] == true) {
        final grant = PurchaseGrant.fromJson((body['grant'] as Map?)?.cast<String, dynamic>() ?? const {});
        if (restored || _restoring) _restoredCount++;
        _events.add(PurchaseVerified(p.productID, grant, alreadyApplied: body['alreadyApplied'] == true, restored: restored));
        await _complete(p);
      } else {
        // Leave the transaction unfinished so StoreKit re-delivers it later.
        _events.add(PurchaseFailed(body['error']?.toString() ?? 'Verification failed (${exec.responseStatusCode})', productId: p.productID));
      }
    } catch (e) {
      _events.add(PurchaseFailed('Could not verify purchase: $e', productId: p.productID));
    }
  }

  Future<void> _complete(PurchaseDetails p) async {
    if (p.pendingCompletePurchase) {
      try {
        await _iap.completePurchase(p);
      } catch (e) {
        debugPrint('completePurchase failed: $e');
      }
    }
  }

  void dispose() {
    _sub?.cancel();
    _events.close();
  }
}
