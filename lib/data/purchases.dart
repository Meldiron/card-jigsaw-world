import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as enums;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart' show SK2Transaction;

import '../core/appwrite.dart';
import '../core/numbers.dart';
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
  const ProductGrant({this.coins = 0, this.tickets = 0, this.hints = 0, this.peeks = 0, this.magics = 0});
  final int coins;
  final int tickets;
  final int hints;

  /// Peeks and Magic in stock (the helper bundles since 2026-10-17).
  final int peeks;
  final int magics;

  /// Gives the three helpers (Peek, Hint, Magic) rather than a currency.
  bool get helpers => peeks > 0 || magics > 0;

  /// "2,500 coins", "10 tickets", "15 Peeks, 10 Hints, 5 Magic". The helpers carry their names as
  /// the game writes them (the Lucky Wheel, the toolbar).
  String get label => [
        if (coins > 0) '${formatCount(coins)} coins',
        if (tickets > 0) '${formatCount(tickets)} ticket${tickets == 1 ? '' : 's'}',
        if (peeks > 0) '${formatCount(peeks)} Peek${peeks == 1 ? '' : 's'}',
        if (hints > 0) '${formatCount(hints)} Hint${hints == 1 ? '' : 's'}',
        if (magics > 0) '${formatCount(magics)} Magic',
      ].join(', ');
}

/// The store catalogue in one place: what each product gives and the USD
/// price shown until StoreKit returns the localised one.
///
/// Three places must agree on the grants (test/economy_test.dart checks
/// them): this table (what the app shows), `GRANTS` in
/// `functions/api/src/purchase.js` and `functions/verify-purchase/src/main.js`
/// (what the server credits; builds up to 124 call verify-purchase) and
/// `store/metadata/subscriptions/consumables.json` (App Store names and
/// prices). The amounts come from the economy model in docs/economy.md:
/// every coin and ticket bundle is worth about the same per dollar, counting a
/// ticket as [ticketCoinValue] coins, and the bigger bundles add up to about a
/// fifth more. The two helper bundles (ids `hints_*`, owner 2026-10-17) give
/// Peeks, Hints and Magic and are meant to be the better deal: about a quarter
/// to a half more per dollar, counting each helper at its in-game price.
class StoreProducts {
  StoreProducts._();

