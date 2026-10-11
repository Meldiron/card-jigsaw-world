import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final canOpen = coins > 0 && (profile?.tickets ?? 0) >= Economy.piggyOpenTickets;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const IconTile(icon: AppIcons.piggy, size: 64, radius: 20),
          const SizedBox(height: 12),
          Text('Piggy bank', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'Every solved puzzle adds ${Economy.piggyPerPuzzle} Coins. Open it with ${Economy.piggyOpenTickets} Ticket whenever you like.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textSecondary),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Padding(padding: EdgeInsets.only(right: 8), child: CoinIcon(size: 26)),
              AnimatedCounter(value: coins, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 40, letterSpacing: -1)),
              Text(' / ${Profile.piggyCapacity}', style: TextStyle(fontWeight: FontWeight.w500, color: c.textSecondary)),
            ],
          ),
          const SizedBox(height: 10),
          ProgressBar(value: coins / Profile.piggyCapacity, height: 10),
          const SizedBox(height: 8),
          Text(full ? 'Full. Open it to keep collecting.' : 'Keep solving to fill it', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: full ? context.accent : c.textTertiary)),
          const SizedBox(height: 20),
          BigButton(
            label: coins == 0 ? 'Nothing inside yet' : 'Open for ${Economy.piggyOpenTickets} ticket',
            trailing: coins == 0 ? null : Amount(currency: Currency.coins, value: coins, size: 18, color: const Color(0xFF2A1F00)),
            icon: CupertinoIcons.hammer_fill,
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
          if (coins > 0 && !canOpen)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('You need 1 Ticket. Earn Tickets from weekly goals, level-ups and events.', style: TextStyle(fontSize: 12, color: c.textTertiary)),
            ),
        ],
      ),
    );
  }
}
