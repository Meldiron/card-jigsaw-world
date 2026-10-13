import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../game/board.dart';
import '../../game/image_loader.dart';
import '../../models/models.dart';
import '../../state/giant.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/rewards.dart';
import '../../state/settings.dart';
import '../../state/social.dart';
import '../../widgets/cached_url_image.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// Pre-game screen: preview with the cut overlay, mode picker, board picker
/// with reward preview, play button. This is the only place the cut preview
/// lives. Each tier's columns and rows are chosen for this picture's
/// proportions ([BoardSpec.forPicture]) from the same decoded image the
/// game uses, the preview frame takes the aspect the real board will have
/// (see [Tiling.boardAspect]) and the overlay is the real tiling, so what is
/// shown is what gets dealt and the tier labels name the real board. While
/// a board is in progress the choice is frozen on the saved mode and size:
/// Continue resumes it, Discard progress throws it away and reopens the
/// choice.
class DifficultyScreen extends ConsumerStatefulWidget {
  const DifficultyScreen({super.key, required this.puzzleId, this.initialGrid, this.initialMode, this.initialPainting = false});
  final String puzzleId;

  /// Painting preselected (`?painting=1`).
  final bool initialPainting;

  /// Optional tier code to preselect: legacy `5x5` or a full code such as
  /// `hexagons:5x6` / `hexagons-5x6` (used by goal shortcuts).
  final String? initialGrid;

  /// Optional mode code (`cards`, `squares`, `triangles`, `hexagons`).
  final String? initialMode;

  @override
  ConsumerState<DifficultyScreen> createState() => _DifficultyScreenState();
}

class _DifficultyScreenState extends ConsumerState<DifficultyScreen> {
  late GameMode _mode;

  /// Selected tier (its index, `BoardSpec.firstGiantTier` and up for giant
  /// sizes); its size follows the picture.
  late int _tier;

  /// Painting chosen for a new board.
  late bool _painting = widget.initialPainting;

  /// Decoded picture size (full resolution), once the image is in.
  Size? _imageSize;
  String? _resolvedUrl;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    final grid = widget.initialGrid;
    final hasGrid = grid != null && grid.isNotEmpty;
    final decoded = hasGrid ? BoardSpec.fromCode(grid) : null;
    final modeArg = widget.initialMode;
    _mode = modeArg != null && modeArg.isNotEmpty ? GameMode.fromCode(modeArg) : (decoded?.mode ?? GameMode.cards);
    if (decoded != null) {
      // A code names its tier (legacy codes such as 5x5 map onto the ladder
      // step they were); the same step is kept for another mode.
      _tier = decoded.tierIndex < 0 ? 2 : decoded.tierIndex;
    } else {
      final idx = GridSpec.tiers.indexWhere((t) => t.cells == ref.read(settingsProvider).defaultGrid);
      _tier = idx < 0 ? 2 : idx;
    }
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  void _stopListening() {
    if (_stream != null && _listener != null) _stream!.removeListener(_listener!);
    _stream = null;
    _listener = null;
  }

