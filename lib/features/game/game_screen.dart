import 'dart:async';
import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../game/board.dart';
import '../../game/game_controller.dart';
import '../../game/image_loader.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/settings.dart';
import '../../state/social.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../ads/house_ads.dart';
import 'board_widget.dart';

/// The play screen: HUD, board, booster bar, pause and completion overlays.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, required this.puzzleId, required this.gridCode});
  final String puzzleId;
  final String gridCode;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> with WidgetsBindingObserver {
  late final BoardSpec _spec = BoardSpec.fromCode(widget.gridCode);
  GameArgs? _args;
  StreamSubscription<GameEventKind>? _sub;
  Timer? _saveDebounce;
  final _confetti = ConfettiController(duration: const Duration(seconds: 2));
  bool _completionHandled = false;
  ({int coins, int xp, bool levelUp, int level})? _reward;
  bool _showTutorial = false;
  int _chainFlash = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final existing = ref.read(puzzleProgressProvider(widget.puzzleId));
    final resume = existing != null && existing.inProgress && existing.gridSize == _spec.cells && existing.mode == _spec.mode.code;
    _args = GameArgs(
      puzzleId: widget.puzzleId,
      spec: _spec,
      layout: resume ? existing.layout : null,
      moves: resume ? existing.moves : 0,
      elapsed: resume ? existing.elapsedSeconds : 0,
      hintsUsed: resume ? existing.hintsUsed : 0,
    );
    _showTutorial = !ref.read(settingsProvider).tutorialSeen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sub = ref.read(gameControllerProvider(_args!).notifier).events.listen(_onEvent);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _saveDebounce?.cancel();
    _confetti.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveNow();
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
    if (_args == null || !mounted) return;
    final s = ref.read(gameControllerProvider(_args!));
    if (s.status == GameStatus.won) return;
    ref.read(progressProvider.notifier).save(widget.puzzleId, {
      'gridSize': _spec.cells,
      'mode': _spec.mode.code,
      'layout': s.board.slots.join(','),
      'moves': s.moves,
      'elapsedSeconds': s.elapsed,
      'hintsUsed': s.hintsUsed,
      'completed': false,
    });
  }

  Future<void> _onWin() async {
    if (_completionHandled) return;
    _completionHandled = true;
    _saveDebounce?.cancel();
    Sfx.instance.win();
    Haptics.success();
    _confetti.play();
    final s = ref.read(gameControllerProvider(_args!));
    final existing = ref.read(puzzleProgressProvider(widget.puzzleId));
    final firstTime = existing?.completed != true;
    final stars = s.stars;
    final bestMoves = existing?.bestMoves == null ? s.moves : math.min(existing!.bestMoves!, s.moves);
    final bestSeconds = existing?.bestSeconds == null ? s.elapsed : math.min(existing!.bestSeconds!, s.elapsed);
    final puzzle = ref.read(resolvedPuzzleProvider(widget.puzzleId));
    final daily = ref.read(dailyPuzzleProvider);
    await ref.read(progressProvider.notifier).save(widget.puzzleId, {
      'gridSize': _spec.cells,
      'mode': _spec.mode.code,
      'layout': '',
      'moves': s.moves,
      'elapsedSeconds': s.elapsed,
      'hintsUsed': s.hintsUsed,
      'completed': true,
      'stars': math.max(stars, existing?.stars ?? 0),
      'bestMoves': bestMoves,
      'bestSeconds': bestSeconds,
      'completedAt': DateTime.now().toUtc().toIso8601String(),
    });
    final reward = await ref.read(profileProvider.notifier).recordCompletion(cells: _spec.cells, stars: stars, firstTime: firstTime, mode: _spec.mode);
    var coins = reward.coins;
    if (daily != null && daily.id == widget.puzzleId && firstTime) {
      await ref.read(profileProvider.notifier).addCoins(50, reason: 'daily-puzzle');
      coins += 50;
    }
    unawaited(bumpEventProgress(ref, packId: puzzle?.packId));
    if (!mounted) return;
    setState(() => _reward = (coins: coins, xp: reward.xp, levelUp: reward.levelUp, level: reward.level));
  }

  Future<void> _hint() async {
    final profile = ref.read(profileProvider).value;
    if (profile == null) return;
    final ok = await ref.read(profileProvider.notifier).useHint();
    if (!mounted) return;
    if (!ok) {
      Sfx.instance.error();
      _offerStore('No Hints left. Buy one for ${Economy.hintCostCoins} Coins.');
      return;
    }
    Sfx.instance.coin();
    _ctrl.showHint();
  }

  Future<void> _magic() async {
    final ok = await ref.read(profileProvider.notifier).spendCoins(Economy.magicLockCostCoins, reason: 'magic-lock');
    if (!mounted) return;
    if (!ok) {
      Sfx.instance.error();
      _offerStore('Not enough Coins. Magic costs ${Economy.magicLockCostCoins} Coins.');
      return;
    }
    Sfx.instance.coin();
    _ctrl.magicLock();
  }

  Future<void> _peek() async {
    final ok = await ref.read(profileProvider.notifier).spendCoins(Economy.peekCostCoins, reason: 'peek');
    if (!mounted) return;
    if (!ok) {
      Sfx.instance.error();
      _offerStore('Not enough Coins. Peek costs ${Economy.peekCostCoins} Coins.');
      return;
    }
    Sfx.instance.whoosh();
    _ctrl.peek();
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
        onRestart: () {
          Navigator.pop(ctx);
          _completionHandled = false;
          _ctrl.restart();
        },
        onQuit: () {
          Navigator.pop(ctx);
          _saveNow();
          context.pop();
        },
      ),
    ).then((_) => _ctrl.resume());
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
    final image = ref.watch(puzzleImageProvider(puzzle.imageUrl));
    final state = ref.watch(gameControllerProvider(_args!));

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
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, cons) {
                      final maxW = cons.maxWidth - 24;
                      final maxH = cons.maxHeight - 16;
                      final aspect = image.value == null ? 3 / 4 : image.value!.width / image.value!.height;
                      var w = maxW;
                      var h = w / aspect;
                      if (h > maxH) {
                        h = maxH;
                        w = h * aspect;
                      }
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
                                    child: Opacity(opacity: 0.6, child: BlurHash(hash: puzzle.blurhash!, color: c.boardBackground)),
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
                            action: BigButton(label: 'Try again', expand: false, onTap: () => ref.invalidate(puzzleImageProvider(puzzle.imageUrl))),
                          ),
                          data: (img) => Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              BoardWidget(
                                image: img,
                                state: state,
                                width: w,
                                height: h,
                                cardStyle: settings.cardStyle,
                                onTap: _ctrl.tap,
                                onDrop: _ctrl.drop,
                              ),
                              if (_chainFlash > 0)
                                IgnorePointer(
                                  child: Text('×2 DOUBLE LOCK', key: ValueKey(_chainFlash), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 24, letterSpacing: -0.3, color: Brand.star, shadows: [Shadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 12)]))
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
                    canUndo: state.canUndo,
                    playing: state.status == GameStatus.playing,
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
          if (_showTutorial && image.hasValue)
            _TutorialOverlay(onDone: () {
              ref.read(settingsProvider.notifier).setTutorialSeen();
              setState(() => _showTutorial = false);
            }),
          if (state.status == GameStatus.won && image.hasValue)
            _CompletionOverlay(
              puzzle: puzzle,
              state: state,
              reward: _reward,
              onReplay: () {
                _completionHandled = false;
                setState(() => _reward = null);
                _ctrl.restart();
              },
              onNext: () async {
                await maybeShowInterstitial(context, ref);
                if (!context.mounted) return;
                final all = ref.read(allPuzzlesProvider).value ?? const <Puzzle>[];
                final pack = all.where((p) => p.packId == puzzle.packId).toList();
                final idx = pack.indexWhere((p) => p.id == puzzle.id);
                if (idx >= 0 && idx + 1 < pack.length) {
                  context.pushReplacement('/game/${pack[idx + 1].id}/${widget.gridCode}');
                } else {
                  context.pop();
                }
              },
              onHome: () async {
                await maybeShowInterstitial(context, ref);
                if (context.mounted) context.pop();
              },
            ),
        ],
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({required this.state, required this.showTimer, required this.onPause, required this.title});
  final GameState state;
  final bool showTimer;
  final VoidCallback onPause;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = state.board;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              RoundIconButton(icon: CupertinoIcons.pause_fill, size: 40, onTap: onPause),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text('${b.spec.mode.label} · ${b.spec.code} · ${b.spec.label}', style: TextStyle(color: c.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              _HudStat(icon: CupertinoIcons.arrow_right_arrow_left, label: 'Moves', value: '${state.moves}', sub: 'par ${state.par}'),
              if (showTimer) ...[
                const SizedBox(width: 8),
                _HudStat(icon: CupertinoIcons.time, label: 'Time', value: formatDuration(state.elapsed)),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: ProgressBar(value: b.lockedCount / b.cells, height: 6)),
              const SizedBox(width: 10),
              Text('${b.lockedCount}/${b.cells} locked${b.floatingGroups > 0 ? ' · ${b.floatingGroups} group${b.floatingGroups == 1 ? '' : 's'}' : ''}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.textSecondary)),
              const SizedBox(width: 10),
              Stars(count: state.stars, size: 14),
            ],
          ),
        ],
      ),
    );
  }
}

