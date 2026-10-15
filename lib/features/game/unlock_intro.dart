import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/theme/tokens.dart';
import '../../game/modes.dart';
import '../../game/tiling.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/giant.dart';
import '../../state/profile.dart';
import '../../state/rewards.dart';
import '../../state/unlocks.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// Title of an unlock's intro ("Squares are open").
String unlockTitle(Unlock u) => switch (u) {
      Unlock.painting => 'Painting is open',
      _ => '${u.label} are open',
    };

/// "15% more coins and XP" for a reward multiplier of 1.15.
String _more(double multiplier) => '${((multiplier - 1) * 100).round()}% more coins and XP';

/// What the unlock is, for a player who does not have it yet.
String unlockWhat(Unlock u) => switch (u) {
      Unlock.squares => 'Pictures cut into even squares instead of cards. Squares pay ${_more(GameMode.squares.multiplier)}.',
      Unlock.triangles => 'Up and down triangles that fit together in rows. They pay ${_more(GameMode.triangles.multiplier)}.',
      Unlock.hexagons => 'A honeycomb of six-sided cells, the trickiest shape. Hexagons pay ${_more(GameMode.hexagons.multiplier)}.',
      Unlock.painting => 'Cards start in black and white and get their colour back as they lock. Works with every shape and pays ${_more(Economy.paintingMultiplier)}.',
      Unlock.giant => 'Boards of 100 to 300 cards for the pictures of the Giant pack, with pinch to zoom.',
    };

/// One calm sentence on what just opened; the reward is shown apart
/// ([unlockBonus]).
String unlockBody(Unlock u) => switch (u) {
      Unlock.squares => 'Pictures can now be cut into even squares.',
      Unlock.triangles => 'Up and down triangles that fit together in rows.',
      Unlock.hexagons => 'A honeycomb of six-sided cells, the trickiest shape.',
      Unlock.painting => 'Cards start in black and white and get their colour back as they lock. Works with every shape.',
      Unlock.giant => 'Boards of 100 to 300 cards for the pictures of the Giant pack. Pinch to zoom in while you play.',
    };

/// The extra reward an unlock pays, or null (giant boards pay by size).
String? unlockBonus(Unlock u) => switch (u) {
      Unlock.squares => _more(GameMode.squares.multiplier),
      Unlock.triangles => _more(GameMode.triangles.multiplier),
      Unlock.hexagons => _more(GameMode.hexagons.multiplier),
      Unlock.painting => _more(Economy.paintingMultiplier),
      Unlock.giant => null,
    };

/// The one-screen intro shown the first time a shape, Painting or giant
/// boards open: what it is, a small picture of it, "Try it" and "Later".
/// [onTryHere] replaces the default "Try it" (a fresh picture with it
/// preselected, or the Giant pack) when the player is already choosing a
/// board. Marks the intro seen.
Future<void> showUnlockIntro(BuildContext context, WidgetRef ref, Unlock u, {VoidCallback? onTryHere}) async {
  ref.read(unlockIntrosProvider.notifier).markSeen(u);
  final art = _artPicture(ref);
  final tryIt = await showAppSheet<bool>(
    context,
    builder: (ctx) => Padding(
      key: ValueKey('unlock-intro-${u.name}'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.lg),
            child: SizedBox(height: 168, width: 168 * 0.78, child: UnlockArt(unlock: u, picture: art)),
          ),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: SheetHeader(title: unlockTitle(u), subtitle: unlockBody(u), center: true)),
          if (unlockBonus(u) case final bonus?) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: ctx.colors.accentTint, borderRadius: BorderRadius.circular(Radii.pill)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CoinIcon(size: 16),
                  const SizedBox(width: 4),
                  Icon(AppIcons.xp, size: 16, color: ctx.accent),
                  const SizedBox(width: 8),
                  Text(bonus[0].toUpperCase() + bonus.substring(1), style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: ctx.accent)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          BigButton(key: const ValueKey('unlock-try'), label: 'Try it', icon: AppIcons.playFill, onTap: () => Navigator.pop(ctx, true)),
          const SizedBox(height: 4),
          // The way out is a plain text button, as on iOS sheets; an outlined
          // box on glass read as an empty field.
          Pressable(
            onTap: () => Navigator.pop(ctx, false),
            child: SizedBox(
              height: 44,
              width: double.infinity,
              child: Center(child: Text('Later', style: TextStyle(fontSize: TypeSize.callout, fontWeight: FontWeight.w600, color: ctx.colors.textSecondary))),
            ),
          ),
        ],
      ),
    ),
  );
  if (tryIt != true || !context.mounted) return;
  Haptics.light();
  if (onTryHere != null) {
    onTryHere();
    return;
  }
  if (u == Unlock.giant) {
    final packs = ref.read(packsProvider).value ?? const <Pack>[];
    for (final p in packs) {
      if (isGiantPack(p)) {
        context.push('/library/pack/${p.id}');
        return;
      }
    }
    return;
  }
  final puzzle = pickRandomPlayable(ref);
  if (puzzle == null) return;
  context.push(u == Unlock.painting ? '/play/${puzzle.id}?painting=1' : '/play/${puzzle.id}?mode=${u.mode!.code}');
}

