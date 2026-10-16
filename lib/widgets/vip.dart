import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import 'icons.dart';

/// The VIP look, one family wherever VIP is shown: the Home banner, the Store's plan picker and
/// a member's card. An ink card with gold marks: near-black on the light page; on the dark page
/// the elevated card colour with a gold hairline, so it still stands off the black canvas.
/// Text on it is white ([Vip.fg], [Vip.fgSecondary]); gold is kept for the crown, the selected
/// plan and the one gold button.
class Vip {
  Vip._();

  static const fg = Colors.white;
  static Color get fgSecondary => Colors.white.withValues(alpha: 0.72);
  static Color get fgTertiary => Colors.white.withValues(alpha: 0.5);

  /// [fgTertiary], stronger with Settings > Accessibility > Increase contrast.
  static Color fgTertiaryOf(BuildContext context) => context.highContrast ? Colors.white.withValues(alpha: 0.62) : fgTertiary;

  /// Hairlines and quiet outlines on the card (unselected plans, dividers).
  static Color get line => Colors.white.withValues(alpha: 0.16);

  /// [line], stronger with Increase contrast.
  static Color lineOf(BuildContext context) => context.highContrast ? Colors.white.withValues(alpha: 0.42) : line;

  /// The gold of the crown, the selected plan and the gold button.
  static const gold = Brand.coin;

  /// The card's fill.
  static Color ink(BuildContext context) => context.isDark ? context.colors.cardElevated : const Color(0xFF16161C);
}

/// The VIP card surface ([Vip]): the ink fill, the large radius, and in dark mode a gold hairline.
class VipSurface extends StatelessWidget {
  const VipSurface({super.key, required this.child, this.padding = Insets.card});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Vip.ink(context),
          borderRadius: BorderRadius.circular(Radii.lg),
          border: context.isDark ? Border.all(color: Vip.gold.withValues(alpha: 0.28)) : null,
        ),
        child: child,
      );
}

/// The gold crown on a faint white tile, the mark that leads every VIP card.
class VipCrown extends StatelessWidget {
  const VipCrown({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(size * 0.3)),
        child: Icon(AppIcons.vip, color: Vip.gold, size: size * 0.55),
      );
}
