/// How the app writes numbers. One style everywhere (the app is written in
/// British English): thousands grouped with a comma from 1,000 up, so a
/// balance reads the same in the header pill, a price, a league row and an
/// alert. Every count a player sees goes through [formatCount] (or a widget
/// that calls it: `AnimatedCounter`, `CostLabel`, `Amount`).
library;

import 'dart:ui' show FontFeature;

/// Figures of equal width, for numbers that tick (balances, timers, move counts) or stand in a
/// column (league XP, statistics): `1,111` and `8,888` take the same room, so a counting pill does
/// not wobble and the digits of a list line up.
const tabularFigures = [FontFeature.tabularFigures()];

/// `12000` -> `12,000`; `-1500` -> `-1,500`; `950` -> `950`.
String formatCount(int v) {
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// A count with its noun: `1 ticket`, `3 tickets`, `12,000 coins`.
/// [many] defaults to [one] + "s".
String countOf(int n, String one, [String? many]) => '${formatCount(n)} ${n == 1 ? one : (many ?? '${one}s')}';

/// A count short enough for a tight spot (the header pills): exact and grouped up to 99,999, then
/// three figures at most: `123K`, `1.23M`, `12.3M`, `123M`, `1.23B`. Always rounded down, so it
/// never shows more than there is (235,999 -> `235K`, 1,239,999 -> `1.23M`).
String compactCount(int v) {
  final a = v.abs();
  final sign = v < 0 ? '-' : '';
  if (a < 100000) return formatCount(v);
  if (a < 1000000) return '$sign${a ~/ 1000}K';
  // Three significant figures, cut (not rounded) and without trailing zeros: 1.20M -> 1.2M.
  String cut(int unit, String suffix) {
    final whole = a ~/ unit;
    final decimals = whole < 10 ? 2 : (whole < 100 ? 1 : 0);
    if (decimals == 0) return '$sign$whole$suffix';
    final step = unit ~/ (decimals == 2 ? 100 : 10);
    final frac = (a % unit) ~/ step;
    var f = frac.toString().padLeft(decimals, '0');
    while (f.isNotEmpty && f.endsWith('0')) {
      f = f.substring(0, f.length - 1);
    }
    return '$sign$whole${f.isEmpty ? '' : '.$f'}$suffix';
  }

  if (a < 1000000000) return cut(1000000, 'M');
  return cut(1000000000, 'B');
}
