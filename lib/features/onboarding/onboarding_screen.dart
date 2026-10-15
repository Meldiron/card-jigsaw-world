import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/appwrite.dart';
import '../../core/theme/tokens.dart';
import '../../game/board.dart';
import '../../game/game_controller.dart';
import '../../game/image_loader.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/settings.dart';
import '../../widgets/ui.dart';
import '../game/board_widget.dart';

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
      title: 'A new picture daily',
      body: 'Play the daily puzzle to keep your streak. Earn Coins and Tickets to open more packs and events.',
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
    final safeTop = MediaQuery.paddingOf(context).top;
    // Room under the art for the longest title and text, so every page puts
    // its title on the same line.
    final textBlock = MediaQuery.textScalerOf(context).scale(196);

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
                  0 => const _CardFan(urls: _Cover.firstFan),
                  1 => _DemoBoard(puzzle: ref.watch(dailyPuzzleProvider), fallback: _Cover.firstFan[1]),
                  _ => const _CardFan(urls: _Cover.dailyFan),
                };
                return LayoutBuilder(
                  builder: (context, box) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The art starts below the status bar and takes what the
                    // text leaves: more on tall phones, never under the clock.
                    Padding(
                      padding: EdgeInsets.only(top: safeTop + 8),
                      child: SizedBox(
                      height: math.max(160, box.maxHeight - textBlock - safeTop - 8),
                      width: double.infinity,
                      // The fans fade into the page; the board is shown whole.
                      child: i == 1
                          ? art.animate(key: ValueKey('a$i')).fadeIn(duration: 400.ms)
                          : _FadeToCanvas(
                              child: art
                                  .animate(key: ValueKey('a$i'))
                                  .fadeIn(duration: 400.ms),
                            ),
                    ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                ),
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
                            color: i == _index ? context.accent : c.textTertiary.withValues(alpha: 0.45),
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
                  // "Start playing" already finishes on the last page; the
                  // space stays so the button does not move.
                  Visibility(
                    visible: !last,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: Pressable(
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
                stops: const [0, 0.72, 1],
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

/// Today's picture on a real 3x3 board that plays itself, drawn by the
/// game's own board renderer: a card is picked and locks into its corner,
/// two cards that belong together snap into a group away from their place,
/// the group moves as one and locks, and the picture completes. Then it
/// starts again. With Reduce Motion it holds one still frame (a locked
/// corner, a group and loose cards). Empty frames while the picture loads.
class _DemoBoard extends ConsumerStatefulWidget {
  const _DemoBoard({required this.puzzle, required this.fallback});
  final Puzzle? puzzle;

  /// The picture when today's is not known yet (the catalogue has not arrived).
  final _Cover fallback;

  @override
  ConsumerState<_DemoBoard> createState() => _DemoBoardState();
}

/// One step of the demo: the layout, the picked slot, the slots that just
/// locked or joined (they pulse, as in the game) and how long it stays.
typedef _DemoFrame = ({List<int> slots, int? selected, Set<int> locked, Set<int> joined, int ms});

class _DemoBoardState extends ConsumerState<_DemoBoard> {
  static const _spec = BoardSpec(GameMode.cards, 3, 3, 'Cozy');

  static const List<_DemoFrame> _frames = [
    (slots: [1, 3, 0, 5, 7, 2, 4, 8, 6], selected: null, locked: {}, joined: {}, ms: 1400),
    (slots: [1, 3, 0, 5, 7, 2, 4, 8, 6], selected: 2, locked: {}, joined: {}, ms: 700),
    (slots: [0, 3, 1, 5, 7, 2, 4, 8, 6], selected: null, locked: {0}, joined: {}, ms: 1300),
    (slots: [0, 3, 1, 5, 7, 2, 4, 8, 6], selected: 3, locked: {}, joined: {}, ms: 700),
    (slots: [0, 3, 1, 8, 7, 2, 4, 5, 6], selected: null, locked: {}, joined: {6, 7}, ms: 1400),
    (slots: [0, 3, 1, 8, 7, 2, 4, 5, 6], selected: 6, locked: {}, joined: {}, ms: 700),
    (slots: [0, 3, 1, 8, 4, 5, 7, 2, 6], selected: null, locked: {4, 5}, joined: {}, ms: 1400),
    (slots: [0, 1, 2, 3, 4, 5, 6, 7, 8], selected: null, locked: {1, 2, 3, 6, 7, 8}, joined: {}, ms: 2200),
  ];

  /// The still frame for Reduce Motion: a locked corner, a group, loose cards.
  static const _still = [0, 1, 7, 8, 3, 6, 4, 5, 2];

  Timer? _timer;
  int _i = 0;
  int _tick = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: _frames[_i].ms), () {
      if (!mounted) return;
      setState(() {
        _i = (_i + 1) % _frames.length;
        _tick++;
      });
      _schedule();
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = ref.watch(puzzleImageProvider(widget.puzzle?.imageUrl ?? widget.fallback.url));
    final style = ref.watch(settingsProvider).cardStyle;
    final still = MediaQuery.disableAnimationsOf(context);
    return image.when(
      loading: () => const _SnapBoard(url: null),
      error: (_, _) => const _SnapBoard(url: null),
      data: (img) {
        if (!still && _timer == null) _schedule();
        final f = _frames[_i];
        final board = Board(_spec, still ? _still : f.slots);
        return LayoutBuilder(
          builder: (_, box) {
            // The art box already starts below the status bar.
            final size = board.tiling.fit(Size(box.maxWidth - 64, box.maxHeight - 16), img.width / img.height);
            return SizedBox.expand(
              child: Center(
                child: IgnorePointer(
                  child: BoardWidget(
                    image: img,
                    state: GameState(
                      board: board,
                      par: board.par,
                      moves: 0,
                      elapsed: 0,
                      status: GameStatus.playing,
                      selected: still ? null : f.selected,
                      hintsUsed: 0,
                      history: const [],
                      justLocked: still ? const {} : f.locked,
                      justJoined: still ? const {} : f.joined,
                      hintSlot: null,
                      hintTarget: null,
                      peeking: false,
                      chain: 0,
                      tick: _tick,
                    ),
                    width: size.width,
                    height: size.height,
                    cardStyle: style,
                    onTap: (_) {},
                    onDrop: (_, _) {},
                  ),
                ),
              ),
            );
          },
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

/// A picture for the welcome art, with its BlurHash.
class _Cover {
  const _Cover(this.url, this.hash);
  final String url;
  final String? hash;

  /// The fans show fixed catalogue pictures (public domain or CC0) by their
  /// Storage address, so they start loading with the first frame instead of
  /// after the whole catalogue; their BlurHash is in the code, so before they
  /// arrive (or offline) each card shows the picture's own blurred colours.
  static const _welcome = '${AppwriteConfig.endpoint}/storage/buckets/${AppwriteConfig.puzzleImagesBucket}/files/';
  static const _preview = '/preview?project=${AppwriteConfig.projectId}&width=600&quality=80';
  static const firstFan = [
    _Cover('${_welcome}p54a4497d62d08bc01e8a352e433a708d807$_preview', r'LrAxQ7s.s.ozt:WEWBbItnWBflay'), // Island Lake, Wind River Range
    _Cover('${_welcome}pa104c6e3ba15d91d5d3fc5caa6ee4648275$_preview', r'LDBzUCRiEK-p_LXgO8tRy9kBM|WB'), // Red panda sleeping
    _Cover('${_welcome}pf0c1b7e37f239d5146a21057a16f9b300a5$_preview', r'LPIhpwtRWUxCp3aLs.WZ16n$RPJ8'), // Tulip Fields 11
    _Cover('${_welcome}pf92be72d8070bec472ee35c02385ba7b98f$_preview', r'LYCZCbofM{j]_4ofV@oftmj[kCof'), // Amsterdam canal at night II
    _Cover('${_welcome}p0f7c012505dbc3ae77d2f3e8dd309e925a8$_preview', r'LbF?9O0M$dxuXpxaSPjEA1-oNLbc'), // Gozo Azure Window
    _Cover('${_welcome}pcc1f6f614dfb408abbc73f091ba705083c7$_preview', r'LDK8w~;3.n~AH[NaTKxtVu-U5n9a'), // Lower Antelope Canyon II
    _Cover('${_welcome}p06fa00b7deb557c600ef49a8206fbb64db4$_preview', r'LGGIr-9G01W9RNIAWFIWxuM{_MIV'), // Emperor penguin
  ];
  static const dailyFan = [
    _Cover('${_welcome}p52bce655e7fccbdb787e7132db54f71c494$_preview', r'LDFEZj+b0y$*tR^Q$kM|ELfi$*R*'), // Cherry blossom
    _Cover('${_welcome}p804cf353e052e92de7b62ba814bb617231c$_preview', r'LKHLVd4mF4tR?dxuogWBE1xwi^jY'), // Meerkat standing
    _Cover('${_welcome}p70c5579a18b51c0d1ba235bd66167a17881$_preview', r'LSI56^_2E4Io0kbckDjZI^ITWCjY'), // Parthenon Athens
    _Cover('${_welcome}pa408454dd415d8fdbfd7ebee076b83d4e7f$_preview', r'L8Ef$I.41GyV^#M}Rj+~DSO8Romv'), // World Mental Health Day 14
    _Cover('${_welcome}p4a23582e9623db6bd22a04d8eb94a840451$_preview', r'LbDSkL%3NKWBg8j]j]j@0KRixZof'), // Tropical Beaches 3
    _Cover('${_welcome}pdcd02f809619f29b7f4f34e391f1e3f5468$_preview', r'LGKJ*trEE8W=~Vs:IooM=|oIIobH'), // California rolls
    _Cover('${_welcome}p97439f5883f26b393d6c309aea1eb7f99ea$_preview', r'LNEfE3,,8^gO%iMcaItl?cn3aJx]'), // Upper Ammonoosuc Falls
  ];
}
