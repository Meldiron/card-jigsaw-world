import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/appwrite.dart';
import '../data/repositories.dart';
import '../models/models.dart';
import 'catalog_sync.dart';
import 'giant.dart';
import 'profile.dart';
import 'progress.dart';
import 'settings.dart';

final catalogSyncProvider = Provider((ref) => CatalogSync(ref.read(localStoreProvider), ref.watch(catalogRepositoryProvider)));

/// The catalogue brought up to date with the server (see [CatalogSync]), or the copy on the device
/// when the server cannot be reached. Refresh by invalidating this.
final catalogProvider = FutureProvider<CatalogTables>((ref) async {
  final sync = ref.watch(catalogSyncProvider);
  try {
    return await sync.sync();
  } catch (e) {
    debugPrint('catalogue sync failed: $e');
    final cached = await sync.cached();
    if (cached != null) return cached;
    rethrow;
  }
}, retry: _catalogRetry);

/// The catalogue is read once more after 2 s, then its error reaches the screens, which offer Try
/// again (`ref.invalidate(catalogProvider)`). Riverpod's default (ten tries over about 40 s, in
/// every provider built on it as well) kept the catalogue screens on a spinner and never showed
/// their error states.
Duration? _catalogRetry(int count, Object error) => count < 1 ? const Duration(seconds: 2) : null;

/// What is built from the catalogue does not try again on its own: it follows [catalogProvider].
Duration? _followCatalog(int count, Object error) => null;

/// Every pack row, including ones that are not released yet (future daily months, event packs
/// more than [Pack.soonWindow] away). Screens read [packsProvider].
final packRowsProvider = FutureProvider<List<Pack>>((ref) async {
  final rows = (await ref.watch(catalogProvider.future))[AppwriteConfig.packs]!;
  return [for (final r in rows) Pack.fromRow('${r[r'$id']}', r)]..sort((a, b) => a.sortOrder != b.sortOrder ? a.sortOrder.compareTo(b.sortOrder) : a.id.compareTo(b.id));
}, retry: _followCatalog);

/// The packs the player owns, for hidden packs (opened with a pack code). Selected as one string so
/// a coin or XP change in the profile does not rebuild the catalogue.
final _ownedPacksProvider = Provider<Set<String>>((ref) {
  final joined = ref.watch(profileProvider.select((p) => p.value?.unlockedPacks.join('\n') ?? ''));
  return joined.isEmpty ? const <String>{} : joined.split('\n').toSet();
});

/// The packs the player can see now (see [Pack.visibleTo]): released, and hidden packs only once a
/// pack code opened them.
final packsProvider = FutureProvider<List<Pack>>((ref) async {
  final rows = await ref.watch(packRowsProvider.future);
  final owned = ref.watch(_ownedPacksProvider);
  final now = DateTime.now();
  return rows.where((p) => p.visibleTo(owned, now)).toList();
}, retry: _followCatalog);

/// The catalogue every player shares: released packs, hidden ones left out. Total Completion and
/// the catalogue size count these, so a pack opened with a code does not change the public numbers
/// (and the profile, which keeps those numbers, does not depend on its own unlocked packs).
final publicPacksProvider = FutureProvider<List<Pack>>((ref) async {
  final rows = await ref.watch(packRowsProvider.future);
  final now = DateTime.now();
  return rows.where((p) => !p.hidden && p.isReleasedAt(now)).toList();
}, retry: _followCatalog);

/// The puzzles of [publicPacksProvider].
final publicPuzzlesProvider = FutureProvider<List<Puzzle>>((ref) async {
  final rows = (await ref.watch(catalogProvider.future))[AppwriteConfig.puzzles]!;
  final packs = {for (final p in await ref.watch(publicPacksProvider.future)) p.id};
  return [
    for (final r in rows)
      if (packs.contains(r['packId'])) Puzzle.fromRow('${r[r'$id']}', r),
  ]..sort((a, b) => a.sortOrder != b.sortOrder ? a.sortOrder.compareTo(b.sortOrder) : a.id.compareTo(b.id));
}, retry: _followCatalog);

