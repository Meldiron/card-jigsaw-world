import 'package:appwrite/appwrite.dart' show Client, TablesDB;
import 'package:card_jigsaw_world/core/appwrite.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/data/repositories.dart';
import 'package:card_jigsaw_world/state/catalog.dart';
import 'package:card_jigsaw_world/state/puzzle_sync.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts the puzzle rows the live database returns (each one is a billed read).
class CountingCatalog extends CatalogRepository {
  CountingCatalog(super.tables);
  var reads = 0;

  Future<List<Map<String, dynamic>>> _count(Future<List<Map<String, dynamic>>> rows) async {
    final out = await rows;
    reads += out.length;
    return out;
  }

  @override
  Future<List<Map<String, dynamic>>> allPuzzleRows() => _count(super.allPuzzleRows());
  @override
  Future<List<Map<String, dynamic>>> puzzleRowsSince(String updatedAt) => _count(super.puzzleRowsSince(updatedAt));
  @override
  Future<List<Map<String, dynamic>>> puzzleRowsOfPacks(List<String> packIds) => _count(super.puzzleRowsOfPacks(packIds));
}

/// Against the live catalogue: the first launch reads every puzzle once, later launches read only
/// what changed, and both give the app the same catalogue.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('puzzle catalogue sync', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final catalog = CountingCatalog(TablesDB(Client().setEndpoint(AppwriteConfig.endpoint).setProject(AppwriteConfig.projectId)));
    final container = ProviderContainer(overrides: [
      localStoreProvider.overrideWithValue(store),
      catalogRepositoryProvider.overrideWithValue(catalog),
    ]);
    addTearDown(container.dispose);

    final first = await container.read(allPuzzlesProvider.future);
    final firstReads = catalog.reads;
    debugPrint('first launch: ${first.length} puzzles, $firstReads puzzle rows read');
    expect(first.length, greaterThan(5000));
    expect(firstReads, greaterThanOrEqualTo(first.length));
    final packs = await container.read(packRowsProvider.future);
    expect(packs.where((p) => p.updatedAt == null), isEmpty, reason: 'every pack row carries its \$updatedAt');

    catalog.reads = 0;
    container.invalidate(packRowsProvider);
    container.invalidate(allPuzzlesProvider);
    final second = await container.read(allPuzzlesProvider.future);
    debugPrint('next launch: ${second.length} puzzles, ${catalog.reads} puzzle rows read');
    expect(catalog.reads, lessThan(500), reason: 'a launch with an unchanged catalogue reads only what changed');
    expect(second.map((p) => '${p.id}|${p.packId}|${p.title}|${p.imageUrl}|${p.sortOrder}').toList(),
        first.map((p) => '${p.id}|${p.packId}|${p.title}|${p.imageUrl}|${p.sortOrder}').toList());
    expect(PuzzleCatalogSync(store, catalog).cached(), isNotNull);
  });
}
