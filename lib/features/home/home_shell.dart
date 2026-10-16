import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../state/achievements.dart';
import '../../state/first_steps.dart';
import '../../state/inbox.dart';
import '../../state/profile.dart';
import '../../state/review_prompt.dart';
import '../../state/settings.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../events/quest_rewards.dart';
import 'guided_start.dart';
import 'header_bar.dart';

/// Bottom tab shell: Home · Library · Quests · Social · Profile. On an expanded window (the web
/// on a desktop) the tabs move to [WideTopBar] at the top of the window.
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
      showToast(context, 'VIP weekly bonus: ${formatCount(paid)} coins', leading: const CoinIcon(size: 20));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    if (!_vipBonusChecked && profile != null && profile.isVip) {
      _vipBonusChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _payVipBonus());
    }
    // The guided start (lib/state/first_steps.dart): tabs and dots join as they open, and a tab
    // that just opened keeps a dot until it is visited.
    final open = ref.watch(revealsProvider);
    final newTabs = ref.watch(newTabsProvider);
    final current = widget.shell.currentIndex;
    if (newTabs.contains(current)) {
      final r = Reveal.values.firstWhere((r) => r.tab == current);
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(firstStepsProvider.notifier).sawTip('tab:${r.name}'));
    }
    final dailyReady = open.contains(Reveal.streak) && (profile?.dailyAvailable ?? false);
    // Profile dot: an achievement reward is waiting to be claimed.
    final rewardReady = open.contains(Reveal.achievements) && ref.watch(achievementsProvider.select((list) => list.any((a) => a.done)));
    // Quests dot: a quest or live event reward is waiting to be claimed.
    final questReady = ref.watch(questRewardReadyProvider) || newTabs.contains(Reveal.quests.tab);
    // Social dot: a message in the inbox not opened yet.
    final inboxNew = ref.watch(inboxUnseenProvider) || newTabs.contains(Reveal.social.tab);
    String? lockedUntil(Reveal r) => open.contains(r) ? null : 'opens ${r.when}';
    // Asks for an App Store rating after a happy moment (rules in ReviewRules).
    ref.watch(reviewPromptProvider);
    final tabs = [
      GlassTabItem(icon: AppIcons.house, activeIcon: AppIcons.home, label: 'Home', badge: dailyReady),
      const GlassTabItem(icon: AppIcons.squareGrid2x2, activeIcon: AppIcons.library, label: 'Library'),
      GlassTabItem(icon: AppIcons.questsOutline, activeIcon: AppIcons.quests, label: 'Quests', badge: questReady, locked: lockedUntil(Reveal.quests)),
      GlassTabItem(icon: AppIcons.person2, activeIcon: AppIcons.social, label: 'Social', badge: inboxNew, locked: lockedUntil(Reveal.social)),
      GlassTabItem(icon: AppIcons.personCropCircle, activeIcon: AppIcons.profile, label: 'Profile', badge: rewardReady),
    ];
    Future<void> select(int i) async {
      Haptics.selection();
      // A tab the guided start keeps back says when it opens, and can open now.
      final reveal = Reveal.values.where((r) => r.tab == i).firstOrNull;
      if (reveal != null && !open.contains(reveal) && i != widget.shell.currentIndex) {
        if (!await askUnlockEarly(context, ref, reveal)) return;
      }
      widget.shell.goBranch(i, initialLocation: i == widget.shell.currentIndex);
    }

    // The website layout (the web on a desktop): the tabs in a top bar across the window, the
    // pages under it, nothing floating over the bottom of the page.
    if (context.isExpanded) {
      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: WideTopBar(items: tabs, currentIndex: widget.shell.currentIndex, onTap: select),
        body: widget.shell,
      );
    }
    return Scaffold(
      extendBody: true,
      body: GlassTabBarScope(child: widget.shell),
      bottomNavigationBar: GlassTabBar(items: tabs, currentIndex: widget.shell.currentIndex, onTap: select),
    );
  }
}