  static const grants = <String, ProductGrant>{
    ProductIds.coins1000: ProductGrant(coins: 2500),
    ProductIds.coins3000: ProductGrant(coins: 8000),
    ProductIds.coins5500: ProductGrant(coins: 14000),
    ProductIds.coins12000: ProductGrant(coins: 30000),
    ProductIds.tickets5: ProductGrant(tickets: 10),
    ProductIds.tickets15: ProductGrant(tickets: 30),
    // 16 and 48 hints until 2026-10-17.
    ProductIds.hints5: ProductGrant(peeks: 15, hints: 10, magics: 5),
    ProductIds.hints15: ProductGrant(peeks: 50, hints: 30, magics: 15),
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

  /// How much less the yearly plan costs than twelve months, in whole percent
  /// rounded down (58 for $14.99 against $2.99). Both prices must come from the
  /// same source (the App Store, or both fallbacks); null when there is no saving.
  static int? yearlySavingPercent(double monthly, double yearly) {
    if (monthly <= 0 || yearly <= 0) return null;
    final percent = ((1 - yearly / (monthly * 12)) * 100).floor();
    return percent >= 5 ? percent : null;
  }
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

/// What the server granted for a verified purchase.
class PurchaseGrant {
  const PurchaseGrant({this.coins = 0, this.tickets = 0, this.hints = 0, this.peeks = 0, this.magics = 0, this.vipExpiresAt});
  final int coins;
  final int tickets;
  final int hints;
  final int peeks;
  final int magics;
  final DateTime? vipExpiresAt;

  factory PurchaseGrant.fromJson(Map<String, dynamic> j) => PurchaseGrant(
        coins: (j['coins'] as num?)?.toInt() ?? 0,
        tickets: (j['tickets'] as num?)?.toInt() ?? 0,
        hints: (j['hints'] as num?)?.toInt() ?? 0,
        peeks: (j['peeks'] as num?)?.toInt() ?? 0,
        magics: (j['magics'] as num?)?.toInt() ?? 0,
        vipExpiresAt: j['vipExpiresAt'] == null ? null : DateTime.tryParse(j['vipExpiresAt'].toString())?.toLocal(),
      );

  ProductGrant get product => ProductGrant(coins: coins, tickets: tickets, hints: hints, peeks: peeks, magics: magics);

  /// "10 tickets", "2,500 coins", "15 Peeks, 10 Hints, 5 Magic".
  String get label => product.label;
}

/// Coins, tickets, hints, Peeks and Magic as the server has them after a grant (a function deployed
/// before the helper bundles answers without Peeks and Magic: 0).
typedef PurchaseBalances = ({int coins, int tickets, int hints, int peeks, int magics});

/// Events surfaced to the UI.
sealed class PurchaseEvent {
  const PurchaseEvent();
}

/// The App Store took the payment; the server is checking the purchase and adding what it gives.
class PurchaseVerifying extends PurchaseEvent {
  const PurchaseVerifying(this.productId, {this.restored = false});
  final String productId;
  final bool restored;
}

class PurchaseVerified extends PurchaseEvent {
  const PurchaseVerified(this.productId, this.grant, {this.alreadyApplied = false, this.restored = false, this.balances});
  final String productId;
  final PurchaseGrant grant;
  final bool alreadyApplied;
  final bool restored;

  /// The player's coins, tickets, hints, Peeks and Magic right after the grant (null when the
  /// purchase had been added before).
  final PurchaseBalances? balances;
}

/// The check did not get through (no connection, the server starting up or busy). It runs again
/// after [wait]; the App Store keeps the purchase open until it is added.
class PurchaseRetrying extends PurchaseEvent {
  const PurchaseRetrying(this.productId, {required this.attempt, required this.wait});
  final String productId;
  final int attempt;
  final Duration wait;
}

class PurchaseFailed extends PurchaseEvent {
  const PurchaseFailed(this.message, {this.productId, this.paid = false});
  final String message;
  final String? productId;

  /// The payment went through but the server did not accept the purchase. The App Store keeps it
  /// open, so it is checked again on the next launch.
  final bool paid;
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
/// completed transaction with the server (`/purchase/verify` on the `api`
/// Appwrite Function), which applies the grant server-side.
///
/// [start] runs at launch (Apple: listen for transactions as soon as the app starts), so a
/// purchase paid while the app was closed, restarted or on another screen is added at once. A
/// check that does not get through is tried again by itself ([retryDelays], then every minute)
/// and when the app comes back ([checkOpenPurchases]); the transaction is finished only once the
/// server has added it, so the App Store keeps it until then.
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
  DateTime? _warmedAt;

  /// Seconds between tries of a check that did not get through; the last one repeats.
  static const retryDelays = [2, 4, 8, 15, 30, 60];

  /// Shown when StoreKit itself fails (before any payment).
  static const storeErrorMessage = 'The App Store could not complete the purchase. Try again in a moment.';

  /// Product id of each transaction being checked right now, by transaction id. StoreKit can hand
  /// over one transaction twice (the purchase call and the updates stream, or a launch sweep).
  final _checking = <String, String>{};

  /// Checks that did not get through, waiting for their next try.
  final _waiting = <String, ({PurchaseDetails details, bool restored})>{};
  final _attempts = <String, int>{};
  final _timers = <String, Timer>{};

  /// Added this session (finished, or about to be).
  final _added = <String>{};

  /// Refused by the server this session; checked again on the next launch.
  final _rejected = <String>{};

  Stream<PurchaseEvent> get events => _events.stream;

  /// Idempotent: listens to the purchase stream (StoreKit 2 `Transaction.updates`) and checks the
  /// purchases the App Store still has open.
  Future<void> start() async {
    if (_started || !supportsPurchases) return;
    _started = true;
    // StoreKit 2 is the default transport in in_app_purchase_storekit 0.4+,
    // so verificationData.serverVerificationData is the signed JWS transaction.
    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (e) => _events.add(PurchaseFailed('$e')));
    unawaited(checkOpenPurchases());
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

  /// Starts a purchase. Completes when the App Store sheet closes; the outcome arrives as events.
  Future<bool> buy(ProductDetails product) async {
    if (!supportsPurchases) {
      _events.add(PurchaseFailed(purchasesOnIphoneMessage, productId: product.id));
      return false;
    }
    warmUp();
    final param = PurchaseParam(productDetails: product);
    try {
      if (ProductIds.isSubscription(product.id)) {
        return await _iap.buyNonConsumable(purchaseParam: param);
      }
      return await _iap.buyConsumable(purchaseParam: param);
    } on PlatformException catch (e) {
      // A purchase of this product is paid but not added yet: StoreKit refuses another one.
      if (e.code == 'storekit_duplicate_product_object') return _resumeOpen(product.id);
      debugPrint('buy ${product.id}: $e');
      _events.add(PurchaseFailed(storeErrorMessage, productId: product.id));
      return false;
    } catch (e) {
      debugPrint('buy ${product.id}: $e');
      _events.add(PurchaseFailed(storeErrorMessage, productId: product.id));
      return false;
    }
  }

  /// Wakes the `api` function while the player is still in the App Store sheet, so the check after
  /// the payment does not wait for a cold start (about 5 s). At most every 2 minutes.
  void warmUp() {
    if (!supportsPurchases) return;
    final now = DateTime.now();
    if (_warmedAt != null && now.difference(_warmedAt!) < const Duration(minutes: 2)) return;
    _warmedAt = now;
    Functions(_client)
        .createExecution(functionId: AppwriteConfig.apiFunction, path: '/health', method: enums.ExecutionMethod.gET, xasync: true)
        .then((_) {}, onError: (Object e) => debugPrint('api warm-up: $e'));
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

  /// Checks at once every purchase that is paid but not added: the ones waiting for another try
  /// and the ones the App Store still has open (paid while the app was closed, an approved Ask to
  /// Buy). Runs at launch and when the app comes back. Returns their product ids.
  Future<Set<String>> checkOpenPurchases() async {
    final products = <String>{};
    for (final id in [..._waiting.keys]) {
      _timers.remove(id)?.cancel();
      final w = _waiting.remove(id)!;
      products.add(w.details.productID);
      unawaited(_verify(w.details, restored: w.restored));
    }
    for (final t in _started ? await _unfinished() : const <SK2Transaction>[]) {
      if (_rejected.contains(t.id)) continue;
      products.add(t.productId);
      unawaited(_verify(_details(t), restored: false));
    }
    return products;
  }

  Future<List<SK2Transaction>> _unfinished() async {
    if (defaultTargetPlatform != TargetPlatform.iOS && defaultTargetPlatform != TargetPlatform.macOS) return const [];
    try {
      return await SK2Transaction.unfinishedTransactions();
    } catch (e) {
      debugPrint('unfinished transactions: $e');
      return const [];
    }
  }

  static PurchaseDetails _details(SK2Transaction t) => SK2PurchaseDetails(
        productID: t.productId,
        purchaseID: t.id,
        verificationData: PurchaseVerificationData(localVerificationData: t.jsonRepresentation ?? '', serverVerificationData: t.receiptData ?? '', source: kIAPSource),
        transactionDate: t.purchaseDate,
        status: PurchaseStatus.purchased,
      );

  /// StoreKit refused a new purchase of [productId] because an earlier one is still open: check
  /// that one now instead.
  Future<bool> _resumeOpen(String productId) async {
    final open = await checkOpenPurchases();
    if (open.contains(productId) || _checking.containsValue(productId)) {
      _events.add(PurchaseVerifying(productId));
      return true;
    }
    _events.add(PurchaseFailed('Your last purchase of this item is still being completed. Try again in a minute.', productId: productId));
    return false;
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
          debugPrint('purchase ${p.productID}: ${p.error}');
          _events.add(PurchaseFailed(storeErrorMessage, productId: p.productID));
          await _complete(p);
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verify(p, restored: p.status == PurchaseStatus.restored);
      }
    }
  }

  Future<void> _verify(PurchaseDetails p, {required bool restored}) async {
    final id = p.purchaseID ?? p.verificationData.serverVerificationData;
    if (_added.contains(id)) {
      await _complete(p);
      return;
    }
    if (_checking.containsKey(id)) return;
    _checking[id] = p.productID;
    _events.add(PurchaseVerifying(p.productID, restored: restored));
    try {
      final (status, text) = await sendForVerification(p.verificationData.serverVerificationData, p.productID);
      Map<String, dynamic> body;
      try {
        body = text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        body = <String, dynamic>{};
      }
      if (body['ok'] == true) {
        _forget(id);
        _added.add(id);
        final grant = PurchaseGrant.fromJson((body['grant'] as Map?)?.cast<String, dynamic>() ?? const {});
        final b = body['balances'];
        final balances = b is Map ? (coins: _int(b['coins']), tickets: _int(b['tickets']), hints: _int(b['hints']), peeks: _int(b['peeks']), magics: _int(b['magics'])) : null;
        if (restored || _restoring) _restoredCount++;
        _events.add(PurchaseVerified(p.productID, grant, alreadyApplied: body['alreadyApplied'] == true, restored: restored, balances: balances));
        await _complete(p);
      } else if (status >= 400 && status < 500 && status != 401 && status != 408 && status != 429) {
        // Refused (not verifiable, refunded, the family limit): another try now would answer the
        // same. The transaction stays open, so the next launch asks again.
        _forget(id);
        _rejected.add(id);
        _events.add(PurchaseFailed(body['error']?.toString() ?? 'The purchase could not be confirmed ($status).', productId: p.productID, paid: true));
      } else {
        debugPrint('verify ${p.productID}: $status $text');
        _retryLater(id, p, restored);
      }
    } catch (e) {
      debugPrint('verify ${p.productID}: $e');
      _retryLater(id, p, restored);
    } finally {
      _checking.remove(id);
    }
  }

  /// `POST /purchase/verify` on the `api` function: the answer's status and body.
  @protected
  Future<(int, String)> sendForVerification(String jws, String productId) async {
    final exec = await Functions(_client).createExecution(
      functionId: AppwriteConfig.apiFunction,
      body: jsonEncode({'jws': jws, 'productId': productId}),
      method: enums.ExecutionMethod.pOST,
      path: '/purchase/verify',
    );
    return (exec.responseStatusCode, exec.responseBody);
  }

  /// Hands [purchases] over as the purchase stream would.
  @visibleForTesting
  Future<void> debugDeliver(List<PurchaseDetails> purchases) => _onPurchases(purchases);

  void _retryLater(String id, PurchaseDetails p, bool restored) {
    final attempt = _attempts[id] = (_attempts[id] ?? 0) + 1;
    final wait = Duration(seconds: retryDelays[min(attempt, retryDelays.length) - 1]);
    _waiting[id] = (details: p, restored: restored);
    _timers.remove(id)?.cancel();
    _timers[id] = Timer(wait, () {
      _timers.remove(id);
      final w = _waiting.remove(id);
      if (w != null) unawaited(_verify(w.details, restored: w.restored));
    });
    _events.add(PurchaseRetrying(p.productID, attempt: attempt, wait: wait));
  }

  void _forget(String id) {
    _waiting.remove(id);
    _attempts.remove(id);
    _timers.remove(id)?.cancel();
  }

  static int _int(Object? v) => v is num ? v.toInt() : 0;

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
    for (final t in _timers.values) {
      t.cancel();
    }
    _sub?.cancel();
    _events.close();
  }
}
