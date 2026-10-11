import 'dart:async';
import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as enums;
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Product identifiers as configured in App Store Connect / Products.storekit.
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
class PurchaseService {
  PurchaseService(this._client);

  final Client _client;
  final _iap = InAppPurchase.instance;
  final _events = StreamController<PurchaseEvent>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _sub;
  bool _started = false;
  bool _restoring = false;
  int _restoredCount = 0;

  Stream<PurchaseEvent> get events => _events.stream;

  /// Idempotent: enables StoreKit 2 and starts listening to the purchase stream.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    // StoreKit 2 is the default transport in in_app_purchase_storekit 0.4+,
    // so verificationData.serverVerificationData is the signed JWS transaction.
    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (e) => _events.add(PurchaseFailed('$e')));
  }

  Future<bool> isAvailable() async {
    try {
      return await _iap.isAvailable();
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, ProductDetails>> queryProducts() async {
    final res = await _iap.queryProductDetails(ProductIds.all);
    if (res.notFoundIDs.isNotEmpty) debugPrint('Products not found: ${res.notFoundIDs}');
    return {for (final p in res.productDetails) p.id: p};
  }

  Future<bool> buy(ProductDetails product) async {
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

  Future<void> restorePurchases() async {
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