  /// Reads the picture's real dimensions from the same cached decode the
  /// preview shows, so the frame and the caption can follow the picture.
  void _resolveImage(Puzzle puzzle) {
    final url = puzzle.imageUrl;
    if (url.isEmpty || url == _resolvedUrl) return;
    _resolvedUrl = url;
    _stopListening();
    _imageSize = null;
    final stream = CachedUrlImage(url).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      final size = Size(info.image.width.toDouble(), info.image.height.toDouble());
      info.dispose();
      if (!mounted || _resolvedUrl != url) return;
      // The listener may fire synchronously from inside build; defer.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _resolvedUrl == url) setState(() => _imageSize = size);
      });
    }, onError: (_, _) {});
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  /// `1600 × 1067 · landscape`
  static String describeSize(Size s) {
    final w = s.width.round(), h = s.height.round();
    final orientation = w > h * 1.05 ? 'landscape' : (h > w * 1.05 ? 'portrait' : 'square');
    return '$w × $h · $orientation';
  }

  Future<void> _discard(PuzzleProgress saved, BoardSpec savedSpec) async {
    final ok = await showAppAlert(
      context,
      title: 'Discard progress?',
      message: 'The board you started (${saved.moves} ${saved.moves == 1 ? 'move' : 'moves'} in) is deleted. Best scores and stars stay.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (!ok || !mounted) return;
    // Keep the saved mode and size selected so the screen does not jump.
    setState(() {
      _mode = savedSpec.mode;
      _tier = savedSpec.tierIndex < 0 ? 2 : savedSpec.tierIndex;
      _painting = saved.painting;
    });
    await ref.read(progressProvider.notifier).discard(widget.puzzleId);
    if (!mounted) return;
    Haptics.medium();
    showToast(context, 'Progress discarded. Pick any mode or board.', icon: CupertinoIcons.trash);
  }

  void _pickMode(GameMode m) {
    if (m == _mode) return;
    Haptics.selection();
    setState(() => _mode = m);
  }

  Future<void> _offerUnlock(int tierIndex, BoardSpec t) async {
    final cost = Economy.tierUnlockCoins(tierIndex);
    final level = LevelRewards.tierUnlockLevel[tierIndex];
    await showAppSheet(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconTile(icon: AppIcons.lock, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Unlock ${t.label} now', style: Theme.of(ctx).textTheme.headlineSmall),
                      const SizedBox(height: 2),
                      Text(
                        '${t.code} ${_mode.label.toLowerCase()} boards open at level $level. Unlock them early and keep the bigger rewards.',
                        style: TextStyle(color: ctx.colors.textSecondary, fontSize: 13.5, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            BigButton(
              label: 'Unlock for',
              trailing: Amount(currency: Currency.coins, value: cost, size: 18, color: Colors.white),
              onTap: () async {
                final ok = await ref.read(profileProvider.notifier).unlockTier(_mode, tierIndex);
                if (!ctx.mounted || !mounted) return;
                Navigator.pop(ctx);
                if (ok) {
                  Sfx.instance.coin();
                  Haptics.success();
                  setState(() => _tier = tierIndex);
                  showToast(context, '${t.label} boards unlocked for ${_mode.label.toLowerCase()}', icon: AppIcons.unlock);
                } else {
                  showToast(context, 'Not enough coins. Visit the store or play more puzzles.', leading: const CoinIcon(size: 20));
                  context.push('/store');
                }
              },
            ),
            const SizedBox(height: 8),
            BigButton(label: 'Not now', kind: ButtonKind.ghost, onTap: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final puzzle = ref.watch(resolvedPuzzleProvider(widget.puzzleId));
    final progress = ref.watch(puzzleProgressProvider(widget.puzzleId));
    final profile = ref.watch(profileProvider).value;
    final profileN = ref.read(profileProvider.notifier);
    if (puzzle != null) _resolveImage(puzzle);
    // Giant pack pictures offer only the giant sizes, all open with the pack.
    final giant = ref.watch(isGiantPuzzleProvider(widget.puzzleId));
    // Boards are laid out for the picture's proportions, read from the same
    // decode the game uses so the preview and the deal always agree. Until
    // it is in, the full-size picture's dimensions (or 3:4) stand in.
    final decoded = puzzle == null || puzzle.imageUrl.isEmpty ? null : ref.watch(puzzleImageFor(puzzle.imageUrl, giant: giant)).value;
    final known = decoded != null;
    final imageAspect = decoded != null
        ? decoded.width / decoded.height
        : (_imageSize == null ? BoardSpec.referenceAspect : _imageSize!.width / _imageSize!.height);
    // A saved board pins the choice to what was dealt; the state fields keep
    // the player's own pick for after a discard. A save whose board this
    // picture no longer deals (an older layout) cannot be resumed: it is
    // left to be replaced by the next game.
    final savedRow = progress != null && progress.inProgress ? progress : null;
    BoardSpec? savedSpec;
    if (savedRow != null) {
      final m = GameMode.fromCode(savedRow.mode);
      savedSpec = BoardSpec.fromSaved(m, savedRow.gridSize, imageAspect) ?? (known ? null : BoardSpec.fromCells(m, savedRow.gridSize));
      if (savedSpec != null && known && !Board.isValidLayout(savedSpec, savedRow.layout)) savedSpec = null;
    }
    final saved = savedSpec != null ? savedRow : null;
    final mode = saved != null ? savedSpec!.mode : _mode;
    final tiers = BoardSpec.ladder(mode, imageAspect, giant: giant);
    // A size picked on the other ladder (a normal tier carried to a Giant
    // pack picture, say) falls back to that ladder's first giant or Relaxed size.
    final pick = giant ? (BoardSpec.isGiantTier(_tier) ? _tier - BoardSpec.firstGiantTier : 0) : (BoardSpec.isGiantTier(_tier) ? 2 : _tier);
    final spec = saved != null ? savedSpec! : tiers[pick.clamp(0, tiers.length - 1)];
    final painting = saved != null ? saved.painting : _painting;
    final coins = Economy.completionCoins(spec.cells, 3, mode: mode, painting: painting);
    final xp = Economy.completionXp(spec.cells, 3, mode: mode, painting: painting);
    final maxTier = LevelRewards.maxTierIndex(profile?.level ?? 1) + 1;
    final boardAspect = spec.tiling.boardAspect(imageAspect);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: RoundIconButton(icon: CupertinoIcons.back, size: 38, onTap: () => context.pop()),
        ),
        title: Text(puzzle?.title ?? 'Puzzle'),
      ),
      body: puzzle == null
          ? const Loader()
          : SafeArea(
              top: false,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + kToolbarHeight + 4, 20, 12),
                      child: Column(
                        children: [
                          // Preview in the real board's proportions with the
                          // chosen tiling drawn over the same centre crop the
                          // board will use (BoxFit.cover == Tiling.crop).
                          AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.32),
                              child: AspectRatio(
                                aspectRatio: boardAspect,
                                child: Container(
                                  clipBehavior: Clip.antiAlias,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(Radii.lg),
                                    border: Border.all(color: c.stroke),
                                  ),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      NetImage(url: puzzle.imageUrl, blurhash: puzzle.blurhash),
                                      CustomPaint(
                                        painter: _CutOverlay(spec: spec, imageAspect: imageAspect, color: Colors.white.withValues(alpha: 0.7)),
                                      ),
                                      if (progress?.completed == true)
                                        Positioned(
                                          left: 12,
                                          top: 12,
                                          child: Glass(
                                            dark: true,
                                            radius: 999,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Stars(count: progress!.stars, size: 13),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Best: ${progress.bestMoves ?? progress.moves} moves',
                                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      Positioned(
                                        left: 12,
                                        right: 12,
                                        bottom: 12,
                                        child: Glass(
                                          dark: true,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          child: Row(
                                            children: [
                                              const Icon(AppIcons.credit, size: 13, color: Colors.white),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      '${puzzle.author} · ${puzzle.source}',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w500),
                                                    ),
                                                    if (_imageSize != null)
                                                      Text(
                                                        describeSize(_imageSize!),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 10.5, fontWeight: FontWeight.w500),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ).animate().fadeIn(duration: 120.ms),
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Choose a mode', style: Theme.of(context).textTheme.headlineSmall),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              saved != null
                                  ? 'A ${mode.label.toLowerCase()} ${spec.code} board${painting ? ' in Painting' : ''} is in progress. Continue it, or discard it to pick another mode or size.'
                                  : 'Every mode cuts the picture differently. Trickier shapes pay more.',
                              style: TextStyle(color: c.textSecondary, fontSize: 13),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              for (final m in GameMode.values) ...[
                                Expanded(
                                  child: _ModeTile(mode: m, selected: m == mode, enabled: saved == null, onTap: () => _pickMode(m)),
                                ),
                                if (m != GameMode.values.last) const SizedBox(width: 8),
                              ],
                            ],
                          ),
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Choose a board', style: Theme.of(context).textTheme.headlineSmall),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              giant
                                  ? 'Giant boards of 100 cards and more, all open with this pack. Pinch to zoom in while you play.'
                                  : 'Bigger boards pay more. Higher levels unlock larger boards, or unlock them now with coins.',
                              style: TextStyle(color: c.textSecondary, fontSize: 13),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 92,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              itemCount: tiers.length,
                              separatorBuilder: (_, _) => const SizedBox(width: 8),
                              itemBuilder: (_, i) {
                                final t = tiers[i];
                                final selected = t == spec;
                                final locked = !giant && i >= maxTier && !profileN.hasTier(mode, i);
                                final fg = selected ? Colors.white : (locked ? c.textTertiary : c.textPrimary);
                                return Pressable(
                                  onTap: saved != null
                                      ? null
                                      : locked
                                      ? () => _offerUnlock(i, t)
                                      : () {
                                          Haptics.selection();
                                          setState(() => _tier = t.tier);
                                        },
                                  child: Opacity(
                                    opacity: saved != null && !selected ? 0.45 : 1,
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 180),
                                      width: 84,
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: selected ? context.accent : c.card,
                                        borderRadius: BorderRadius.circular(Radii.md),
                                        border: Border.all(color: selected ? context.accent : c.stroke),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          // Giant sizes borrow the top four tier marks.
                                          Icon(locked ? AppIcons.lock : AppIcons.tier(giant ? 4 + i : i), size: 22, color: selected ? Colors.white : (locked ? c.textTertiary : context.accent)),
                                          const SizedBox(height: 4),
                                          Text(
                                            t.code,
                                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: fg),
                                          ),
                                          Text(t.label, style: TextStyle(fontSize: 11, color: selected ? Colors.white.withValues(alpha: 0.85) : (locked ? c.textTertiary : c.textSecondary))),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          _PaintingTile(
                            on: painting,
                            enabled: saved == null,
                            onChanged: (v) {
                              Haptics.selection();
                              setState(() => _painting = v);
                            },
                          ),
                          const SizedBox(height: 16),
                          // One row: caption with the mode multiplier, then
                          // three equal chips that wrap on narrow screens.
                          SoftCard(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Rewards',
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, letterSpacing: 0.2, color: c.textSecondary),
                                    ),
                                    const SizedBox(width: 8),
                                    Chip2(label: 'x${_fmtMult(mode.multiplier)}', color: c.accentTint, foreground: context.accent),
                                    if (painting) ...[
                                      const SizedBox(width: 6),
                                      Chip2(key: const ValueKey('painting-bonus'), label: 'Painting x${_fmtMult(Economy.paintingMultiplier)}', color: c.accentTint, foreground: context.accent),
                                    ],
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text('for 3 stars', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                LayoutBuilder(
                                  builder: (context, cons) {
                                    const gap = 12.0;
                                    // Three across when they fit; on a 320 pt screen the third
                                    // chip wraps to a second row.
                                    final width = math.max(92.0, (cons.maxWidth - 2 * gap) / 3).floorToDouble();
                                    return Wrap(
                                      spacing: gap,
                                      runSpacing: gap,
                                      children: [
                                        _RewardChip(
                                          width: width,
                                          child: Amount(currency: Currency.coins, value: coins, prefix: 'up to ', size: 16, fontSize: 13, weight: FontWeight.w600),
                                        ),
                                        _RewardChip(width: width, icon: AppIcons.xp, label: '+$xp XP'),
                                        _RewardChip(width: width, icon: AppIcons.piggy, label: '+${Economy.piggyPerPuzzle}'),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BigButton(
                          label: saved != null
                              ? 'Continue · ${saved.moves} ${saved.moves == 1 ? 'move' : 'moves'} in'
                              : '${spec.cells} ${mode == GameMode.cards ? 'cards' : mode.label.toLowerCase()} · Play',
                          icon: CupertinoIcons.play_fill,
                          onTap: () {
                            // The default size follows normal boards only.
                            if (!spec.isGiant) {
                              final idx = spec.tierIndex < 0 ? 2 : spec.tierIndex;
                              ref.read(settingsProvider.notifier).setDefaultGrid(GridSpec.tiers[idx].cells);
                            }
                            // A saved board resumes the way it was saved, so only a new one carries the choice.
                            final flag = saved == null && painting ? '?painting=1' : '';
                            context.pushReplacement('/game/${widget.puzzleId}/${BoardCode.toPath(spec.fullCode)}$flag');
                          },
                        ),
                        if (saved != null) ...[const SizedBox(height: 8), BigButton(label: 'Discard progress', kind: ButtonKind.ghost, icon: CupertinoIcons.trash, onTap: () => _discard(saved, spec))],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  static String _fmtMult(double m) => m == m.roundToDouble() ? '${m.toInt()}.0' : m.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}

/// The Painting option: works with every shape and size and pays
/// [Economy.paintingMultiplier] more. Frozen while a board is in progress.
class _PaintingTile extends StatelessWidget {
  const _PaintingTile({required this.on, required this.enabled, required this.onChanged});
  final bool on;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      key: const ValueKey('painting-option'),
      onTap: enabled ? () => onChanged(!on) : null,
      scale: 0.99,
      child: Opacity(
        opacity: enabled || on ? 1 : 0.45,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: on ? c.accentTint : c.card,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: on ? context.accent : c.stroke),
          ),
          child: Row(
            children: [
              const IconTile(icon: AppIcons.painting, size: 36, radius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Painting · x${_DifficultyScreenState._fmtMult(Economy.paintingMultiplier)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text('Cards start in black and white and get their colour back as they lock.', style: TextStyle(fontSize: 12.5, height: 1.3, color: c.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              CupertinoSwitch(value: on, activeTrackColor: Brand.success, onChanged: enabled ? onChanged : null),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({required this.mode, required this.selected, required this.onTap, this.enabled = true});
  final GameMode mode;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? Colors.white : c.textPrimary;
    return Pressable(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled || selected ? 1 : 0.45,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? context.accent : c.card,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: selected ? context.accent : c.stroke),
          ),
          child: Column(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CustomPaint(
                  painter: _ModePreview(mode: mode, color: selected ? Colors.white : context.accent),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                mode.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: fg),
              ),
              const SizedBox(height: 2),
              Text('x${_DifficultyScreenState._fmtMult(mode.multiplier)}', style: TextStyle(fontSize: 11, color: selected ? Colors.white.withValues(alpha: 0.85) : c.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small outline drawing of a tiling for the mode tiles.
class _ModePreview extends CustomPainter {
  _ModePreview({required this.mode, required this.color});
  final GameMode mode;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round;
    final (cols, rows) = switch (mode) {
      GameMode.cards => (2, 3),
      GameMode.squares => (3, 3),
      GameMode.triangles => (5, 2),
      GameMode.hexagons => (3, 3),
    };
    final tiling = Tiling.of(mode, cols, rows);
    final box = mode == GameMode.cards ? Rect.fromLTWH(6, 0, size.width - 12, size.height) : Offset.zero & size;
    // Regular cells, centred in the icon box.
    final fitted = tiling.fit(box.size, box.width / box.height);
    final area = Rect.fromCenter(center: box.center, width: fitted.width, height: fitted.height);
    for (var s = 0; s < tiling.cells; s++) {
      final poly = tiling.polygon(s, area.size);
      final path = Path()..moveTo(poly.first.dx + area.left, poly.first.dy + area.top);
      for (final v in poly.skip(1)) {
        path.lineTo(v.dx + area.left, v.dy + area.top);
      }
      path.close();
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_ModePreview old) => old.mode != mode || old.color != color;
}

/// One reward in the rewards row: a fixed-width, centred pill with either
/// an icon and a label or a ready-made [Amount].
class _RewardChip extends StatelessWidget {
  const _RewardChip({required this.width, this.icon, this.label, this.child}) : assert(child != null || (icon != null && label != null));
  final double width;
  final IconData? icon;
  final String? label;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: width,
      height: 36,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: c.canvas,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: c.stroke),
      ),
      // Scales down rather than overflowing when the chip is at its minimum.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: child ??
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: c.textSecondary),
                const SizedBox(width: 4),
                Text(label!, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
      ),
    );
  }
}

/// Draws the selected tiling's cell outlines over the preview, laid out the
/// way the board will be for a picture of [imageAspect] (same fit and
/// centre crop as the game, see [Tiling.fit] and [Tiling.crop]).
class _CutOverlay extends CustomPainter {
  _CutOverlay({required this.spec, required this.imageAspect, required this.color});
  final BoardSpec spec;
  final double imageAspect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final tiling = spec.tiling;
    // The frame already has the board's aspect, so this fills it; should the
    // two ever differ, the tiling is still centred in the board's proportions.
    final fitted = tiling.fit(size, imageAspect);
    final origin = Offset((size.width - fitted.width) / 2, (size.height - fitted.height) / 2);
    // Only the cuts inside the picture: edges on the board's outline are left
    // to the frame's own rounded border, which a square outline would cross
    // at the corners.
    const eps = 0.5;
    bool onOutline(Offset a, Offset b) =>
        (a.dx.abs() < eps && b.dx.abs() < eps) ||
        ((a.dx - fitted.width).abs() < eps && (b.dx - fitted.width).abs() < eps) ||
        (a.dy.abs() < eps && b.dy.abs() < eps) ||
        ((a.dy - fitted.height).abs() < eps && (b.dy - fitted.height).abs() < eps);
    final path = Path();
    for (var s = 0; s < tiling.cells; s++) {
      final poly = tiling.polygon(s, fitted);
      for (var i = 0; i < poly.length; i++) {
        final a = poly[i], b = poly[(i + 1) % poly.length];
        if (onOutline(a, b)) continue;
        path
          ..moveTo(a.dx + origin.dx, a.dy + origin.dy)
          ..lineTo(b.dx + origin.dx, b.dy + origin.dy);
      }
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_CutOverlay old) => old.spec != spec || old.imageAspect != imageAspect || old.color != color;
}
