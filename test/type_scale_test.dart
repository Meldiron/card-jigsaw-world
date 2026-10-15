import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every text uses a size from the type ramp (`TypeSize` in lib/core/theme/tokens.dart) and a
/// weight from 400 to 700 (design QA 162). Sizes computed from a box (board labels, wheel glyphs)
/// are not literals and are not checked.
void main() {
  test('no font size outside the type ramp, nothing heavier than 700', () {
    final literal = RegExp(r'fontSize: \d|fontSize = \d|fontSize: \w+ \? \d');
    final heavy = RegExp(r'FontWeight\.w[89]00');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (f.path.endsWith('theme/tokens.dart') || f.path.endsWith('theme/app_theme.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (literal.hasMatch(lines[i]) || heavy.hasMatch(lines[i])) offenders.add('${f.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty, reason: 'use TypeSize.* and FontWeight.w400-w700');
  });
}
