// An Appwrite-like server in memory and "devices" (provider containers) that play on it, for
// testing the save sync without the network.
import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/data/repositories.dart';
import 'package:card_jigsaw_world/data/sync/backend.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/auth.dart';
import 'package:card_jigsaw_world/state/catalog.dart';
import 'package:card_jigsaw_world/state/profile.dart';
import 'package:card_jigsaw_world/state/progress.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:card_jigsaw_world/state/sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

models.User testUser(String id, {String email = ''}) => models.User.fromMap({
      '\$id': id, '\$createdAt': '', '\$updatedAt': '', 'name': 'Tester', 'registration': '', 'status': true, 'labels': [],
      'passwordUpdate': '', 'email': email, 'phone': '', 'emailVerification': false, 'phoneVerification': false, 'mfa': false,
      'prefs': <String, dynamic>{}, 'targets': [], 'accessedAt': '',
    });

/// The tables the sync writes, with operators applied the way Appwrite applies them (checked on
/// the live backend): a decrement below its floor and an increment past its cap are skipped, an
/// append keeps duplicates, a skipped column does not block the others.
class FakeServer {
  final profiles = <String, Map<String, dynamic>>{};
  final progress = <String, Map<String, dynamic>>{};
  final events = <String, Map<String, dynamic>>{};
  final ledger = <String, Map<String, dynamic>>{};
  int _clock = 0;

  /// Five minutes per write, so a read that starts from the wrong time misses rows.
  String _now() => DateTime.utc(2026, 10, 13, 12).add(Duration(minutes: 5 * ++_clock)).toIso8601String();

  Map<String, dynamic> write(Map<String, dynamic>? row, Map<String, dynamic> data, String id) {
    final out = {...?row};
    for (final e in data.entries) {
      out[e.key] = _value(out[e.key], e.value);
    }
    out['\$id'] = id;
    out['\$updatedAt'] = _now();
    return out;
  }

  static dynamic _value(dynamic current, dynamic value) {
    if (value is! String || !value.startsWith('{"method"')) return value;
    final j = jsonDecode(value) as Map<String, dynamic>;
    final v = j['values'] as List;
    int cur() => current is num ? current.toInt() : 0;
    List<String> list() => current is List ? [for (final e in current) e.toString()] : <String>[];
    switch (j['method']) {
      case 'increment':
        final next = cur() + (v[0] as num).toInt();
        return v.length > 1 && v[1] != null && next > (v[1] as num) ? cur() : next;
      case 'decrement':
        final next = cur() - (v[0] as num).toInt();
        return v.length > 1 && v[1] != null && next < (v[1] as num) ? cur() : next;
      case 'arrayAppend':
        return [...list(), ...v.map((e) => e.toString())];
      case 'arrayDiff':
        return [for (final e in list()) if (!v.contains(e)) e];
      case 'arrayUnique':
        return {...list()}.toList();
    }
    throw UnsupportedError('operator ${j['method']}');
  }

  Map<String, dynamic>? progressOf(String userId, String puzzleId) => progress[deterministicId(userId, puzzleId)];
}

class FakeBackend implements SyncBackend {
  FakeBackend(this.server);
  final FakeServer server;

  /// False: every request fails without an answer.
  bool online = true;

  /// The next write reaches the server but its answer is lost.
  bool loseNextAnswer = false;
  int requests = 0;

  void _reach() {
    requests++;
    if (!online) throw AppwriteException('Failed host lookup');
  }

  T _answer<T>(T value) {
    if (loseNextAnswer) {
      loseNextAnswer = false;
      throw AppwriteException('Connection closed before full header was received');
    }
    return value;
  }

  @override
  Future<Map<String, dynamic>?> getProfile(String userId) async {
    _reach();
    final r = server.profiles[userId];
    return r == null ? null : {...r};
  }

  @override
  Future<Map<String, dynamic>> createProfile(String userId, Map<String, dynamic> data) async {
    _reach();
    return {...server.profiles[userId] ??= server.write(null, data, userId)};
  }

  @override
  Future<Map<String, dynamic>> updateProfile(String userId, Map<String, dynamic> data) async {
    _reach();
    final row = server.profiles[userId];
    if (row == null) throw AppwriteException('Row not found', 404);
    server.profiles[userId] = server.write(row, data, userId);
    return _answer({...server.profiles[userId]!});
  }

  @override
  Future<List<Map<String, dynamic>>> progressRows(String userId, {String? since}) async {
    _reach();
    return [
      for (final r in server.progress.values)
        if (r['userId'] == userId && (since == null || DateTime.parse(r['\$updatedAt']).compareTo(DateTime.parse(since)) >= 0)) {...r},
    ];
  }

