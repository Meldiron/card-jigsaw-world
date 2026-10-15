import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/appwrite.dart';
import '../core/platform.dart';
import '../data/purchases.dart';
import 'profile.dart';
import 'sync.dart';

final purchaseServiceProvider = Provider<PurchaseService>((ref) {
  final service = PurchaseService(ref.watch(appwriteClientProvider));
  ref.onDispose(service.dispose);
  return service;
});

/// Whether the platform store can be used (false on simulators without a
/// StoreKit configuration, and on web).
final storeAvailableProvider = FutureProvider<bool>((ref) async {
  if (!supportsPurchases) return false;
  final service = ref.watch(purchaseServiceProvider);
  await service.start();
  return service.isAvailable();
});

/// Localised product details keyed by product id; empty when the store is down.
final productsProvider = FutureProvider<Map<String, ProductDetails>>((ref) async {
  final available = await ref.watch(storeAvailableProvider.future);
  if (!available) return const {};
  try {
    return await ref.watch(purchaseServiceProvider).queryProducts();
  } catch (_) {
    return const {};
  }
});

/// Where a purchase stands, from the tap on a bundle to the coins in the header.
enum PurchaseStage {
  /// Nothing going on.
  idle,

  /// The App Store sheet is open.
  paying,

  /// The App Store sheet closed and the App Store is still processing the payment (TestFlight's
  /// sandbox can take a while).
  waiting,

  /// Paid: the server is checking the purchase and adding it.
  adding,

  /// Added; [PurchaseFlowState.grant] says what.
  added,

  /// Paid, but the server did not accept it; the App Store keeps it and the next launch asks again.
  notAdded,

  /// The App Store could not complete the purchase (nothing was paid).
  storeError,

  /// Ask to Buy: waiting for a parent's approval; added once approved.
  awaitingApproval,
}

@immutable
class PurchaseFlowState {
  const PurchaseFlowState({this.stage = PurchaseStage.idle, this.productId, this.watching = false, this.slow = false, this.grant, this.balances, this.message});

  final PurchaseStage stage;
  final String? productId;

  /// The player is looking at it: they started it and the purchase sheet is open (or about to
  /// open). Otherwise a toast reports the outcome.
  final bool watching;

  /// Adding takes longer than [PurchaseFlow.slowAfter].
  final bool slow;
  final PurchaseGrant? grant;
  final PurchaseBalances? balances;
  final String? message;

  /// A purchase the player follows is under way: the store's buttons wait.
  bool get busy => stage == PurchaseStage.paying || ((stage == PurchaseStage.waiting || stage == PurchaseStage.adding) && watching);

  PurchaseFlowState copyWith({PurchaseStage? stage, bool? watching, bool? slow, PurchaseGrant? grant, PurchaseBalances? balances, String? message}) => PurchaseFlowState(
        stage: stage ?? this.stage,
        productId: productId,
        watching: watching ?? this.watching,
        slow: slow ?? this.slow,
        grant: grant ?? this.grant,
        balances: balances ?? this.balances,
        message: message ?? this.message,
      );
}

/// The purchase flow the screens follow ([PurchaseHost] shows it): the store tile waits while the
/// App Store sheet is open, a sheet shows "Adding 10 tickets" once the payment is in and "10
/// tickets added" once the server added them and the save shows them. A purchase the player did
/// not follow (paid while the app was closed, an approved Ask to Buy, a sheet they closed) ends in
/// a toast instead.
class PurchaseFlow extends Notifier<PurchaseFlowState> {
  /// After this long "Adding" says it takes longer than usual.
  static const slowAfter = Duration(seconds: 10);

  Timer? _slow;
  Timer? _waitTimer;
  Timer? _outcome;

  PurchaseService get _service => ref.read(purchaseServiceProvider);

  @override
  PurchaseFlowState build() {
    final sub = ref.watch(purchaseServiceProvider).events.listen(_on);
    ref.onDispose(() {
      sub.cancel();
      _slow?.cancel();
      _waitTimer?.cancel();
      _outcome?.cancel();
    });
    return const PurchaseFlowState();
  }

  /// Listens for transactions; called at launch once the player is signed in (the check needs the
  /// session).
  Future<void> start() => _service.start();

