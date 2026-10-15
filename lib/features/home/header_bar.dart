import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../state/profile.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// Top bar shared by tabs: avatar + level on the left, tickets and coins on
/// the right. As a sliver it stays pinned and turns to glass once the page
/// scrolls under it; `sliver: false` gives a plain box for non-scrolling
/// layouts.
class HeaderBar extends ConsumerWidget {
  const HeaderBar({super.key, required this.title, this.sliver = true});
  final String title;
  final bool sliver;

  /// Content height below the status bar.
  static const double height = 50;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final profile = ref.watch(profileProvider).value;
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(
        children: [
          Pressable(
            onTap: () => context.go('/profile'),
            child: Row(
              children: [
                AvatarCircle(avatarKey: profile?.avatar, size: 38),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('LV ${profile?.level ?? 1}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: -0.2, color: c.textPrimary)),
                    const SizedBox(height: 4),
                    SizedBox(width: 56, child: ProgressBar(value: profile?.levelProgress ?? 0, height: 4)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Balances too long for the bar shrink the capsule a little instead of pushing it off screen.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: _BalancePill(tickets: profile?.tickets ?? 0, coins: profile?.coins ?? 0, onTap: () => context.push('/store')),
            ),
          ),
        ],
      ),
    );
    if (!sliver) return SafeArea(bottom: false, child: SizedBox(height: height, child: row));
    return GlassSliverHeader(height: height, child: row);
  }
}

/// Tickets and coins in one capsule with one "+" (both lead to the Store). Two pills with a "+"
/// each repeated the same action and took the width long balances need.
class _BalancePill extends StatelessWidget {
  const _BalancePill({required this.tickets, required this.coins, required this.onTap});
  final int tickets;
  final int coins;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final number = TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: c.textPrimary, letterSpacing: -0.2);
    return Pressable(
      onTap: onTap,
      scale: 0.95,
      child: Semantics(
        button: true,
        label: '$tickets tickets, $coins coins, open the Store',
        child: Container(
          height: 34,
          padding: const EdgeInsets.only(left: 10, right: 5),
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(Radii.pill), border: Border.all(color: c.stroke)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              currencyIcon(Currency.tickets, size: 16),
              const SizedBox(width: 5),
              AnimatedCounter(value: tickets, style: number),
              Container(width: 1, height: 16, margin: const EdgeInsets.symmetric(horizontal: 10), color: c.stroke),
              currencyIcon(Currency.coins, size: 16),
              const SizedBox(width: 5),
              AnimatedCounter(value: coins, style: number),
              const SizedBox(width: 8),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(color: c.accentTint, shape: BoxShape.circle),
                child: Icon(CupertinoIcons.plus, size: 14, color: context.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
