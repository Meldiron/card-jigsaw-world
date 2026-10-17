import 'catalog_cache.dart';
import 'local_store.dart';

/// Apps (the iPhone): SharedPreferences, as before.
CatalogCache catalogCacheFor(LocalStore store) => PrefsCatalogCache(store);
