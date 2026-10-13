import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories.dart';
import '../models/models.dart';
import 'profile.dart';
import 'progress.dart';
import 'settings.dart';

/// Every pack row, including ones that are not released yet (future daily months, event packs
/// more than [Pack.soonWindow] away). Screens read [packsProvider]; refresh by invalidating this.
final packRowsProvider = FutureProvider<List<Pack>>((ref) async {
  final store = ref.read(localStoreProvider);
  try {
    final packs = await ref.watch(catalogRepositoryProvider).packs();
    store.setJsonList('packs', packs.map((p) => {'id': p.id, ..._packToJson(p)}).toList());
    return packs;
  } catch (e) {
    debugPrint('packs failed: $e');
    final cached = store.getJsonList('packs');
    if (cached != null) return cached.map((j) => Pack.fromRow(j['id'], Map<String, dynamic>.from(j))).toList();
    rethrow;
  }
});

/// The packs the player can see now (see [Pack.isReleasedAt]).
final packsProvider = FutureProvider<List<Pack>>((ref) async {
  final rows = await ref.watch(packRowsProvider.future);
  final now = DateTime.now();
  return rows.where((p) => p.isReleasedAt(now)).toList();
});

/// Ids of packs that exist but are not released yet; their puzzles stay out of the app too.
Future<Set<String>> _hiddenPackIds(Ref ref) async {
  try {
    final now = DateTime.now();
    return {for (final p in await ref.watch(packRowsProvider.future)) if (!p.isReleasedAt(now)) p.id};
  } catch (_) {
    return const {};
  }
}

Map<String, dynamic> _packToJson(Pack p) => {
      'name': p.name,
      'category': p.category,
      'description': p.description,
      'coverUrl': p.coverUrl,
      'priceCoins': p.priceCoins,
      'priceTickets': p.priceTickets,
      'isFree': p.isFree,
      'isPremium': p.isPremium,
      'isSeasonal': p.isSeasonal,
      'eventId': p.eventId,
      'sortOrder': p.sortOrder,
      'imageCount': p.imageCount,
      'accent': '#${p.accent.toARGB32().toRadixString(16).substring(2)}',
      'emoji': p.emoji,
      'startAt': p.startAt?.toIso8601String(),
      'endAt': p.endAt?.toIso8601String(),
      'blurhash': p.blurhash,
    };

Map<String, dynamic> _puzzleToJson(Puzzle p) => {
      'packId': p.packId,
      'title': p.title,
      'imageUrl': p.imageUrl,
      'thumbUrl': p.thumbUrl,
      'author': p.author,
      'source': p.source,
      'sortOrder': p.sortOrder,
      'date': p.date?.toIso8601String(),
      'blurhash': p.blurhash,
    };

final allPuzzlesProvider = FutureProvider<List<Puzzle>>((ref) async {
  final store = ref.read(localStoreProvider);
  final hiddenPacks = _hiddenPackIds(ref);
  List<Puzzle> visible(List<Puzzle> all, Set<String> hidden) => hidden.isEmpty ? all : all.where((p) => !hidden.contains(p.packId)).toList();
  try {
    final puzzles = await ref.watch(catalogRepositoryProvider).allPuzzles();
    store.setJsonList('puzzles', puzzles.map((p) => {'id': p.id, ..._puzzleToJson(p)}).toList());
    return visible(puzzles, await hiddenPacks);
  } catch (e) {
    debugPrint('puzzles failed: $e');
    final cached = store.getJsonList('puzzles');
    if (cached != null) return visible(cached.map((j) => Puzzle.fromRow(j['id'], Map<String, dynamic>.from(j))).toList(), await hiddenPacks);
    rethrow;
  }
});

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

final eventsProvider = FutureProvider<List<GameEvent>>((ref) async {
  try {
    return await ref.watch(catalogRepositoryProvider).events();
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
/// not already completed when possible). Used by goal "Play" buttons.
Puzzle? pickRandomPlayable(WidgetRef ref) {
  final packs = ref.read(packsProvider).value ?? const <Pack>[];
  final all = ref.read(allPuzzlesProvider).value ?? const <Puzzle>[];
  final progress = ref.read(progressProvider).value ?? const {};
  final notifier = ref.read(profileProvider.notifier);
  final open = {for (final p in packs) if (notifier.isUnlocked(p)) p.id};
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
