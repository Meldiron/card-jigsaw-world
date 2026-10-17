// Who has a card in Play together (docs/multiplayer.md, "Who has a card"): first grab wins. A card
// another player has picked or is dragging (and its group) cannot be taken here; when two players grab
// the same card at once, the earlier server time wins and the other gives way; claims end with the
// put-down, the drop's move, 2 s without a drag's news, or the player going away.
import 'dart:ui' as ui;

import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/data/coop_repository.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/game/board.dart';
import 'package:carden/game/game_controller.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/coop/coop_controller.dart';
import 'package:carden/state/coop/coop_live.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_coop.dart';

final _t0 = DateTime.utc(2026, 10, 17, 12);
DateTime _at(int ms) => _t0.add(Duration(milliseconds: ms));

CoopLive _state(String user, LivePhase phase, int seq, {int card = 3, int drag = 1000, int server = 0}) =>
    CoopLive(userId: user, board: 1, phase: phase, card: card, x: 0.5, y: 0.5, drag: drag, seq: seq, updatedAt: _at(server));

void main() {
  group('claims', () {
    test('the earlier server time wins; a tie goes to the smaller player id; an unknown time never wins', () {
      final amy = LiveClaim(userId: 'amy', card: 3, since: _at(100));
      final bob = LiveClaim(userId: 'bob', card: 3, since: _at(120));
      expect(amy.before(bob), isTrue);
      expect(bob.before(amy), isFalse);
      final bobTie = LiveClaim(userId: 'bob', card: 3, since: _at(100));
      expect(amy.before(bobTie), isTrue);
      expect(bobTie.before(amy), isFalse);
      const pending = LiveClaim(userId: 'amy', card: 3);
      expect(pending.before(bob), isFalse);
      expect(bob.before(pending), isTrue);
    });

    test('a pick that becomes a drag keeps its time; a drop holds the card until its move; a put-down ends it', () {
      final tracks = LiveTracks();
      tracks.add(_state('amy', LivePhase.pick, 1, server: 100), _at(100));
      tracks.add(_state('amy', LivePhase.drag, 2, server: 300), _at(300));
      expect(tracks.claims(_at(400)).single.since, _at(100), reason: 'the same card in hand');
      tracks.add(_state('amy', LivePhase.drop, 3, server: 500), _at(500));
      expect(tracks.claims(_at(600)).single.card, 3, reason: 'held until the move comes');
      tracks.onMove('amy', [3, 9]);
      expect(tracks.claims(_at(700)), isEmpty);
      tracks.add(_state('amy', LivePhase.pick, 4, card: 7, server: 800), _at(800));
      expect(tracks.claims(_at(900)).single.since, _at(800), reason: 'a new card: a new claim');
      tracks.add(_state('amy', LivePhase.none, 5, card: -1, server: 900), _at(900));
      expect(tracks.claims(_at(1000)), isEmpty);
    });

    test('a drag not heard from for 2 s holds nothing; a pick holds until put down; a player who went away holds nothing', () {
      final tracks = LiveTracks();
      tracks.add(_state('amy', LivePhase.drag, 1, server: 0), _at(0));
      expect(tracks.claims(_at(1900)), hasLength(1));
      expect(tracks.claims(_at(2100)), isEmpty);
      tracks.add(_state('bob', LivePhase.pick, 1, card: 5, server: 0), _at(0));
      expect(tracks.claims(_at(60000)).single.userId, 'bob');
      tracks.forget('bob');
      expect(tracks.claims(_at(60000)), isEmpty);
    });
  });

  group('between devices', () {
    final spec = BoardSpec(GameMode.cards, 4, 5, 'Medium', tier: 3);
    Future<void> settle() async {
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    ProviderContainer device(FakeCoopServer server, String id) => ProviderContainer(overrides: [
          coopBackendProvider.overrideWithValue(FakeCoopBackend(server, id)),
          currentUserIdProvider.overrideWithValue(id),
          coopTimingProvider.overrideWithValue(const CoopTiming(presenceGap: Duration(milliseconds: 5), markFor: Duration(milliseconds: 60))),
        ]);

    test('two players grab the same card at once: both devices agree who has it', () async {
      final server = FakeCoopServer();
      final amy = device(server, 'amy'), bob = device(server, 'bob');
      addTearDown(amy.dispose);
      addTearDown(bob.dispose);
      final base = Board.shuffled(spec, seed: 21).slots;
      final game = await amy.read(coopProvider.notifier).create(puzzleId: 'p1', grid: 'cards-4x5t3', layout: base);
      await bob.read(coopProvider.notifier).join(game.code);
      await settle();
      final a = amy.read(coopProvider.notifier), b = bob.read(coopProvider.notifier);
      final card = base[4];
      // Amy picks it a moment before Bob starts dragging it; neither has heard of the other yet.
      a.hold(card);
      b.dragStart(card, 0.3, 0.3);
      await settle();
      final mineA = a.myClaim!, mineB = b.myClaim!;
      expect(mineA.since, isNotNull);
      expect(mineB.since, isNotNull);
      final theirsOnA = a.claims().single, theirsOnB = b.claims().single;
      expect(theirsOnA.userId, 'bob');
      expect(theirsOnB.userId, 'amy');
      expect(mineA.before(theirsOnA), isTrue, reason: 'Amy\'s device: hers came first, she keeps it');
      expect(theirsOnB.before(mineB), isTrue, reason: 'Bob\'s device: Amy\'s came first, he gives way');
      // Bob's drag ends (his board gives it up): Amy's device no longer sees him holding it.
      b.dragEnd(dropped: false);
      await settle();
      expect(a.claims(), isEmpty);
      expect(b.claims().single.userId, 'amy');
      // Amy puts it down: nobody holds it.
      a.hold(null);
      await settle();
      expect(b.claims(), isEmpty);
    });
  });

  group('the board', () {
    late ui.Image image;
    setUpAll(() {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 240, 320), Paint()..color = const Color(0xFF6094DE));
      image = rec.endRecording().toImageSync(240, 320);
    });
    final spec = BoardSpec.squareTiers(GameMode.cards)[1];
    const size = Size(240, 320);
    List<int> reversed() => List.generate(16, (s) => 15 - s);
    GameState stateOf(List<int> layout) {
      final c = ProviderContainer();
      final s = c.read(gameControllerProvider(GameArgs(puzzleId: 'p', spec: spec, layout: layout)));
      c.dispose();
      return s;
    }

    final refused = <int>[], lost = <(int, DragLoss)>[], ended = <int>[];
    Widget board(GameState s, Set<int> blocked) => MaterialApp(
          theme: AppTheme.light(),
          home: Align(
            alignment: Alignment.topLeft,
            child: BoardWidget(
              image: image,
              state: s,
              width: size.width,
              height: size.height,
              cardStyle: CardStyle.classic,
              onTap: (_) {},
              onDrop: (_, _) {},
              onDragMove: (_, _, _) {},
              onDragEnd: ended.add,
              blocked: blocked,
              onDragRefused: refused.add,
              onDragLost: (card, why) => lost.add((card, why)),
            ),
          ),
        );
    setUp(() {
      refused.clear();
      lost.clear();
      ended.clear();
    });

    testWidgets('a card another player has does not lift', (tester) async {
      final s = stateOf(reversed());
      await tester.pumpWidget(board(s, {5}));
      final origin = tester.getTopLeft(find.byType(BoardWidget));
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('card-5'))));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 10));
      await tester.pump();
      expect(refused, [10]);
      expect(tester.getTopLeft(find.byKey(const ValueKey('card-5'))) - origin, spec.tiling.cellBounds(10, size).topLeft, reason: 'it stays in its slot');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(ended, isEmpty, reason: 'no drag began');
    });

    testWidgets('a drag whose card another player turns out to have had first ends: the card goes back', (tester) async {
      final s = stateOf(reversed());
      await tester.pumpWidget(board(s, const {}));
      final origin = tester.getTopLeft(find.byType(BoardWidget));
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('card-5'))));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(24, 10));
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(const ValueKey('card-5'))) - origin, isNot(spec.tiling.cellBounds(10, size).topLeft));
      // The other player's grab came first: card 5 is theirs.
      await tester.pumpWidget(board(s, {5}));
      await tester.pump();
      expect(lost, [(5, DragLoss.claimed)]);
      expect(ended, [10]);
      await gesture.moveBy(const Offset(20, 20));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(const ValueKey('card-5'))) - origin, spec.tiling.cellBounds(10, size).topLeft, reason: 'back in its slot');
    });
  });
}
