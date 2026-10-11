import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Loads and decodes a puzzle image once (cached on disk by the cache manager).
final puzzleImageProvider = FutureProvider.autoDispose.family<ui.Image, String>((ref, url) async {
  final keep = ref.keepAlive();
  Uint8List bytes;
  if (url.startsWith('asset:')) {
    bytes = (await rootBundle.load(url.substring(6))).buffer.asUint8List();
  } else {
    final file = await DefaultCacheManager().getSingleFile(url);
    bytes = await file.readAsBytes();
  }
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1400, allowUpscaling: false);
  final frame = await codec.getNextFrame();
  ref.onDispose(() {
    keep.close();
  });
  return frame.image;
});