class _HudStat extends StatelessWidget {
  const _HudStat({required this.icon, required this.label, required this.value, this.sub});
  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.stroke)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: c.textTertiary),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c.textTertiary)),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: -0.3)),
              if (sub != null) ...[const SizedBox(width: 4), Text(sub!, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: c.textTertiary))],
            ],
          ),
        ],
      ),
    );
  }
}

class _BoosterBar extends StatelessWidget {
  const _BoosterBar({required this.hints, required this.canUndo, required this.playing, required this.onHint, required this.onMagic, required this.onPeek, required this.onUndo});
  final int hints;
  final bool canUndo;
  final bool playing;
  final VoidCallback onHint;
  final VoidCallback onMagic;
  final VoidCallback onPeek;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.stroke),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Booster(icon: AppIcons.undo, label: 'Undo', cost: const Text('free'), enabled: canUndo, onTap: onUndo),
          _Booster(icon: AppIcons.peek, label: 'Peek', cost: Amount(currency: Currency.coins, value: Economy.peekCostCoins, size: 11, fontSize: 10, weight: FontWeight.w700), enabled: playing, onTap: onPeek),
          _Booster(icon: AppIcons.hint, label: 'Hint', cost: hints > 0 ? Text('$hints left') : Amount(currency: Currency.coins, value: Economy.hintCostCoins, size: 11, fontSize: 10, weight: FontWeight.w700), enabled: playing, onTap: onHint, accent: hints > 0),
          _Booster(icon: AppIcons.magic, label: 'Magic', cost: Amount(currency: Currency.coins, value: Economy.magicLockCostCoins, size: 11, fontSize: 10, weight: FontWeight.w700), enabled: playing, onTap: onMagic),
        ],
      ),
    );
  }
}

