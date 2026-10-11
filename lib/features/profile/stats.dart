import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../game/modes.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/social.dart';

/// Numbers for the profile's Statistics section, derived from the profile
/// row, the per-picture progress rows and the catalog. Anything not tracked
/// for an older account simply reads 0.
class PlayerStats {
  const PlayerStats({
    required this.solved,
    required this.perfect,
    required this.stars,
    required this.streak,
    required this.longestStreak,
    required this.moves,
    required this.seconds,
    required this.hints,
    required this.peeks,
    required this.magic,
    required this.packsCompleted,
    required this.packsTotal,
    required this.eventsCompleted,
    required this.level,
    required this.xp,
    required this.solvedByMode,
    required this.bestSecondsByMode,
  });

  final int solved;
  final int perfect;
  final int stars;
  final int streak;
  final int longestStreak;
  final int moves;
  final int seconds;
  final int hints;
  final int peeks;
  final int magic;
  final int packsCompleted;
  final int packsTotal;
  final int eventsCompleted;
  final int level;
  final int xp;
  final Map<GameMode, int> solvedByMode;
  /// Fastest completed board per mode; absent when none was completed.
  final Map<GameMode, int> bestSecondsByMode;
}

final playerStatsProvider = Provider<PlayerStats>((ref) {
  final profile = ref.watch(profileProvider).value ?? Profile.guest('local');
  final progress = ref.watch(progressProvider).value ?? const <String, PuzzleProgress>{};
  final rows = progress.values.toList();
  final done = rows.where((p) => p.completed).toList();

  final solvedByMode = <GameMode, int>{};
  final bestByMode = <GameMode, int>{};
  for (final p in done) {
    final m = GameMode.fromCode(p.mode);
    solvedByMode[m] = (solvedByMode[m] ?? 0) + 1;
    final best = p.bestSeconds ?? (p.elapsedSeconds > 0 ? p.elapsedSeconds : null);
    if (best != null && best > 0 && (bestByMode[m] == null || best < bestByMode[m]!)) bestByMode[m] = best;
  }

  // Packs whose every picture is solved (only packs with a known picture list).
  final packs = ref.watch(packsProvider).value ?? const <Pack>[];
  final puzzles = ref.watch(allPuzzlesProvider).value ?? const <Puzzle>[];
  final byPack = <String, List<Puzzle>>{};
  for (final z in puzzles) {
    byPack.putIfAbsent(z.packId, () => []).add(z);
  }
  var packsCompleted = 0;
  for (final pack in packs) {
    final list = byPack[pack.id];
    if (list == null || list.isEmpty) continue;
    if (list.every((z) => progress[z.id]?.completed == true)) packsCompleted++;
  }

  final events = ref.watch(eventsProvider).value ?? const <GameEvent>[];
  final goals = {for (final e in events) e.id: e.goal};
  final eventProgress = ref.watch(eventProgressProvider).value ?? const <String, EventProgress>{};
  final eventsCompleted = eventProgress.values.where((e) => e.claimed || e.progress >= (goals[e.eventId] ?? 1 << 30)).length;

  return PlayerStats(
    solved: profile.puzzlesCompleted,
    perfect: done.where((p) => p.stars >= 3).length,
    stars: profile.totalStars,
    streak: profile.streak,
    longestStreak: profile.longestStreak,
    moves: rows.fold(0, (s, p) => s + p.totalMoves),
    seconds: rows.fold(0, (s, p) => s + p.totalSeconds),
    hints: rows.fold(0, (s, p) => s + p.totalHints),
    peeks: ref.watch(ledgerCountProvider('peek')).value ?? 0,
    magic: ref.watch(ledgerCountProvider('magic-lock')).value ?? 0,
    packsCompleted: packsCompleted,
    packsTotal: packs.where((p) => (byPack[p.id] ?? const []).isNotEmpty).length,
    eventsCompleted: eventsCompleted,
    level: profile.level,
    xp: profile.xp,
    solvedByMode: solvedByMode,
    bestSecondsByMode: bestByMode,
  );
});

/// Compact duration for stat tiles: `42s`, `12m`, `3h 05m`, `2d 4h`.
String formatPlayTime(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final d = seconds ~/ 86400, h = (seconds % 86400) ~/ 3600, m = (seconds % 3600) ~/ 60;
  if (d > 0) return '${d}d ${h}h';
  if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
  return '${m}m';
}
