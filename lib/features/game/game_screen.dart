import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../data/sync/ops.dart';
import '../../game/board.dart';
import '../../game/game_controller.dart';
import '../../game/image_loader.dart';
import '../../models/models.dart';
import '../../router.dart' show rootNavigatorKey;
import '../../state/catalog.dart';
import '../../state/giant.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/rewards.dart';
import '../../state/settings.dart';
import '../../state/social.dart';
import '../../state/sync.dart';
import '../../state/unlocks.dart';
import '../../widgets/glass.dart';
import '../../widgets/hash_image.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../ads/house_ads.dart';
import '../events/quest_rewards.dart';
import '../sync/board_choice_sheet.dart';
import 'board_widget.dart';
import 'giant_board.dart';

/// The play screen: HUD, board, booster bar, pause and completion overlays.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, required this.puzzleId, required this.gridCode, this.painting = false});
  final String puzzleId;
  final String gridCode;

  /// A new board starts in Painting (a saved board resumes the way it was saved).
  final bool painting;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  /// The board being played. It starts from the route code and is settled
  /// for the picture once the picture is decoded (see [_fitToPicture]).
  late BoardSpec _spec = BoardSpec.fromCode(widget.gridCode);

  /// Painting on this board: the saved board's choice when one resumes, else the route's.
  late bool _painting = widget.painting;

  /// Zoom of giant boards (the zoom bar and the board share it).
  late final BoardZoom _zoom = BoardZoom(vsync: this);

  /// Giant boards: the overview map (remembered; the selected card's place
  /// shows on it), and the saved view, restored once when a board resumes
  /// and written shortly after the player stops zooming or panning.
  late bool _showMap = ref.read(giantViewsProvider).showMap;

  bool _viewRestored = false;
  bool _viewCleared = false;
  String? _viewId;
  Timer? _viewSave;
  GameArgs? _args;
  bool _fitted = false;
  GameArgs? _listening;
  StreamSubscription<GameEventKind>? _sub;
  Timer? _saveDebounce;
  final _confetti = ConfettiController(duration: const Duration(seconds: 2));
  bool _completionHandled = false;
  ({int coins, int xp, bool levelUp, int level})? _reward;

  /// Quests this win finished (ready to claim) and what the level-up opened, for the overlay.
  List<Goal> _questsReady = const [];
  List<Unlock> _unlocked = const [];
  bool _showTutorial = false;
  int _chainFlash = 0;

  /// The play-through being saved (lifetime totals add up per play-through), and whether it
  /// continues the board that was saved for the picture.
  String _playId = SyncOp.newId();
  bool _resumed = false;
  StreamSubscription<BoardUpdate>? _boardSub;
  bool _askingBoard = false;

  /// Each screen counts its sessions from its own base: a screen that replaces another one for the
  /// same picture and board (another device's board reopened) must not get the old screen's
  /// controller, which is still alive while the two swap.
  static int _screens = 0;
  final int _base = 1000 * ++_screens;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _args = _argsFor(_spec, resume: true, session: _base);
    _showTutorial = !ref.read(settingsProvider).tutorialSeen;
    _boardSub = ref.read(syncProvider.notifier).boardUpdates.listen(_onBoardUpdate);
    _zoom.addListener(_onZoomChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
  }

  void _onZoomChanged() {
    _maybeLocateTip();
    if (_viewId == null || _viewCleared) return;
    _viewSave?.cancel();
    _viewSave = Timer(const Duration(milliseconds: 600), _saveView);
  }

  /// The first time a giant board is zoomed in with the map and Locate on:
  /// how to find a card's place.
  void _maybeLocateTip() {
    if (!_zoom.zoomed || _zoom.zoom < 1.5 || !_showMap) return;
    final views = ref.read(giantViewsProvider);
    if (views.locateTipShown) return;
    views.locateTipShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showToast(context, 'Tap a card to see its place on the map', icon: AppIcons.minimap);
    });
  }

  void _saveView() {
    final id = _viewId;
    if (id == null || _viewCleared) return;
    ref.read(giantViewsProvider).write(id, _zoom.snapshot);
  }

  /// Giant boards: opens a resumed board on the view it was left at, and
  /// forgets the view once the board is finished.
  void _syncView(GameState state) {
    final id = GiantViews.id(widget.puzzleId, state.board.spec);
    if (_viewId != id) {
      _viewId = id;
      _viewRestored = false;
    }
    if (state.status == GameStatus.won) {
      if (!_viewCleared) {
        _viewCleared = true;
        _viewSave?.cancel();
        ref.read(giantViewsProvider).clear(id);
      }
      return;
    }
    if (_viewRestored) return;
    _viewRestored = true;
    final saved = _resumed ? ref.read(giantViewsProvider).read(id) : null;
    if (saved == null) return;
    // Before the board's first layout the view waits for its size; later it
    // must not change in the middle of this build.
    if (_zoom.viewport.isEmpty) {
      _zoom.restore(saved.zoom, saved.centre);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _zoom.restore(saved.zoom, saved.centre);
      });
    }
  }

  /// Session arguments for [spec], resuming the saved board when [resume]
  /// and the save is for this mode and piece count.
  GameArgs _argsFor(BoardSpec spec, {required bool resume, int session = 0}) {
    final existing = ref.read(puzzleProgressProvider(widget.puzzleId));
    final ok = resume && existing != null && existing.inProgress && existing.gridSize == spec.cells && existing.mode == spec.mode.code;
    _resumed = ok;
    _painting = ok ? existing.painting : widget.painting;
    _playId = ok && existing.session.isNotEmpty ? existing.session : SyncOp.newId();
    return GameArgs(
      puzzleId: widget.puzzleId,
      spec: spec,
      layout: ok ? existing.layout : null,
      moves: ok ? existing.moves : 0,
      elapsed: ok ? existing.elapsedSeconds : 0,
      hintsUsed: ok ? existing.hintsUsed : 0,
      session: session,
      par: ok ? existing.par : 0,
      peeked: ok && existing.peeked,
      bestLock: ok ? existing.bestLock : 0,
    );
  }

  /// Settles the board for the decoded picture, once. Layouts follow the
  /// picture's proportions, so a board picked on the difficulty screen
  /// already matches (the same decode), while the next picture of a pack or
  /// a board resumed from Home gets the size its tier has for this picture.
  /// A save resumes only when this picture still deals its board; older
  /// saves (a layout that changed) start fresh.
  void _fitToPicture(ui.Image image, {required bool giant}) {
    if (_fitted) return;
    _fitted = true;
    final aspect = image.width / image.height;
    final current = _args!;
    var next = _spec.fitTo(aspect);
    // A Giant pack picture deals only giant sizes and other pictures only
    // normal ones, whatever size the route named (a pack's next picture).
    if (next.isGiant != giant) next = BoardSpec.forPicture(next.mode, giant ? BoardSpec.firstGiantTier : 2, aspect);
    var resume = false;
    if (current.layout != null) {
      final saved = BoardSpec.fromSaved(_spec.mode, _spec.cells, aspect);
      if (saved != null && Board.isValidLayout(saved, current.layout)) {
        next = saved;
        resume = true;
      }
    }
    if (next == _spec && resume == (current.layout != null)) return;
    _spec = next;
    _args = _argsFor(next, resume: resume, session: current.session + 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _listen();
    });
  }

  /// Follows the events of the current session's controller.
  void _listen() {
    if (_args == null || _args == _listening) return;
    _sub?.cancel();
    _listening = _args;
    _sub = ref.read(gameControllerProvider(_args!).notifier).events.listen(_onEvent);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _boardSub?.cancel();
    _saveDebounce?.cancel();
    _confetti.dispose();
    if (_viewSave?.isActive ?? false) {
      _viewSave!.cancel();
      _saveView();
    }
    _zoom.removeListener(_onZoomChanged);
    _zoom.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveNow();
      if (_viewSave?.isActive ?? false) {
        _viewSave!.cancel();
        _saveView();
      }
    }
  }

  GameController get _ctrl => ref.read(gameControllerProvider(_args!).notifier);

  void _onEvent(GameEventKind e) {
    switch (e) {
      case GameEventKind.pick:
        Sfx.instance.pick();
        Haptics.selection();
      case GameEventKind.move:
        Sfx.instance.swap();
        Haptics.light();
        _scheduleSave();
      case GameEventKind.join:
        Sfx.instance.snap();
        Haptics.medium();
        _scheduleSave();
      case GameEventKind.lock:
        Sfx.instance.lock();
        Haptics.medium();
        _scheduleSave();
      case GameEventKind.doubleLock:
        Sfx.instance.lock();
        Haptics.success();
        setState(() => _chainFlash++);
        _scheduleSave();
        // The "Lock 5 cards in one move" quests count it when the board is finished.
        final locked = ref.read(gameControllerProvider(_args!)).justLocked.length;
        if (locked >= Goals.lockRun) showToast(context, '$locked cards locked in one move', icon: AppIcons.lock);
      case GameEventKind.undo:
        Sfx.instance.whoosh();
        Haptics.light();
        _scheduleSave();
      case GameEventKind.invalid:
        Sfx.instance.error();
        Haptics.heavy();
      case GameEventKind.win:
        _onWin();
    }
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 900), _saveNow);
  }

  void _saveNow() {
    // Nothing to save before the board is settled for the picture (and a
    // save then could overwrite the one being resumed).
    if (_args == null || !mounted || !_fitted) return;
    final s = ref.read(gameControllerProvider(_args!));
    if (s.status == GameStatus.won) return;
    ref.read(progressProvider.notifier).saveBoard(
      widget.puzzleId,
      gridSize: _spec.cells,
      mode: _spec.mode.code,
      layout: s.board.slots,
      moves: s.moves,
      seconds: s.elapsed,
      hints: s.hintsUsed,
      session: _playId,
      resumed: _resumed,
      painting: _painting,
      par: s.basePar,
      peeked: s.peeked,
      bestLock: s.bestLock,
    );
  }

  /// Another device changed this picture's board while it is open here.
  Future<void> _onBoardUpdate(BoardUpdate u) async {
    if (u.puzzleId != widget.puzzleId || !mounted || !_fitted || _args == null || _askingBoard) return;
    final s = ref.read(gameControllerProvider(_args!));
    if (s.status == GameStatus.won) return;
    // Already the board on screen (this device's own save coming back).
    if (u.after.layout?.join(',') == s.board.slots.join(',')) return;
    if (u.chosen) {
      _openSaved(u.after);
      return;
    }
    if (u.continued) {
      // The player went on with this same board elsewhere: its newer state replaces this one.
      _openSaved(u.after);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = rootNavigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        showAppAlert(
          ctx,
          title: 'Board updated',
          message: 'You played this picture on another device. Its newer board is loaded here.',
          confirmLabel: 'Continue',
          cancelLabel: null,
        );
      });
      return;
    }
    _askingBoard = true;
    _ctrl.pause();
    final here = PuzzleProgress.fromRow('', {
      'puzzleId': widget.puzzleId,
      'gridSize': _spec.cells,
      'mode': _spec.mode.code,
      'layout': s.board.slots.join(','),
      'moves': s.moves,
      'elapsedSeconds': s.elapsed,
    });
    final title = ref.read(resolvedPuzzleProvider(widget.puzzleId))?.title;
    final choice = await showBoardChoiceSheet(context, title: title, device: here, other: u.after);
    _askingBoard = false;
    if (!mounted) return;
    if (choice == BoardChoice.other) {
      _openSaved(u.after);
    } else {
      _ctrl.resume();
      _saveNow();
    }
  }

  /// A new play-through (restart, replay): its moves and time add to the picture's totals.
  void _newPlay() {
    _playId = SyncOp.newId();
    _resumed = false;
  }

  /// Reopens the picture on the board saved for it (another device's).
  void _openSaved(PuzzleProgress p) {
    _saveDebounce?.cancel();
    final spec = BoardSpec.fromCells(GameMode.fromCode(p.mode), p.gridSize);
    context.pushReplacement('/game/${widget.puzzleId}/${BoardCode.toPath(spec.fullCode)}');
  }

  Future<void> _onWin() async {
    if (_completionHandled) return;
    _completionHandled = true;
    // The first board is done: the coach line has done its job.
    if (_showTutorial) {
      ref.read(settingsProvider.notifier).setTutorialSeen();
      _showTutorial = false;
    }
    _saveDebounce?.cancel();
    Sfx.instance.win();
    Haptics.success();
    _confetti.play();
    final s = ref.read(gameControllerProvider(_args!));
    final existing = ref.read(puzzleProgressProvider(widget.puzzleId));
    final firstTime = existing?.completed != true;
    final stars = s.stars;
    final puzzle = ref.read(resolvedPuzzleProvider(widget.puzzleId));
    final daily = ref.read(dailyPuzzleProvider);
    // Quests this win finishes: the ones ready with the solve counted, minus those ready before.
    final now = DateTime.now();
    final profileBefore = ref.read(profileProvider).value;
    final open = ref.read(openFeaturesProvider);
    final rows = {...?ref.read(progressProvider).value};
    final readyBefore = {for (final g in readyGoals(rows.values, profileBefore, open, now, dailyPuzzle: daily?.id)) g.key};
    rows[widget.puzzleId] = PuzzleProgress.fromRow(existing?.id ?? '', {
      ...?existing?.toData(),
      'puzzleId': widget.puzzleId,
      'gridSize': _spec.cells,
      'mode': _spec.mode.code,
      'layout': '',
      'moves': s.moves,
      'completed': true,
      'completedAt': now.toUtc().toIso8601String(),
      'stars': math.max(existing?.stars ?? 0, stars),
      'painting': _painting,
      'par': s.basePar,
      'peeked': s.peeked,
      'bestLock': s.bestLock,
    });
    final questsReady = [for (final g in readyGoals(rows.values, profileBefore, open, now, dailyPuzzle: daily?.id)) if (!readyBefore.contains(g.key)) g];
    ref.read(progressProvider.notifier).complete(
      widget.puzzleId,
      gridSize: _spec.cells,
      mode: _spec.mode.code,
      moves: s.moves,
      seconds: s.elapsed,
      hints: s.hintsUsed,
      stars: stars,
      session: _playId,
      resumed: _resumed,
      painting: _painting,
      par: s.basePar,
      peeked: s.peeked,
      bestLock: s.bestLock,
    );
    final reward = await ref.read(profileProvider.notifier).recordCompletion(
          puzzleId: widget.puzzleId,
          cells: _spec.cells,
          stars: stars,
          firstTime: firstTime,
          mode: _spec.mode,
          painting: _painting,
          moves: s.moves,
          seconds: s.elapsed,
          dailyBonus: daily != null && daily.id == widget.puzzleId ? 50 : 0,
        );
    unawaited(bumpEventProgress(ref, packId: puzzle?.packId));
    if (!mounted) return;
    final before = profileBefore?.level ?? reward.level;
    setState(() {
      _reward = (coins: reward.coins, xp: reward.xp, levelUp: reward.levelUp, level: reward.level);
      _questsReady = questsReady;
      _unlocked = [
        for (var l = before + 1; l <= reward.level; l++)
          for (final u in Unlocks.atLevel(l))
            if (!open.has(u)) u,
      ];
    });
  }

  Future<void> _hint() async {
    final profile = ref.read(profileProvider).value;
    if (profile == null) return;
    final ok = await ref.read(profileProvider.notifier).useHint();
    if (!mounted) return;
    if (!ok) {
      Sfx.instance.error();
      _offerStore('No hints left. Buy one for ${countOf(Economy.hintCostCoins, 'coin')}.');
      return;
    }
    Sfx.instance.coin();
    _ctrl.showHint();
  }

  /// Magic: from stock (Lucky Wheel prizes) first, then for coins.
  Future<void> _magic() async {
    final ok = await ref.read(profileProvider.notifier).useMagic();
    if (!mounted) return;
    if (!ok) {
      Sfx.instance.error();
      _offerStore('Not enough coins. Magic costs ${countOf(Economy.magicLockCostCoins, 'coin')}.');
      return;
    }
    Sfx.instance.coin();
    _ctrl.magicLock();
  }

  /// Peek: the cards fly to their places for a moment and back (a little
  /// longer on giant boards, where there is more to read). From stock first,
  /// then for coins.
  Future<void> _peek() async {
    final state = ref.read(gameControllerProvider(_args!));
    if (state.peeking) return;
    final giant = state.board.spec.isGiant;
    final ok = await ref.read(profileProvider.notifier).usePeek();
    if (!mounted) return;
    if (!ok) {
      Sfx.instance.error();
      _offerStore('Not enough coins. Peek costs ${countOf(Economy.peekCostCoins, 'coin')}.');
      return;
    }
    Sfx.instance.whoosh();
    Haptics.light();
    _ctrl.peek(duration: giant ? GameController.giantPeekTime : GameController.peekTime);
  }

  /// Gather (zoomed giant board): the cards that belong in view come into it.
  /// Gather (giant boards, at any zoom): the cards that belong in view come into it; when they
  /// are all here or nearby already, the loose ones in view are shuffled instead.
  void _gather(Size boardSize) {
    final r = _ctrl.gather(_zoom.visible, boardSize);
    if (r.gathered > 0) {
      Haptics.medium();
      showToast(context, '${r.gathered} card${r.gathered == 1 ? '' : 's'} gathered', icon: AppIcons.gather);
    } else if (r.shuffled > 0) {
      Haptics.medium();
      showToast(context, 'Every card for this view is here or nearby. The loose ones were shuffled.', icon: AppIcons.gather);
    } else {
      showToast(context, 'Every card for this view is here or nearby', icon: AppIcons.gather);
    }
  }

  void _offerStore(String message) {
    showToast(context, message, leading: const CoinIcon(size: 20));
    context.push('/store');
  }

  void _openPause() {
    _ctrl.pause();
    showAppSheet(
      context,
      builder: (ctx) => _PauseSheet(
        onResume: () => Navigator.pop(ctx),
        onRestart: () async {
          // A started board is thrown away: ask first, like Change mode or board does.
          final moves = ref.read(gameControllerProvider(_args!)).moves;
          if (moves > 0) {
            final ok = await showAppAlert(
              context,
              title: 'Shuffle and restart?',
              message: 'This board and its $moves ${moves == 1 ? 'move' : 'moves'} are thrown away and the cards are dealt again. Stars and records stay.',
              confirmLabel: 'Shuffle',
              destructive: true,
            );
            if (!ok || !mounted || !ctx.mounted) return;
          }
          Navigator.pop(ctx);
          _completionHandled = false;
          _newPlay();
          _ctrl.restart();
        },
        onQuit: () {
          Navigator.pop(ctx);
          _saveNow();
          context.pop();
        },
        onChangeDifficulty: () async {
          final ok = await showAppAlert(
            context,
            title: 'Discard this board?',
            message: 'Your moves and time on this picture are thrown away so you can pick another mode or board size. Stars and records stay.',
            confirmLabel: 'Discard',
            destructive: true,
          );
          if (!ok || !mounted || !ctx.mounted) return;
          Navigator.pop(ctx);
          await ref.read(progressProvider.notifier).discard(widget.puzzleId);
          if (!mounted) return;
          context.pushReplacement('/play/${widget.puzzleId}');
        },
      ),
    ).then((_) => _ctrl.resume());
  }

  /// Where the player stands in this puzzle's pack once this one counts as
  /// solved, and the next unsolved puzzle after it (wrapping round), or null
  /// when this was the last one left.
  _PackProgress _packProgress(Puzzle puzzle, GameState state) {
    final all = ref.watch(allPuzzlesProvider).value ?? const <Puzzle>[];
    final progress = ref.watch(progressProvider).value ?? const <String, PuzzleProgress>{};
    final packs = ref.watch(packsProvider).value ?? const <Pack>[];
    final list = all.where((p) => p.packId == puzzle.packId).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    bool solved(Puzzle p) => p.id == puzzle.id || progress[p.id]?.completed == true;
    int stars(Puzzle p) => p.id == puzzle.id ? math.max(state.stars, progress[p.id]?.stars ?? 0) : (progress[p.id]?.stars ?? 0);
    final idx = list.indexWhere((p) => p.id == puzzle.id);
    Puzzle? next;
    for (var k = 1; k < list.length && idx >= 0; k++) {
      final candidate = list[(idx + k) % list.length];
      if (!solved(candidate) && !candidate.isLockedByDate) {
        next = candidate;
        break;
      }
    }
    final pack = packs.where((p) => p.id == puzzle.packId).firstOrNull;
    return _PackProgress(
      name: pack?.name,
      solved: list.where(solved).length,
      total: list.length,
      stars: list.fold<int>(0, (sum, p) => sum + stars(p)),
      next: next,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final puzzle = ref.watch(resolvedPuzzleProvider(widget.puzzleId));
    final settings = ref.watch(settingsProvider);
    final profile = ref.watch(profileProvider).value;
    if (puzzle == null) {
      return Scaffold(appBar: AppBar(leading: const BackButton()), body: const Loader());
    }
    // Giant pack pictures (or a giant board named by the route, before the
    // catalogue says so) are decoded at full size for zooming in.
    final giant = ref.watch(isGiantPuzzleProvider(widget.puzzleId)) || _spec.isGiant;
    final imageProvider = puzzleImageFor(puzzle.imageUrl, giant: giant);
    final image = ref.watch(imageProvider);
    if (image.hasValue) _fitToPicture(image.requireValue, giant: giant);
    final state = ref.watch(gameControllerProvider(_args!));
    final zoomable = state.board.spec.isGiant;
    if (zoomable && image.hasValue) _syncView(state);
    final sel = state.selected;
    // Locate: while the map is on, the selected card's place shows on it.
    final locate = sel != null && sel < state.board.cells && !state.board.isLocked(sel) ? sel : null;

    return Scaffold(
      backgroundColor: c.canvas,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _Hud(
                  state: state,
                  showTimer: settings.showTimer,
                  onPause: _openPause,
                  title: puzzle.title,
                  painting: _painting,
                ),
                // First game: one line that teaches the next thing to do, while playing.
                if (_showTutorial && image.hasValue && state.status != GameStatus.won)
                  _CoachLine(
                    state: state,
                    onDone: () {
                      ref.read(settingsProvider.notifier).setTutorialSeen();
                      setState(() => _showTutorial = false);
                    },
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, cons) {
                      // The tiling decides the board's proportions: honeycombs
                      // and triangle strips keep regular cells and crop the
                      // picture; rectangular grids follow the picture within
                      // sane limits (a 900×21 handscroll must not become a strip).
                      final imageAspect = image.value == null ? 3 / 4 : image.value!.width / image.value!.height;
                      // Giant boards keep a strip above the board for their tools.
                      final bar = zoomable && image.hasValue ? GiantBoardBar.height : 0.0;
                      final fitted = state.board.tiling.fit(Size(cons.maxWidth - 24, cons.maxHeight - 16 - bar), imageAspect);
                      final w = fitted.width, h = fitted.height;
                      return Center(
                        child: image.when(
                          loading: () => SizedBox(
                            width: w,
                            height: h,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (puzzle.blurhash != null)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Opacity(opacity: 0.6, child: HashImage(hash: puzzle.blurhash!, color: c.boardBackground)),
                                  ),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Loader(),
                                    const SizedBox(height: 12),
                                    Text('Dealing the cards', style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          error: (e, _) => EmptyState(
                            icon: AppIcons.image,
                            title: 'Picture did not load',
                            message: 'Check your connection and try again.',
                            action: BigButton(label: 'Try again', expand: false, onTap: () => ref.invalidate(imageProvider)),
                          ),
                          data: (img) => Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (zoomable)
                                    GiantBoardBar(
                                      zoom: _zoom,
                                      width: w,
                                      showMap: _showMap,
                                      onMap: () {
                                        setState(() => _showMap = !_showMap);
                                        ref.read(giantViewsProvider).showMap = _showMap;
                                      },
                                      onGather: state.status == GameStatus.playing ? () => _gather(Size(w, h)) : null,
                                    ),
                                  if (!zoomable)
                                    BoardWidget(
                                      image: img,
                                      state: state,
                                      width: w,
                                      height: h,
                                      cardStyle: settings.cardStyle,
                                      painting: _painting,
                                      onTap: _ctrl.tap,
                                      onDrop: _ctrl.drop,
                                    )
                                  else
                                    SizedBox(
                                      width: w,
                                      height: h,
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          BoardWidget(
                                            image: img,
                                            state: state,
                                            width: w,
                                            height: h,
                                            cardStyle: settings.cardStyle,
                                            painting: _painting,
                                            zoom: _zoom,
                                            onTap: _ctrl.tap,
                                            onDrop: _ctrl.drop,
                                          ),
                                          OffscreenSelection(zoom: _zoom, board: state.board, boardSize: Size(w, h), selected: state.selected),
                                          if (_showMap)
                                            Positioned(
                                              top: 8,
                                              right: 8,
                                              child: ListenableBuilder(
                                                listenable: _zoom,
                                                builder: (context, child) => IgnorePointer(
                                                  ignoring: !_zoom.zoomed,
                                                  child: AnimatedOpacity(opacity: _zoom.zoomed ? 1 : 0, duration: const Duration(milliseconds: 180), child: child),
                                                ),
                                                child: GiantMinimap(
                                                  image: img,
                                                  board: state.board,
                                                  boardSize: Size(w, h),
                                                  zoom: _zoom,
                                                  // Small enough to cover only a few cards in the corner.
                                                  width: math.min(84.0, w * 0.22),
                                                  selected: state.selected,
                                                  painting: _painting,
                                                  locate: locate,
                                                ),
                                              ),
                                            ),
                                          GiantMilestones(
                                            board: state.board,
                                            playing: state.status == GameStatus.playing,
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              if (_chainFlash > 0)
                                IgnorePointer(
                                  child: Text('×2 DOUBLE LOCK', key: ValueKey(_chainFlash), style: TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.title2, letterSpacing: -0.3, color: Brand.star, shadows: [Shadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 12)]))
                                      .animate()
                                      .fadeIn(duration: 150.ms)
                                      .scale(begin: const Offset(0.6, 0.6), end: const Offset(1.1, 1.1), curve: Curves.easeOutBack)
                                      .then(delay: 500.ms)
                                      .fadeOut(duration: 300.ms)
                                      .slideY(end: -0.6),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (state.status != GameStatus.won)
                  _BoosterBar(
                    hints: profile?.hints ?? 0,
                    peeks: profile?.peeks ?? 0,
                    magics: profile?.magics ?? 0,
                    canUndo: state.canUndo,
                    playing: state.status == GameStatus.playing && !state.peeking,
                    onHint: _hint,
                    onMagic: _magic,
                    onPeek: _peek,
                    onUndo: _ctrl.undo,
                  )
                else
                  const SizedBox(height: 120),
              ],
            ),
          ),
          if (state.status == GameStatus.won && image.hasValue)
            _CompletionOverlay(
              puzzle: puzzle,
              image: image.requireValue,
              state: state,
              reward: _reward,
              questsReady: _questsReady,
              unlocked: _unlocked,
              pack: _packProgress(puzzle, state),
              onQuests: () => context.go('/events'),
              onReplay: () {
                _completionHandled = false;
                setState(() {
                  _reward = null;
                  _questsReady = const [];
                  _unlocked = const [];
                });
                _newPlay();
                _ctrl.restart();
              },
              onNext: (next) async {
                final offer = await maybeShowInterstitial(context, ref);
                if (!context.mounted) return;
                if (offer != null && leaveGameForCreative(context, ref, offer)) return;
                if (next != null) {
                  // Same mode, tier and Painting; the next picture settles its own size.
                  context.pushReplacement('/game/${next.id}/${BoardCode.toPath(_spec.fullCode)}${_painting ? '?painting=1' : ''}');
                } else {
                  context.pop();
                }
              },
              onHome: () async {
                final offer = await maybeShowInterstitial(context, ref);
                if (!context.mounted) return;
                if (offer != null && leaveGameForCreative(context, ref, offer)) return;
                context.pop();
              },
            ),
          // Over the results: the panel is opaque.
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 24,
              maxBlastForce: 24,
              minBlastForce: 8,
              gravity: 0.25,
              emissionFrequency: 0.04,
              colors: const [Brand.accent, Brand.star, Brand.ticket, Color(0xFF94A3B8), Colors.white],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({required this.state, required this.showTimer, required this.onPause, required this.title, this.painting = false});
  final GameState state;
  final bool showTimer;
  final VoidCallback onPause;
  final String title;
  final bool painting;

  @override
  // Chrome keeps its size above the text-size cap of the bars (see ChromeText).
  Widget build(BuildContext context) => ChromeText(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = context.colors;
    final b = state.board;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              RoundIconButton(icon: AppIcons.pauseFill, size: 40, onTap: onPause),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.body)),
                    Text('${b.spec.mode.label} · ${b.spec.code} · ${b.spec.label}${painting ? ' · Painting' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontSize: TypeSize.caption)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Moves against par ("14 / 18": three stars while within it), then time.
              _HudStat(label: 'Moves', value: formatCount(state.moves), sub: '/${state.par}'),
              if (showTimer) ...[
                const SizedBox(width: 16),
                _HudStat(label: 'Time', value: formatDuration(state.elapsed)),
              ],
              const SizedBox(width: 4),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: ProgressBar(value: b.lockedCount / b.cells, height: 6)),
              const SizedBox(width: 10),
              Text('${b.lockedCount}/${b.cells} locked${b.floatingGroups > 0 ? ' · ${b.floatingGroups} group${b.floatingGroups == 1 ? '' : 's'}' : ''}', style: TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w500, color: c.textSecondary)),
              const SizedBox(width: 10),
              Stars(count: state.stars, size: 14),
            ],
          ),
        ],
      ),
    );
  }
}

