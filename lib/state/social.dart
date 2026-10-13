import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories.dart';
import '../models/models.dart';
import 'auth.dart';
import 'catalog.dart';
import 'paged.dart';
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

/// The league, most XP first, loaded a page at a time as the list scrolls.
class LeaderboardNotifier extends PagedNotifier<Profile> {
  @override
  int get pageSize => 50;

  @override
  Future<PageResult<Profile>> fetchPage(String? after) => ref.read(profileRepositoryProvider).leaderboardPage(limit: pageSize, after: after);
}

final leaderboardProvider = AsyncNotifierProvider<LeaderboardNotifier, Paged<Profile>>(LeaderboardNotifier.new);

/// The player's place in the league and its size (server-side counts, independent of paging).
/// League place of the row at [index]: players with equal XP share a place (1, 2, 2, 4), the same
/// rule as the "You are #N" header (players with more XP, plus one). Rows are a loaded prefix of the
/// XP-ordered league, so equal XP rows are next to each other.
int leaguePlace(List<Profile> rows, int index) {
  var j = index;
  while (j > 0 && rows[j - 1].xp == rows[index].xp) {
    j--;
  }
  return j + 1;
}

final leaderboardRankProvider = FutureProvider<({int rank, int total})?>((ref) async {
  final me = ref.watch(profileProvider).value;
  if (me == null || me.puzzlesCompleted <= 0) return null;
  try {
    return await ref.watch(profileRepositoryProvider).leaderboardRank(me);
  } catch (e) {
    debugPrint('league rank failed: $e');
    return null;
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

/// The player's photos, newest first, loaded a page at a time as the grid scrolls.
class MyPuzzlesNotifier extends PagedNotifier<MyPuzzle> {
  @override
  int get pageSize => 30;

  @override
  Future<PageResult<MyPuzzle>> fetchPage(String? after) async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return (items: const <MyPuzzle>[], lastId: null);
    return ref.read(uploadRepositoryProvider).page(userId, limit: pageSize, after: after);
  }
}

final myPuzzlesProvider = AsyncNotifierProvider<MyPuzzlesNotifier, Paged<MyPuzzle>>(MyPuzzlesNotifier.new);

/// How many photos the player keeps, for the free limit ([Economy.freeMyPuzzles]).
final myPuzzleCountProvider = FutureProvider<int>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return 0;
  return ref.watch(uploadRepositoryProvider).count(userId);
});

/// One photo by id, for puzzles older than the pages the grid has loaded.
final myPuzzleByIdProvider = FutureProvider.family<MyPuzzle?, String>((ref, id) async {
  if (ref.watch(currentUserIdProvider) == null) return null;
  try {
    return await ref.watch(uploadRepositoryProvider).byId(id);
  } catch (e) {
    debugPrint('my puzzle $id failed: $e');
    return null;
  }
});

/// Resolves a puzzle id to a [Puzzle], including custom uploads.
final resolvedPuzzleProvider = Provider.family<Puzzle?, String>((ref, id) {
  final fromCatalog = ref.watch(puzzleByIdProvider(id));
  if (fromCatalog != null) return fromCatalog;
  Puzzle custom(MyPuzzle m) => Puzzle.custom(id: m.id, title: m.title, imageUrl: UploadRepository.imageUrl(m.fileId));
  for (final m in ref.watch(myPuzzlesProvider).value?.items ?? const <MyPuzzle>[]) {
    if (m.id == id) return custom(m);
  }
  // Only ask the server once the catalogue has loaded: until then every id would look unknown.
  if (ref.watch(allPuzzlesProvider).value == null) return null;
  final single = ref.watch(myPuzzleByIdProvider(id)).value;
  return single == null ? null : custom(single);
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
