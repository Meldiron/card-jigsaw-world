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

/// A count in a slot of fixed width (Profile's wallet, the player card's three numbers): exact and
/// grouped up to 99,999, then short and rounded down, so it never shows more than there is:
/// `99,999`, `235K`, `1.2M`, `12M`. The exact figure stays in the Home pills and the Store.
String compactCount(int v) {
  final a = v.abs();
  final sign = v < 0 ? '-' : '';
  if (a < 100000) return formatCount(v);
  if (a < 1000000) return '$sign${a ~/ 1000}K';
  final tenths = a ~/ 100000; // millions with one decimal, rounded down
  final whole = tenths ~/ 10, decimal = tenths % 10;
  return '$sign${formatCount(whole)}${decimal == 0 || whole >= 10 ? '' : '.$decimal'}M';
}
