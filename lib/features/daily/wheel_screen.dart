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
import '../../state/profile.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

class _Segment {
  const _Segment(this.label, this.kind, this.color, {this.coins = 0, this.hints = 0, this.weight = 1, this.jackpot = false});
  final String label;
  final Currency kind;
  final Color color;
  final int coins;
  final int hints;
  final double weight;
  final bool jackpot;
}

/// Balance: a spin costs 1 Ticket, and a Ticket is worth roughly 150 Coins
/// (it opens a piggy bank of up to 500 Coins, premium packs cost 3).
/// Expected value per spin:
///   coins  = (60·5 + 90·4 + 120·4 + 150·3 + 200·2 + 300·1.5 + 500·0.5) / 22 ≈ 122
///   hints  = 2 hints (≈120 Coins at the 60-Coin hint price) × 2/22      ≈  11
///   total  ≈ 133 Coin-equivalent, i.e. about a 90% return with a 2.3%
///   chance (0.5/22) of the 500-Coin jackpot. Tickets are never a reward,
///   so the wheel cannot pay for itself.
const _segments = [
  _Segment('60', Currency.coins, Color(0xFFD97706), coins: 60, weight: 5),
  _Segment('90', Currency.coins, Color(0xFF64748B), coins: 90, weight: 4),
  _Segment('120', Currency.coins, Color(0xFF0F9D8F), coins: 120, weight: 4),
  _Segment('2', Currency.hints, Brand.accent, hints: 2, weight: 2),
  _Segment('150', Currency.coins, Color(0xFFB45309), coins: 150, weight: 3),
  _Segment('200', Currency.coins, Color(0xFF475569), coins: 200, weight: 2),
  _Segment('300', Currency.coins, Color(0xFF0B7A70), coins: 300, weight: 1.5),
  _Segment('500', Currency.coins, Color(0xFF3730A3), coins: 500, weight: 0.5, jackpot: true),
];

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
  _Segment? _result;
  int _lastTick = -1;

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
    // Weighted pick.
    final total = _segments.fold<double>(0, (s, e) => s + e.weight);
    var r = math.Random().nextDouble() * total;
    var idx = 0;
    for (var i = 0; i < _segments.length; i++) {
      r -= _segments[i].weight;
      if (r <= 0) {
        idx = i;
        break;
      }
    }
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
      if (won.coins > 0) await n.addCoins(won.coins, reason: 'wheel');
      if (won.hints > 0) await n.addHints(won.hints, reason: 'wheel');
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
      appBar: GlassAppBar(
        title: const Text('Lucky Wheel'),
        leading: Padding(padding: const EdgeInsets.only(left: 12), child: RoundIconButton(icon: CupertinoIcons.xmark, size: 38, onTap: () => context.pop())),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Your Tickets', style: TextStyle(color: c.textSecondary)),
                const SizedBox(width: 8),
                Amount(currency: Currency.tickets, value: tickets, size: 16),
              ],
            ),
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (_, cons) {
                    final size = math.min(cons.maxWidth - 48, 340.0);
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
                          builder: (_, _) => Transform.rotate(
                            angle: _angle,
                            child: CustomPaint(size: Size.square(size), painter: _WheelPainter(dark: context.isDark, ring: c.card, tick: c.stroke)),
                          ),
                        ),
                        Container(
                          width: 64,
                          height: 64,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: c.card, shape: BoxShape.circle, border: Border.all(color: c.stroke)),
                          child: Icon(AppIcons.wheel, size: 30, color: context.accent),
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
                            child: CustomPaint(size: const Size(30, 36), painter: _PointerPainter()),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            if (_result != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SoftCard(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('You won', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      const SizedBox(width: 10),
                      if (_result!.coins > 0) Amount(currency: Currency.coins, value: _result!.coins, size: 20),
                      if (_result!.hints > 0) Amount(currency: Currency.hints, value: _result!.hints, size: 20),
                      if (jackpot) ...[const SizedBox(width: 8), const Chip2(label: 'Jackpot', color: Brand.coin, foreground: Color(0xFF2A1F00))],
                    ],
                  ),
                ).animate().fadeIn().then().scale(begin: const Offset(1, 1), end: jackpot ? const Offset(1.08, 1.08) : const Offset(1, 1), duration: 220.ms, curve: Curves.easeOut).then().scale(begin: const Offset(1, 1), end: jackpot ? const Offset(1 / 1.08, 1 / 1.08) : const Offset(1, 1), duration: 260.ms, curve: Curves.easeOutBack),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                children: [
                  BigButton.cost(
                    label: 'Spin for',
                    currency: Currency.tickets,
                    amount: Economy.wheelSpinTickets,
                    onTap: canSpin ? _spin : null,
                  ),
                  if (tickets < Economy.wheelSpinTickets) ...[
                    const SizedBox(height: 8),
                    BigButton(label: 'Get tickets', kind: ButtonKind.secondary, onTap: () => context.push('/store')),
                    const SizedBox(height: 8),
                    Text('Earn tickets from weekly quests, level-ups and events.', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 12.5)),
                  ] else ...[
                    const SizedBox(height: 8),
                    Text('Jackpot: 500 coins', style: TextStyle(color: c.textTertiary, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Segment glyph: the jackpot is coins too, so it carries the coin mark.
IconData _glyph(_Segment s) => switch (s.kind) {
      Currency.coins => Icons.monetization_on_rounded,
      Currency.tickets => Icons.confirmation_number_rounded,
      Currency.hints => Icons.lightbulb_rounded,
    };

class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.dark, required this.ring, required this.tick});
  final bool dark;
  final Color ring;
  final Color tick;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    final seg = 2 * math.pi / _segments.length;
    for (var i = 0; i < _segments.length; i++) {
      final start = -math.pi / 2 + i * seg;
      final paint = Paint()..color = _segments[i].color;
      canvas.drawArc(Rect.fromCircle(center: center, radius: r), start, seg, true, paint);
      canvas.drawArc(Rect.fromCircle(center: center, radius: r), start, seg, true, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = ring);
      // Label
      final angle = start + seg / 2;
      final tp = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(text: String.fromCharCode(_glyph(_segments[i]).codePoint), style: TextStyle(fontFamily: _glyph(_segments[i]).fontFamily, package: _glyph(_segments[i]).fontPackage, fontSize: 22, color: Colors.white)),
            TextSpan(text: '\n${_segments[i].label}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white, height: 1.25)),
          ],
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(center.dx + math.cos(angle) * r * 0.66, center.dy + math.sin(angle) * r * 0.66);
      canvas.rotate(angle + math.pi / 2);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
    canvas.drawCircle(center, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 6..color = ring);
    for (var i = 0; i < _segments.length; i++) {
      final a = -math.pi / 2 + i * seg;
      canvas.drawCircle(Offset(center.dx + math.cos(a) * r, center.dy + math.sin(a) * r), 4, Paint()..color = tick);
    }
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.dark != dark || old.ring != ring || old.tick != tick;
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height * 0.75)
      ..quadraticBezierTo(size.width / 2, size.height, 0, size.height * 0.75)
      ..close();
    canvas.drawPath(path, Paint()..color = Brand.live);
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