  /// Buys [product]: the App Store sheet opens and the stages follow its events.
  Future<void> buy(ProductDetails product) async {
    if (state.busy) return;
    state = PurchaseFlowState(stage: PurchaseStage.paying, productId: product.id, watching: true);
    final started = await _service.buy(product);
    bool stillPaying() => state.stage == PurchaseStage.paying && state.productId == product.id;
    if (!stillPaying()) return;
    if (!started) {
      clear();
      return;
    }
    // StoreKit sends the outcome as its sheet closes, just before this call returns. Should it get
    // lost, the tile does not wait forever.
    _outcome?.cancel();
    _outcome = Timer(const Duration(seconds: 10), () {
      if (stillPaying()) clear();
    });
  }

  /// The app is back in the foreground. When that is the App Store sheet closing with the payment
  /// still processing, the purchase sheet opens and says so. Purchases waiting for another check
  /// are checked now.
  void onResume() {
    unawaited(_service.checkOpenPurchases());
    if (state.stage != PurchaseStage.paying) return;
    final id = state.productId;
    _waitTimer?.cancel();
    // A cancel or the purchase itself usually arrives within a moment; only a slow App Store waits.
    _waitTimer = Timer(const Duration(milliseconds: 1500), () {
      if (state.stage == PurchaseStage.paying && state.productId == id) state = state.copyWith(stage: PurchaseStage.waiting);
    });
  }

  /// The player closed the purchase sheet: a purchase still on its way finishes in the background
  /// and a toast reports it; a finished one is cleared.
  void closeSheet() {
    if (state.stage == PurchaseStage.waiting || state.stage == PurchaseStage.adding) {
      state = state.copyWith(watching: false);
    } else if (!state.busy) {
      clear();
    }
  }

  /// Back to idle once the host has shown the outcome.
  void clear() {
    _slow?.cancel();
    _waitTimer?.cancel();
    _outcome?.cancel();
    state = const PurchaseFlowState();
  }

  bool _isCurrent(String? productId) => productId != null && state.productId == productId && const {PurchaseStage.paying, PurchaseStage.waiting, PurchaseStage.adding}.contains(state.stage);

  void _on(PurchaseEvent e) {
    switch (e) {
      case PurchaseVerifying(:final productId, :final restored):
        if (restored) return;
        ref.read(syncProvider.notifier).expectServerChange();
        if (!_isCurrent(productId) || state.stage == PurchaseStage.adding) return;
        _waitTimer?.cancel();
        state = state.copyWith(stage: PurchaseStage.adding);
        _slow?.cancel();
        _slow = Timer(slowAfter, () {
          if (state.stage == PurchaseStage.adding && state.productId == productId) state = state.copyWith(slow: true);
        });
      case PurchaseVerified():
        if (!e.restored) unawaited(_added(e));
      case PurchaseRetrying():
        break;
      case PurchaseFailed(:final productId, :final paid, :final message):
        if (!_isCurrent(productId)) return;
        _slow?.cancel();
        _waitTimer?.cancel();
        state = state.copyWith(stage: paid ? PurchaseStage.notAdded : PurchaseStage.storeError, message: message);
      case PurchaseCanceled():
        if (state.stage == PurchaseStage.paying || state.stage == PurchaseStage.waiting) clear();
      case PurchasePending(:final productId):
        if (_isCurrent(productId)) state = state.copyWith(stage: PurchaseStage.awaitingApproval);
      case RestoreFinished():
        break;
    }
  }

  Future<void> _added(PurchaseVerified e) async {
    final current = _isCurrent(e.productId);
    final wasVip = ref.read(profileProvider).value?.isVip ?? false;
    // Show it once the save has it, so the sheet and the header say the same.
    try {
      await ref.read(syncProvider.notifier).sync(silent: true).timeout(const Duration(seconds: 6));
    } catch (_) {}
    if (current) {
      if (!_isCurrent(e.productId)) return;
      _slow?.cancel();
      state = state.copyWith(stage: PurchaseStage.added, grant: e.grant, balances: e.balances);
      return;
    }
    // Not followed by the player: news only when it gives something new. A VIP renewal is not.
    if (e.alreadyApplied || (e.grant.vipExpiresAt != null && wasVip) || state.busy) return;
    state = PurchaseFlowState(stage: PurchaseStage.added, productId: e.productId, grant: e.grant, balances: e.balances);
  }
}

final purchaseFlowProvider = NotifierProvider<PurchaseFlow, PurchaseFlowState>(PurchaseFlow.new);
