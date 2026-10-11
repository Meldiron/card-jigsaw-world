import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/appwrite.dart';
import '../data/purchases.dart';

final purchaseServiceProvider = Provider<PurchaseService>((ref) {
  final service = PurchaseService(ref.watch(appwriteClientProvider));
  ref.onDispose(service.dispose);
  return service;
});

/// Whether the platform store can be used (false on simulators without a
/// StoreKit configuration, and on web).
final storeAvailableProvider = FutureProvider<bool>((ref) async {
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
