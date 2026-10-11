import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../state/profile.dart';
import '../../state/settings.dart';
import '../../widgets/glass.dart';

/// Bottom tab shell: Home · Library · Events · Social · Profile.
///
/// The tab bar is a floating glass capsule (iOS 26). The body extends under
/// it, so every tab's scroll view pads its end with
/// `MediaQuery.paddingOf(context).bottom`, which the Scaffold sets to the bar
/// height.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(settingsProvider).music) Sfx.instance.startMusic();
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final dailyReady = profile?.dailyAvailable ?? false;
    final tabs = [
      GlassTabItem(icon: CupertinoIcons.house, activeIcon: CupertinoIcons.house_fill, label: 'Home', badge: dailyReady),
      const GlassTabItem(icon: CupertinoIcons.square_grid_2x2, activeIcon: CupertinoIcons.square_grid_2x2_fill, label: 'Library'),
      const GlassTabItem(icon: CupertinoIcons.gift, activeIcon: CupertinoIcons.gift_fill, label: 'Events'),
      const GlassTabItem(icon: CupertinoIcons.person_2, activeIcon: CupertinoIcons.person_2_fill, label: 'Social'),
      const GlassTabItem(icon: CupertinoIcons.person_crop_circle, activeIcon: CupertinoIcons.person_crop_circle_fill, label: 'Profile'),
    ];
    return Scaffold(
      extendBody: true,
      body: widget.shell,
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
