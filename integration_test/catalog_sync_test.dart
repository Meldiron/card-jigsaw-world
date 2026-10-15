import 'dart:convert';

import 'package:appwrite/appwrite.dart' show Client, Storage, TablesDB;
import 'package:carden/core/appwrite.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/data/repositories.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/catalog_sync.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts the rows the live database returns (each one is a billed read) and snapshot downloads.
class CountingCatalog extends CatalogRepository {
  CountingCatalog(super.tables, super.storage);
  var reads = 0;
  var snapshots = 0;

  Future<List<Map<String, dynamic>>> _count(Future<List<Map<String, dynamic>>> rows) async {
    final out = await rows;
    reads += out.length;
    return out;
  }

  @override
  Future<Map<String, dynamic>?> snapshot() async {
    final snap = await super.snapshot();
    if (snap != null) snapshots++;
    return snap;
  }

  @override
  Future<List<Map<String, dynamic>>> rows(String tableId) => _count(super.rows(tableId));
  @override
  Future<List<Map<String, dynamic>>> rowsSince(String tableId, String updatedAt) => _count(super.rowsSince(tableId, updatedAt));
  @override
  Future<List<Map<String, dynamic>>> puzzleRowsOfPacks(List<String> packIds) => _count(super.puzzleRowsOfPacks(packIds));
}

/// Against the live catalogue: the first launch starts from the snapshot file and reads only rows
/// changed since; the result matches the tables read whole; the next launch reads only the overlap.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('catalogue snapshot + delta sync', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final client = Client().setEndpoint(AppwriteConfig.endpoint).setProject(AppwriteConfig.projectId);
    final catalog = CountingCatalog(TablesDB(client), Storage(client));
    final container = ProviderContainer(overrides: [
      localStoreProvider.overrideWithValue(store),
      catalogRepositoryProvider.overrideWithValue(catalog),
    ]);
    addTearDown(container.dispose);

    final first = await container.read(catalogProvider.future);
    debugPrint('first launch: ${CatalogSync.tables.map((t) => '${first[t]!.length} $t').join(', ')}; '
        '${catalog.snapshots} snapshot, ${catalog.reads} rows read');
    expect(catalog.snapshots, 1, reason: 'the base comes from the snapshot file');
    expect(catalog.reads, lessThan(500));
    expect((await container.read(packRowsProvider.future)).length, greaterThan(300));
    expect((await container.read(allPuzzlesProvider.future)).length, greaterThan(5000));
    expect(await container.read(eventsProvider.future), isNotEmpty);

    // The synced catalogue is the tables as they are now (read whole, outside the counter).
    final plain = CatalogRepository(TablesDB(client), Storage(client));
    for (final t in CatalogSync.tables) {
      // Null and absent are the same column value (a column added later is absent from older snapshot rows).
      String key(Map<String, dynamic> r) => jsonEncode({
            for (final k in (r.keys.toList()..sort()))
              if ((!k.startsWith(r'$') || k == r'$id' || k == r'$updatedAt') && k != 'sourceUrl' && k != 'coverSourceUrl' && r[k] != null) k: r[k],
          });
      final live = {for (final r in await plain.rows(t)) key(r)};
      final synced = {for (final r in first[t]!) key(r)};
      expect(synced.difference(live), isEmpty, reason: '$t: rows the device has that the server does not');
      expect(live.difference(synced), isEmpty, reason: '$t: rows the server has that the device misses');
    }

    catalog.reads = 0;
    container.invalidate(catalogProvider);
    final second = await container.read(catalogProvider.future);
    debugPrint('next launch: ${second[AppwriteConfig.puzzles]!.length} puzzles; ${catalog.snapshots} snapshot, ${catalog.reads} rows read');
    expect(catalog.snapshots, 1, reason: 'no second download');
    expect(catalog.reads, lessThan(100));
  });
}
