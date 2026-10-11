import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/guest_names.dart';
import '../data/repositories.dart';
import '../game/modes.dart';
import '../models/models.dart';
import 'auth.dart';
import 'rewards.dart';
import 'settings.dart';

/// Economy rules in one place so UI and backend stay consistent.
class Economy {
  static const hintCostCoins = 60;
  static const magicLockCostCoins = 120;
  static const peekCostCoins = 30;
  static const piggyOpenTickets = 1;
  static const wheelSpinTickets = 1;

  /// Early unlock of a board tier that is still above the player's level.
  static int tierUnlockCoins(int tierIndex) => 600 + 300 * tierIndex;

  /// Restoring a lost streak to the player's longest.
  static int streakRestoreTickets(int longest) => (3 + longest ~/ 7).clamp(3, 10);

  static const avatarCoins = 900;

  /// Piggy bank: +5 coins per solved picture, holds up to [piggyCapacity].
  static const piggyPerPuzzle = 5;
  static const piggyCapacity = Profile.piggyCapacity;
  static const adRewardCoins = 40;

  static const dailyRewards = <({int coins, int tickets, int hints})>[
    (coins: 50, tickets: 0, hints: 0),
    (coins: 75, tickets: 0, hints: 1),
    (coins: 100, tickets: 1, hints: 0),
    (coins: 125, tickets: 0, hints: 1),
    (coins: 150, tickets: 1, hints: 0),
    (coins: 200, tickets: 1, hints: 1),
    (coins: 400, tickets: 2, hints: 2),
  ];

  /// Coins awarded for finishing a board of [cells] cards with [stars].
  /// Harder tilings multiply the payout.
  static int completionCoins(int cells, int stars, {GameMode mode = GameMode.cards}) {
    final base = (cells * 3.2).round();
    return ((base + (stars - 1) * (base ~/ 3)) * mode.multiplier).round();
  }

  static int completionXp(int cells, int stars, {GameMode mode = GameMode.cards}) =>
      (((cells * 2.5).round() + stars * 10) * mode.multiplier).round();
}

class ProfileNotifier extends AsyncNotifier<Profile> {
  @override
  Future<Profile> build() async {
    final auth = await ref.watch(authProvider.future);
    final store = ref.read(localStoreProvider);
    if (auth == null) {
      // Offline guest: restore cached profile.
      final cached = store.getJson('profile');
      return cached != null ? Profile.fromRow(cached['id'] ?? 'local', cached) : Profile.guest('local');
    }
    final repo = ref.read(profileRepositoryProvider);
    try {
      final p = await repo.fetchOrCreate(auth.$id, name: auth.name.isNotEmpty ? auth.name : GuestNames.next());
      _cache(p);
      return p;
    } catch (e) {
      debugPrint('profile load failed: $e');
      final cached = store.getJson('profile');
      return cached != null ? Profile.fromRow(cached['id'] ?? auth.$id, cached) : Profile.guest(auth.$id);
    }
  }

  void _cache(Profile p) {
    ref.read(localStoreProvider).setJson('profile', {...p.toData(), 'id': p.id});
  }

  Profile get _p => state.value ?? Profile.guest('local');

  /// Applies an optimistic patch locally and persists it in the background.
  /// Any change to `xp` also rewrites the mirrored `level` column, derived
  /// with [LevelRewards.levelForXp], so other players read the same level.
  Future<void> _apply(Map<String, dynamic> patch) async {
    if (patch.containsKey('xp')) patch = {...patch, 'level': LevelRewards.levelForXp((patch['xp'] as num?)?.toInt() ?? 0)};
    final current = _p;
    final merged = {...current.toData(), ...patch};
    final next = Profile.fromRow(current.id, merged);
    state = AsyncData(next);
    _cache(next);
    if (current.id == 'local') return;
    try {
      await ref.read(profileRepositoryProvider).update(current.id, patch);
    } catch (e) {
      debugPrint('profile patch failed: $e');
    }
  }

