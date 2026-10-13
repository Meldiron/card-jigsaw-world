import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/appwrite.dart';
import '../repositories.dart';

/// The rows the save sync reads and writes. Row maps carry the table columns plus `$id` and
/// `$updatedAt`. [AppwriteSyncBackend] talks to Appwrite; tests use an in-memory server.
abstract class SyncBackend {
  /// The profile row, or null when it does not exist yet.
  Future<Map<String, dynamic>?> getProfile(String userId);
  Future<Map<String, dynamic>> createProfile(String userId, Map<String, dynamic> data);

  /// Applies [data] (plain values and atomic operators) and returns the row as it is now.
  Future<Map<String, dynamic>> updateProfile(String userId, Map<String, dynamic> data);

  /// Every progress row of the player, or only rows written at or after [since] (server time).
  Future<List<Map<String, dynamic>>> progressRows(String userId, {String? since});
  Future<Map<String, dynamic>?> getProgress(String userId, String puzzleId);
  Future<Map<String, dynamic>> upsertProgress(String userId, String puzzleId, Map<String, dynamic> data);
  Future<void> upsertEvent(String userId, String eventId, Map<String, dynamic> data);
  Future<Map<String, dynamic>?> getEvent(String userId, String eventId);

  /// Creates a ledger row with a fixed id; an existing row with that id counts as written.
  Future<void> createLedger(String userId, String rowId, Map<String, dynamic> data);
}

/// How a failed request is handled.
enum SyncFailure {
  /// No answer (offline, timeout, server busy): try again later; the server may have applied it.
  offline,

  /// The session is gone: check the sign-in, then try again.
  auth,

  /// The row does not exist.
  missing,

  /// The server refused the data; sending it again would fail the same way.
  rejected,
}

SyncFailure classifyFailure(Object e) {
  if (e is AppwriteException) {
    final c = e.code ?? 0;
    if (c == 0 || c == 408 || c == 429 || c >= 500) return SyncFailure.offline;
    if (c == 401) return SyncFailure.auth;
    if (c == 404) return SyncFailure.missing;
    return SyncFailure.rejected;
  }
  return SyncFailure.offline;
}

Map<String, dynamic> _row(models.Row r) => {...r.data, '\$id': r.$id, '\$updatedAt': r.$updatedAt};

class AppwriteSyncBackend implements SyncBackend {
  AppwriteSyncBackend(this._tables);
  final TablesDB _tables;
  static const _db = AppwriteConfig.databaseId;

  @override
  Future<Map<String, dynamic>?> getProfile(String userId) async {
    try {
      return _row(await _tables.getRow(databaseId: _db, tableId: AppwriteConfig.profiles, rowId: userId));
    } on AppwriteException catch (e) {
      if (e.code == 404) return null;
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> createProfile(String userId, Map<String, dynamic> data) async {
    try {
      return _row(await _tables.createRow(
        databaseId: _db,
        tableId: AppwriteConfig.profiles,
        rowId: userId,
        data: data,
        permissions: [Permission.read(Role.any()), Permission.update(Role.user(userId)), Permission.delete(Role.user(userId))],
      ));
    } on AppwriteException catch (e) {
      // Created meanwhile (another device, or an earlier try whose answer was lost).
      if (e.code == 409) return (await getProfile(userId))!;
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> updateProfile(String userId, Map<String, dynamic> data) async =>
      _row(await _tables.updateRow(databaseId: _db, tableId: AppwriteConfig.profiles, rowId: userId, data: data));

  @override
  Future<List<Map<String, dynamic>>> progressRows(String userId, {String? since}) async {
    final rows = await listAllRows(_tables, AppwriteConfig.progress, [
      Query.equal('userId', userId),
      if (since != null) Query.greaterThanEqual('\$updatedAt', since),
    ]);
    return [for (final r in rows) _row(r)];
  }

  @override
  Future<Map<String, dynamic>?> getProgress(String userId, String puzzleId) async {
    try {
      return _row(await _tables.getRow(databaseId: _db, tableId: AppwriteConfig.progress, rowId: deterministicId(userId, puzzleId)));
    } on AppwriteException catch (e) {
      if (e.code == 404) return null;
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> upsertProgress(String userId, String puzzleId, Map<String, dynamic> data) async => _row(await _tables.upsertRow(
        databaseId: _db,
        tableId: AppwriteConfig.progress,
        rowId: deterministicId(userId, puzzleId),
        data: {...data, 'userId': userId, 'puzzleId': puzzleId},
        permissions: [Permission.read(Role.user(userId)), Permission.update(Role.user(userId)), Permission.delete(Role.user(userId))],
      ));

  @override
  Future<void> upsertEvent(String userId, String eventId, Map<String, dynamic> data) => _tables.upsertRow(
        databaseId: _db,
        tableId: AppwriteConfig.eventProgress,
        rowId: deterministicId(userId, eventId),
        data: {...data, 'userId': userId, 'eventId': eventId},
        permissions: [Permission.read(Role.users()), Permission.update(Role.user(userId)), Permission.delete(Role.user(userId))],
      );

  @override
  Future<Map<String, dynamic>?> getEvent(String userId, String eventId) async {
    try {
      return _row(await _tables.getRow(databaseId: _db, tableId: AppwriteConfig.eventProgress, rowId: deterministicId(userId, eventId)));
    } on AppwriteException catch (e) {
      if (e.code == 404) return null;
      rethrow;
    }
  }

  @override
  Future<void> createLedger(String userId, String rowId, Map<String, dynamic> data) async {
    try {
      await _tables.createRow(
        databaseId: _db,
        tableId: AppwriteConfig.ledger,
        rowId: rowId,
        data: {...data, 'userId': userId},
        permissions: [Permission.read(Role.user(userId))],
      );
    } on AppwriteException catch (e) {
      if (e.code != 409) rethrow;
    }
  }
}

final syncBackendProvider = Provider<SyncBackend>((ref) => AppwriteSyncBackend(ref.watch(tablesProvider)));
