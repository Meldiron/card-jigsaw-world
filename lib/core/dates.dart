/// How the app writes time and dates. One place, three rules:
///
/// - **Time left** before something opens or resets ("Resets in", "Opens in",
///   "Next offer in"): at most two units and never a zero unit, rounded up so
///   the last minute still says "1m": `5d 18h`, `5d`, `16h 39m`, `16h`, `35m`.
/// - **A live event's end** on a cover or chip: one unit, then "soon":
///   `Ends in 5d`, `Ends in 6h`, `Ends soon`. Never "Ends in 0h".
/// - **Dates** written out, day first (the app is British English):
///   `23 May 2027`, `16 October` (this year), `12 Oct` (tight spots).
///
/// Elapsed time on a board stays a clock (`4:20`, `formatDuration` in
/// game_controller.dart); total play time is [formatPlayTime].
library;

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// `5d 18h` · `5d` · `16h 39m` · `16h` · `35m` · `1m`.
String formatTimeLeft(Duration d) {
  final total = d.isNegative ? 0 : (d.inSeconds / 60).ceil();
  final mins = total < 1 ? 1 : total;
  final days = mins ~/ 1440, hours = (mins % 1440) ~/ 60, m = mins % 60;
  if (days > 0) return hours > 0 ? '${days}d ${hours}h' : '${days}d';
  if (hours > 0) return m > 0 ? '${hours}h ${m}m' : '${hours}h';
  return '${m}m';
}

/// `Ends in 5d` · `Ends in 6h` · `Ends soon` (the last hour).
String endsIn(Duration left) {
  if (left.inDays >= 1) return 'Ends in ${left.inDays}d';
  if (left.inHours >= 1) return 'Ends in ${left.inHours}h';
  return 'Ends soon';
}

/// `23 May 2027`; `16 October` with [year] false; `12 Oct` with [short].
String formatDate(DateTime d, {bool year = true, bool short = false}) {
  final month = _months[d.month - 1];
  final m = short && month.length > 4 ? month.substring(0, 3) : month;
  return year ? '${d.day} $m ${d.year}' : '${d.day} $m';
}

/// When a message arrived: `Today, 21:05`, `Yesterday, 9:30`, `12 Oct, 21:05`, or with the year
/// when it is not this year. [time] is the time of day as the device writes it (12 or 24 hours).
String formatMessageDate(DateTime local, String time, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final d = DateTime(local.year, local.month, local.day);
  final t = DateTime(today.year, today.month, today.day);
  final day = switch (t.difference(d).inDays) {
    0 => 'Today',
    1 => 'Yesterday',
    _ => formatDate(local, year: local.year != today.year, short: true),
  };
  return '$day, $time';
}

/// Total time played: `45s`, `13m`, `6h 23m`, `2d 4h`.
String formatPlayTime(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final d = seconds ~/ 86400, h = (seconds % 86400) ~/ 3600, m = (seconds % 3600) ~/ 60;
  if (d > 0) return h > 0 ? '${d}d ${h}h' : '${d}d';
  if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
  return '${m}m';
}