  void _ledger(int amount, String currency, String reason, int balanceAfter) {
    final p = _p;
    if (p.id == 'local') return;
    ref.read(profileRepositoryProvider).logLedger(p.id, amount: amount, currency: currency, reason: reason, balanceAfter: balanceAfter);
  }

  Future<void> addCoins(int amount, {required String reason}) async {
    final next = _p.coins + amount;
    await _apply({'coins': next});
    _ledger(amount, 'coins', reason, next);
  }

  Future<bool> spendCoins(int amount, {required String reason}) async {
    if (_p.coins < amount) return false;
    final next = _p.coins - amount;
    await _apply({'coins': next});
    _ledger(-amount, 'coins', reason, next);
    return true;
  }

  Future<void> addTickets(int amount, {required String reason}) async {
    final next = _p.tickets + amount;
    await _apply({'tickets': next});
    _ledger(amount, 'tickets', reason, next);
  }

  Future<bool> spendTickets(int amount, {required String reason}) async {
    if (_p.tickets < amount) return false;
    final next = _p.tickets - amount;
    await _apply({'tickets': next});
    _ledger(-amount, 'tickets', reason, next);
    return true;
  }

  Future<void> addHints(int amount, {required String reason}) async {
    final next = _p.hints + amount;
    await _apply({'hints': next});
    _ledger(amount, 'hints', reason, next);
  }

  /// Uses a hint from inventory, or buys one with coins. Returns false if neither is possible.
  Future<bool> useHint() async {
    if (_p.hints > 0) {
      await _apply({'hints': _p.hints - 1});
      return true;
    }
    return spendCoins(Economy.hintCostCoins, reason: 'hint');
  }

  Future<void> setIdentity({String? name, String? avatar}) =>
      _apply({'displayName': ?name, 'avatar': ?avatar});

  Future<bool> unlockPack(Pack pack) async {
    if (_p.unlockedPacks.contains(pack.id)) return true;
    if (pack.priceTickets > 0) {
      if (_p.tickets < pack.priceTickets) return false;
      final next = _p.tickets - pack.priceTickets;
      await _apply({'tickets': next, 'unlockedPacks': [..._p.unlockedPacks, pack.id]});
      _ledger(-pack.priceTickets, 'tickets', 'unlock:${pack.id}', next);
      return true;
    }
    if (_p.coins < pack.priceCoins) return false;
    final next = _p.coins - pack.priceCoins;
    await _apply({'coins': next, 'unlockedPacks': [..._p.unlockedPacks, pack.id]});
    _ledger(-pack.priceCoins, 'coins', 'unlock:${pack.id}', next);
    return true;
  }

  /// Playable right now: event packs must be live; otherwise VIP, the current
  /// daily month, free packs and purchased packs are open.
  bool isUnlocked(Pack pack) {
    if (pack.hasWindow && !pack.isLive) return false;
    return _p.isVip || pack.isCurrentMonth || pack.isFree || (pack.priceCoins == 0 && pack.priceTickets == 0) || _p.unlockedPacks.contains(pack.id);
  }

  /// Debug-only sandbox toggle. Real VIP comes from verified App Store
  /// subscriptions (`vipExpiresAt`), applied by the verify-purchase function.
  Future<void> setVip(bool vip) => _apply({'isVip': vip});

  /// Records a rewarded video. Returns false when today's allowance is used up.
  Future<bool> consumeAd() async {
    final p = _p;
    if (p.adsLeftToday <= 0) return false;
    final now = DateTime.now();
    final sameDay = p.adsDate != null && p.adsDate!.year == now.year && p.adsDate!.month == now.month && p.adsDate!.day == now.day;
    await _apply({'adsToday': (sameDay ? p.adsToday : 0) + 1, 'adsDate': now.toUtc().toIso8601String()});
    return true;
  }

