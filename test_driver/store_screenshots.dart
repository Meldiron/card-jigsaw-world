// Driver for integration_test/store_screenshots_test.dart.
// Writes every in-app capture to store/raw/<name>.png (App Store raw captures)
// and the board rectangles the test recorded on game screens to
// store/raw/boards.json (merged into an existing file, so a partial or
// light-theme run keeps the other entries).
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = File('store/raw/$name.png');
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);
      return true;
    },
    writeResponseOnFailure: true,
    responseDataCallback: (Map<String, dynamic>? data) async {
      final boards = data?['boards'];
      if (boards is! Map) return;
      final file = File('store/raw/boards.json');
      final merged = <String, dynamic>{
        if (file.existsSync()) ...jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
        ...boards.cast<String, dynamic>(),
      };
      final sorted = {for (final k in merged.keys.toList()..sort()) k: merged[k]};
      await file.writeAsString('${const JsonEncoder.withIndent('  ').convert(sorted)}\n');
    },
  );
}
