import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/quick_play.dart' show lockedByDateOn;
import '../gallery/pack_progress.dart';

/// Totals over the finished packs, for the line above Home's list.
@immutable
class FinishedStats {
  const FinishedStats({required this.packs, required this.perfect, required this.pictures});

  /// Packs with every picture solved.
  final int packs;

  /// Of those, packs with three stars on every picture.
  final int perfect;

  /// Pictures in the finished packs (all solved).
  final int pictures;

  @override
  bool operator ==(Object other) => other is FinishedStats && other.packs == packs && other.perfect == perfect && other.pictures == pictures;

  @override
  int get hashCode => Object.hash(packs, perfect, pictures);

  @override
  String toString() => 'FinishedStats($packs packs, $perfect perfect, $pictures pictures)';
}

/// Home's pack rows, worked out from the player's progress in one pass.
@immutable
class HomePackRows {
  const HomePackRows({required this.inProgress, required this.missingStars, required this.finished, required this.stats});

  static const empty = HomePackRows(inProgress: [], missingStars: [], finished: [], stats: FinishedStats(packs: 0, perfect: 0, pictures: 0));

  /// Packs started but not finished that still have a picture to play today,
  /// most recently played first.
  final List<Pack> inProgress;

  /// Finished packs without three stars everywhere, fewest stars missing first.
  final List<Pack> missingStars;

  /// Every finished pack, most recently finished first.
  final List<Pack> finished;

  final FinishedStats stats;
}

/// Sorts [packs] into Home's rows.
///
/// * In progress: started, not every picture solved, playable now
///   ([isUnlocked]) and with an unsolved picture whose day has come (a
///   daily month with every day so far solved is not listed until the next
///   day opens).
/// * Missing stars: every picture solved, not all with three stars, and
///   playable now so the stars can still be earned.
/// * Finished: every picture solved, playable or not.
///
/// Recency is the newest `completedAt` among a pack's pictures.
HomePackRows homePackRows({
  required List<Pack> packs,
  required List<Puzzle> puzzles,
  required Map<String, PuzzleProgress> rows,
  required Map<String, PackProgress> progress,
  required bool Function(Pack pack) isUnlocked,
  required DateTime now,
}) {
  final lastPlayed = <String, DateTime>{};
  final openUnsolved = <String>{};
  for (final z in puzzles) {
    final row = rows[z.id];
    final at = row?.completedAt;
    if (at != null) {
      final seen = lastPlayed[z.packId];
      if (seen == null || at.isAfter(seen)) lastPlayed[z.packId] = at;
    }
    if (row?.completed != true && !lockedByDateOn(z, now)) openUnsolved.add(z.packId);
  }
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  int byRecent(Pack a, Pack b) => (lastPlayed[b.id] ?? epoch).compareTo(lastPlayed[a.id] ?? epoch);
  int byCatalog(Pack a, Pack b) => a.sortOrder != b.sortOrder ? a.sortOrder.compareTo(b.sortOrder) : a.id.compareTo(b.id);

  final inProgress = <Pack>[];
  final missingStars = <Pack>[];
  final finished = <Pack>[];
  var perfect = 0, pictures = 0;
  for (final pack in packs) {
    final p = progress[pack.id];
    if (p == null || !p.started) continue;
    if (p.complete) {
      finished.add(pack);
      pictures += p.total;
      if (p.perfect) {
        perfect++;
      } else if (isUnlocked(pack)) {
        missingStars.add(pack);
      }
    } else if (isUnlocked(pack) && openUnsolved.contains(pack.id)) {
      inProgress.add(pack);
    }
  }

  inProgress.sort((a, b) {
    final r = byRecent(a, b);
    if (r != 0) return r;
    final d = progress[b.id]!.solvedRatio.compareTo(progress[a.id]!.solvedRatio);
    return d != 0 ? d : byCatalog(a, b);
  });
  missingStars.sort((a, b) {
    final pa = progress[a.id]!, pb = progress[b.id]!;
    final d = (pa.maxStars - pa.stars).compareTo(pb.maxStars - pb.stars);
    if (d != 0) return d;
    final r = byRecent(a, b);
    return r != 0 ? r : byCatalog(a, b);
  });
  finished.sort((a, b) {
    final r = byRecent(a, b);
    return r != 0 ? r : byCatalog(a, b);
  });

  return HomePackRows(
    inProgress: inProgress,
    missingStars: missingStars,
    finished: finished,
    stats: FinishedStats(packs: finished.length, perfect: perfect, pictures: pictures),
  );
}

/// Home's pack rows for the signed-in player.
final homePackRowsProvider = Provider<HomePackRows>((ref) {
  final packs = ref.watch(packsProvider).value;
  final puzzles = ref.watch(allPuzzlesProvider).value;
  if (packs == null || puzzles == null) return HomePackRows.empty;
  // isUnlocked reads the profile (VIP, bought packs).
  ref.watch(profileProvider);
  return homePackRows(
    packs: packs,
    puzzles: puzzles,
    rows: ref.watch(progressProvider).value ?? const {},
    progress: ref.watch(allPackProgressProvider),
    isUnlocked: ref.read(profileProvider.notifier).isUnlocked,
    now: DateTime.now(),
  );
});
