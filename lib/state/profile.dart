import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/name_filter.dart';
import '../data/repositories.dart';
import '../data/sync/ops.dart';
import '../game/modes.dart';
import '../models/models.dart';
import 'auth.dart';
import 'completion.dart';
import 'progress.dart';
import 'rewards.dart';
import 'starter_packs.dart';
import 'sync.dart';

/// Economy rules in one place so UI and backend stay consistent.
class Economy {
  static const hintCostCoins = 150;
  static const magicLockCostCoins = 300;
  static const peekCostCoins = 10;
  static const piggyOpenTickets = 1;
  static const wheelSpinTickets = 1;

  /// The Lucky Wheel's ×5 spin (owner, 2026-10-17): five times the tickets for one spin with the same
  /// odds, paying the prize it lands on five times (the 1,000-coin jackpot pays 5,000).
  static const wheelBigSpin = 5;

  /// Early unlock of a board tier that is still above the player's level.
  static int tierUnlockCoins(int tierIndex) => 600 + 300 * tierIndex;

  /// Opening giant boards before their level ([Unlock.giant], level 10) costs one ticket for every
  /// level still to go, on top of the Giant pack's own price (owner, 2026-10-15): a level 7 player
  /// opens a 12-ticket Giant pack now for 12 + 3. Paid once; giant boards then stay open.
  static const giantEarlyTicketsPerLevel = 1;

  /// Tickets that open giant boards now for a player at [level] (0 from level 10).
  static int giantEarlyFee(int level) => max(0, Unlock.giant.level - level) * giantEarlyTicketsPerLevel;

  /// Restoring a lost streak of [lost] days with the next daily gift.
  static int streakRestoreTickets(int lost) => (3 + lost ~/ 7).clamp(3, 10);

  /// A lost streak can be restored while at most this many days were missed.
  static const streakRestoreMissedDays = 2;

  static const avatarCoins = 900;

  /// Photos a free player can keep in My Puzzles at once (deleting one frees a place); VIP has no
  /// limit ("Unlimited My Puzzles uploads").
  static const freeMyPuzzles = 5;

  /// Piggy bank: +5 coins per solved picture, up to the player's [Profile.piggyCapacity] (500, and
  /// [Profile.piggyStep] more for each upgrade).
  static const piggyPerPuzzle = 5;

  /// One piggy bank upgrade (owner, 2026-10-17: a coin sink): five of them take it from 500 to
  /// 1,000 for 25,000 coins.
  static const piggyUpgradeCoins = 5000;
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

  /// Coins per card for a finished board (3.2 until 2026-10-13; the owner found it too generous).
  static const coinsPerCard = 1.2;

  /// Share of the coins paid again when a solved picture is replayed (0.4 until 2026-10-13).
  static const replayCoinShare = 0.25;

  /// Painting (cards in black and white until they lock) pays this much more coins and XP, on top
  /// of the mode's multiplier.
  static const paintingMultiplier = 1.25;

  /// Coins awarded for finishing a board of [cells] cards with [stars].
  /// Harder tilings multiply the payout, and so does [painting].
  static int completionCoins(int cells, int stars, {GameMode mode = GameMode.cards, bool painting = false}) {
    final base = (cells * coinsPerCard).round();
    return ((base + (stars - 1) * (base ~/ 3)) * mode.multiplier * (painting ? paintingMultiplier : 1)).round();
  }

  static int completionXp(int cells, int stars, {GameMode mode = GameMode.cards, bool painting = false}) =>
      (((cells * 2.5).round() + stars * 10) * mode.multiplier * (painting ? paintingMultiplier : 1)).round();
}

/// The player's profile. Every change is queued as a [SyncOp] ([SyncController]): the screen shows
/// it at once and the server applies it on top of whatever the player's other devices did.
class ProfileNotifier extends AsyncNotifier<Profile> {
  @override
  Future<Profile> build() async {
    // The public completion numbers follow the player's own progress (see [syncCompletion]).
    ref.listen(completionTotalsProvider, (_, t) => syncCompletion(t));
    final auth = await ref.watch(authProvider.future);
    final sync = ref.read(syncProvider.notifier);
    await sync.attach(auth);
    final id = auth?.$id ?? SyncController.local;
    ref.listen(syncProvider.select((s) => s.profile), (_, p) {
      if (p != null && p.id == id) state = AsyncData(p);
    });
    // Once the state is set: bring older rows up to date (completion numbers, quest count).
    Future(_selfHeal);
    final p = ref.read(syncProvider).profile;
    return p != null && p.id == id ? p : Profile.guest(id);
  }

