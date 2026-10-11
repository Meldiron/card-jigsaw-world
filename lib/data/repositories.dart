import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as enums;
import 'package:appwrite/models.dart' as models;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/appwrite.dart';
import '../models/models.dart';
import 'web_redirect.dart' as web_redirect;

const _db = AppwriteConfig.databaseId;

String deterministicId(String a, String b) => md5.convert(utf8.encode('$a:$b')).toString();

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------
class AuthRepository {
  AuthRepository(this._account);
  final Account _account;

  Future<models.User?> currentUser() async {
    try {
      return await _account.get();
    } on AppwriteException catch (e) {
      if (e.code == 401) return null;
      rethrow;
    }
  }

  Future<models.User> signInAnonymously() async {
    await _account.createAnonymousSession();
    return _account.get();
  }

  Future<models.User> signUp({required String email, required String password, required String name}) async {
    await _account.create(userId: ID.unique(), email: email, password: password, name: name);
    await _account.createEmailPasswordSession(email: email, password: password);
    return _account.get();
  }

  /// Converts the current anonymous session into a permanent account.
  Future<models.User> linkAnonymous({required String email, required String password, required String name}) async {
    await _account.updateEmail(email: email, password: password);
    if (name.trim().isNotEmpty) await _account.updateName(name: name.trim());
    return _account.get();
  }

  Future<models.User> signIn({required String email, required String password}) async {
    await _account.createEmailPasswordSession(email: email, password: password);
    return _account.get();
  }

  /// Exchanges an Apple ID token obtained on device for an Appwrite session.
  /// [nonce] is the raw (unhashed) nonce whose SHA-256 was handed to Apple.
  /// When a session already exists (a guest), Appwrite links the Apple identity
  /// to that user instead of creating a new one, so progress carries over.
  /// Returns the signed-in user and whether an existing account was used
  /// instead of the current guest.
  Future<({models.User user, bool switched})> signInWithAppleIdToken({required String idToken, required String nonce, String? name}) async {
    final cleanName = (name == null || name.trim().isEmpty) ? null : name.trim();
    try {
      await _account.createIdTokenSession(provider: enums.IdTokenProvider.apple, idToken: idToken, nonce: nonce, name: cleanName);
      return (user: await _account.get(), switched: false);
    } on AppwriteException catch (e) {
      // 409: this Apple ID already belongs to another account, so it cannot be
      // linked to the current guest. Drop the guest session and sign in to the
      // existing account instead; that is what a returning player expects.
      if (e.code != 409) rethrow;
      await signOut();
      await _account.createIdTokenSession(provider: enums.IdTokenProvider.apple, idToken: idToken, nonce: nonce, name: cleanName);
      return (user: await _account.get(), switched: true);
    }
  }

  /// Web: leaves the page for the provider's sign-in and comes back to
  /// [success] with `userId` and `secret` in the query (or to [failure]).
  /// This is Appwrite's OAuth token flow in a full-page redirect rather than
  /// the SDK's popup, so it works without third-party cookies: the session
  /// is created afterwards with [createSessionFromToken], whose response
  /// carries the fallback cookie the browser SDK stores. An active guest
  /// session is linked to the identity when the browser sends its cookie;
  /// if the identity already belongs to another user Appwrite redirects to
  /// [failure] (user_already_exists) and the caller drops the guest session
  /// and redirects again.
  void signInWithOAuthRedirect({required enums.OAuthProvider provider, required String success, required String failure}) {
    final url = Uri.parse('${AppwriteConfig.endpoint}/account/tokens/oauth2/${provider.value}').replace(queryParameters: {
      'project': AppwriteConfig.projectId,
      'success': success,
      'failure': failure,
    });
    web_redirect.navigateTo(url.toString());
  }

  /// Second half of the redirect flow: turns the returned token into a session.
  Future<models.User> createSessionFromToken({required String userId, required String secret}) async {
    await _account.createSession(userId: userId, secret: secret);
    return _account.get();
  }

  Future<void> signOut() async {
    try {
      await _account.deleteSession(sessionId: 'current');
    } on AppwriteException catch (e) {
      if (e.code != 401) rethrow;
    }
  }

  Future<void> updateName(String name) => _account.updateName(name: name);
  Future<void> updatePrefs(Map<String, dynamic> prefs) => _account.updatePrefs(prefs: prefs);
}

