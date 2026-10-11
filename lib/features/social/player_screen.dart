import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../state/achievements.dart';
import '../../state/auth.dart';
import '../../state/social.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../profile/stats.dart';

/// Read-only profile of another player: identity, headline numbers, the
/// public statistics and the achievement tiers they have claimed. Profiles
/// are public, so this works for league rows and friends alike; progress
/// rows are not, so the Statistics section shows the profile's aggregates
/// (the same widget as the own profile, minus the owner-only tiles).
class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final profile = ref.watch(playerProfileProvider(userId));
    final isMe = ref.watch(currentUserIdProvider) == userId;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('Player'),
        leading: Padding(padding: const EdgeInsets.only(left: 12), child: RoundIconButton(icon: CupertinoIcons.back, size: 38, onTap: () => context.pop())),
      ),
      body: profile.when(
        loading: () => const Loader(),
        error: (e, _) => const EmptyState(icon: AppIcons.signal, title: 'Profile could not load', message: 'Check your connection and try again.'),
        data: (p) {
          if (p == null) return const EmptyState(icon: AppIcons.profile, title: 'Player not found', message: 'This player may have deleted their account.');
          final claimed = <({AchievementFamily family, int tier})>[
            for (final f in achievementFamilies)
              for (var i = f.steps.length; i >= 1; i--)
                if (p.claimedAchievements.contains('${f.id}:$i')) ...[(family: f, tier: i)],
          ];
          // One entry per family: its highest claimed tier.
          final badges = <String, ({AchievementFamily family, int tier})>{};
          for (final b in claimed) {
            badges.putIfAbsent(b.family.id, () => b);
          }
          final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, top + 12, 20, MediaQuery.paddingOf(context).bottom + 28),
            children: [
              SoftCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        AvatarCircle(avatarKey: p.avatar, size: 72, border: true),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(isMe ? '${p.displayName} (you)' : p.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text('Level ${p.level}', style: TextStyle(color: c.textSecondary, fontSize: 12.5)),
                                  if (p.isVip) ...[
                                    const SizedBox(width: 8),
                                    Chip2(label: 'VIP', icon: AppIcons.vip, color: c.accentTint, foreground: context.accent),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Text('LV ${p.level}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                  const SizedBox(width: 8),
                                  Expanded(child: ProgressBar(value: p.levelProgress, height: 6)),
                                  const SizedBox(width: 8),
                                  Text('${p.xp} XP', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _BigStat(icon: AppIcons.puzzle, value: '${p.puzzlesCompleted}', label: 'Solved'),
                  const SizedBox(width: 12),
                  _BigStat(icon: AppIcons.star, iconColor: Brand.star, value: '${p.totalStars}', label: 'Stars'),
                  const SizedBox(width: 12),
                  _BigStat(icon: AppIcons.level, value: '${badges.length}', label: 'Badges'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _BigStat(icon: AppIcons.streak, value: '${p.streak}', label: 'Streak'),
                  const SizedBox(width: 12),
                  _BigStat(icon: AppIcons.streak, value: '${p.longestStreak}', label: 'Longest streak'),
                  const SizedBox(width: 12),
                  _BigStat(icon: AppIcons.xp, value: '${p.xp}', label: 'XP'),
                ],
              ),
              SectionHeader(
                padding: const EdgeInsets.fromLTRB(0, 28, 0, 12),
                title: 'Statistics',
                subtitle: isMe ? 'Everything you have played so far' : 'Everything ${p.displayName} has played so far',
              ),
              StatisticsSection(stats: isMe ? ref.watch(playerStatsProvider) : PlayerStats.fromProfile(p)),
              SectionHeader(padding: const EdgeInsets.fromLTRB(0, 28, 0, 12), title: 'Achievements', subtitle: badges.isEmpty ? 'Nothing claimed yet' : '${badges.length} of ${achievementFamilies.length} families claimed'),
              if (badges.isEmpty)
                const EmptyState(icon: AppIcons.level, title: 'No badges yet', message: 'Claimed achievement tiers show up here.')
              else
                GridView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.92),
                  itemCount: badges.length,
                  itemBuilder: (_, i) {
                    final b = badges.values.elementAt(i);
                    return _BadgeTile(family: b.family, tier: b.tier);
                  },
                ),
            ],
          );
        },
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
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        child: Column(
          children: [
            Icon(icon, size: 22, color: iconColor ?? context.accent),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.family, required this.tier});
  final AchievementFamily family;
  final int tier;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final step = family.steps[tier - 1];
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (step.avatarKey != null)
            AvatarCircle(avatarKey: step.avatarKey, size: 40)
          else
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(shape: BoxShape.circle, color: c.accentTint),
              child: Icon(family.icon, size: 20, color: context.accent),
            ),
          const SizedBox(height: 8),
          Text(family.title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
          const SizedBox(height: 2),
          Text(family.steps.length > 1 ? 'Tier $tier of ${family.steps.length}' : family.describe(step.threshold), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: c.textSecondary)),
        ],
      ),
    );
  }
}
