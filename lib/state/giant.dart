import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'catalog.dart';
import 'social.dart';

/// Category of the Giant pack: pictures hosted at up to 4096 px, large and detailed enough for
/// boards of 100 to 300 cards (`BoardSpec.giantTiers`). They offer only the giant sizes.
const giantCategory = 'Giant';

/// Whether [pack] is a Giant pack.
bool isGiantPack(Pack pack) => pack.category.toLowerCase() == giantCategory.toLowerCase();

/// Whether the picture [puzzleId] belongs to a Giant pack (its boards come from the giant
/// ladder, its picture is decoded at full size so zooming in stays sharp).
final isGiantPuzzleProvider = Provider.family<bool, String>((ref, puzzleId) {
  final puzzle = ref.watch(resolvedPuzzleProvider(puzzleId));
  // My Puzzles photos are never part of a pack.
  if (puzzle == null || puzzle.packId.isEmpty || puzzle.packId == 'my-puzzles') return false;
  final packs = ref.watch(packsProvider).value ?? const <Pack>[];
  for (final p in packs) {
    if (p.id == puzzle.packId) return isGiantPack(p);
  }
  return false;
});
