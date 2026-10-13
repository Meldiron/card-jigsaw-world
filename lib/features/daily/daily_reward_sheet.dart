import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../state/profile.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

Future<void> showDailyRewardSheet(BuildContext context) => showAppSheet(context, builder: (_) => const DailyRewardSheet());

/// 7-day streak calendar. Day 7 is the big one.
class DailyRewardSheet extends ConsumerStatefulWidget {
  const DailyRewardSheet({super.key});
  @override
  ConsumerState<DailyRewardSheet> createState() => _DailyRewardSheetState();
}

class _DailyRewardSheetState extends ConsumerState<DailyRewardSheet> {
  bool _claiming = false;
  bool _restoring = false;
  ({int coins, int tickets, int hints, int day})? _claimed;

  Future<void> _restore() async {
    final n = ref.read(profileProvider.notifier);
    final p = ref.read(profileProvider).value;
    if (p == null) return;
    final cost = Economy.streakRestoreTickets(p.longestStreak);
    if (p.tickets < cost) {
      showToast(context, 'You need $cost tickets to restore the streak.', leading: const TicketIcon(size: 18));
      context.push('/store');
      return;
    }
    setState(() => _restoring = true);
    final ok = await n.restoreStreak();
    if (!mounted) return;
    setState(() => _restoring = false);
    if (ok) {
      Sfx.instance.coin();
      Haptics.success();
      showToast(context, 'Streak restored', icon: AppIcons.streak);
    } else {
      showToast(context, 'The streak could not be restored right now.', icon: AppIcons.streak);
    }
  }

  Future<void> _claim() async {
    setState(() => _claiming = true);
    final r = await ref.read(profileProvider.notifier).claimDaily();
    if (!mounted) return;
    if (r != null) {
      Sfx.instance.coin();
      Haptics.success();
    }
    setState(() {
      _claiming = false;
      _claimed = r;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final profile = ref.watch(profileProvider).value;
    final available = profile?.dailyAvailable ?? false;
    final streak = profile?.streak ?? 0;
    final todayIdx = available ? (streak % 7) : ((streak - 1) % 7).clamp(0, 6);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const IconTile(icon: AppIcons.dailyGift, size: 64, radius: 20),
          const SizedBox(height: 12),
          Text('Daily gift', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            available ? 'Come back every day to grow your streak.' : 'Claimed · Streak: $streak day${streak == 1 ? '' : 's'}. Back tomorrow.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textSecondary),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < 7; i++)
                _DayTile(
                  day: i + 1,
                  reward: Economy.dailyRewards[i],
                  claimed: available ? i < todayIdx : i <= todayIdx,
                  today: i == todayIdx,
                  big: i == 6,
                ).animate().fadeIn(delay: (40 * i).ms).scale(begin: const Offset(0.9, 0.9)),
            ],
          ),
          const SizedBox(height: 20),
          if (profile != null && ref.read(profileProvider.notifier).canRestoreStreak)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SoftCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const IconTile(icon: AppIcons.streak, size: 34, radius: 10),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Restore your ${profile.longestStreak}-day streak', style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 2),
                              Text(
                                'Your streak reset to ${profile.streak}. Bring it back to ${profile.longestStreak} days.',
                                style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    BigButton(
                      label: 'Restore for',
                      trailing: Amount(currency: Currency.tickets, value: Economy.streakRestoreTickets(profile.longestStreak), size: 18, color: Colors.white),
                      loading: _restoring,
                      onTap: _restore,
                    ),
                  ],
                ),
              ),
            ),
          if (_claimed != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 14,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('You received', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  Amount(currency: Currency.coins, value: _claimed!.coins, size: 18, prefix: '+'),
                  if (_claimed!.tickets > 0) Amount(currency: Currency.tickets, value: _claimed!.tickets, size: 18, prefix: '+'),
                  if (_claimed!.hints > 0) Amount(currency: Currency.hints, value: _claimed!.hints, size: 18, prefix: '+'),
                ],
              ).animate().scale(curve: Curves.easeOutBack),
            ),
          BigButton(
            label: available ? 'Claim day ${todayIdx + 1} gift' : 'Claimed today',
            icon: available ? AppIcons.dailyGift : CupertinoIcons.checkmark_alt,
            kind: available ? ButtonKind.primary : ButtonKind.secondary,
            loading: _claiming,
            onTap: available ? _claim : () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({required this.day, required this.reward, required this.claimed, required this.today, required this.big});
  final int day;
  final ({int coins, int tickets, int hints}) reward;
  final bool claimed;
  final bool today;
  final bool big;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = context.accent;
    // Today is a tinted tile with a strong outline, not a solid accent fill: the coin, ticket and
    // hint icons keep their own colours and need a dark (or, in light mode, pale) ground to read.
    final onColor = c.textPrimary;
    final labelColor = today ? accent : c.textTertiary;
    return Container(
      width: big ? 168 : 80,
      height: 96,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: today ? c.accentTint : c.card,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: today ? accent : (big ? accent.withValues(alpha: 0.6) : c.stroke), width: today ? 2 : 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Day $day', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: labelColor)),
          const SizedBox(height: 6),
          SizedBox(
            height: 24,
            child: claimed && !today
                ? Icon(CupertinoIcons.checkmark_circle_fill, size: 22, color: c.success)
                : big
                    ? Icon(AppIcons.crown, size: 24, color: accent)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CoinIcon(size: 18),
                          if (reward.tickets > 0) ...[const SizedBox(width: 3), const TicketIcon(size: 13)],
                          if (reward.hints > 0) ...[const SizedBox(width: 3), const HintIcon(size: 16)],
                        ],
                      ),
          ),
          const SizedBox(height: 4),
          Text(
            big ? '${reward.coins} · ${reward.tickets} tickets · ${reward.hints} hints' : '${reward.coins}${reward.tickets > 0 ? ' +${reward.tickets}' : ''}${reward.hints > 0 ? ' +${reward.hints}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5, color: onColor),
          ),
        ],
      ),
    );
  }
}
