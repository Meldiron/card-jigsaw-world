import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories.dart';
import 'auth.dart';
import 'merge.dart';
import 'profile.dart';
import 'progress.dart';
import 'settings.dart';

/// What happened to the guest save after a sign-in, for the toast.
enum MergeOutcome {
  /// The identity was linked to the guest: same user, nothing to merge.
  linked,

  /// The account's coins, level and streak were kept (device unlocks added).
  keptAccount,

  /// This device's coins, level and streak were written to the account.
  keptGuest,
}

/// Moves a guest save into an existing account: snapshots the guest before
/// the session switches, then combines both saves under the account session
/// (see `merge.dart` for the rules). Web keeps the snapshot in local storage
/// because the OAuth redirect reloads the page.
class SaveMerge {
  SaveMerge(this._ref);
  final Ref _ref;

  static const pendingKey = 'pendingMerge';

  /// The save of [userId]: fresh rows from the backend, or the providers'
  /// cached copy when the backend cannot be reached.
  Future<SaveSnapshot?> snapshot(String userId) async {
    try {
      final meta = await _ref.read(profileRepositoryProvider).fetchWithMeta(userId);
      final rows = await _ref.read(progressRepositoryProvider).forUserWithMeta(userId);
      if (meta == null && rows.isEmpty) return null;
      return SaveSnapshot(
        userId: userId,
        profile: meta?.profile.toData() ?? const {},
        progress: [for (final r in rows) {...r.row.toData(), '\$updatedAt': r.updatedAt?.toIso8601String()}],
        updatedAt: meta?.updatedAt,
      );
    } catch (e) {
      debugPrint('snapshot fetch failed, using cache: $e');
      final profile = _ref.read(profileProvider).value;
      if (profile == null || profile.id != userId) return null;
      final progress = _ref.read(progressProvider).value?.values ?? const Iterable.empty();
      return SaveSnapshot(userId: userId, profile: profile.toData(), progress: [for (final p in progress) p.toData()]);
    }
  }

  // ---- web: the snapshot survives the redirect in local storage ----

  Future<void> storePending(SaveSnapshot s, {int attempt = 1}) =>
      _ref.read(localStoreProvider).setJson(pendingKey, {'attempt': attempt, 'snapshot': s.toJson()});

  ({SaveSnapshot snapshot, int attempt})? pending() {
    final j = _ref.read(localStoreProvider).getJson(pendingKey);
    if (j == null) return null;
    try {
      return (snapshot: SaveSnapshot.fromJson(Map<String, dynamic>.from(j['snapshot'] as Map)), attempt: (j['attempt'] as num?)?.toInt() ?? 1);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearPending() => _ref.read(localStoreProvider).remove(pendingKey);

  /// Combines [guest] into the account the current session belongs to.
  /// [ask] is called only when neither save clearly wins. The guest's own
  /// rows are never touched.
  Future<MergeOutcome> mergeInto(
    String accountId,
    SaveSnapshot guest, {
    required Future<MergeChoice> Function(SaveSnapshot guest, SaveSnapshot account) ask,
  }) async {
    if (guest.userId == accountId) return MergeOutcome.linked;
    final profiles = _ref.read(profileRepositoryProvider);
    final progress = _ref.read(progressRepositoryProvider);

    var meta = await profiles.fetchWithMeta(accountId);
    if (meta == null) {
      final user = _ref.read(authProvider).value;
      meta = (profile: await profiles.create(accountId, name: user?.name), updatedAt: null);
    }
    final rows = await progress.forUserWithMeta(accountId);
    final account = SaveSnapshot(
      userId: accountId,
      profile: meta.profile.toData(),
      progress: [for (final r in rows) {...r.row.toData(), '\$updatedAt': r.updatedAt?.toIso8601String()}],
      updatedAt: meta.updatedAt,
    );

    final choice = switch (decide(guest: guest, account: account)) {
      MergeDecision.keepGuest => MergeChoice.guest,
      MergeDecision.keepAccount => MergeChoice.account,
      MergeDecision.ask => await ask(guest, account),
    };

    final merged = mergeProgress(guest.progress, account.progress);
    for (final e in merged.changed.entries) {
      final data = {...e.value}..remove('userId')..remove('puzzleId')..remove('id');
      try {
        await progress.upsert(accountId, e.key, data);
      } catch (err) {
        debugPrint('merge: progress ${e.key} failed: $err');
      }
    }
    await profiles.update(accountId, mergeProfile(guest: guest, account: account, choice: choice, mergedProgress: merged.all));
    return choice == MergeChoice.guest ? MergeOutcome.keptGuest : MergeOutcome.keptAccount;
  }
}

final saveMergeProvider = Provider<SaveMerge>((ref) => SaveMerge(ref));