  SyncController get _sync => ref.read(syncProvider.notifier);

  Profile get _p => state.value ?? Profile.guest(SyncController.local);

  void _do(SyncOp op) => _sync.enqueue(op);

  Future<void> addCoins(int amount, {required String reason}) async => _do(SyncOp.earn('coins', amount, reason));

  Future<bool> spendCoins(int amount, {required String reason}) async {
    if (_p.coins < amount) return false;
    _do(SyncOp.spend('coins', amount, reason));
    return true;
  }

  Future<void> addTickets(int amount, {required String reason}) async => _do(SyncOp.earn('tickets', amount, reason));

  Future<bool> spendTickets(int amount, {required String reason}) async {
    if (_p.tickets < amount) return false;
    _do(SyncOp.spend('tickets', amount, reason));
    return true;
  }

  Future<void> addHints(int amount, {required String reason}) async => _do(SyncOp.earn('hints', amount, reason));

  /// Uses a hint from inventory, or buys one with coins. Returns false if neither is possible.
  Future<bool> useHint() async {
    if (_p.hints > 0) {
      _do(SyncOp.spend('hints', 1, 'hint', log: false));
      return true;
    }
    return spendCoins(Economy.hintCostCoins, reason: 'hint');
  }

  Future<void> addPeeks(int amount, {required String reason}) async => _do(SyncOp.earn('peeks', amount, reason));

  Future<void> addMagics(int amount, {required String reason}) async => _do(SyncOp.earn('magics', amount, reason));

  /// Uses a Peek from stock, or pays [Economy.peekCostCoins]. False if neither is possible.
  Future<bool> usePeek() async {
    if (_p.peeks > 0) {
      _do(SyncOp.spend('peeks', 1, 'peek', log: false));
      return true;
    }
    return spendCoins(Economy.peekCostCoins, reason: 'peek');
  }

  /// Uses a Magic from stock, or pays [Economy.magicLockCostCoins]. False if neither is possible.
  Future<bool> useMagic() async {
    if (_p.magics > 0) {
      _do(SyncOp.spend('magics', 1, 'magic-lock', log: false));
      return true;
    }
    return spendCoins(Economy.magicLockCostCoins, reason: 'magic-lock');
  }

  /// An offensive [name] is not saved (the name alert says so before it gets here).
  Future<void> setIdentity({String? name, String? avatar}) async {
    if (name != null && NameFilter.isOffensive(name)) name = null;
    if (name == null && avatar == null) return;
    _do(SyncOp.put({'displayName': ?name, 'avatar': ?avatar}));
  }

  Future<bool> unlockPack(Pack pack) async {
    if (_p.unlockedPacks.contains(pack.id)) return true;
    final tickets = pack.priceTickets > 0;
    final price = tickets ? pack.priceTickets : pack.priceCoins;
    if ((tickets ? _p.tickets : _p.coins) < price) return false;
    _do(SyncOp.unlock(list: 'unlockedPacks', key: pack.id, currency: tickets ? 'tickets' : 'coins', price: price, reason: 'unlock:${pack.id}'));
    return true;
  }

  /// Tickets [openGiantEarly] takes for [pack] now: [Economy.giantEarlyFee], plus the pack's ticket
  /// price unless the player already has the pack (bought, VIP, free). A pack priced in coins
  /// keeps its coin price for later (its access card): only the fee is paid here.
  int giantEarlyPrice(Pack pack) => _giantFeeNow() + (isUnlocked(pack) ? 0 : pack.priceTickets);

  /// The early fee still to pay: none once giant boards were opened early.
  int _giantFeeNow() => _p.unlockedTiers.contains(Unlocks.earlyKey(Unlock.giant)) ? 0 : Economy.giantEarlyFee(_p.level);

  /// Opens giant boards before their level and, unless the player has it, buys the Giant [pack],
  /// in one payment of [giantEarlyPrice] tickets. Two ops, each applied exactly once: the pack
  /// first (`unlockedPacks`), then the early opening ([Unlocks.earlyKey] in `unlockedTiers`, which
  /// [openFeaturesProvider] reads). Spent elsewhere meanwhile, the server skips what no longer
  /// fits and the pack page offers the rest. False when the tickets are short.
  Future<bool> openGiantEarly(Pack pack) async {
    final fee = _giantFeeNow();
    final packTickets = isUnlocked(pack) ? 0 : pack.priceTickets;
    if (_p.tickets < fee + packTickets) return false;
    if (packTickets > 0) {
      _do(SyncOp.unlock(list: 'unlockedPacks', key: pack.id, currency: 'tickets', price: packTickets, reason: 'unlock:${pack.id}'));
    }
    if (fee > 0) {
      final key = Unlocks.earlyKey(Unlock.giant);
      _do(SyncOp.unlock(list: 'unlockedTiers', key: key, currency: 'tickets', price: fee, reason: key));
    }
    return true;
  }

