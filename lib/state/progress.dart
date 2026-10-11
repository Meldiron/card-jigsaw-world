import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories.dart';
import '../models/models.dart';
import 'auth.dart';
import 'settings.dart';

/// Map of puzzleId -> progress for the signed-in player.
class ProgressNotifier extends AsyncNotifier<Map<String, PuzzleProgress>> {
  @override
  Future<Map<String, PuzzleProgress>> build() async {
    final auth = await ref.watch(authProvider.future);
    final store = ref.read(localStoreProvider);
    if (auth == null) return _fromCache(store.getJsonList('progress'));
    try {
      final list = await ref.read(progressRepositoryProvider).forUser(auth.$id);
      final map = {for (final p in list) p.puzzleId: p};
      _cache(map);
      return map;
    } catch (e) {
      debugPrint('progress failed: $e');
      return _fromCache(store.getJsonList('progress'));
    }
  }

  Map<String, PuzzleProgress> _fromCache(List<dynamic>? raw) {
    if (raw == null) return {};
    final map = <String, PuzzleProgress>{};
    for (final j in raw) {
      final m = Map<String, dynamic>.from(j);
      final p = PuzzleProgress.fromRow(m['id'] ?? '', m);
      map[p.puzzleId] = p;
    }
    return map;
  }

  void _cache(Map<String, PuzzleProgress> map) {
    ref.read(localStoreProvider).setJsonList(
          'progress',
          map.values
              .map((p) => {
                    'id': p.id,
                    'userId': p.userId,
                    'puzzleId': p.puzzleId,
                    'gridSize': p.gridSize,
                    'layout': p.layout?.join(','),
                    'moves': p.moves,
                    'elapsedSeconds': p.elapsedSeconds,
                    'hintsUsed': p.hintsUsed,
                    'completed': p.completed,
                    'stars': p.stars,
                    'bestMoves': p.bestMoves,
                    'bestSeconds': p.bestSeconds,
                    'completedAt': p.completedAt?.toIso8601String(),
                    'mode': p.mode,
                  })
              .toList(),
        );
  }

  Future<void> save(String puzzleId, Map<String, dynamic> data) async {
    final userId = ref.read(currentUserIdProvider) ?? 'local';
    final current = state.value ?? {};
    final existing = current[puzzleId];
    final merged = PuzzleProgress.fromRow(existing?.id ?? deterministicId(userId, puzzleId), {
      'userId': userId,
      'puzzleId': puzzleId,
      if (existing != null) ...{
        'gridSize': existing.gridSize,
        'layout': existing.layout?.join(','),
        'moves': existing.moves,
        'elapsedSeconds': existing.elapsedSeconds,
        'hintsUsed': existing.hintsUsed,
        'completed': existing.completed,
        'stars': existing.stars,
        'bestMoves': existing.bestMoves,
        'bestSeconds': existing.bestSeconds,
        'completedAt': existing.completedAt?.toIso8601String(),
        'mode': existing.mode,
      },
      ...data,
    });
    final next = {...current, puzzleId: merged};
    state = AsyncData(next);
    _cache(next);
    if (userId == 'local') return;
    try {
      await ref.read(progressRepositoryProvider).upsert(userId, puzzleId, data);
    } catch (e) {
      debugPrint('progress save failed: $e');
    }
  }
}

final progressProvider = AsyncNotifierProvider<ProgressNotifier, Map<String, PuzzleProgress>>(ProgressNotifier.new);

final puzzleProgressProvider = Provider.family<PuzzleProgress?, String>((ref, puzzleId) {
  return ref.watch(progressProvider).value?[puzzleId];
});
