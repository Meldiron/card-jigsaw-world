import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../game/game_controller.dart' show formatDuration;
import '../../game/modes.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/completion.dart';
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
    required this.quests,
    this.completion,
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
  /// read 0 until they finish a board). "Total Completion" puts their public
  /// completion numbers over this device's [catalogue] (left out while it loads).
  factory PlayerStats.fromProfile(Profile p, {CatalogueSize? catalogue}) => PlayerStats(
        solved: p.puzzlesCompleted,
        stars: p.totalStars,
        streak: p.streak,
        longestStreak: p.longestStreak,
        moves: p.totalMoves,
        seconds: p.totalSeconds,
        level: p.level,
        xp: p.xp,
        solvedByMode: {for (final m in GameMode.values) m: p.solvedByMode[m.code] ?? 0},
        quests: p.questsCompleted,
        completion: catalogue == null ? null : CompletionTotals.forProfile(p, catalogue),
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

  /// Quests claimed over the player's lifetime (daily and weekly, VIP ones included).
  final int quests;

  /// "Total Completion": catalogue pictures and packs solved, and with three stars. Null while
  /// the catalogue loads.
  final CompletionTotals? completion;

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
    quests: profile.questsCompleted,
    completion: ref.watch(completionTotalsProvider),
    bestSecondsByMode: bestByMode,
  );
});

/// Statistics as inset grouped lists (the iOS Settings and Health idiom): label on the left,
/// value on the right, in small titled groups, plus a per-mode table in the same style. Shared by
/// the own profile and other players' profiles; rows whose number is not available are left
/// out. Level and packs are not repeated here: the header shows the level and Total
/// Completion shows the packs.
class StatisticsSection extends StatelessWidget {
  const StatisticsSection({super.key, required this.stats, this.omit = const {}, this.compact = false});
  final PlayerStats stats;

  /// Tiles the page already shows elsewhere: 'solved', 'stars', 'streak', 'longestStreak', 'level'.
  final Set<String> omit;

  /// Total Completion and four headline rows only (own Profile); the rest opens from "See all".
  final bool compact;

  static String _days(int v) => '${formatCount(v)} ${v == 1 ? 'day' : 'days'}';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = stats;
    final groups = <(String, List<(IconData, Color?, String, String)>)>[
      ('Puzzles', [
        if (!omit.contains('solved')) (AppIcons.puzzle, null, 'Puzzles solved', formatCount(s.solved)),
        if (s.perfect != null) (AppIcons.star, Brand.star, '3-star solves', formatCount(s.perfect!)),
        if (!omit.contains('stars')) (AppIcons.star, Brand.star, 'Stars collected', formatCount(s.stars)),
        (AppIcons.swaps, null, 'Moves made', formatCount(s.moves)),
        (AppIcons.time, null, 'Time played', formatPlayTime(s.seconds)),
      ]),
      ('Streaks and quests', [
        if (!omit.contains('streak')) (AppIcons.streak, null, 'Current streak', _days(s.streak)),
        if (!omit.contains('longestStreak')) (AppIcons.trophy, null, 'Longest streak', _days(s.longestStreak)),
        (AppIcons.quests, null, 'Quests completed', formatCount(s.quests)),
        if (s.eventsCompleted != null) (AppIcons.events, null, 'Events completed', formatCount(s.eventsCompleted!)),
      ]),
      if (s.hints != null || s.peeks != null || s.magic != null)
        ('Boosters used', [
          if (s.hints != null) (AppIcons.hint, Brand.hint, 'Hints', formatCount(s.hints!)),
          if (s.peeks != null) (AppIcons.peek, null, 'Peeks', formatCount(s.peeks!)),
          if (s.magic != null) (AppIcons.magic, null, 'Magic', formatCount(s.magic!)),
        ]),
    ];
    if (compact) {
      const keep = {'Puzzles solved', 'Stars collected', 'Current streak', 'Time played'};
      final rows = [for (final g in groups) ...g.$2.where((t) => keep.contains(t.$3))];
      groups
        ..clear()
        ..add(('', rows));
    }
    final best = s.bestSecondsByMode;
    const figures = [FontFeature.tabularFigures()];
    Widget label(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
          child: Text(text.toUpperCase(), style: TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: c.textTertiary)),
        );
    Widget card(List<Widget> rows) => SoftCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i < rows.length - 1) Divider(height: 1, color: c.stroke, indent: 46),
              ],
            ],
          ),
        );
    Widget row(IconData icon, Color? tint, String name, List<Widget> values) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              SizedBox(width: 20, child: Icon(icon, size: 18, color: tint ?? context.accent)),
              const SizedBox(width: 12),
              Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w500))),
              ...values,
            ],
          ),
        );
    Widget value(String text, {double? width, Color? color}) => SizedBox(
          width: width,
          child: Text(text, textAlign: TextAlign.right, style: TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w600, color: color, fontFeatures: figures)),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s.completion != null) TotalCompletion(totals: s.completion!),
        for (final g in groups.where((g) => g.$2.isNotEmpty)) ...[
          if (g.$1.isEmpty) const SizedBox(height: 10) else label(g.$1),
          card([for (final t in g.$2) row(t.$1, t.$2, t.$3, [value(t.$4)])]),
        ],
        if (!compact) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 14, 8),
          child: Row(
            children: [
              Expanded(child: Text('BY MODE', style: TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: c.textTertiary))),
              SizedBox(width: 64, child: Text('SOLVED', textAlign: TextAlign.right, style: TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: c.textTertiary))),
              if (best != null) SizedBox(width: 72, child: Text('BEST', textAlign: TextAlign.right, style: TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: c.textTertiary))),
            ],
          ),
        ),
        card([
          for (final m in GameMode.values)
            row(_modeIcon(m), c.textSecondary, m.label, [
              value(formatCount(s.solvedByMode[m] ?? 0), width: 64),
              if (best != null) value(best[m] == null ? '—' : formatDuration(best[m]!), width: 72, color: c.textSecondary),
            ]),
        ]),
        ],
      ],
    );
  }

  static IconData _modeIcon(GameMode m) => switch (m) {
        GameMode.cards => AppIcons.modeCards,
        GameMode.squares => AppIcons.modeSquares,
        GameMode.triangles => AppIcons.modeTriangles,
        GameMode.hexagons => AppIcons.modeHexagons,
      };
}