  /// Playable right now: event packs must be live; otherwise VIP, the current
  /// daily month, free packs, purchased packs, and the packs that were free until
  /// 2026-10-14 for a player who had played them ([keptFreePack]) are open.
  bool isUnlocked(Pack pack) {
    if (pack.hasWindow && !pack.isLive) return false;
    return _p.isVip ||
        pack.isCurrentMonth ||
        pack.isFree ||
        (pack.priceCoins == 0 && pack.priceTickets == 0) ||
        _p.unlockedPacks.contains(pack.id) ||
        keptFreePack(pack.id, () => ref.read(playedPacksProvider));
  }

  /// Debug-only sandbox toggle. Real VIP comes from verified App Store
  /// subscriptions (`vipExpiresAt`), applied by the server's purchase checks (docs/purchases.md).
  Future<void> setVip(bool vip) async => _do(SyncOp.put({'isVip': vip}));

  /// Records a rewarded video. Returns false when today's allowance is used up.
  Future<bool> consumeAd() async {
    if (_p.adsLeftToday <= 0) return false;
    _do(SyncOp.ad());
    return true;
  }

  /// Claims a finished goal once; rewards are credited immediately and the quest counts towards
  /// the public "Quests completed" number. A quest claimed on another device first pays nothing.
  Future<bool> claimGoal(Goal goal) async {
    final p = _p;
    if (!goal.done || p.claimedGoals.contains(goal.key)) return false;
    if (goal.vipOnly && !p.isVip) return false;
    _do(SyncOp.quest(goal.key, coins: goal.coins, tickets: goal.tickets));
    return true;
  }

  /// Swaps a quest that is not finished or claimed for [Goal.swap]'s quest, for [QuestSwap.tickets]
  /// ticket. Only that quest changes; a swap made on another device first (or a claim there) charges
  /// nothing. False when there is nothing to swap or the tickets are short.
  Future<bool> swapQuest(Goal goal) async {
    final p = _p;
    final s = goal.swap;
    if (s == null || goal.done || p.claimedGoals.contains(goal.key)) return false;
    if (goal.vipOnly && !p.isVip) return false;
    if (p.tickets < QuestSwap.tickets) return false;
    _do(SyncOp.questSwap(slot: s.slot, base: s.base, kind: s.next, swaps: s.count, tickets: QuestSwap.tickets, fixedKey: s.fixedKey));
    return true;
  }

  /// Pays the VIP weekly bonus once per week; returns the coins paid (0 when
  /// the player is not VIP or already got this week's bonus).
  Future<int> claimVipWeeklyBonus() async {
    final p = _p;
    if (!p.isVip || p.id == SyncController.local) return 0;
    final key = Goals.vipBonusKey(DateTime.now());
    if (p.claimedGoals.contains(key)) return 0;
    const bonus = Goals.vipWeeklyBonus;
    _do(SyncOp.vipBonus(key, bonus));
    return bonus;
  }

  /// Daily reward: streak day index (0-6) determines the reward. With [restore] (see
  /// [canRestoreStreak]) the lost streak is restored for tickets and today's gift continues it.
  Future<({int coins, int tickets, int hints, int day})?> claimDaily({bool restore = false}) async {
    final p = _p;
    if (!p.dailyAvailable) return null;
    final now = DateTime.now();
    final last = p.lastDailyClaim;
    final consecutive = last != null && now.difference(DateTime(last.year, last.month, last.day)).inDays == 1;
    final restoring = restore && !consecutive && canRestoreStreak;
    final cost = restoring ? Economy.streakRestoreTickets(p.streak) : 0;
    if (restoring && p.tickets < cost) return null;
    final streak = consecutive || restoring ? p.streak + 1 : 1;
    final day = (streak - 1) % 7;
    final r = Economy.dailyRewards[day];
    _do(SyncOp.daily(day: day, coins: r.coins, tickets: r.tickets, hints: r.hints, restoreTarget: restoring ? p.streak : 0, restoreCost: cost));
    return (coins: r.coins, tickets: r.tickets, hints: r.hints, day: day);
  }

