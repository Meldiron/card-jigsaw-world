/// The finish log of a progress row (`progress.finishes`, docs/sync.md).
///
/// Pure Dart on purpose, like the save-merge rules (lib/state/merge.dart), which use it on raw row
/// maps.
library;

import 'dart:convert';
import 'dart:math';

/// One finished board of a picture with the values it was finished with: an entry of the
/// `finishes` column of a progress row, a JSON list every win adds to. The row's board fields
/// (mode, size, Painting, par, moves, time, Peek, longest lock) belong to the board on the row, which
/// a replay overwrites as soon as it is saved, so the quests and the achievements count these
/// instead (2026-10-17: replaying a picture finished today changed what the shape, size and Painting
/// quests counted, and a replay moved the per-shape and size achievements).
class BoardFinish {
  const BoardFinish({
    required this.at,
    this.mode = 'cards',
    this.gridSize = 16,
    this.painting = false,
    this.par = 0,
    this.moves = 0,
    this.seconds = 0,
    this.peeked = false,
    this.bestLock = 0,
    this.stars = 0,
    this.hints = 0,
    this.known = true,
  });

  /// When the board was finished (local time).
  final DateTime at;
  final String mode;
  final int gridSize;
  final bool painting;
  final int par;
  final int moves;
  final int seconds;
  final bool peeked;
  final int bestLock;
  final int stars;

  /// Hints used on the board (entries written before 2026-10-17 evening have none: 0).
  final int hints;

  /// False when the finish's values are lost: a build from before the log finished the board, and
  /// a board saved since (a replay) overwrote the row's board fields. It still counts as a solve on
  /// its day, and for nothing that asks how the board was played.
  final bool known;

  /// Finished quickly, under 4 seconds a card (achievement "Quick Hands").
  bool get quick => seconds > 0 && seconds < gridSize * 4;

  /// Finished between 22:00 and 05:00 (achievement "Night Owl"); [early]: between 05:00 and 08:00
  /// ("Early Bird"). The finish time is known also when the values are not.
  bool get atNight => at.hour >= 22 || at.hour < 5;
  bool get early => at.hour >= 5 && at.hour < 8;

  /// The log keeps the finishes of the [keep] days before the newest one (today's and this week's
  /// quests, with a day to spare), plus the newest one before those (what the player usually plays,
  /// `PlayHabits`, looks before today or Monday), plus the boards the achievements count a picture
  /// by, whenever they were finished: the newest of each shape, the biggest, the newest without
  /// hints, quick, at night and early (so a replay never moves an achievement back).
  static const keep = Duration(days: 8);

  /// At most this many finishes, in at most [maxChars] characters (the column is a string of 4,000).
  static const maxEntries = 16;
  static const maxChars = 4000;

  /// A finish recorded within this of the row's finish time is that finish.
  static const _same = Duration(seconds: 1);

  Map<String, dynamic> toJson() => known
      ? {
          'at': _time(at),
          'mode': mode,
          'gridSize': gridSize,
          'painting': painting,
          'par': par,
          'moves': moves,
          'seconds': seconds,
          'peeked': peeked,
          'bestLock': bestLock,
          'stars': stars,
          'hints': hints,
        }
      : {'at': _time(at), 'known': false};

  static BoardFinish? fromJson(dynamic j) {
    if (j is! Map) return null;
    final at = _date(j['at']);
    if (at == null) return null;
    if (j['known'] == false) return BoardFinish(at: at, known: false);
    return BoardFinish(
      at: at,
      mode: '${j['mode'] ?? 'cards'}',
      gridSize: _int(j['gridSize'], 16),
      painting: j['painting'] == true,
      par: _int(j['par']),
      moves: _int(j['moves']),
      seconds: _int(j['seconds']),
      peeked: j['peeked'] == true,
      bestLock: _int(j['bestLock']),
      stars: _int(j['stars']),
      hints: _int(j['hints']),
    );
  }

  /// A stored log, oldest first; anything unreadable is left out.
  static List<BoardFinish> decode(dynamic raw) {
    if (raw == null || '$raw'.isEmpty) return const [];
    try {
      final list = jsonDecode('$raw');
      if (list is! List) return const [];
      return [for (final j in list) ?fromJson(j)]..sort((a, b) => a.at.compareTo(b.at));
    } catch (_) {
      return const [];
    }
  }

  static String encode(List<BoardFinish> finishes) => finishes.isEmpty ? '' : jsonEncode([for (final f in finishes) f.toJson()]);

