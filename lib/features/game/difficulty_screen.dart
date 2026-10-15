import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../game/board.dart';
import '../../game/game_controller.dart' show formatDuration;
import '../../game/image_loader.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/giant.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/quick_play.dart';
import '../../state/rewards.dart';
import '../../state/settings.dart';
import '../../state/social.dart';
import '../../state/unlocks.dart';
import '../../widgets/cached_url_image.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import 'unlock_intro.dart';

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
  const DifficultyScreen({super.key, required this.puzzleId, this.initialGrid, this.initialMode, this.initialPainting = false, this.fromQuick = false});
  final String puzzleId;

  /// Opened by Quick play: "Another picture" draws a new one from the same pool.
  final bool fromQuick;

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

  /// The choices continue under the footer: it turns to glass with a
  /// hairline, like an iOS toolbar over a list that scrolls beneath it.
  bool _moreBelow = false;

  void _onMetrics(ScrollMetrics m) {
    if (m.axis != Axis.vertical) return;
    final more = m.extentAfter > 0.5;
    if (more != _moreBelow) setState(() => _moreBelow = more);
  }
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
    showToast(context, 'Progress discarded. Pick any mode or board.', icon: AppIcons.trash);
  }

  void _pickMode(GameMode m) {
    if (m == _mode) return;
    Haptics.selection();
    setState(() => _mode = m);
  }

  /// Quick play's "Another picture": a new picture from the same pool, on the
  /// same mode, size and Painting.
  void _anotherPicture(BoardSpec spec, bool painting) {
    final pool = ref.read(quickPlayPoolProvider);
    if (pool == null) return;
    final others = QuickPlayPool(pool.tier, [for (final z in pool.puzzles) if (z.id != widget.puzzleId) z]);
    final next = pickQuickPlay(others, _random);
    if (next == null) {
      showToast(context, 'No other picture to pick right now', icon: AppIcons.shuffle);
      return;
    }
    Haptics.light();
    final route = quickPlayRoute(next, saved: ref.read(puzzleProgressProvider(next.id)), board: spec.isGiant ? null : spec);
    context.pushReplacement(painting ? '$route&painting=1' : route);
  }

  static final _random = math.Random();

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
                const IconTile(icon: AppIcons.lock, size: IconTile.large),
                const SizedBox(width: 12),
                Expanded(
                  child: SheetHeader(
                    title: 'Unlock ${t.label} now',
                    subtitle: '${t.code} ${_mode.label.toLowerCase()} boards open at level $level. Unlock them early and keep the bigger rewards.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            BigButton(
              label: 'Unlock for',
              trailing: Amount(currency: Currency.coins, value: cost, size: 18, color: context.onAccent),
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
    // Shapes, Painting and giant boards open as levels rise (or stay open once used).
    final open = ref.watch(openFeaturesProvider);
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
    // A shape not open yet (a preselection from a quest, say) falls back to Cards.
    final mode = saved != null ? savedSpec!.mode : (open.mode(_mode) ? _mode : GameMode.cards);
    // Giant pack pictures wait for giant boards to open (the pack itself can be bought before).
    final giantLocked = giant && saved == null && !open.giant;
    final tiers = BoardSpec.ladder(mode, imageAspect, giant: giant);
    // A size picked on the other ladder (a normal tier carried to a Giant
    // pack picture, say) falls back to that ladder's first giant or Relaxed size.
    final pick = giant ? (BoardSpec.isGiantTier(_tier) ? _tier - BoardSpec.firstGiantTier : 0) : (BoardSpec.isGiantTier(_tier) ? 2 : _tier);
    final spec = saved != null ? savedSpec! : tiers[pick.clamp(0, tiers.length - 1)];
    final painting = saved != null ? saved.painting : (_painting && open.painting);
    final coins = Economy.completionCoins(spec.cells, 3, mode: mode, painting: painting);
    final xp = Economy.completionXp(spec.cells, 3, mode: mode, painting: painting);
    final maxTier = LevelRewards.maxTierIndex(profile?.level ?? 1) + 1;
    final boardAspect = spec.tiling.boardAspect(imageAspect);
    // Short phones (SE, mini): a smaller preview, so every choice sits above Play.
    final compact = MediaQuery.sizeOf(context).height < 740;

    final footer = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // What a 3-star solve pays, next to the button that starts it.
        if (!giantLocked) ...[
          _RewardsLine(coins: coins, xp: xp, piggy: Economy.piggyPerPuzzle),
          const SizedBox(height: 10),
        ],
        // Shows the first-time intro of a shape or option that just opened.
        UnlockIntroHost(
          at: (path) => path == '/play/${widget.puzzleId}',
          onTryHere: (u) => setState(() {
            if (u.mode != null) _mode = u.mode!;
            if (u == Unlock.painting) _painting = true;
          }),
        ),
        if (giantLocked)
          BigButton(
            key: const ValueKey('giant-locked'),
            label: 'Giant boards open at level ${Unlock.giant.level}',
            kind: ButtonKind.secondary,
            icon: AppIcons.lock,
            onTap: () => showLockedInfo(context, ref, Unlock.giant),
          )
        else
        BigButton(
          label: saved != null
              ? 'Continue · ${saved.moves} ${saved.moves == 1 ? 'move' : 'moves'} in'
              : '${spec.cells} ${mode == GameMode.cards ? 'cards' : mode.label.toLowerCase()} · Play',
          icon: AppIcons.playFill,
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
        if (saved != null) ...[const SizedBox(height: 8), BigButton(label: 'Discard progress', kind: ButtonKind.ghost, icon: AppIcons.trash, onTap: () => _discard(saved, spec))],
        if (widget.fromQuick) ...[
          const SizedBox(height: 4),
          BigButton(
            key: const ValueKey('another-picture'),
            label: 'Another picture',
            kind: ButtonKind.ghost,
            height: 40,
            icon: AppIcons.shuffle,
            onTap: () => _anotherPicture(spec, painting),
          ),
        ],
      ],
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      // The footer floats over the page and the choices scroll under it.
      extendBody: true,
      bottomNavigationBar: puzzle == null ? null : _GlassFooter(glass: _moreBelow, child: footer),
      appBar: GlassAppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: RoundIconButton(icon: AppIcons.back, size: 38, onTap: () => context.canPop() ? context.pop() : context.go('/home')),
        ),
        title: Text(puzzle?.title ?? 'Puzzle'),
      ),
      body: puzzle == null
          // A link to a picture that is gone (or someone else's photo) says so once the
          // catalogue and the player's own photos have answered.
          ? (ref.watch(allPuzzlesProvider).hasValue && ref.watch(myPuzzleByIdProvider(widget.puzzleId)).hasValue
              ? const EmptyState(
                  key: ValueKey('picture-not-available'),
                  icon: AppIcons.image,
                  title: 'Picture not available',
                  message: 'The link may be out of date, or the picture belongs to another player.',
                )
              : const Loader())
          : NotificationListener<ScrollMetricsNotification>(
              onNotification: (n) {
                if (n.depth == 0) _onMetrics(n.metrics);
                return false;
              },
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: (n) {
                  if (n.depth == 0) _onMetrics(n.metrics);
                  return false;
                },
                // The body's bottom padding is the footer's height.
                child: Builder(
                  builder: (context) => SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 4, 20, MediaQuery.paddingOf(context).bottom + 16),
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
                              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * (compact ? 0.24 : 0.32)),
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
                                        // A board in progress: the cards not in place yet are dimmed, so the
                                        // preview shows how far along it is.
                                        painter: _CutOverlay(
                                          spec: spec,
                                          imageAspect: imageAspect,
                                          color: Colors.white.withValues(alpha: 0.7),
                                          placed: saved?.layout == null ? null : {for (var i = 0; i < saved!.layout!.length; i++) if (saved.layout![i] == i) i},
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ).animate().fadeIn(duration: 120.ms),
                          const SizedBox(height: 6),
                          // A solved picture: its best result, above the credit.
                          if (progress?.completed == true) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Stars(count: progress!.stars, size: 13),
                                const SizedBox(width: 6),
                                Text(
                                  'Best ${countOf(progress.bestMoves ?? progress.moves, 'move')}',
                                  style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textSecondary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                          ],
                          // The credit the licence asks for, quietly under the picture.
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(AppIcons.credit, size: 12, color: c.textTertiary),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  '${puzzle.author} · ${puzzle.source}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: TypeSize.caption, color: c.textTertiary),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: compact ? 14 : 20),
                          // A board in progress: what it is and how far along, instead of
                          // pickers that cannot be used until it is discarded.
                          if (saved != null) ...[
                            _InProgressCard(spec: spec, saved: saved, painting: painting),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Continue where you left off, or discard it to pick another mode or size.',
                                style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote),
                              ),
                            ),
                          ] else ...[
                          const _SectionLabel('Mode'),
                          const SizedBox(height: 8),
                          _ModeSegments(
                            selected: mode,
                            frozen: saved != null,
                            isOpen: (m) => saved != null || open.mode(m),
                            onTap: (m) => saved == null && !open.mode(m) ? showLockedInfo(context, ref, Unlocks.ofMode(m)!) : _pickMode(m),
                          ),
                          SizedBox(height: compact ? 14 : 20),
                          const _SectionLabel('Board'),
                          if (giant) ...[
                            const SizedBox(height: 2),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                giantLocked
                                    ? 'Giant boards of 100 cards and more open at level ${Unlock.giant.level}. This pack is ready for you then.'
                                    : 'Giant boards of 100 cards and more, all open with this pack. Pinch to zoom in while you play.',
                                style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          // Runs to the screen edges, so the next size peeks in as a hint to scroll.
                          SizedBox(
                            // 167: the chips' two lines grow with Larger Text; so does the row.
                            height: MediaQuery.textScalerOf(context).scale(56),
                            child: OverflowBox(
                              maxWidth: MediaQuery.sizeOf(context).width,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                itemCount: tiers.length,
                                separatorBuilder: (_, _) => const SizedBox(width: 8),
                                itemBuilder: (_, i) {
                                  final t = tiers[i];
                                  final locked = giant ? giantLocked : i >= maxTier && !profileN.hasTier(mode, i);
                                  return _BoardChip(
                                    spec: t,
                                    selected: t == spec,
                                    locked: locked,
                                    frozen: saved != null,
                                    onTap: saved != null
                                        ? null
                                        : locked
                                        ? () => giant ? showLockedInfo(context, ref, Unlock.giant) : _offerUnlock(i, t)
                                        : () {
                                            Haptics.selection();
                                            setState(() => _tier = t.tier);
                                          },
                                  );
                                },
                              ),
                            ),
                          ),
                          SizedBox(height: compact ? 12 : 16),
                          _PaintingTile(
                            on: painting,
                            enabled: saved == null,
                            locked: saved == null && !open.painting,
                            onLocked: () => showLockedInfo(context, ref, Unlock.painting),
                            onChanged: (v) {
                              Haptics.selection();
                              setState(() => _painting = v);
                            },
                          ),
                          ],
                        ],
                      ),
                    ),
                ),
              ),
            ),
    );
  }

  static String _fmtMult(double m) => m == m.roundToDouble() ? '${m.toInt()}.0' : m.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}

