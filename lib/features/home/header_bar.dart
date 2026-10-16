import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../state/profile.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// Top bar shared by tabs: the avatar inside a ring that fills with the level's XP (the level
/// number in a badge on the ring) on the left, tickets and coins on the right. As a sliver it
/// stays pinned and turns to glass once the page scrolls under it; `sliver: false` gives a plain
/// box for non-scrolling layouts.
class HeaderBar extends ConsumerWidget {
  const HeaderBar({super.key, required this.title, this.sliver = true});
  final String title;
  final bool sliver;

  /// Content height below the status bar.
  static const double height = 50;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The website layout shows the avatar and the balances in the window's top bar
    // ([WideTopBar]); the page only keeps the room under it.
    if (context.isExpanded) {
      final space = SizedBox(height: MediaQuery.paddingOf(context).top);
      return sliver ? SliverToBoxAdapter(child: space) : space;
    }
    return ChromeText(child: Builder(builder: (context) => _build(context, ref)));
  }

  Widget _build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final level = profile?.level ?? 1;
    final row = Padding(
      // The row is 44 pt high (the pills' touch boxes); the bar keeps its 50 pt height. The level
      // badge hangs below the ring, so the row sits 1 pt above the bar's middle and the badge
      // stays 2 pt clear of the bar's bottom edge.
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
      child: Row(
        children: [
          Pressable(
            onTap: () => context.go('/profile'),
            child: Semantics(
              button: true,
              label: 'Level $level, profile',
              child: TapTarget(child: LevelAvatar(avatar: profile?.avatar, level: level, progress: profile?.levelProgress ?? 0)),
            ),
          ),
          const Spacer(),
          // Balances from 100,000 are written short ("123K", "1.23M"), so the pills never push off
          // the screen; the exact numbers are in the Store.
          CurrencyPill(currency: Currency.tickets, value: profile?.tickets ?? 0, abbreviate: true, onAdd: () => context.push('/store')),
          const SizedBox(width: 8),
          CurrencyPill(currency: Currency.coins, value: profile?.coins ?? 0, abbreviate: true, onAdd: () => context.push('/store')),
        ],
      ),
    );
    if (!sliver) return SafeArea(bottom: false, child: SizedBox(height: height, child: row));
    return GlassSliverHeader(height: height, child: row);
  }
}

/// The player's avatar inside a ring that fills with the level's XP, the level number in a
/// small cobalt badge on the ring's lower edge: level and progress at a glance, in a third of
/// the width the "LV 5" label and bar took.
class LevelAvatar extends StatelessWidget {
  const LevelAvatar({super.key, required this.avatar, required this.level, required this.progress, this.size = 40});
  final String? avatar;
  final int level;

  /// XP into the level, 0..1.
  final double progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // The badge is cut out of what is behind it (the bar's canvas) by a ring of that colour.
    final cutout = c.canvas;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: progress.clamp(0, 1).toDouble()),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => CustomPaint(painter: _RingPainter(value: v, track: c.stroke, fill: context.accent)),
            ),
          ),
          AvatarCircle(avatarKey: avatar, size: size - 9),
          Positioned(
            bottom: -4,
            child: Container(
              height: 16,
              constraints: const BoxConstraints(minWidth: 20),
              padding: const EdgeInsets.symmetric(horizontal: 4.5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.accentFill,
                borderRadius: BorderRadius.circular(Radii.pill),
                border: Border.all(color: cutout, width: 1.5),
              ),
              child: Text(
                formatCount(level),
                style: TextStyle(color: context.onAccent, fontSize: TypeSize.micro, fontWeight: FontWeight.w700, height: 1.1, letterSpacing: -0.2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.track, required this.fill});
  final double value;
  final Color track;
  final Color fill;

  static const stroke = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(rect, 0, 2 * math.pi, false, Paint()..style = PaintingStyle.stroke..strokeWidth = stroke..color = track);
    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = fill,
    );
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.value != value || o.track != track || o.fill != fill;
}

