import 'package:carden/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

Pack _pack(String id, {String category = 'Nature', DateTime? startAt, DateTime? endAt}) => Pack.fromRow(id, {
      'name': id,
      'category': category,
      'startAt': startAt?.toIso8601String(),
      'endAt': endAt?.toIso8601String(),
    });

void main() {
  final now = DateTime(2026, 10, 13, 12);

  group('daily months appear on their first day', () {
    test('past and current months are shown', () {
      expect(_pack('daily-2026-09', category: 'Daily').isReleasedAt(now), isTrue);
      expect(_pack('daily-2026-10', category: 'Daily').isReleasedAt(now), isTrue);
    });
    test('next month stays hidden until it starts, without a "coming soon" period', () {
      final november = _pack('daily-2026-11', category: 'Daily');
      expect(november.isReleasedAt(now), isFalse);
      expect(november.isReleasedAt(DateTime(2026, 10, 31, 23, 59)), isFalse);
      expect(november.isReleasedAt(DateTime(2026, 11, 1)), isTrue);
      expect(_pack('daily-2027-12', category: 'Daily').isReleasedAt(now), isFalse);
    });
  });

  group('event packs show up three days before they open', () {
    test('live and ended event packs are shown', () {
      expect(_pack('evpack-live', startAt: now.subtract(const Duration(days: 1)), endAt: now.add(const Duration(days: 2))).isReleasedAt(now), isTrue);
      expect(_pack('evpack-ended', startAt: now.subtract(const Duration(days: 9)), endAt: now.subtract(const Duration(days: 2))).isReleasedAt(now), isTrue);
    });
    test('an event pack two days away is coming soon', () {
      expect(_pack('evpack-soon', startAt: now.add(const Duration(days: 2)), endAt: now.add(const Duration(days: 9))).isReleasedAt(now), isTrue);
      expect(_pack('evpack-edge', startAt: now.add(Pack.soonWindow), endAt: now.add(const Duration(days: 9))).isReleasedAt(now), isTrue);
    });
    test('an event pack further away is hidden', () {
      expect(_pack('evpack-later', startAt: now.add(const Duration(days: 4)), endAt: now.add(const Duration(days: 11))).isReleasedAt(now), isFalse);
      expect(_pack('evpack-far', startAt: now.add(const Duration(days: 250)), endAt: now.add(const Duration(days: 257))).isReleasedAt(now), isFalse);
    });
  });

  test('library packs without a window are always shown', () {
    expect(_pack('wild-nature').isReleasedAt(now), isTrue);
  });

  test('events list: upcoming only within three days', () {
    GameEvent event(Duration startsIn) => GameEvent.fromRow('e', {
          'name': 'e',
          'startAt': DateTime.now().add(startsIn).toIso8601String(),
          'endAt': DateTime.now().add(startsIn + const Duration(days: 7)).toIso8601String(),
        });
    expect(event(const Duration(days: 2)).isUpcoming, isTrue);
    expect(event(const Duration(days: 5)).isUpcoming, isFalse);
    expect(event(const Duration(days: 250)).isUpcoming, isFalse);
  });
}
