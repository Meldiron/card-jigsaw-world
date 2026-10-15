// Report and block (guideline 1.2): the leaderboard leaves blocked players out, blocking also ends a
// friendship, a report carries its reason, and event notes need their own yes (guideline 4.5.4).
import 'dart:io' show Directory;

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:carden/data/local_store.dart';
import 'package:carden/data/repositories.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/reminders.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/social.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Profile _player(String id, {int xp = 100}) => Profile.fromRow(id, {'userId': id, 'displayName': 'Player $id', 'avatar': 'fox', 'xp': xp, 'puzzlesCompleted': 3});

class _Profiles extends ProfileRepository {
  _Profiles() : super(TablesDB(Client()));
  Set<String>? excluded;
  @override
  Future<({List<Profile> items, String? lastId})> leaderboardPage({required int limit, String? after, Profile? viewer, Set<String> excluding = const {}}) async {
    excluded = excluding;
    final rows = [for (final id in ['p1', 'p2', 'p3']) if (!excluding.contains(id)) _player(id)];
    return (items: rows, lastId: rows.isEmpty ? null : rows.last.id);
  }
}

class _Social extends SocialRepository {
  _Social() : super(TablesDB(Client()));
  final calls = <String>[];
  final blocked = <BlockedPlayer>[];
  @override
  Future<void> report({required String reporterId, required Profile player, required ReportReason reason}) async => calls.add('report $reporterId ${player.userId} ${reason.code}');
  @override
  Future<void> block(String userId, Profile player) async {
    calls.add('block $userId ${player.userId}');
    blocked.add(BlockedPlayer(id: deterministicId(userId, player.userId), playerId: player.userId, name: player.displayName, avatar: player.avatar));
  }

  @override
  Future<void> unblock(String rowId) async {
    calls.add('unblock $rowId');
    blocked.removeWhere((b) => b.id == rowId);
  }

  @override
  Future<void> removeFriend(String rowId) async => calls.add('unfriend $rowId');
  @override
  Future<List<BlockedPlayer>> blocks(String userId) async => List.of(blocked);
  @override
  Future<List<Friend>> friends(String userId) async => const [];
}

class _Me extends AuthNotifier {
  @override
  Future<models.User?> build() async => null;
}

class _MeProfile extends ProfileNotifier {
  @override
  Future<Profile> build() async => _player('me');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The Appwrite IO client asks path_provider for its cookie jar folder.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => Directory.systemTemp.createTempSync('cjw-test').path,
  );
  late _Profiles profiles;
  late _Social social;
  late ProviderContainer c;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    profiles = _Profiles();
    social = _Social();
    c = ProviderContainer(overrides: [
      localStoreProvider.overrideWithValue(store),
      authProvider.overrideWith(_Me.new),
      currentUserIdProvider.overrideWithValue('me'),
      profileProvider.overrideWith(_MeProfile.new),
      profileRepositoryProvider.overrideWithValue(profiles),
      socialRepositoryProvider.overrideWithValue(social),
    ]);
    addTearDown(c.dispose);
  });

  List<String> board() => [for (final p in c.read(leaderboardProvider).value!.items) p.id];

  test('a blocked player leaves the leaderboard, and comes back when unblocked', () async {
    await c.read(leaderboardProvider.future);
    expect(board(), ['p1', 'p2', 'p3']);
    expect(profiles.excluded, isEmpty);

    await c.read(playerSafetyProvider).block(_player('p2'));
    await c.read(leaderboardProvider.future);
    expect(profiles.excluded, {'p2'});
    expect(board(), ['p1', 'p3']);
    expect(social.calls, ['block me p2', 'unfriend ${deterministicId('me', 'p2')}'], reason: 'blocking ends a friendship too');
    expect((await c.read(blockedPlayersProvider.future)).map((b) => b.playerId), ['p2']);

    await c.read(playerSafetyProvider).unblock('p2');
    await c.read(leaderboardProvider.future);
    expect(board(), ['p1', 'p2', 'p3']);
    expect(await c.read(blockedPlayersProvider.future), isEmpty);
  });

  test('a report names the reporter, the player and the reason', () async {
    await c.read(playerSafetyProvider).report(_player('p3'), ReportReason.name);
    expect(social.calls, ['report me p3 name']);
    expect(ReportReason.values.map((r) => r.code), ['name', 'cheating', 'other'], reason: 'the server keeps these codes as text');
  });

  test('event notes are off until the player turns them on', () {
    expect(c.read(eventRemindersProvider), isFalse);
    c.read(eventRemindersProvider.notifier).set(true);
    expect(c.read(eventRemindersProvider), isTrue);
    c.read(eventRemindersProvider.notifier).set(false);
    expect(c.read(eventRemindersProvider), isFalse);
  });
}