// ---------------------------------------------------------------------------
// Profile + economy
// ---------------------------------------------------------------------------
class ProfileRepository {
  ProfileRepository(this._tables);
  final TablesDB _tables;

  Future<Profile?> fetch(String userId) async {
    try {
      final row = await _tables.getRow(databaseId: _db, tableId: AppwriteConfig.profiles, rowId: userId);
      return Profile.fromRow(row.$id, row.data);
    } on AppwriteException catch (e) {
      if (e.code == 404) return null;
      rethrow;
    }
  }

  Future<Profile> create(String userId, {String? name}) async {
    final p = Profile.guest(userId).copyWith(displayName: name?.trim().isNotEmpty == true ? name!.trim() : 'Player');
    final row = await _tables.createRow(
      databaseId: _db,
      tableId: AppwriteConfig.profiles,
      rowId: userId,
      data: p.toData(),
      permissions: [
        Permission.read(Role.any()),
        Permission.update(Role.user(userId)),
        Permission.delete(Role.user(userId)),
      ],
    );
    return Profile.fromRow(row.$id, row.data);
  }

  Future<Profile> fetchOrCreate(String userId, {String? name}) async =>
      (await fetch(userId)) ?? await create(userId, name: name);

  /// The profile with its last-written time (for the save merge).
  Future<({Profile profile, DateTime? updatedAt})?> fetchWithMeta(String userId) async {
    try {
      final row = await _tables.getRow(databaseId: _db, tableId: AppwriteConfig.profiles, rowId: userId);
      return (profile: Profile.fromRow(row.$id, row.data), updatedAt: DateTime.tryParse(row.$updatedAt));
    } on AppwriteException catch (e) {
      if (e.code == 404) return null;
      rethrow;
    }
  }

  Future<Profile> update(String userId, Map<String, dynamic> patch) async {
    final row = await _tables.updateRow(databaseId: _db, tableId: AppwriteConfig.profiles, rowId: userId, data: patch);
    return Profile.fromRow(row.$id, row.data);
  }

  Future<Profile?> findByUserId(String userId) => fetch(userId);

  Future<List<Profile>> leaderboard({int limit = 50}) async {
    final res = await _tables.listRows(
      databaseId: _db,
      tableId: AppwriteConfig.profiles,
      queries: [Query.greaterThan('puzzlesCompleted', 0), Query.orderDesc('xp'), Query.limit(limit)],
    );
    return res.rows.map((r) => Profile.fromRow(r.$id, r.data)).toList();
  }

  /// How many ledger entries the player has with [reason] (e.g. `peek`).
  Future<int> ledgerCount(String userId, String reason) async {
    final res = await _tables.listRows(
      databaseId: _db,
      tableId: AppwriteConfig.ledger,
      queries: [Query.equal('userId', userId), Query.equal('reason', reason), Query.limit(1), Query.select(['\$id'])],
    );
    return res.total;
  }

