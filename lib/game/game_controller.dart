import 'dart:async';
import 'dart:math';
import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'board.dart';
import 'zones.dart';

enum GameStatus { playing, paused, won }

class GameState {
  const GameState({
    required this.board,
    required this.par,
    required this.moves,
    required this.elapsed,
    required this.status,
    required this.selected,
    required this.hintsUsed,
    required this.history,
    required this.justLocked,
    required this.justJoined,
    required this.hintSlot,
    required this.hintTarget,
    required this.peeking,
    required this.chain,
    required this.tick,
    this.basePar = 0,
    this.peeked = false,
    this.bestLock = 0,
    this.zoned = false,
  });

  final Board board;
  final int par;
  final int moves;
  final int elapsed;
  final GameStatus status;
  final int? selected;
  final int hintsUsed;
  final List<List<int>> history; // layout snapshots for undo
  final Set<int> justLocked;
  final Set<int> justJoined;
  final int? hintSlot;
  final int? hintTarget;
  final bool peeking;
  final int chain; // 2 when the last move locked 2+ cards in place
  final int tick; // increments on each lock/join, used to re-trigger animations

  /// Par of the play-through as dealt (a resumed board keeps the one it was saved with; [par]
  /// itself is recomputed on resume and stays what the stars use).
  final int basePar;

  /// Peek was used in this play-through.
  final bool peeked;

  /// Most cards a single move of the player's locked in this play-through (Magic does not count).
  final int bestLock;

  /// The board was dealt by zone (giant sizes, see `BoardZones`): the game shows the zone lines
  /// and counts finished zones. A giant board saved before zones plays on without them.
  final bool zoned;

  /// Finished in no more moves than the dealt par.
  bool get atPar => basePar > 0 && moves <= basePar;

  int get stars => Board.starsFor(moves: moves, par: par);
  bool get canUndo => history.isNotEmpty && status == GameStatus.playing;

  /// Slots highlighted as the current selection (whole group).
  List<int> get selectedGroup => selected == null ? const [] : board.groupOf(selected!);

  GameState copyWith({
    Board? board,
    int? par,
    int? moves,
    int? elapsed,
    GameStatus? status,
    int? selected,
    bool clearSelected = false,
    int? hintsUsed,
    List<List<int>>? history,
    Set<int>? justLocked,
    Set<int>? justJoined,
    int? hintSlot,
    int? hintTarget,
    bool clearHint = false,
    bool? peeking,
    int? chain,
    int? tick,
    int? basePar,
    bool? peeked,
    int? bestLock,
    bool? zoned,
  }) =>
      GameState(
        board: board ?? this.board,
        par: par ?? this.par,
        moves: moves ?? this.moves,
        elapsed: elapsed ?? this.elapsed,
        status: status ?? this.status,
        selected: clearSelected ? null : (selected ?? this.selected),
        hintsUsed: hintsUsed ?? this.hintsUsed,
        history: history ?? this.history,
        justLocked: justLocked ?? this.justLocked,
        justJoined: justJoined ?? this.justJoined,
        hintSlot: clearHint ? null : (hintSlot ?? this.hintSlot),
        hintTarget: clearHint ? null : (hintTarget ?? this.hintTarget),
        peeking: peeking ?? this.peeking,
        chain: chain ?? this.chain,
        tick: tick ?? this.tick,
        basePar: basePar ?? this.basePar,
        peeked: peeked ?? this.peeked,
        bestLock: bestLock ?? this.bestLock,
        zoned: zoned ?? this.zoned,
      );
}

/// Parameters for a game session: which puzzle, which grid, and optionally a
/// saved layout to resume from.
class GameArgs {
  const GameArgs({
    required this.puzzleId,
    required this.spec,
    this.layout,
    this.moves = 0,
    this.elapsed = 0,
    this.hintsUsed = 0,
    this.session = 0,
    this.par = 0,
    this.peeked = false,
    this.bestLock = 0,
  });
  final String puzzleId;
  final BoardSpec spec;
  final List<int>? layout;
  final int moves;
  final int elapsed;
  final int hintsUsed;

  /// The saved play-through's par, Peek and longest lock (0 / false on saves from older versions).
  final int par;
  final bool peeked;
  final int bestLock;

  /// Distinguishes sessions on the same board (the game screen bumps it when
  /// it settles the board for the loaded picture), so each gets its own
  /// controller.
  final int session;

  @override
  bool operator ==(Object other) => other is GameArgs && other.puzzleId == puzzleId && other.spec == spec && other.session == session;
  @override
  int get hashCode => Object.hash(puzzleId, spec, session);
}

