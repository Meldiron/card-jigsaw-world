import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'profile.dart';
import 'progress.dart';
import 'rewards.dart';
import 'settings.dart';

/// What the player can pick now: the shapes, Painting and giant boards their level has reached,
/// plus anything they already used or opened early with tickets (see [OpenFeatures.forPlayer]).
/// Before the profile loads everything counts as open, so a slow start never locks a board the
/// player is used to.
final openFeaturesProvider = Provider<OpenFeatures>((ref) {
  final profile = ref.watch(profileProvider).value;
  if (profile == null) return OpenFeatures.all;
  final rows = ref.watch(progressProvider).value?.values ?? const <PuzzleProgress>[];
  return OpenFeatures.forPlayer(level: profile.level, progress: rows, solvedByMode: profile.solvedByMode, unlockedTiers: profile.unlockedTiers);
});

/// Unlocks whose one-screen intro was shown on this device.
class UnlockIntros extends Notifier<Set<Unlock>> {
  static const _key = 'unlockIntros';

  @override
  Set<Unlock> build() {
    final seen = ref.read(localStoreProvider).getJson(_key)?['seen'];
    return {
      if (seen is List)
        for (final name in seen)
          for (final u in Unlock.values)
            if (u.name == name) u,
    };
  }

  void markSeen(Unlock u) {
    if (state.contains(u)) return;
    state = {...state, u};
    ref.read(localStoreProvider).setJson(_key, {'seen': [for (final s in state) s.name]});
  }
}

final unlockIntrosProvider = NotifierProvider<UnlockIntros, Set<Unlock>>(UnlockIntros.new);

/// The next intro to show: something open that the player has neither used nor seen the intro
/// of, in unlock order. Null while the profile or the progress loads (an early answer would
/// introduce shapes the player already used).
final pendingUnlockIntroProvider = Provider<Unlock?>((ref) {
  if (ref.watch(profileProvider).value == null || ref.watch(progressProvider).value == null) return null;
  final open = ref.watch(openFeaturesProvider);
  final seen = ref.watch(unlockIntrosProvider);
  for (final u in Unlock.values) {
    if (open.has(u) && !open.used.contains(u) && !seen.contains(u)) return u;
  }
  return null;
});
