import 'dart:async';
import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/profile.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// One slice of the Lucky Wheel: [amount] of [kind]. [weight] is its share
/// of the draw: the chance of a slice is its weight over the sum of all weights.
class WheelSegment {
  const WheelSegment(this.kind, this.amount, this.color, {this.weight = 1, this.jackpot = false});
  final Currency kind;
  final int amount;
  final Color color;
  final double weight;
  final bool jackpot;

  String get label => '$amount';

  /// What the prize is, after its icon and number ("2 Hints", "5 Peeks",
  /// "1 Magic"). Coins carry the coin mark only.
  String? get name => switch (kind) {
        Currency.coins => null,
        Currency.tickets => amount == 1 ? 'Ticket' : 'Tickets',
        Currency.hints => amount == 1 ? 'Hint' : 'Hints',
        Currency.peeks => amount == 1 ? 'Peek' : 'Peeks',
        Currency.magics => 'Magic',
      };

  /// The prize in coins, at what the same boosters cost in a game.
  int get coinValue => switch (kind) {
        Currency.coins => amount,
        Currency.tickets => 0,
        Currency.hints => amount * Economy.hintCostCoins,
        Currency.peeks => amount * Economy.peekCostCoins,
        Currency.magics => amount * Economy.magicLockCostCoins,
      };
}

/// Balance: a spin costs 1 Ticket. Since 2026-10-14 (owner) four coin slices
/// are boosters for the stock: 5 and 10 Peeks, 1 and 3 Magic, used in a game
/// before coins. Expected value per spin, boosters at their price in coins
/// (Peek 10, Hint 150, Magic 300):
///   coins    = (60·5 + 120·5 + 500·0.5) / 22 ≈ 52 coins
///   boosters = (5·10·4 + 2·150·2 + 10·10·3 + 300·2 + 900·0.5) / 22 ≈ 98 coins
///   together ≈ 150 coins (149 before, when the wheel paid mostly coins)
/// with a 2.3% chance (0.5/22) of the 500-Coin jackpot. Tickets are never a
/// reward, so the wheel cannot pay for itself. The odds sheet reads this same
/// table ([wheelOdds]), so what players are shown is what the spin draws.
const wheelSegments = [
  WheelSegment(Currency.coins, 60, Color(0xFFD97706), weight: 5),
  WheelSegment(Currency.peeks, 5, Color(0xFF64748B), weight: 4),
  WheelSegment(Currency.coins, 120, Color(0xFF0F9D8F), weight: 5),
  WheelSegment(Currency.hints, 2, Brand.accent, weight: 2),
  WheelSegment(Currency.peeks, 10, Color(0xFF475569), weight: 3),
  WheelSegment(Currency.magics, 1, Color(0xFFB45309), weight: 2),
  WheelSegment(Currency.coins, 500, Color(0xFF3730A3), weight: 0.5, jackpot: true),
  WheelSegment(Currency.magics, 3, Color(0xFF0B7A70), weight: 0.5),
];

const _segments = wheelSegments;

/// The slice a spin lands on for [r], a uniform random number in [0, 1).
int wheelPick(double r, [List<WheelSegment> segments = wheelSegments]) {
  final total = segments.fold<double>(0, (s, e) => s + e.weight);
  var left = r * total;
  for (var i = 0; i < segments.length; i++) {
    left -= segments[i].weight;
    if (left < 0) return i;
  }
  return segments.length - 1;
}

/// One prize on the odds sheet and its chance in percent (one decimal).
typedef WheelOdd = ({WheelSegment segment, double percent});

/// Every prize with its chance, smallest prize first. Percentages carry one
/// decimal and are rounded by largest remainder, so they add up to exactly 100.
List<WheelOdd> wheelOdds([List<WheelSegment> segments = wheelSegments]) {
  final total = segments.fold<double>(0, (s, e) => s + e.weight);
  final tenths = [for (final s in segments) s.weight / total * 1000];
  final floors = [for (final t in tenths) t.floor()];
  var missing = 1000 - floors.fold<int>(0, (a, b) => a + b);
  final order = List.generate(segments.length, (i) => i)..sort((a, b) => (tenths[b] - floors[b]).compareTo(tenths[a] - floors[a]));
  for (final i in order) {
    if (missing <= 0) break;
    floors[i]++;
    missing--;
  }
  final odds = [for (var i = 0; i < segments.length; i++) (segment: segments[i], percent: floors[i] / 10)];
  // Coins by amount, then hints, Peeks and Magic.
  odds.sort((a, b) => a.segment.kind != b.segment.kind ? a.segment.kind.index.compareTo(b.segment.kind.index) : a.segment.amount.compareTo(b.segment.amount));
  return odds;
}

