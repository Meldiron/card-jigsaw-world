import 'dart:ui' show Offset;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../game/board.dart';
import '../models/models.dart';
import 'catalog.dart';
import 'settings.dart';
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

/// Where each giant board in progress was left (zoom and the part of the
/// picture in view), so it resumes exactly there, and whether the overview
/// map shows. Kept on this device only: a view is a convenience, not save
/// data.
class GiantViews {
  GiantViews(this._store);
  final LocalStore _store;

  static const _viewsKey = 'giantViews';
  static const _prefsKey = 'giantPrefs';

  /// Views kept at most (the oldest go first).
  static const keep = 40;

  /// The saved view's key: one per picture, shape and size.
  static String id(String puzzleId, BoardSpec spec) => '$puzzleId|${spec.mode.code}|${spec.cells}';

  ({double zoom, Offset centre})? read(String id) {
    final v = _store.getJson(_viewsKey)?[id];
    if (v is! Map) return null;
    final z = v['z'], x = v['x'], y = v['y'];
    if (z is! num || x is! num || y is! num) return null;
    return (zoom: z.toDouble(), centre: Offset(x.toDouble(), y.toDouble()));
  }

  void write(String id, ({double zoom, Offset centre}) view) {
    final all = {...?_store.getJson(_viewsKey)}..remove(id);
    // Insertion order is recency: the newest view goes last.
    all[id] = {'z': _round(view.zoom), 'x': _round(view.centre.dx), 'y': _round(view.centre.dy)};
    while (all.length > keep) {
      all.remove(all.keys.first);
    }
    _store.setJson(_viewsKey, all);
  }

  void clear(String id) {
    final all = _store.getJson(_viewsKey);
    if (all == null || !all.containsKey(id)) return;
    _store.setJson(_viewsKey, {...all}..remove(id));
  }

  /// The overview map in the corner of a zoomed giant board (on by default).
  bool get showMap => _store.getJson(_prefsKey)?['map'] != false;
  set showMap(bool v) => _store.setJson(_prefsKey, {...?_store.getJson(_prefsKey), 'map': v});

  static double _round(double v) => (v * 1000).roundToDouble() / 1000;
}

final giantViewsProvider = Provider<GiantViews>((ref) => GiantViews(ref.watch(localStoreProvider)));
