// Design QA harness: repositories that answer from memory, so every screen can be shown in any
// state without touching the live backend. Not part of the app.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:card_jigsaw_world/data/repositories.dart';
import 'package:card_jigsaw_world/models/models.dart';

class NoClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw AppwriteException('design QA harness: offline', 0);
}

final _tables = TablesDB(NoClient());
final _storage = Storage(NoClient());

/// The catalogue from the snapshot file on the Mac (downloaded once), never the network.
class SnapshotCatalogSource implements CatalogSource {
  SnapshotCatalogSource(this.path, {this.eventPatches = const {}});
  final String path;
  /// Column overrides per event id (scene key `eventRows`), e.g. an `endAt` 40 minutes from now.
  final Map<String, Map<String, dynamic>> eventPatches;
  Map<String, dynamic>? _cache;

  @override
  Future<Map<String, dynamic>?> snapshot() async {
    if (_cache != null) return _cache;
    final s = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    if (eventPatches.isNotEmpty) {
      for (final r in (s['tables']['events']['rows'] as List)) {
        final patch = eventPatches[(r as Map)[r'$id']];
        if (patch != null) r.addAll(patch);
      }
    }
    return _cache = s;
  }

  @override
  Future<List<Map<String, dynamic>>> rows(String tableId) async {
    final s = await snapshot();
    return [for (final r in (s!['tables'][tableId]['rows'] as List)) Map<String, dynamic>.from(r as Map)];
  }

  @override
  Future<List<Map<String, dynamic>>> rowsSince(String tableId, String updatedAt) async => const [];

  @override
  Future<List<Map<String, dynamic>>> puzzleRowsOfPacks(List<String> packIds) async => const [];
}

class FakeCatalogRepo extends CatalogRepository implements CatalogSource {
  FakeCatalogRepo(this.source) : super(_tables, _storage);
  final SnapshotCatalogSource source;
  @override
  Future<Map<String, dynamic>?> snapshot() => source.snapshot();
  @override
  Future<List<Map<String, dynamic>>> rows(String tableId) => source.rows(tableId);
  @override
  Future<List<Map<String, dynamic>>> rowsSince(String tableId, String updatedAt) => source.rowsSince(tableId, updatedAt);
  @override
  Future<List<Map<String, dynamic>>> puzzleRowsOfPacks(List<String> packIds) => source.puzzleRowsOfPacks(packIds);
}

/// League, other players and ledger counts from a list of profiles.
class FakeProfileRepo extends ProfileRepository {
  FakeProfileRepo({required this.league, this.claims = 0, this.ledger = const {}}) : super(_tables);
  final List<Profile> league;
  final int claims;
  final Map<String, int> ledger;

  @override
  Future<Profile?> fetch(String userId) async {
    for (final p in league) {
      if (p.userId == userId || p.id == userId) return p;
    }
    return null;
  }

  @override
  Future<({List<Profile> items, String? lastId})> leaderboardPage({required int limit, String? after, Profile? viewer, Set<String> excluding = const {}}) async {
    final sorted = [...league.where((p) => !excluding.contains(p.id))]..sort((a, b) => b.xp.compareTo(a.xp));
    var start = 0;
    if (after != null) start = sorted.indexWhere((p) => p.id == after) + 1;
    final items = sorted.skip(start).take(limit).toList();
    return (items: items, lastId: items.isEmpty ? null : items.last.id);
  }

  @override
  Future<({int rank, int total})> leaderboardRank(Profile me) async {
    final ahead = league.where((p) => p.xp > me.xp && p.id != me.id).length;
    return (rank: ahead + 1, total: league.length);
  }

  @override
  Future<int> questClaims(String userId) async => claims;

  @override
  Future<int> ledgerCount(String userId, String reason) async => ledger[reason] ?? 0;

  @override
  Future<void> logLedger(String userId, {required int amount, required String currency, required String reason, int? balanceAfter}) async {}
}

class FakeSocialRepo extends SocialRepository {
  FakeSocialRepo({this.friendList = const [], this.blocked = const [], this.events = const {}, this.community = const {}}) : super(_tables);
  List<Friend> friendList;
  List<BlockedPlayer> blocked;
  final Map<String, EventProgress> events;
  final Map<String, int> community;

  @override
  Future<List<Friend>> friends(String userId) async => friendList;

  @override
  Future<Friend> addFriend(String userId, Profile friend) async {
    final f = Friend(id: deterministicId(userId, friend.userId), friendId: friend.userId, name: friend.displayName, avatar: friend.avatar);
    friendList = [...friendList, f];
    return f;
  }

  @override
  Future<void> removeFriend(String rowId) async => friendList = [for (final f in friendList) if (f.id != rowId) f];

  @override
  Future<void> report({required String reporterId, required Profile player, required ReportReason reason}) async {}

  @override
  Future<List<BlockedPlayer>> blocks(String userId) async => blocked;

  @override
  Future<void> block(String userId, Profile player) async {
    blocked = [BlockedPlayer(id: deterministicId(userId, player.userId), playerId: player.userId, name: player.displayName, avatar: player.avatar), ...blocked];
  }

  @override
  Future<void> unblock(String rowId) async => blocked = [for (final b in blocked) if (b.id != rowId) b];

  @override
  Future<Map<String, EventProgress>> eventProgress(String userId) async => events;

  @override
  Future<int> communityProgress(String eventId) async => community[eventId] ?? 1240;

  @override
  Future<EventProgress> upsertEventProgress(String userId, String eventId, {required int progress, bool claimed = false}) async =>
      EventProgress.fromRow(eventId, {'eventId': eventId, 'progress': progress, 'claimed': claimed});
}

class FakeUploadRepo extends UploadRepository {
  FakeUploadRepo(this.items) : super(_storage, _tables);
  final List<MyPuzzle> items;

  @override
  Future<({List<MyPuzzle> items, String? lastId})> page(String userId, {required int limit, String? after}) async {
    var start = 0;
    if (after != null) start = items.indexWhere((p) => p.id == after) + 1;
    final page = items.skip(start).take(limit).toList();
    return (items: page, lastId: page.isEmpty ? null : page.last.id);
  }

  @override
  Future<int> count(String userId) async => items.length;

  @override
  Future<MyPuzzle?> byId(String id) async {
    for (final p in items) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<MyPuzzle> upload(String userId, {required Uint8List bytes, required String filename, String? title}) async => throw AppwriteException('offline', 0);

  @override
  Future<void> delete(MyPuzzle p) async {}
}

models.User fakeUser(String id, {String name = 'Player', String email = ''}) => models.User.fromMap({
      '\$id': id, '\$createdAt': '2026-09-01T10:00:00.000+00:00', '\$updatedAt': '', 'name': name, 'registration': '', 'status': true,
      'labels': [], 'passwordUpdate': '', 'email': email, 'phone': '', 'emailVerification': email.isNotEmpty, 'phoneVerification': false,
      'mfa': false, 'prefs': <String, dynamic>{}, 'targets': [], 'accessedAt': '',
    });