class _Booster extends StatelessWidget {
  const _Booster({required this.icon, required this.label, required this.cost, required this.enabled, required this.onTap, this.accent = false});
  final IconData icon;
  final String label;
  final Widget cost;
  final bool enabled;
  final VoidCallback onTap;
  final bool accent;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: enabled ? onTap : null,
      scale: 0.9,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTile(icon: icon, size: 48, radius: 14, color: c.accentTint, iconColor: accent ? Brand.hint : context.accent),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
            DefaultTextStyle(style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: c.textTertiary), child: cost),
          ],
        ),
      ),
    );
  }
}

class _PauseSheet extends ConsumerWidget {
  const _PauseSheet({required this.onResume, required this.onRestart, required this.onQuit});
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
          Text('Paused', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              RoundIconButton(icon: settings.music ? CupertinoIcons.music_note_2 : CupertinoIcons.speaker_slash, label: 'Music', size: 52, onTap: () => n.setMusic(!settings.music), iconColor: settings.music ? context.accent : null),
              RoundIconButton(icon: settings.sound ? CupertinoIcons.speaker_2_fill : CupertinoIcons.speaker_slash_fill, label: 'Sound', size: 52, onTap: () => n.setSound(!settings.sound), iconColor: settings.sound ? context.accent : null),
              RoundIconButton(icon: CupertinoIcons.waveform, label: 'Haptics', size: 52, onTap: () => n.setHaptics(!settings.haptics), iconColor: settings.haptics ? context.accent : null),
              RoundIconButton(icon: CupertinoIcons.time, label: 'Timer', size: 52, onTap: () => n.setShowTimer(!settings.showTimer), iconColor: settings.showTimer ? context.accent : null),
            ],
          ),
          const SizedBox(height: 22),
          BigButton(label: 'Resume', icon: CupertinoIcons.play_fill, onTap: onResume),
          const SizedBox(height: 10),
          BigButton(label: 'Shuffle and restart', kind: ButtonKind.secondary, icon: CupertinoIcons.shuffle, onTap: onRestart),
          const SizedBox(height: 10),
          BigButton(label: 'Save & quit', kind: ButtonKind.ghost, onTap: onQuit),
        ],
      ),
    );
  }
}

