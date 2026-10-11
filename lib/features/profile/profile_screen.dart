import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../game/game_controller.dart' show formatDuration;
import '../../game/modes.dart';
import '../../models/models.dart';
import '../../state/achievements.dart';
import '../../state/auth.dart';
import '../../state/profile.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import 'avatar_picker.dart';
import 'stats.dart';

/// Profile: identity, stats, achievements and shortcuts.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final profile = ref.watch(profileProvider).value;
    final user = ref.watch(authProvider).value;
    final isGuest = ref.watch(isGuestProvider);
    if (profile == null) return const Scaffold(body: Loader());
    final achievements = ref.watch(achievementsProvider);
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
                                  Text('${profile.xpIntoLevel}/${Profile.xpForLevel(profile.level)}', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
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
                    Row(
                      children: [
                        _Stat(value: '${profile.coins}', label: 'Coins', icon: const CoinIcon(size: 14)),
                        _Stat(value: '${profile.tickets}', label: 'Tickets', icon: const TicketIcon(size: 13)),
                        _Stat(value: '${profile.hints}', label: 'Hints', icon: const HintIcon(size: 14)),
                        _Stat(value: '${profile.streak}', label: 'Streak', icon: Icon(AppIcons.streak, size: 15, color: c.textSecondary)),
                      ],
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
                child: BigButton(label: 'Save progress · create account', icon: AppIcons.save, onTap: () => context.go('/profile/account')),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  _BigStat(icon: AppIcons.puzzle, value: '${profile.puzzlesCompleted}', label: 'Solved'),
                  const SizedBox(width: 12),
                  _BigStat(icon: AppIcons.star, iconColor: Brand.star, value: '${profile.totalStars}', label: 'Stars'),
                  const SizedBox(width: 12),
                  _BigStat(icon: AppIcons.level, value: '$claimedSteps', label: 'Badges'),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SectionHeader(title: 'Statistics', subtitle: 'Everything you have played so far')),
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: _Statistics())),
          SliverToBoxAdapter(
            child: SectionHeader(
              title: 'Achievements',
              subtitle: readyToClaim > 0 ? '$claimedSteps of $totalSteps claimed · $readyToClaim ready' : '$claimedSteps of $totalSteps claimed',
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.separated(
              itemCount: achievements.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _AchievementCard(status: achievements[i]).animate().fadeIn(delay: (25 * i).ms),
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
                    ListRow(icon: AppIcons.profile, title: 'Account', subtitle: isGuest ? 'Guest · sign in to save progress' : 'Signed in', onTap: () => context.go('/profile/account')),
                    Divider(height: 1, color: c.stroke, indent: 62),
                    ListRow(icon: CupertinoIcons.bag_fill, title: 'Store', subtitle: 'Coins, Tickets, Hints and VIP', onTap: () => context.push('/store')),
                    Divider(height: 1, color: c.stroke, indent: 62),
                    ListRow(icon: CupertinoIcons.gear_alt_fill, title: 'Settings', subtitle: 'Theme, sound, haptics', onTap: () => context.go('/profile/settings')),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 28)),
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
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
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

class _BigStat extends StatelessWidget {
  const _BigStat({required this.icon, required this.value, required this.label, this.iconColor});
  final IconData icon;
  final Color? iconColor;
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: SoftCard(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Icon(icon, size: 22, color: iconColor ?? context.accent),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            Text(label, style: TextStyle(fontSize: 11, color: c.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Two-column grid of small stat tiles plus a per-mode table.
class _Statistics extends ConsumerWidget {
  const _Statistics();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(playerStatsProvider);
    final tiles = <(IconData, Color?, String, String)>[
      (AppIcons.puzzle, null, '${s.solved}', 'Puzzles solved'),
      (AppIcons.star, Brand.star, '${s.perfect}', '3-star solves'),
      (AppIcons.star, Brand.star, '${s.stars}', 'Stars collected'),
      (AppIcons.streak, null, '${s.streak}', 'Current streak'),
      (AppIcons.streak, null, '${s.longestStreak}', 'Longest streak'),
      (AppIcons.level, null, 'LV ${s.level}', '${s.xp} XP'),
      (AppIcons.swaps, null, _n(s.moves), 'Moves made'),
      (AppIcons.time, null, formatPlayTime(s.seconds), 'Time played'),
      (AppIcons.hint, Brand.hint, '${s.hints}', 'Hints used'),
      (AppIcons.peek, null, '${s.peeks}', 'Peeks used'),
      (AppIcons.magic, null, '${s.magic}', 'Magic used'),
      (AppIcons.library, null, '${s.packsCompleted}/${s.packsTotal}', 'Packs completed'),
      (AppIcons.events, null, '${s.eventsCompleted}', 'Events completed'),
    ];
    return Column(
      children: [
        GridView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 64),
          itemCount: tiles.length,
          itemBuilder: (_, i) {
            final t = tiles[i];
            return SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: c.boardBackground),
                    child: Icon(t.$1, size: 17, color: t.$2 ?? context.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: -0.3)),
                        Text(t.$4, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        SoftCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('By mode', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                  Text('Solved · Best time', style: TextStyle(fontSize: 11, color: c.textTertiary, fontWeight: FontWeight.w500)),
                ],
              ),
              const SizedBox(height: 4),
              for (final m in GameMode.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(_modeIcon(m), size: 16, color: c.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(m.label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500))),
                      Text('${s.solvedByMode[m] ?? 0}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      SizedBox(
                        width: 72,
                        child: Text(
                          s.bestSecondsByMode[m] == null ? '—' : formatDuration(s.bestSecondsByMode[m]!),
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.textSecondary, fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static IconData _modeIcon(GameMode m) => switch (m) {
        GameMode.cards => Icons.style_rounded,
        GameMode.squares => Icons.grid_view_rounded,
        GameMode.triangles => Icons.change_history_rounded,
        GameMode.hexagons => Icons.hexagon_rounded,
      };

  /// Thousands separator for big counters.
  static String _n(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

class _AchievementCard extends ConsumerWidget {
  const _AchievementCard({required this.status});
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
                Row(
                  children: [
                    Expanded(child: Text(f.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                    if (f.steps.length > 1)
                      Text('${status.claimedSteps}/${f.steps.length}', style: TextStyle(fontSize: 11.5, color: c.textTertiary, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(all ? 'All tiers claimed' : status.description, style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: ProgressBar(value: ratio, height: 6, color: all ? Brand.success : null)),
                    const SizedBox(width: 8),
                    Text(all ? 'Done' : '${status.progress.clamp(0, status.target)}/${status.target}', style: TextStyle(fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (all)
            const Icon(CupertinoIcons.checkmark_circle_fill, color: Brand.success, size: 22)
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (step!.avatarKey != null) ...[AvatarCircle(avatarKey: step.avatarKey, size: 22), const SizedBox(width: 6)],
                    if (step.coins > 0) Amount(currency: Currency.coins, value: step.coins, size: 13, fontSize: 12, weight: FontWeight.w600),
                    if (step.tickets > 0) ...[const SizedBox(width: 6), Amount(currency: Currency.tickets, value: step.tickets, size: 13, fontSize: 12, weight: FontWeight.w600)],
                  ],
                ),
                if (done) ...[
                  const SizedBox(height: 6),
                  BigButton(label: 'Claim', height: 34, expand: false, onTap: () => _claim(context, ref)),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
