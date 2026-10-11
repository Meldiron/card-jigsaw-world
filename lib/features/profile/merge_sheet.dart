import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../state/merge.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// Asks which save supplies coins, level and streak when a guest signs in to
/// an existing account and neither save clearly wins. Pictures, badges and
/// unlocks from both are combined before this is shown. Cannot be dismissed
/// without choosing; if the OS closes it anyway, the account's save is kept.
Future<MergeChoice> showMergeSheet(BuildContext context, {required SaveSnapshot device, required SaveSnapshot account}) async {
  final choice = await showAppSheet<MergeChoice>(
    context,
    dismissible: false,
    builder: (ctx) => MergeSheet(device: device, account: account),
  );
  return choice ?? MergeChoice.account;
}

class MergeSheet extends StatelessWidget {
  const MergeSheet({super.key, required this.device, required this.account});
  final SaveSnapshot device;
  final SaveSnapshot account;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Two saves found', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Pictures, badges and unlocks from both are already combined. Choose whose coins, level and streak to keep.',
              style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _SaveCard(label: 'This device', save: device)),
                const SizedBox(width: 12),
                Expanded(child: _SaveCard(label: 'Your account', save: account)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: BigButton(label: "Keep this device's", kind: ButtonKind.secondary, onTap: () => Navigator.of(context).pop(MergeChoice.guest))),
                const SizedBox(width: 10),
                Expanded(child: BigButton(label: "Keep account's", onTap: () => Navigator.of(context).pop(MergeChoice.account))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveCard extends StatelessWidget {
  const _SaveCard({required this.label, required this.save});
  final String label;
  final SaveSnapshot save;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = NumberFormat.decimalPattern();
    Widget stat(Widget icon, String name, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(width: 18, child: Center(child: icon)),
              const SizedBox(width: 6),
              Expanded(child: Text(name, style: TextStyle(fontSize: 12.5, color: c.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              Text(value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.textPrimary)),
            ],
          ),
        );
    Widget mono(IconData i) => Icon(i, size: 15, color: c.textTertiary);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(Radii.lg), border: Border.all(color: c.stroke)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: c.textTertiary)),
          const SizedBox(height: 10),
          Row(
            children: [
              AvatarCircle(avatarKey: save.avatar, size: 34),
              const SizedBox(width: 8),
              Expanded(child: Text(save.displayName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: c.stroke),
          const SizedBox(height: 6),
          stat(mono(AppIcons.puzzle), 'Solved', n.format(save.solved)),
          stat(Icon(AppIcons.star, size: 15, color: Brand.star), 'Stars', n.format(save.stars)),
          stat(mono(AppIcons.level), 'Level', '${save.level}'),
          stat(mono(AppIcons.xp), 'XP', n.format(save.xp)),
          stat(currencyIcon(Currency.coins, size: 15), 'Coins', n.format(save.coins)),
          stat(currencyIcon(Currency.tickets, size: 15), 'Tickets', n.format(save.tickets)),
          stat(currencyIcon(Currency.hints, size: 15), 'Hints', n.format(save.hints)),
          stat(mono(CupertinoIcons.time), 'Played', relativeTime(save.lastPlayed)),
        ],
      ),
    );
  }
}
