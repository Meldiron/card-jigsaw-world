import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../state/profile.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// Top bar shared by tabs: avatar + level on the left, tickets and coins on the right.
class HeaderBar extends ConsumerWidget {
  const HeaderBar({super.key, required this.title, this.showTitle = true});
  final String title;
  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final profile = ref.watch(profileProvider).value;
    return SafeArea(
      bottom: false,
      child: Padding(
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
            const Spacer(),
            CurrencyPill(currency: Currency.tickets, value: profile?.tickets ?? 0, compact: true, onAdd: () => context.push('/store')),
            const SizedBox(width: 8),
            CurrencyPill(currency: Currency.coins, value: profile?.coins ?? 0, onAdd: () => context.push('/store')),
          ],
        ),
      ),
    );
  }
}
