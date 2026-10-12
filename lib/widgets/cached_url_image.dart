import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// A network image cached on disk by [DefaultCacheManager] (the same cache the
/// game uses for puzzle pictures) and decoded by Flutter's own
/// [MultiFrameImageStreamCompleter].
///
/// It replaces `CachedNetworkImageProvider`, whose stream completer re-decodes
/// a still image every time its listener count goes from zero to one. Two
/// quick re-attaches (cards rebuilt while scrolling, a preview and a size
/// listener on the same picture) emitted the same frame twice, the second
/// emission disposed the first image while it was still being handed out, and
/// Flutter reported "Cannot clone a disposed image". Flutter's completer does
/// not re-decode a still image it already holds.
@immutable
class CachedUrlImage extends ImageProvider<CachedUrlImage> {
  const CachedUrlImage(this.url, {this.scale = 1.0});

  final String url;
  final double scale;

  @override
  Future<CachedUrlImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture<CachedUrlImage>(this);

  @override
  ImageStreamCompleter loadImage(CachedUrlImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => [DiagnosticsProperty<ImageProvider>('Image provider', this), DiagnosticsProperty<CachedUrlImage>('Image key', key)],
    );
  }

  static Future<ui.Codec> _load(CachedUrlImage key, ImageDecoderCallback decode) async {
    final file = await DefaultCacheManager().getSingleFile(key.url);
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw StateError('Empty image file for ${key.url}');
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) => other is CachedUrlImage && other.url == url && other.scale == scale;

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() => '${objectRuntimeType(this, 'CachedUrlImage')}("$url", scale: $scale)';
}
