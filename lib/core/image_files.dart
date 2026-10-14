import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'appwrite.dart';

/// Bytes of a picture, cached on disk by [DefaultCacheManager].
///
/// Catalogue pictures are public Storage files and load straight from their URL. Player photos
/// (My Puzzles) and the pictures of private packs (opened with a pack code) are private files that
/// only some players can read, so they are fetched through the signed-in Appwrite client (session
/// cookie on iOS, cookie fallback on the web) and then cached under the same URL key.
class ImageFiles {
  ImageFiles._();

  static Storage? _storage;

  /// Called once by the app root with the app's Appwrite [Storage].
  static void attach(Storage storage) => _storage = storage;

  static const _privateBuckets = [AppwriteConfig.userUploadsBucket, AppwriteConfig.privatePacksBucket];

  /// The private file a URL points at (bucket, file id and, for a preview URL, its width), or null
  /// for a public picture.
  static ({String bucket, String fileId, int? width})? privateFile(String url) {
    for (final bucket in _privateBuckets) {
      final base = '${AppwriteConfig.endpoint}/storage/buckets/$bucket/files/';
      if (!url.startsWith(base)) continue;
      final rest = url.substring(base.length);
      final id = rest.split('/').first;
      if (id.isEmpty) return null;
      final preview = rest.startsWith('$id/preview');
      final width = preview ? int.tryParse(Uri.tryParse(url)?.queryParameters['width'] ?? '') : null;
      return (bucket: bucket, fileId: id, width: width);
    }
    return null;
  }

  /// File id of a private picture URL (player photo or private pack), or null for any other picture.
  static String? privateFileId(String url) => privateFile(url)?.fileId;

  static Future<Uint8List> bytes(String url) async {
    final cache = DefaultCacheManager();
    final file = privateFile(url);
    final storage = _storage;
    if (file == null || storage == null) {
      return (await cache.getSingleFile(url)).readAsBytes();
    }
    final hit = await cache.getFileFromCache(url);
    if (hit != null) return hit.file.readAsBytes();
    final width = file.width;
    final data = width != null
        ? await storage.getFilePreview(bucketId: file.bucket, fileId: file.fileId, width: width, quality: 82)
        : await storage.getFileView(bucketId: file.bucket, fileId: file.fileId);
    await cache.putFile(url, data, fileExtension: 'jpg', maxAge: const Duration(days: 30));
    return data;
  }
}
