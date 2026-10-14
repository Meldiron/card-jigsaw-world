import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'catalog.dart';
import 'progress.dart';

/// Library packs that were free until 2026-10-14, when the owner cut the free library down to six
/// starter packs from six categories (`STARTER_PACKS` in tools/store/apply_pack_prices.py, which
/// priced these as standard coin packs). A player who had started one keeps it open
/// ([keptFreePack]); everyone else unlocks it like any other pack.
const formerlyFreePacks = {
  'abstract-bokeh', 'abstract-dunes', 'abstract-fluid-ink', 'abstract-frost', 'abstract-macro-textures',
  'abstract-marbling', 'ai-abstract', 'ai-birds', 'ai-cats', 'ai-dreamscapes', 'ai-forests',
  'ai-little-creatures', 'autumn-harvest', 'pack-alpine-lakes', 'pack-amsterdam', 'pack-autumn-parks',
  'pack-botanical', 'pack-castles', 'pack-cherry-blossom', 'pack-coffee-shops', 'pack-deer',
  'pack-doors', 'pack-farm-life', 'pack-first-flowers', 'pack-gardens', 'pack-harbours',
  'pack-lighthouses', 'pack-lisbon', 'pack-london', 'pack-misty-forests', 'pack-owls', 'pack-pastries',
  'pack-penguins', 'pack-planets', 'pack-rolling-hills', 'pack-scottish-highlands', 'pack-skylines',
  'pack-steam-trains', 'pack-still-life', 'pack-summer-fruit', 'pack-sunflowers', 'pack-sunsets',
  'pack-tiles', 'pack-windmills', 'pack-winter-scenes',
};

/// A pack that was free until 2026-10-14 stays open for a player who has played it. [playedPacks]
/// is only read for those packs, so a screen of other packs never loads the progress for it.
bool keptFreePack(String packId, Set<String> Function() playedPacks) => formerlyFreePacks.contains(packId) && playedPacks().contains(packId);

/// Ids of the public packs the player has a board or a solved picture in (any progress row). Read
/// from the public catalogue, which never waits on the profile.
final playedPacksProvider = Provider<Set<String>>((ref) {
  final progress = ref.watch(progressProvider).value ?? const <String, PuzzleProgress>{};
  if (progress.isEmpty) return const {};
  final puzzles = ref.watch(publicPuzzlesProvider).value ?? const <Puzzle>[];
  final packOf = {for (final z in puzzles) z.id: z.packId};
  return {for (final id in progress.keys) ?packOf[id]};
});
