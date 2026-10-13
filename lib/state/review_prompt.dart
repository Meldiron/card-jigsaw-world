import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/app_review.dart';
import '../core/qa.dart';
import '../models/models.dart';
import 'catalog.dart';
import 'progress.dart';
import 'settings.dart';

/// Rules for the App Store rating prompt: only right after a happy moment (a 3-star solve, or the
/// solve that finishes a pack), never before [minSolved] solved pictures, at most once per app
/// version and once per [gap], and never within [adShield] of an ad break (the prompt must not
/// land on top of one). StoreKit may still decide not to show it.
class ReviewRules {
  ReviewRules._();

  static const minSolved = 5;
  static const gap = Duration(days: 120);
  static const adShield = Duration(minutes: 2);

  /// A completion older than this when the progress list changes came from another device or an
  /// earlier session, not from the board the player just finished.
  static const fresh = Duration(minutes: 2);

  /// Wait for the win screen to settle before asking.
  static const delay = Duration(milliseconds: 1600);

  static bool shouldAsk({
    required bool happy,
    required int solved,
    required DateTime now,
    required String version,
    DateTime? lastAskedAt,
    String? lastAskedVersion,
    DateTime? lastAdAt,
  }) {
    if (!happy || solved < minSolved) return false;
    if (lastAskedVersion == version) return false;
    if (lastAskedAt != null && now.difference(lastAskedAt) < gap) return false;
    if (lastAdAt != null && now.difference(lastAdAt).abs() < adShield) return false;
    return true;
  }

  /// Pictures in [next] that were finished just now: completed with a completion time newer than in
  /// [prev] and less than [fresh] old.
  static List<PuzzleProgress> justFinished(Map<String, PuzzleProgress> prev, Map<String, PuzzleProgress> next, DateTime now) => [
        for (final row in next.values)
          if (row.completed && row.completedAt != null && now.difference(row.completedAt!) < fresh)
            if (prev[row.puzzleId]?.completedAt == null || row.completedAt!.isAfter(prev[row.puzzleId]!.completedAt!)) row,
      ];

  /// A happy moment: three stars, or the first solve of a picture that finishes its pack.
  static bool isHappy(PuzzleProgress row, {required PuzzleProgress? before, required Iterable<Puzzle> pack, required Map<String, PuzzleProgress> progress}) {
    if (row.stars >= 3) return true;
    if (before?.completed == true || pack.isEmpty) return false;
    return pack.every((p) => progress[p.id]?.completed == true);
  }
}

/// Watches finished boards and asks for a rating at a happy moment. Kept alive by the tab shell.
class ReviewPrompter {
  ReviewPrompter(this._ref);
  final Ref _ref;
  bool _asking = false;

  static const _askedAtKey = 'reviewAskedAt';
  static const _askedVersionKey = 'reviewAskedVersion';

  /// Integration suites solve many 3-star boards; the prompt stays out of their way unless a suite
  /// that checks it turns it on.
  static bool allowInIntegrationRuns = false;

  void onProgress(Map<String, PuzzleProgress> prev, Map<String, PuzzleProgress> next) {
    if (!AppReviewChannel.supported || _asking) return;
    if (QaRun.integrationRun && !allowInIntegrationRuns) return;
    final now = DateTime.now();
    final finished = ReviewRules.justFinished(prev, next, now);
    if (finished.isEmpty) return;
    final puzzles = _ref.read(allPuzzlesProvider).value ?? const <Puzzle>[];
    final happy = finished.any((row) {
      final picture = puzzles.where((p) => p.id == row.puzzleId).firstOrNull;
      final pack = picture == null ? const <Puzzle>[] : puzzles.where((p) => p.packId == picture.packId);
      return ReviewRules.isHappy(row, before: prev[row.puzzleId], pack: pack, progress: next);
    });
    if (!happy) return;
    final solved = next.values.where((p) => p.completed).length;
    unawaited(_maybeAsk(happy: happy, solved: solved));
  }

  Future<void> _maybeAsk({required bool happy, required int solved}) async {
    _asking = true;
    try {
      final store = _ref.read(localStoreProvider);
      final version = (await PackageInfo.fromPlatform()).version;
      await Future<void>.delayed(ReviewRules.delay);
      final now = DateTime.now();
      final ads = [store.lastInterstitialAt, store.lastRewardedAt].whereType<DateTime>();
      final lastAd = ads.isEmpty ? null : ads.reduce((a, b) => a.isAfter(b) ? a : b);
      final ask = ReviewRules.shouldAsk(
        happy: happy,
        solved: solved,
        now: now,
        version: version,
        lastAskedAt: DateTime.tryParse(store.getText(_askedAtKey) ?? ''),
        lastAskedVersion: store.getText(_askedVersionKey),
        lastAdAt: lastAd,
      );
      if (!ask || WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
      if (await AppReviewChannel.request()) {
        await store.setText(_askedAtKey, now.toIso8601String());
        await store.setText(_askedVersionKey, version);
      }
    } finally {
      _asking = false;
    }
  }
}

final reviewPromptProvider = Provider<ReviewPrompter>((ref) {
  final prompter = ReviewPrompter(ref);
  ref.listen(progressProvider, (prev, next) {
    final before = prev?.value, after = next.value;
    if (before != null && after != null && !identical(before, after)) prompter.onProgress(before, after);
  });
  return prompter;
});