  Future<void> logLedger(String userId, {required int amount, required String currency, required String reason, int? balanceAfter}) async {
    try {
      await _tables.createRow(
        databaseId: _db,
        tableId: AppwriteConfig.ledger,
        rowId: ID.unique(),
        data: {'userId': userId, 'amount': amount, 'currency': currency, 'reason': reason, 'balanceAfter': balanceAfter},
        permissions: [Permission.read(Role.user(userId))],
      );
    } catch (e) {
      debugPrint('ledger failed: $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Catalog (packs, puzzles, events)
// ---------------------------------------------------------------------------
class CatalogRepository {
  CatalogRepository(this._tables);
  final TablesDB _tables;

  Future<List<Pack>> packs() async {
    final res = await _tables.listRows(
      databaseId: _db,
      tableId: AppwriteConfig.packs,
      queries: [Query.orderAsc('sortOrder'), Query.limit(200)],
    );
    return res.rows.map((r) => Pack.fromRow(r.$id, r.data)).toList();
  }

  Future<List<Puzzle>> puzzles(String packId) async {
    final res = await _tables.listRows(
      databaseId: _db,
      tableId: AppwriteConfig.puzzles,
      queries: [Query.equal('packId', packId), Query.orderAsc('sortOrder'), Query.limit(200)],
    );
    return res.rows.map((r) => Puzzle.fromRow(r.$id, r.data)).toList();
  }

  /// Loads the whole catalog (featured packs + every daily puzzle) in pages.
  Future<List<Puzzle>> allPuzzles() async {
    final out = <Puzzle>[];
    String? cursor;
    while (true) {
      final res = await _tables.listRows(
        databaseId: _db,
        tableId: AppwriteConfig.puzzles,
        queries: [Query.orderAsc('\$id'), Query.limit(500), if (cursor != null) Query.cursorAfter(cursor)],
      );
      out.addAll(res.rows.map((r) => Puzzle.fromRow(r.$id, r.data)));
      if (res.rows.length < 500) break;
      cursor = res.rows.last.$id;
    }
    out.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return out;
  }

  Future<Puzzle?> puzzle(String id) async {
    try {
      final row = await _tables.getRow(databaseId: _db, tableId: AppwriteConfig.puzzles, rowId: id);
      return Puzzle.fromRow(row.$id, row.data);
    } on AppwriteException catch (e) {
      if (e.code == 404) return null;
      rethrow;
    }
  }

  Future<List<GameEvent>> events() async {
    final res = await _tables.listRows(
      databaseId: _db,
      tableId: AppwriteConfig.events,
      queries: [Query.orderAsc('endAt'), Query.limit(50)],
    );
    return res.rows.map((r) => GameEvent.fromRow(r.$id, r.data)).toList();
  }
}

// ---------------------------------------------------------------------------
// Progress
// ---------------------------------------------------------------------------
class ProgressRepository {
  ProgressRepository(this._tables);
  final TablesDB _tables;

  Future<List<PuzzleProgress>> forUser(String userId) async {
    final res = await _tables.listRows(
      databaseId: _db,
      tableId: AppwriteConfig.progress,
      queries: [Query.equal('userId', userId), Query.limit(500)],
    );
    return res.rows.map((r) => PuzzleProgress.fromRow(r.$id, r.data)).toList();
  }

  /// Every row with its last-written time (for the save merge).
  Future<List<({PuzzleProgress row, DateTime? updatedAt})>> forUserWithMeta(String userId) async {
    final out = <({PuzzleProgress row, DateTime? updatedAt})>[];
    String? cursor;
    while (true) {
      final res = await _tables.listRows(
        databaseId: _db,
        tableId: AppwriteConfig.progress,
        queries: [Query.equal('userId', userId), Query.orderAsc('\$id'), Query.limit(500), if (cursor != null) Query.cursorAfter(cursor)],
      );
      out.addAll(res.rows.map((r) => (row: PuzzleProgress.fromRow(r.$id, r.data), updatedAt: DateTime.tryParse(r.$updatedAt))));
      if (res.rows.length < 500) break;
      cursor = res.rows.last.$id;
    }
    return out;
  }

  Future<PuzzleProgress> upsert(String userId, String puzzleId, Map<String, dynamic> data) async {
    final id = deterministicId(userId, puzzleId);
    final row = await _tables.upsertRow(
      databaseId: _db,
      tableId: AppwriteConfig.progress,
      rowId: id,
      data: {'userId': userId, 'puzzleId': puzzleId, ...data},
      permissions: [
        Permission.read(Role.user(userId)),
        Permission.update(Role.user(userId)),
        Permission.delete(Role.user(userId)),
      ],
    );
    return PuzzleProgress.fromRow(row.$id, row.data);
  }
}

// ---------------------------------------------------------------------------
// Social: friends + event progress
// ---------------------------------------------------------------------------
class SocialRepository {
  SocialRepository(this._tables);
  final TablesDB _tables;

  Future<List<Friend>> friends(String userId) async {
    final res = await _tables.listRows(
      databaseId: _db,
      tableId: AppwriteConfig.friends,
      queries: [Query.equal('userId', userId), Query.limit(200)],
    );
    return res.rows.map((r) => Friend.fromRow(r.$id, r.data)).toList();
  }

  Future<Friend> addFriend(String userId, Profile friend) async {
    final row = await _tables.upsertRow(
      databaseId: _db,
      tableId: AppwriteConfig.friends,
      rowId: deterministicId(userId, friend.userId),
      data: {
        'userId': userId,
        'friendId': friend.userId,
        'friendName': friend.displayName,
        'friendAvatar': friend.avatar,
        'status': 'accepted',
      },
      permissions: [Permission.read(Role.user(userId)), Permission.update(Role.user(userId)), Permission.delete(Role.user(userId))],
    );
    return Friend.fromRow(row.$id, row.data);
  }

  Future<void> removeFriend(String rowId) =>
      _tables.deleteRow(databaseId: _db, tableId: AppwriteConfig.friends, rowId: rowId);

  Future<Map<String, EventProgress>> eventProgress(String userId) async {
    final res = await _tables.listRows(
      databaseId: _db,
      tableId: AppwriteConfig.eventProgress,
      queries: [Query.equal('userId', userId), Query.limit(100)],
    );
    return {for (final r in res.rows) r.data['eventId'].toString(): EventProgress.fromRow(r.$id, r.data)};
  }

  /// Community progress is the sum of every player's progress on this event.
  Future<int> communityProgress(String eventId) async {
    try {
      final res = await _tables.listRows(
        databaseId: _db,
        tableId: AppwriteConfig.eventProgress,
        queries: [Query.equal('eventId', eventId), Query.limit(1000), Query.select(['progress'])],
      );
      return res.rows.fold<int>(0, (sum, r) => sum + ((r.data['progress'] as num?)?.toInt() ?? 0));
    } catch (e) {
      debugPrint('communityProgress failed: $e');
      return 0;
    }
  }

  Future<EventProgress> upsertEventProgress(String userId, String eventId, {required int progress, bool claimed = false}) async {
    final row = await _tables.upsertRow(
      databaseId: _db,
      tableId: AppwriteConfig.eventProgress,
      rowId: deterministicId(userId, eventId),
      data: {'userId': userId, 'eventId': eventId, 'progress': progress, 'claimed': claimed},
      permissions: [Permission.read(Role.users()), Permission.update(Role.user(userId)), Permission.delete(Role.user(userId))],
    );
    return EventProgress.fromRow(row.$id, row.data);
  }
}

// ---------------------------------------------------------------------------
// User uploads (My Puzzles)
// ---------------------------------------------------------------------------
class UploadRepository {
  UploadRepository(this._storage, this._tables);
  final Storage _storage;
  final TablesDB _tables;

  Future<List<MyPuzzle>> list(String userId) async {
    final res = await _tables.listRows(
      databaseId: _db,
      tableId: AppwriteConfig.myPuzzles,
      queries: [Query.equal('userId', userId), Query.orderDesc('\$createdAt'), Query.limit(100)],
    );
    return res.rows.map((r) => MyPuzzle.fromRow(r.$id, r.data)).toList();
  }

  Future<MyPuzzle> upload(String userId, {required Uint8List bytes, required String filename, String? title}) async {
    final file = await _storage.createFile(
      bucketId: AppwriteConfig.userUploadsBucket,
      fileId: ID.unique(),
      file: InputFile.fromBytes(bytes: bytes, filename: filename),
      permissions: [Permission.read(Role.any()), Permission.delete(Role.user(userId))],
    );
    final row = await _tables.createRow(
      databaseId: _db,
      tableId: AppwriteConfig.myPuzzles,
      rowId: ID.unique(),
      data: {'userId': userId, 'fileId': file.$id, 'title': title ?? 'My photo'},
      permissions: [Permission.read(Role.user(userId)), Permission.update(Role.user(userId)), Permission.delete(Role.user(userId))],
    );
    return MyPuzzle.fromRow(row.$id, row.data);
  }

  Future<void> delete(MyPuzzle p) async {
    try {
      await _storage.deleteFile(bucketId: AppwriteConfig.userUploadsBucket, fileId: p.fileId);
    } catch (_) {}
    await _tables.deleteRow(databaseId: _db, tableId: AppwriteConfig.myPuzzles, rowId: p.id);
  }

  static String imageUrl(String fileId) => AppwriteConfig.fileViewUrl(AppwriteConfig.userUploadsBucket, fileId);
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final authRepositoryProvider = Provider((ref) => AuthRepository(ref.watch(accountProvider)));
final profileRepositoryProvider = Provider((ref) => ProfileRepository(ref.watch(tablesProvider)));
final catalogRepositoryProvider = Provider((ref) => CatalogRepository(ref.watch(tablesProvider)));
final progressRepositoryProvider = Provider((ref) => ProgressRepository(ref.watch(tablesProvider)));
final socialRepositoryProvider = Provider((ref) => SocialRepository(ref.watch(tablesProvider)));
final uploadRepositoryProvider = Provider((ref) => UploadRepository(ref.watch(storageProvider), ref.watch(tablesProvider)));