  /// Claims a finished goal once; rewards are credited immediately.
  Future<bool> claimGoal(Goal goal) async {
    final p = _p;
    if (!goal.done || p.claimedGoals.contains(goal.key)) return false;
    if (goal.vipOnly && !p.isVip) return false;
    final claimed = [...p.claimedGoals, goal.key];
    // Keep the list short: drop keys older than ~3 weeks by trimming length.
    final trimmed = claimed.length > 60 ? claimed.sublist(claimed.length - 60) : claimed;
    await _apply({'claimedGoals': trimmed, if (goal.coins > 0) 'coins': p.coins + goal.coins, if (goal.tickets > 0) 'tickets': p.tickets + goal.tickets});
    if (goal.coins > 0) _ledger(goal.coins, 'coins', 'goal:${goal.key}', p.coins + goal.coins);
    if (goal.tickets > 0) _ledger(goal.tickets, 'tickets', 'goal:${goal.key}', p.tickets + goal.tickets);
    return true;
  }

  /// Daily reward: streak day index (0-6) determines the reward.
  Future<({int coins, int tickets, int hints, int day})?> claimDaily() async {
    final p = _p;
    if (!p.dailyAvailable) return null;
    final now = DateTime.now();
    final last = p.lastDailyClaim;
    final consecutive = last != null && now.difference(DateTime(last.year, last.month, last.day)).inDays == 1;
    final streak = consecutive ? p.streak + 1 : 1;
    final day = (streak - 1) % 7;
    final r = Economy.dailyRewards[day];
    await _apply({
      'coins': p.coins + r.coins,
      'tickets': p.tickets + r.tickets,
      'hints': p.hints + r.hints,
      'streak': streak,
      'longestStreak': max(p.longestStreak, streak),
      'lastDailyClaim': now.toUtc().toIso8601String(),
    });
    _ledger(r.coins, 'coins', 'daily:day${day + 1}', p.coins + r.coins);
    return (coins: r.coins, tickets: r.tickets, hints: r.hints, day: day);
  }

  /// A broken streak can be restored to the player's longest, for tickets.
  bool get canRestoreStreak {
    final p = _p;
    if (p.longestStreak <= p.streak || p.longestStreak < 3) return false;
    final last = p.lastStreakRestore;
    return last == null || DateTime.now().difference(last).inDays >= 1;
  }

  Future<bool> restoreStreak() async {
    final p = _p;
    if (!canRestoreStreak) return false;
    final cost = Economy.streakRestoreTickets(p.longestStreak);
    if (p.tickets < cost) return false;
    await _apply({'tickets': p.tickets - cost, 'streak': p.longestStreak, 'lastStreakRestore': DateTime.now().toUtc().toIso8601String()});
    _ledger(-cost, 'tickets', 'streak-restore', p.tickets - cost);
    return true;
  }

  /// Early unlock of a board tier (`<mode>:<index>`).
  bool hasTier(GameMode mode, int tierIndex) => _p.unlockedTiers.contains('${mode.code}:$tierIndex');

  Future<bool> unlockTier(GameMode mode, int tierIndex) async {
    final p = _p;
    final key = '${mode.code}:$tierIndex';
    if (p.unlockedTiers.contains(key)) return true;
    final cost = Economy.tierUnlockCoins(tierIndex);
    if (p.coins < cost) return false;
    await _apply({'coins': p.coins - cost, 'unlockedTiers': [...p.unlockedTiers, key]});
    _ledger(-cost, 'coins', 'tier:$key', p.coins - cost);
    return true;
  }

  Future<bool> unlockAvatar(String key, {int cost = Economy.avatarCoins}) async {
    final p = _p;
    if (p.unlockedAvatars.contains(key)) return true;
    if (p.coins < cost) return false;
    await _apply({'coins': p.coins - cost, 'unlockedAvatars': [...p.unlockedAvatars, key]});
    _ledger(-cost, 'coins', 'avatar:$key', p.coins - cost);
    return true;
  }

  /// Grants an avatar for free (achievement reward).
  Future<void> grantAvatar(String key) async {
    final p = _p;
    if (p.unlockedAvatars.contains(key)) return;
    await _apply({'unlockedAvatars': [...p.unlockedAvatars, key]});
  }

