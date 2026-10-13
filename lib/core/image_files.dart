import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'appwrite.dart';

/// Bytes of a picture, cached on disk by [DefaultCacheManager].
///
/// Catalogue pictures are public Storage files and load straight from their URL. Player photos
/// (My Puzzles) are private files that only their owner can read, so they are fetched through the
/// signed-in Appwrite client (session cookie on iOS, cookie fallback on the web) and then cached
/// under the same URL key.
class ImageFiles {
  ImageFiles._();

  static Storage? _storage;

  /// Called once by the app root with the app's Appwrite [Storage].
  static void attach(Storage storage) => _storage = storage;

  static const _uploadsBase = '${AppwriteConfig.endpoint}/storage/buckets/${AppwriteConfig.userUploadsBucket}/files/';

  /// File id of a player photo URL, or null for any other picture.
  static String? privateFileId(String url) {
    if (!url.startsWith(_uploadsBase)) return null;
    final id = url.substring(_uploadsBase.length).split('/').first;
    return id.isEmpty ? null : id;
  }

  static Future<Uint8List> bytes(String url) async {
    final cache = DefaultCacheManager();
    final fileId = privateFileId(url);
    final storage = _storage;
    if (fileId == null || storage == null) {
      return (await cache.getSingleFile(url)).readAsBytes();
    }
    final hit = await cache.getFileFromCache(url);
    if (hit != null) return hit.file.readAsBytes();
    final data = await storage.getFileView(bucketId: AppwriteConfig.userUploadsBucket, fileId: fileId);
    await cache.putFile(url, data, fileExtension: 'jpg', maxAge: const Duration(days: 30));
    return data;
  }
}
