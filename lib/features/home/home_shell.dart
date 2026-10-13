import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../data/purchases.dart';
import '../../state/achievements.dart';
import '../../state/profile.dart';
import '../../state/review_prompt.dart';
import '../../state/settings.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../events/quest_rewards.dart';

/// Bottom tab shell: Home · Library · Quests · Social · Profile.
///
/// The tab bar is a floating glass capsule (iOS 26). The body extends under
/// it, so every tab's scroll view (and every page pushed inside a tab) pads
/// its end with `GlassTabBar.scrollEndPadding(context)`, which clears the
/// bar; [GlassTabBarScope] marks the area the bar covers.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  bool _vipBonusChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(settingsProvider).music) Sfx.instance.startMusic();
    });
  }

  /// VIP members get their weekly bonus once a week when the app opens.
  Future<void> _payVipBonus() async {
    final paid = await ref.read(profileProvider.notifier).claimVipWeeklyBonus();
    if (paid > 0 && mounted) {
      Sfx.instance.coin();
      showToast(context, 'VIP weekly bonus: ${groupThousands(paid)} coins', leading: const CoinIcon(size: 20));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    if (!_vipBonusChecked && profile != null && profile.isVip) {
      _vipBonusChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _payVipBonus());
    }
    final dailyReady = profile?.dailyAvailable ?? false;
    // Profile dot: an achievement reward is waiting to be claimed.
    final rewardReady = ref.watch(achievementsProvider.select((list) => list.any((a) => a.done)));
    // Quests dot: a quest or live event reward is waiting to be claimed.
    final questReady = ref.watch(questRewardReadyProvider);
    // Asks for an App Store rating after a happy moment (rules in ReviewRules).
    ref.watch(reviewPromptProvider);
    final tabs = [
      GlassTabItem(icon: CupertinoIcons.house, activeIcon: CupertinoIcons.house_fill, label: 'Home', badge: dailyReady),
      const GlassTabItem(icon: CupertinoIcons.square_grid_2x2, activeIcon: CupertinoIcons.square_grid_2x2_fill, label: 'Library'),
      GlassTabItem(icon: AppIcons.questsOutline, activeIcon: AppIcons.quests, label: 'Quests', badge: questReady),
      const GlassTabItem(icon: CupertinoIcons.person_2, activeIcon: CupertinoIcons.person_2_fill, label: 'Social'),
      GlassTabItem(icon: CupertinoIcons.person_crop_circle, activeIcon: CupertinoIcons.person_crop_circle_fill, label: 'Profile', badge: rewardReady),
    ];
    return Scaffold(
      extendBody: true,
      body: GlassTabBarScope(child: widget.shell),
      bottomNavigationBar: GlassTabBar(
        items: tabs,
        currentIndex: widget.shell.currentIndex,
        onTap: (i) {
          Haptics.selection();
          widget.shell.goBranch(i, initialLocation: i == widget.shell.currentIndex);
        },
      ),
    );
  }
}