/// The window's top bar in the website layout (expanded windows, the web on a desktop), in place
/// of the floating tab bar: the Carden mark on the left, the five tabs in a glass capsule in the
/// middle (the iPadOS 26 top tab bar), the balances and the avatar on the right. It spans the
/// window; its content lines up with the pages' content column.
class WideTopBar extends ConsumerWidget implements PreferredSizeWidget {
  const WideTopBar({super.key, required this.items, required this.currentIndex, required this.onTap});
  final List<GlassTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const double height = 68;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context, WidgetRef ref) => ChromeText(child: Builder(builder: (context) => _build(context, ref)));

  Widget _build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final profile = ref.watch(profileProvider).value;
    final level = profile?.level ?? 1;
    final inset = pageInsetOf(context) + 20;
    return GlassSurface(
      opacity: context.isDark ? 0.72 : 0.80,
      hairline: Border(bottom: BorderSide(color: c.stroke, width: 0.5)),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: NavigationToolbar(
              centerMiddle: true,
              middleSpacing: 16,
              leading: Semantics(
                button: true,
                label: 'Carden, home',
                child: Pressable(
                  onTap: () => onTap(0),
                  scale: 0.97,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), border: Border.all(color: c.stroke)),
                        child: Image.asset('assets/brand/mark.png', fit: BoxFit.cover, filterQuality: FilterQuality.medium),
                      ),
                      const SizedBox(width: 10),
                      Text('Carden', style: TextStyle(fontSize: TypeSize.title3, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: c.textPrimary)),
                    ],
                  ),
                ),
              ),
              middle: _TopTabs(items: items, currentIndex: currentIndex, onTap: onTap),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CurrencyPill(currency: Currency.tickets, value: profile?.tickets ?? 0, abbreviate: true, onAdd: () => context.push('/store')),
                  const SizedBox(width: 8),
                  CurrencyPill(currency: Currency.coins, value: profile?.coins ?? 0, abbreviate: true, onAdd: () => context.push('/store')),
                  const SizedBox(width: 12),
                  Pressable(
                    onTap: () => onTap(items.length - 1),
                    child: Semantics(
                      button: true,
                      label: 'Level $level, profile',
                      child: TapTarget(child: LevelAvatar(avatar: profile?.avatar, level: level, progress: profile?.levelProgress ?? 0)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tabs of [WideTopBar]: labels in a glass capsule, the selected one on a soft cobalt pill
/// (the floating tab bar's), a cobalt dot after a label whose tab has something waiting.
class _TopTabs extends StatelessWidget {
  const _TopTabs({required this.items, required this.currentIndex, required this.onTap});
  final List<GlassTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.pill),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(Radii.pill),
        opacity: isDark ? 0.7 : 0.9,
        hairline: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.06), width: 0.5),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < items.length; i++) _TopTab(item: items[i], selected: i == currentIndex, onTap: () => onTap(i)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopTab extends StatefulWidget {
  const _TopTab({required this.item, required this.selected, required this.onTap});
  final GlassTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TopTab> createState() => _TopTabState();
}

class _TopTabState extends State<_TopTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = context.isDark;
    final selected = widget.selected;
    final color = selected ? context.accent : (_hover ? c.textPrimary : c.textSecondary);
    final fill = selected ? context.accent.withValues(alpha: isDark ? 0.18 : 0.10) : (_hover ? c.textPrimary.withValues(alpha: 0.05) : Colors.transparent);
    return Semantics(
      button: true,
      selected: selected,
      label: widget.item.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(Radii.pill)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.item.label, style: TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w600, color: color, letterSpacing: -0.1)),
                // Something waits on that tab (as on the floating tab bar): a small cobalt dot.
                if (widget.item.badge && !selected) ...[
                  const SizedBox(width: 6),
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: context.accent, shape: BoxShape.circle)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