/// A HUD figure without a box: the name small above, the number below
/// (tabular figures, so the timer does not jitter), an optional quiet suffix.
class _HudStat extends StatelessWidget {
  const _HudStat({required this.label, required this.value, this.sub});
  final String label;
  final String value;
  final String? sub;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: TextStyle(fontSize: TypeSize.micro, fontWeight: FontWeight.w600, color: c.textTertiary)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.headline, letterSpacing: -0.3, fontFeatures: tabularFigures)),
            if (sub != null) Text(sub!, style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textTertiary, fontFeatures: tabularFigures)),
          ],
        ),
      ],
    );
  }
}

class _BoosterBar extends StatelessWidget {
  const _BoosterBar({required this.hints, this.peeks = 0, this.magics = 0, required this.canUndo, required this.playing, required this.onHint, required this.onMagic, required this.onPeek, required this.onUndo});
  final int hints;

  /// Peeks and Magic in stock: used before coins, shown as a count on the tool.
  final int peeks;
  final int magics;
  final bool canUndo;
  final bool playing;

  final VoidCallback onHint;
  final VoidCallback onMagic;
  final VoidCallback onPeek;
  final VoidCallback onUndo;

  @override
  // Chrome keeps its size above the text-size cap of the bars (see ChromeText).
  Widget build(BuildContext context) => ChromeText(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = context.colors;
    final row = Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _Booster(icon: AppIcons.undo, label: 'Undo', enabled: canUndo, onTap: onUndo),
        _Booster(key: const ValueKey('booster-peek'), icon: AppIcons.peek, label: 'Peek', stock: peeks, price: Economy.peekCostCoins, enabled: playing, onTap: onPeek),
        _Booster(key: const ValueKey('booster-magic'), icon: AppIcons.magic, label: 'Magic', stock: magics, price: Economy.magicLockCostCoins, enabled: playing, onTap: onMagic),
        _Booster(icon: AppIcons.hint, label: 'Hint', stock: hints, price: Economy.hintCostCoins, enabled: playing, onTap: onHint),
      ],
    );
    // A floating glass toolbar, the same material and shape as the tab bar.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.pill),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? 0.35 : 0.08), blurRadius: 18, offset: const Offset(0, 4))],
        ),
        child: GlassSurface(
          borderRadius: BorderRadius.circular(Radii.pill),
          opacity: context.isDark ? 0.7 : 0.82,
          hairline: Border.all(color: c.stroke, width: 0.5),
          child: Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 7), child: row),
        ),
      ),
    );
  }
}

