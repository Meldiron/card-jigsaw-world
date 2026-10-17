// Races in Play together's live drags (build 126, TestFlight feedback AGyfyDbbHhCGY72W1h5num0 and the
// owner's "two players drag the same piece"): what happens on this device when another player's move
// changes the board under this player's finger, and what the other devices are left with.
//
// The tests marked `_known` reproduce the reported bugs: they describe the right behaviour and fail
// today, so they are skipped in the normal run. Run them with
//
//   flutter test --dart-define=CJW_RUN_KNOWN_FAILURES=true test/coop_race_test.dart
//
// and remove the skip once the fix is in. The others pass today: they pin what already works (the
// shared board, the others' ghosts and marks always settle).
import 'dart:ui' as ui;

import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/data/coop_repository.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/game/board.dart';
import 'package:carden/game/game_controller.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/coop/coop_controller.dart';
import 'package:carden/state/coop/coop_live.dart';
import 'package:carden/state/coop/coop_models.dart';
import 'package:carden/state/settings.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_coop.dart';

const _runKnown = bool.fromEnvironment('CJW_RUN_KNOWN_FAILURES');

/// A reproduced bug's test is skipped unless the known failures are asked for.
const _skipKnown = !_runKnown;

final _spec = BoardSpec.squareTiers(GameMode.cards)[1]; // 4x4
const _size = Size(240, 320);

/// A 4x4 board dealt back to front: slot s holds card 15 - s; no card in place, no pair joined.
List<int> _reversed() => List.generate(16, (s) => 15 - s);

List<int> _swap(List<int> l, int a, int b) {
  final out = List<int>.from(l);
  final t = out[a];
  out[a] = out[b];
  out[b] = t;
  return out;
}