  /// A streak of 3 days or more that was lost to missed days can be restored with the next claim,
  /// for tickets ([Economy.streakRestoreTickets] of the lost streak): today's gift then continues
  /// it instead of starting again at day 1. Offered while at most [Economy.streakRestoreMissedDays]
  /// days were missed, once a day. A running streak shorter than the longest is not a lost one.
  bool get canRestoreStreak {
    final p = _p;
    final since = p.daysSinceDailyClaim;
    if (since == null || p.streakAlive || since > Economy.streakRestoreMissedDays + 1 || p.streak < 3) return false;
    final last = p.lastStreakRestore;
    return last == null || DateTime.now().difference(last).inDays >= 1;
  }

  /// Early unlock of a board tier (`<mode>:<index>`).
  bool hasTier(GameMode mode, int tierIndex) => _p.unlockedTiers.contains('${mode.code}:$tierIndex');

  Future<bool> unlockTier(GameMode mode, int tierIndex) async {
    final key = '${mode.code}:$tierIndex';
    if (_p.unlockedTiers.contains(key)) return true;
    final cost = Economy.tierUnlockCoins(tierIndex);
    if (_p.coins < cost) return false;
    _do(SyncOp.unlock(list: 'unlockedTiers', key: key, price: cost, reason: 'tier:$key'));
    return true;
  }

  Future<bool> unlockAvatar(String key, {int cost = Economy.avatarCoins}) async {
    if (_p.unlockedAvatars.contains(key)) return true;
    if (_p.coins < cost) return false;
    _do(SyncOp.unlock(list: 'unlockedAvatars', key: key, price: cost, reason: 'avatar:$key'));
    return true;
  }

  /// Grants an avatar for free (achievement reward).
  Future<void> grantAvatar(String key) async {
    if (_p.unlockedAvatars.contains(key)) return;
    _do(SyncOp.unlock(list: 'unlockedAvatars', key: key));
  }

  Future<bool> claimAchievement(String stepKey, {int coins = 0, int tickets = 0, String? avatar}) async {
    if (_p.claimedAchievements.contains(stepKey)) return false;
    _do(SyncOp.achievement(stepKey, coins: coins, tickets: tickets, avatar: avatar));
    return true;
  }

  /// Social > Inbox: a message opened, deleted or its reward claimed (lib/state/inbox.dart). The
  /// state lives in `profiles.inbox`, so it follows the player to every device; a reward is paid
  /// once per message.
  void markMessageSeen(String id) {
    if (!_p.inbox.contains('seen:$id')) _do(SyncOp.inbox(id, 'seen'));
  }

  void deleteMessage(String id) {
    if (!_p.inbox.contains('deleted:$id')) _do(SyncOp.inbox(id, 'deleted'));
  }

  bool claimMessage(String id, {int coins = 0, int tickets = 0, int hints = 0, int peeks = 0, int magics = 0}) {
    if (_p.inbox.contains('claimed:$id')) return false;
    _do(SyncOp.inbox(id, 'claimed', coins: coins, tickets: tickets, hints: hints, peeks: peeks, magics: magics));
    return true;
  }

  Future<void> markWheelSpun() async => _do(SyncOp.put({'lastWheelSpin': DateTime.now().toUtc().toIso8601String()}));

  Future<bool> openPiggy() async {
    final p = _p;
    if (p.tickets < Economy.piggyOpenTickets || p.piggyCoins <= 0) return false;
    _do(SyncOp.piggy(amount: p.piggyCoins, tickets: Economy.piggyOpenTickets));
    return true;
  }

  /// Makes the piggy bank hold [Profile.piggyStep] coins more, for [Economy.piggyUpgradeCoins]. False
  /// at the largest size or when the coins are short. Upgraded on another device meanwhile, the server
  /// charges nothing (the op names the level it raises to).
  Future<bool> upgradePiggy() async {
    final p = _p;
    if (p.piggyLevel >= Profile.maxPiggyLevel || p.coins < Economy.piggyUpgradeCoins) return false;
    _do(SyncOp.piggyUpgrade(level: p.piggyLevel + 1, price: Economy.piggyUpgradeCoins));
    return true;
  }

