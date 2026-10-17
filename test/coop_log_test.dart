// Play together's shared board (lib/state/coop/, docs/multiplayer.md): changes as slots with the
// card expected before and the card after, applied in the server's order by every device, whatever
// order they arrive in. Random interleavings of several players' moves end on the same board on
// every device; a change that lost its cards to an earlier one is skipped everywhere and slides back
// on its author's board; what arrives twice counts once.
import 'dart:math';

import 'package:carden/game/board.dart';
import 'package:carden/state/coop/board_change.dart';
import 'package:carden/state/coop/coop_log.dart';
import 'package:carden/state/coop/coop_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _game = 'g1';

bool _isPermutation(List<int> l) => (List.of(l)..sort()).asMap().entries.every((e) => e.key == e.value);

/// One player's device in the simulation: its log, and its changes waiting to be sent (one at a time,
/// in order, as `CoopController` sends them).
class _Device {
  _Device(this.id, List<int> base) : log = CoopLog(gameId: _game, board: 1, base: base, me: id);
  final String id;
  final CoopLog log;
  final outbox = <CoopOp>[];
  bool inFlight = false;
  int made = 0;
  final dropped = <String>{};
}

/// What the server does: numbers changes as they arrive (`$sequence`).
class _Server {
  int seq = 100;
  final ops = <CoopOp>[];
  CoopOp take(CoopOp op) {
    // Rows of other games take numbers too.
    seq += 1 + (op.id.hashCode % 3).abs();
    final numbered = op.withSeq(seq);
    ops.add(numbered);
    return numbered;
  }

  /// The board every device must end on: the changes in order, each only when it fits.
  List<int> replay(List<int> base) {
    var b = base;
    for (final op in ops..sort((a, c) => a.seq!.compareTo(c.seq!))) {
      if (op.change.fits(b)) b = op.change.applyTo(b);
    }
    return b;
  }
}

