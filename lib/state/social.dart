import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories.dart';
import '../models/models.dart';
import 'auth.dart';
import 'catalog.dart';
import 'profile.dart';

final friendsProvider = FutureProvider<List<Friend>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const [];
  try {
    return await ref.watch(socialRepositoryProvider).friends(userId);
  } catch (e) {
    debugPrint('friends failed: $e');
    return const [];
  }
});

final leaderboardProvider = FutureProvider<List<Profile>>((ref) async {
  try {
    return await ref.watch(profileRepositoryProvider).leaderboard();
  } catch (e) {
    debugPrint('leaderboard failed: $e');
    return const [];
  }
});

/// Another player's public profile (profiles are readable by anyone).
final playerProfileProvider = FutureProvider.family<Profile?, String>((ref, userId) async {
  final me = ref.watch(currentUserIdProvider);
  if (userId == me) {
    final mine = ref.watch(profileProvider).value;
    if (mine != null) return mine;
  }
  return ref.watch(profileRepositoryProvider).findByUserId(userId);
});

/// Lifetime count of a ledger reason for the signed-in player (peeks, magic).
final ledgerCountProvider = FutureProvider.family<int, String>((ref, reason) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return 0;
  try {
    return await ref.watch(profileRepositoryProvider).ledgerCount(userId, reason);
  } catch (e) {
    debugPrint('ledger count failed: $e');
    return 0;
  }
});

final eventProgressProvider = FutureProvider<Map<String, EventProgress>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const {};
  try {
    return await ref.watch(socialRepositoryProvider).eventProgress(userId);
  } catch (e) {
    debugPrint('event progress failed: $e');
    return const {};
  }
});

final communityProgressProvider = FutureProvider.family<int, String>((ref, eventId) async {
  return ref.watch(socialRepositoryProvider).communityProgress(eventId);
});

final myPuzzlesProvider = FutureProvider<List<MyPuzzle>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const [];
  try {
    return await ref.watch(uploadRepositoryProvider).list(userId);
  } catch (e) {
    debugPrint('my puzzles failed: $e');
    return const [];
  }
});

/// Resolves a puzzle id to a [Puzzle], including custom uploads.
final resolvedPuzzleProvider = Provider.family<Puzzle?, String>((ref, id) {
  final fromCatalog = ref.watch(puzzleByIdProvider(id));
  if (fromCatalog != null) return fromCatalog;
  final mine = ref.watch(myPuzzlesProvider).value;
  if (mine != null) {
    for (final m in mine) {
      if (m.id == id) {
        return Puzzle.custom(id: m.id, title: m.title, imageUrl: UploadRepository.imageUrl(m.fileId));
      }
    }
  }
  return null;
});

/// Records progress on every active event when a puzzle is completed.
Future<void> bumpEventProgress(WidgetRef ref, {String? packId}) async {
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) return;
  final events = ref.read(eventsProvider).value ?? const [];
  final progress = ref.read(eventProgressProvider).value ?? const {};
  final repo = ref.read(socialRepositoryProvider);
  for (final e in events.where((e) => e.isActive)) {
    if (e.packId != null && e.packId!.isNotEmpty && e.packId != packId) continue;
    final current = progress[e.id];
    if (current?.claimed == true) continue;
    try {
      await repo.upsertEventProgress(userId, e.id, progress: (current?.progress ?? 0) + 1);
    } catch (err) {
      debugPrint('event bump failed: $err');
    }
  }
  ref.invalidate(eventProgressProvider);
}
