import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Owner rule: icons only from lib/widgets/icons.dart (design QA 164). Screens name an icon
/// (`AppIcons.streak`), never a font glyph (`Icons.local_fire_department_rounded`), so one file
/// decides the icon family; icon tiles come in four sizes.
void main() {
  test('icons come from AppIcons, tiles in the four sizes', () {
    final glyph = RegExp(r'\b(Cupertino)?Icons\.[a-z]');
    final tile = RegExp(r'IconTile\([^;]*?size: (?!IconTile\.(small|medium|tool|large)\b)');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (f.path.endsWith('widgets/icons.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (glyph.hasMatch(lines[i]) || tile.hasMatch(lines[i])) offenders.add('${f.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty, reason: 'add the icon to AppIcons; use IconTile.small/medium/tool/large');
  });
}
