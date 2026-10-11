import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/settings.dart';
import '../../widgets/ui.dart';

/// Three-slide welcome. The top half shows real pack pictures so the game
/// sells itself; players start as guests and can link an account later.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;

  static const _slides = [
    (
      title: 'Pictures made of cards',
      body: 'Every puzzle is a photo cut into cards and shuffled. Tap a card, then tap where it belongs, or drag it there.',
    ),
    (
      title: 'Snap, group, lock',
      body: 'Cards that belong together snap into a group anywhere on the board. A card in its true spot locks into the picture.',
    ),
    (
      title: 'A new picture every day',
      body: 'Keep a daily streak, earn coins and tickets, and open packs, monthly albums and limited-time events.',
    ),
  ];

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _finish() {
    ref.read(settingsProvider.notifier).setOnboarded();
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final last = _index == _slides.length - 1;
    final packs = ref.watch(packsProvider).value ?? const <Pack>[];
    final covers = packs.where((p) => !p.isDaily && p.coverUrl.isNotEmpty).map((p) => _Cover(p.coverUrl, p.blurhash)).toList();
    final months = packs.where((p) => p.isDaily && p.coverUrl.isNotEmpty).map((p) => _Cover(p.coverUrl, p.blurhash)).toList();
    final artHeight = MediaQuery.sizeOf(context).height * 0.52;

    return Scaffold(
      backgroundColor: c.canvas,
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _page,
              itemCount: _slides.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) {
                final s = _slides[i];
                final Widget art = switch (i) {
                  0 => _CardFan(urls: covers.take(7).toList()),
                  1 => _SnapBoard(
                    url: covers.isEmpty
                        ? null
                        : covers[math.min(1, covers.length - 1)],
                  ),
                  _ => _CardFan(
                    urls: [...months.take(4), ...covers.skip(7).take(3)],
                  ),
                };
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: artHeight,
                      width: double.infinity,
                      child: _FadeToCanvas(
                        child: art
                            .animate(key: ValueKey('a$i'))
                            .fadeIn(duration: 400.ms),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                                  s.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .displaySmall,
                                )
                                .animate(key: ValueKey('t$i'))
                                .fadeIn(delay: 80.ms, duration: 350.ms)
                                .slideY(begin: 0.08, curve: Curves.easeOut),
                            const SizedBox(height: 12),
                            Text(
                                  s.body,
                                  style: TextStyle(
                                    fontSize: 16,
                                    height: 1.45,
                                    color: c.textSecondary,
                                  ),
                                )
                                .animate(key: ValueKey('b$i'))
                                .fadeIn(delay: 160.ms, duration: 350.ms)
                                .slideY(begin: 0.08, curve: Curves.easeOut),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _slides.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _index ? 20 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _index ? context.accent : c.stroke,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  BigButton(
                    label: last ? 'Start playing' : 'Continue',
                    icon: last ? CupertinoIcons.play_fill : null,
                    onTap: () {
                      if (last) {
                        _finish();
                      } else {
                        _page.nextPage(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Pressable(
                    onTap: _finish,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades the bottom of the artwork into the canvas colour.
class _FadeToCanvas extends StatelessWidget {
  const _FadeToCanvas({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final canvas = context.colors.canvas;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.55, 1],
                colors: [
                  canvas.withValues(alpha: 0),
                  canvas.withValues(alpha: 0),
                  canvas,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A fan of overlapping, slightly rotated picture cards.
class _CardFan extends StatelessWidget {
  const _CardFan({required this.urls});
  final List<_Cover> urls;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = urls.isEmpty
        ? List<_Cover?>.filled(7, null)
        : List<_Cover?>.from(urls);
    // Fixed layout: fraction of width/height, rotation in radians, card size.
    const layout = <(double, double, double, double)>[
      (0.08, 0.14, -0.22, 0.34),
      (0.36, 0.04, 0.08, 0.30),
      (0.64, 0.12, 0.20, 0.34),
      (0.02, 0.50, 0.12, 0.30),
      (0.30, 0.42, -0.06, 0.38),
      (0.66, 0.50, -0.16, 0.32),
      (0.42, 0.74, 0.14, 0.28),
    ];
    return LayoutBuilder(
      builder: (_, box) {
        final w = box.maxWidth, h = box.maxHeight;
        return Stack(
          children: [
            for (var i = 0; i < math.min(items.length, layout.length); i++)
              Positioned(
                left: w * layout[i].$1,
                top: h * layout[i].$2,
                child: Transform.rotate(
                  angle: layout[i].$3,
                  child: Container(
                    width: w * layout[i].$4,
                    height: w * layout[i].$4 * 1.3,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: c.boardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.card, width: 3),
                    ),
                    child: items[i] == null ? null : NetImage(url: items[i]!.url, blurhash: items[i]!.hash),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One picture sliced into a 3x3 board, with two adjacent cards drawn as a
/// joined group and one card lifted out of place.
class _SnapBoard extends StatelessWidget {
  const _SnapBoard({required this.url});
  final _Cover? url;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (_, box) {
        final side = math.min(box.maxWidth - 88, box.maxHeight - 32);
        final cell = side / 3;
        const gap = 6.0;
        Widget tile(
          int idx, {
          bool joinedLeft = false,
          bool joinedRight = false,
          Offset shift = Offset.zero,
          bool lifted = false,
        }) {
          final col = idx % 3, row = idx ~/ 3;
          final radius = BorderRadius.only(
            topLeft: Radius.circular(joinedLeft ? 0 : 10),
            bottomLeft: Radius.circular(joinedLeft ? 0 : 10),
            topRight: Radius.circular(joinedRight ? 0 : 10),
            bottomRight: Radius.circular(joinedRight ? 0 : 10),
          );
          return Positioned(
            left: col * cell + (joinedLeft ? 0 : gap / 2) + shift.dx,
            top: row * cell + gap / 2 + shift.dy,
            width:
                cell -
                (joinedLeft ? gap / 2 : gap) +
                (joinedRight ? gap / 2 : 0),
            height: cell - gap,
            child: Transform.rotate(
              angle: lifted ? -0.06 : 0,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: c.boardBackground,
                  borderRadius: radius,
                  border: Border.all(
                    color: lifted ? context.accent : c.card,
                    width: lifted ? 2.5 : 2,
                  ),
                ),
                child: url == null
                    ? null
                    : ClipRect(
                        child: Align(
                          alignment: Alignment(
                            (col - 1).toDouble(),
                            (row - 1).toDouble(),
                          ),
                          widthFactor: 1 / 3,
                          heightFactor: 1 / 3,
                          child: SizedBox(
                            width: side,
                            height: side,
                            child: NetImage(url: url!.url, blurhash: url!.hash),
                          ),
                        ),
                      ),
              ),
            ),
          );
        }

        // Scramble: show a plausible mid-game board. Cards 3 and 4 are joined.
        return Center(
          child: Container(
            width: side + 16,
            height: side + 16,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.boardBackground,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                tile(0),
                tile(1),
                tile(2),
                tile(3, joinedRight: true),
                tile(4, joinedLeft: true),
                tile(5),
                tile(6),
                tile(7),
                tile(8, shift: const Offset(10, -18), lifted: true),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A pack cover with its BlurHash.
class _Cover {
  const _Cover(this.url, this.hash);
  final String url;
  final String? hash;
}
