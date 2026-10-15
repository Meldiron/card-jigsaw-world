import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/profile.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

Future<void> showPiggySheet(BuildContext context) => showAppSheet(context, builder: (_) => const PiggySheet());

/// Piggy bank fills with every completed puzzle; break it open with a ticket.
class PiggySheet extends ConsumerWidget {
  const PiggySheet({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final profile = ref.watch(profileProvider).value;
    final coins = profile?.piggyCoins ?? 0;
    final full = profile?.piggyFull ?? false;
    final tickets = profile?.tickets ?? 0;
    final canOpen = coins > 0 && tickets >= Economy.piggyOpenTickets;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: 'Piggy bank',
            subtitle: 'Every solved picture adds ${Economy.piggyPerPuzzle} coins, up to ${Profile.piggyCapacity}. Open it with ${Economy.piggyOpenTickets} ticket whenever you like.',
            center: true,
          ),
          const SizedBox(height: 20),
          // The bank itself: a ring that fills with the coins inside, the amount in its middle.
          SizedBox.square(
            dimension: 148,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: (coins / Profile.piggyCapacity).clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, v, child) => CustomPaint(painter: _RingPainter(value: v, track: c.stroke, fill: context.accent), child: child),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(AppIcons.piggy, size: 22, color: context.accent),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CoinIcon(size: 20),
                      const SizedBox(width: 5),
                      AnimatedCounter(value: coins, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 32, letterSpacing: -0.8)),
                    ],
                  ),
                  Text('of ${Profile.piggyCapacity}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: c.textSecondary)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          const SizedBox(height: 8),
          Text(full ? 'Full. Open it to keep collecting.' : (coins == 0 ? 'Solve a picture to drop in the first ${Economy.piggyPerPuzzle} coins.' : 'Keep solving to fill it'), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: full ? context.accent : c.textTertiary)),
          const SizedBox(height: 20),
          // One clear state each: nothing inside (no button, it says how it fills), not enough
          // tickets (the way to get one), or ready to open.
          if (coins == 0)
            const SizedBox.shrink()
          else if (tickets < Economy.piggyOpenTickets) ...[
            BigButton(label: 'Get tickets', onTap: () {
              Navigator.pop(context);
              context.push('/store');
            }),
            const SizedBox(height: 10),
            Text(
              'Opening costs ${Economy.piggyOpenTickets} ticket. You have $tickets. Weekly quests, level-ups and events give tickets too.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: c.textSecondary),
            ),
          ] else ...[
            BigButton.cost(
              label: 'Open for',
              currency: Currency.tickets,
              amount: Economy.piggyOpenTickets,
              onTap: !canOpen
                  ? null
                  : () async {
                      final ok = await ref.read(profileProvider.notifier).openPiggy();
                      if (!context.mounted) return;
                      if (ok) {
                        Sfx.instance.coin();
                        Haptics.success();
                        Navigator.pop(context);
                        showToast(context, '+$coins coins from your piggy bank', icon: AppIcons.piggy);
                      }
                    },
            ),
            const SizedBox(height: 10),
            Text('You have $tickets ticket${tickets == 1 ? '' : 's'}', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: c.textSecondary)),
          ],
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.track, required this.fill});
  final double value;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - stroke / 2);
    canvas.drawArc(rect, 0, 6.283185307179586, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track);
    if (value > 0) {
      canvas.drawArc(rect, -1.5707963267948966, 6.283185307179586 * value, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = fill);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.track != track || old.fill != fill;
}
