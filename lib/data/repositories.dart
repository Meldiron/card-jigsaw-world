import 'dart:convert';
import 'dart:math' show min;

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as enums;
import 'package:appwrite/models.dart' as models;
import 'package:archive/archive.dart' show GZipDecoder;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/appwrite.dart';
import '../core/qa.dart';
import '../models/models.dart';
import 'web_redirect.dart' as web_redirect;

/// Every row matching [queries], read page by page with cursor pagination, so no list is ever cut
/// at one page. Ordering queries in [queries] apply across pages.
Future<List<models.Row>> listAllRows(TablesDB tables, String tableId, List<String> queries, {int pageSize = 500}) async {
  final out = <models.Row>[];
  String? cursor;
  while (true) {
    final res = await tables.listRows(
      databaseId: AppwriteConfig.databaseId,
      tableId: tableId,
      queries: [...queries, Query.limit(pageSize), if (cursor != null) Query.cursorAfter(cursor)],
      total: false,
    );
    out.addAll(res.rows);
    if (res.rows.length < pageSize) break;
    cursor = res.rows.last.$id;
  }
  return out;
}

/// One page of rows after the row id [after] (cursor pagination), for lists that scroll.
Future<List<models.Row>> listRowsPage(TablesDB tables, String tableId, List<String> queries, {required int limit, String? after}) async {
  final res = await tables.listRows(
    databaseId: AppwriteConfig.databaseId,
    tableId: tableId,
    queries: [...queries, Query.limit(limit), if (after != null) Query.cursorAfter(after)],
    total: false,
  );
  return res.rows;
}

/// How many rows match [queries] (Appwrite counts them; no rows are transferred).
Future<int> countRows(TablesDB tables, String tableId, List<String> queries) async {
  final res = await tables.listRows(databaseId: AppwriteConfig.databaseId, tableId: tableId, queries: [...queries, Query.limit(1), Query.select(['\$id'])]);
  return res.total;
}

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
    return markQaGuest(await _account.get());
  }

  /// QA builds (`CJW_QA`) write the test-player prefs on the guest they play, so the purge tool
  /// finds it even when its profile row never got written (see [QaRun]). Accounts with an email or
  /// phone are never marked, and release builds do nothing here.
  Future<models.User> markQaGuest(models.User user) async {
    if (!QaRun.enabled || user.email.isNotEmpty || user.phone.isNotEmpty) return user;
    final prefs = Map<String, dynamic>.from(user.prefs.data);
    if (!QaRun.needsPrefs(prefs)) return user;
    try {
      await _account.updatePrefs(prefs: QaRun.markedPrefs(prefs));
      return await _account.get();
    } catch (e) {
      debugPrint('QA mark failed: $e');
      return user;
    }
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
      // 401: no session; 404: the user (and so the session) was deleted.
      if (e.code != 401 && e.code != 404) rethrow;
    }
  }

  /// Whether the signed-in player signed in with Apple (their tokens are revoked on deletion).
  Future<bool> hasAppleIdentity() async {
    try {
      final list = await _account.listIdentities();
      return list.identities.any((i) => i.provider == 'apple');
    } on AppwriteException catch (e) {
      debugPrint('identities failed: ${e.message}');
      return false;
    }
  }

  Future<void> updateName(String name) => _account.updateName(name: name);
  Future<void> updatePrefs(Map<String, dynamic> prefs) => _account.updatePrefs(prefs: prefs);
}

/// What the `delete-account` function removed.
class AccountDeletionResult {
  const AccountDeletionResult({required this.files, required this.rows, required this.apple});
  final int files;
  final Map<String, int> rows;

  /// `revoked`, `not-apple`, or why the Apple tokens were not revoked (`skipped:no-key`, ...).
  final String apple;
}

/// Deletes the signed-in player's account on the server: the `delete-account` Appwrite Function
/// (functions/delete-account) removes their photos, their rows in every player table, the profile
/// and the user, and revokes their Sign in with Apple tokens when [appleAuthorizationCode] is
/// given. Only the caller's own account can go: the function reads the user from the session.
class AccountDeletionRepository {
  AccountDeletionRepository(this._functions);
  final Functions _functions;