/// Share of [total] that [part] is, as a whole percentage for a label: never above 100, "<1%"
/// for a start that rounds to nothing, and 100% only when everything is done.
String completionPercent(int part, int total) {
  if (total <= 0 || part <= 0) return '0%';
  if (part >= total) return '100%';
  final p = part * 100 / total;
  if (p < 1) return '<1%';
  return '${p.floor().clamp(1, 99)}%';
}

/// "Total Completion" at the top of the statistics: one bar for pictures and one for packs. Green
/// is what is solved, star yellow the part of it solved with three stars (always a subset, so it
/// leads the green part), with the percentage and the real numbers.
class TotalCompletion extends StatelessWidget {
  const TotalCompletion({super.key, required this.totals});
  final CompletionTotals totals;

  @override
  Widget build(BuildContext context) {
    final t = totals;
    return SoftCard(
      key: const ValueKey('total-completion'),
      padding: Insets.cardCompact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Total Completion', style: TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.body)),
          const SizedBox(height: 12),
          _CompletionLine(label: 'Pictures', done: t.picturesSolved, perfect: t.picturesPerfect, total: t.pictures, doneWord: 'solved'),
          const SizedBox(height: 14),
          _CompletionLine(label: 'Packs', done: t.packsCompleted, perfect: t.packsPerfect, total: t.packs, doneWord: 'finished'),
        ],
      ),
    );
  }
}

class _CompletionLine extends StatelessWidget {
  const _CompletionLine({required this.label, required this.done, required this.perfect, required this.total, required this.doneWord});
  final String label;
  final int done;
  final int perfect;
  final int total;
  final String doneWord;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shownDone = done.clamp(0, total);
    final shownPerfect = perfect.clamp(0, shownDone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w500))),
            Text(completionPercent(shownDone, total), style: const TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w700, fontFeatures: tabularFigures)),
          ],
        ),
        const SizedBox(height: 6),
        TwoToneBar(solved: total == 0 ? 0 : shownDone / total, perfect: total == 0 ? 0 : shownPerfect / total),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 2,
          children: [
            _Legend(color: c.success, text: '${formatCount(shownDone)} of ${formatCount(total)} $doneWord'),
            _Legend(color: Brand.star, text: '${formatCount(shownPerfect)} with every star'),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(fontSize: TypeSize.caption, color: context.colors.textSecondary)),
      ],
    );
  }
}

/// A progress bar in two colours over one track: green up to [solved], star yellow up to
/// [perfect] drawn over its start ([perfect] is never more than [solved]). A part that is not
/// zero stays visible as at least a dot, so a first solve in a big catalogue still shows, and
/// green always shows past the yellow while some solved pictures lack a star.
class TwoToneBar extends StatelessWidget {
  const TwoToneBar({super.key, required this.solved, required this.perfect, this.height = 8});
  final double solved;
  final double perfect;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, cons) {
        final w = cons.maxWidth;
        double width(double f) => f <= 0 ? 0 : (f.clamp(0.0, 1.0) * w).clamp(height, w);
        final yellow = width(perfect.clamp(0.0, solved));
        var green = width(solved);
        // Solved but not all with every star: keep some green past the yellow, even when both
        // are only dots in a big catalogue.
        final tail = yellow + height * 0.75;
        if (solved > perfect && yellow > 0 && green < tail) green = tail > w ? w : tail;
        return ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: SizedBox(
            height: height,
            width: w,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: c.stroke)),
                if (green > 0) Positioned(left: 0, top: 0, bottom: 0, width: green, child: _Segment(color: c.success, radius: height)),
                if (yellow > 0) Positioned(left: 0, top: 0, bottom: 0, width: yellow, child: _Segment(color: Brand.star, radius: height)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)));
}