/// Events the UI reacts to with sound/haptics/particles.
enum GameEventKind { pick, move, join, lock, doubleLock, win, invalid, undo }

class GameController extends Notifier<GameState> {
  GameController(this.args);
  final GameArgs args;

  Timer? _timer;
  Timer? _peekTimer;
  final _events = StreamController<GameEventKind>.broadcast();
  Stream<GameEventKind> get events => _events.stream;

  @override
  GameState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _peekTimer?.cancel();
      _events.close();
    });
    // A save only resumes when it still describes this board: the right
    // length, a permutation, every card in a slot of its own shape. Saves
    // from before a layout changed start fresh instead.
    final restore = Board.isValidLayout(args.spec, args.layout);
    final board = restore ? Board(args.spec, args.layout!) : dealBoard(args.spec);
    final par = restore ? args.moves + board.par : board.par;
    final zoned = BoardZones.appliesTo(args.spec) && (!restore || BoardZones.of(args.spec).dealtIn(board));
    _startTimer();
    return restore
        ? _fresh(board,
            par: max(par, 1),
            moves: args.moves,
            elapsed: args.elapsed,
            hintsUsed: args.hintsUsed,
            basePar: args.par > 0 ? args.par : max(par, 1),
            peeked: args.peeked,
            bestLock: args.bestLock,
            zoned: zoned)
        : _fresh(board, par: max(par, 1), zoned: zoned);
  }

  GameState _fresh(Board board, {required int par, int moves = 0, int elapsed = 0, int hintsUsed = 0, int? basePar, bool peeked = false, int bestLock = 0, bool zoned = false}) => GameState(
        board: board,
        par: par,
        moves: moves,
        elapsed: elapsed,
        status: board.isSolved ? GameStatus.won : GameStatus.playing,
        selected: null,
        hintsUsed: hintsUsed,
        history: const [],
        justLocked: const {},
        justJoined: const {},
        hintSlot: null,
        hintTarget: null,
        peeking: false,
        chain: 0,
        tick: 0,
        basePar: basePar ?? par,
        peeked: peeked,
        bestLock: bestLock,
        zoned: zoned,
      );

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.status == GameStatus.playing) {
        state = state.copyWith(elapsed: state.elapsed + 1);
      }
    });
  }

  void pause() {
    if (state.status == GameStatus.playing) state = state.copyWith(status: GameStatus.paused, clearSelected: true);
  }

  void resume() {
    if (state.status == GameStatus.paused) state = state.copyWith(status: GameStatus.playing);
  }

  /// Tap-to-select (selects the whole group) then tap a destination for the
  /// tapped card; the group travels with it.
  void tap(int slot) {
    if (state.status != GameStatus.playing) return;
    final b = state.board;
    final sel = state.selected;
    if (sel == null) {
      if (b.isLocked(slot)) {
        _events.add(GameEventKind.invalid);
        return;
      }
      state = state.copyWith(selected: slot);
      _events.add(GameEventKind.pick);
    } else if (sel == slot) {
      state = state.copyWith(clearSelected: true);
    } else {
      // Tapping another cell of the same group shifts the whole group.
      _apply(b.moveTo(sel, slot));
    }
  }

  /// Drag-and-drop: the card at [from] (and its group) lands on [to].
  void drop(int from, int to) {
    if (state.status != GameStatus.playing) return;
    if (from == to) {
      state = state.copyWith(clearSelected: true);
      return;
    }
    _apply(state.board.moveTo(from, to));
  }

  void _apply(Board? after, {bool countMove = true, bool byPlayer = true}) {
    if (after == null) {
      state = state.copyWith(clearSelected: true);
      _events.add(GameEventKind.invalid);
      return;
    }
    final before = state.board;
    final newlyLocked = <int>{for (var i = 0; i < after.cells; i++) if (after.isLocked(i) && !before.isLocked(i)) i};
    // Cards that gained a joined neighbour (new snap) – excluding in-place locks.
    final newlyJoined = <int>{};
    if (after.joinCount > before.joinCount) {
      for (var s = 0; s < after.cells; s++) {
        if (after.isLocked(s)) continue;
        final g = after.groupOf(s);
        if (g.length > 1 && before.groupOf(before.slotOfCard(after.slots[s])).length < g.length) newlyJoined.add(s);
      }
    }
    final won = after.isSolved;
    state = state.copyWith(
      board: after,
      moves: countMove ? state.moves + 1 : state.moves,
      history: [...state.history, before.slots],
      justLocked: newlyLocked,
      justJoined: newlyJoined,
      chain: newlyLocked.length >= 2 ? 2 : 0,
      bestLock: byPlayer ? max(state.bestLock, newlyLocked.length) : state.bestLock,
      tick: newlyLocked.isEmpty && newlyJoined.isEmpty ? state.tick : state.tick + 1,
      clearSelected: true,
      clearHint: true,
      status: won ? GameStatus.won : state.status,
    );
    if (won) {
      _events.add(GameEventKind.win);
      _timer?.cancel();
    } else if (newlyLocked.length >= 2) {
      _events.add(GameEventKind.doubleLock);
    } else if (newlyLocked.isNotEmpty) {
      _events.add(GameEventKind.lock);
    } else if (newlyJoined.isNotEmpty) {
      _events.add(GameEventKind.join);
    } else {
      _events.add(GameEventKind.move);
    }
  }

  void undo() {
    if (!state.canUndo) return;
    final previous = state.history.last;
    final history = state.history.sublist(0, state.history.length - 1);
    state = state.copyWith(
      board: Board(state.board.spec, previous),
      history: history,
      moves: state.moves + 1,
      justLocked: const {},
      justJoined: const {},
      chain: 0,
      clearSelected: true,
      clearHint: true,
    );
    _events.add(GameEventKind.undo);
  }

  /// Highlights a misplaced card and where it belongs. The caller handles
  /// payment before invoking this.
  bool showHint() {
    if (state.status != GameStatus.playing) return false;
    final b = state.board;
    final candidates = <int>[for (var i = 0; i < b.cells; i++) if (!b.isLocked(i)) i];
    if (candidates.isEmpty) return false;
    final slot = state.selected != null && !b.isLocked(state.selected!) ? state.selected! : candidates[Random().nextInt(candidates.length)];
    final target = b.homeOf(slot);
    state = state.copyWith(hintSlot: slot, hintTarget: target, hintsUsed: state.hintsUsed + 1, clearSelected: true);
    _events.add(GameEventKind.pick);
    return true;
  }

  /// Magic lock: sends one misplaced card (and its whole group) home. Counts as a move.
  bool magicLock() {
    if (state.status != GameStatus.playing) return false;
    final b = state.board;
    final candidates = <int>[for (var i = 0; i < b.cells; i++) if (!b.isLocked(i)) i];
    if (candidates.isEmpty) return false;
    final slot = state.hintSlot ?? (state.selected != null && !b.isLocked(state.selected!) ? state.selected! : candidates[Random().nextInt(candidates.length)]);
    state = state.copyWith(hintsUsed: state.hintsUsed + 1);
    _apply(b.moveTo(slot, b.homeOf(slot)), byPlayer: false);
    return true;
  }

  /// Peek: every card not in place flies to its place, the picture shows for a moment and the
  /// cards fly back (the board draws the flight while [GameState.peeking] is on). [duration] is
  /// the time the cards spend away, the flight there included. The caller handles payment.
  void peek({Duration duration = peekTime}) {
    if (state.status != GameStatus.playing || state.peeking) return;
    _peekTimer?.cancel();
    state = state.copyWith(peeking: true, peeked: true, clearSelected: true);
    _peekTimer = Timer(duration, () {
      if (!_events.isClosed) state = state.copyWith(peeking: false);
    });
  }

  /// How long a Peek keeps the cards in their places, and the longer look on a giant board.
  static const peekTime = Duration(milliseconds: 2400);
  static const giantPeekTime = Duration(milliseconds: 3200);

  /// Gather (giant boards): brings the cards that belong in [view] (board coordinates at the
  /// board's [size]) into it, trading places with cards that belong elsewhere (see
  /// [gatherInto]). Not a move; Undo takes it back. Returns how many cards came in.
  int gather(Rect view, Size size) {
    if (state.status != GameStatus.playing || state.peeking) return 0;
    final before = state.board;
    final after = gatherInto(before, view, size);
    if (after == null) return 0;
    var moved = 0;
    for (var s = 0; s < after.cells; s++) {
      if (after.slots[s] != before.slots[s]) moved++;
    }
    _apply(after, countMove: false, byPlayer: false);
    return moved ~/ 2;
  }

  void restart() {
    _peekTimer?.cancel();
    final board = dealBoard(args.spec);
    state = _fresh(board, par: max(board.par, 1), zoned: BoardZones.appliesTo(args.spec));
    _startTimer();
  }

  void clearSelection() {
    if (state.selected != null) state = state.copyWith(clearSelected: true);
  }
}

final gameControllerProvider = NotifierProvider.autoDispose.family<GameController, GameState, GameArgs>(GameController.new);

/// Formats seconds as m:ss or h:mm:ss.
String formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

@visibleForTesting
Board debugBoard(BoardSpec spec, List<int> slots) => Board(spec, slots);