  static const functionId = 'delete-account';

  Future<AccountDeletionResult> delete({String? appleAuthorizationCode}) async {
    final exec = await _functions.createExecution(
      functionId: functionId,
      body: jsonEncode({'appleAuthorizationCode': ?appleAuthorizationCode}),
      method: enums.ExecutionMethod.pOST,
      path: '/delete',
    );
    final body = exec.responseBody.isEmpty ? <String, dynamic>{} : jsonDecode(exec.responseBody) as Map<String, dynamic>;
    if (body['ok'] != true) {
      throw AppwriteException(body['error']?.toString() ?? 'Account deletion failed (${exec.responseStatusCode})', exec.responseStatusCode);
    }
    final rows = <String, int>{for (final e in ((body['rows'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num?)?.toInt() ?? 0};
    return AccountDeletionResult(files: (body['files'] as num?)?.toInt() ?? 0, rows: rows, apple: '${body['apple'] ?? ''}');
  }
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

  /// Creates the player's profile row. [isTest] marks a QA run's guest (kept out of the league).
  Future<Profile> create(String userId, {String? name, bool isTest = false}) async {
    final p = Profile.guest(userId).copyWith(displayName: name?.trim().isNotEmpty == true ? name!.trim() : 'Player', isTest: isTest);
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

  Future<Profile> fetchOrCreate(String userId, {String? name, bool isTest = false}) async =>
      (await fetch(userId)) ?? await create(userId, name: name, isTest: isTest);

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

  /// Who is in the league: players with a solved puzzle, never QA test players ([Profile.isTest]),
  /// filtered on the server for the list and both counts. A test player looking at the league
  /// (a QA run) still finds its own row, so its screenshots read like a real player's; nobody
  /// else ever sees it.
  static List<String> leagueQueries({Profile? viewer}) => [
        Query.greaterThan('puzzlesCompleted', 0),
        if (viewer != null && viewer.isTest)
          Query.or([Query.equal('isTest', false), Query.equal('\$id', viewer.id)])
        else
          Query.equal('isTest', false),
      ];

  /// Blocked players left out on the server, one `notEqual` each (Appwrite takes at most 100 queries
  /// a request); any beyond are left out of the page on the device.
  static const maxServerExclusions = 90;

  /// One page of the league (most XP first) after the row [after], as [viewer] sees it, without the
  /// players in [excluding] (the viewer's blocked players).
  Future<({List<Profile> items, String? lastId})> leaderboardPage({required int limit, String? after, Profile? viewer, Set<String> excluding = const {}}) async {
    final rows = await listRowsPage(
      _tables,
      AppwriteConfig.profiles,
      [
        ...leagueQueries(viewer: viewer),
        for (final id in excluding.take(maxServerExclusions)) Query.notEqual('\$id', id),
        Query.orderDesc('xp'),
      ],
      limit: limit,
      after: after,
    );
    return (
      items: [for (final r in rows) if (!excluding.contains(r.$id)) Profile.fromRow(r.$id, r.data)],
      lastId: rows.isEmpty ? null : rows.last.$id,
    );
  }

  /// League size and the player's place in it, counted on the server (the list itself pages).
  Future<({int rank, int total})> leaderboardRank(Profile me) async {
    final league = leagueQueries(viewer: me);
    final total = await countRows(_tables, AppwriteConfig.profiles, league);
    final ahead = await countRows(_tables, AppwriteConfig.profiles, [...league, Query.greaterThan('xp', me.xp)]);
    return (rank: ahead + 1, total: total);
  }

  /// Quests the player has claimed, from the ledger (one `goal:<key>` entry per reward currency),
  /// counted once per quest key.
  Future<int> questClaims(String userId) async {
    final rows = await listAllRows(_tables, AppwriteConfig.ledger, [Query.equal('userId', userId), Query.startsWith('reason', 'goal:'), Query.select(['\$id', 'reason'])]);
    return {for (final r in rows) r.data['reason']}.length;
  }

  /// How many ledger entries the player has with [reason] (e.g. `peek`).
  Future<int> ledgerCount(String userId, String reason) async {
    return countRows(_tables, AppwriteConfig.ledger, [Query.equal('userId', userId), Query.equal('reason', reason)]);
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
class CatalogRepository implements CatalogSource {
  CatalogRepository(this._tables, this._storage);
  final TablesDB _tables;
  final Storage _storage;

  /// Appwrite takes at most 100 values in one `equal` query.
  static const _maxQueryValues = 100;

  Future<List<Map<String, dynamic>>> _rows(String tableId, List<String> queries) async =>
      [for (final r in await listAllRows(_tables, tableId, [...queries, Query.orderAsc('\$id')])) r.data];

  @override
  Future<Map<String, dynamic>?> snapshot() async {
    final models.Row pointer;
    try {
      pointer = await _tables.getRow(databaseId: _db, tableId: AppwriteConfig.meta, rowId: AppwriteConfig.catalogPointer);
    } on AppwriteException catch (e) {
      if (e.code == 404) return null;
      rethrow;
    }
    final bytes = await _storage.getFileDownload(bucketId: AppwriteConfig.catalogBucket, fileId: '${pointer.data['fileId']}');
    return jsonDecode(utf8.decode(const GZipDecoder().decodeBytes(bytes))) as Map<String, dynamic>;
  }

  @override
  Future<List<Map<String, dynamic>>> rows(String tableId) => _rows(tableId, const []);

  @override
  Future<List<Map<String, dynamic>>> rowsSince(String tableId, String updatedAt) => _rows(tableId, [Query.greaterThanEqual('\$updatedAt', updatedAt)]);

  @override
  Future<List<Map<String, dynamic>>> puzzleRowsOfPacks(List<String> packIds) async => [
        for (var i = 0; i < packIds.length; i += _maxQueryValues)
          ...await _rows(AppwriteConfig.puzzles, [Query.equal('packId', packIds.sublist(i, min(i + _maxQueryValues, packIds.length)))]),
      ];
}

/// Where [CatalogSync] gets the catalogue: the daily snapshot file and the tables (rows as maps with
/// `$id` and `$updatedAt`).
abstract interface class CatalogSource {
  /// The newest snapshot (`functions/catalog-snapshot`), decoded; null when there is none yet.
  Future<Map<String, dynamic>?> snapshot();

  /// Every row of [tableId], in pages.
  Future<List<Map<String, dynamic>>> rows(String tableId);

  /// Rows of [tableId] created or updated at or after [updatedAt] (server time, ISO 8601).
  Future<List<Map<String, dynamic>>> rowsSince(String tableId, String updatedAt);

  /// Every puzzle row of the packs [packIds].
  Future<List<Map<String, dynamic>>> puzzleRowsOfPacks(List<String> packIds);
}

// ---------------------------------------------------------------------------
// Progress
// ---------------------------------------------------------------------------
class ProgressRepository {
  ProgressRepository(this._tables);
  final TablesDB _tables;

  Future<List<PuzzleProgress>> forUser(String userId) async {
    final rows = await listAllRows(_tables, AppwriteConfig.progress, [Query.equal('userId', userId)]);
    return rows.map((r) => PuzzleProgress.fromRow(r.$id, r.data)).toList();
  }

  /// Every row with its last-written time (for the save merge).
  Future<List<({PuzzleProgress row, DateTime? updatedAt})>> forUserWithMeta(String userId) async {
    final rows = await listAllRows(_tables, AppwriteConfig.progress, [Query.equal('userId', userId)]);
    return [for (final r in rows) (row: PuzzleProgress.fromRow(r.$id, r.data), updatedAt: DateTime.tryParse(r.$updatedAt))];
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
    final rows = await listAllRows(_tables, AppwriteConfig.friends, [Query.equal('userId', userId), Query.orderDesc('\$createdAt')]);
    return rows.map((r) => Friend.fromRow(r.$id, r.data)).toList();
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

  /// The friend row [userId] keeps for [friendId], if any (rows have a deterministic id).
  String friendRowId(String userId, String friendId) => deterministicId(userId, friendId);

  /// Reports [player] for [reason]. The row carries no permissions: only the server reads it.
  Future<void> report({required String reporterId, required Profile player, required ReportReason reason}) async {
    await _tables.createRow(
      databaseId: _db,
      tableId: AppwriteConfig.reports,
      rowId: ID.unique(),
      data: {'reporterId': reporterId, 'reportedId': player.userId, 'reportedName': player.displayName, 'reason': reason.code},
      permissions: const [],
    );
  }

  Future<List<BlockedPlayer>> blocks(String userId) async {
    final rows = await listAllRows(_tables, AppwriteConfig.blocks, [Query.equal('blockerId', userId), Query.orderDesc('\$createdAt')]);
    return rows.map((r) => BlockedPlayer.fromRow(r.$id, r.data)).toList();
  }

  Future<void> block(String userId, Profile player) async {
    await _tables.upsertRow(
      databaseId: _db,
      tableId: AppwriteConfig.blocks,
      rowId: deterministicId(userId, player.userId),
      data: {'blockerId': userId, 'blockedId': player.userId, 'blockedName': player.displayName, 'blockedAvatar': player.avatar},
      permissions: [Permission.read(Role.user(userId)), Permission.update(Role.user(userId)), Permission.delete(Role.user(userId))],
    );
  }

  Future<void> unblock(String rowId) => _tables.deleteRow(databaseId: _db, tableId: AppwriteConfig.blocks, rowId: rowId);

  Future<Map<String, EventProgress>> eventProgress(String userId) async {
    final rows = await listAllRows(_tables, AppwriteConfig.eventProgress, [Query.equal('userId', userId)]);
    return {for (final r in rows) r.data['eventId'].toString(): EventProgress.fromRow(r.$id, r.data)};
  }

  /// Community progress is the sum of every player's progress on this event.
  Future<int> communityProgress(String eventId) async {
    try {
      final rows = await listAllRows(_tables, AppwriteConfig.eventProgress, [Query.equal('eventId', eventId), Query.select(['\$id', 'progress'])], pageSize: 1000);
      return rows.fold<int>(0, (sum, r) => sum + ((r.data['progress'] as num?)?.toInt() ?? 0));
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

  /// One page of the player's photos, newest first, after the row [after].
  Future<({List<MyPuzzle> items, String? lastId})> page(String userId, {required int limit, String? after}) async {
    final rows = await listRowsPage(_tables, AppwriteConfig.myPuzzles, [Query.equal('userId', userId), Query.orderDesc('\$createdAt')], limit: limit, after: after);
    return (items: rows.map((r) => MyPuzzle.fromRow(r.$id, r.data)).toList(), lastId: rows.isEmpty ? null : rows.last.$id);
  }

  /// How many photos the player keeps (counted on the server).
  Future<int> count(String userId) => countRows(_tables, AppwriteConfig.myPuzzles, [Query.equal('userId', userId)]);

  /// One photo by id (a puzzle in progress may be older than the pages loaded so far).
  Future<MyPuzzle?> byId(String id) async {
    try {
      final row = await _tables.getRow(databaseId: _db, tableId: AppwriteConfig.myPuzzles, rowId: id);
      return MyPuzzle.fromRow(row.$id, row.data);
    } on AppwriteException catch (e) {
      if (e.code == 404) return null;
      rethrow;
    }
  }

  Future<MyPuzzle> upload(String userId, {required Uint8List bytes, required String filename, String? title}) async {
    final file = await _storage.createFile(
      bucketId: AppwriteConfig.userUploadsBucket,
      fileId: ID.unique(),
      file: InputFile.fromBytes(bytes: bytes, filename: filename),
      // Private to the uploader: other players cannot read or list it (see ImageFiles).
      permissions: [Permission.read(Role.user(userId)), Permission.delete(Role.user(userId))],
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
final catalogRepositoryProvider = Provider((ref) => CatalogRepository(ref.watch(tablesProvider), ref.watch(storageProvider)));
final progressRepositoryProvider = Provider((ref) => ProgressRepository(ref.watch(tablesProvider)));
final socialRepositoryProvider = Provider((ref) => SocialRepository(ref.watch(tablesProvider)));
final uploadRepositoryProvider = Provider((ref) => UploadRepository(ref.watch(storageProvider), ref.watch(tablesProvider)));
final accountDeletionRepositoryProvider = Provider((ref) => AccountDeletionRepository(Functions(ref.watch(appwriteClientProvider))));
