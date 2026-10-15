import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../data/purchases.dart' show groupThousands;
import '../../models/models.dart';
import '../../state/achievements.dart';
import '../../state/auth.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import 'achievement_order.dart';
import 'avatar_picker.dart';
import 'stats.dart';

/// Profile: identity, stats, achievements and shortcuts.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// Achievement order, fixed while the player is on the screen so a card
  /// never moves under the finger after a claim. Recomputed when the page
  /// comes back into view: another tab or a page pushed on top hides it,
  /// which turns its tickers off.
  List<String>? _achievementOrder;
  bool _visible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_visible) _achievementOrder = null;
    _visible = visible;
  }

  /// The live statuses in the frozen order. The order is only fixed once the
  /// progress rows have settled, so it is not taken from an empty save.
  List<AchievementStatus> _orderedAchievements(List<AchievementStatus> live) {
    final order = _achievementOrder ?? achievementOrder(live);
    final rows = ref.read(progressProvider);
    if (_achievementOrder == null && (rows.hasValue || rows.hasError)) _achievementOrder = order;
    return applyAchievementOrder(live, order);
  }

  Future<void> _editName(BuildContext context, WidgetRef ref, Profile p) async {
    final controller = TextEditingController(text: p.displayName);
    final c = context.colors;
    final ok = await showAppAlert(
      context,
      title: 'Your name',
      confirmLabel: 'Save',
      canConfirm: () => controller.text.trim().isNotEmpty,
      child: CupertinoTextField(
        controller: controller,
        autofocus: true,
        maxLength: 20,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.textPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: c.boardBackground, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.stroke)),
      ),
    );
    final name = ok ? controller.text.trim() : null;
    if (name == null || name.isEmpty) return;
    await ref.read(profileProvider.notifier).setIdentity(name: name);
    try {
      await ref.read(authProvider.notifier).updateName(name);
    } catch (_) {}
  }

  /// Every statistic (boosters, packs, events, quests, best times by mode) in a tall sheet.
  void _showAllStatistics(BuildContext context) {
    showAppSheet(
      context,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.86,
        child: Consumer(
          builder: (ctx, ref, _) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            physics: const BouncingScrollPhysics(),
            children: [
              const SheetHeader(title: 'Statistics', subtitle: 'Everything you have played so far'),
              const SizedBox(height: 14),
              StatisticsSection(stats: ref.watch(playerStatsProvider)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final profile = ref.watch(profileProvider).value;
    final user = ref.watch(authProvider).value;
    final isGuest = ref.watch(isGuestProvider);
    if (profile == null) return const Scaffold(body: Loader());
    final achievements = _orderedAchievements(ref.watch(achievementsProvider));
    final totalSteps = achievements.fold<int>(0, (s, a) => s + a.family.steps.length);
    final claimedSteps = achievements.fold<int>(0, (s, a) => s + a.claimedSteps);
    final readyToClaim = achievements.where((a) => a.done).length;

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          GlassSliverHeader(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                children: [
                  Expanded(child: Text('Profile', style: Theme.of(context).textTheme.headlineLarge)),
                  RoundIconButton(icon: CupertinoIcons.gear_alt_fill, onTap: () => context.go('/profile/settings')),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: SoftCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Pressable(
                          onTap: () => showAvatarPicker(context),
                          child: AvatarCircle(avatarKey: profile.avatar, size: 72, border: true),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Pressable(
                                onTap: () => _editName(context, ref, profile),
                                child: Row(
                                  children: [
                                    Flexible(child: Text(profile.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall)),
                                    const SizedBox(width: 6),
                                    Icon(CupertinoIcons.pencil, color: c.textTertiary, size: 16),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Flexible(child: Text(isGuest ? 'Guest account' : (user?.email ?? ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontSize: 12.5))),
                                  if (profile.isVip) ...[
                                    const SizedBox(width: 8),
                                    Chip2(label: 'VIP', icon: AppIcons.vip, color: c.accentTint, foreground: context.accent),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Text('LV ${profile.level}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                  const SizedBox(width: 8),
                                  Expanded(child: ProgressBar(value: profile.levelProgress, height: 6)),
                                  const SizedBox(width: 8),
                                  Text('${groupThousands(profile.xpIntoLevel)}/${groupThousands(Profile.xpForLevel(profile.level))}', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Divider(height: 1, color: c.stroke),
                    const SizedBox(height: 12),
                    // The wallet: three columns split by hairlines. The streak lives in Statistics
                    // (and on Home), so each balance gets a third of the card at full size.
                    IntrinsicHeight(
                      child: Row(
                        children: [
                          _Stat(value: groupThousands(profile.coins), label: 'Coins', icon: const CoinIcon(size: 14)),
                          VerticalDivider(width: 1, thickness: 1, color: c.stroke),
                          _Stat(value: groupThousands(profile.tickets), label: 'Tickets', icon: const TicketIcon(size: 13)),
                          VerticalDivider(width: 1, thickness: 1, color: c.stroke),
                          _Stat(value: groupThousands(profile.hints), label: 'Hints', icon: const HintIcon(size: 14)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isGuest)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: BigButton(label: 'Save progress · create account', icon: AppIcons.save, onTap: () => context.push('/account')),
              ),
            ),
          SliverToBoxAdapter(child: SectionHeader(title: 'Statistics', action: 'See all', onAction: () => _showAllStatistics(context))),
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: StatisticsSection(stats: ref.watch(playerStatsProvider), compact: true))),
          SliverToBoxAdapter(
            child: SectionHeader(
              title: 'Achievements',
              subtitle: readyToClaim > 0 ? '$claimedSteps of $totalSteps claimed · $readyToClaim ready' : '$claimedSteps of $totalSteps claimed',
            ),
          ),
          if (readyToClaim > 1)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: _ClaimAllCard(ready: [for (final a in achievements) if (a.done) a]),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.separated(
              itemCount: achievements.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _AchievementCard(key: ValueKey(achievements[i].family.id), status: achievements[i]),
            ),
          ),
          const SliverToBoxAdapter(child: SectionHeader(title: 'More')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SoftCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListRow(icon: AppIcons.photo, title: 'My Puzzles', subtitle: 'Create puzzles from your photos', onTap: () => context.go('/profile/my-puzzles')),
                    Divider(height: 1, color: c.stroke, indent: 62),
                    ListRow(icon: AppIcons.profile, title: 'Account', subtitle: isGuest ? 'Guest · sign in to save progress' : 'Signed in', onTap: () => context.push('/account')),
                    Divider(height: 1, color: c.stroke, indent: 62),
                    ListRow(icon: CupertinoIcons.bag_fill, title: 'Store', subtitle: 'Coins, Tickets, Hints and VIP', onTap: () => context.push('/store')),
                    Divider(height: 1, color: c.stroke, indent: 62),
                    ListRow(icon: CupertinoIcons.gear_alt_fill, title: 'Settings', subtitle: 'Theme, sound, haptics', onTap: () => context.go('/profile/settings')),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: GlassTabBar.scrollEndPadding(context))),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.icon});
  final String value;
  final String label;
  final Widget icon;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: Column(
        children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: -0.3))),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}

/// "12 rewards ready": what the ready tiers pay together, and one button that claims them all
/// (including the next tiers they unlock that are already reached).
class _ClaimAllCard extends ConsumerStatefulWidget {
  const _ClaimAllCard({required this.ready});
  final List<AchievementStatus> ready;
  @override
  ConsumerState<_ClaimAllCard> createState() => _ClaimAllCardState();
}

class _ClaimAllCardState extends ConsumerState<_ClaimAllCard> {
  bool _busy = false;

  Future<void> _claimAll() async {
    setState(() => _busy = true);
    final notifier = ref.read(profileProvider.notifier);
    var coins = 0, tickets = 0, avatars = 0, count = 0;
    // Claiming a tier can make the next tier ready too: keep going until none is left.
    for (var guard = 0; guard < 200; guard++) {
      final next = ref.read(achievementsProvider).where((a) => a.done).firstOrNull;
      final step = next?.step;
      if (next == null || step == null) break;
      final ok = await notifier.claimAchievement(next.stepKey, coins: step.coins, tickets: step.tickets, avatar: step.avatarKey);
      if (!ok) break;
      count++;
      coins += step.coins;
      tickets += step.tickets;
      if (step.avatarKey != null) avatars++;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (count == 0) return;
    Sfx.instance.coin();
    Haptics.success();
    final parts = [
      if (coins > 0) '${groupThousands(coins)} coins',
      if (tickets > 0) '$tickets ticket${tickets == 1 ? '' : 's'}',
      if (avatars > 0) '$avatars avatar${avatars == 1 ? '' : 's'}',
    ];
    showToast(context, '$count rewards claimed: ${parts.join(', ')}', icon: AppIcons.check);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    var coins = 0, tickets = 0, avatars = 0;
    for (final a in widget.ready) {
      coins += a.step?.coins ?? 0;
      tickets += a.step?.tickets ?? 0;
      if (a.step?.avatarKey != null) avatars++;
    }
    return SoftCard(
      color: c.accentTint,
      border: false,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${widget.ready.length} rewards ready', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (coins > 0) Amount(currency: Currency.coins, value: groupThousands(coins), size: 14, fontSize: 13, weight: FontWeight.w600),
                    if (tickets > 0) Amount(currency: Currency.tickets, value: tickets, size: 14, fontSize: 13, weight: FontWeight.w600),
                    if (avatars > 0) Text('$avatars avatar${avatars == 1 ? '' : 's'}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          BigButton(label: 'Claim all', height: 40, expand: false, loading: _busy, onTap: _claimAll),
        ],
      ),
    );
  }
}

class _AchievementCard extends ConsumerWidget {
  const _AchievementCard({super.key, required this.status});
  final AchievementStatus status;

  Future<void> _claim(BuildContext context, WidgetRef ref) async {
    final step = status.step;
    if (step == null) return;
    final ok = await ref.read(profileProvider.notifier).claimAchievement(status.stepKey, coins: step.coins, tickets: step.tickets, avatar: step.avatarKey);
    if (!ok || !context.mounted) return;
    Sfx.instance.coin();
    Haptics.success();
    showToast(context, step.avatarKey != null ? 'New avatar unlocked' : 'Reward claimed', icon: AppIcons.check);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final f = status.family;
    final step = status.step;
    final all = status.allClaimed;
    final done = status.done;
    final ratio = all ? 1.0 : (status.progress / status.target).clamp(0.0, 1.0);
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(shape: BoxShape.circle, color: (all || done) ? c.accentTint : c.boardBackground),
            child: Icon(f.icon, size: 22, color: (all || done) ? context.accent : c.textTertiary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The title, then one dot per tier (filled once claimed) instead of a second fraction.
                Row(
                  children: [
                    Flexible(child: Text(f.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                    if (f.steps.length > 1) ...[const SizedBox(width: 8), _TierDots(claimed: status.claimedSteps, total: f.steps.length)],
                  ],
                ),
                const SizedBox(height: 2),
                Text(all ? 'Every tier claimed' : status.description, style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
                // A ready tier needs no full bar next to its Claim button.
                if (!done) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: ProgressBar(value: ratio, height: 6, color: all ? Brand.success : null)),
                    const SizedBox(width: 8),
                    Text(
                      all ? 'Done' : '${groupThousands(status.progress.clamp(0, status.target))} / ${groupThousands(status.target)}',
                      style: TextStyle(fontSize: 11.5, color: c.textSecondary, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ],
                ),
                ],
                if (!all) ...[
                  const SizedBox(height: 8),
                  // What the next tier pays, as one quiet line (wraps when space is short).
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Reward', style: TextStyle(fontSize: 11.5, color: c.textTertiary, fontWeight: FontWeight.w500)),
                      if (step!.coins > 0) Amount(currency: Currency.coins, value: groupThousands(step.coins), size: 13, fontSize: 12, weight: FontWeight.w600),
                      if (step.tickets > 0) Amount(currency: Currency.tickets, value: step.tickets, size: 13, fontSize: 12, weight: FontWeight.w600),
                      if (step.avatarKey != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AvatarCircle(avatarKey: step.avatarKey, size: 16),
                            const SizedBox(width: 4),
                            Text('Avatar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textPrimary)),
                          ],
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (all) ...[
            const SizedBox(width: 12),
            const Icon(CupertinoIcons.checkmark_circle_fill, color: Brand.success, size: 22),
          ] else if (done) ...[
            const SizedBox(width: 12),
            BigButton(label: 'Claim', height: 34, expand: false, onTap: () => _claim(context, ref)),
          ],
        ],
      ),
    );
  }
}

/// One small dot per tier of an achievement, filled for the tiers already claimed.
class _TierDots extends StatelessWidget {
  const _TierDots({required this.claimed, required this.total});
  final int claimed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Tier ${claimed.clamp(0, total)} of $total claimed',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(shape: BoxShape.circle, color: i < claimed ? context.accent : c.stroke),
            ),
        ],
      ),
    );
  }
}
