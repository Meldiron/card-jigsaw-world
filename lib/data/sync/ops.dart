/// What the player did, queued until the server has it.
///
/// Every change to the save is recorded as a [SyncOp]: an intent ("claim this quest", "spend 75
/// coins", "save this board") rather than the totals it produces. The op is turned into column
/// changes ([OpPlan]) against the row as the server has it when the op is sent, so two devices add
/// up instead of overwriting each other, and something done on both (a quest claimed on the iPhone
/// and offline on the laptop) is applied once. Ops are stored on the device until the server
/// confirms them, so play without a connection is sent later.
library;

import 'dart:convert';
import 'dart:math';

import '../../models/models.dart';
import '../../state/rewards.dart';
import 'changes.dart';

enum OpTarget { profile, progress, event, ledger }

/// Why an op was dropped when it was sent: another device had already done the same thing.
enum SkipReason { questClaimed, vipBonusPaid, dailyClaimed, streakRestored, unlocked, achievementClaimed, piggyEmpty, notEnough }

/// A ledger entry written once its op is confirmed (`balanceAfter` comes from the server's row).
/// The currencies the ledger records (its `currency` column is an enum of these). Peeks and Magic
/// in stock are boosters, not money: they change the profile and leave no ledger line.
const ledgerCurrencies = {'coins', 'tickets', 'hints'};

class LedgerLine {
  const LedgerLine(this.amount, this.currency, this.reason);
  final int amount;
  final String currency;
  final String reason;
}

/// The column changes one op makes to a row, or why it was dropped.
class OpPlan {
  const OpPlan(this.changes, {this.ledger = const [], this.alreadySolved = false}) : skipped = null;
  const OpPlan.skip(SkipReason this.skipped)
      : changes = const {},
        ledger = const [],
        alreadySolved = false;

  final RowChanges changes;
  final List<LedgerLine> ledger;
  final SkipReason? skipped;

  /// Progress wins only: the picture was already solved on the server before this win.
  final bool alreadySolved;

  bool get isEmpty => changes.isEmpty;
}

/// The kinds of [SyncOp] (stored with every queued op, so never rename one).
abstract final class OpKind {
  // Profile.
  static const earn = 'earn', spend = 'spend', put = 'put', ad = 'ad', quest = 'quest', vipBonus = 'vipBonus', daily = 'daily';
  static const streak = 'streak', unlock = 'unlock', achievement = 'achievement', piggy = 'piggy', solve = 'solve', questCount = 'questCount';
  // Progress, event progress, ledger.
  static const board = 'board', win = 'win', discard = 'discard', event = 'event', ledger = 'ledger';
}

class SyncOp {
  SyncOp(this.kind, this.args, {String? id, DateTime? at, this.tries = 0})
      : id = id ?? newId(),
        // Milliseconds, as the server stores dates (a win recognises its own finish time).
        at = DateTime.fromMillisecondsSinceEpoch((at ?? DateTime.now()).millisecondsSinceEpoch, isUtc: true);

  final String id;
  final String kind;
  final Map<String, dynamic> args;

  /// When the player did it.
  final DateTime at;

  /// Sends that failed without an answer (the server may still have applied the op; profile ops
  /// are checked against `appliedOps` before they are sent again).
  int tries;

  static final _rng = Random();

  /// Four characters naming this device (set from the device's storage by the sync), so a device
  /// can tidy its own ids out of `appliedOps` without touching another device's.
  static String device = '0000';

  /// `<device><time><random>`: time-ordered, and short enough for ledger row ids (`<op id>-<n>`).
  static String newId() =>
      '$device${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_rng.nextInt(1 << 30).toRadixString(36).padLeft(6, '0')}';

  /// A new device name for [device].
  static String newDevice() => _rng.nextInt(36 * 36 * 36 * 36).toRadixString(36).padLeft(4, '0');