/// "22.7%", "9.1%", "2.3%".
String formatOdds(double percent) => '${percent.toStringAsFixed(1)}%';

/// The odds sheet, opened from "See odds" on the wheel (App Review guideline
/// 3.1.1: the odds of a paid random reward are shown before spending).
Future<void> showWheelOdds(BuildContext context) => showAppSheet(
      context,
      builder: (ctx) {
        final c = ctx.colors;
        final odds = wheelOdds();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The shared sheet header (130): a table, so left-aligned.
              SizedBox(
                width: double.infinity,
                child: SheetHeader(
                  title: 'Lucky Wheel odds',
                  subtitle: 'Every spin costs ${Economy.wheelSpinTickets} ticket and pays one prize. Each spin is drawn on its own with these chances.',
                ),
              ),
              const SizedBox(height: 14),
              SoftCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < odds.length; i++) ...[
                      Padding(
                        key: ValueKey('wheel-odd-$i'),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                        child: Row(
                          children: [
                            // Mark, then the prize in words at one weight: "60 coins", "2 Hints".
                            currencyIcon(odds[i].segment.kind, size: 20),
                            const SizedBox(width: 10),
                            Text('${odds[i].segment.amount}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
                            const SizedBox(width: 4),
                            Text(odds[i].segment.name ?? 'coins', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            if (odds[i].segment.jackpot) ...[const SizedBox(width: 8), Chip2(label: 'Jackpot', color: Brand.coin.withValues(alpha: 0.16), foreground: ctx.isDark ? Brand.coin : Brand.coinDeep)],
                            const Spacer(),
                            Text(formatOdds(odds[i].percent), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, fontFeatures: [FontFeature.tabularFigures()])),
                          ],
                        ),
                      ),
                      if (i < odds.length - 1) Divider(height: 1, color: c.stroke, indent: 16),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

/// Lucky Wheel: every spin costs one Ticket.
class WheelScreen extends ConsumerStatefulWidget {
  const WheelScreen({super.key});
  @override
  ConsumerState<WheelScreen> createState() => _WheelScreenState();
}

class _WheelScreenState extends ConsumerState<WheelScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200));
  /// Jackpot burst from the wheel centre.
  late final ConfettiController _confetti = ConfettiController(duration: const Duration(milliseconds: 900));
  double _from = 0;
  double _to = 0;
  bool _spinning = false;
  WheelSegment? _result;
  int _lastTick = -1;
  int _spins = 0;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      final angle = _angle;
      final tick = (angle / (2 * math.pi / _segments.length)).floor();
      if (tick != _lastTick) {
        _lastTick = tick;
        Sfx.instance.spin();
        Haptics.selection();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _confetti.dispose();
    super.dispose();
  }

  double get _angle => _from + (_to - _from) * Curves.easeOutQuart.transform(_c.value);

  Future<void> _spin() async {
    if (_spinning) return;
    final n = ref.read(profileProvider.notifier);
    final ok = await n.spendTickets(Economy.wheelSpinTickets, reason: 'wheel');
    if (!ok) {
      if (mounted) showToast(context, 'You need 1 Ticket to spin.', leading: const TicketIcon(size: 18));
      return;
    }
    // Weighted pick, from the same table the odds sheet shows.
    final idx = wheelPick(math.Random().nextDouble());
    final seg = 2 * math.pi / _segments.length;
    // Pointer is at top (-pi/2). Segment i spans [i*seg, (i+1)*seg) starting at -pi/2 when rotation=0.
    final target = -(idx * seg + seg / 2) + (math.Random().nextDouble() - 0.5) * seg * 0.6;
    setState(() {
      _spinning = true;
      _result = null;
      _from = _angle % (2 * math.pi);
      _to = _from + 2 * math.pi * 6 + ((target - _from) % (2 * math.pi));
    });
    _c.forward(from: 0).whenComplete(() async {
      final won = _segments[idx];
      switch (won.kind) {
        case Currency.coins:
          await n.addCoins(won.amount, reason: 'wheel');
        case Currency.tickets:
          await n.addTickets(won.amount, reason: 'wheel');
        case Currency.hints:
          await n.addHints(won.amount, reason: 'wheel');
        case Currency.peeks:
          await n.addPeeks(won.amount, reason: 'wheel');
        case Currency.magics:
          await n.addMagics(won.amount, reason: 'wheel');
      }
      if (!mounted) return;
      Sfx.instance.win();
      if (won.jackpot) {
        Haptics.heavy();
        _confetti.play();
      } else {
        Haptics.success();
      }
      setState(() {
        _spinning = false;
        _result = won;
        _spins++;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final profile = ref.watch(profileProvider).value;
    final tickets = profile?.tickets ?? 0;
    final canSpin = tickets >= Economy.wheelSpinTickets && !_spinning;
    final jackpot = _result?.jackpot ?? false;
    return Scaffold(
      // The ticket balance sits in the bar, as in the Store, so the wheel gets the height.
      appBar: GlassAppBar(
        title: const Text('Lucky Wheel'),
        leading: Padding(padding: const EdgeInsets.only(left: 12), child: RoundIconButton(icon: CupertinoIcons.xmark, size: 38, onTap: () => context.pop())),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: CurrencyPill(currency: Currency.tickets, value: tickets, compact: true, onAdd: () => context.push('/store')),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (_, cons) {
                    // The wheel fits the space left in both directions: on an SE the result
                    // card and "Get tickets" take height the width-only size did not leave.
                    final size = math.max(160.0, math.min(math.min(cons.maxWidth - 48, cons.maxHeight - 32), 340.0));
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: size + 20,
                          height: size + 20,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: c.card, border: Border.all(color: c.stroke)),
                        ),
                        AnimatedBuilder(
                          animation: _c,
                          builder: (_, _) => _WheelFace(angle: _angle, size: size, photo: ref.watch(dailyPuzzleProvider)),
                        ),
                        // A plain cap on the axle: the old wheel glyph there read as a loading spinner.
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: c.cardElevated,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.stroke),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? 0.4 : 0.12), blurRadius: 8, offset: const Offset(0, 2))],
                          ),
                          child: Center(child: Container(width: 10, height: 10, decoration: BoxDecoration(color: context.accent, shape: BoxShape.circle))),
                        ),
                        if (jackpot)
                          // Glow pulse on the whole wheel when the jackpot lands.
                          IgnorePointer(
                            child: Container(
                              width: size + 20,
                              height: size + 20,
                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Brand.coin, width: 4)),
                            )
                                .animate(onPlay: (ctrl) => ctrl.repeat(count: 3))
                                .fadeIn(duration: 200.ms)
                                .scale(begin: const Offset(0.96, 0.96), end: const Offset(1.06, 1.06), duration: 600.ms, curve: Curves.easeOut)
                                .fadeOut(delay: 300.ms, duration: 300.ms),
                          ),
                        ConfettiWidget(
                          confettiController: _confetti,
                          blastDirectionality: BlastDirectionality.explosive,
                          emissionFrequency: 0.6,
                          numberOfParticles: 18,
                          maxBlastForce: 24,
                          minBlastForce: 8,
                          gravity: 0.25,
                          shouldLoop: false,
                          colors: [Brand.coin, Brand.coinDeep, context.accent, Colors.white],
                        ),
                        Positioned(
                          top: -4,
                          child: Transform.rotate(
                            angle: math.pi,
                            child: CustomPaint(size: const Size(28, 34), painter: _PointerPainter(color: context.accent, edge: c.card)),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            // One fixed slot under the wheel: the jackpot before a spin, the prize after it.
            // Its height never changes, so the wheel does not jump when a prize lands.
            SizedBox(
              height: 56,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOutBack,
                  transitionBuilder: (child, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(a), child: child)),
                  child: _result == null
                      ? Row(
                          key: const ValueKey('jackpot'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Jackpot', style: TextStyle(color: c.textSecondary, fontSize: 13.5, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 8),
                            Amount(currency: Currency.coins, value: _segments.firstWhere((s) => s.jackpot).amount, size: 16, fontSize: 14.5, weight: FontWeight.w700),
                          ],
                        )
                      : SoftCard(
                          key: ValueKey('won-${_result!.kind}-${_result!.amount}-$_spins'),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          radius: Radii.pill,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('You won', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                              const SizedBox(width: 10),
                              Amount(currency: _result!.kind, value: _result!.amount, size: 18, fontSize: 16, weight: FontWeight.w800),
                              if (_result!.name != null) ...[const SizedBox(width: 5), Text(_result!.name!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))],
                              if (jackpot) ...[const SizedBox(width: 8), const Chip2(label: 'Jackpot', color: Brand.coin, foreground: Color(0xFF2A1F00))],
                            ],
                          ),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                children: [
                  // Out of tickets: one clear way on instead of a disabled Spin above a second button.
                  if (tickets < Economy.wheelSpinTickets && !_spinning) ...[
                    BigButton(label: 'Get tickets', onTap: () => context.push('/store')),
                    const SizedBox(height: 8),
                    Text('A spin costs 1 ticket. Earn them from weekly quests, level-ups and events.', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 12.5, height: 1.35)),
                  ] else
                    BigButton.cost(
                      label: 'Spin for',
                      currency: Currency.tickets,
                      amount: Economy.wheelSpinTickets,
                      onTap: canSpin ? _spin : null,
                    ),
                  CupertinoButton(
                    key: const ValueKey('wheel-see-odds'),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    minimumSize: const Size(44, 32),
                    onPressed: () => showWheelOdds(context),
                    child: Text('See odds', style: TextStyle(color: context.accent, fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The wheel: slices painted by [_SlicePainter], prizes as the game's own marks
/// (coin, hint, Peek, Magic) laid on top. The slices turn with [angle]; each prize
/// moves with its slice but stays upright, so no amount is ever upside down.
class _WheelFace extends StatelessWidget {
  const _WheelFace({required this.angle, required this.size, this.photo});
  final double angle;
  final double size;
  final Puzzle? photo;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = size / 2;
    final seg = 2 * math.pi / _segments.length;
    final palette = _WheelPalette.of(context);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Transform.rotate(
            angle: angle,
            child: Stack(
              children: [
                // Colour from the photos: the slices are pieces of today's picture.
                ClipOval(
                  child: SizedBox.square(
                    dimension: size,
                    child: photo == null ? ColoredBox(color: c.boardBackground) : NetImage(url: photo!.thumbUrl, blurhash: photo!.blurhash),
                  ),
                ),
                CustomPaint(size: Size.square(size), painter: _SlicePainter(palette: palette, ring: c.card)),
              ],
            ),
          ),
          for (var i = 0; i < _segments.length; i++)
            Builder(builder: (context) {
              final a = -math.pi / 2 + i * seg + seg / 2 + angle;
              const box = 56.0;
              return Positioned(
                left: r + math.cos(a) * r * 0.64 - box / 2,
                top: r + math.sin(a) * r * 0.64 - box / 2,
                width: box,
                height: box,
                child: _PrizeMark(segment: _segments[i], ink: palette.ink(i), ring: palette.markRing),
              );
            }),
        ],
      ),
    );
  }
}

