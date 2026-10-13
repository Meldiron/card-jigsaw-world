// "Quests completed" and the public completion numbers on the profile row.
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/data/repositories.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/auth.dart';
import 'package:card_jigsaw_world/state/catalog.dart';
import 'package:card_jigsaw_world/state/profile.dart';
import 'package:card_jigsaw_world/state/progress.dart';
import 'package:card_jigsaw_world/state/rewards.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

models.User _user(String id) => models.User.fromMap({
      '\$id': id, '\$createdAt': '', '\$updatedAt': '', 'name': 'Tester', 'registration': '', 'status': true, 'labels': [],
      'passwordUpdate': '', 'email': '', 'phone': '', 'emailVerification': false, 'phoneVerification': false, 'mfa': false,
      'prefs': <String, dynamic>{}, 'targets': [], 'accessedAt': '',
    });

class _Auth extends AuthNotifier {
  _Auth(this.user);
  final models.User? user;
  @override
  Future<models.User?> build() async => user;
}

class _Rows extends ProgressNotifier {
  _Rows(this.rows);
  final Map<String, PuzzleProgress> rows;
  @override
  Future<Map<String, PuzzleProgress>> build() async => rows;
}

/// A client that is never asked for anything (the fake repository answers first).
class _NoClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('no network in unit tests');
}

/// The profile table in memory: one row, every patch recorded.
class _Repo extends ProfileRepository {
  _Repo(this.row, {this.claims = 0}) : super(TablesDB(_NoClient()));
  Profile row;
  final int claims;
  final patches = <Map<String, dynamic>>[];

  @override
  Future<Profile> fetchOrCreate(String userId, {String? name, bool isTest = false}) async => row;
  @override
  Future<Profile> update(String userId, Map<String, dynamic> patch) async {
    patches.add(patch);
    return row = Profile.fromRow(userId, {...row.toData(), ...patch});
  }

  @override
  Future<int> questClaims(String userId) async => claims;
  @override
  Future<void> logLedger(String userId, {required int amount, required String currency, required String reason, int? balanceAfter}) async {}
}

Future<ProviderContainer> _container({required models.User? user, required _Repo repo, Map<String, PuzzleProgress> rows = const {}}) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();
  final c = ProviderContainer(overrides: [
    localStoreProvider.overrideWithValue(store),
    authProvider.overrideWith(() => _Auth(user)),
    profileRepositoryProvider.overrideWithValue(repo),
    progressProvider.overrideWith(() => _Rows(rows)),
    packsProvider.overrideWith((ref) async => [Pack.fromRow('a', {'name': 'A', 'category': 'Nature'})]),
    allPuzzlesProvider.overrideWith((ref) async => [
          Puzzle.fromRow('a1', {'packId': 'a', 'imageUrl': 'x'}),
          Puzzle.fromRow('a2', {'packId': 'a', 'imageUrl': 'x'}),
        ]),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('claiming a quest counts it once', () async {
    final repo = _Repo(Profile.fromRow('p1', {'userId': 'p1', 'questsCompleted': 4}));
    final c = await _container(user: _user('p1'), repo: repo);
    await c.read(profileProvider.future);
    await _settle();
    final now = DateTime.now();
    final goal = Goal(key: 'd:${Goals.dayKey(now)}:solve3', title: 'Solve 3 puzzles', progress: 3, target: 3, coins: 60, icon: 'puzzle');
    expect(await c.read(profileProvider.notifier).claimGoal(goal), isTrue);
    expect(c.read(profileProvider).value!.questsCompleted, 5);
    expect(repo.patches.last['questsCompleted'], 5);
    expect(await c.read(profileProvider.notifier).claimGoal(goal), isFalse, reason: 'a quest is claimed once');
    expect(c.read(profileProvider).value!.questsCompleted, 5);
  });

  test('on start, older rows get their quest count from the ledger and their completion numbers', () async {
    final repo = _Repo(Profile.fromRow('p2', {'userId': 'p2', 'questsCompleted': 0}), claims: 6);
    final c = await _container(user: _user('p2'), repo: repo, rows: {
      'a1': PuzzleProgress.fromRow('r1', {'userId': 'p2', 'puzzleId': 'a1', 'completed': true, 'stars': 3}),
      'a2': PuzzleProgress.fromRow('r2', {'userId': 'p2', 'puzzleId': 'a2', 'completed': true, 'stars': 2}),
    });
    await c.read(profileProvider.future);
    // The listener and the start-up repair both watch the catalogue and progress.
    c.listen(progressProvider, (_, _) {});
    await _settle();
    final p = c.read(profileProvider).value!;
    expect(p.questsCompleted, 6);
    expect([p.picturesSolved, p.picturesPerfect, p.packsCompleted, p.packsPerfect], [2, 1, 1, 0]);
    final writes = repo.patches.length;
    await _settle();
    expect(repo.patches.length, writes, reason: 'nothing is written again once the row is right');
  });

  test("progress rows of another player are never written to this profile", () async {
    final repo = _Repo(Profile.fromRow('p3', {'userId': 'p3'}));
    final c = await _container(user: _user('p3'), repo: repo, rows: {
      'a1': PuzzleProgress.fromRow('r1', {'userId': 'someone-else', 'puzzleId': 'a1', 'completed': true, 'stars': 3}),
    });
    await c.read(profileProvider.future);
    await _settle();
    expect(repo.patches.where((p) => p.containsKey('picturesSolved')), isEmpty);
  });
}