/// One tool. What it costs reads the same on every tool: a count on its
/// corner while there are some in stock, else its price in coins under the
/// label. Undo is free and shows neither.
class _Booster extends StatelessWidget {
  const _Booster({super.key, required this.icon, required this.label, required this.enabled, required this.onTap, this.stock, this.price});
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  /// In stock (used before coins); null for free tools.
  final int? stock;

  /// Coins per use once the stock is out.
  final int? price;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final count = stock ?? 0;
    final buying = stock != null && count == 0 && price != null;
    return Pressable(
      onTap: enabled ? onTap : null,
      scale: 0.9,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  SizedBox(width: 40, height: 30, child: Icon(icon, size: 26, color: context.accent)),
                  if (count > 0)
                    Positioned(
                      right: -11,
                      top: -6,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.textPrimary,
                          borderRadius: BorderRadius.circular(Radii.pill),
                          border: Border.all(color: c.card, width: 1.5),
                        ),
                        child: Text('$count', style: TextStyle(fontSize: TypeSize.micro, fontWeight: FontWeight.w700, color: c.card, height: 1.1)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w600)),
              SizedBox(
                height: 14,
                child: buying ? Amount(currency: Currency.coins, value: price!, size: 12, fontSize: TypeSize.micro, weight: FontWeight.w600, color: c.textSecondary) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PauseSheet extends ConsumerWidget {
  const _PauseSheet({required this.onResume, required this.onRestart, required this.onQuit, required this.onChangeDifficulty});
  final VoidCallback onChangeDifficulty;
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onQuit;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(title: 'Paused', center: true),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _PauseToggle(icon: AppIcons.musicNote2, label: 'Music', on: settings.music, onChanged: n.setMusic),
              _PauseToggle(icon: AppIcons.speaker2Fill, label: 'Sound', on: settings.sound, onChanged: n.setSound),
              _PauseToggle(icon: AppIcons.waveform, label: 'Haptics', on: settings.haptics, onChanged: n.setHaptics),
              _PauseToggle(icon: AppIcons.time, label: 'Timer', on: settings.showTimer, onChanged: n.setShowTimer),
            ],
          ),
          const SizedBox(height: 20),
          BigButton(label: 'Resume', icon: AppIcons.playFill, onTap: onResume),
          const SizedBox(height: 12),
          // The other ways out, as one grouped list: one primary action above it.
          SoftCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _PauseAction(icon: AppIcons.shuffle, label: 'Shuffle and restart', onTap: onRestart),
                _PauseDivider(),
                _PauseAction(icon: AppIcons.sliderHorizontal3, label: 'Change mode or board', onTap: onChangeDifficulty),
                _PauseDivider(),
                _PauseAction(icon: AppIcons.squareArrowLeft, label: 'Save & quit', onTap: onQuit),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// An on/off switch as a round button, the way Control Center draws them:
/// filled cobalt with a white mark when on, grey when off, and the state
/// spelled out under the name.
class _PauseToggle extends StatelessWidget {
  const _PauseToggle({required this.icon, required this.label, required this.on, required this.onChanged});
  final IconData icon;
  final String label;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      toggled: on,
      label: label,
      child: Pressable(
        onTap: () => onChanged(!on),
        scale: 0.92,
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: on ? context.accentFill : (context.isDark ? c.cardElevated : const Color(0xFFE6E6EB)), shape: BoxShape.circle),
                child: Icon(icon, size: 23, color: on ? context.onAccent : c.textSecondary),
              ),
              const SizedBox(height: 5),
              Text(label, style: const TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w600)),
              Text(on ? 'On' : 'Off', style: TextStyle(fontSize: TypeSize.micro, fontWeight: FontWeight.w500, color: c.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row in the pause sheet's grouped list.
class _PauseAction extends StatelessWidget {
  const _PauseAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        scale: 0.99,
        child: SizedBox(
          height: 50,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(icon, size: 20, color: context.accent),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: const TextStyle(fontSize: TypeSize.callout, fontWeight: FontWeight.w500))),
            ],
          ),
        ),
      );
}

