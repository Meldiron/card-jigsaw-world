import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../game/game_controller.dart' show formatDuration;
import '../../game/modes.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/social.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// Numbers for a Statistics section. For the signed-in player they come
/// from the profile row, the per-picture progress rows and the catalog; for
/// another player only the public profile row is readable, so the numbers
/// that need private rows are null and their tiles are left out.
class PlayerStats {
  const PlayerStats({
    required this.solved,
    required this.stars,
    required this.streak,
    required this.longestStreak,
    required this.moves,
    required this.seconds,
    required this.level,
    required this.xp,
    required this.solvedByMode,
    this.perfect,
    this.hints,
    this.peeks,
    this.magic,
    this.packsCompleted,
    this.packsTotal,
    this.eventsCompleted,
    this.bestSecondsByMode,
  });

  /// Public aggregates of another player's profile row. Moves, time and the
  /// per-mode counts are the counters bumped on every solve (older accounts
  /// read 0 until they finish a board).
  factory PlayerStats.fromProfile(Profile p) => PlayerStats(
        solved: p.puzzlesCompleted,
        stars: p.totalStars,
        streak: p.streak,
        longestStreak: p.longestStreak,
        moves: p.totalMoves,
        seconds: p.totalSeconds,
        level: p.level,
        xp: p.xp,
        solvedByMode: {for (final m in GameMode.values) m: p.solvedByMode[m.code] ?? 0},
      );

  final int solved;
  final int stars;
  final int streak;
  final int longestStreak;
  final int moves;
  final int seconds;
  final int level;
  final int xp;
  final Map<GameMode, int> solvedByMode;

  // Owner-only numbers (null when looking at another player).
  final int? perfect;
  final int? hints;
  final int? peeks;
  final int? magic;
  final int? packsCompleted;
  final int? packsTotal;
  final int? eventsCompleted;

  /// Fastest completed board per mode; absent when none was completed, null
  /// when the player's boards are not readable.
  final Map<GameMode, int>? bestSecondsByMode;
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
    moves: rows.fold<int>(0, (s, p) => s + p.totalMoves),
    seconds: rows.fold<int>(0, (s, p) => s + p.totalSeconds),
    hints: rows.fold<int>(0, (s, p) => s + p.totalHints),
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

/// Two-column grid of small stat tiles plus a per-mode table. Shared by the
/// own profile and other players' profiles; tiles whose number is not
/// available are simply left out.
class StatisticsSection extends StatelessWidget {
  const StatisticsSection({super.key, required this.stats});
  final PlayerStats stats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = stats;
    final tiles = <(IconData, Color?, String, String)>[
      (AppIcons.puzzle, null, '${s.solved}', 'Puzzles solved'),
      if (s.perfect != null) (AppIcons.star, Brand.star, '${s.perfect}', '3-star solves'),
      (AppIcons.star, Brand.star, '${s.stars}', 'Stars collected'),
      (AppIcons.streak, null, '${s.streak}', 'Current streak'),
      (AppIcons.streak, null, '${s.longestStreak}', 'Longest streak'),
      (AppIcons.level, null, 'LV ${s.level}', '${s.xp} XP'),
      (AppIcons.swaps, null, _n(s.moves), 'Moves made'),
      (AppIcons.time, null, formatPlayTime(s.seconds), 'Time played'),
      if (s.hints != null) (AppIcons.hint, Brand.hint, '${s.hints}', 'Hints used'),
      if (s.peeks != null) (AppIcons.peek, null, '${s.peeks}', 'Peeks used'),
      if (s.magic != null) (AppIcons.magic, null, '${s.magic}', 'Magic used'),
      if (s.packsCompleted != null) (AppIcons.library, null, '${s.packsCompleted}/${s.packsTotal ?? 0}', 'Packs completed'),
      if (s.eventsCompleted != null) (AppIcons.events, null, '${s.eventsCompleted}', 'Events completed'),
    ];
    final best = s.bestSecondsByMode;
    return Column(
      children: [
        GridView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 64),
          itemCount: tiles.length,
          itemBuilder: (_, i) {
            final t = tiles[i];
            return SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: c.boardBackground),
                    child: Icon(t.$1, size: 17, color: t.$2 ?? context.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: -0.3)),
                        Text(t.$4, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        SoftCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('By mode', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                  Text(best == null ? 'Solved' : 'Solved · Best time', style: TextStyle(fontSize: 11, color: c.textTertiary, fontWeight: FontWeight.w500)),
                ],
              ),
              const SizedBox(height: 4),
              for (final m in GameMode.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(_modeIcon(m), size: 16, color: c.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(m.label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500))),
                      Text('${s.solvedByMode[m] ?? 0}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      if (best != null)
                        SizedBox(
                          width: 72,
                          child: Text(
                            best[m] == null ? '—' : formatDuration(best[m]!),
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.textSecondary, fontFeatures: const [FontFeature.tabularFigures()]),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static IconData _modeIcon(GameMode m) => switch (m) {
        GameMode.cards => Icons.style_rounded,
        GameMode.squares => Icons.grid_view_rounded,
        GameMode.triangles => Icons.change_history_rounded,
        GameMode.hexagons => Icons.hexagon_rounded,
      };

  /// Thousands separator for big counters.
  static String _n(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}
