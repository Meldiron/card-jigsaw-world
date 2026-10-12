import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart' show blurHashDecodeImage;

/// A BlurHash placeholder painted straight from a decoded image.
///
/// `flutter_blurhash`'s own widget wraps its decoded `ui.Image` in an
/// ImageProvider that hands the same image to every stream completer without
/// cloning it. When Flutter's image cache dropped one completer, it disposed
/// that shared image, and the next card with the same hash failed with "Cannot
/// clone a disposed image". Here each hash is decoded once into a small cache
/// and painted with [RawImage], which clones the image for its render object,
/// so nothing outside this cache ever disposes it.
class HashImage extends StatefulWidget {
  const HashImage({super.key, required this.hash, required this.color, this.fit = BoxFit.cover});

  final String hash;

  /// Shown until the hash is decoded (and if it cannot be decoded).
  final Color color;
  final BoxFit fit;

  @override
  State<HashImage> createState() => _HashImageState();
}

class _HashImageState extends State<HashImage> {
  // 32x32 RGBA images are about 4 KB each; 256 of them is a few hundred KB.
  static const _capacity = 256;
  // Map literals keep insertion order, which makes this an LRU list.
  static final _cache = <String, Future<ui.Image?>>{};
  // Decoded images by hash, so a cached hash paints on its first frame.
  static final _ready = <String, ui.Image>{};

  static Future<ui.Image?> _decode(String hash) {
    final hit = _cache.remove(hash);
    if (hit != null) {
      _cache[hash] = hit; // most recently used last
      return hit;
    }
    final future = blurHashDecodeImage(blurHash: hash, width: 32, height: 32).then<ui.Image?>((i) {
      if (_cache.containsKey(hash)) _ready[hash] = i;
      return i;
    }).catchError((Object _) => null);
    _cache[hash] = future;
    // Evicted images are not disposed: a widget may still paint one, and the
    // engine frees an unreferenced image on its own.
    while (_cache.length > _capacity) {
      _ready.remove(_cache.keys.first);
      _cache.remove(_cache.keys.first);
    }
    return future;
  }

  late Future<ui.Image?> _image = _decode(widget.hash);

  @override
  void didUpdateWidget(HashImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hash != widget.hash) _image = _decode(widget.hash);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: FutureBuilder<ui.Image?>(
        future: _image,
        initialData: _ready[widget.hash],
        builder: (context, snap) {
          final image = snap.data ?? _ready[widget.hash];
          if (image == null) return ColoredBox(color: widget.color);
          return RawImage(image: image, fit: widget.fit, filterQuality: FilterQuality.low);
        },
      ),
    );
  }
}
