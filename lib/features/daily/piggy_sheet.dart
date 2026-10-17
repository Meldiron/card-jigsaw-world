import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics.dart';
import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/profile.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

Future<void> showPiggySheet(BuildContext context) => showAppSheet(context, builder: (_) => const PiggySheet());

/// Piggy bank fills with every completed puzzle; break it open with a ticket. Five upgrades make it
/// hold more (500 to 1,000), for coins.
class PiggySheet extends ConsumerWidget {
  const PiggySheet({super.key});

  /// Asks first, then upgrades; short of coins, the store (as for packs and boosters).
  Future<void> _upgrade(BuildContext context, WidgetRef ref, Profile profile) async {
    const price = Economy.piggyUpgradeCoins;
    final next = Profile.piggyCapacityAt(profile.piggyLevel + 1);
    if (profile.coins < price) {
      Sfx.instance.error();
      showToast(context, 'Not enough coins. Play more puzzles or visit the store.', leading: const CoinIcon(size: 20));
      final router = GoRouter.of(context);
      Navigator.pop(context);
      router.push('/store');
      return;
    }
    final sure = await showAppAlert(
      context,
      title: 'Upgrade the piggy bank?',
      message: 'It holds ${formatCount(next)} coins instead of ${formatCount(profile.piggyCapacity)}. This costs ${countOf(price, 'coin')}. You have ${formatCount(profile.coins)}.',
      confirmLabel: 'Pay ${countOf(price, 'coin')}',
    );
    if (!sure || !context.mounted) return;
    if (!await ref.read(profileProvider.notifier).upgradePiggy()) return;
    AppAnalytics.event('piggy_upgraded', {'level': profile.piggyLevel + 1, 'capacity': next, 'price': price});
    if (!context.mounted) return;
    Sfx.instance.coin();
    Haptics.success();
    showToast(context, 'Your piggy bank holds ${formatCount(next)} coins now', icon: AppIcons.piggy);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final profile = ref.watch(profileProvider).value;
    final coins = profile?.piggyCoins ?? 0;
    final capacity = profile?.piggyCapacity ?? Profile.basePiggyCapacity;
    final full = profile?.piggyFull ?? false;
    final tickets = profile?.tickets ?? 0;
    final canOpen = coins > 0 && tickets >= Economy.piggyOpenTickets;
    // The next size, while there is one.
    final upgrade = profile != null && profile.piggyLevel < Profile.maxPiggyLevel ? profile.piggyLevel + 1 : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: 'Piggy bank',
            subtitle: 'Every solved picture adds ${countOf(Economy.piggyPerPuzzle, 'coin')}, up to ${formatCount(capacity)}. Open it with ${countOf(Economy.piggyOpenTickets, 'ticket')} whenever you like.',
            center: true,
          ),
          const SizedBox(height: 20),
          // The bank itself: a ring that fills with the coins inside, the amount in its middle.
          SizedBox.square(
            dimension: 148,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: (coins / capacity).clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, v, child) => CustomPaint(painter: _RingPainter(value: v, track: c.stroke, fill: context.accent), child: child),
              // The ring keeps its size: with a large text size its middle shrinks to fit.
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIcons.piggy, size: 22, color: context.accent),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CoinIcon(size: 20),
                      const SizedBox(width: 5),
                      AnimatedCounter(value: coins, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.largeTitle, letterSpacing: -0.8)),
                    ],
                  ),
                  Text('of ${formatCount(capacity)}', style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w500, color: c.textSecondary)),
                ],
              ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const SizedBox(height: 8),
          Text(full ? 'Full. Open it to keep collecting.' : (coins == 0 ? 'Solve a picture to drop in the first ${countOf(Economy.piggyPerPuzzle, 'coin')}.' : 'Keep solving to fill it'), style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w500, color: full ? context.accent : c.textTertiary)),
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
              'Opening costs ${countOf(Economy.piggyOpenTickets, 'ticket')}. You have ${formatCount(tickets)}. Weekly quests, level-ups and events give tickets too.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w500, color: c.textSecondary),
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
                      if (ok) AppAnalytics.event('piggy_opened', {'coins': coins, 'capacity': capacity, 'full': coins >= capacity});
                      if (!context.mounted) return;
                      if (ok) {
                        Sfx.instance.coin();
                        Haptics.success();
                        Navigator.pop(context);
                        showToast(context, '+${countOf(coins, 'coin')} from your piggy bank', icon: AppIcons.piggy);
                      }
                    },
            ),
            const SizedBox(height: 10),
            Text('You have ${countOf(tickets, 'ticket')}', textAlign: TextAlign.center, style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w500, color: c.textSecondary)),
          ],
          // A bigger piggy bank, one size at a time; not offered at the largest size.
          if (upgrade != null) ...[
            SizedBox(height: coins == 0 ? 0 : 20),
            BigButton.cost(
              key: const ValueKey('piggy-upgrade'),
              label: 'Upgrade to ${formatCount(Profile.piggyCapacityAt(upgrade))} for',
              currency: Currency.coins,
              amount: Economy.piggyUpgradeCoins,
              kind: ButtonKind.secondary,
              onTap: () => _upgrade(context, ref, profile!),
            ),
            const SizedBox(height: 8),
            Text(
              'Upgrade $upgrade of ${Profile.maxPiggyLevel}: holds ${formatCount(Profile.piggyStep)} coins more',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w500, color: c.textSecondary),
            ),
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