  @override
  Future<Map<String, dynamic>?> getProgress(String userId, String puzzleId) async {
    _reach();
    final r = server.progressOf(userId, puzzleId);
    return r == null ? null : {...r};
  }

  @override
  Future<Map<String, dynamic>> upsertProgress(String userId, String puzzleId, Map<String, dynamic> data) async {
    _reach();
    final id = deterministicId(userId, puzzleId);
    server.progress[id] = server.write(server.progress[id], {...data, 'userId': userId, 'puzzleId': puzzleId}, id);
    return _answer({...server.progress[id]!});
  }

  @override
  Future<void> upsertEvent(String userId, String eventId, Map<String, dynamic> data) async {
    _reach();
    final id = deterministicId(userId, eventId);
    server.events[id] = server.write(server.events[id], {...data, 'userId': userId, 'eventId': eventId}, id);
    _answer(null);
  }

  @override
  Future<Map<String, dynamic>?> getEvent(String userId, String eventId) async {
    _reach();
    final r = server.events[deterministicId(userId, eventId)];
    return r == null ? null : {...r};
  }

  @override
  Future<void> createLedger(String userId, String rowId, Map<String, dynamic> data) async {
    _reach();
    server.ledger.putIfAbsent(rowId, () => {...data, 'userId': userId});
  }
}

/// SharedPreferences in memory, one per device (the plugin's mock is a single global store).
class FakePrefs implements SharedPreferences {
  final values = <String, Object>{};
  @override
  String? getString(String key) => values[key] as String?;
  @override
  Future<bool> setString(String key, String value) async => (values[key] = value) == value;
  @override
  bool? getBool(String key) => values[key] as bool?;
  @override
  Future<bool> setBool(String key, bool value) async => (values[key] = value) == value;
  @override
  int? getInt(String key) => values[key] as int?;
  @override
  Future<bool> setInt(String key, int value) async => (values[key] = value) == value;
  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }
  @override
  bool containsKey(String key) => values.containsKey(key);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('${invocation.memberName}');
}

class FakeAuth extends AuthNotifier {
  FakeAuth(this.user);
  final models.User? user;
  @override
  Future<models.User?> build() async => user;
  @override
  Future<void> reconnect({bool force = false}) async {}
}

class _NoClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('no network in unit tests');
}

/// The profile repository's reads that are not part of the sync (the quest count from the ledger).
class FakeProfileRepo extends ProfileRepository {
  FakeProfileRepo({this.claims = 0}) : super(TablesDB(_NoClient()));
  int claims;
  @override
  Future<int> questClaims(String userId) async => claims;
}

/// One device of a player: its own storage and connection, the shared server.
class Device {
  Device(this.server, this.user, {FakePrefs? prefs, List<Pack> packs = const [], List<Puzzle> puzzles = const [], FakeProfileRepo? repo})
      : prefs = prefs ?? FakePrefs(),
        repo = repo ?? FakeProfileRepo() {
    backend = FakeBackend(server);
    container = ProviderContainer(overrides: [
      localStoreProvider.overrideWithValue(LocalStore(this.prefs)),
      syncBackendProvider.overrideWithValue(backend),
      authProvider.overrideWith(() => FakeAuth(user)),
      profileRepositoryProvider.overrideWithValue(this.repo),
      packsProvider.overrideWith((ref) async => packs),
      allPuzzlesProvider.overrideWith((ref) async => puzzles),
      eventsProvider.overrideWith((ref) async => const <GameEvent>[]),
    ]);
  }

  final FakeServer server;
  final models.User? user;
  final FakePrefs prefs;
  final FakeProfileRepo repo;
  late final FakeBackend backend;
  late final ProviderContainer container;

  Future<Device> open() async {
    container.listen(profileProvider, (_, _) {});
    container.listen(progressProvider, (_, _) {});
    await container.read(profileProvider.future);
    await container.read(progressProvider.future);
    await settle();
    return this;
  }

  void close() => container.dispose();

  ProfileNotifier get profile => container.read(profileProvider.notifier);
  ProgressNotifier get progress => container.read(progressProvider.notifier);
  SyncController get sync => container.read(syncProvider.notifier);
  Profile get me => container.read(profileProvider).value!;
  Map<String, PuzzleProgress> get rows => container.read(progressProvider).value!;

  /// Comes back to the foreground: sends what is queued and reads the save again.
  Future<void> resume() async {
    sync.onResume();
    await sync.sync();
    await settle();
  }

  Future<void> settle() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}
