// A shared board on the game controller (phase 2 of Play together, docs/multiplayer.md): the
// others' changes are put on the board without counting a move or adding history, the player's own
// changes are shared as the slots that changed, and two players' boards stay the same, the way the
// game screen wires them (lib/features/game/game_screen.dart, `_onState` and `_SharedBoard`).
import 'dart:math';

import 'package:carden/data/coop_repository.dart';
import 'package:carden/game/board.dart';
import 'package:carden/game/game_controller.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/coop/coop_bridge.dart';
import 'package:carden/state/coop/coop_controller.dart';
import 'package:carden/state/coop/coop_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_coop.dart';

const _spec = BoardSpec(GameMode.cards, 4, 5, 'Medium', tier: 3);

Future<void> _settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// One player's game screen, reduced to what the sharing needs.
class _Screen implements CoopBoardTarget {
  _Screen(FakeCoopServer server, this.id) : backend = FakeCoopBackend(server, id) {
    container = ProviderContainer(overrides: [
      coopBackendProvider.overrideWithValue(backend),
      currentUserIdProvider.overrideWithValue(id),
      coopTimingProvider.overrideWithValue(const CoopTiming(presenceGap: Duration(milliseconds: 5), markFor: Duration(milliseconds: 50))),
    ]);
  }

  final String id;
  final FakeCoopBackend backend;
  late final ProviderContainer container;
  late GameArgs args;
  CoopBridge? bridge;
  bool showing = false;
  CoopOpKind nextKind = CoopOpKind.move;

  CoopController get coop => container.read(coopProvider.notifier);
  GameController get ctrl => container.read(gameControllerProvider(args).notifier);
  GameState get game => container.read(gameControllerProvider(args));

  /// What the game screen does once the shared board is known.
  void open() {
    args = GameArgs(puzzleId: 'p1', spec: _spec, layout: coop.log!.layout);
    container.listen(gameControllerProvider(args), (GameState? prev, GameState next) {
      if (prev == null || identical(prev.board, next.board) || showing) return;
      final kind = nextKind;
      nextKind = CoopOpKind.move;
      bridge!.localChange(kind, prev.board.slots, next.board.slots);
    });
    bridge = CoopBridge(coop, this);
  }

  @override
  List<int> get layout => game.board.slots;

  @override
  void showShared(CoopBoardUpdate update) {
    showing = true;
    ctrl.showShared(update.update.after);
    showing = false;
  }

  /// A move as a tap would make it: the card at [from] (and its group) onto [to].
  bool move(int from, int to) {
    final before = game.board;
    ctrl.drop(from, to);
    return !identical(before, game.board);
  }

  void dispose() {
    bridge?.dispose();
    container.dispose();
  }
}

void main() {
  test('the others\' changes count no move, add no history, and a finished board is won', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final base = Board.shuffled(_spec, seed: 3).slots;
    final args = GameArgs(puzzleId: 'p1', spec: _spec, layout: base);
    final ctrl = c.read(gameControllerProvider(args).notifier);
    final events = <GameEventKind>[];
    ctrl.events.listen(events.add);
    // Someone else put card 0 in place.
    final board = Board(_spec, base);
    final after = board.moveTo(board.slotOfCard(0), 0)!.slots;
    ctrl.showShared(after);
    var s = c.read(gameControllerProvider(args));
    expect(s.board.slots, after);
    expect(s.moves, 0);
    expect(s.history, isEmpty);
    expect(s.justLocked, contains(0));
    // The whole picture, finished by the others.
    ctrl.showShared(List.generate(base.length, (i) => i));
    s = c.read(gameControllerProvider(args));
    expect(s.status, GameStatus.won);
    expect(s.moves, 0);
    // A layout of another board is ignored.
    ctrl.showShared(const [1, 0]);
    expect(c.read(gameControllerProvider(args)).board.cells, base.length);
  });

  test('a card the player holds stays picked up unless the others move it', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final base = Board.shuffled(_spec, seed: 5).slots;
    final args = GameArgs(puzzleId: 'p1', spec: _spec, layout: base);
    final ctrl = c.read(gameControllerProvider(args).notifier);
    final board = Board(_spec, base);
    // Pick up a card far from the one the others move.
    final moving = board.slotOfCard(0);
    final target = 0;
    final keep = [for (var s = 0; s < board.cells; s++) if (s != moving && s != target && !board.groupOf(moving).contains(s)) s].first;
    ctrl.tap(keep);
    ctrl.showShared(board.moveTo(moving, target)!.slots);
    final changed = c.read(gameControllerProvider(args)).board.slots[keep] != base[keep];
    expect(c.read(gameControllerProvider(args)).selected, changed ? isNull : keep);
  });

  test('two screens playing at once end on the same board, and only moves are shared as moves', () async {
    final server = FakeCoopServer();
    final amy = _Screen(server, 'amy');
    final bob = _Screen(server, 'bob');
    addTearDown(amy.dispose);
    addTearDown(bob.dispose);
    final base = Board.shuffled(_spec, seed: 8).slots;
    final game = await amy.coop.create(puzzleId: 'p1', grid: 'cards-4x5t3', layout: base);
    await bob.coop.join(game.code);
    await _settle();
    amy.open();
    bob.open();
    final rnd = Random(4);
    for (var i = 0; i < 60; i++) {
      final who = rnd.nextBool() ? amy : bob;
      final b = who.game.board;
      final from = rnd.nextInt(b.cells), to = rnd.nextInt(b.cells);
      if (from != to && !b.isLocked(from)) who.move(from, to);
      if (i % 7 == 0) await _settle();
    }
    // Magic, as the game screen says it before the board changes.
    amy.nextKind = CoopOpKind.magic;
    amy.ctrl.magicLock();
    bob.nextKind = CoopOpKind.shuffle;
    bob.ctrl.shuffle(random: Random(1));
    await _settle();
    await amy.coop.catchUp();
    await bob.coop.catchUp();
    await _settle();
    expect(amy.game.board.slots, bob.game.board.slots, reason: 'one board on both screens');
    expect(amy.game.board.slots, amy.coop.log!.layout);
    final kinds = server.moves.map((m) => m['kind']).toSet();
    expect(kinds, containsAll(['move', 'magic', 'shuffle']));
    // Bob's moves on his own screen count; Amy's do not reach his count.
    expect(bob.game.moves, lessThan(server.moves.length));
  });
}
