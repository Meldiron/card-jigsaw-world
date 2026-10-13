import 'package:card_jigsaw_world/state/merge.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime.utc(2026, 10, 1);
final t1 = DateTime.utc(2026, 10, 5);
final t2 = DateTime.utc(2026, 10, 9);

Map<String, dynamic> row(String id, {int stars = 3, bool completed = true, int? bestMoves, int? bestSeconds, int totalMoves = 0, DateTime? at, Map<String, dynamic> extra = const {}}) => {
      'puzzleId': id,
      'stars': stars,
      'completed': completed,
      'bestMoves': bestMoves,
      'bestSeconds': bestSeconds,
      'totalMoves': totalMoves,
      if (at != null) '\$updatedAt': at.toIso8601String(),
      ...extra,
    };

SaveSnapshot save(
  String user, {
  int solved = 0,
  int xp = 0,
  int coins = 500,
  int tickets = 1,
  int streak = 0,
  int longestStreak = 0,
  DateTime? at,
  List<String> packs = const [],
  List<String> achievements = const [],
  String name = 'Player',
}) =>
    SaveSnapshot(
      userId: user,
      profile: {'xp': xp, 'level': 1 + xp ~/ 100, 'coins': coins, 'tickets': tickets, 'hints': 2, 'piggyCoins': 40, 'streak': streak, 'longestStreak': longestStreak, 'displayName': name, 'avatar': 'fox', 'unlockedPacks': packs, 'claimedAchievements': achievements, 'puzzlesCompleted': solved, 'totalStars': solved * 3},
      progress: [for (var i = 0; i < solved; i++) row('${user}_p$i', at: at)],
      updatedAt: at,
    );