/// Every puzzle of the packs the player can see (puzzles of packs that are not released yet, and of
/// hidden packs the player has not opened, stay out of the app).
final allPuzzlesProvider = FutureProvider<List<Puzzle>>((ref) async {
  final rows = (await ref.watch(catalogProvider.future))[AppwriteConfig.puzzles]!;
  final owned = ref.watch(_ownedPacksProvider);
  final now = DateTime.now();
  final hidden = {for (final p in await ref.watch(packRowsProvider.future)) if (!p.visibleTo(owned, now)) p.id};
  return [
    for (final r in rows)
      if (!hidden.contains(r['packId'])) Puzzle.fromRow('${r[r'$id']}', r),
  ]..sort((a, b) => a.sortOrder != b.sortOrder ? a.sortOrder.compareTo(b.sortOrder) : a.id.compareTo(b.id));
}, retry: _followCatalog);

final packPuzzlesProvider = Provider.family<AsyncValue<List<Puzzle>>, String>((ref, packId) {
  return ref.watch(allPuzzlesProvider).whenData((all) => all.where((p) => p.packId == packId).toList());
});

final puzzleByIdProvider = Provider.family<Puzzle?, String>((ref, id) {
  final all = ref.watch(allPuzzlesProvider).value;
  if (all == null) return null;
  for (final p in all) {
    if (p.id == id) return p;
  }
  return null;
});

/// Every event row (past events still count towards player statistics), by end date.
final eventsProvider = FutureProvider<List<GameEvent>>((ref) async {
  try {
    final rows = (await ref.watch(catalogProvider.future))[AppwriteConfig.events]!;
    return [for (final r in rows) GameEvent.fromRow('${r[r'$id']}', r)]..sort((a, b) => (a.endAt ?? DateTime(9999)).compareTo(b.endAt ?? DateTime(9999)));
  } catch (e) {
    debugPrint('events failed: $e');
    return const [];
  }
});

/// Puzzle of the day: the entry of this month's daily pack dated today.
/// Falls back to a deterministic pick when the catalog has no dated puzzle.
final dailyPuzzleProvider = Provider<Puzzle?>((ref) {
  final all = ref.watch(allPuzzlesProvider).value;
  if (all == null || all.isEmpty) return null;
  for (final p in all) {
    if (p.isToday) return p;
  }
  final now = DateTime.now();
  final dayIndex = now.difference(DateTime(2026, 1, 1)).inDays;
  final pool = all.where((p) => p.date == null).toList();
  return pool.isEmpty ? null : pool[dayIndex % pool.length];
});

/// Picks a random puzzle the player can start right now (unlocked pack,
/// not already completed when possible). Used by goal "Play" buttons; the
/// Giant pack's 100-card boards are left out.
Puzzle? pickRandomPlayable(WidgetRef ref) {
  final packs = ref.read(packsProvider).value ?? const <Pack>[];
  final all = ref.read(allPuzzlesProvider).value ?? const <Puzzle>[];
  final progress = ref.read(progressProvider).value ?? const {};
  final notifier = ref.read(profileProvider.notifier);
  final open = {for (final p in packs) if (notifier.isUnlocked(p) && !isGiantPack(p)) p.id};
  final pool = all.where((z) => open.contains(z.packId) && !z.isLockedByDate).toList();
  if (pool.isEmpty) return null;
  final fresh = pool.where((z) => progress[z.id]?.completed != true).toList();
  final list = fresh.isEmpty ? pool : fresh;
  return list[DateTime.now().microsecondsSinceEpoch % list.length];
}

/// Event packs (carry a time window), newest first.
final eventPacksProvider = Provider<List<Pack>>((ref) {
  return (ref.watch(packsProvider).value ?? const []).where((p) => p.hasWindow).toList();
});

/// Featured (non-daily) packs in catalog order.
final featuredPacksProvider = Provider<List<Pack>>((ref) {
  return (ref.watch(packsProvider).value ?? const []).where((p) => !p.isDaily && !p.hasWindow).toList();
});

/// Monthly daily packs, newest first.
final dailyPacksProvider = Provider<List<Pack>>((ref) {
  return (ref.watch(packsProvider).value ?? const []).where((p) => p.isDaily).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
});