  Future<bool> claimAchievement(String stepKey, {int coins = 0, int tickets = 0, String? avatar}) async {
    final p = _p;
    if (p.claimedAchievements.contains(stepKey)) return false;
    final avatars = avatar != null && !p.unlockedAvatars.contains(avatar) ? [...p.unlockedAvatars, avatar] : p.unlockedAvatars;
    await _apply({
      'claimedAchievements': [...p.claimedAchievements, stepKey],
      if (coins > 0) 'coins': p.coins + coins,
      if (tickets > 0) 'tickets': p.tickets + tickets,
      'unlockedAvatars': avatars,
    });
    if (coins > 0) _ledger(coins, 'coins', 'achievement:$stepKey', p.coins + coins);
    if (tickets > 0) _ledger(tickets, 'tickets', 'achievement:$stepKey', p.tickets + tickets);
    return true;
  }

  Future<void> markWheelSpun() => _apply({'lastWheelSpin': DateTime.now().toUtc().toIso8601String()});

  Future<bool> openPiggy() async {
    final p = _p;
    if (p.tickets < Economy.piggyOpenTickets || p.piggyCoins <= 0) return false;
    final coins = p.coins + p.piggyCoins;
    await _apply({'coins': coins, 'tickets': p.tickets - Economy.piggyOpenTickets, 'piggyCoins': 0});
    _ledger(p.piggyCoins, 'coins', 'piggy', coins);
    return true;
  }

  /// Called when a puzzle is completed; returns the rewards granted. [moves]
  /// and [seconds] are the finishing session's numbers, added to the public
  /// aggregates on the profile row.
  Future<({int coins, int xp, bool levelUp, int level})> recordCompletion({
    required int cells,
    required int stars,
    required bool firstTime,
    GameMode mode = GameMode.cards,
    int moves = 0,
    int seconds = 0,
  }) async {
    final p = _p;
    var coins = Economy.completionCoins(cells, stars, mode: mode);
    final xpGain = Economy.completionXp(cells, stars, mode: mode);
    if (!firstTime) coins = (coins * 0.4).round();
    final xp = p.xp + xpGain;
    final level = LevelRewards.levelForXp(xp);
    final levelUp = level > p.level;
    var levelBonus = 0, levelTickets = 0, levelHints = 0;
    for (var l = p.level + 1; l <= level; l++) {
      final r = LevelRewards.forLevel(l);
      levelBonus += r.coins;
      levelTickets += r.tickets;
      levelHints += r.hints;
    }
    final total = p.coins + coins + levelBonus;
    await _apply({
      'coins': total,
      'xp': xp,
      'level': level,
      'piggyCoins': min(Profile.piggyCapacity, p.piggyCoins + Economy.piggyPerPuzzle),
      'puzzlesCompleted': p.puzzlesCompleted + (firstTime ? 1 : 0),
      'totalStars': p.totalStars + (firstTime ? stars : 0),
      'totalMoves': p.totalMoves + max(0, moves),
      'totalSeconds': p.totalSeconds + max(0, seconds),
      'solvedByMode': jsonEncode({...p.solvedByMode, mode.code: (p.solvedByMode[mode.code] ?? 0) + 1}),
      if (levelTickets > 0) 'tickets': p.tickets + levelTickets,
      if (levelHints > 0) 'hints': p.hints + levelHints,
    });
    _ledger(coins + levelBonus, 'coins', 'complete', total);
    return (coins: coins + levelBonus, xp: xpGain, levelUp: levelUp, level: level);
  }

  Future<void> refresh() async {
    final p = _p;
    if (p.id == 'local') return;
    try {
      final fresh = await ref.read(profileRepositoryProvider).fetch(p.id);
      if (fresh != null) {
        state = AsyncData(fresh);
        _cache(fresh);
      }
    } catch (_) {}
  }
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, Profile>(ProfileNotifier.new);