void main() {
  final spec = BoardSpec(GameMode.cards, 4, 5, 'Medium', tier: 3);

  group('BoardChange', () {
    test('a change is the slots whose card changed, and reads back from its row', () {
      final before = [3, 0, 1, 2, 4];
      final after = [0, 3, 1, 2, 4];
      final c = BoardChange.between(before, after);
      expect(c.slots, [const SlotChange(0, 3, 0), const SlotChange(1, 0, 3)]);
      expect(c.encode(), '0:3:0,1:0:3');
      expect(BoardChange.decode(c.encode(), 5), c);
      expect(c.fits(before), isTrue);
      expect(c.applyTo(before), after);
      expect(c.inverse.applyTo(after), before);
      expect(c.locks, {0});
      expect(c.fits(after), isFalse, reason: 'its cards moved on');
    });

    test('rows that are not a change of this board are refused', () {
      for (final bad in ['', '0:1', '0:1:2', '0:1:1,0:1:1', '9:0:1,1:1:0', 'a:b:c', '0:1:0,1:0:2', '0:0:1,1:0:0']) {
        expect(BoardChange.decode(bad, 5), isNull, reason: bad);
      }
    });

    test('a row proves its author by its permissions', () {
      Map<String, dynamic> row(String user, List<String> perms) => {r'$id': 'm1', r'$sequence': '7', r'$permissions': perms, 'gameId': _game, 'board': 1, 'userId': user, 'kind': 'move', 'changes': '0:1:0,1:0:1'};
      expect(CoopOp.fromRow(row('amy', CoopOp.permissionsFor(_game, 'amy')), cells: 4)?.seq, 7);
      expect(CoopOp.fromRow(row('amy', ['read("team:$_game")', 'read("user:bob")']), cells: 4), isNull, reason: 'bob wrote it in amy\'s name');
      expect(CoopOp.fromRow({...row('amy', CoopOp.permissionsFor(_game, 'amy')), 'kind': 'teleport'}, cells: 4)!.kind, CoopOpKind.other, reason: 'a kind from a later build still applies');
    });
  });

  group('CoopLog', () {
    test('random interleavings of three players converge to the same board on every device', () {
      for (var seed = 0; seed < 100; seed++) {
        final rnd = Random(seed);
        final base = Board.shuffled(spec, seed: seed).slots;
        final server = _Server();
        final devices = [for (final id in ['amy', 'bob', 'cat']) _Device(id, base)];
        // Realtime events not yet delivered: (device, op) pairs, delivered in any order.
        final inbox = <(_Device, CoopOp)>[];
        // Answers to creates not yet received by their author.
        final answers = <(_Device, CoopOp)>[];
        var steps = 0;
        while (steps < 400) {
          steps++;
          final r = rnd.nextInt(10);
          final d = devices[rnd.nextInt(devices.length)];
          if (r < 4 && d.made < 25) {
            // A move on the board this device shows.
            final board = Board(spec, d.log.layout);
            final from = rnd.nextInt(board.cells);
            final to = rnd.nextInt(board.cells);
            if (board.isLocked(from) || from == to) continue;
            final after = board.moveTo(from, to);
            if (after == null) continue;
            final op = CoopOp(id: '${d.id}-${d.made++}', gameId: _game, board: 1, userId: d.id, kind: CoopOpKind.move, change: BoardChange.between(board.slots, after.slots));
            final u = d.log.addLocal(op);
            expect(u, isNotNull);
            d.outbox.add(op);
          } else if (r < 6 && d.outbox.isNotEmpty && !d.inFlight) {
            // The next change reaches the server.
            final numbered = server.take(d.outbox.removeAt(0));
            d.inFlight = true;
            answers.add((d, numbered));
            for (final other in devices) {
              inbox.add((other, numbered));
            }
          } else if (r < 8 && inbox.isNotEmpty) {
            final (to, op) = inbox.removeAt(rnd.nextInt(inbox.length));
            final u = to.log.addRemote(op);
            to.dropped.addAll(u.dropped.map((o) => o.id));
          } else if (answers.isNotEmpty) {
            final (to, op) = answers.removeAt(rnd.nextInt(answers.length));
            to.inFlight = false;
            to.log.confirm(op.id, op.seq!);
          }
          for (final dev in devices) {
            expect(_isPermutation(dev.log.layout), isTrue, reason: 'seed $seed: ${dev.id} shows a board');
          }
        }
        // Everything still on its way arrives.
        while (devices.any((d) => d.outbox.isNotEmpty || d.inFlight) || inbox.isNotEmpty || answers.isNotEmpty) {
          for (final (to, op) in answers) {
            to.inFlight = false;
            to.log.confirm(op.id, op.seq!);
          }
          answers.clear();
          for (final d in devices) {
            if (d.outbox.isNotEmpty && !d.inFlight) {
              final numbered = server.take(d.outbox.removeAt(0));
              d.inFlight = true;
              answers.add((d, numbered));
              for (final other in devices) {
                inbox.add((other, numbered));
              }
            }
          }
          inbox.shuffle(rnd);
          for (final (to, op) in inbox) {
            to.log.addRemote(op);
          }
          inbox.clear();
        }
        final expected = server.replay(base);
        for (final d in devices) {
          expect(d.log.pending, isEmpty, reason: 'seed $seed');
          expect(d.log.confirmed, expected, reason: 'seed $seed: ${d.id} agrees with the server order');
          expect(d.log.layout, expected, reason: 'seed $seed: ${d.id} shows the shared board');
          expect(d.log.ops.length, server.ops.length, reason: 'seed $seed: every change once');
        }
        // The cards each player locked are counted the same everywhere.
        for (final who in ['amy', 'bob', 'cat']) {
          expect({for (final d in devices) d.log.locksBy(who)}.length, 1, reason: 'seed $seed: locks of $who');
        }
      }
    });

    test('two players take the same card: the server order decides, the later one slides back', () {
      final base = [1, 0, 3, 2];
      final amy = CoopLog(gameId: _game, board: 1, base: base, me: 'amy');
      final bob = CoopLog(gameId: _game, board: 1, base: base, me: 'bob');
      // Both move card 1 at once: Amy to slot 1 (locks 0 and 1), Bob swaps it with card 3.
      final a = CoopOp(id: 'a', gameId: _game, board: 1, userId: 'amy', kind: CoopOpKind.move, change: BoardChange.between(base, [0, 1, 3, 2]));
      final b = CoopOp(id: 'b', gameId: _game, board: 1, userId: 'bob', kind: CoopOpKind.move, change: BoardChange.between(base, [3, 0, 1, 2]));
      amy.addLocal(a);
      bob.addLocal(b);
      expect(bob.layout, [3, 0, 1, 2], reason: 'a move shows at once');
      // The server took Amy's first. Bob hears it before his own answer.
      final u = bob.addRemote(a.withSeq(10));
      expect(u.dropped.map((o) => o.id), ['b'], reason: 'his card slides back');
      expect(bob.layout, [0, 1, 3, 2]);
      expect(u.applied.single.userId, 'amy');
      bob.confirm('b', 11);
      amy.confirm('a', 10);
      amy.addRemote(b.withSeq(11));
      expect(amy.layout, bob.layout);
      expect(bob.wasSkipped('b'), isTrue);
      expect(amy.locksBy('amy'), 2);
      expect(amy.locksBy('bob'), 0);
    });

    test('an answer that comes after a later change: the order is fixed when it arrives', () {
      final base = [1, 0, 3, 2];
      final bob = CoopLog(gameId: _game, board: 1, base: base, me: 'bob');
      final b = CoopOp(id: 'b', gameId: _game, board: 1, userId: 'bob', kind: CoopOpKind.move, change: BoardChange.between(base, [3, 0, 1, 2]));
      final a = CoopOp(id: 'a', gameId: _game, board: 1, userId: 'amy', kind: CoopOpKind.move, change: BoardChange.between(base, [0, 1, 3, 2]));
      bob.addLocal(b);
      // Bob's own answer first (seq 12), then Amy's change, numbered earlier (11), arrives.
      bob.confirm('b', 12);
      expect(bob.layout, [3, 0, 1, 2]);
      final u = bob.addRemote(a.withSeq(11));
      expect(bob.layout, [0, 1, 3, 2], reason: 'Amy\'s came first on the server');
      expect(u.dropped.map((o) => o.id), ['b']);
    });

    test('a change seen twice (realtime, then the catch-up) counts once', () {
      final base = [1, 0, 3, 2];
      final log = CoopLog(gameId: _game, board: 1, base: base, me: 'cat');
      final a = CoopOp(id: 'a', gameId: _game, board: 1, userId: 'amy', kind: CoopOpKind.move, change: BoardChange.between(base, [0, 1, 3, 2]), seq: 5);
      final b = CoopOp(id: 'b', gameId: _game, board: 1, userId: 'bob', kind: CoopOpKind.move, change: BoardChange.between([0, 1, 3, 2], [0, 1, 2, 3]), seq: 9);
      log.addRemote(b);
      log.addRemote(a);
      final again = [log.addRemote(a), log.addRemote(b)];
      expect(again.every((u) => !u.changed), isTrue);
      expect(log.ops.map((o) => o.id), ['a', 'b']);
      expect(log.isSolved, isTrue);
      expect(log.locksBy('amy'), 2);
      expect(log.locksBy('bob'), 2);
    });

    test('changes of another board or game are ignored', () {
      final log = CoopLog(gameId: _game, board: 2, base: const [1, 0], me: 'cat');
      final change = BoardChange.between(const [1, 0], const [0, 1]);
      expect(log.addRemote(CoopOp(id: 'x', gameId: _game, board: 1, userId: 'amy', kind: CoopOpKind.move, change: change, seq: 3)).changed, isFalse);
      expect(log.addRemote(CoopOp(id: 'y', gameId: 'g2', board: 2, userId: 'amy', kind: CoopOpKind.move, change: change, seq: 4)).changed, isFalse);
      expect(log.ops, isEmpty);
    });

    test('a refused change goes back', () {
      final log = CoopLog(gameId: _game, board: 1, base: const [1, 0, 3, 2], me: 'amy');
      final op = CoopOp(id: 'a', gameId: _game, board: 1, userId: 'amy', kind: CoopOpKind.move, change: BoardChange.between(const [1, 0, 3, 2], const [0, 1, 3, 2]));
      log.addLocal(op);
      final u = log.reject('a');
      expect(log.layout, [1, 0, 3, 2]);
      expect(u.dropped.single.id, 'a');
    });

    test('a change that does not fit the board shown is not made', () {
      final log = CoopLog(gameId: _game, board: 1, base: const [1, 0, 3, 2], me: 'amy');
      final stale = CoopOp(id: 's', gameId: _game, board: 1, userId: 'amy', kind: CoopOpKind.move, change: BoardChange.between(const [0, 1, 3, 2], const [1, 0, 3, 2]));
      expect(log.addLocal(stale), isNull);
      expect(log.pending, isEmpty);
    });

    test('Magic, Shuffle and Gather do not earn a guest the rewards; a move that locks does', () {
      final log = CoopLog(gameId: _game, board: 1, base: const [1, 0, 3, 2], me: 'amy');
      log.addRemote(CoopOp(id: 'm', gameId: _game, board: 1, userId: 'bob', kind: CoopOpKind.magic, change: BoardChange.between(const [1, 0, 3, 2], const [0, 1, 3, 2]), seq: 1));
      expect(log.locksBy('bob'), 0);
      log.addRemote(CoopOp(id: 'n', gameId: _game, board: 1, userId: 'bob', kind: CoopOpKind.move, change: BoardChange.between(const [0, 1, 3, 2], const [0, 1, 2, 3]), seq: 2));
      expect(log.locksBy('bob'), 2);
    });

    test('a catch-up starts from the change received half a minute before the newest one', () {
      var now = DateTime(2026, 10, 17, 12);
      final log = CoopLog(gameId: _game, board: 1, base: List.generate(6, (i) => (i + 1) % 6), me: 'cat', clock: () => now);
      expect(log.catchUpFrom(), 0);
      var layout = log.layout;
      for (var i = 0; i < 4; i++) {
        final after = List.of(layout);
        final t = after[0];
        after[0] = after[i + 1];
        after[i + 1] = t;
        log.addRemote(CoopOp(id: 'op$i', gameId: _game, board: 1, userId: 'amy', kind: CoopOpKind.move, change: BoardChange.between(layout, after), seq: 10 + i * 10));
        layout = log.layout;
        now = now.add(const Duration(seconds: 20));
      }
      // Received at 0, 20, 40, 60 s: the newest at 60 s, so from the one at 20 s (seq 20).
      expect(log.catchUpFrom(), 20);
    });
  });
}
