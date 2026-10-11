import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../state/profile.dart';
import '../../state/settings.dart';

/// Bottom tab shell: Home · Library · Events · Social · Profile.
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
    final c = context.colors;
    final profile = ref.watch(profileProvider).value;
    final dailyReady = profile?.dailyAvailable ?? false;
    final tabs = [
      (CupertinoIcons.house, CupertinoIcons.house_fill, 'Home', dailyReady),
      (CupertinoIcons.square_grid_2x2, CupertinoIcons.square_grid_2x2_fill, 'Library', false),
      (CupertinoIcons.gift, CupertinoIcons.gift_fill, 'Events', false),
      (CupertinoIcons.person_2, CupertinoIcons.person_2_fill, 'Social', false),
      (CupertinoIcons.person_crop_circle, CupertinoIcons.person_crop_circle_fill, 'Profile', false),
    ];
    return Scaffold(
      body: widget.shell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: c.card, border: Border(top: BorderSide(color: c.stroke))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: _TabButton(
                      icon: tabs[i].$1,
                      activeIcon: tabs[i].$2,
                      label: tabs[i].$3,
                      badge: tabs[i].$4,
                      selected: widget.shell.currentIndex == i,
                      onTap: () {
                        Haptics.selection();
                        widget.shell.goBranch(i, initialLocation: i == widget.shell.currentIndex);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.icon, required this.activeIcon, required this.label, required this.selected, required this.onTap, this.badge = false});
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final bool badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = selected ? context.accent : c.textTertiary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(selected ? activeIcon : icon, color: color, size: 23),
              if (badge)
                Positioned(
                  right: -4,
                  top: -2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: Brand.live, shape: BoxShape.circle, border: Border.all(color: c.card, width: 1.5)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