  /// The finishes of progress row [row] (table columns), oldest first: the log, plus the last
  /// finish when only the board fields hold it (a row finished by a build from before the log).
  /// Those fields describe that finish until a board is saved over them: then (a board in progress,
  /// or a discarded one, which leaves no moves and no session) it counts with no values ([known]
  /// false).
  static List<BoardFinish> ofRow(Map<String, dynamic> row) {
    final log = decode(row['finishes']);
    final at = _date(row['completedAt']);
    if (at == null || (log.isNotEmpty && !at.isAfter(log.last.at.add(_same)))) return log;
    final kept = '${row['layout'] ?? ''}'.isEmpty && (_int(row['moves']) > 0 || '${row['session'] ?? ''}'.isNotEmpty);
    return [
      ...log,
      kept
          ? BoardFinish(
              at: at,
              mode: '${row['mode'] ?? 'cards'}',
              gridSize: _int(row['gridSize'], 4),
              painting: row['painting'] == true,
              par: _int(row['par']),
              moves: _int(row['moves']),
              seconds: _int(row['elapsedSeconds']),
              peeked: row['peeked'] == true,
              bestLock: _int(row['bestLock']),
              stars: _int(row['stars']),
              hints: _int(row['hintsUsed']),
            )
          : BoardFinish(at: at, known: false),
    ];
  }

  /// The log of [row] with [finish] added, as the column stores it (the finish only the board
  /// fields hold recorded too, see [ofRow]).
  static String logWith(Map<String, dynamic> row, [BoardFinish? finish]) => _log([...ofRow(row), ?finish]);

  /// The logs of two rows of the same picture as one (a sign-in merge of two saves).
  static String merged(Map<String, dynamic> a, Map<String, dynamic> b) => _log([...ofRow(a), ...ofRow(b)]);

  /// The log of [row] with the finish only its board fields hold recorded, or null when there is
  /// none: a board about to be saved over those fields keeps the finish this way.
  static String? unrecorded(Map<String, dynamic> row) {
    final all = ofRow(row);
    if (all.isEmpty || !all.last.known || decode(row['finishes']).length == all.length) return null;
    return _log(all);
  }

  /// One entry per finish time (a win sent twice is one; of a known and an unknown one, the known),
  /// oldest first: the [keep] days before the newest finish, the newest one before them and the
  /// boards the achievements count ([keep]), at most [maxEntries] in [maxChars] (the oldest of the
  /// others go first, then the oldest of those).
  static String _log(Iterable<BoardFinish> finishes) {
    final byTime = <int, BoardFinish>{};
    for (final f in finishes) {
      final t = f.at.millisecondsSinceEpoch;
      if (byTime[t] == null || f.known) byTime[t] = f;
    }
    final sorted = byTime.values.toList()..sort((a, b) => a.at.compareTo(b.at));
    if (sorted.isEmpty) return '';
    final from = sorted.last.at.subtract(keep);
    final first = sorted.indexWhere((f) => !f.at.isBefore(from));
    final recent = sorted.sublist(max(0, first - 1)).toSet();
    final known = sorted.where((f) => f.known).toList();
    BoardFinish? newest(Iterable<BoardFinish> list, bool Function(BoardFinish f) test) => list.where(test).lastOrNull;
    final lasting = <BoardFinish>{
      for (final mode in {for (final f in known) f.mode}) ?newest(known, (f) => f.mode == mode),
      if (known.isNotEmpty) known.reduce((a, b) => b.gridSize >= a.gridSize ? b : a),
      ?newest(known, (f) => f.hints == 0),
      ?newest(known, (f) => f.quick),
      ?newest(sorted, (f) => f.atNight),
      ?newest(sorted, (f) => f.early),
    };
    var kept = [for (final f in sorted) if (recent.contains(f) || lasting.contains(f)) f];
    bool over() => kept.length > maxEntries || encode(kept).length > maxChars;
    while (kept.length > 1 && over()) {
      final drop = kept.firstWhere((f) => !lasting.contains(f) && f != sorted.last, orElse: () => kept.first);
      kept = [for (final f in kept) if (f != drop) f];
    }
    return encode(kept);
  }

  /// [at] in UTC to the millisecond, as the log stores it.
  static String _time(DateTime at) => DateTime.fromMillisecondsSinceEpoch(at.millisecondsSinceEpoch, isUtc: true).toIso8601String();

  static int _int(dynamic v, [int d = 0]) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? d : d);

  static DateTime? _date(dynamic v) => v == null || '$v'.isEmpty ? null : DateTime.tryParse('$v')?.toLocal();
}
