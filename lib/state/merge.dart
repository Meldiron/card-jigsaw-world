/// Save-merge rules, used when a sign-in moves a player from the guest
/// account on this device to an existing account.
///
/// Pure Dart on purpose: the rules work on the raw row maps that the
/// profile and progress repositories read and write (the same keys as the
/// Appwrite tables), so they can be unit-tested without Flutter and the
/// snapshot can be stored as JSON across a web redirect.
library;

import 'dart:math';

/// Which save supplies the scalar parts (coins, level, streak, identity).
enum MergeChoice { guest, account }

/// What the rules decided before any UI was involved.
enum MergeDecision { keepGuest, keepAccount, ask }

/// A player's save: the profile row plus every progress row.
class SaveSnapshot {
  SaveSnapshot({required this.userId, required this.profile, required this.progress, this.updatedAt});

  /// Owner of the rows (an Appwrite user id).
  final String userId;

  /// Profile row data (`Profile.toData()` keys).
  final Map<String, dynamic> profile;

  /// Progress rows (`PuzzleProgress.toData()` keys, plus `$updatedAt` when known).
  final List<Map<String, dynamic>> progress;

  /// When the profile row was last written.
  final DateTime? updatedAt;

  static int _i(dynamic v, [int d = 0]) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? d : d);
  static DateTime? _dt(dynamic v) => v == null || v.toString().isEmpty ? null : DateTime.tryParse(v.toString())?.toUtc();
  static List<String> _list(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : const [];

  int get solved => progress.where((r) => r['completed'] == true).length;
  int get stars => progress.where((r) => r['completed'] == true).fold(0, (s, r) => s + _i(r['stars']));
  int get xp => _i(profile['xp']);
  int get level => _i(profile['level'], 1);
  int get coins => _i(profile['coins']);
  int get tickets => _i(profile['tickets']);
  int get hints => _i(profile['hints']);
  int get piggyCoins => _i(profile['piggyCoins']);
  int get streak => _i(profile['streak']);
  int get longestStreak => _i(profile['longestStreak']);
  String get displayName => (profile['displayName'] ?? 'Player').toString();
  String get avatar => (profile['avatar'] ?? 'fox').toString();

  /// Most recent activity: the newest progress row, or the profile row.
  DateTime? get lastPlayed {
    DateTime? best = updatedAt;
    for (final r in progress) {
      for (final key in const ['\$updatedAt', 'completedAt']) {
        final t = _dt(r[key]);
        if (t != null && (best == null || t.isAfter(best))) best = t;
      }
    }
    return best;
  }

  /// A save with almost nothing in it is not worth asking about: few pictures, little XP and no
  /// more Coins, Tickets or Hints than a new player gets in the first days (bought ones count).
  bool get isTrivial => solved < 3 && xp < 200 && coins <= 650 && tickets <= 5 && hints <= 5;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'profile': profile,
        'progress': progress,
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
      };

  factory SaveSnapshot.fromJson(Map<String, dynamic> j) => SaveSnapshot(
        userId: j['userId'].toString(),
        profile: Map<String, dynamic>.from(j['profile'] as Map),
        progress: [for (final r in (j['progress'] as List? ?? const [])) Map<String, dynamic>.from(r as Map)],
        updatedAt: _dt(j['updatedAt']),
      );
}

/// [x] can replace [y] without the player losing anything visible: at least
/// as many solved pictures, stars and XP, and played at least as recently.
bool dominates(SaveSnapshot x, SaveSnapshot y) {
  if (x.solved < y.solved || x.stars < y.stars || x.xp < y.xp) return false;
  final xt = x.lastPlayed, yt = y.lastPlayed;
  if (yt == null) return true;
  if (xt == null) return false;
  return !xt.isBefore(yt);
}

/// Decides the scalar parts. The account wins ties, so a player who signs in
/// on a fresh install never sees a question. Coins, Tickets and Hints come
/// from one save only, so when the save that would be dropped holds more of
/// any of them (bought ones, say), the player chooses.
MergeDecision decide({required SaveSnapshot guest, required SaveSnapshot account}) {
  if (guest.isTrivial) return MergeDecision.keepAccount;
  if (account.isTrivial) return MergeDecision.keepGuest;
  final auto = dominates(account, guest)
      ? MergeDecision.keepAccount
      : dominates(guest, account)
          ? MergeDecision.keepGuest
          : MergeDecision.ask;
  if (auto == MergeDecision.ask) return auto;
  final kept = auto == MergeDecision.keepAccount ? account : guest;
  final dropped = auto == MergeDecision.keepAccount ? guest : account;
  if (dropped.coins > kept.coins || dropped.tickets > kept.tickets || dropped.hints > kept.hints) return MergeDecision.ask;
  return auto;
}

/// Keys of the profile that are copied as a block from the chosen save.
const scalarKeys = ['coins', 'tickets', 'hints', 'piggyCoins', 'xp', 'level', 'streak', 'lastDailyClaim', 'displayName', 'avatar'];

/// Profile lists that are always combined.
const unionKeys = ['unlockedPacks', 'unlockedTiers', 'unlockedAvatars', 'claimedAchievements', 'claimedGoals'];

List<String> unionOf(dynamic a, dynamic b) {
  final out = <String>[];
  for (final v in [...SaveSnapshot._list(a), ...SaveSnapshot._list(b)]) {
    if (!out.contains(v)) out.add(v);
  }
  return out;
}