/// Explains a locked shape, Painting or giant boards: the level it opens at
/// and how far away that is.
Future<void> showLockedInfo(BuildContext context, WidgetRef ref, Unlock u) async {
  final xp = ref.read(profileProvider).value?.xp ?? 0;
  final goal = LevelRewards.xpToReach(u.level);
  final left = math.max(0, goal - xp);
  final what = u == Unlock.painting ? 'Painting opens' : '${u.label} open';
  final art = _artPicture(ref);
  // The same sheet as the intro that greets it once it opens, in black and
  // white with a lock, so the player recognises it later.
  await showAppSheet<void>(
    context,
    builder: (ctx) => Padding(
      key: ValueKey('locked-info-${u.name}'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.lg),
            child: SizedBox(
              height: 140,
              width: 140 * 0.78,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColorFiltered(colorFilter: const ColorFilter.matrix(UnlockArt._greyscale), child: UnlockArt(unlock: u, picture: art)),
                  ColoredBox(color: Colors.black.withValues(alpha: 0.18)),
                  Center(
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), shape: BoxShape.circle),
                      child: const Icon(AppIcons.lock, size: 20, color: Color(0xFF111118)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: SheetHeader(title: '$what at level ${u.level}', subtitle: unlockWhat(u), center: true)),
          const SizedBox(height: 18),
          _LevelDistance(level: LevelRewards.levelForXp(xp), progress: goal == 0 ? 1 : xp / goal, left: left),
          const SizedBox(height: 20),
          BigButton(label: 'Got it', kind: ButtonKind.secondary, onTap: () => Navigator.pop(ctx)),
        ],
      ),
    ),
  );
}

/// "Level 5 ... 220 XP to go" over a bar: the way to the level a feature opens at.
class _LevelDistance extends StatelessWidget {
  const _LevelDistance({required this.level, required this.progress, required this.left});
  final int level;
  final double progress;
  final int left;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textSecondary);
    return Column(
      children: [
        ProgressBar(value: progress, height: 6),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Level $level', style: small),
            const Spacer(),
            Text('${formatCount(left)} XP to go', style: small),
          ],
        ),
      ],
    );
  }
}

/// A picture for the intro art: today's daily picture, else any.
Puzzle? _artPicture(WidgetRef ref) {
  final daily = ref.read(dailyPuzzleProvider);
  if (daily != null) return daily;
  final all = ref.read(allPuzzlesProvider).value ?? const <Puzzle>[];
  return all.isEmpty ? null : all.first;
}