void main() {
  group('dominance', () {
    test('the newer save with more of everything wins', () {
      final guest = save('g', solved: 5, xp: 400, at: t1);
      final account = save('a', solved: 10, xp: 900, at: t2);
      expect(dominates(account, guest), isTrue);
      expect(dominates(guest, account), isFalse);
      expect(decide(guest: guest, account: account), MergeDecision.keepAccount);
    });

    test('works in both directions', () {
      final guest = save('g', solved: 12, xp: 1200, at: t2);
      final account = save('a', solved: 4, xp: 300, at: t1);
      expect(dominates(guest, account), isTrue);
      expect(decide(guest: guest, account: account), MergeDecision.keepGuest);
    });

    test('the save that would be dropped holds more Coins: ask instead of dropping them', () {
      final guest = save('g', solved: 5, xp: 400, coins: 3000, at: t1);
      final account = save('a', solved: 10, xp: 900, coins: 200, at: t2);
      expect(dominates(account, guest), isTrue);
      expect(decide(guest: guest, account: account), MergeDecision.ask);
      final more = save('a', solved: 10, xp: 900, tickets: 9, at: t2);
      expect(decide(guest: more, account: save('g', solved: 12, xp: 1200, at: t2.add(const Duration(days: 1)))), MergeDecision.ask, reason: 'Tickets too');
    });

    test('a guest with bought Coins and no pictures is not a save to drop silently', () {
      final guest = save('g', coins: 2500, at: t2);
      expect(guest.isTrivial, isFalse);
      expect(decide(guest: guest, account: save('a', solved: 10, xp: 900, coins: 300, at: t1)), MergeDecision.ask);
    });

    test('more progress but older is not clear: ask', () {
      final guest = save('g', solved: 12, xp: 1200, at: t0);
      final account = save('a', solved: 4, xp: 300, at: t2);
      expect(dominates(guest, account), isFalse);
      expect(dominates(account, guest), isFalse);
      expect(decide(guest: guest, account: account), MergeDecision.ask);
    });

    test('mixed stats (more xp, fewer solved) ask', () {
      final guest = save('g', solved: 3, xp: 2000, at: t2);
      final account = save('a', solved: 9, xp: 500, at: t2);
      expect(decide(guest: guest, account: account), MergeDecision.ask);
    });

    test('identical saves keep the account', () {
      final guest = save('g', solved: 6, xp: 600, at: t1);
      final account = save('a', solved: 6, xp: 600, at: t1);
      expect(decide(guest: guest, account: account), MergeDecision.keepAccount);
    });

    test('a save that was never played counts as oldest', () {
      final guest = save('g', solved: 6, xp: 600, at: t1);
      final account = save('a', solved: 6, xp: 600);
      expect(dominates(guest, account), isTrue);
      expect(dominates(account, guest), isFalse);
    });

    test('last played comes from the newest progress row', () {
      final guest = SaveSnapshot(userId: 'g', profile: const {'xp': 300}, progress: [row('p1', at: t2), row('p2', at: t0)], updatedAt: t1);
      expect(guest.lastPlayed, t2);
    });
  });

  group('trivial saves', () {
    test('a fresh install never asks', () {
      final guest = save('g', solved: 2, xp: 150, at: t2);
      final account = save('a', solved: 4, xp: 300, at: t0);
      expect(guest.isTrivial, isTrue);
      expect(decide(guest: guest, account: account), MergeDecision.keepAccount);
    });

    test('an empty account takes the device save', () {
      final guest = save('g', solved: 4, xp: 300, at: t0);
      final account = save('a', solved: 0, xp: 0, at: t2);
      expect(decide(guest: guest, account: account), MergeDecision.keepGuest);
    });

    test('three solved or 200 xp is no longer trivial', () {
      expect(save('g', solved: 3).isTrivial, isFalse);
      expect(save('g', xp: 200).isTrivial, isFalse);
      expect(save('g', solved: 2, xp: 199).isTrivial, isTrue);
    });

    test('two trivial saves keep the account', () {
      expect(decide(guest: save('g', solved: 1, at: t2), account: save('a', at: t0)), MergeDecision.keepAccount);
    });
  });

  group('union', () {
    test('lists are combined without duplicates, order kept', () {
      expect(unionOf(['a', 'b'], ['b', 'c']), ['a', 'b', 'c']);
      expect(unionOf(null, ['x']), ['x']);
      expect(unionOf(['x'], null), ['x']);
    });

    test('profile patch unions unlocks and takes the longest streak', () {
      final guest = save('g', solved: 4, xp: 300, longestStreak: 9, streak: 2, packs: ['wild', 'sea'], achievements: ['solver:1'], at: t1);
      final account = save('a', solved: 8, xp: 900, longestStreak: 4, streak: 4, packs: ['sea', 'city'], achievements: ['solver:1', 'solver:2'], at: t2);
      final patch = mergeProfile(guest: guest, account: account, choice: MergeChoice.account, mergedProgress: mergeProgress(guest.progress, account.progress).all);
      expect(patch['unlockedPacks'], ['sea', 'city', 'wild']);
      expect(patch['claimedAchievements'], ['solver:1', 'solver:2']);
      expect(patch['longestStreak'], 9);
      expect(patch['streak'], 4);
      expect(patch['coins'], account.coins);
      expect(patch['puzzlesCompleted'], 12);
      expect(patch['totalStars'], 36);
      expect(patch.containsKey('userId'), isFalse);
      expect(patch.containsKey('isVip'), isFalse);
      expect(patch.containsKey('vipExpiresAt'), isFalse);
    });

    test('choosing the device copies its scalars', () {
      final guest = save('g', solved: 4, xp: 300, coins: 1200, streak: 7, longestStreak: 7, name: 'Nia', at: t1);
      final account = save('a', solved: 8, xp: 900, coins: 90, streak: 1, longestStreak: 3, name: 'Old', at: t2);
      final patch = mergeProfile(guest: guest, account: account, choice: MergeChoice.guest, mergedProgress: const {});
      expect(patch['coins'], 1200);
      expect(patch['xp'], 300);
      expect(patch['level'], 4);
      expect(patch['streak'], 7);
      expect(patch['longestStreak'], 7);
      expect(patch['displayName'], 'Nia');
    });
  });

  group('progress', () {
    test('best of both per picture', () {
      final a = row('p', stars: 2, bestMoves: 40, bestSeconds: 90, totalMoves: 100, at: t2, extra: {'moves': 5, 'layout': '1,2,3'});
      final b = row('p', stars: 3, bestMoves: 55, bestSeconds: 60, totalMoves: 140, at: t1, extra: {'moves': 30, 'layout': null});
      final m = mergeProgressRow(a, b);
      expect(m['stars'], 3);
      expect(m['bestMoves'], 40);
      expect(m['bestSeconds'], 60);
      expect(m['totalMoves'], 140);
      expect(m['completed'], isTrue);
      // The newer row keeps its board in progress.
      expect(m['moves'], 5);
      expect(m['layout'], '1,2,3');
      expect(m.containsKey('\$updatedAt'), isFalse);
    });

    test('solved if either side solved it; null records yield to the other side', () {
      final a = row('p', stars: 0, completed: false, bestMoves: null, at: t2);
      final b = row('p', stars: 1, completed: true, bestMoves: 70, at: t0);
      final m = mergeProgressRow(a, b);
      expect(m['completed'], isTrue);
      expect(m['stars'], 1);
      expect(m['bestMoves'], 70);
    });

    test('only pictures the guest touched are written', () {
      final guest = [row('shared', stars: 1, at: t2), row('guestOnly', stars: 2, at: t2)];
      final account = [row('shared', stars: 3, at: t1), row('accountOnly', stars: 3, at: t1)];
      final m = mergeProgress(guest, account);
      expect(m.all.keys, containsAll(['shared', 'guestOnly', 'accountOnly']));
      expect(m.changed.keys, unorderedEquals(['shared', 'guestOnly']));
      expect(m.all['shared']!['stars'], 3);
    });
  });

  test('snapshot survives a JSON round trip', () {
    final s = save('g', solved: 2, xp: 50, packs: ['wild'], at: t1);
    final back = SaveSnapshot.fromJson(s.toJson());
    expect(back.userId, 'g');
    expect(back.solved, 2);
    expect(back.xp, 50);
    expect(back.updatedAt, t1);
    expect(back.profile['unlockedPacks'], ['wild']);
  });

  test('relative time reads naturally', () {
    final now = DateTime.utc(2026, 10, 11, 12);
    expect(relativeTime(null, now: now), 'never');
    expect(relativeTime(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
    expect(relativeTime(now.subtract(const Duration(minutes: 5)), now: now), '5 min ago');
    expect(relativeTime(now.subtract(const Duration(hours: 3)), now: now), '3 hours ago');
    expect(relativeTime(now.subtract(const Duration(hours: 30)), now: now), 'yesterday');
    expect(relativeTime(now.subtract(const Duration(days: 5)), now: now), '5 days ago');
    expect(relativeTime(now.subtract(const Duration(days: 21)), now: now), '3 weeks ago');
    expect(relativeTime(now.subtract(const Duration(days: 100)), now: now), '3 months ago');
  });
}
