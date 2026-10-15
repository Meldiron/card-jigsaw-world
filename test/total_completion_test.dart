// "Total Completion" on the profile and on other players' profiles.
import 'package:card_jigsaw_world/core/numbers.dart';
import 'package:card_jigsaw_world/core/theme/app_theme.dart';
import 'package:card_jigsaw_world/features/profile/stats.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/completion.dart';
import 'package:card_jigsaw_world/state/merge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Pack _pack(String id) => Pack.fromRow(id, {'name': id, 'category': 'Nature'});
Puzzle _pic(String id, String pack) => Puzzle.fromRow(id, {'packId': pack, 'title': id, 'imageUrl': 'x'});
PuzzleProgress _row(String puzzle, {bool done = true, int stars = 3}) =>
    PuzzleProgress.fromRow('r-$puzzle', {'userId': 'me', 'puzzleId': puzzle, 'gridSize': 16, 'completed': done, 'stars': stars});

void main() {
  final packs = [_pack('a'), _pack('b'), _pack('empty')];
  final puzzles = [
    _pic('a1', 'a'), _pic('a2', 'a'), //
    _pic('b1', 'b'), _pic('b2', 'b'), _pic('b3', 'b'),
    _pic('gone1', 'gone'), // a pack that left the catalogue
  ];

  test('counts catalogue pictures and packs; old packs and photos never count', () {
    final t = CompletionTotals.of(packs: packs, puzzles: puzzles, rows: {
      'a1': _row('a1'),
      'a2': _row('a2'),
      'b1': _row('b1', stars: 2),
      'b2': _row('b2', done: false, stars: 0),
      'gone1': _row('gone1'),
      'my-photo': _row('my-photo'),
    });
    expect(t.pictures, 5, reason: 'pack "empty" has no pictures; "gone" is not in the catalogue');
    expect(t.packs, 2);
    expect(t.picturesSolved, 3);
    expect(t.picturesPerfect, 2);
    expect(t.packsCompleted, 1);
    expect(t.packsPerfect, 1);
    expect(t.ownerId, 'me');
    expect(t.publicFields, {'picturesSolved': 3, 'picturesPerfect': 2, 'packsCompleted': 1, 'packsPerfect': 1});
  });

  test('a finished pack with a two-star picture is finished, not perfect', () {
    final t = CompletionTotals.of(packs: packs, puzzles: puzzles, rows: {'a1': _row('a1'), 'a2': _row('a2', stars: 2)});
    expect(t.packsCompleted, 1);
    expect(t.packsPerfect, 0);
  });

  test("another player's numbers sit on this device's catalogue and never pass 100%", () {
    final p = Profile.fromRow('them', {'userId': 'them', 'picturesSolved': 900, 'picturesPerfect': 950, 'packsCompleted': 3, 'packsPerfect': 1});
    final t = CompletionTotals.forProfile(p, (pictures: 800, packs: 40));
    expect(t.picturesSolved, 800);
    expect(t.picturesPerfect, 800, reason: 'perfect is part of solved');
    expect(t.packsCompleted, 3);
    expect(t.pictures, 800);
  });

  test('percent labels: capped, honest at both ends', () {
    expect(completionPercent(0, 7268), '0%');
    expect(completionPercent(1, 7268), '<1%');
    expect(completionPercent(412, 7268), '5%');
    expect(completionPercent(7267, 7268), '99%');
    expect(completionPercent(7268, 7268), '100%');
    expect(completionPercent(9000, 7268), '100%');
    expect(completionPercent(3, 0), '0%');
    expect(formatCount(7268), '7,268');
  });

  test('the guest-to-account merge keeps the larger quest count', () {
    SaveSnapshot save(int quests) => SaveSnapshot(userId: 'u', profile: {'questsCompleted': quests}, progress: const []);
    final patch = mergeProfile(guest: save(4), account: save(9), choice: MergeChoice.guest, mergedProgress: const {});
    expect(patch['questsCompleted'], 9);
  });

  testWidgets('Statistics: Total Completion on top, then the quests tile', (tester) async {
    tester.view.physicalSize = const Size(520, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final p = Profile.fromRow('them', {'userId': 'them', 'questsCompleted': 1234, 'picturesSolved': 412, 'picturesPerfect': 230, 'packsCompleted': 3, 'packsPerfect': 1});
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: StatisticsSection(stats: PlayerStats.fromProfile(p, catalogue: (pictures: 7268, packs: 152))))),
    ));
    expect(find.text('Total Completion'), findsOneWidget);
    expect(find.text('412 of 7,268 solved'), findsOneWidget);
    expect(find.text('230 with every star'), findsOneWidget);
    expect(find.text('3 of 152 finished'), findsOneWidget);
    expect(find.text('5%'), findsOneWidget);
    expect(find.text('1%'), findsOneWidget);
    expect(find.text('1,234'), findsOneWidget);
    expect(find.text('Quests completed'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Total Completion')).dy, lessThan(tester.getTopLeft(find.text('Puzzles solved')).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a catalogue the block is left out', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: StatisticsSection(stats: PlayerStats.fromProfile(Profile.guest('x'))))),
    ));
    expect(find.text('Total Completion'), findsNothing);
    expect(find.text('Quests completed'), findsOneWidget);
  });
}