class _PauseDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Divider(height: 0.5, thickness: 0.5, indent: 50, color: context.colors.stroke);
}

/// First game: a coach line between the HUD and the board that follows the
/// player: pick a card, place it, then how groups and locks work. It never
/// covers the board; "Got it" (or the first locked card's step) ends it.
class _CoachLine extends StatelessWidget {
  const _CoachLine({required this.state, required this.onDone});
  final GameState state;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = state.board;
    final (IconData icon, String text) = b.lockedCount > 0
        ? (AppIcons.lock, 'A card in its true spot locks in place. Fewer moves earn more stars.')
        : state.moves > 0
        ? (AppIcons.group, 'Neighbours in the picture snap into a group and move together.')
        : state.selected != null
        ? (AppIcons.tapCard, 'Now tap the place where it belongs. Or drag it there.')
        : (AppIcons.tapCard, 'Tap a card to pick it up.');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: Container(
          key: ValueKey(text),
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          decoration: BoxDecoration(color: c.accentTint, borderRadius: BorderRadius.circular(Radii.md)),
          child: Row(
            children: [
              Icon(icon, size: 18, color: context.accent),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: TextStyle(fontSize: TypeSize.footnote, height: 1.3, fontWeight: FontWeight.w500, color: c.textPrimary))),
              Pressable(
                onTap: onDone,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text('Got it', style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w700, color: context.accent)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Standing in the pack shown on the completion screen.
class _PackProgress {
  const _PackProgress({required this.name, required this.solved, required this.total, required this.stars, required this.next});
  final String? name;
  final int solved;
  final int total;
  final int stars;

  /// Next unsolved puzzle in the pack, or null when every puzzle is solved.
  final Puzzle? next;

  bool get complete => total > 0 && solved >= total;
}

/// Completion: the picture is revealed with rewards and next actions. A
/// "View picture" pill swaps the results for the finished photo on its own,
/// with one way forward kept at the bottom so nobody gets stuck.
class _CompletionOverlay extends StatefulWidget {
  const _CompletionOverlay({
    required this.puzzle,
    required this.image,
    required this.state,
    required this.reward,
    required this.pack,
    required this.onReplay,
    required this.onNext,
    required this.onHome,
    this.questsReady = const [],
    this.unlocked = const [],
    this.onQuests,
  });
  final Puzzle puzzle;
  final ui.Image image;
  final GameState state;
  final ({int coins, int xp, bool levelUp, int level})? reward;

  /// Quests this solve finished; a tap opens the Quests tab to claim them.
  final List<Goal> questsReady;

  /// What the level-up opened (Squares, Painting...).
  final List<Unlock> unlocked;
  final VoidCallback? onQuests;
  final _PackProgress pack;
  final VoidCallback onReplay;
  final void Function(Puzzle? next) onNext;
  final VoidCallback onHome;

  @override
  State<_CompletionOverlay> createState() => _CompletionOverlayState();
}

class _CompletionOverlayState extends State<_CompletionOverlay> {
  static const _swap = Duration(milliseconds: 250);

  /// Target mode; the picture layer stays mounted until its fade-out ends.
  bool _viewing = false;
  bool _pictureMounted = false;

  void _view() => setState(() {
        _viewing = true;
        _pictureMounted = true;
      });

  void _results() => setState(() => _viewing = false);

  @override
  Widget build(BuildContext context) {
    final puzzle = widget.puzzle, state = widget.state, reward = widget.reward, pack = widget.pack;
    final c = context.colors;
    // The pack is finished (or nothing unsolved is playable): the primary
    // action returns to the pack instead of promising a next puzzle.
    final backIsPrimary = pack.next == null;
    final credit = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(AppIcons.credit, size: 12, color: _viewing ? Colors.white.withValues(alpha: 0.7) : c.textTertiary),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            '${puzzle.author} · ${puzzle.source}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: TypeSize.caption, color: _viewing ? Colors.white.withValues(alpha: 0.7) : c.textTertiary),
          ),
        ),
      ],
    );

