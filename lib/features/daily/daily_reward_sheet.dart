import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/platform.dart';
import '../../core/reminders.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../state/profile.dart';
import '../../state/reminders.dart';
import '../../state/settings.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// The daily gift sheet. When the player claimed a gift in it, the sheet may
/// be followed by the one-time reminder question ([offerRemindersAfterGift]).
Future<void> showDailyRewardSheet(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final before = container.read(localStoreProvider).giftClaimDays;
  await showAppSheet(context, builder: (_) => const DailyRewardSheet());
  if (!context.mounted || container.read(localStoreProvider).giftClaimDays == before) return;
  await offerRemindersAfterGift(context, container);
}

/// Asks once, in the game, whether the player wants a daily reminder, before
/// iOS shows its own permission prompt (see [shouldOfferReminders]). "Turn on"
/// goes on to the iOS prompt; either answer closes the question for good.
Future<void> offerRemindersAfterGift(BuildContext context, ProviderContainer container) async {
  if (!container.read(platformCapsProvider).notifications) return;
  final store = container.read(localStoreProvider);
  final settings = container.read(settingsProvider);
  final profile = container.read(profileProvider).value;
  final permission = await ReminderChannel.status();
  final offer = shouldOfferReminders(
    giftDays: store.giftClaimDays,
    streak: profile?.streak ?? 0,
    remindersOn: settings.reminders,
    offerShown: store.reminderOfferShown,
    permission: permission,
  );
  if (!offer || !context.mounted) return;
  store.reminderOfferShown = true;
  final time = TimeOfDay(hour: settings.reminderMinutes ~/ 60, minute: settings.reminderMinutes % 60).format(context);
  final yes = await showAppAlert(
    context,
    title: 'Get a daily reminder?',
    message: 'One notification a day with the daily puzzle at $time, and one the evening before a new event opens. You can change or turn off either in Settings.',
    confirmLabel: 'Turn on',
    cancelLabel: 'Not now',
  );
  if (!yes) return;
  // The question named event notes too, so Turn on is the explicit yes to them.
  container.read(eventRemindersProvider.notifier).set(true);
  final granted = await container.read(remindersProvider).enable();
  if (granted && context.mounted) showToast(context, 'Daily reminder at $time', icon: CupertinoIcons.bell_fill);
}

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

  /// Restores the lost streak and claims today's gift with it.
  Future<void> _restore() async {
    final p = ref.read(profileProvider).value;
    if (p == null) return;
    final cost = Economy.streakRestoreTickets(p.streak);
    if (p.tickets < cost) {
      showToast(context, 'You need $cost tickets to restore the streak.', leading: const TicketIcon(size: 18));
      context.push('/store');
      return;
    }
    setState(() => _restoring = true);
    final r = await ref.read(profileProvider.notifier).claimDaily(restore: true);
    if (r != null) {
      final store = ref.read(localStoreProvider);
      store.giftClaimDays = store.giftClaimDays + 1;
    }
    if (!mounted) return;
    setState(() {
      _restoring = false;
      _claimed = r;
    });
    if (r != null) {
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
    if (r != null) {
      final store = ref.read(localStoreProvider);
      store.giftClaimDays = store.giftClaimDays + 1;
    }
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
    // After a missed day the next claim starts again at day 1, whatever the stored streak says.
    final todayIdx = profile == null ? 0 : (available ? profile.nextGiftDay : profile.giftsClaimedThisRound - 1);
    final missed = profile != null && !profile.streakAlive && profile.streak > 0;
    final canRestore = profile != null && ref.read(profileProvider.notifier).canRestoreStreak;

    final today = Economy.dailyRewards[todayIdx];
    final next = Economy.dailyRewards[(todayIdx + 1) % 7];
    final received = _claimed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Daily gift', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            !available
                ? 'Streak: $streak day${streak == 1 ? '' : 's'}. Back tomorrow.'
                : missed
                    ? (canRestore ? 'You missed a day. Restore your streak or start again.' : 'You missed a day, so the streak starts again.')
                    : 'Come back every day to grow your streak.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 18),
          _StreakTrack(todayIdx: todayIdx, claimedToday: !available),
          const SizedBox(height: 18),
          // Today's gift in full; after the claim the same card says what arrived.
          SoftCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        received != null ? 'You received' : (available ? 'Day ${todayIdx + 1} gift' : 'Today, day ${todayIdx + 1}'),
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      _Rewards(reward: today, size: 22, prefix: received != null ? '+' : ''),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(todayIdx == 5 ? 'Tomorrow, the big one' : 'Tomorrow', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.textTertiary)),
                    const SizedBox(height: 6),
                    _Rewards(reward: next, size: 14),
                  ],
                ),
              ],
            ),
          ).animate(key: ValueKey(received != null)).fadeIn(duration: 200.ms),
          if (profile != null && canRestore) ...[
            const SizedBox(height: 10),
            // 001 B: restoring the streak just lost also claims today's gift as the next day of it.
            _RestoreRow(
              streak: profile.streak,
              day: profile.streak % 7 + 1,
              cost: Economy.streakRestoreTickets(profile.streak),
              loading: _restoring,
              onTap: _restore,
            ),
          ],
          const SizedBox(height: 18),
          BigButton(
            label: available ? 'Claim day ${todayIdx + 1} gift' : 'Done',
            icon: available ? AppIcons.dailyGift : null,
            kind: available ? ButtonKind.primary : ButtonKind.secondary,
            loading: _claiming,
            onTap: available ? _claim : () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

/// Coins, tickets and hints of one day's gift, each as its mark and number.
class _Rewards extends StatelessWidget {
  const _Rewards({required this.reward, required this.size, this.prefix = ''});
  final ({int coins, int tickets, int hints}) reward;
  final double size;
  final String prefix;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: size * 0.6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Amount(currency: Currency.coins, value: reward.coins, size: size, prefix: prefix, weight: FontWeight.w700),
          if (reward.tickets > 0) Amount(currency: Currency.tickets, value: reward.tickets, size: size, prefix: prefix, weight: FontWeight.w700),
          if (reward.hints > 0) Amount(currency: Currency.hints, value: reward.hints, size: size, prefix: prefix, weight: FontWeight.w700),
        ],
      );
}