void main() {
  group('this player\'s drag when another player\'s move lands under the finger', () {
    late ui.Image image;
    setUpAll(() {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 240, 320), Paint()..color = const Color(0xFF6094DE));
      image = rec.endRecording().toImageSync(240, 320);
    });

    GameState stateOf(List<int> layout) {
      final c = ProviderContainer();
      final s = c.read(gameControllerProvider(GameArgs(puzzleId: 'p', spec: _spec, layout: layout)));
      c.dispose();
      return s;
    }

    final ended = <int>[], dropped = <(int, int)>[];
    Widget board(GameState s) => MaterialApp(
      theme: AppTheme.light(),
      home: Align(
        alignment: Alignment.topLeft,
        child: BoardWidget(
          image: image,
          state: s,
          width: _size.width,
          height: _size.height,
          cardStyle: CardStyle.classic,
          onTap: (_) {},
          onDrop: (from, to) => dropped.add((from, to)),
          onDragMove: (_, _, _) {},
          onDragEnd: ended.add,
        ),
      ),
    );

    setUp(() {
      ended.clear();
      dropped.clear();
    });

    /// Every card drawn in its own slot (nothing floating, nothing lifted off its place).
    void expectNothingFloats(WidgetTester tester, GameState s) {
      final origin = tester.getTopLeft(find.byType(BoardWidget));
      for (var slot = 0; slot < s.board.cells; slot++) {
        final card = s.board.slots[slot];
        final at = tester.getTopLeft(find.byKey(ValueKey('card-$card'))) - origin;
        expect(at, _spec.tiling.cellBounds(slot, _size).topLeft, reason: 'card $card is drawn away from slot $slot');
      }
    }

    testWidgets('a move of two other cards leaves the drag alone: the drop lands where the finger lets go', (tester) async {
      final s0 = stateOf(_reversed());
      await tester.pumpWidget(board(s0));
      // Card 5 sits in slot 10; the finger takes it.
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('card-5'))));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(24, 10));
      await tester.pump();
      // The other player swaps cards 0 and 1 (slots 15 and 14).
      await tester.pumpWidget(board(stateOf(_swap(_reversed(), 15, 14))));
      await gesture.moveBy(Offset(0, -_spec.tiling.cellBounds(0, _size).height));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(dropped.single.$1, 10);
      expect(ended, [10]);
    });

    testWidgets('the other player puts the dragged card in its place: the drag ends and nothing is left floating', (tester) async {
      final s0 = stateOf(_reversed());
      await tester.pumpWidget(board(s0));
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('card-5'))));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(24, 10));
      await tester.pump();
      // They took card 5 to its place (slot 5); card 10 came to slot 10, under the finger's old slot.
      final s1 = stateOf(_swap(_reversed(), 10, 5));
      expect(s1.board.isLocked(5), isTrue);
      await tester.pumpWidget(board(s1));

      await gesture.moveBy(const Offset(20, 20));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expectNothingFloats(tester, s1);
      expect(ended, isNotEmpty, reason: 'the drag was reported as over (the others stop seeing it)');
    }, skip: _skipKnown); // Known failure (build 126): the card that took the dragged card's old slot floats where the finger was, forever (white outline in the screenshot)

    testWidgets('the other player moves the dragged card elsewhere: the drag ends and nothing is left floating', (tester) async {
      final s0 = stateOf(_reversed());
      await tester.pumpWidget(board(s0));
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('card-5'))));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(24, 10));
      await tester.pump();
      // They took card 5 from slot 10 to slot 3 (card 12 came to slot 10).
      final s1 = stateOf(_swap(_reversed(), 10, 3));
      await tester.pumpWidget(board(s1));
      await gesture.moveBy(const Offset(20, 20));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expectNothingFloats(tester, s1);
      expect(ended, isNotEmpty);
    }, skip: _skipKnown); // Known failure (build 126): the drag never ends: onPanEnd sees another slot and returns before clearing it

    testWidgets('after such a drag, cards that lock in its old slot are not lifted off their places', (tester) async {
      final s0 = stateOf(_reversed());
      await tester.pumpWidget(board(s0));
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('card-5'))));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(24, 10));
      await tester.pump();
      await tester.pumpWidget(board(stateOf(_swap(_reversed(), 10, 3))));
      await gesture.up();
      await tester.pumpAndSettle();
      // Later the whole middle locks (the others played on): slots 5, 6, 9 and 10 are in place.
      final later = _reversed();
      for (final home in [5, 6, 9, 10]) {
        final at = later.indexOf(home);
        later[at] = later[home];
        later[home] = home;
      }
      final s2 = stateOf(later);
      expect(s2.board.isLocked(10), isTrue);
      await tester.pumpWidget(board(s2));
      await tester.pumpAndSettle();
      expectNothingFloats(tester, s2);
    }, skip: _skipKnown); // Known failure (build 126): a stuck drag lifts the locked cluster at its old slot ("a stuck moving piece of blocks already fixed in place")
  });

  group('this player\'s live row after such a drag', () {
    test('a drag whose end never came does not silence the player\'s picks for good', () {
      fakeAsync((async) {
        final sent = <CoopLive>[];
        final start = DateTime.utc(2026, 10, 17, 12);
        final sender = LiveSender(userId: 'bob', board: 1, clock: () => start.add(async.elapsed), send: (s) async => sent.add(s));
        // The board lost the drag's end (above): no dragEnd reaches the sender.
        sender.dragStart(5, 0.6, 0.6);
        async.elapse(const Duration(seconds: 10));
        sender.pick(7);
        async.elapse(const Duration(seconds: 1));
        expect(sent.last.phase, LivePhase.pick, reason: 'the others see the pick');
      });
    }, skip: _skipKnown); // Known failure (build 126): the sender still thinks the finger holds card 5, so every later pick is held back and the others see none
  });

  group('the shared board and the others\' screens', () {
    final spec = BoardSpec(GameMode.cards, 4, 5, 'Medium', tier: 3);

    Future<void> settle() async {
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    ProviderContainer device(FakeCoopServer server, String id) => ProviderContainer(
      overrides: [
        coopBackendProvider.overrideWithValue(FakeCoopBackend(server, id)),
        currentUserIdProvider.overrideWithValue(id),
        coopTimingProvider.overrideWithValue(const CoopTiming(presenceGap: Duration(milliseconds: 5), markFor: Duration(milliseconds: 60))),
      ],
    );

    Future<(ProviderContainer, ProviderContainer, List<int>)> start(int seed) async {
      final server = FakeCoopServer();
      final amy = device(server, 'amy'), bob = device(server, 'bob');
      addTearDown(amy.dispose);
      addTearDown(bob.dispose);
      final base = Board.shuffled(spec, seed: seed).slots;
      final game = await amy.read(coopProvider.notifier).create(puzzleId: 'p1', grid: 'cards-4x5t3', layout: base);
      await bob.read(coopProvider.notifier).join(game.code);
      await settle();
      return (amy, bob, base);
    }

    test('two players drag the same card at once: the first drop wins, the second slides back, nothing is left on either screen', () async {
      final (amy, bob, base) = await start(11);
      final a = amy.read(coopProvider.notifier), b = bob.read(coopProvider.notifier);
      final board = Board(spec, base);
      final card = board.slots.firstWhere((c) => board.slots.indexOf(c) != c);
      final from = board.slotOfCard(card);
      a.dragStart(card, 0.1, 0.1);
      b.dragStart(card, 0.1, 0.1);
      await settle();
      // Amy drops it in its place; Bob, who has not heard of that yet, drops it next door.
      a.dragEnd(dropped: true);
      final amyMove = board.moveTo(from, card)!;
      a.submit(CoopOpKind.move, board.slots, amyMove.slots);
      b.dragEnd(dropped: true);
      final other = [
        for (var s = 0; s < board.cells; s++)
          if (s != from && s != card && !board.isLocked(s)) s,
      ].first;
      final bobMove = board.moveTo(from, other)!;
      final shown = b.submit(CoopOpKind.move, board.slots, bobMove.slots);
      expect(shown, isNotNull, reason: 'Bob\'s move shows at once on his screen');
      await settle();
      await b.catchUp();
      await settle();
      expect(bob.read(coopProvider).layout, amy.read(coopProvider).layout, reason: 'one board');
      expect(bob.read(coopProvider).layout, amyMove.slots, reason: 'Amy\'s drop came first; Bob\'s did not fit and went back');
      final later = DateTime.now().add(const Duration(seconds: 3));
      expect(a.liveTracks.ghosts(later), isEmpty);
      expect(b.liveTracks.ghosts(later), isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await settle();
      expect(amy.read(coopProvider).marks.isEmpty && bob.read(coopProvider).marks.isEmpty, isTrue, reason: 'marks fade');
    });

    test('marks of many quick moves (group moves, a catch-up batch) all fade', () async {
      final (amy, bob, base) = await start(12);
      final a = amy.read(coopProvider.notifier);
      var layout = base;
      for (var i = 0; i < 8; i++) {
        final b = Board(spec, layout);
        final from = [
          for (var s = 0; s < b.cells; s++)
            if (!b.isLocked(s)) s,
        ][i % 3];
        final to = [
          for (var s = 0; s < b.cells; s++)
            if (s != from && !b.isLocked(s)) s,
        ].last;
        final after = b.moveTo(from, to);
        if (after == null) continue;
        a.submit(CoopOpKind.move, layout, after.slots);
        layout = after.slots;
      }
      await settle();
      expect(bob.read(coopProvider).marks.moved, isNotEmpty);
      await bob.read(coopProvider.notifier).catchUp();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await settle();
      expect(bob.read(coopProvider).marks.moved, isEmpty, reason: 'every mark faded, none came back with the catch-up');
    });

    test('rapid picks, a drag and a put-down while updates are on their way end as nothing in hand on the other screen', () async {
      final (amy, bob, base) = await start(13);
      final a = amy.read(coopProvider.notifier), b = bob.read(coopProvider.notifier);
      a.hold(base[0]);
      a.hold(base[1]);
      a.dragStart(base[2], 0.3, 0.3);
      a.dragMove(0.4, 0.3);
      a.dragEnd(dropped: false);
      a.hold(base[3]);
      a.hold(null);
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await settle();
      expect(b.liveTracks.picks, isEmpty);
      expect(b.liveTracks.ghosts(DateTime.now()), isEmpty);
      expect(bob.read(coopProvider).marks.held, isEmpty);
    });

    test('a drop whose move never comes (lost, refused) goes back after 2 s; a late move then still lands', () {
      final tracks = LiveTracks();
      final t0 = DateTime.utc(2026, 10, 17, 12);
      tracks.add(const CoopLive(userId: 'amy', board: 1, phase: LivePhase.drag, card: 3, x: 0.2, y: 0.2, drag: 1, seq: 1), t0);
      tracks.add(const CoopLive(userId: 'amy', board: 1, phase: LivePhase.drop, card: 3, x: 0.8, y: 0.2, drag: 1, seq: 2, t: 400), t0.add(const Duration(milliseconds: 400)));
      expect(tracks.ghosts(t0.add(const Duration(seconds: 2))), hasLength(1));
      expect(tracks.ghosts(t0.add(const Duration(milliseconds: 2500))), isEmpty);
      expect(tracks.onMove('amy', [3]), isFalse, reason: 'nothing left to settle');
    });
  });
}
