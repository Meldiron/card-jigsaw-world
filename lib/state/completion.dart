import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'catalog.dart';
import 'progress.dart';

/// Size of the catalogue on this device: pictures of released packs, and released packs that have
/// pictures. The denominators of "Total Completion" for every profile shown here.
typedef CatalogueSize = ({int pictures, int packs});

/// "Total Completion": how much of the catalogue a player has solved, and how much of it with
/// three stars. Pictures of packs that are no longer in the catalogue and My Puzzles photos never
/// count; a pack counts as finished when every picture is solved and as perfect when every picture
/// has three stars (the same rules as the pack badges, `PackProgress`).
@immutable
class CompletionTotals {
  const CompletionTotals({
    required this.pictures,
    required this.picturesSolved,
    required this.picturesPerfect,
    required this.packs,
    required this.packsCompleted,
    required this.packsPerfect,
    this.ownerId,
  });

  /// The player's own numbers, from their progress rows ([rows] by puzzle id) and the catalogue.
  factory CompletionTotals.of({required List<Pack> packs, required List<Puzzle> puzzles, required Map<String, PuzzleProgress> rows}) {
    final released = {for (final p in packs) p.id};
    final byPack = <String, List<Puzzle>>{};
    for (final z in puzzles) {
      if (released.contains(z.packId)) (byPack[z.packId] ??= []).add(z);
    }
    var pictures = 0, solved = 0, perfect = 0, packsDone = 0, packsPerfect = 0;
    for (final list in byPack.values) {
      var packSolved = 0, packStars = 0;
      for (final z in list) {
        final row = rows[z.id];
        if (row == null) continue;
        packStars += row.stars;
        if (!row.completed) continue;
        packSolved++;
        if (row.stars >= 3) perfect++;
      }
      pictures += list.length;
      solved += packSolved;
      if (packSolved >= list.length) {
        packsDone++;
        if (packStars >= list.length * 3) packsPerfect++;
      }
    }
    final owners = {for (final r in rows.values) r.userId};
    return CompletionTotals(
      pictures: pictures,
      picturesSolved: solved,
      picturesPerfect: perfect,
      packs: byPack.length,
      packsCompleted: packsDone,
      packsPerfect: packsPerfect,
      ownerId: owners.length == 1 ? owners.first : null,
    );
  }

  /// Another player's numbers: the public aggregates on their profile row over this device's
  /// catalogue, capped so a catalogue that shrank never shows more than 100%.
  factory CompletionTotals.forProfile(Profile p, CatalogueSize size) {
    int cap(int v, int max) => v.clamp(0, max);
    final solved = cap(p.picturesSolved, size.pictures);
    final packsDone = cap(p.packsCompleted, size.packs);
    return CompletionTotals(
      pictures: size.pictures,
      picturesSolved: solved,
      picturesPerfect: cap(p.picturesPerfect, solved),
      packs: size.packs,
      packsCompleted: packsDone,
      packsPerfect: cap(p.packsPerfect, packsDone),
      ownerId: p.id,
    );
  }

  final int pictures;
  final int picturesSolved;
  final int picturesPerfect;
  final int packs;
  final int packsCompleted;
  final int packsPerfect;

  /// Whose progress rows these are (null when there are none), so numbers computed while a
  /// sign-in switches players are never written to the wrong profile.
  final String? ownerId;

  /// The profile columns other players read ([Profile.picturesSolved] and the rest).
  Map<String, int> get publicFields => {
        'picturesSolved': picturesSolved,
        'picturesPerfect': picturesPerfect,
        'packsCompleted': packsCompleted,
        'packsPerfect': packsPerfect,
      };

  @override
  bool operator ==(Object other) =>
      other is CompletionTotals &&
      other.pictures == pictures &&
      other.picturesSolved == picturesSolved &&
      other.picturesPerfect == picturesPerfect &&
      other.packs == packs &&
      other.packsCompleted == packsCompleted &&
      other.packsPerfect == packsPerfect &&
      other.ownerId == ownerId;

  @override
  int get hashCode => Object.hash(pictures, picturesSolved, picturesPerfect, packs, packsCompleted, packsPerfect, ownerId);

  @override
  String toString() => 'CompletionTotals($picturesSolved/$pictures pictures, $picturesPerfect perfect; $packsCompleted/$packs packs, $packsPerfect perfect)';
}

/// The catalogue's size here, or null while it loads.
final catalogueSizeProvider = Provider<CatalogueSize?>((ref) {
  final packs = ref.watch(packsProvider).value;
  final puzzles = ref.watch(allPuzzlesProvider).value;
  if (packs == null || puzzles == null || puzzles.isEmpty) return null;
  final t = CompletionTotals.of(packs: packs, puzzles: puzzles, rows: const {});
  return (pictures: t.pictures, packs: t.packs);
});

/// The signed-in player's "Total Completion", or null while the catalogue or progress loads.
final completionTotalsProvider = Provider<CompletionTotals?>((ref) {
  final packs = ref.watch(packsProvider).value;
  final puzzles = ref.watch(allPuzzlesProvider).value;
  final rows = ref.watch(progressProvider).value;
  if (packs == null || puzzles == null || puzzles.isEmpty || rows == null) return null;
  return CompletionTotals.of(packs: packs, puzzles: puzzles, rows: rows);
});