/// The Painting option: works with every shape and size and pays
/// [Economy.paintingMultiplier] more. Frozen while a board is in progress.
class _PaintingTile extends StatelessWidget {
  const _PaintingTile({required this.on, required this.enabled, required this.onChanged, this.locked = false, this.onLocked});
  final bool on;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  /// Not open yet (level below [Unlock.painting]): a tap explains when it opens.
  final bool locked;
  final VoidCallback? onLocked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      key: const ValueKey('painting-option'),
      onTap: locked ? onLocked : (enabled ? () => onChanged(!on) : null),
      scale: 0.99,
      child: Opacity(
        // Locked is said by the lock and the level, not by fading the text.
        opacity: locked ? 1 : (enabled || on ? 1 : 0.45),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: on ? c.accentTint : c.card,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: on ? context.accent : c.stroke),
          ),
          child: Row(
            children: [
              const IconTile(icon: AppIcons.painting, size: IconTile.small),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Keyed while on: the bonus is part of the rewards in the footer.
                    Text('Painting · x${_DifficultyScreenState._fmtMult(Economy.paintingMultiplier)}', key: on ? const ValueKey('painting-bonus') : null, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.body)),
                    const SizedBox(height: 2),
                    Text(
                      locked ? 'Opens at level ${Unlock.painting.level}' : 'Colour returns as cards lock',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: TypeSize.footnote, height: 1.3, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (locked)
                Icon(AppIcons.lock, size: 18, color: c.textTertiary)
              else
                CupertinoSwitch(value: on, activeTrackColor: Brand.success, onChanged: enabled ? onChanged : null),
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

/// Draws the selected tiling's cell outlines over the preview, laid out the
/// way the board will be for a picture of [imageAspect] (same fit and
/// centre crop as the game, see [Tiling.fit] and [Tiling.crop]).
class _CutOverlay extends CustomPainter {
  _CutOverlay({required this.spec, required this.imageAspect, required this.color, this.placed});
  final BoardSpec spec;
  final double imageAspect;
  final Color color;

  /// Slots whose card is in place on a saved board; every other cell is dimmed.
  final Set<int>? placed;

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
    final placed = this.placed;
    if (placed != null) {
      final dim = Paint()..color = Colors.black.withValues(alpha: 0.55);
      for (var s = 0; s < tiling.cells; s++) {
        if (placed.contains(s)) continue;
        final poly = tiling.polygon(s, fitted);
        final cell = Path()..moveTo(poly.first.dx + origin.dx, poly.first.dy + origin.dy);
        for (final v in poly.skip(1)) {
          cell.lineTo(v.dx + origin.dx, v.dy + origin.dy);
        }
        canvas.drawPath(cell..close(), dim);
      }
    }
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
  bool shouldRepaint(_CutOverlay old) => old.spec != spec || old.imageAspect != imageAspect || old.color != color || !setEquals(old.placed, placed);
}

/// The Play footer: transparent over the canvas while the choices end above
/// it, glass with a hairline once they continue underneath.
class _GlassFooter extends StatelessWidget {
  const _GlassFooter({required this.glass, required this.child});
  final bool glass;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      visible: glass,
      hairline: Border(top: BorderSide(color: context.colors.stroke, width: 0.5)),
      child: SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 12), child: child),
      ),
    );
  }
}

