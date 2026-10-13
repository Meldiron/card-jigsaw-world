import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/data/repositories.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/puzzle_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An in-memory puzzles table that counts every row it returns (each one is a billed read).
class FakePuzzleTable implements PuzzleRowSource {
  final rows = <String, Map<String, dynamic>>{};
  var reads = 0;
  var fullReads = 0;
  var clock = DateTime.utc(2026, 10, 13, 12);

  void put(String id, String packId, {String title = 'Picture', int sortOrder = 0}) {
    clock = clock.add(const Duration(seconds: 30));
    rows[id] = {r'$id': id, r'$updatedAt': clock.toIso8601String(), 'packId': packId, 'title': title, 'imageUrl': 'https://x/$id', 'sortOrder': sortOrder};
  }

  List<Map<String, dynamic>> _read(Iterable<Map<String, dynamic>> it) {
    final out = [for (final r in it) Map<String, dynamic>.from(r)];
    reads += out.length;
    return out;
  }

  @override
  Future<List<Map<String, dynamic>>> allPuzzleRows() async {
    fullReads++;
    return _read(rows.values);
  }

  @override
  Future<List<Map<String, dynamic>>> puzzleRowsSince(String updatedAt) async {
    final since = DateTime.parse(updatedAt);
    return _read(rows.values.where((r) => !DateTime.parse(r[r'$updatedAt']).isBefore(since)));
  }

  @override
  Future<List<Map<String, dynamic>>> puzzleRowsOfPacks(List<String> packIds) async => _read(rows.values.where((r) => packIds.contains(r['packId'])));
}

Pack _pack(String id, String updatedAt) => Pack.fromRow(id, {'name': id, r'$updatedAt': updatedAt});

void main() {
  late LocalStore store;
  late FakePuzzleTable table;
  late DateTime now;
  PuzzleCatalogSync sync() => PuzzleCatalogSync(store, table, clock: () => now);
  Future<List<String>> ids(List<Pack>? packs) async => [for (final p in await sync().sync(packs)) p.id];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    table = FakePuzzleTable();
    now = DateTime(2026, 10, 13, 14);
    for (var i = 0; i < 24; i++) {
      table.put('a$i', 'pack-a', sortOrder: i);
      table.put('b$i', 'pack-b', sortOrder: i);
    }
  });

  test('first launch reads the whole catalogue, the next one reads nothing new', () async {
    final packs = [_pack('pack-a', 't1'), _pack('pack-b', 't1')];
    expect(await ids(packs), hasLength(48));
    expect(table.reads, 48);

    table.reads = 0;
    expect(await ids(packs), hasLength(48));
    expect(table.reads, lessThan(3), reason: 'only rows inside the overlap window are read again');
    expect(table.fullReads, 1);
  });

  test('new and edited rows arrive through the delta', () async {
    final packs = [_pack('pack-a', 't1'), _pack('pack-b', 't1')];
    await ids(packs);
    table.put('a0', 'pack-a', title: 'Renamed');
    table.put('c0', 'pack-c');

    table.reads = 0;
    final puzzles = await sync().sync(packs);
    expect(puzzles.firstWhere((p) => p.id == 'a0').title, 'Renamed');
    expect(puzzles.map((p) => p.id), contains('c0'));
    expect(table.reads, lessThan(5));
  });

  test('a pack whose row changed is read again whole, so deleted puzzles disappear', () async {
    await ids([_pack('pack-a', 't1'), _pack('pack-b', 't1')]);
    table.rows.remove('a3');
    table.rows.remove('a4');
    table.put('a99', 'pack-a');

    table.reads = 0;
    final after = await ids([_pack('pack-a', 't2'), _pack('pack-b', 't1')]);
    expect(after, isNot(contains('a3')));
    expect(after, isNot(contains('a4')));
    expect(after, contains('a99'));
    expect(after, hasLength(47));
    expect(table.reads, lessThan(30), reason: 'one pack plus the delta, not the whole catalogue');
  });

  test('puzzles of a pack that no longer exists are dropped', () async {
    await ids([_pack('pack-a', 't1'), _pack('pack-b', 't1')]);
    table.rows.removeWhere((_, r) => r['packId'] == 'pack-b');
    expect(await ids([_pack('pack-a', 't1')]), hasLength(24));
  });

  test('missing pack stamps, a week-old cache or the old cache format read everything again', () async {
    final packs = [_pack('pack-a', 't1'), _pack('pack-b', 't1')];
    await ids(packs);
    await ids(null);
    expect(table.fullReads, 2);

    await ids(packs);
    now = now.add(PuzzleCatalogSync.fullEvery + const Duration(hours: 1));
    await ids(packs);
    expect(table.fullReads, 4);

    SharedPreferences.setMockInitialValues({'puzzles': '[]'});
    store = await LocalStore.open();
    await ids(packs);
    expect(table.fullReads, 5);
    expect(store.getJsonList('puzzles'), isNull, reason: 'the old full-catalogue cache is removed');
  });

  test('cached() serves the last synced catalogue offline, in catalogue order', () async {
    expect(sync().cached(), isNull);
    await ids([_pack('pack-a', 't1'), _pack('pack-b', 't1')]);
    final cached = sync().cached()!;
    expect(cached, hasLength(48));
    expect(cached.first.sortOrder, 0);
    expect(cached.last.sortOrder, 23);
  });
}