/// The intro's small picture: a real picture cut the way the unlock cuts it
/// (squares, triangles, hexagons, a dense giant grid) or half in black and
/// white for Painting.
class UnlockArt extends StatelessWidget {
  const UnlockArt({super.key, required this.unlock, required this.picture});
  final Unlock unlock;
  final Puzzle? picture;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final image = picture == null
        ? Container(color: c.accentTint)
        : NetImage(url: picture!.thumbUrl.isEmpty ? picture!.imageUrl : picture!.thumbUrl, blurhash: picture!.blurhash);
    final (mode, cols, rows) = switch (unlock) {
      Unlock.squares => (GameMode.squares, 3, 4),
      Unlock.triangles => (GameMode.triangles, 4, 4),
      Unlock.hexagons => (GameMode.hexagons, 3, 4),
      Unlock.painting => (GameMode.cards, 3, 3),
      Unlock.giant => (GameMode.cards, 10, 13),
    };
    final tiling = Tiling.of(mode, cols, rows);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (unlock == Unlock.painting) ...[
          ColorFiltered(colorFilter: const ColorFilter.matrix(_greyscale), child: image),
          // The locked cards have their colour back.
          ClipPath(clipper: _CellsClipper(tiling, const {0, 4, 5, 8}), child: image),
        ] else
          image,
        CustomPaint(painter: _CutsPainter(tiling, Colors.white.withValues(alpha: unlock == Unlock.giant ? 0.55 : 0.8), unlock == Unlock.giant ? 0.8 : 1.6)),
      ],
    );
  }

  static const _greyscale = <double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

class _CellsClipper extends CustomClipper<Path> {
  _CellsClipper(this.tiling, this.cells);
  final Tiling tiling;
  final Set<int> cells;

  @override
  Path getClip(Size size) {
    final path = Path();
    for (final s in cells) {
      final poly = tiling.polygon(s, size);
      path.addPolygon(poly, true);
    }
    return path;
  }

  @override
  bool shouldReclip(_CellsClipper old) => old.tiling != tiling || old.cells != cells;
}

/// The tiling's cell outlines over the whole box.
class _CutsPainter extends CustomPainter {
  _CutsPainter(this.tiling, this.color, this.width);
  final Tiling tiling;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round;
    for (var s = 0; s < tiling.cells; s++) {
      canvas.drawPath(Path()..addPolygon(tiling.polygon(s, size), true), p);
    }
  }

  @override
  bool shouldRepaint(_CutsPainter old) => old.tiling != tiling || old.color != color || old.width != width;
}

/// Shows pending unlock intros where it sits: one at a time, only while the
/// app's top location is [at] (Home, or the mode and board screen), so a sheet
/// never opens over a game or from an offstage tab. Checks again whenever
/// the location changes.
class UnlockIntroHost extends ConsumerStatefulWidget {
  const UnlockIntroHost({super.key, required this.at, this.onTryHere});

  /// Whether the top location's path is this host's screen.
  final bool Function(String path) at;

  /// "Try it" on this screen (the mode and board screen preselects it).
  final void Function(Unlock u)? onTryHere;

  @override
  ConsumerState<UnlockIntroHost> createState() => _UnlockIntroHostState();
}

class _UnlockIntroHostState extends ConsumerState<UnlockIntroHost> {
  bool _showing = false;
  GoRouter? _router;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.maybeOf(context);
    if (router != _router) {
      _router?.routerDelegate.removeListener(_schedule);
      _router = router?..routerDelegate.addListener(_schedule);
    }
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_schedule);
    super.dispose();
  }

  void _schedule() => WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());

  void _maybeShow() {
    if (_showing || !mounted) return;
    final u = ref.read(pendingUnlockIntroProvider);
    if (u == null) return;
    // The top-most route, pushes included (the configuration's own uri stays on the tab below).
    final router = _router;
    final path = router == null || router.routerDelegate.currentConfiguration.isEmpty ? null : router.state.uri.path;
    if (path == null || !widget.at(path)) return;
    _showing = true;
    final onTryHere = widget.onTryHere;
    showUnlockIntro(context, ref, u, onTryHere: onTryHere == null ? null : () => onTryHere(u)).whenComplete(() {
      if (mounted) setState(() => _showing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(pendingUnlockIntroProvider);
    _schedule();
    return const SizedBox.shrink();
  }
}
