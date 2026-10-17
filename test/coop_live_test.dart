// Live picks and drags in Play together (docs/multiplayer.md, "Live picks and drags"): the live
// row's states, the sender's pace and budget (Appwrite: 120 row updates a minute per player), the
// smooth play-back of another player's drag, and what reaches the other devices.

import 'package:carden/data/coop_repository.dart';
import 'package:carden/game/board.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/coop/coop_controller.dart';
import 'package:carden/state/coop/coop_live.dart';
import 'package:carden/state/coop/coop_models.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_coop.dart';

/// A sender on a fake clock: what it sends lands in [sent] after [answer].
({LiveSender sender, List<(Duration, CoopLive)> sent}) _sender(FakeAsync async, {Duration answer = const Duration(milliseconds: 80), Future<void> Function(CoopLive)? send}) {
  final sent = <(Duration, CoopLive)>[];
  final start = DateTime.utc(2026, 10, 17, 12);
  final sender = LiveSender(
    userId: 'amy',
    board: 1,
    clock: () => start.add(async.elapsed),
    send: send ??
        (s) async {
          await Future<void>.delayed(answer);
          sent.add((async.elapsed, s));
        },
  );
  return (sender: sender, sent: sent);
}

void main() {
  group('the live row', () {
    test('reads back what it wrote, and only from its own player', () {
      const s = CoopLive(userId: 'amy', board: 2, phase: LivePhase.drag, card: 7, x: 0.25, y: 0.75, drag: 1000, seq: 1200, t: 200);
      final row = {'userId': 'amy', 'gameId': 'g', r'$permissions': CoopLive.permissionsFor('g', 'amy'), ...s.toData()};
      final back = CoopLive.fromRow(row, cells: 20)!;
      expect((back.phase, back.card, back.x, back.y, back.drag, back.seq, back.t, back.board), (LivePhase.drag, 7, 0.25, 0.75, 1000, 1200, 200, 2));
      // A row that does not prove its author, a card that is not on the board, a wild position.
      expect(CoopLive.fromRow({...row, r'$permissions': ['read("team:g")', 'update("user:bob")']}, cells: 20), isNull);
      expect(CoopLive.fromRow({...row, 'card': 20}, cells: 20), isNull);
      expect(CoopLive.fromRow({...row, 'x': 9.0}, cells: 20), isNull);
      // Nothing in hand needs no card.
      expect(CoopLive.fromRow({...row, 'phase': '', 'card': -1}, cells: 20)!.phase, LivePhase.none);
    });

    test('its id is the one the api function makes (md5 of live:<game>:<player>)', () {
      // functions/api/test/coop-live.test.mjs checks the same value.
      expect(CoopLive.rowId('game1', 'amy'), '6d22d57a1a7f6d5cbd1c5ec49d7ee45b');
    });
  });

  group('the sender', () {
    test('a pick and a put-down go at once; the same pick twice goes once', () {
      fakeAsync((async) {
        final (:sender, :sent) = _sender(async);
        sender.pick(4);
        sender.pick(4);
        async.elapse(const Duration(milliseconds: 100));
        expect(sent.map((e) => (e.$2.phase, e.$2.card)), [(LivePhase.pick, 4)]);
        expect(sent.single.$1, const Duration(milliseconds: 80), reason: 'no waiting before it goes');
        sender.pick(null);
        async.elapse(const Duration(milliseconds: 100));
        expect(sent.last.$2.phase, LivePhase.none);
      });
    });

    test('a drag sends where the card is 5 times a second, the newest position only, then how it ended', () {
      fakeAsync((async) {
        final (:sender, :sent) = _sender(async);
        sender.dragStart(3, 0.1, 0.1);
        // A finger moving for 2 s, one event per frame.
        for (var f = 1; f <= 120; f++) {
          async.elapse(const Duration(milliseconds: 16));
          sender.dragMove(0.1 + f * 0.005, 0.1);
        }
        sender.dragEnd(dropped: true);
        async.elapse(const Duration(seconds: 1));
        final drags = [for (final e in sent) if (e.$2.phase == LivePhase.drag) e.$2];
        expect(drags.length, inInclusiveRange(9, 12), reason: '2 s at 5 a second, plus the start');
        expect(sent.last.$2.phase, LivePhase.drop);
        expect(sent.last.$2.x, closeTo(0.7, 1e-9), reason: 'the drop is where the finger let go');
        expect(drags.first.t, 0);
        expect(drags.map((d) => d.t).toList(), orderedEquals([...drags.map((d) => d.t)]..sort()));
        expect(sent.map((e) => e.$2.drag).toSet().length, 1, reason: 'one drag id');
        final seqs = sent.map((e) => e.$2.seq).toList();
        for (var i = 1; i < seqs.length; i++) {
          expect(seqs[i], greaterThan(seqs[i - 1]));
        }
      });
    });

    test('while an update is on its way only the newest waits, and the end of a drag is never folded away', () {
      fakeAsync((async) {
        final (:sender, :sent) = _sender(async, answer: const Duration(milliseconds: 500));
        sender.pick(1);
        sender.pick(2);
        sender.pick(5);
        async.elapse(const Duration(seconds: 2));
        expect(sent.map((e) => e.$2.card), [1, 5]);
        sent.clear();
        sender.dragStart(5, 0.5, 0.5);
        sender.dragMove(0.6, 0.5);
        sender.dragEnd(dropped: false); // a cancel, while the start is on its way
        sender.pick(null);
        async.elapse(const Duration(seconds: 3));
        expect(sent.map((e) => e.$2.phase), [LivePhase.drag, LivePhase.cancel, LivePhase.none]);
      });
    });

    test('a cancelled drag shows the card still picked again', () {
      fakeAsync((async) {
        final (:sender, :sent) = _sender(async);
        sender.pick(6);
        async.elapse(const Duration(milliseconds: 200));
        sender.dragStart(6, 0.3, 0.3);
        async.elapse(const Duration(milliseconds: 200));
        sender.dragEnd(dropped: false);
        async.elapse(const Duration(milliseconds: 500));
        expect(sent.map((e) => e.$2.phase), [LivePhase.pick, LivePhase.drag, LivePhase.cancel, LivePhase.pick]);
      });
    });

    test('positions slow down as the minute\'s budget runs low and stop before it is spent; picks still go', () {
      fakeAsync((async) {
        final (:sender, :sent) = _sender(async, answer: const Duration(milliseconds: 20));
        // A long drag: a full minute of finger movement.
        sender.dragStart(1, 0, 0);
        for (var f = 1; f <= 3600; f++) {
          async.elapse(const Duration(milliseconds: 16));
          sender.dragMove((f % 100) / 100, 0.5);
        }
        final inMinute = sent.length;
        expect(inMinute, lessThanOrEqualTo(sender.budget), reason: 'under Appwrite\'s 120 a minute');
        expect(inMinute, greaterThan(90), reason: 'the budget is used, not wasted');
        // The first seconds at full pace, the last ones slow.
        final firstSecond = sent.where((e) => e.$1 < const Duration(seconds: 1)).length;
        expect(firstSecond, greaterThanOrEqualTo(5));
        sender.dragEnd(dropped: false);
        async.elapse(const Duration(minutes: 1));
        expect(sent.last.$2.phase, LivePhase.cancel, reason: 'the end goes once the minute moves on');
      });
    });

    test('a refusal (429) waits, then sends what is in hand; a missing row stops sending', () {
      fakeAsync((async) {
        var refuse = true;
        final sent = <CoopLive>[];
        final (:sender, sent: _) = _sender(async, send: (s) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          if (refuse) throw const LiveRateLimited();
          sent.add(s);
        });
        sender.pick(3);
        async.elapse(const Duration(seconds: 1));
        expect(sent, isEmpty);
        refuse = false;
        async.elapse(const Duration(seconds: 10));
        expect(sent.map((s) => s.card), [3]);

        final (sender: other, sent: _) = _sender(async, send: (s) async => throw const LiveRowMissing());
        other.pick(1);
        async.elapse(const Duration(seconds: 1));
        expect(other.disabled, isTrue);
      });
    });
  });

  group('playing a drag back', () {
    final t0 = DateTime.utc(2026, 10, 17, 12);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('glides between positions behind the newest one, never back', () {
      final path = DragPath(userId: 'amy', drag: 1, card: 3);
      // Positions every 200 ms along x, arriving 100 ms later with up to 80 ms of jitter.
      const jitter = [0, 60, 10, 80, 30, 0, 50];
      for (var i = 0; i < jitter.length; i++) {
        path.add(i * 200, i * 0.1, 0.5, at(100 + i * 200 + jitter[i]));
      }
      expect(path.delay, inInclusiveRange(150, 300));
      var last = -1.0;
      final xs = <double>[];
      for (var ms = 100; ms <= 1700; ms += 16) {
        final p = path.positionAt(at(ms));
        expect(p.x, greaterThanOrEqualTo(last), reason: 'never back');
        expect(p.y, 0.5);
        last = p.x;
        xs.add(p.x);
      }
      expect(xs.first, 0, reason: 'starts where the card was');
      expect(xs.last, closeTo(0.6, 1e-9), reason: 'ends at the newest position');
      // In between, positions that were never sent: a glide, not jumps of a whole step.
      final steps = [for (var i = 1; i < xs.length; i++) xs[i] - xs[i - 1]];
      expect(steps.reduce((a, b) => a > b ? a : b), lessThan(0.1));
      expect(xs.where((x) => (x * 10 - (x * 10).round()).abs() > 0.05).length, greaterThan(xs.length ~/ 2));
    });

    test('a position that arrives late goes in its place on the path', () {
      final path = DragPath(userId: 'amy', drag: 1, card: 3);
      path.add(0, 0, 0, at(100));
      path.add(400, 0.4, 0, at(500));
      path.add(200, 0.2, 0, at(520));
      expect(path.positionAt(at(5000)).x, closeTo(0.4, 1e-9));
      expect(path.latest.x, 0.4);
    });

    test('Reduce motion: the newest position, no glide', () {
      final path = DragPath(userId: 'amy', drag: 1, card: 3);
      path.add(0, 0, 0, at(100));
      path.add(200, 0.2, 0, at(300));
      expect(path.positionAt(at(300), latest: true).x, 0.2);
    });
  });

  group('the other players\' states', () {
    final t0 = DateTime.utc(2026, 10, 17, 12);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));
    CoopLive s(LivePhase phase, int seq, {int card = 3, int drag = 1000, double x = 0.5, int t = 0}) =>
        CoopLive(userId: 'amy', board: 1, phase: phase, card: card, x: x, y: 0.5, drag: drag, seq: seq, t: t);

    test('a pick shows until it is put down; an older state arriving late changes nothing', () {
      final tracks = LiveTracks();
      expect(tracks.add(s(LivePhase.pick, 10, card: 4), at(0)), isTrue);
      expect(tracks.picks, {'amy': 4});
      expect(tracks.add(s(LivePhase.pick, 9, card: 2), at(10)), isFalse);
      expect(tracks.picks, {'amy': 4});
      tracks.add(s(LivePhase.none, 11, card: -1), at(20));
      expect(tracks.picks, isEmpty);
      expect(tracks.heard, ['amy']);
    });

    test('a drag shows until its move arrives; its late positions do not bring it back', () {
      final tracks = LiveTracks();
      expect(tracks.add(s(LivePhase.drag, 1, t: 0), at(0)), isTrue, reason: 'a drag started');
      expect(tracks.add(s(LivePhase.drag, 2, t: 200, x: 0.6), at(200)), isFalse, reason: 'only a position');
      expect(tracks.ghosts(at(300)).single.card, 3);
      tracks.add(s(LivePhase.drop, 4, t: 400, x: 0.8), at(400));
      expect(tracks.ghosts(at(1500)).single.x, closeTo(0.8, 1e-9), reason: 'waits where it was dropped');
      expect(tracks.onMove('amy', [3, 9]), isTrue);
      expect(tracks.ghosts(at(1600)), isEmpty);
      tracks.add(s(LivePhase.drag, 3, t: 300, x: 0.7), at(1700));
      expect(tracks.ghosts(at(1800)), isEmpty, reason: 'a position of a finished drag');
    });

    test('a cancelled drag goes back at once; a drag not heard from for 2 s or a drop without its move goes back', () {
      final tracks = LiveTracks();
      tracks.add(s(LivePhase.drag, 1), at(0));
      tracks.add(s(LivePhase.cancel, 2), at(100));
      expect(tracks.ghosts(at(150)), isEmpty);
      tracks.add(s(LivePhase.drag, 3, drag: 2000), at(200));
      expect(tracks.ghosts(at(2100)), hasLength(1));
      expect(tracks.ghosts(at(2300)), isEmpty, reason: 'stale');
      tracks.add(s(LivePhase.drag, 4, drag: 3000), at(3000));
      tracks.add(s(LivePhase.drop, 5, drag: 3000), at(3100));
      expect(tracks.ghosts(at(5000)), hasLength(1));
      expect(tracks.ghosts(at(5200)), isEmpty, reason: 'the move never came');
    });

    test('a player who left or went away leaves nothing behind', () {
      final tracks = LiveTracks();
      tracks.add(s(LivePhase.drag, 1), at(0));
      tracks.forget('amy');
      expect(tracks.ghosts(at(10)), isEmpty);
      expect(tracks.picks, isEmpty);
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

    test('a pick reaches the others at once; a drag reaches them as a card to draw, until its move', () async {
      final server = FakeCoopServer();
      final amy = device(server, 'amy'), bob = device(server, 'bob');
      addTearDown(amy.dispose);
      addTearDown(bob.dispose);
      final base = Board.shuffled(spec, seed: 4).slots;
      final game = await amy.read(coopProvider.notifier).create(puzzleId: 'p1', grid: 'cards-4x5t3', layout: base);
      await bob.read(coopProvider.notifier).join(game.code);
      await settle();
      final a = amy.read(coopProvider.notifier);
      final board = Board(spec, base);
      final card = board.slots[0];

      a.hold(card);
      await settle();
      expect(bob.read(coopProvider).marks.held, {card: 'amy'}, reason: 'the pick, without waiting for the presence');

      a.dragStart(card, 0.12, 0.1);
      await settle();
      final b = bob.read(coopProvider.notifier);
      expect(b.liveTracks.ghosts(DateTime.now()).single.card, card);
      expect(bob.read(coopProvider).marks.held, isEmpty, reason: 'a dragged card is drawn where it is, not marked');

      // Amy drops it on slot 5: her move follows the drop.
      a.dragEnd(dropped: true);
      final after = board.moveTo(0, 5)!;
      a.submit(CoopOpKind.move, board.slots, after.slots);
      await settle();
      expect(b.liveTracks.ghosts(DateTime.now()), isEmpty);
      expect(bob.read(coopProvider).layout, after.slots);
      // Nothing of Amy's own row comes back to her.
      expect(amy.read(coopProvider.notifier).liveTracks.heard, isEmpty);
    });

    test('without live rows (a game from before them) picks still come through the presence', () async {
      final server = FakeCoopServer();
      final amy = device(server, 'amy'), bob = device(server, 'bob');
      addTearDown(amy.dispose);
      addTearDown(bob.dispose);
      final base = Board.shuffled(spec, seed: 6).slots;
      final game = await amy.read(coopProvider.notifier).create(puzzleId: 'p1', grid: 'cards-4x5t3', layout: base);
      await bob.read(coopProvider.notifier).join(game.code);
      server.live.clear();
      await settle();
      amy.read(coopProvider.notifier).hold(base[2]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await settle();
      expect(bob.read(coopProvider).marks.held, {base[2]: 'amy'});
      expect(amy.read(coopProvider.notifier).liveSender!.disabled, isTrue);
    });
  });
}