  /// Called when a puzzle is completed; returns the rewards granted. [moves]
  /// and [seconds] are the finishing session's numbers, added to the public
  /// aggregates on the profile row. [dailyBonus] is paid on top for a first
  /// solve of the daily puzzle. Level rewards follow the server's XP, so a
  /// level reached on two devices pays once.
  Future<({int coins, int xp, bool levelUp, int level})> recordCompletion({
    required String puzzleId,
    required int cells,
    required int stars,
    required bool firstTime,
    GameMode mode = GameMode.cards,
    bool painting = false,
    int moves = 0,
    int seconds = 0,
    int dailyBonus = 0,
  }) async {
    final p = _p;
    final full = Economy.completionCoins(cells, stars, mode: mode, painting: painting);
    final replay = (full * Economy.replayCoinShare).round();
    final xpGain = Economy.completionXp(cells, stars, mode: mode, painting: painting);
    final level = LevelRewards.levelForXp(p.xp + xpGain);
    var levelBonus = 0;
    for (var l = p.level + 1; l <= level; l++) {
      levelBonus += LevelRewards.forLevel(l).coins;
    }
    _do(SyncOp.solve(
      puzzleId: puzzleId,
      first: firstTime,
      coins: full + dailyBonus,
      replayCoins: replay,
      xp: xpGain,
      stars: stars,
      mode: mode.code,
      moves: max(0, moves),
      seconds: max(0, seconds),
      piggy: Economy.piggyPerPuzzle,
    ));
    return (coins: (firstTime ? full + dailyBonus : replay) + levelBonus, xp: xpGain, levelUp: level > p.level, level: level);
  }

  /// A guest's rewards for a shared board (Play together): what the board would pay as the guest's
  /// own ([firstTime]: the guest has not solved the picture before), coins, XP, piggy bank and
  /// level, and nothing else (no progress row, no solve totals, no quests or achievements).
  Future<({int coins, int xp, bool levelUp, int level})> recordCoopReward({
    required String gameId,
    required int board,
    required int cells,
    required int stars,
    required bool firstTime,
    GameMode mode = GameMode.cards,
    bool painting = false,
  }) async {
    final p = _p;
    final full = Economy.completionCoins(cells, stars, mode: mode, painting: painting);
    final coins = firstTime ? full : (full * Economy.replayCoinShare).round();
    final xpGain = Economy.completionXp(cells, stars, mode: mode, painting: painting);
    final level = LevelRewards.levelForXp(p.xp + xpGain);
    var levelBonus = 0;
    for (var l = p.level + 1; l <= level; l++) {
      levelBonus += LevelRewards.forLevel(l).coins;
    }
    _do(SyncOp.coopReward(gameId: gameId, board: board, coins: coins, xp: xpGain, piggy: Economy.piggyPerPuzzle));
    return (coins: coins + levelBonus, xp: xpGain, levelUp: level > p.level, level: level);
  }

  /// Writes the public "Total Completion" numbers ([Profile.picturesSolved] and the rest) when
  /// the player's own progress says something else: after a solve or a better score, when the
  /// catalogue changes, and on start for rows written by older versions. Skipped while progress
  /// (re)loads or belongs to another player (a sign-in in flight).
  Future<void> syncCompletion(CompletionTotals? t) async {
    if (t == null || !ref.mounted) return;
    final p = state.value;
    if (p == null || p.id == SyncController.local || state.isLoading || ref.read(progressProvider).isLoading) return;
    if (t.ownerId != null && t.ownerId != p.id) return;
    final current = p.toData();
    final patch = {for (final e in t.publicFields.entries) if (current[e.key] != e.value) e.key: e.value};
    if (patch.isNotEmpty) _do(SyncOp.put(patch));
  }

  /// Start-up repairs for rows from older versions: the completion numbers, and the quest count
  /// from the ledger (quests claimed before the count existed, or a write that failed).
  Future<void> _selfHeal() async {
    if (!ref.mounted) return;
    await syncCompletion(ref.read(completionTotalsProvider));
    final p = state.value;
    if (p == null || p.id == SyncController.local || !ref.mounted) return;
    try {
      final claims = await ref.read(profileRepositoryProvider).questClaims(p.id);
      if (ref.mounted && claims > _p.questsCompleted && _p.id == p.id) _do(SyncOp.questCount(claims));
    } catch (e) {
      debugPrint('quest count failed: $e');
    }
  }

  /// Reads the save from the server again (pull to refresh).
  Future<void> refresh() => _sync.sync();
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, Profile>(ProfileNotifier.new);
