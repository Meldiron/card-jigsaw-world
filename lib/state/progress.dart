import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sync/ops.dart';
import '../models/models.dart';
import 'auth.dart';
import 'sync.dart';

/// Map of puzzleId -> progress for the signed-in player. Saves are queued as [SyncOp]s
/// ([SyncController]): records only improve and a solved picture stays solved, whichever device
/// writes last.
class ProgressNotifier extends AsyncNotifier<Map<String, PuzzleProgress>> {
  @override
  Future<Map<String, PuzzleProgress>> build() async {
    final auth = await ref.watch(authProvider.future);
    final sync = ref.read(syncProvider.notifier);
    await sync.attach(auth);
    final id = auth?.$id ?? SyncController.local;
    ref.listen(syncProvider.select((s) => (s.userId, s.progress)), (_, s) {
      if (s.$1 == id) state = AsyncData(s.$2);
    });
    final s = ref.read(syncProvider);
    return s.userId == id ? s.progress : const {};
  }

  void _do(SyncOp op) => ref.read(syncProvider.notifier).enqueue(op);

  /// Saves the board in progress. [session] is the play-through; [resumed] says it continues the
  /// board that was saved for the picture.
  void saveBoard(
    String puzzleId, {
    required int gridSize,
    required String mode,
    required List<int> layout,
    required int moves,
    required int seconds,
    required int hints,
    required String session,
    required bool resumed,
    bool painting = false,
  }) =>
      _do(SyncOp.board(
        puzzleId: puzzleId,
        gridSize: gridSize,
        mode: mode,
        layout: layout.join(','),
        moves: moves,
        seconds: seconds,
        hints: hints,
        session: session,
        resumed: resumed,
        painting: painting,
      ));

  /// Records a finished board: the picture is solved, stars and best moves and time keep the
  /// better of this and what was there, the saved board is cleared. [at] is the finish time (now).
  void complete(
    String puzzleId, {
    required int gridSize,
    required String mode,
    required int moves,
    required int seconds,
    required int hints,
    required int stars,
    required String session,
    required bool resumed,
    bool painting = false,
    DateTime? at,
  }) =>
      _do(SyncOp.win(
        puzzleId: puzzleId,
        gridSize: gridSize,
        mode: mode,
        moves: moves,
        seconds: seconds,
        hints: hints,
        stars: stars,
        session: session,
        resumed: resumed,
        painting: painting,
        at: at,
      ));

  /// Throws away the saved board of a picture so a new mode or size can be
  /// chosen. Records (stars, best moves and time) and the lifetime totals
  /// stay; only the session in progress is dropped.
  Future<void> discard(String puzzleId) async => _do(SyncOp.discard(puzzleId));
}

final progressProvider = AsyncNotifierProvider<ProgressNotifier, Map<String, PuzzleProgress>>(ProgressNotifier.new);

final puzzleProgressProvider = Provider.family<PuzzleProgress?, String>((ref, puzzleId) {
  return ref.watch(progressProvider).value?[puzzleId];
});
