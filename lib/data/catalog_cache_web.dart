import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'catalog_cache.dart';
import 'local_store.dart';

/// The web build: IndexedDB (no new package, nothing leaves the browser).
CatalogCache catalogCacheFor(LocalStore store) => IndexedDbCatalogCache(store);

/// The catalogue as one JSON string in the browser's IndexedDB (database `carden`, store `cache`,
/// key `catalog`). Its room is a share of the disk, not localStorage's 5 MB, which the catalogue
/// (about 8,700 rows) overflows. A catalogue an earlier build left in localStorage (when it still
/// fitted) moves over once and leaves localStorage, freeing its room for the save. Where IndexedDB
/// cannot be opened (a browser that refuses it, say), localStorage is used as before.
class IndexedDbCatalogCache implements CatalogCache {
  IndexedDbCatalogCache(this._store);
  final LocalStore _store;

  static const _database = 'carden';
  static const _table = 'cache';
  static const _key = 'catalog';

  Future<web.IDBDatabase>? _db;

  late final _prefs = PrefsCatalogCache(_store);

  @override
  Future<Map<String, dynamic>?> read() async {
    String? raw;
    try {
      raw = await _get();
    } catch (e) {
      debugPrint('catalogue cache: IndexedDB unavailable, localStorage used ($e)');
      return _prefs.read();
    }
    if (raw == null) {
      // The first launch of this build: what an earlier build kept in localStorage moves over.
      final old = await _prefs.read();
      if (old != null) {
        try {
          await write(old);
        } catch (e) {
          debugPrint('catalogue cache: not moved to IndexedDB ($e)');
        }
      }
      return old;
    }
    try {
      final json = jsonDecode(raw);
      return json is Map<String, dynamic> ? json : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(Map<String, dynamic> json) async {
    try {
      await _put(jsonEncode(json));
    } catch (e) {
      debugPrint('catalogue cache: IndexedDB unavailable, localStorage used ($e)');
      return _prefs.write(json);
    }
    // A copy left in localStorage by an earlier build gives its room back.
    if (_store.getText(PrefsCatalogCache.key) != null) await _store.remove(PrefsCatalogCache.key);
  }

  Future<web.IDBDatabase> _open() async {
    final pending = _db ??= _connect();
    try {
      return await pending;
    } catch (_) {
      if (identical(_db, pending)) _db = null; // tried again next time
      rethrow;
    }
  }

  Future<web.IDBDatabase> _connect() {
    final done = Completer<web.IDBDatabase>();
    final req = web.window.indexedDB.open(_database, 1);
    req.onupgradeneeded = ((web.Event _) {
      final db = req.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_table)) db.createObjectStore(_table);
    }).toJS;
    req.onsuccess = ((web.Event _) {
      done.complete(req.result as web.IDBDatabase);
    }).toJS;
    req.onerror = ((web.Event _) {
      if (!done.isCompleted) done.completeError(StateError('IndexedDB open: ${req.error?.message}'));
    }).toJS;
    req.onblocked = ((web.Event _) {
      if (!done.isCompleted) done.completeError(StateError('IndexedDB open blocked'));
    }).toJS;
    return done.future;
  }

  Future<String?> _get() async {
    final db = await _open();
    final req = db.transaction(_table.toJS, 'readonly').objectStore(_table).get(_key.toJS);
    final done = Completer<String?>();
    req.onsuccess = ((web.Event _) {
      final v = req.result;
      done.complete(v != null && v.isA<JSString>() ? (v as JSString).toDart : null);
    }).toJS;
    req.onerror = ((web.Event _) {
      if (!done.isCompleted) done.completeError(StateError('IndexedDB read: ${req.error?.message}'));
    }).toJS;
    return done.future;
  }

  Future<void> _put(String value) async {
    final db = await _open();
    final tx = db.transaction(_table.toJS, 'readwrite');
    final done = Completer<void>();
    tx.oncomplete = ((web.Event _) {
      if (!done.isCompleted) done.complete();
    }).toJS;
    tx.onerror = ((web.Event _) {
      if (!done.isCompleted) done.completeError(StateError('IndexedDB write: ${tx.error?.message}'));
    }).toJS;
    tx.onabort = ((web.Event _) {
      if (!done.isCompleted) done.completeError(StateError('IndexedDB write stopped: ${tx.error?.message}'));
    }).toJS;
    tx.objectStore(_table).put(value.toJS, _key.toJS);
    return done.future;
  }
}