    // The finished picture is the reward: it stays in full colour above a
    // results panel (no scrim over it). A tap on it shows it on its own.
    final stats = Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _RewardStat(icon: const CoinIcon(size: 17), label: 'Coins', value: reward == null ? '…' : '+${formatCount(reward.coins)}'),
        _RewardStat(icon: Icon(AppIcons.xp, size: 17, color: context.accent), label: 'XP', value: reward == null ? '…' : '+${formatCount(reward.xp)}'),
        _RewardStat(label: 'Moves', value: formatCount(state.moves)),
        _RewardStat(label: 'Time', value: formatDuration(state.elapsed)),
      ],
    );
    final panel = Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? 0.4 : 0.1), blurRadius: 24, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Scrolls when a quest and a level-up make it taller than a small phone.
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < 3; i++)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: Icon(
                                i < state.stars ? AppIcons.star : AppIcons.starOutline,
                                size: i == 1 ? 34 : 28,
                                color: i < state.stars ? Brand.star : c.stroke,
                              ).animate().scale(delay: (300 + i * 150).ms, begin: const Offset(0, 0), curve: Curves.easeOutBack, duration: 450.ms),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Picture complete', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 2),
                      Text(puzzle.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w600, fontSize: TypeSize.body)),
                      const SizedBox(height: 16),
                      stats,
                      if (pack.total > 0) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${formatCount(pack.solved)} of ${formatCount(pack.total)} solved${pack.name != null ? ' · ${pack.name}' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textSecondary),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Icon(AppIcons.star, size: 13, color: Brand.star),
                            const SizedBox(width: 4),
                            Text('${formatCount(pack.stars)}/${formatCount(pack.total * 3)}', style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w700, color: c.textPrimary)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ProgressBar(value: pack.solved / pack.total, height: 4),
                      ],
                      if (reward?.levelUp == true) ...[
                        const SizedBox(height: 12),
                        _ResultLine(
                          key: const ValueKey('level-up-line'),
                          icon: AppIcons.crown,
                          text: widget.unlocked.isEmpty
                              ? 'Level ${reward!.level} reached'
                              : 'Level ${reward!.level} · ${widget.unlocked.map((u) => u == Unlock.painting ? 'Painting is open' : '${u.label} are open').join(' · ')}',
                          tinted: true,
                        ).animate().fadeIn(),
                      ],
                      if (widget.questsReady.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _ResultLine(
                          key: const ValueKey('quest-ready-line'),
                          icon: AppIcons.quests,
                          text: widget.questsReady.length == 1 ? 'Quest ready: ${widget.questsReady.first.title}' : '${widget.questsReady.length} quests ready to claim',
                          onTap: widget.onQuests,
                        ).animate().fadeIn(delay: 200.ms),
                      ],
                      const SizedBox(height: 12),
                      credit,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  // Equal widths so neither label truncates on a 393 pt phone.
                  Expanded(child: BigButton(label: 'Replay', kind: ButtonKind.secondary, icon: AppIcons.arrowCounterclockwise, onTap: widget.onReplay)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: backIsPrimary
                        ? BigButton(label: 'Back to pack', icon: AppIcons.squareGrid2x2, onTap: widget.onHome)
                        : BigButton(label: 'Next puzzle', icon: AppIcons.arrowRight, onTap: () => widget.onNext(pack.next)),
                  ),
                ],
              ),
              if (backIsPrimary)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(pack.complete ? 'Every picture in this pack is solved' : 'Nothing else to play here yet', style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w600)),
                )
              else
                Pressable(onTap: widget.onHome, child: Padding(padding: const EdgeInsets.all(10), child: Text('Back to pack', style: TextStyle(color: context.accent, fontWeight: FontWeight.w600)))),
            ],
          ),
        ),
      ),
    ).animate().slideY(begin: 0.25, duration: 350.ms, curve: Curves.easeOutCubic).fadeIn(duration: 200.ms);

    final results = Container(
      color: c.canvas,
      child: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Center(
                  child: GestureDetector(
                    onTap: _view,
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.lg),
                          child: RawImage(image: widget.image, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                        ),
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: _OverlayPill(icon: AppIcons.arrowUpLeftArrowDownRight, label: 'View picture', onTap: _view, small: true),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          panel,
        ],
      ),
    );

    // The photo on its own: no scrim, gutters or borders. A tap anywhere
    // brings the results back; the primary action stays within reach.
    // On black the status bar turns light (time and battery stay readable).
    final picture = AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _results,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(child: RawImage(image: widget.image, fit: BoxFit.contain, filterQuality: FilterQuality.medium)),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  children: [
                    _OverlayPill(icon: AppIcons.listBullet, label: 'Back to results', onTap: _results),
                    const Spacer(),
                    credit,
                    const SizedBox(height: 10),
                    backIsPrimary
                        ? _OverlayPill(icon: AppIcons.squareGrid2x2, label: 'Back to pack', primary: true, onTap: widget.onHome)
                        : _OverlayPill(icon: AppIcons.arrowRight, label: 'Next puzzle', primary: true, onTap: () => widget.onNext(pack.next)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );

    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            ignoring: _viewing,
            child: AnimatedOpacity(opacity: _viewing ? 0 : 1, duration: _swap, curve: Curves.easeOut, child: results),
          ),
          if (_pictureMounted)
            IgnorePointer(
              ignoring: !_viewing,
              child: AnimatedOpacity(
                opacity: _viewing ? 1 : 0,
                duration: _swap,
                curve: Curves.easeOut,
                onEnd: () {
                  if (!_viewing && mounted) setState(() => _pictureMounted = false);
                },
                child: AnimatedScale(scale: _viewing ? 1 : 0.96, duration: _swap, curve: Curves.easeOut, child: picture),
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact pill over the finished picture: frosted glass, or solid accent
/// for the one primary action.
class _OverlayPill extends StatelessWidget {
  const _OverlayPill({required this.icon, required this.label, required this.onTap, this.primary = false, this.small = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  /// Over the picture's corner: a smaller pill.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? context.onAccent : Colors.white;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: small ? 13 : 17, color: fg),
        SizedBox(width: small ? 5 : 7),
        Text(label, style: TextStyle(color: fg, fontWeight: small ? FontWeight.w600 : FontWeight.w700, fontSize: small ? TypeSize.caption : TypeSize.body)),
      ],
    );
    final padding = small ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6) : const EdgeInsets.symmetric(horizontal: 16, vertical: 10);
    return Pressable(
      onTap: onTap,
      child: primary
          ? Container(
              padding: padding,
              decoration: BoxDecoration(color: context.accentFill, borderRadius: BorderRadius.circular(Radii.pill)),
              child: row,
            )
          : Glass(dark: true, radius: Radii.pill, padding: padding, opacity: 0.45, child: row),
    );
  }
}

class _RewardStat extends StatelessWidget {
  const _RewardStat({this.icon, required this.label, required this.value});

  /// Drawn before the value (the coin, the XP mark); counts go without one.
  final Widget? icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 4)],
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.headline)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: TypeSize.micro, fontWeight: FontWeight.w600, color: c.textTertiary)),
      ],
    );
  }
}

/// One extra result under the numbers (a level reached, a quest ready): an
/// icon and a line; tinted for news, outlined with a chevron when it opens something.
class _ResultLine extends StatelessWidget {
  const _ResultLine({super.key, required this.icon, required this.text, this.onTap, this.tinted = false});
  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final row = Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: tinted ? c.accentTint : c.canvas,
        borderRadius: BorderRadius.circular(Radii.md),
        border: tinted ? null : Border.all(color: c.stroke),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.footnote, color: tinted ? context.accent : c.textPrimary)),
          ),
          if (onTap != null) Icon(AppIcons.chevronRight, size: 15, color: c.textTertiary),
        ],
      ),
    );
    return onTap == null ? row : Pressable(onTap: onTap, scale: 0.99, child: row);
  }
}