/// First-time, finger-guided hint overlay.
class _TutorialOverlay extends StatelessWidget {
  const _TutorialOverlay({required this.onDone});
  final VoidCallback onDone;
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: onDone,
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(28),
          child: SoftCard(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const IconTile(icon: Icons.touch_app_rounded, size: 56, radius: 16),
                const SizedBox(height: 14),
                Text('How to play', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Tap a card, then tap where it belongs. Or drag it there.\n\nCards that sit next to each other in the picture snap into a group anywhere on the board and move together. A card in its true spot locks in place. Fewer moves earn more stars. There is no timer pressure.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.colors.textSecondary, height: 1.45),
                ),
                const SizedBox(height: 18),
                BigButton(label: 'Got it', onTap: onDone),
              ],
            ),
          ).animate().scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutBack).fadeIn(),
        ),
      ),
    );
  }
}

/// Completion: the picture is revealed full-bleed with rewards and next actions.
class _CompletionOverlay extends StatelessWidget {
  const _CompletionOverlay({required this.puzzle, required this.state, required this.reward, required this.onReplay, required this.onNext, required this.onHome});
  final Puzzle puzzle;
  final GameState state;
  final ({int coins, int xp, bool levelUp, int level})? reward;
  final VoidCallback onReplay;
  final VoidCallback onNext;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.5),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              children: [
                const Spacer(),
                Text('Picture complete', style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white))
                    .animate()
                    .fadeIn(delay: 300.ms)
                    .slideY(begin: 0.3, curve: Curves.easeOutBack),
                const SizedBox(height: 6),
                Text(puzzle.title, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w700, fontSize: 15)).animate().fadeIn(delay: 400.ms),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          i < state.stars ? CupertinoIcons.star_fill : CupertinoIcons.star,
                          size: i == 1 ? 54 : 42,
                          color: i < state.stars ? Brand.star : Colors.white.withValues(alpha: 0.4),
                        ).animate().scale(delay: (500 + i * 180).ms, begin: const Offset(0, 0), curve: Curves.elasticOut, duration: 700.ms),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                SoftCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _RewardStat(icon: const CoinIcon(size: 22), label: 'Coins', value: reward == null ? '…' : '+${reward!.coins}'),
                          _RewardStat(icon: Icon(AppIcons.xp, size: 22, color: context.accent), label: 'XP', value: reward == null ? '…' : '+${reward!.xp}'),
                          _RewardStat(icon: Icon(AppIcons.swaps, size: 22, color: c.textSecondary), label: 'Moves', value: '${state.moves}', sub: 'par ${state.par}'),
                          _RewardStat(icon: Icon(AppIcons.time, size: 22, color: c.textSecondary), label: 'Time', value: formatDuration(state.elapsed)),
                        ],
                      ),
                      if (reward?.levelUp == true) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(color: c.accentTint, borderRadius: BorderRadius.circular(Radii.md)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(AppIcons.crown, size: 20, color: context.accent),
                              const SizedBox(width: 8),
                              Text('Level ${reward!.level} reached', style: TextStyle(fontWeight: FontWeight.w600, color: context.accent)),
                            ],
                          ),
                        ).animate().fadeIn(),
                      ],
                      const SizedBox(height: 10),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(AppIcons.credit, size: 12, color: c.textTertiary), const SizedBox(width: 5), Flexible(child: Text('${puzzle.author} · ${puzzle.source}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: c.textTertiary)))]),
                    ],
                  ),
                ).animate().fadeIn(delay: 900.ms).slideY(begin: 0.2, curve: Curves.easeOut),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: BigButton(label: 'Replay', kind: ButtonKind.secondary, icon: CupertinoIcons.arrow_counterclockwise, onTap: onReplay)),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: BigButton(label: 'Next puzzle', icon: CupertinoIcons.arrow_right, onTap: onNext)),
                  ],
                ).animate().fadeIn(delay: 1100.ms),
                const SizedBox(height: 8),
                Pressable(onTap: onHome, child: const Padding(padding: EdgeInsets.all(10), child: Text('Back to pack', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RewardStat extends StatelessWidget {
  const _RewardStat({required this.icon, required this.label, required this.value, this.sub});
  final Widget icon;
  final String label;
  final String value;
  final String? sub;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        SizedBox(height: 24, child: Center(child: icon)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        Text(sub ?? label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.textTertiary)),
      ],
    );
  }
}
