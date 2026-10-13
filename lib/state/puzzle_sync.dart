import 'package:flutter/foundation.dart';

import '../data/local_store.dart';
import '../data/repositories.dart';
import '../models/models.dart';

/// The puzzle catalogue kept on the device and brought up to date with a few small reads, instead of
/// reading every row on each launch (each row returned is a billed database read).
///
/// Rows created or updated since the last sync come from [PuzzleRowSource.puzzleRowsSince]. Deletions
/// are caught per pack: the content tool updates a pack's row whenever it removes or replaces puzzles,
/// so every pack whose `$updatedAt` moved is read again whole. Everything is read again on first launch,
/// when pack stamps are missing, and after [fullEvery] (for rows deleted outside the content tool).
class PuzzleCatalogSync {
  PuzzleCatalogSync(this._store, this._source, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final LocalStore _store;
  final PuzzleRowSource _source;
  final DateTime Function() _clock;

  static const cacheKey = 'puzzleCatalog';
  static const _legacyCacheKey = 'puzzles';
  static const _version = 1;

  /// Rows written just before the last sync are read again, in case concurrent writes landed out of order.
  static const overlap = Duration(seconds: 10);
  static const fullEvery = Duration(days: 7);
  static const _fields = ['packId', 'title', 'imageUrl', 'thumbUrl', 'author', 'source', 'sortOrder', 'accent', 'date', 'blurhash'];

  /// The cached catalogue, for when the server cannot be reached.
  List<Puzzle>? cached() {
    final cache = _store.getJson(cacheKey);
    if (cache == null || cache['v'] != _version) return null;
    return _puzzles(_cachedRows(cache).values);
  }

  /// Brings the cache in step with the server and returns every puzzle. [packs] is every pack row
  /// (released or not), or null when they could not be read.
  Future<List<Puzzle>> sync(List<Pack>? packs) async {
    final now = _clock();
    final stamps = packs == null ? null : {for (final p in packs) p.id: p.updatedAt};
    final cache = _store.getJson(cacheKey);
    final cachedStamps = cache?['packs'];
    final watermark = DateTime.tryParse('${cache?['watermark']}');
    final fullAt = DateTime.tryParse('${cache?['fullAt']}');
    final full = cache == null ||
        cache['v'] != _version ||
        stamps == null ||
        stamps.values.contains(null) ||
        cachedStamps is! Map ||
        watermark == null ||
        fullAt == null ||
        now.difference(fullAt).abs() > fullEvery;

    final Map<String, Map<String, dynamic>> rows;
    final DateTime? latest;
    var dirty = full;
    if (full) {
      final fetched = await _source.allPuzzleRows();
      rows = {for (final r in fetched) '${r[r'$id']}': _compact(r)};
      latest = _latest(fetched, null);
    } else {
      rows = _cachedRows(cache);
      final changed = [for (final e in stamps.entries) if (cachedStamps[e.key] != e.value) e.key];
      final reread = {...changed, for (final id in cachedStamps.keys) if (!stamps.containsKey(id)) '$id'};
      final fresh = await _source.puzzleRowsSince(watermark.subtract(overlap).toUtc().toIso8601String());
      final repacked = changed.isEmpty ? const <Map<String, dynamic>>[] : await _source.puzzleRowsOfPacks(changed);
      if (reread.isNotEmpty) {
        rows.removeWhere((_, r) => reread.contains(r['packId']));
        dirty = true;
      }
      for (final r in [...fresh, ...repacked]) {
        final row = _compact(r);
        if (mapEquals(rows[row[r'$id']], row)) continue;
        rows['${row[r'$id']}'] = row;
        dirty = true;
      }
      latest = _latest([...fresh, ...repacked], watermark);
      dirty = dirty || latest != watermark;
    }

    if (dirty) {
      try {
        await _store.remove(_legacyCacheKey);
        await _store.setJson(cacheKey, {
          'v': _version,
          'watermark': latest?.toUtc().toIso8601String(),
          'fullAt': (full ? now : fullAt).toIso8601String(),
          'packs': stamps,
          'rows': rows.values.toList(),
        });
      } catch (e) {
        debugPrint('puzzle cache not saved: $e');
      }
    }
    return _puzzles(rows.values);
  }

  static Map<String, dynamic> _compact(Map<String, dynamic> row) => {
        r'$id': '${row[r'$id']}',
        for (final k in _fields)
          if (row[k] != null) k: row[k],
      };

  static Map<String, Map<String, dynamic>> _cachedRows(Map<String, dynamic> cache) => {
        for (final r in (cache['rows'] as List? ?? const []).whereType<Map>()) '${r[r'$id']}': Map<String, dynamic>.from(r),
      };

  static DateTime? _latest(Iterable<Map<String, dynamic>> rows, DateTime? start) {
    var latest = start;
    for (final r in rows) {
      final t = DateTime.tryParse('${r[r'$updatedAt']}');
      if (t != null && (latest == null || t.isAfter(latest))) latest = t;
    }
    return latest;
  }

  static List<Puzzle> _puzzles(Iterable<Map<String, dynamic>> rows) =>
      [for (final r in rows) Puzzle.fromRow('${r[r'$id']}', r)]..sort((a, b) => a.sortOrder != b.sortOrder ? a.sortOrder.compareTo(b.sortOrder) : a.id.compareTo(b.id));
}