/// Small section title, lighter than a page heading: the choices are the content.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Text(title, style: const TextStyle(fontSize: TypeSize.headline, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
      );
}

/// The four modes as one segmented control: a track with a raised segment
/// for the choice, each with its cut drawn small and its multiplier.
class _ModeSegments extends StatelessWidget {
  const _ModeSegments({required this.selected, required this.frozen, required this.isOpen, required this.onTap});
  final GameMode selected;

  /// A board is in progress: only its mode shows as chosen, the rest rest.
  final bool frozen;
  final bool Function(GameMode) isOpen;
  final ValueChanged<GameMode> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: context.isDark ? c.card : const Color(0xFFE9E9EE), borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(
        children: [
          for (final m in GameMode.values)
            Expanded(
              child: Pressable(
                key: ValueKey('mode-${m.code}'),
                onTap: frozen ? null : () => onTap(m),
                scale: 0.96,
                child: Opacity(
                  opacity: frozen && m != selected ? 0.4 : 1,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      // The raised segment is lighter than the track in both themes.
                      color: m == selected ? (context.isDark ? Color.lerp(c.cardElevated, Colors.white, 0.08) : c.card) : Colors.transparent,
                      borderRadius: BorderRadius.circular(Radii.md - 3),
                      boxShadow: m == selected ? [BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? 0.3 : 0.08), blurRadius: 6, offset: const Offset(0, 1))] : null,
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          width: 26,
                          height: 22,
                          child: isOpen(m)
                              ? CustomPaint(painter: _ModePreview(mode: m, color: m == selected ? context.accent : c.textSecondary))
                              : Icon(AppIcons.lock, size: 15, color: c.textTertiary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          m.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: TypeSize.footnote, fontWeight: m == selected ? FontWeight.w700 : FontWeight.w600, color: isOpen(m) ? c.textPrimary : c.textTertiary),
                        ),
                        Text(
                          isOpen(m) ? 'x${_DifficultyScreenState._fmtMult(m.multiplier)}' : 'Level ${Unlocks.ofMode(m)!.level}',
                          style: TextStyle(fontSize: TypeSize.micro, color: m == selected ? context.accent : c.textTertiary, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One board size: its cut ("5x4") over its name ("Relaxed"). Locked sizes
/// carry a small lock; a tap offers the unlock.
class _BoardChip extends StatelessWidget {
  const _BoardChip({required this.spec, required this.selected, required this.locked, required this.frozen, this.onTap});
  final BoardSpec spec;
  final bool selected;
  final bool locked;
  final bool frozen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? context.accent : (locked ? c.textTertiary : c.textPrimary);
    return Pressable(
      onTap: onTap,
      child: Opacity(
        opacity: frozen && !selected ? 0.4 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minWidth: 74),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? c.accentTint : c.card,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: selected ? context.accent : c.stroke, width: selected ? 1.5 : 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (locked) ...[Icon(AppIcons.lock, size: 11, color: fg), const SizedBox(width: 3)],
                  Text(spec.code, style: TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.body, letterSpacing: -0.2, color: fg)),
                ],
              ),
              Text(spec.label, style: TextStyle(fontSize: TypeSize.micro, color: selected ? context.accent : c.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Up to [coin] 40 · 80 XP · [piggy] +5": what a 3-star solve pays.
class _RewardsLine extends StatelessWidget {
  const _RewardsLine({required this.coins, required this.xp, required this.piggy});
  final int coins;
  final int xp;
  final int piggy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textSecondary);
    Widget dot() => Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('·', style: style));
    // Scales down rather than overflowing with big numbers or Larger Text.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('3 stars pay up to', style: style.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(width: 6),
        Amount(currency: Currency.coins, value: coins, size: 15, fontSize: TypeSize.footnote, weight: FontWeight.w700),
        dot(),
        Text('${formatCount(xp)} XP', style: style.copyWith(color: c.textPrimary, fontWeight: FontWeight.w700)),
        dot(),
        Icon(AppIcons.piggy, size: 14, color: c.textSecondary),
        const SizedBox(width: 3),
        Text('+$piggy', style: style.copyWith(color: c.textPrimary, fontWeight: FontWeight.w700)),
      ],
      ),
    );
  }
}

/// The board in progress for this picture: mode and size, how many cards
/// are in place, moves and time.
class _InProgressCard extends StatelessWidget {
  const _InProgressCard({required this.spec, required this.saved, required this.painting});
  final BoardSpec spec;
  final PuzzleProgress saved;
  final bool painting;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final layout = saved.layout ?? const <int>[];
    final placed = [for (var i = 0; i < layout.length; i++) if (layout[i] == i) i].length;
    final cells = spec.cells;
    return SoftCard(
      key: const ValueKey('board-in-progress'),
      padding: Insets.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: c.accentTint, borderRadius: BorderRadius.circular(Radii.md)),
                child: CustomPaint(painter: _ModePreview(mode: spec.mode, color: context.accent)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Board in progress', style: TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.callout)),
                    const SizedBox(height: 2),
                    Text(
                      '${spec.mode.label} · ${spec.code} ${spec.label}${painting ? ' · Painting' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ProgressBar(value: cells == 0 ? 0 : placed / cells, height: 6),
          const SizedBox(height: 8),
          Row(
            children: [
              Flexible(child: Text('$placed of $cells in place', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600))),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${saved.moves} ${saved.moves == 1 ? 'move' : 'moves'} · ${formatDuration(saved.elapsedSeconds)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
