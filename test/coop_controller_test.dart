// Play together on several devices against an in-memory server (test/support/fake_coop.dart):
// joining, moves reaching everyone in any delivery order, a lost answer, a lost connection, removal,
// the end of a game, the next board, presence, and the bridge the game screen will use.
import 'dart:async';
import 'dart:math';

import 'package:carden/data/coop_repository.dart';
import 'package:carden/game/board.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/coop/coop_bridge.dart';
import 'package:carden/state/coop/coop_controller.dart';
import 'package:carden/state/coop/coop_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_coop.dart';

const _fast = CoopTiming(
  presenceGap: Duration(milliseconds: 5),
  keepAlive: Duration(seconds: 5),
  safetyCatchUp: Duration(minutes: 10),
  markFor: Duration(milliseconds: 60),
  retryFirst: Duration(milliseconds: 2),
  retryMax: Duration(milliseconds: 10),
);

Future<void> _settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Player {
  _Player(FakeCoopServer server, this.id) : backend = FakeCoopBackend(server, id) {
    container = ProviderContainer(overrides: [
      coopBackendProvider.overrideWithValue(backend),
      currentUserIdProvider.overrideWithValue(id),
      coopTimingProvider.overrideWithValue(_fast),
    ]);
    container.read(coopProvider);
    _sub = coop.notices.listen(notices.add);
  }

  final String id;
  final FakeCoopBackend backend;
  late final ProviderContainer container;
  final notices = <CoopNotice>[];
  late final StreamSubscription<CoopNotice> _sub;

  CoopController get coop => container.read(coopProvider.notifier);
  CoopState get state => container.read(coopProvider);

  /// A random move on the board this device shows; false when the pick is not a move.
  bool randomMove(BoardSpec spec, Random rnd) {
    final board = Board(spec, state.layout);
    final from = rnd.nextInt(board.cells);
    final to = rnd.nextInt(board.cells);
    if (from == to || board.isLocked(from)) return false;
    final after = board.moveTo(from, to);
    if (after == null) return false;
    return coop.submit(CoopOpKind.move, board.slots, after.slots) != null;
  }

  void dispose() {
    _sub.cancel();
    container.dispose();
  }
}

/// The board the server order gives.
List<int> _serverBoard(FakeCoopServer server, String gameId, int board, List<int> base) {
  var b = base;
  final rows = server.moves.where((m) => m['gameId'] == gameId && m['board'] == board).toList()
    ..sort((a, c) => int.parse(a[r'$sequence'] as String).compareTo(int.parse(c[r'$sequence'] as String)));
  for (final r in rows) {
    final op = CoopOp.fromRow(r, cells: base.length)!;
    if (op.change.fits(b)) b = op.change.applyTo(b);
  }
  return b;
}

class _ListTarget implements CoopBoardTarget {
  _ListTarget(this.layout);
  @override
  List<int> layout;
  final shown = <CoopBoardUpdate>[];
  @override
  void showShared(CoopBoardUpdate update) {
    shown.add(update);
    layout = update.update.after;
  }
}

