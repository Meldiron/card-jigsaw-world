import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'board.dart';
import 'image_loader.dart';
import 'twins.dart';

/// The part of [image] a board of [spec] shows (the centre crop the board widget draws from), at
/// most [maxSide] pixels on its longer side, as pixels [TwinFinder] can read.
Future<TwinPicture> twinPictureFor(ui.Image image, BoardSpec spec, {int maxSide = 1400}) async {
  final tiling = spec.tiling;
  final crop = tiling.crop(Size(image.width.toDouble(), image.height.toDouble()), Size(tiling.boardAspect(image.width / image.height), 1));
  final scale = math.min(1.0, maxSide / math.max(crop.width, crop.height));
  final w = math.max(1, (crop.width * scale).round()), h = math.max(1, (crop.height * scale).round());
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(image, crop, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..filterQuality = FilterQuality.medium);
  final picture = recorder.endRecording();
  final out = await picture.toImage(w, h);
  picture.dispose();
  final data = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
  out.dispose();
  return TwinPicture(w, h, data!.buffer.asUint8List());
}

/// Longest side read for twins: the shared decode as it is, and a giant picture at a size that
/// still gives every card about 30 boxes.
int twinReadSide({required bool giant}) => giant ? 2048 : 1400;

/// The twin cards of a picture's board (docs/twins.md): the picture at [url] (decoded as the game
/// decodes it, full size for a Giant pack) measured for the board [spec], once per picture and
/// board and off the UI thread (an isolate; about 20 ms for a normal board, up to a second for
/// the biggest giant ones). [Twins.none] when the picture cannot be read in time: the board then
/// plays as before.
final boardTwinsProvider = FutureProvider.autoDispose.family<Twins, (String, bool, BoardSpec)>((ref, key) async {
  final (url, giant, spec) = key;
  final link = ref.keepAlive();
  Timer? release;
  ref.onCancel(() => release = Timer(const Duration(seconds: 30), link.close));
  ref.onResume(() => release?.cancel());
  ref.onDispose(() => release?.cancel());
  try {
    final image = await ref.watch(puzzleImageFor(url, giant: giant).future);
    Future<Twins> measure() async => compute(findTwins, (await twinPictureFor(image, spec, maxSide: twinReadSide(giant: giant)), spec));
    return await measure().timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('Twins for $url: $e');
    return Twins.none;
  }
});
