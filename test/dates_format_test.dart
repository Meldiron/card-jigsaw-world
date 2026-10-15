import 'package:carden/core/dates.dart';
import 'package:flutter_test/flutter_test.dart';

/// One style for time left and dates (design QA 161).
void main() {
  test('time left: two units at most, never a zero unit, never zero', () {
    expect(formatTimeLeft(const Duration(days: 5, hours: 18, minutes: 3)), '5d 18h');
    expect(formatTimeLeft(const Duration(days: 1)), '1d');
    expect(formatTimeLeft(const Duration(days: 1, minutes: 20)), '1d');
    expect(formatTimeLeft(const Duration(hours: 16, minutes: 39)), '16h 39m');
    expect(formatTimeLeft(const Duration(hours: 3)), '3h');
    expect(formatTimeLeft(const Duration(minutes: 35)), '35m');
    expect(formatTimeLeft(const Duration(seconds: 20)), '1m');
    expect(formatTimeLeft(const Duration(seconds: -5)), '1m');
  });

  test('a live event ends in days, then hours, then soon', () {
    expect(endsIn(const Duration(days: 5, hours: 18)), 'Ends in 5d');
    expect(endsIn(const Duration(hours: 6, minutes: 50)), 'Ends in 6h');
    expect(endsIn(const Duration(minutes: 36)), 'Ends soon');
    expect(endsIn(const Duration(minutes: -3)), 'Ends soon');
  });

  test('dates are written out, day first', () {
    expect(formatDate(DateTime(2027, 5, 23)), '23 May 2027');
    expect(formatDate(DateTime(2026, 10, 16), year: false), '16 October');
    expect(formatDate(DateTime(2026, 10, 12), year: false, short: true), '12 Oct');
    expect(formatDate(DateTime(2026, 6, 2), year: false, short: true), '2 June');
  });

  test('play time drops zero units', () {
    expect(formatPlayTime(42), '42s');
    expect(formatPlayTime(13 * 60), '13m');
    expect(formatPlayTime(3 * 3600 + 5 * 60), '3h 5m');
    expect(formatPlayTime(2 * 86400), '2d');
  });
}