/// Seven stops on one line: done days filled, today ringed, day 7 marked.
/// Under each stop the day's coins, so the climb to day 7 reads at a glance.
class _StreakTrack extends StatelessWidget {
  const _StreakTrack({required this.todayIdx, required this.claimedToday});
  final int todayIdx;
  final bool claimedToday;

  static const _dot = 34.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = context.accent;
    bool done(int i) => i < todayIdx || (claimedToday && i == todayIdx);
    return LayoutBuilder(
      builder: (context, cons) {
        final cell = cons.maxWidth / 7;
        final reached = todayIdx.clamp(0, 6);
        return SizedBox(
          height: _dot + 22,
          child: Stack(
            children: [
              // The track behind the stops, filled up to today.
              Positioned(left: cell / 2, right: cell / 2, top: _dot / 2 - 1.5, child: Container(height: 3, decoration: BoxDecoration(color: c.stroke, borderRadius: BorderRadius.circular(2)))),
              if (reached > 0)
                Positioned(left: cell / 2, width: cell * reached, top: _dot / 2 - 1.5, child: Container(height: 3, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)))),
              Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    SizedBox(
                      width: cell,
                      child: Column(
                        children: [
                          _Stop(day: i + 1, done: done(i), today: i == todayIdx, big: i == 6, size: _dot),
                          const SizedBox(height: 6),
                          Text(
                            '${Economy.dailyRewards[i].coins}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: i == todayIdx ? accent : (done(i) ? c.textTertiary : c.textSecondary),
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Stop extends StatelessWidget {
  const _Stop({required this.day, required this.done, required this.today, required this.big, required this.size});
  final int day;
  final bool done;
  final bool today;
  final bool big;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = context.accent;
    final fill = done ? accent : (today ? c.accentTint : c.card);
    final Widget mark = done
        ? const Icon(CupertinoIcons.checkmark_alt, size: 18, color: Colors.white)
        : big
            ? Icon(AppIcons.crown, size: 18, color: today ? accent : accent.withValues(alpha: 0.8))
            : Text('$day', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: today ? accent : c.textSecondary));
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: done ? null : Border.all(color: today ? accent : (big ? accent.withValues(alpha: 0.5) : c.stroke), width: today ? 2 : 1),
      ),
      child: mark,
    );
  }
}

/// The streak restore offer as one row: what happened, what it brings back,
/// and a small tinted button with the price. It sits above the claim and
/// never outweighs it.
class _RestoreRow extends StatelessWidget {
  const _RestoreRow({required this.streak, required this.day, required this.cost, required this.loading, required this.onTap});

  /// The streak lost to the missed days, and the gift day a restore claims with it.
  final int streak;
  final int day;
  final int cost;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Row(
        children: [
          const IconTile(icon: AppIcons.streak, size: 34, radius: 10),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$streak-day streak', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Text('Restore and claim day $day', maxLines: 2, style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          BigButton.cost(label: 'Restore', currency: Currency.tickets, amount: cost, kind: ButtonKind.secondary, height: 36, expand: false, loading: loading, onTap: onTap),
        ],
      ),
    );
  }
}