/// A prize on the wheel: its currency mark over its amount.
class _PrizeMark extends StatelessWidget {
  const _PrizeMark({required this.segment, required this.ink, this.ring});
  final WheelSegment segment;
  final Color ink;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    Widget mark = currencyIcon(segment.kind, size: 24);
    if (ring != null) {
      mark = DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring!, width: 1.5)), child: mark);
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        mark,
        const SizedBox(height: 3),
        Text(segment.label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, height: 1.1, color: ink, letterSpacing: -0.2, fontFeatures: const [FontFeature.tabularFigures()], shadows: const [Shadow(color: Color(0x99000000), blurRadius: 6)])),
      ],
    );
  }
}

/// Today's picture under the slices: alternate slices darkened a little more than
/// the others, the jackpot washed in coin gold. White amounts with a soft shadow; the
/// marks get a white ring so they read on any picture.
class _WheelPalette {
  const _WheelPalette();

  static _WheelPalette of(BuildContext context) => const _WheelPalette();

  Color get spoke => Colors.white.withValues(alpha: 0.7);
  Color? get markRing => Colors.white;
  Color fill(int i) => _segments[i].jackpot ? Brand.coin.withValues(alpha: 0.62) : Colors.black.withValues(alpha: i.isEven ? 0.30 : 0.48);
  Color ink(int i) => Colors.white;
}

