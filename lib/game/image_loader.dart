import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/image_files.dart';

/// Loads and decodes a puzzle image once (cached on disk, see [ImageFiles]).
final puzzleImageProvider = FutureProvider.autoDispose.family<ui.Image, String>((ref, url) async {
  final keep = ref.keepAlive();
  Uint8List bytes;
  if (url.startsWith('asset:')) {
    bytes = (await rootBundle.load(url.substring(6))).buffer.asUint8List();
  } else {
    bytes = await ImageFiles.bytes(url);
  }
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1400, allowUpscaling: false);
  final frame = await codec.getNextFrame();
  ref.onDispose(() {
    keep.close();
  });
  return frame.image;
});
