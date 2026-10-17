// Twin cards report (docs/twins.md): measures real catalogue pictures the way the game does and
// writes what it finds, for the threshold evidence and the contact sheets
// (tools/dev/twins_sheets.py). Not part of `flutter test` (it lives outside test/):
//
//   TWINS_SAMPLE=sample.json TWINS_OUT=out flutter test tools/dev/twins_report_test.dart
//
// sample.json lists the pictures: [{"id": ..., "file": "/path/to.jpg", "category": ..., "giant": false}].
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:carden/game/board.dart';
import 'package:carden/game/twins.dart';
import 'package:carden/game/twins_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('twins report', () async {
    final samplePath = Platform.environment['TWINS_SAMPLE'];
    final outDir = Platform.environment['TWINS_OUT'];
    if (samplePath == null || outDir == null) {
      markTestSkipped('Set TWINS_SAMPLE and TWINS_OUT');
      return;
    }
    final sample = (jsonDecode(File(samplePath).readAsStringSync()) as List).cast<Map<String, dynamic>>();
    final boards = <Map<String, dynamic>>[];
    for (final p in sample) {
      final giant = p['giant'] == true;
      final bytes = File(p['file'] as String).readAsBytesSync();
      // The game's decode: 1400 px wide at most for a normal picture, full size for a giant one.
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: giant ? null : 1400, allowUpscaling: false);
      final image = (await codec.getNextFrame()).image;
      final specs = giant
          ? [for (final m in GameMode.values) BoardSpec.squareGiantTiers(m).last]
          : [
              for (final m in GameMode.values)
                for (final t in BoardSpec.squareTiers(m))
                  if (t.rows >= 4) t,
            ];
      for (final spec in specs) {
        final tiling = spec.tiling;
        final picture = await twinPictureFor(image, spec, maxSide: twinReadSide(giant: giant));
        final watch = Stopwatch()..start();
        final finder = TwinFinder(picture, spec);
        final twins = finder.find();
        final findMs = watch.elapsedMilliseconds;
        // Every candidate pair in full, the ones near the limits kept.
        final near = <Map<String, dynamic>>[];
        var compared = 0;
        for (final (a, b) in finder.candidates()) {
          compared++;
          final pair = finder.compare(a, b);
          // The colour part of the score alone, so pairs kept apart by a speck show too.
          final colour = math.max(math.max(pair.mean / TwinFinder.meanLimit, pair.max / TwinFinder.maxLimit), math.max(pair.p95, pair.edge) / TwinFinder.p95Limit);
          if (colour <= 1.6) {
            near.add({'a': a, 'b': b, 'mean': pair.mean, 'p95': pair.p95, 'max': pair.max, 'edge': pair.edge, 'speck': pair.speck, 'grain': pair.grain, 'colour': colour, 'score': pair.score});
          }
        }
        // Where each card's picture comes from, in the decoded picture's pixels.
        final crop = tiling.crop(ui.Size(image.width.toDouble(), image.height.toDouble()), ui.Size(tiling.boardAspect(image.width / image.height), 1));
        final scale = crop.width / picture.width;
        List<List<double>> poly(int card) => [
              for (final o in tiling.polygon(card, ui.Size(picture.width.toDouble(), picture.height.toDouble()))) [crop.left + o.dx * scale, crop.top + o.dy * scale],
            ];
        final cards = <int>{for (final p in near) ...[p['a'] as int, p['b'] as int]};
        final shapes = <int, int>{};
        for (var s = 0; s < spec.cells; s++) {
          shapes[tiling.classOf(s)] = (shapes[tiling.classOf(s)] ?? 0) + 1;
        }
        final classes = twins.classes;
        // A class bigger than half its shape cannot be dealt without one of its cards on a twin's place.
        final crowded = [
          for (final c in classes)
            if (c.length * 2 > shapes[tiling.classOf(c.first)]!) c.length,
        ];
        boards.add({
          'id': p['id'],
          'category': p['category'],
          'file': p['file'],
          'decoded': [image.width, image.height],
          'spec': spec.fullCode,
          'cells': spec.cells,
          'twinCards': twins.cards,
          'classes': [for (final c in classes) c],
          'crowded': crowded,
          'compared': compared,
          'findMs': findMs,
          'near': near,
          'polys': {for (final c in cards) '$c': poly(c)},
        });
        // ignore: avoid_print
        print('${p['id']} ${spec.fullCode}: ${twins.cards} twin cards in ${classes.length} classes, $compared pairs, ${findMs}ms');
      }
      image.dispose();
    }
    Directory(outDir).createSync(recursive: true);
    File('$outDir/twins_report.json').writeAsStringSync(jsonEncode(boards));
  }, timeout: const Timeout(Duration(hours: 2)));
}