class _SlicePainter extends CustomPainter {
  _SlicePainter({required this.palette, required this.ring});
  final _WheelPalette palette;
  final Color ring;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    final seg = 2 * math.pi / _segments.length;
    final rect = Rect.fromCircle(center: center, radius: r);
    for (var i = 0; i < _segments.length; i++) {
      final start = -math.pi / 2 + i * seg;
      canvas.drawArc(rect, start, seg, true, Paint()..color = palette.fill(i));
    }
    // Hairline spokes between the slices.
    final spoke = Paint()
      ..color = palette.spoke
      ..strokeWidth = 1.5;
    for (var i = 0; i < _segments.length; i++) {
      final a = -math.pi / 2 + i * seg;
      canvas.drawLine(center, Offset(center.dx + math.cos(a) * r, center.dy + math.sin(a) * r), spoke);
    }
    canvas.drawCircle(center, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 6..color = ring);
    // A hairline just inside the rim, so light slices do not melt into it.
    canvas.drawCircle(center, r - 3, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = palette.spoke);
  }

  @override
  bool shouldRepaint(_SlicePainter old) => old.ring != ring;
}

class _PointerPainter extends CustomPainter {
  _PointerPainter({required this.color, required this.edge});
  final Color color;
  final Color edge;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height * 0.75)
      ..quadraticBezierTo(size.width / 2, size.height, 0, size.height * 0.75)
      ..close();
    canvas.drawShadow(path, Colors.black, 3, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = edge);
  }

  @override
  bool shouldRepaint(_PointerPainter old) => old.color != color || old.edge != edge;
}
