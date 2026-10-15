// "Quests completed" and the public completion numbers on the profile row.
import 'package:carden/models/models.dart';
import 'package:carden/state/completion.dart';
import 'package:carden/state/rewards.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_sync.dart';

final _packs = [Pack.fromRow('a', {'name': 'A', 'category': 'Nature'})];
final _puzzles = [
  Puzzle.fromRow('a1', {'packId': 'a', 'imageUrl': 'x'}),
  Puzzle.fromRow('a2', {'packId': 'a', 'imageUrl': 'x'}),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('claiming a quest counts it once', () async {
    final server = FakeServer();
    server.profiles['p1'] = server.write(null, {'userId': 'p1', 'coins': 500, 'questsCompleted': 4}, 'p1');
    final d = await Device(server, testUser('p1'), packs: _packs, puzzles: _puzzles).open();
    addTearDown(d.close);
    final goal = Goal(key: 'd:${Goals.dayKey(DateTime.now())}:solve3', title: 'Solve 3 puzzles', progress: 3, target: 3, coins: 60, icon: 'puzzle');
    expect(await d.profile.claimGoal(goal), isTrue);
    expect(d.me.questsCompleted, 5);
    await d.settle();
    expect(server.profiles['p1']!['questsCompleted'], 5);
    expect(await d.profile.claimGoal(goal), isFalse, reason: 'a quest is claimed once');
    expect(d.me.questsCompleted, 5);
  });

  test('on start, older rows get their quest count from the ledger and their completion numbers', () async {
    final server = FakeServer();
    server.profiles['p2'] = server.write(null, {'userId': 'p2', 'questsCompleted': 0}, 'p2');
    for (final (id, stars) in [('a1', 3), ('a2', 2)]) {
      server.progress['$id-row'] = server.write(null, {'userId': 'p2', 'puzzleId': id, 'completed': true, 'stars': stars}, '$id-row');
    }
    final d = await Device(server, testUser('p2'), packs: _packs, puzzles: _puzzles, repo: FakeProfileRepo(claims: 6)).open();
    addTearDown(d.close);
    await d.settle();
    final p = d.me;
    expect(p.questsCompleted, 6);
    expect([p.picturesSolved, p.picturesPerfect, p.packsCompleted, p.packsPerfect], [2, 1, 1, 0]);
    final row = server.profiles['p2']!;
    expect([for (final k in ['questsCompleted', 'picturesSolved', 'picturesPerfect', 'packsCompleted', 'packsPerfect']) row[k] ?? 0], [6, 2, 1, 1, 0]);
    final writes = d.backend.requests;
    await d.settle();
    expect(d.backend.requests, writes, reason: 'nothing is written again once the row is right');
  });

  test('completion numbers of another player are never written to this profile', () async {
    final server = FakeServer();
    final d = await Device(server, testUser('p3'), packs: _packs, puzzles: _puzzles).open();
    addTearDown(d.close);
    await d.settle();
    final before = d.backend.requests;
    await d.profile.syncCompletion(const CompletionTotals(pictures: 2, picturesSolved: 2, picturesPerfect: 2, packs: 1, packsCompleted: 1, packsPerfect: 1, ownerId: 'someone-else'));
    await d.settle();
    expect(d.backend.requests, before);
    expect(server.profiles['p3']!['picturesSolved'], isNot(2));
  });
}