  /// When an op id was made (for trimming `appliedOps`).
  static DateTime? idTime(String id) {
    if (id.length < 13) return null;
    final ms = int.tryParse(id.substring(4, id.length - 6), radix: 36);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  OpTarget get target => switch (kind) {
        OpKind.board || OpKind.win || OpKind.discard => OpTarget.progress,
        OpKind.event => OpTarget.event,
        OpKind.ledger => OpTarget.ledger,
        _ => OpTarget.profile,
      };

  String? get puzzleId => args['puzzleId'] as String?;

  /// Built against the row as the server has it right now (guards, records, values derived from
  /// the row). The others are built against the last row the server returned.
  bool get needsFresh => const {OpKind.spend, OpKind.ad, OpKind.quest, OpKind.vipBonus, OpKind.daily, OpKind.streak, OpKind.unlock, OpKind.achievement, OpKind.piggy, OpKind.solve, OpKind.questCount, OpKind.win}.contains(kind);

  // ---- profile ----

  factory SyncOp.earn(String currency, int amount, String reason) => SyncOp(OpKind.earn, {'currency': currency, 'amount': amount, 'reason': reason});
  /// [log] false keeps it out of the ledger (a Hint used from the inventory).
  factory SyncOp.spend(String currency, int amount, String reason, {bool log = true}) =>
      SyncOp(OpKind.spend, {'currency': currency, 'amount': amount, 'reason': reason, if (!log) 'log': false});

  /// Plain fields where the last writer wins (name, avatar, timestamps, public stats).
  factory SyncOp.put(Map<String, dynamic> fields) => SyncOp(OpKind.put, {'fields': fields});
  factory SyncOp.ad() => SyncOp(OpKind.ad, {});
  factory SyncOp.quest(String key, {int coins = 0, int tickets = 0}) => SyncOp(OpKind.quest, {'key': key, 'coins': coins, 'tickets': tickets});
  factory SyncOp.vipBonus(String key, int coins) => SyncOp(OpKind.vipBonus, {'key': key, 'coins': coins});

  /// The daily gift as shown to the player (the streak is worked out from the server's last claim).
  /// A [restoreTarget] restores a streak lost to missed days with the claim, for [restoreCost]
  /// tickets, so the gift continues it instead of starting again at day 1.
  factory SyncOp.daily({required int day, required int coins, required int tickets, required int hints, int restoreTarget = 0, int restoreCost = 0}) =>
      SyncOp(OpKind.daily, {
        'day': day,
        'coins': coins,
        'tickets': tickets,
        'hints': hints,
        if (restoreTarget > 0) 'restoreTarget': restoreTarget,
        if (restoreTarget > 0) 'restoreCost': restoreCost,
      });

  /// Older builds restored a streak on its own, after the claim; kept for ops they queued.
  factory SyncOp.restoreStreak({required int cost, required int target}) => SyncOp(OpKind.streak, {'cost': cost, 'target': target});

  /// Adds [key] to the list column [list] (`unlockedPacks`, `unlockedTiers`, `unlockedAvatars`) for
  /// [price] of [currency], unless it is there already.
  factory SyncOp.unlock({required String list, required String key, String currency = 'coins', int price = 0, String? reason}) =>
      SyncOp(OpKind.unlock, {'list': list, 'key': key, 'currency': currency, 'price': price, 'reason': ?reason});
  factory SyncOp.achievement(String key, {int coins = 0, int tickets = 0, String? avatar}) =>
      SyncOp(OpKind.achievement, {'key': key, 'coins': coins, 'tickets': tickets, 'avatar': ?avatar});
  factory SyncOp.piggy({required int amount, required int tickets}) => SyncOp(OpKind.piggy, {'amount': amount, 'tickets': tickets});

  /// A finished board. [coins] is paid on a first solve and [replayCoins] when the picture was
  /// solved before (on this device or, found out when sending, another one). Level rewards follow
  /// the server's XP.
  factory SyncOp.solve({
    required String puzzleId,
    required bool first,
    required int coins,
    required int replayCoins,
    required int xp,
    required int stars,
    required String mode,
    required int moves,
    required int seconds,
    required int piggy,
  }) =>
      SyncOp(OpKind.solve, {
        'puzzleId': puzzleId,
        'first': first,
        'coins': coins,
        'replayCoins': replayCoins,
        'xp': xp,
        'stars': stars,
        'mode': mode,
        'moves': moves,
        'seconds': seconds,
        'piggy': piggy,
      });
  factory SyncOp.questCount(int count) => SyncOp(OpKind.questCount, {'count': count});

  // ---- progress ----

  /// The board in progress. [session] identifies one play-through; [resumed] means it continues
  /// the board saved on the row (rows from older versions have no session yet).
  factory SyncOp.board({
    required String puzzleId,
    required int gridSize,
    required String mode,
    required String layout,
    required int moves,
    required int seconds,
    required int hints,
    required String session,
    required bool resumed,
    bool painting = false,
    int par = 0,
    bool peeked = false,
    int bestLock = 0,
  }) =>
      SyncOp(OpKind.board, {
        'puzzleId': puzzleId,
        'gridSize': gridSize,
        'mode': mode,
        'layout': layout,
        'moves': moves,
        'seconds': seconds,
        'hints': hints,
        'session': session,
        'resumed': resumed,
        'painting': painting,
        'par': par,
        'peeked': peeked,
        'bestLock': bestLock,
      });

  /// A finished board: records only improve, a solved picture stays solved.
  factory SyncOp.win({
    required String puzzleId,
    required int gridSize,
    required String mode,
    required int moves,
    required int seconds,
    required int hints,
    required int stars,
    required String session,
    required bool resumed,
    bool painting = false,
    int par = 0,
    bool peeked = false,
    int bestLock = 0,
    DateTime? at,
  }) =>
      SyncOp(at: at, OpKind.win, {
        'puzzleId': puzzleId,
        'gridSize': gridSize,
        'mode': mode,
        'moves': moves,
        'seconds': seconds,
        'hints': hints,
        'stars': stars,
        'session': session,
        'resumed': resumed,
        'painting': painting,
        'par': par,
        'peeked': peeked,
        'bestLock': bestLock,
      });

  /// Drops the board in progress; records and lifetime totals stay.
  factory SyncOp.discard(String puzzleId) => SyncOp(OpKind.discard, {'puzzleId': puzzleId});

  factory SyncOp.event(String eventId) => SyncOp(OpKind.event, {'eventId': eventId});

  factory SyncOp.ledgerRow({required String rowId, required LedgerLine line, int? balanceAfter}) =>
      SyncOp(OpKind.ledger, {'rowId': rowId, 'amount': line.amount, 'currency': line.currency, 'reason': line.reason, 'balanceAfter': balanceAfter});

  /// The changes this op makes to [row] (the profile row, the picture's progress row or `{}` for a
  /// row that does not exist yet).
  OpPlan build(Map<String, dynamic> row) => switch (target) {
        OpTarget.profile => _profile(row),
        OpTarget.progress => _progress(row),
        OpTarget.event => OpPlan({'progress': const Inc(1), 'appliedOps': Append([id])}),
        OpTarget.ledger => const OpPlan({}),
      };

  int _a(String k) => asInt(args[k]);

  OpPlan _profile(Map<String, dynamic> row) {
    switch (kind) {
      case OpKind.earn:
        final n = _a('amount'), cur = args['currency'] as String;
        return n == 0 ? const OpPlan({}) : OpPlan({cur: Inc(n)}, ledger: [if (ledgerCurrencies.contains(cur)) LedgerLine(n, cur, args['reason'] as String)]);
      case OpKind.spend:
        // Spent on another device meanwhile: the balance never goes below zero, so this charges
        // what is left (the hint or peek was already used here).
        final n = min(_a('amount'), asInt(row[args['currency']])), cur = args['currency'] as String;
        if (n <= 0) return const OpPlan({});
        return OpPlan({cur: Dec(n)}, ledger: [if (args['log'] != false && ledgerCurrencies.contains(cur)) LedgerLine(-n, cur, args['reason'] as String)]);
      case OpKind.put:
        return OpPlan({for (final e in (args['fields'] as Map).entries) e.key.toString(): Put(e.value)});
      case OpKind.ad:
        final last = rowDate(row['adsDate']);
        final sameDay = last != null && isSameDay(last, at.toLocal());
        return OpPlan(sameDay ? {'adsToday': const Inc(1)} : {'adsToday': const Put(1), 'adsDate': Put(at.toIso8601String())});
      case OpKind.quest:
        final key = args['key'] as String;
        if (asStrings(row['claimedGoals']).contains(key)) return const OpPlan.skip(SkipReason.questClaimed);
        final coins = _a('coins'), tickets = _a('tickets');
        return OpPlan({
          'claimedGoals': Append([key]),
          'questsCompleted': const Inc(1),
          if (coins > 0) 'coins': Inc(coins),
          if (tickets > 0) 'tickets': Inc(tickets),
        }, ledger: [
          if (coins > 0) LedgerLine(coins, 'coins', 'goal:$key'),
          if (tickets > 0) LedgerLine(tickets, 'tickets', 'goal:$key'),
        ]);
      case OpKind.vipBonus:
        final key = args['key'] as String;
        if (asStrings(row['claimedGoals']).contains(key)) return const OpPlan.skip(SkipReason.vipBonusPaid);
        final coins = _a('coins');
        return OpPlan({'claimedGoals': Append([key]), 'coins': Inc(coins)}, ledger: [LedgerLine(coins, 'coins', 'vip-weekly')]);
      case OpKind.daily:
        final day = at.toLocal();
        final last = rowDate(row['lastDailyClaim']);
        if (last != null && isSameDay(last, day)) return const OpPlan.skip(SkipReason.dailyClaimed);
        final coins = _a('coins'), tickets = _a('tickets'), hints = _a('hints');
        final gift = <String, FieldChange>{
          if (coins > 0) 'coins': Inc(coins),
          if (tickets > 0) 'tickets': Inc(tickets),
          if (hints > 0) 'hints': Inc(hints),
        };
        final ledger = [LedgerLine(coins, 'coins', 'daily:day${_a('day') + 1}')];
        // A later day was already claimed elsewhere: this day's gift is still the player's, the
        // streak and the last claim stay as they are.
        if (last != null && last.isAfter(day)) return OpPlan(gift, ledger: ledger);
        final consecutive = last != null && dayIndex(day) - dayIndex(last) == 1;
        final restore = _a('restoreTarget'), restoreCost = _a('restoreCost');
        if (restore > 0 && !consecutive) {
          // Restored with the claim: the lost streak goes on, and the tickets are paid net of the gift's.
          if (asInt(row['tickets']) + tickets < restoreCost) return const OpPlan.skip(SkipReason.notEnough);
          final net = tickets - restoreCost;
          final streak = restore + 1;
          return OpPlan({
            for (final e in gift.entries)
              if (e.key != 'tickets') e.key: e.value,
            if (net != 0) 'tickets': net > 0 ? Inc(net) : Dec(-net),
            'streak': Put(streak),
            'longestStreak': Put(max(asInt(row['longestStreak']), streak)),
            'lastDailyClaim': Put(at.toIso8601String()),
            'lastStreakRestore': Put(at.toIso8601String()),
          }, ledger: [...ledger, LedgerLine(-restoreCost, 'tickets', 'streak-restore')]);
        }
        final streak = consecutive ? asInt(row['streak']) + 1 : 1;
        return OpPlan({
          ...gift,
          'streak': Put(streak),
          'longestStreak': Put(max(asInt(row['longestStreak']), streak)),
          'lastDailyClaim': Put(at.toIso8601String()),
        }, ledger: ledger);
      case OpKind.streak:
        final target = _a('target'), cost = _a('cost');
        if (asInt(row['streak']) >= target) return const OpPlan.skip(SkipReason.streakRestored);
        if (asInt(row['tickets']) < cost) return const OpPlan.skip(SkipReason.notEnough);
        return OpPlan({
          'tickets': Dec(cost),
          'streak': Put(target),
          'longestStreak': Put(max(asInt(row['longestStreak']), target)),
          'lastStreakRestore': Put(at.toIso8601String()),
        }, ledger: [LedgerLine(-cost, 'tickets', 'streak-restore')]);
      case OpKind.unlock:
        final list = args['list'] as String, key = args['key'] as String, price = _a('price'), cur = args['currency'] as String;
        if (asStrings(row[list]).contains(key)) return const OpPlan.skip(SkipReason.unlocked);
        // Spent on another device meanwhile: an unlock is not given away.
        if (price > 0 && asInt(row[cur]) < price) return const OpPlan.skip(SkipReason.notEnough);
        return OpPlan({list: Append([key]), if (price > 0) cur: Dec(price)},
            ledger: [if (price > 0) LedgerLine(-price, cur, (args['reason'] as String?) ?? 'unlock:$key')]);
      case OpKind.achievement:
        final key = args['key'] as String, avatar = args['avatar'] as String?;
        if (asStrings(row['claimedAchievements']).contains(key)) return const OpPlan.skip(SkipReason.achievementClaimed);
        final coins = _a('coins'), tickets = _a('tickets');
        return OpPlan({
          'claimedAchievements': Append([key]),
          if (coins > 0) 'coins': Inc(coins),
          if (tickets > 0) 'tickets': Inc(tickets),
          if (avatar != null && !asStrings(row['unlockedAvatars']).contains(avatar)) 'unlockedAvatars': Append([avatar]),
        }, ledger: [
          if (coins > 0) LedgerLine(coins, 'coins', 'achievement:$key'),
          if (tickets > 0) LedgerLine(tickets, 'tickets', 'achievement:$key'),
        ]);
      case OpKind.piggy:
        // Opened on another device first: only what is still in the piggy bank can be paid out.
        final credit = min(_a('amount'), asInt(row['piggyCoins']));
        if (credit <= 0) return const OpPlan.skip(SkipReason.piggyEmpty);
        if (asInt(row['tickets']) < _a('tickets')) return const OpPlan.skip(SkipReason.notEnough);
        return OpPlan({'coins': Inc(credit), 'piggyCoins': Dec(credit), 'tickets': Dec(_a('tickets'))},
            ledger: [LedgerLine(credit, 'coins', 'piggy')]);
      case OpKind.solve:
        return _solve(row);
      case OpKind.questCount:
        final n = _a('count');
        return asInt(row['questsCompleted']) >= n ? const OpPlan({}) : OpPlan({'questsCompleted': Put(n)});
    }
    return const OpPlan({});
  }

  OpPlan _solve(Map<String, dynamic> row) {
    final first = args['first'] == true;
    final xp0 = asInt(row['xp']), xp1 = xp0 + _a('xp');
    final from = LevelRewards.levelForXp(xp0), to = LevelRewards.levelForXp(xp1);
    var bonus = 0, tickets = 0, hints = 0;
    for (var l = from + 1; l <= to; l++) {
      final r = LevelRewards.forLevel(l);
      bonus += r.coins;
      tickets += r.tickets;
      hints += r.hints;
    }
    final coins = (first ? _a('coins') : _a('replayCoins')) + bonus;
    final room = Profile.piggyCapacity - asInt(row['piggyCoins']);
    final piggy = min(_a('piggy'), room);
    final modes = solvedModes(row['solvedByMode']);
    final mode = args['mode'] as String;
    modes[mode] = (modes[mode] ?? 0) + 1;
    return OpPlan({
      if (coins > 0) 'coins': Inc(coins),
      'xp': Inc(_a('xp')),
      'level': Put(to),
      if (piggy > 0) 'piggyCoins': Inc(piggy, max: Profile.piggyCapacity),
      if (first) 'puzzlesCompleted': const Inc(1),
      if (first && _a('stars') > 0) 'totalStars': Inc(_a('stars')),
      if (_a('moves') > 0) 'totalMoves': Inc(_a('moves')),
      if (_a('seconds') > 0) 'totalSeconds': Inc(_a('seconds')),
      'solvedByMode': Put(jsonEncode(modes)),
      if (tickets > 0) 'tickets': Inc(tickets),
      if (hints > 0) 'hints': Inc(hints),
    }, ledger: [LedgerLine(coins, 'coins', 'complete')]);
  }

  OpPlan _progress(Map<String, dynamic> row) {
    switch (kind) {
      case OpKind.discard:
        return const OpPlan({
          'layout': Put(''),
          'moves': Put(0),
          'elapsedSeconds': Put(0),
          'hintsUsed': Put(0),
          'session': Put(''),
          'par': Put(0),
          'peeked': Put(false),
          'bestLock': Put(0),
        });
      case OpKind.board:
        return OpPlan({
          'gridSize': Put(_a('gridSize')),
          'mode': Put(args['mode']),
          // Ops queued by builds before Painting carry no flag: a plain board.
          'painting': Put(args['painting'] == true),
          // The play-through's par, Peek and longest lock (quests); older ops carry none.
          ..._run(),
          'layout': Put(args['layout']),
          'moves': Put(_a('moves')),
          'elapsedSeconds': Put(_a('seconds')),
          'hintsUsed': Put(_a('hints')),
          'session': Put(args['session']),
          ..._totals(row),
        });
      case OpKind.win:
        // Solved before this win, unless the row is this very win (sent before, answer lost).
        final own = row['session'] == args['session'] && rowDate(row['completedAt'])?.isAtSameMomentAs(at) == true;
        final solved = rowSolved(row) && !own;
        final moves = _a('moves'), seconds = _a('seconds');
        int best(String k, int v) => row[k] == null ? v : min(asInt(row[k]), v);
        final last = rowDate(row['completedAt']);
        return OpPlan({
          'gridSize': Put(_a('gridSize')),
          'mode': Put(args['mode']),
          'painting': Put(args['painting'] == true),
          ..._run(),
          'layout': const Put(''),
          'moves': Put(moves),
          'elapsedSeconds': Put(seconds),
          'hintsUsed': Put(_a('hints')),
          'session': Put(args['session']),
          'completed': const Put(true),
          'stars': Put(max(asInt(row['stars']), _a('stars'))),
          'bestMoves': Put(best('bestMoves', moves)),
          'bestSeconds': Put(best('bestSeconds', seconds)),
          'completedAt': Put((last != null && last.isAfter(at) ? last.toUtc() : at).toIso8601String()),
          ..._totals(row),
        }, alreadySolved: solved);
    }
    return const OpPlan({});
  }

  /// The play-through's numbers the quests read: par, whether Peek was used, the most cards one
  /// move locked. They describe the board on the row (in progress, or the last one finished).
  Map<String, FieldChange> _run() => {
        'par': Put(_a('par')),
        'peeked': Put(args['peeked'] == true),
        'bestLock': Put(_a('bestLock')),
      };

  /// Lifetime totals on the picture: the session's numbers replace its earlier save, or add on
  /// top when this is a new session. Sending the same op twice gives the same result.
  Map<String, FieldChange> _totals(Map<String, dynamic> row) {
    final session = (row['session'] ?? '').toString();
    final same = session.isNotEmpty ? session == args['session'] : (args['resumed'] == true && (row['layout'] ?? '').toString().isNotEmpty);
    FieldChange total(String totalKey, String key, int value) {
      final t = max(asInt(row[totalKey]), asInt(row[key]));
      return Put(same ? t - asInt(row[key]) + value : t + value);
    }

    return {
      'totalMoves': total('totalMoves', 'moves', _a('moves')),
      'totalSeconds': total('totalSeconds', 'elapsedSeconds', _a('seconds')),
      'totalHints': total('totalHints', 'hintsUsed', _a('hints')),
    };
  }

  Map<String, dynamic> toJson() => {'id': id, 'kind': kind, 'args': args, 'at': at.toIso8601String(), 'tries': tries};

  factory SyncOp.fromJson(Map<String, dynamic> j) => SyncOp(
        j['kind'] as String,
        Map<String, dynamic>.from(j['args'] as Map),
        id: j['id'] as String,
        at: DateTime.tryParse(j['at']?.toString() ?? ''),
        tries: asInt(j['tries']),
      );

  SyncOp copyWith({Map<String, dynamic>? args}) => SyncOp(kind, args ?? this.args, id: id, at: at, tries: tries);

  @override
  String toString() => 'SyncOp($kind $id $args)';
}

/// A picture counts as solved once it was finished; older versions wrote `completed: false` while a
/// solved picture was replayed, so a finish time also counts.
bool rowSolved(Map<String, dynamic> row) => row['completed'] == true || rowDate(row['completedAt']) != null;

DateTime? rowDate(dynamic v) => v == null || v.toString().isEmpty ? null : DateTime.tryParse(v.toString())?.toLocal();

bool isSameDay(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

int dayIndex(DateTime d) {
  final l = d.toLocal();
  return DateTime.utc(l.year, l.month, l.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
}

Map<String, int> solvedModes(dynamic raw) {
  if (raw is Map) return {for (final e in raw.entries) e.key.toString(): asInt(e.value)};
  final s = raw?.toString();
  if (s == null || s.isEmpty) return {};
  try {
    final decoded = jsonDecode(s);
    if (decoded is Map) return {for (final e in decoded.entries) e.key.toString(): asInt(e.value)};
  } catch (_) {}
  return {};
}
