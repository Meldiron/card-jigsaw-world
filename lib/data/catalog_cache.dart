/// Where the catalogue kept on the device lives (`CatalogSync`, docs/catalog-sync.md): the iPhone keeps
/// it in SharedPreferences as before; the web build in IndexedDB, because localStorage (5 MB per site,
/// shared with the save and the settings) cannot hold it and refused it with `QuotaExceededError`, so
/// every launch downloaded the snapshot again.
library;

import 'catalog_cache_stub.dart' if (dart.library.js_interop) 'catalog_cache_web.dart' as platform;
import 'local_store.dart';

abstract interface class CatalogCache {
  /// The stored catalogue (the JSON `CatalogSync` wrote), or null when there is none.
  Future<Map<String, dynamic>?> read();

  /// Stores [json] in place of what was there. Throws when it cannot be stored.
  Future<void> write(Map<String, dynamic> json);

  /// The cache of this platform: SharedPreferences on the iPhone, IndexedDB on the web.
  static CatalogCache of(LocalStore store) => platform.catalogCacheFor(store);
}

/// The catalogue as one SharedPreferences value (`catalog`), as the iPhone has always kept it.
class PrefsCatalogCache implements CatalogCache {
  PrefsCatalogCache(this.store);
  final LocalStore store;

  /// The SharedPreferences key (on the web, localStorage `flutter.catalog`).
  static const key = 'catalog';

  @override
  Future<Map<String, dynamic>?> read() async => store.getJson(key);

  @override
  Future<void> write(Map<String, dynamic> json) => store.setJson(key, json);
}
