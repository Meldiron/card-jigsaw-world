import 'dart:io';

import 'package:card_jigsaw_world/core/numbers.dart';
import 'package:flutter_test/flutter_test.dart';

/// One number style in the app: `formatCount` in lib/core/numbers.dart (design QA 160).
void main() {
  test('counts are grouped by thousands', () {
    expect(formatCount(0), '0');
    expect(formatCount(950), '950');
    expect(formatCount(1000), '1,000');
    expect(formatCount(18950), '18,950');
    expect(formatCount(1235067), '1,235,067');
    expect(formatCount(-1500), '-1,500');
  });

  test('counts in a tight spot are written short from 100,000 (header pills 002, Profile wallet 080)', () {
    expect(compactCount(950), '950');
    expect(compactCount(99999), '99,999');
    expect(compactCount(100000), '100K');
    expect(compactCount(235999), '235K');
    expect(compactCount(999999), '999K');
    expect(compactCount(1000000), '1M');
    expect(compactCount(1200000), '1.2M', reason: 'no trailing zero');
    expect(compactCount(1235067), '1.23M');
    expect(compactCount(1239999), '1.23M', reason: 'rounded down: never more than the player has');
    expect(compactCount(12500000), '12.5M');
    expect(compactCount(123456789), '123M');
    expect(compactCount(1239999999), '1.23B');
    expect(compactCount(-150000), '-150K');
  });

  test('a count with its noun', () {
    expect(countOf(1, 'ticket'), '1 ticket');
    expect(countOf(3, 'ticket'), '3 tickets');
    expect(countOf(12000, 'coin'), '12,000 coins');
    expect(countOf(2, 'board size', 'board sizes'), '2 board sizes');
  });

  test('no second thousands helper and no bare balance in the UI', () {
    // Values that grow past 999 for real players. Interpolated into a string as they are, they
    // print "18950" next to a header pill that says "18,950".
    const fields = r'(xp|coins|tickets|hints|peeks|magics|totalStars|piggyCoins|piggyCapacity|xpIntoLevel|rewardCoins|priceCoins|balance)';
    final braced = RegExp(r'\$\{([^{}]*?\b' + fields + r')\}');
    final plain = RegExp(r'\$' + fields + r'\b');
    final offenders = <String>[];
    // lib/core/numbers.dart is the helper itself.
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart') && !f.path.endsWith('core/numbers.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Comments, logs and debug descriptions are not shown to players.
        if (line.trimLeft().startsWith('//') || line.contains('debugPrint') || line.contains('toString()')) continue;
        if (RegExp(r'String (groupThousands|_fmt)\(').hasMatch(line) || line.contains('NumberFormat')) offenders.add('${f.path}:${i + 1} second number helper');
        for (final m in [...braced.allMatches(line), ...plain.allMatches(line)]) {
          offenders.add('${f.path}:${i + 1} ${m.group(0)}');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'format player-facing counts with formatCount / countOf');
  });
}
