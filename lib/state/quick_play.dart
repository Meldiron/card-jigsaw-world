import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/board.dart';
import '../models/models.dart';
import 'catalog.dart';
import 'giant.dart';
import 'profile.dart';
import 'progress.dart';
import 'settings.dart';
import 'rewards.dart';

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
/// the choice Quick play preselects. Null before the first finished game.
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

/// Where Quick play goes for [puzzle]: its difficulty screen, so the mode
/// and board can be chosen (owner request: Quick play never starts a game by
/// itself). [board], the player's last board, is preselected; a board in
/// progress ([saved]) opens on its own mode and size with Continue. The
/// screen knows it came from Quick play (`from=quick`) and offers Another
/// picture.
String quickPlayRoute(Puzzle puzzle, {PuzzleProgress? saved, BoardSpec? board}) {
  final preselect = board != null && (saved == null || !saved.inProgress);
  return Uri(path: '/play/${puzzle.id}', queryParameters: {
    if (preselect) 'grid': BoardCode.toPath(board.fullCode),
    'from': 'quick',
  }).toString();
}

/// [board] when the player may still play its tier (by level, or bought with [hasTier]); null
/// otherwise, and Quick play preselects nothing.
BoardSpec? openQuickPlayBoard(BoardSpec? board, {required int level, required bool Function(GameMode mode, int tier) hasTier}) {
  if (board == null) return null;
  final tier = board.tierIndex;
  return tier <= LevelRewards.maxTierIndex(level) || hasTier(board.mode, tier) ? board : null;
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
    // Giant boards (100 cards and more) are never a quick game.
    packs: [for (final p in packs) if (!isGiantPack(p)) p],
    puzzles: puzzles,
    progress: ref.watch(progressProvider).value ?? const {},
    isUnlocked: profile.isUnlocked,
    now: DateTime.now(),
  );
});

/// The board Quick play preselects: the one the player last chose with Play (Settings.lastBoard),
/// else the board of their last finished game.
final quickPlayBoardProvider = Provider<BoardSpec?>((ref) {
  final last = ref.watch(settingsProvider.select((s) => s.lastBoard));
  if (last != null) return BoardSpec.forPicture(GameMode.fromCode(last.mode), last.tier, BoardSpec.referenceAspect);
  return lastFinishedBoard(ref.watch(progressProvider).value ?? const {});
});
