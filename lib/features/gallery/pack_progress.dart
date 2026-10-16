import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/progress.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// How far the player is through one pack: pictures solved and stars earned.
///
/// Every pack surface (library cards, the Home event and month rows, the
/// Quests event cards) reads it from [packProgressProvider], so they always
/// agree with each other and with the pack page.
@immutable
class PackProgress {
  const PackProgress({required this.solved, required this.total, required this.stars, this.playing = 0});

  /// Counts from the pack's pictures and the player's progress rows.
  /// [fallbackTotal] stands in for the picture count while the catalogue
  /// is still loading.
  factory PackProgress.of(List<Puzzle> puzzles, Map<String, PuzzleProgress> rows, {int fallbackTotal = 0}) {
    var solved = 0;
    var stars = 0;
    var playing = 0;
    for (final p in puzzles) {
      final row = rows[p.id];
      if (row == null) continue;
      if (row.completed) solved++;
      if (row.inProgress) playing++;
      stars += row.stars;
    }
    return PackProgress(solved: solved, total: puzzles.isEmpty ? fallbackTotal : puzzles.length, stars: stars, playing: playing);
  }

  final int solved;
  final int total;
  final int stars;

  /// Boards left unfinished in this pack (saved, not yet solved).
  final int playing;

  /// At least one picture solved or a board in progress.
  bool get started => solved > 0 || playing > 0;

  int get maxStars => total * 3;

  /// Every picture solved.
  bool get complete => total > 0 && solved >= total;

  /// Every picture solved with three stars.
  bool get perfect => complete && stars >= maxStars;

  double get solvedRatio => total == 0 ? 0 : (solved / total).clamp(0.0, 1.0);
  double get starRatio => maxStars == 0 ? 0 : (stars / maxStars).clamp(0.0, 1.0);

  @override
  bool operator ==(Object other) => other is PackProgress && other.solved == solved && other.total == total && other.stars == stars && other.playing == playing;

  @override
  int get hashCode => Object.hash(solved, total, stars, playing);

  @override
  String toString() => 'PackProgress($solved/$total, $stars/$maxStars stars, $playing playing)';
}

/// Progress of a pack by id: its pictures from the catalogue and the
/// player's own progress rows (the same source the pack page uses).
final packProgressProvider = Provider.family<PackProgress, String>((ref, packId) {
  final puzzles = ref.watch(packPuzzlesProvider(packId)).value ?? const <Puzzle>[];
  final rows = ref.watch(progressProvider).value ?? const <String, PuzzleProgress>{};
  var fallback = 0;
  if (puzzles.isEmpty) {
    for (final p in ref.watch(packsProvider).value ?? const <Pack>[]) {
      if (p.id == packId) {
        fallback = p.imageCount;
        break;
      }
    }
  }
  return PackProgress.of(puzzles, rows, fallbackTotal: fallback);
});

/// Progress of every visible pack in one pass, for lists that filter or sort packs by it (Home's
/// unfinished and finished rows, the Library's Finished and Started filters).
final allPackProgressProvider = Provider<Map<String, PackProgress>>((ref) {
  final packs = ref.watch(packsProvider).value ?? const <Pack>[];
  final puzzles = ref.watch(allPuzzlesProvider).value ?? const <Puzzle>[];
  final rows = ref.watch(progressProvider).value ?? const <String, PuzzleProgress>{};
  final byPack = <String, List<Puzzle>>{};
  for (final p in puzzles) {
    (byPack[p.packId] ??= []).add(p);
  }
  return {for (final p in packs) p.id: PackProgress.of(byPack[p.id] ?? const [], rows, fallbackTotal: p.imageCount)};
});

/// Cover badges for a finished pack: a green check once every picture is
/// solved, with a star badge before it when every picture also has three
/// stars. Draws nothing until the pack is complete.
class PackDoneBadges extends StatelessWidget {
  const PackDoneBadges({super.key, required this.progress, this.size = 26});
  final PackProgress progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!progress.complete) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (progress.perfect) ...[_DoneBadge(size: size, perfect: true), SizedBox(width: (size * 0.23).roundToDouble())],
        _DoneBadge(size: size, perfect: false),
      ],
    );
  }
}

class _DoneBadge extends StatelessWidget {
  const _DoneBadge({required this.size, required this.perfect});
  final double size;
  final bool perfect;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: perfect ? 'Three stars on every picture' : 'Every picture solved',
      child: Container(
        key: ValueKey(perfect ? 'pack-perfect-badge' : 'pack-done-badge'),
        width: size,
        height: size,
        // Perfect: a gold star on white with a gold ring, so it is not mistaken for the coin mark
        // (a gold disc with a star).
        decoration: BoxDecoration(
          color: perfect ? Colors.white : Brand.success,
          shape: BoxShape.circle,
          border: Border.all(color: perfect ? Brand.star : Colors.white.withValues(alpha: 0.9), width: perfect ? 2 : 1.5),
        ),
        child: Icon(perfect ? AppIcons.star : AppIcons.checkmark, size: size * (perfect ? 0.56 : 0.54), color: perfect ? Brand.star : Colors.white),
      ),
    );
  }
}

/// The progress line under a pack's name: a bar and the count.
///
/// Until every picture is solved the bar tracks solved pictures ("12/30").
/// After that it tracks stars, in the star colour over a full muted bar
/// ("30/30 · 84/90" and a star), so only a pack with three stars everywhere
/// reads as full. Where the line is too narrow for both counts, the solved
/// count is left out: the check badge on the cover already says it.
///
/// [onImage] draws it in white for use over a picture with a scrim.
class PackProgressLine extends StatelessWidget {
  const PackProgressLine({super.key, required this.progress, this.onImage = false, this.height = 5, this.fontSize = TypeSize.micro});
  final PackProgress progress;
  final bool onImage;
  final double height;
  final double fontSize;

  /// Narrowest bar worth drawing next to the full count.
  static const double minBar = 36;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = progress;
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: onImage ? FontWeight.w600 : FontWeight.w500,
      color: onImage ? Colors.white : c.textSecondary,
    );
    final starSize = fontSize - 1;
    final gap = onImage ? 6.0 : 8.0;

    final Widget bar = p.complete
        ? ProgressBar(
            value: p.starRatio,
            height: height,
            color: context.star,
            background: onImage ? Colors.white.withValues(alpha: 0.35) : context.accent.withValues(alpha: 0.28),
          )
        : ProgressBar(
            value: p.solvedRatio,
            height: height,
            color: onImage ? Colors.white : null,
            background: onImage ? Colors.white.withValues(alpha: 0.3) : null,
          );

    if (!p.complete) {
      return Row(
        children: [
          Expanded(child: bar),
          SizedBox(width: gap),
          Text('${p.solved}/${p.total}', style: style),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, cons) {
        final full = '${p.solved}/${p.total} · ${p.stars}/${p.maxStars}';
        // Measure with the style the Text will really use (inherited font included).
        final painter = TextPainter(
          text: TextSpan(text: full, style: DefaultTextStyle.of(context).style.merge(style)),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final fits = !cons.hasBoundedWidth || cons.maxWidth - gap - painter.width - 2 - starSize >= minBar;
        painter.dispose();
        return Row(
          children: [
            Expanded(child: bar),
            SizedBox(width: gap),
            Text(fits ? full : '${p.stars}/${p.maxStars}', style: style),
            const SizedBox(width: 2),
            Icon(AppIcons.star, size: starSize, color: context.star),
          ],
        );
      },
    );
  }
}
