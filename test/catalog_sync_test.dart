import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/data/repositories.dart';
import 'package:card_jigsaw_world/state/catalog_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory catalogue tables and snapshot file. Counts every row returned (each one is a billed read).
class FakeCatalog implements CatalogSource {
  final tables = <String, Map<String, Map<String, dynamic>>>{'packs': {}, 'puzzles': {}, 'events': {}};
  Map<String, dynamic>? file;
  var reads = 0;
  var fullReads = 0;
  var snapshotDownloads = 0;
  var snapshotFails = false;
  var clock = DateTime.utc(2026, 10, 13, 12);

  Map<String, dynamic> put(String table, String id, [Map<String, dynamic> data = const {}]) {
    clock = clock.add(const Duration(seconds: 30));
    return tables[table]![id] = {r'$id': id, r'$updatedAt': clock.toIso8601String(), r'$permissions': ['read("any")'], ...data};
  }

  void puzzle(String id, String packId, {String title = 'Picture'}) => put('puzzles', id, {'packId': packId, 'title': title, 'imageUrl': 'https://x/$id'});

  /// What `functions/catalog-snapshot` writes.
  void takeSnapshot() => file = {
        'v': 1,
        'tables': {
          for (final e in tables.entries)
            e.key: {
              'watermark': e.value.values.map((r) => r[r'$updatedAt'] as String).fold<String?>(null, (a, b) => a == null || b.compareTo(a) > 0 ? b : a),
              'rows': [for (final r in e.value.values) Map<String, dynamic>.from(r)..remove(r'$permissions')],
            },
        },
      };

  List<Map<String, dynamic>> _read(Iterable<Map<String, dynamic>> it) {
    final out = [for (final r in it) Map<String, dynamic>.from(r)];
    reads += out.length;
    return out;
  }

  @override
  Future<Map<String, dynamic>?> snapshot() async {
    if (snapshotFails) throw Exception('offline');
    if (file != null) snapshotDownloads++;
    return file;
  }

  @override
  Future<List<Map<String, dynamic>>> rows(String tableId) async {
    fullReads++;
    return _read(tables[tableId]!.values);
  }

  @override
  Future<List<Map<String, dynamic>>> rowsSince(String tableId, String updatedAt) async {
    final since = DateTime.parse(updatedAt);
    return _read(tables[tableId]!.values.where((r) => !DateTime.parse(r[r'$updatedAt']).isBefore(since)));
  }

  @override
  Future<List<Map<String, dynamic>>> puzzleRowsOfPacks(List<String> packIds) async => _read(tables['puzzles']!.values.where((r) => packIds.contains(r['packId'])));
}

void main() {
  late LocalStore store;
  late FakeCatalog server;
  late DateTime now;
  CatalogSync sync() => CatalogSync(store, server, clock: () => now);
  Future<Set<String>> ids(String table) async => {for (final r in (await sync().sync())[table]!) '${r[r'$id']}'};

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    server = FakeCatalog();
    now = DateTime(2026, 10, 13, 14);
    for (final pack in ['pack-a', 'pack-b']) {
      server.put('packs', pack, {'name': pack});
      for (var i = 0; i < 24; i++) {
        server.puzzle('$pack-$i', pack);
      }
    }
    server.put('events', 'world-food-day', {'name': 'World Food Day'});
  });

  test('first launch starts from the snapshot and reads only what changed since', () async {
    server.takeSnapshot();
    server.puzzle('pack-b-new', 'pack-b');

    final tables = await sync().sync();
    expect(tables['puzzles'], hasLength(49));
    expect(tables['packs'], hasLength(2));
    expect(tables['events'], hasLength(1));
    expect(server.fullReads, 0);
    expect(server.reads, lessThan(5), reason: 'the new row plus rows inside the overlap window');
    expect(tables['puzzles']!.first.containsKey(r'$permissions'), isFalse, reason: 'Appwrite internals are not kept');
  });

  test('without a snapshot, or when it cannot be read, the tables are read whole', () async {
    expect(await ids('puzzles'), hasLength(48));
    expect(server.fullReads, 3);

    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    server.takeSnapshot();
    server.snapshotFails = true;
    expect(await ids('puzzles'), hasLength(48));
    expect(server.fullReads, 6);
  });

  test('the next launch reads only the overlap window', () async {
    server.takeSnapshot();
    await sync().sync();
    server.reads = 0;
    expect(await ids('puzzles'), hasLength(48));
    expect(server.reads, lessThan(4));
    expect(server.snapshotDownloads, 1);
  });

  test('edited packs, puzzles and events arrive through the delta', () async {
    server.takeSnapshot();
    await sync().sync();
    server.put('events', 'world-food-day', {'name': 'World Food Day 2026'});
    server.puzzle('pack-a-0', 'pack-a', title: 'Renamed');
    server.put('packs', 'pack-c', {'name': 'pack-c'});

    final tables = await sync().sync();
    expect(tables['events']!.single['name'], 'World Food Day 2026');
    expect(tables['puzzles']!.firstWhere((r) => r[r'$id'] == 'pack-a-0')['title'], 'Renamed');
    expect(tables['packs']!.map((r) => r[r'$id']), contains('pack-c'));
  });

  test('a pack whose row changed has its puzzles read again, so deleted puzzles disappear', () async {
    server.takeSnapshot();
    await sync().sync();
    server.tables['puzzles']!.remove('pack-a-3');
    server.tables['puzzles']!.remove('pack-a-4');
    server.puzzle('pack-a-99', 'pack-a');
    server.put('packs', 'pack-a', {'name': 'pack-a', 'imageCount': 23});

    server.reads = 0;
    final after = await ids('puzzles');
    expect(after, isNot(contains('pack-a-3')));
    expect(after, isNot(contains('pack-a-4')));
    expect(after, contains('pack-a-99'));
    expect(after, hasLength(47));
    expect(server.reads, lessThan(30), reason: 'one pack plus the delta, not the whole catalogue');
  });

  test('after a week the base comes from the snapshot again, dropping rows deleted by hand', () async {
    server.takeSnapshot();
    await sync().sync();
    server.tables['packs']!.remove('pack-b');
    server.tables['puzzles']!.removeWhere((_, r) => r['packId'] == 'pack-b');
    server.takeSnapshot();

    expect(await ids('packs'), contains('pack-b'), reason: 'a delta cannot see deletions');
    now = now.add(CatalogSync.rebaseEvery + const Duration(hours: 1));
    expect(await ids('packs'), {'pack-a'});
    expect(await ids('puzzles'), hasLength(24));
    expect(server.snapshotDownloads, 2);
  });

  test('old caches are replaced, and cached() serves the catalogue offline', () async {
    SharedPreferences.setMockInitialValues({'packs': '[]', 'puzzles': '[]', 'puzzleCatalog': '{}'});
    store = await LocalStore.open();
    expect(sync().cached(), isNull);
    server.takeSnapshot();
    await sync().sync();
    for (final key in ['packs', 'puzzles', 'puzzleCatalog']) {
      expect(store.getJson(key) ?? store.getJsonList(key), isNull, reason: '$key is removed');
    }
    expect(sync().cached()!['puzzles'], hasLength(48));
  });
}