/// Best of both for one picture. The row played more recently is the base
/// (so a board in progress survives); records and totals take the better of
/// the two; solved if either side solved it.
Map<String, dynamic> mergeProgressRow(Map<String, dynamic> a, Map<String, dynamic> b) {
  final ta = SaveSnapshot._dt(a['\$updatedAt']) ?? SaveSnapshot._dt(a['completedAt']);
  final tb = SaveSnapshot._dt(b['\$updatedAt']) ?? SaveSnapshot._dt(b['completedAt']);
  final aNewer = tb == null || (ta != null && !ta.isBefore(tb));
  final base = aNewer ? a : b;
  final other = aNewer ? b : a;
  final out = <String, dynamic>{...other, ...base};
  // Painting belongs to the board kept (the newer row's), also when that row predates it.
  out['painting'] = base['painting'] == true;
  out['stars'] =max(SaveSnapshot._i(a['stars']), SaveSnapshot._i(b['stars']));
  out['completed'] = a['completed'] == true || b['completed'] == true;
  for (final k in const ['bestMoves', 'bestSeconds']) {
    final va = a[k], vb = b[k];
    out[k] = va == null ? vb : (vb == null ? va : min(SaveSnapshot._i(va), SaveSnapshot._i(vb)));
  }
  for (final k in const ['totalMoves', 'totalSeconds', 'totalHints']) {
    out[k] = max(SaveSnapshot._i(a[k]), SaveSnapshot._i(b[k]));
  }
  final ca = SaveSnapshot._dt(a['completedAt']), cb = SaveSnapshot._dt(b['completedAt']);
  if (ca != null || cb != null) {
    out['completedAt'] = (ca == null ? cb : (cb == null ? ca : (ca.isBefore(cb) ? ca : cb)))!.toIso8601String();
  }
  out.remove('\$updatedAt');
  return out;
}

/// Progress rows of both saves combined, keyed by puzzle id. Only pictures
/// the guest touched are returned as [changed]; the rest of the account's
/// rows are untouched.
({Map<String, Map<String, dynamic>> all, Map<String, Map<String, dynamic>> changed}) mergeProgress(
  List<Map<String, dynamic>> guest,
  List<Map<String, dynamic>> account,
) {
  final all = <String, Map<String, dynamic>>{};
  for (final r in account) {
    final id = r['puzzleId']?.toString();
    if (id != null) all[id] = {...r}..remove('\$updatedAt');
  }
  final changed = <String, Map<String, dynamic>>{};
  for (final r in guest) {
    final id = r['puzzleId']?.toString();
    if (id == null) continue;
    final existing = all[id];
    final merged = existing == null ? ({...r}..remove('\$updatedAt')) : mergeProgressRow(r, existing);
    all[id] = merged;
    changed[id] = merged;
  }
  return (all: all, changed: changed);
}

/// Patch for the account's profile row: unions and records always, scalars
/// from the chosen save. Never includes ownership, VIP or purchase fields.
Map<String, dynamic> mergeProfile({
  required SaveSnapshot guest,
  required SaveSnapshot account,
  required MergeChoice choice,
  required Map<String, Map<String, dynamic>> mergedProgress,
}) {
  final patch = <String, dynamic>{};
  for (final k in unionKeys) {
    patch[k] = unionOf(account.profile[k], guest.profile[k]);
  }
  patch['longestStreak'] = max(guest.longestStreak, account.longestStreak);
  final rows = mergedProgress.values;
  final solved = rows.where((r) => r['completed'] == true).length;
  final stars = rows.where((r) => r['completed'] == true).fold<int>(0, (s, r) => s + SaveSnapshot._i(r['stars']));
  patch['puzzlesCompleted'] = [solved, SaveSnapshot._i(guest.profile['puzzlesCompleted']), SaveSnapshot._i(account.profile['puzzlesCompleted'])].reduce(max);
  patch['totalStars'] = [stars, SaveSnapshot._i(guest.profile['totalStars']), SaveSnapshot._i(account.profile['totalStars'])].reduce(max);
  // Quests claimed: the larger count (claimedGoals is a union, so a quest claimed on both saves is one).
  patch['questsCompleted'] = max(SaveSnapshot._i(guest.profile['questsCompleted']), SaveSnapshot._i(account.profile['questsCompleted']));
  final chosen = choice == MergeChoice.guest ? guest : account;
  for (final k in scalarKeys) {
    patch[k] = chosen.profile[k];
  }
  // The chosen streak must stay at or below the combined longest.
  patch['longestStreak'] = max(patch['longestStreak'] as int, SaveSnapshot._i(patch['streak']));
  return patch;
}

/// Short relative date for the merge sheet ("today", "3 days ago").
String relativeTime(DateTime? t, {DateTime? now}) {
  if (t == null) return 'never';
  final n = (now ?? DateTime.now()).toUtc();
  final d = n.difference(t.toUtc());
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago';
  if (d.inDays < 2) return 'yesterday';
  if (d.inDays < 14) return '${d.inDays} days ago';
  if (d.inDays < 60) return '${d.inDays ~/ 7} weeks ago';
  if (d.inDays < 365) return '${d.inDays ~/ 30} months ago';
  return '${d.inDays ~/ 365} years ago';
}
