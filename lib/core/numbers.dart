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
