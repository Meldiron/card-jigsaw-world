import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../state/merge.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// Asks which save supplies coins, level and streak when a guest signs in to
/// an existing account and neither save clearly wins. Pictures, badges and
/// unlocks from both are combined before this is shown. Cannot be dismissed
/// without choosing; if the OS closes it anyway, the account's save is kept.
/// The account's save is called the "cloud save" here: what the player is
/// choosing between is where a save lives, not two accounts.
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
    String days(int v) => countOf(v, 'day');
    // What the choice decides, side by side; the larger number of a row is in full ink.
    final rows = <(Widget, String, int, int, String Function(int))>[
      (Icon(AppIcons.level, size: 15, color: c.textTertiary), 'Level', device.level, account.level, (v) => formatCount(v)),
      (currencyIcon(Currency.coins, size: 15), 'Coins', device.coins, account.coins, formatCount),
      (currencyIcon(Currency.tickets, size: 15), 'Tickets', device.tickets, account.tickets, formatCount),
      (currencyIcon(Currency.hints, size: 15), 'Hints', device.hints, account.hints, formatCount),
      (Icon(AppIcons.streak, size: 15, color: c.textTertiary), 'Streak', device.streak, account.streak, days),
    ];
    const figures = tabularFigures;
    Widget value(String text, bool more) => Expanded(
          flex: 3,
          child: Text(
            text,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: TypeSize.body, fontWeight: more ? FontWeight.w700 : FontWeight.w500, color: more ? c.textPrimary : c.textSecondary, fontFeatures: figures),
          ),
        );
    Widget head(SaveSnapshot s, String label) => Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AvatarCircle(avatarKey: s.avatar, size: 30),
              const SizedBox(height: 6),
              Text(label, maxLines: 1, style: const TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w700)),
              Text(relativeTime(s.lastPlayed), style: TextStyle(fontSize: TypeSize.caption, color: c.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        );
    return PopScope(
      canPop: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHeader(
              title: 'Two saves found',
              subtitle: 'Pictures, stars and badges from both are already combined. Choose which coins, level and streak to keep.',
            ),
            const SizedBox(height: 16),
            SoftCard(
              padding: Insets.cardCompact.copyWith(bottom: 8),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Expanded(flex: 4, child: SizedBox()),
                      head(device, 'This device'),
                      const SizedBox(width: 12),
                      head(account, 'Cloud save'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final r in rows) ...[
                    Divider(height: 1, color: c.stroke),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Row(
                              children: [
                                SizedBox(width: 18, child: Center(child: r.$1)),
                                const SizedBox(width: 8),
                                Flexible(child: Text(r.$2, style: TextStyle(fontSize: TypeSize.body, color: c.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ),
                          value(r.$5(r.$3), r.$3 > r.$4),
                          const SizedBox(width: 12),
                          value(r.$5(r.$4), r.$4 > r.$3),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            BigButton(label: 'Keep cloud save', onTap: () => Navigator.of(context).pop(MergeChoice.account)),
            const SizedBox(height: 10),
            BigButton(label: "Keep this device's save", kind: ButtonKind.secondary, onTap: () => Navigator.of(context).pop(MergeChoice.guest)),
          ],
        ),
      ),
    );
  }
}
