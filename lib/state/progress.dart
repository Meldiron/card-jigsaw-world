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
    ref.read(localStoreProvider).setJsonList('progress', map.values.map((p) => {'id': p.id, ...p.toData()}).toList());
  }

  /// Lifetime totals for a picture, carried across sessions. A session is
  /// one play-through: within it the saved numbers only grow, so the running
  /// total is the previous sessions' sum plus the current session's numbers.
  /// A fresh session (replay after a win, or a restart) shows up as the
  /// counters dropping, and then adds on top of the previous total.
  @visibleForTesting
  static Map<String, int> sessionTotals(PuzzleProgress? existing, Map<String, dynamic> data) {
    int n(String k) => (data[k] as num?)?.toInt() ?? 0;
    final moves = n('moves'), seconds = n('elapsedSeconds'), hints = n('hintsUsed');
    if (existing == null) return {'totalMoves': moves, 'totalSeconds': seconds, 'totalHints': hints};
    final fresh = existing.completed || seconds < existing.elapsedSeconds || moves < existing.moves;
    if (fresh) {
      return {
        'totalMoves': existing.totalMoves + moves,
        'totalSeconds': existing.totalSeconds + seconds,
        'totalHints': existing.totalHints + hints,
      };
    }
    return {
      'totalMoves': existing.totalMoves - existing.moves + moves,
      'totalSeconds': existing.totalSeconds - existing.elapsedSeconds + seconds,
      'totalHints': existing.totalHints - existing.hintsUsed + hints,
    };
  }

  Future<void> save(String puzzleId, Map<String, dynamic> data) async {
    final userId = ref.read(currentUserIdProvider) ?? 'local';
    final current = state.value ?? {};
    final existing = current[puzzleId];
    // Only session saves (moves/time) move the lifetime totals.
    final patch = data.containsKey('moves') || data.containsKey('elapsedSeconds') ? {...data, ...ProgressNotifier.sessionTotals(existing, data)} : data;
    final merged = PuzzleProgress.fromRow(existing?.id ?? deterministicId(userId, puzzleId), {
      'userId': userId,
      'puzzleId': puzzleId,
      if (existing != null) ...existing.toData(),
      ...patch,
    });
    final next = {...current, puzzleId: merged};
    state = AsyncData(next);
    _cache(next);
    if (userId == 'local') return;
    try {
      await ref.read(progressRepositoryProvider).upsert(userId, puzzleId, patch);
    } catch (e) {
      debugPrint('progress save failed: $e');
    }
  }
}

final progressProvider = AsyncNotifierProvider<ProgressNotifier, Map<String, PuzzleProgress>>(ProgressNotifier.new);

final puzzleProgressProvider = Provider.family<PuzzleProgress?, String>((ref, puzzleId) {
  return ref.watch(progressProvider).value?[puzzleId];
});