void main() {
  final spec = BoardSpec(GameMode.cards, 4, 5, 'Medium', tier: 3);

  late FakeCoopServer server;
  late List<_Player> players;

  Future<(_Player host, List<_Player> guests, CoopGame game, List<int> base)> start(int guests, {int seed = 1}) async {
    server = FakeCoopServer();
    players = [for (var i = 0; i <= guests; i++) _Player(server, ['amy', 'bob', 'cat', 'dan', 'eve'][i])];
    final base = Board.shuffled(spec, seed: seed).slots;
    final game = await players.first.coop.create(puzzleId: 'p1', grid: 'cards-4x5t3', layout: base);
    for (final g in players.skip(1)) {
      await g.coop.join(game.code);
      await _settle();
    }
    return (players.first, players.skip(1).toList(), game, base);
  }

  tearDown(() {
    for (final p in players) {
      p.dispose();
    }
  });

  test('the host starts a game, guests join and hear each other join', () async {
    final (host, guests, game, base) = await start(2);
    expect(host.state.playing, isTrue);
    expect(host.state.isHost, isTrue);
    expect(guests.first.state.isGuest, isTrue);
    expect(host.notices.whereType<CoopJoined>().map((n) => n.userId), ['bob', 'cat']);
    expect(guests.first.notices.whereType<CoopJoined>().map((n) => n.userId), ['cat']);
    for (final p in players) {
      expect(p.state.layout, base);
      expect(p.state.game!.playerIds, ['amy', 'bob', 'cat']);
    }
  });

  test('moves in any delivery order end on the same board on every device', () async {
    for (var seed = 0; seed < 12; seed++) {
      final (_, _, game, base) = await start(2, seed: seed);
      final rnd = Random(seed);
      server.hold = true;
      for (var step = 0; step < 120; step++) {
        final r = rnd.nextInt(6);
        if (r < 3) {
          players[rnd.nextInt(players.length)].randomMove(spec, rnd);
        } else if (r == 3) {
          server.release(random: rnd);
        }
        await Future<void>.delayed(Duration.zero);
      }
      server.hold = false;
      for (var i = 0; i < 5; i++) {
        server.release(random: rnd);
        await _settle();
      }
      final expected = _serverBoard(server, game.id, 1, base);
      for (final p in players) {
        expect(p.coop.log!.pending, isEmpty, reason: 'seed $seed ${p.id}');
        expect(p.state.layout, expected, reason: 'seed $seed: ${p.id} shows the server\'s board');
      }
      for (final p in players) {
        p.dispose();
      }
      players = [];
    }
  });

  test('a lost answer is sent again and counts once', () async {
    final (host, guests, game, base) = await start(1);
    final bob = guests.single;
    bob.backend.loseNextAnswer = true;
    expect(bob.randomMove(spec, Random(3)) || bob.randomMove(spec, Random(4)) || bob.randomMove(spec, Random(5)), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await _settle();
    expect(server.moves.length, 1, reason: 'the row id is fixed: the retry found it');
    expect(bob.backend.creates, 2);
    expect(bob.coop.log!.pending, isEmpty);
    expect(host.state.layout, bob.state.layout);
    expect(host.state.layout, isNot(base));
  });

  test('a device that lost its connection catches up on return, without doubles', () async {
    final (host, guests, game, base) = await start(1);
    final bob = guests.single;
    bob.backend.connected = false;
    final rnd = Random(9);
    var made = 0;
    while (made < 8) {
      if (host.randomMove(spec, rnd)) made++;
      await _settle();
    }
    expect(bob.state.layout, base, reason: 'nothing reached Bob');
    bob.backend.connected = true;
    bob.coop.onResume();
    await _settle();
    expect(bob.state.layout, host.state.layout);
    expect(bob.coop.log!.ops.length, 8);
    // The catch-up again: nothing new, nothing twice.
    await bob.coop.catchUp();
    expect(bob.coop.log!.ops.length, 8);
    expect(bob.state.layout, _serverBoard(server, game.id, 1, base));
  });

  test('a reconnect is noticed by the presence the SDK sends again, and what was missed is read', () async {
    final (host, guests, game, base) = await start(1);
    final bob = guests.single;
    bob.backend.dropSocket();
    final rnd = Random(21);
    var made = 0;
    while (made < 5) {
      if (host.randomMove(spec, rnd)) made++;
      await _settle();
    }
    expect(bob.state.layout, base);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    bob.backend.reconnect();
    await _settle();
    expect(bob.state.layout, host.state.layout, reason: 'caught up without a resume');
    expect(host.state.isHere('bob'), isTrue);
  });

  test('a removed player hears it, stops sharing and cannot come back', () async {
    final (host, guests, game, base) = await start(2);
    final bob = guests.first;
    await host.coop.remove('bob');
    await _settle();
    expect(bob.notices.whereType<CoopRemoved>(), hasLength(1));
    expect(bob.state.phase, CoopPhase.removed);
    expect(bob.coop.submit(CoopOpKind.move, base, base.reversed.toList()), isNull);
    expect(host.notices.whereType<CoopLeft>().map((n) => n.userId), ['bob']);
    expect(guests.last.notices.whereType<CoopLeft>().map((n) => n.userId), ['bob']);
    bob.coop.clear();
    await expectLater(bob.coop.join(game.code), throwsA(isA<CoopRefusal>().having((r) => r.reason, 'reason', CoopRefusalReason.removed)));
  });

  test('the host ends the game for everyone; a guest leaving frees the seat', () async {
    final (host, guests, game, _) = await start(2);
    await guests.last.coop.leave();
    await _settle();
    expect(host.notices.whereType<CoopLeft>().map((n) => n.userId), ['cat']);
    expect(host.state.game!.playerIds, ['amy', 'bob']);
    await host.coop.endForEveryone();
    await _settle();
    final ended = guests.first.notices.whereType<CoopEnded>().single;
    expect(ended.game.endReason, 'host');
    expect(guests.first.state.phase, CoopPhase.ended);
    expect(host.state.phase, CoopPhase.none, reason: 'the host keeps the board as their own');
  });

  test('the next board moves the guests onto it; moves of the old board never touch it', () async {
    final (host, guests, game, base) = await start(1);
    final bob = guests.single;
    final rnd = Random(2);
    while (!host.randomMove(spec, rnd)) {}
    await _settle();
    final next = Board.shuffled(spec, seed: 77).slots;
    await host.coop.nextBoard(puzzleId: 'p2', grid: 'cards-4x5t3', layout: next);
    await _settle();
    expect(bob.notices.whereType<CoopNextBoard>().single.game.puzzleId, 'p2');
    expect(bob.state.layout, next);
    expect(bob.state.game!.board, 2);
    expect(bob.state.game!.route, '/game/p2/cards-4x5t3?coop=${game.id}');
    while (!bob.randomMove(spec, rnd)) {}
    await _settle();
    expect(host.state.layout, bob.state.layout);
    expect(bob.coop.log!.board, 2);
  });

  test('presence: who holds which card, and who is away', () async {
    final (host, guests, _, base) = await start(1);
    final bob = guests.single;
    bob.coop.hold(base[3]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await _settle();
    expect(host.state.marks.held, {base[3]: 'bob'});
    expect(host.state.isHere('bob'), isTrue);
    bob.coop.onPause();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await _settle();
    expect(host.state.isHere('bob'), isFalse);
    expect(host.state.marks.held, isEmpty, reason: 'an away player holds nothing');
    bob.backend.dropSocket();
    await _settle();
    expect(host.state.presences.containsKey('bob'), isFalse);
  });

  test('cards another player moved carry their mark for a moment', () async {
    final (host, guests, _, _) = await start(1);
    final bob = guests.single;
    final rnd = Random(11);
    while (!bob.randomMove(spec, rnd)) {}
    await _settle();
    expect(host.state.marks.moved.values.toSet(), {'bob'});
    expect(bob.state.marks.moved, isEmpty, reason: 'a player\'s own moves are not marked');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(host.state.marks.moved, isEmpty);
  });

  test('a guest earns the board only with a card they locked themselves', () async {
    final (host, guests, _, base) = await start(1);
    final bob = guests.single;
    expect(bob.state.placedACard, isFalse);
    // Bob puts the card that belongs in slot 0 there.
    final board = Board(spec, base);
    final after = board.moveTo(board.slotOfCard(0), 0)!;
    bob.coop.submit(CoopOpKind.move, base, after.slots);
    await _settle();
    expect(bob.state.placedACard, isTrue);
    expect(host.state.placedACard, isFalse);
  });

  test('the bridge: own changes are not shown twice, other players\' changes are', () async {
    final (host, guests, _, base) = await start(1);
    final bob = guests.single;
    final screen = _ListTarget(List.of(base));
    final bridge = CoopBridge(host.coop, screen);
    addTearDown(bridge.dispose);
    // Amy moves on her screen, then tells the bridge.
    final board = Board(spec, screen.layout);
    var after = board.moveTo(board.slotOfCard(0), 0)!;
    final before = screen.layout;
    screen.layout = after.slots;
    expect(bridge.localChange(CoopOpKind.move, before, after.slots), isTrue);
    await _settle();
    expect(screen.shown, isEmpty);
    // Bob's move reaches Amy's screen.
    final rnd = Random(4);
    while (!bob.randomMove(spec, rnd)) {}
    await _settle();
    expect(screen.shown, hasLength(1));
    expect(screen.layout, bob.state.layout);
    expect(screen.shown.single.update.applied.single.userId, 'bob');
    // A change made on a board that has moved on is not shared; the screen goes back to the shared board.
    after = Board(spec, base).moveTo(5, 6) ?? Board(spec, base).moveTo(6, 7)!;
    screen.layout = after.slots;
    bridge.localChange(CoopOpKind.move, base, after.slots);
    expect(screen.layout, host.state.layout);
  });
}
