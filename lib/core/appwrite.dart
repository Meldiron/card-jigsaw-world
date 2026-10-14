import 'package:appwrite/appwrite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Central Appwrite configuration for Card Jigsaw World.
class AppwriteConfig {
  static const endpoint = 'https://fra.cloud.appwrite.io/v1';
  static const projectId = '6acb4de5003e38d5ebd9';
  static const databaseId = 'cjw';

  // Tables
  static const profiles = 'profiles';
  static const packs = 'packs';
  static const puzzles = 'puzzles';
  static const progress = 'progress';
  static const events = 'events';
  static const eventProgress = 'event_progress';
  static const friends = 'friends';

  /// Player reports (Player > Report): rows only the server reads (`tools/dev/reports.py`).
  static const reports = 'reports';

  /// Players a player blocked (Player > Block): left out of their leaderboard; rows only they read.
  static const blocks = 'blocks';
  static const ledger = 'ledger';
  static const myPuzzles = 'my_puzzles';
  static const meta = 'meta';

  /// Row in [meta] naming the newest catalogue snapshot file in [catalogBucket].
  static const catalogPointer = 'catalog';

  // Buckets
  static const puzzleImagesBucket = 'puzzle-images';
  static const userUploadsBucket = 'user-uploads';
  static const catalogBucket = 'catalog';

  /// Pictures of private packs (hidden packs opened with a pack code): each file is readable only by
  /// the players who claimed one of its pack's codes (function `redeem-code`), fetched like player
  /// photos through the signed-in client (`ImageFiles`).
  static const privatePacksBucket = 'private-packs';

  /// View URL of a file. Public files load from it directly; private player photos are fetched
  /// through the signed-in client under this URL (`ImageFiles`).
  static String fileViewUrl(String bucketId, String fileId) =>
      '$endpoint/storage/buckets/$bucketId/files/$fileId/view?project=$projectId';

  /// Preview URL (server-side resized) – handy for thumbnails.
  static String filePreviewUrl(String bucketId, String fileId,
          {int width = 400, int quality = 80}) =>
      '$endpoint/storage/buckets/$bucketId/files/$fileId/preview?project=$projectId&width=$width&quality=$quality&output=webp';
}

final appwriteClientProvider = Provider<Client>((ref) {
  return Client()
      .setEndpoint(AppwriteConfig.endpoint)
      .setProject(AppwriteConfig.projectId);
});

final accountProvider = Provider<Account>((ref) => Account(ref.watch(appwriteClientProvider)));
final tablesProvider = Provider<TablesDB>((ref) => TablesDB(ref.watch(appwriteClientProvider)));
final storageProvider = Provider<Storage>((ref) => Storage(ref.watch(appwriteClientProvider)));
