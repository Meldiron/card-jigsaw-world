import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../game/board.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/rewards.dart';
import '../../state/settings.dart';
import '../../state/social.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// Pre-game screen: preview with the cut overlay, mode picker, board picker
/// with reward preview, play button. This is the only place the cut preview
/// lives.
class DifficultyScreen extends ConsumerStatefulWidget {
  const DifficultyScreen({super.key, required this.puzzleId, this.initialGrid, this.initialMode});
  final String puzzleId;

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
  late BoardSpec _spec;

  @override
  void initState() {
    super.initState();
    final grid = widget.initialGrid;
    final hasGrid = grid != null && grid.isNotEmpty;
    final decoded = hasGrid ? BoardSpec.fromCode(grid) : null;
    final modeArg = widget.initialMode;
    _mode = modeArg != null && modeArg.isNotEmpty ? GameMode.fromCode(modeArg) : (decoded?.mode ?? GameMode.cards);
    if (decoded != null && decoded.mode == _mode) {
      _spec = decoded.tierIndex >= 0 ? decoded : BoardSpec.fromCells(_mode, decoded.cells);
    } else if (decoded != null) {
      // A legacy grid like 5x5 with a different mode: pick the same ladder step.
      final idx = GridSpec.tiers.indexWhere((t) => t.cells == decoded.cells);
      _spec = BoardSpec.tiers(_mode)[idx < 0 ? 2 : idx];
    } else {
      final idx = GridSpec.tiers.indexWhere((t) => t.cells == ref.read(settingsProvider).defaultGrid);
      _spec = BoardSpec.tiers(_mode)[idx < 0 ? 2 : idx];
    }
  }

  void _pickMode(GameMode m) {
    if (m == _mode) return;
    Haptics.selection();
    final idx = _spec.tierIndex < 0 ? 2 : _spec.tierIndex;
    setState(() {
      _mode = m;
      _spec = BoardSpec.tiers(m)[idx];
    });
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
                      Text('${t.code} ${_mode.label.toLowerCase()} boards open at level $level. Unlock them early and keep the bigger rewards.',
                          style: TextStyle(color: ctx.colors.textSecondary, fontSize: 13.5, height: 1.35)),
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
                  setState(() => _spec = t);
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
    final coins = Economy.completionCoins(_spec.cells, 3, mode: _mode);
    final xp = Economy.completionXp(_spec.cells, 3, mode: _mode);
    final maxTier = LevelRewards.maxTierIndex(profile?.level ?? 1) + 1;
    final tiers = BoardSpec.tiers(_mode);

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
                          // Preview with the cut overlay of the chosen mode and tier.
                          ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.30),
                            child: AspectRatio(
                              aspectRatio: 3 / 4,
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
                                    CustomPaint(painter: _CutOverlay(spec: _spec, color: Colors.white.withValues(alpha: 0.7))),
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
                                              Text('Best: ${progress.bestMoves ?? progress.moves} moves', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
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
                                              child: Text(
                                                '${puzzle.author} · ${puzzle.source}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w500),
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
                          ).animate().fadeIn(duration: 250.ms),
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Choose a mode', style: Theme.of(context).textTheme.headlineSmall),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Every mode cuts the picture differently. Trickier shapes pay more.', style: TextStyle(color: c.textSecondary, fontSize: 13)),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              for (final m in GameMode.values) ...[
                                Expanded(child: _ModeTile(mode: m, selected: m == _mode, onTap: () => _pickMode(m))),
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
                            child: Text('Bigger boards pay more. Higher levels unlock larger boards, or unlock them now with coins.', style: TextStyle(color: c.textSecondary, fontSize: 13)),
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
                                final selected = t == _spec;
                                final locked = i >= maxTier && !profileN.hasTier(_mode, i);
                                final fg = selected ? Colors.white : (locked ? c.textTertiary : c.textPrimary);
                                return Pressable(
                                  onTap: locked
                                      ? () => _offerUnlock(i, t)
                                      : () {
                                          Haptics.selection();
                                          setState(() => _spec = t);
                                        },
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
                                        Icon(locked ? AppIcons.lock : AppIcons.tier(i), size: 22, color: selected ? Colors.white : (locked ? c.textTertiary : context.accent)),
                                        const SizedBox(height: 4),
                                        Text(t.code, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: fg)),
                                        Text(t.label, style: TextStyle(fontSize: 11, color: selected ? Colors.white.withValues(alpha: 0.85) : (locked ? c.textTertiary : c.textSecondary))),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          SoftCard(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Text('REWARDS', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5, letterSpacing: 0.8, color: c.textTertiary)),
                                const SizedBox(width: 8),
                                Chip2(label: 'x${_fmtMult(_mode.multiplier)}', color: c.accentTint, foreground: context.accent),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Wrap(
                                    alignment: WrapAlignment.end,
                                    spacing: 12,
                                    runSpacing: 6,
                                    children: [
                                      Amount(currency: Currency.coins, value: coins, prefix: 'up to ', size: 16, fontSize: 13.5, weight: FontWeight.w600),
                                      _Reward(icon: AppIcons.xp, value: '+$xp XP'),
                                      const _Reward(icon: AppIcons.piggy, value: '+${Economy.piggyPerPuzzle}'),
                                    ],
                                  ),
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
                    child: BigButton(
                      label: '${_spec.cells} ${_mode == GameMode.cards ? 'cards' : _mode.label.toLowerCase()} · Play',
                      icon: CupertinoIcons.play_fill,
                      onTap: () {
                        final idx = _spec.tierIndex < 0 ? 2 : _spec.tierIndex;
                        ref.read(settingsProvider.notifier).setDefaultGrid(GridSpec.tiers[idx].cells);
                        context.pushReplacement('/game/${widget.puzzleId}/${BoardCode.toPath(_spec.fullCode)}');
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  static String _fmtMult(double m) => m == m.roundToDouble() ? '${m.toInt()}.0' : m.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({required this.mode, required this.selected, required this.onTap});
  final GameMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? Colors.white : c.textPrimary;
    return Pressable(
      onTap: onTap,
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
              child: CustomPaint(painter: _ModePreview(mode: mode, color: selected ? Colors.white : context.accent)),
            ),
            const SizedBox(height: 6),
            Text(mode.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: fg)),
            const SizedBox(height: 2),
            Text('x${_DifficultyScreenState._fmtMult(mode.multiplier)}', style: TextStyle(fontSize: 11, color: selected ? Colors.white.withValues(alpha: 0.85) : c.textSecondary)),
          ],
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

class _Reward extends StatelessWidget {
  const _Reward({required this.icon, required this.value});
  final IconData icon;
  final String value;
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: context.colors.textSecondary),
          const SizedBox(width: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        ],
      );
}

/// Draws the selected tiling's cell outlines over the preview.
class _CutOverlay extends CustomPainter {
  _CutOverlay({required this.spec, required this.color});
  final BoardSpec spec;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final tiling = spec.tiling;
    // Same proportions as the real board, centred over the preview: regular
    // hexagons and triangles, grids following the picture within limits.
    final fitted = tiling.fit(size, size.width / size.height);
    final origin = Offset((size.width - fitted.width) / 2, (size.height - fitted.height) / 2);
    for (var s = 0; s < tiling.cells; s++) {
      final poly = tiling.polygon(s, fitted);
      final path = Path()..moveTo(poly.first.dx + origin.dx, poly.first.dy + origin.dy);
      for (final v in poly.skip(1)) {
        path.lineTo(v.dx + origin.dx, v.dy + origin.dy);
      }
      path.close();
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_CutOverlay old) => old.spec != spec || old.color != color;
}
