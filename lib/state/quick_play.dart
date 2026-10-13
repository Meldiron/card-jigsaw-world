import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/board.dart';
import '../models/models.dart';
import 'catalog.dart';
import 'profile.dart';
import 'progress.dart';

/// Which pictures Quick play draws from, in order of preference.
enum QuickPlayTier {
  /// Pictures the player has never opened (no progress row).
  fresh,

  /// Pictures played before that still have fewer than three stars.
  improve,

  /// Every playable picture, once each one has three stars.
  any,
}

/// The pictures Quick play picks from right now and the tier they come from.
@immutable
class QuickPlayPool {
  const QuickPlayPool(this.tier, this.puzzles);
  final QuickPlayTier tier;
  final List<Puzzle> puzzles;
}

/// A daily picture whose day has not come yet (local time), like
/// [Puzzle.isLockedByDate] but against [now].
bool lockedByDateOn(Puzzle p, DateTime now) {
  final d = p.date;
  if (d == null) return false;
  return DateTime(d.year, d.month, d.day).isAfter(DateTime(now.year, now.month, now.day));
}

/// The catalogue pictures Quick play may start: pictures of packs the
/// player can play ([isUnlocked]) that are open today, narrowed to the first
/// tier that has any (never played, then played with fewer than three
/// stars, then all of them). Null when nothing is playable.
///
/// [puzzles] is the catalogue only (My Puzzles photos are not in it).
QuickPlayPool? quickPlayPool({
  required Iterable<Pack> packs,
  required Iterable<Puzzle> puzzles,
  required Map<String, PuzzleProgress> progress,
  required bool Function(Pack pack) isUnlocked,
  required DateTime now,
}) {
  final open = {for (final p in packs) if (isUnlocked(p)) p.id};
  final playable = [for (final z in puzzles) if (open.contains(z.packId) && !lockedByDateOn(z, now)) z];
  if (playable.isEmpty) return null;
  final fresh = [for (final z in playable) if (progress[z.id] == null) z];
  if (fresh.isNotEmpty) return QuickPlayPool(QuickPlayTier.fresh, fresh);
  final improve = [for (final z in playable) if (progress[z.id]!.stars < 3) z];
  if (improve.isNotEmpty) return QuickPlayPool(QuickPlayTier.improve, improve);
  return QuickPlayPool(QuickPlayTier.any, playable);
}

/// One picture from [pool] at random, or null for an empty pool.
Puzzle? pickQuickPlay(QuickPlayPool? pool, Random random) {
  if (pool == null || pool.puzzles.isEmpty) return null;
  return pool.puzzles[random.nextInt(pool.puzzles.length)];
}

/// The mode and board tier of the player's most recently finished game,
/// the choice Quick play repeats. Null before the first finished game.
///
/// The board's columns and rows are those of a reference picture; the game
/// screen lays the same tier out for the picked picture's proportions.
BoardSpec? lastFinishedBoard(Map<String, PuzzleProgress> progress) {
  PuzzleProgress? last;
  for (final row in progress.values) {
    if (!row.completed || row.completedAt == null) continue;
    if (last == null || row.completedAt!.isAfter(last.completedAt!)) last = row;
  }
  if (last == null) return null;
  return BoardSpec.fromCells(GameMode.fromCode(last.mode), last.gridSize);
}

/// Where Quick play goes for [puzzle]: its saved board when one is in
/// progress, a new game on [board] when the player has a last board, else the
/// picture's difficulty screen so the mode and board can be chosen.
String quickPlayRoute(Puzzle puzzle, {PuzzleProgress? saved, BoardSpec? board}) {
  if (saved != null && saved.inProgress) {
    final spec = BoardSpec.fromCells(GameMode.fromCode(saved.mode), saved.gridSize);
    return '/game/${puzzle.id}/${BoardCode.toPath(spec.fullCode)}';
  }
  if (board != null) return '/game/${puzzle.id}/${BoardCode.toPath(board.fullCode)}';
  return '/play/${puzzle.id}';
}

/// Quick play's pool for the signed-in player (Home shows what it will do).
final quickPlayPoolProvider = Provider<QuickPlayPool?>((ref) {
  final packs = ref.watch(packsProvider).value;
  final puzzles = ref.watch(allPuzzlesProvider).value;
  if (packs == null || puzzles == null) return null;
  // isUnlocked reads the profile (VIP, bought packs).
  ref.watch(profileProvider);
  final profile = ref.read(profileProvider.notifier);
  return quickPlayPool(
    packs: packs,
    puzzles: puzzles,
    progress: ref.watch(progressProvider).value ?? const {},
    isUnlocked: profile.isUnlocked,
    now: DateTime.now(),
  );
});

/// The board Quick play starts on, when the player has finished a game.
final quickPlayBoardProvider = Provider<BoardSpec?>((ref) {
  return lastFinishedBoard(ref.watch(progressProvider).value ?? const {});
});
