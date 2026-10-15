import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
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
  Widget build(BuildContext context, WidgetRef ref) => ChromeText(child: Builder(builder: (context) => _build(context, ref)));

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
