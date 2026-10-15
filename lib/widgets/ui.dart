import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/haptics.dart';
import '../core/sfx.dart';
import '../core/theme/tokens.dart';
import 'cached_url_image.dart';
import 'glass.dart';
import 'hash_image.dart';
import 'icons.dart';

/// A tappable surface that scales down slightly while pressed (iOS-style).
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.97, this.haptic = true, this.sound = true});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final bool sound;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) Haptics.light();
              if (widget.sound) Sfx.instance.tap();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedOpacity(opacity: _down ? 0.85 : 1, duration: const Duration(milliseconds: 110), child: widget.child),
      ),
    );
  }
}

/// Flat surface card: 1px hairline, no shadow. The main container.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Spacing.lg),
    this.radius = Radii.lg,
    this.color,
    this.gradient,
    this.onTap,
    this.border = true,
    this.borderColor,
    this.margin,
    this.clip = Clip.antiAlias,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final bool border;

  /// Outline colour (the theme's stroke by default).
  final Color? borderColor;
  final EdgeInsetsGeometry? margin;
  final Clip clip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = Container(
      margin: margin,
      clipBehavior: clip,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? c.card) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: border && gradient == null ? Border.all(color: borderColor ?? c.stroke) : null,
      ),
      child: Padding(padding: padding, child: child),
    );
    return onTap == null ? card : Pressable(onTap: onTap, scale: 0.985, child: card);
  }
}

enum ButtonKind { primary, secondary, ghost, ghostLight, coral, gold, teal, dark }

/// The CTA button. Solid fills, no gradients.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    this.onTap,
    this.kind = ButtonKind.primary,
    this.icon,
    this.trailing,
    this.expand = true,
    this.height = 52,
    this.loading = false,
  })  : currency = null,
        amount = null,
        amountPrefix = '';

  /// A button for an action that costs or pays [currency]: the label is
  /// followed by the currency mark and the amount ("Open for [ticket] 1").
  /// The one style for every spend in the app: wheel spin, piggy bank, tier
  /// and pack unlocks, boosters.
  const BigButton.cost({
    super.key,
    required this.label,
    required Currency this.currency,
    required int this.amount,
    this.amountPrefix = '',
    this.onTap,
    this.kind = ButtonKind.primary,
    this.expand = true,
    this.height = 52,
    this.loading = false,
  })  : icon = null,
        trailing = null;

  final String label;
  final VoidCallback? onTap;
  final ButtonKind kind;
  final IconData? icon;
  final Widget? trailing;
  final bool expand;
  final double height;
  final bool loading;
  final Currency? currency;
  final int? amount;
  final String amountPrefix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final disabled = onTap == null;
    Color bg;
    Color fg = Colors.white;
    Border? border;
    switch (kind) {
      case ButtonKind.primary:
      case ButtonKind.coral:
      case ButtonKind.teal:
        bg = context.accent;
      case ButtonKind.gold:
        bg = Brand.coin;
        fg = const Color(0xFF2A1F00);
      case ButtonKind.dark:
        // Inverted surface: white on dark themes, ink on light ones, so the
        // label must be the opposite of the fill, not the theme's text colour.
        bg = context.isDark ? Colors.white : c.textPrimary;
        fg = context.isDark ? const Color(0xFF111827) : Colors.white;
      case ButtonKind.secondary:
        bg = c.accentTint;
        fg = context.accent;
      case ButtonKind.ghost:
        bg = Colors.transparent;
        fg = c.textPrimary;
        border = Border.all(color: c.stroke);
      case ButtonKind.ghostLight:
        // For always-dark surfaces such as the VIP card.
        bg = Colors.transparent;
        fg = Colors.white;
        border = Border.all(color: Colors.white.withValues(alpha: 0.45));
    }
    // On a filled button a ticket mark (in a cost label or a trailing
    // [Amount]) is drawn in the label colour, never teal on cobalt.
    final filled = bg != Colors.transparent;
    final Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
        else ...[
          if (icon != null) ...[Icon(icon, color: fg, size: 19), const SizedBox(width: 8)],
          if (currency != null)
            Flexible(child: CostLabel(label: label, currency: currency!, amount: amount!, prefix: amountPrefix, color: fg, fontSize: 16))
          else
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: fg))),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ],
    );
    return Pressable(
      onTap: loading ? null : onTap,
      child: Opacity(
        opacity: disabled ? 0.45 : 1,
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: expand ? 16 : 20),
          decoration: BoxDecoration(color: bg, border: border, borderRadius: BorderRadius.circular(Radii.md)),
          child: filled ? CurrencyInk(color: fg, child: content) : content,
        ),
      ),
    );
  }
}

/// "Label [currency mark] amount" for anything that costs or pays coins,
/// tickets or hints. Used inside [BigButton.cost]; also usable on its own in
/// rows and sheets so prices read the same everywhere.
class CostLabel extends StatelessWidget {
  const CostLabel({super.key, required this.label, required this.currency, required this.amount, this.prefix = '', this.color, this.fontSize = 15, this.iconSize});
  final String label;
  final Currency currency;
  final int amount;
  /// E.g. "+" for a payout.
  final String prefix;
  final Color? color;
  final double fontSize;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.colors.textPrimary;
    final mark = iconSize ?? fontSize * 1.15;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: fg))),
        SizedBox(width: fontSize * 0.5),
        currencyIcon(currency, size: mark, mono: fg.computeLuminance() > 0.8, monoColor: fg),
        SizedBox(width: fontSize * 0.3),
        Text('$prefix${AnimatedCounter._fmt(amount)}', style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: fg)),
      ],
    );
  }
}

/// Small round icon button (used in HUDs and headers).
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({super.key, required this.icon, this.onTap, this.size = 40, this.color, this.iconColor, this.badge, this.label});
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  final Color? iconColor;
  final String? badge;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color ?? c.card, shape: BoxShape.circle, border: Border.all(color: c.stroke)),
      child: Icon(icon, size: size * 0.48, color: iconColor ?? c.textPrimary),
    );
    Widget child = badge == null
        ? button
        : Stack(
            clipBehavior: Clip.none,
            children: [
              button,
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Brand.live, borderRadius: BorderRadius.circular(999)),
                  child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          );
    if (label != null) {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          const SizedBox(height: 4),
          Text(label!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.textSecondary)),
        ],
      );
    }
    return Pressable(onTap: onTap, scale: 0.9, child: child);
  }
}

/// Coins / tickets / hints pill shown in headers.
class CurrencyPill extends StatelessWidget {
  const CurrencyPill({super.key, required this.currency, required this.value, this.onAdd, this.color = Brand.coin, this.compact = false});
  final Currency currency;
  final int value;
  final VoidCallback? onAdd;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onAdd,
      scale: 0.95,
      child: Container(
        height: 34,
        padding: EdgeInsets.only(left: 9, right: onAdd != null ? 5 : 12),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: c.stroke)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            currencyIcon(currency, size: 16),
            const SizedBox(width: 6),
            AnimatedCounter(value: value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: compact ? 14 : 15, color: c.textPrimary, letterSpacing: -0.2)),
            if (onAdd != null) ...[
              const SizedBox(width: 6),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: c.accentTint, shape: BoxShape.circle),
                child: Icon(CupertinoIcons.plus, size: 13, color: context.accent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Number that counts up/down when changed.
class AnimatedCounter extends StatelessWidget {
  const AnimatedCounter({super.key, required this.value, this.style});
  final int value;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text(_fmt(v.round()), style: style),
    );
  }

  static String _fmt(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

/// Section title with optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.subtitle, this.action, this.onAction, this.trailing, this.padding = const EdgeInsets.fromLTRB(20, 28, 20, 12)});
  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;
  /// Widget on the right instead of the text [action] (e.g. a countdown chip).
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final titleText = Text(title, style: Theme.of(context).textTheme.headlineSmall);
    // A text action sits on the title's baseline, as iOS places "See All"; a trailing widget (a
    // countdown chip) stays aligned to the bottom of the title block.
    final Widget titleRow = action == null || trailing != null
        ? titleText
        : Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: titleText),
              const SizedBox(width: 12),
              Pressable(
                onTap: onAction,
                // No padding: it would move the title's baseline. The text plus the 12 pt gap is the target.
                child: Text(action!, style: TextStyle(color: context.accent, fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ],
          );
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleRow,
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: TextStyle(color: c.textSecondary, fontSize: 13)),
                ],
              ],
            ),
          ),
          if (trailing != null) Padding(padding: const EdgeInsets.only(bottom: 2), child: trailing!),
        ],
      ),
    );
  }
}

/// Frosted glass panel for overlays on top of imagery.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.radius = Radii.md, this.padding = const EdgeInsets.all(12), this.opacity = 0.55, this.dark = false});
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double opacity;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final base = dark ? Colors.black : (context.isDark ? const Color(0xFF17171C) : Colors.white);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: base.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.12 : 0.35)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Network image with a BlurHash (or shimmer) placeholder and rounded corners.
class NetImage extends StatelessWidget {
  const NetImage({super.key, required this.url, this.blurhash, this.fit = BoxFit.cover, this.radius = 0, this.width, this.height, this.alignment = Alignment.center});
  final String url;
  /// Compact BlurHash string; when present the blurred colours show instantly.
  final String? blurhash;
  final BoxFit fit;
  final double radius;
  final double? width;
  final double? height;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasHash = blurhash != null && blurhash!.length >= 6;
    Widget img = url.isEmpty
        ? Container(color: c.boardBackground)
        : Image(
            image: CachedUrlImage(url),
            fit: fit,
            width: width,
            height: height,
            alignment: alignment,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return Stack(
                fit: StackFit.passthrough,
                children: [
                  // A BlurHash is static, so it can stay under the picture;
                  // the animated shimmer goes away once the picture is in.
                  if (frame == null || hasHash) Positioned.fill(child: hasHash ? HashImage(hash: blurhash!, color: c.boardBackground) : const _Shimmer()),
                  AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 250), curve: Curves.easeOut, child: child),
                ],
              );
            },
            errorBuilder: (_, _, _) => SizedBox(
              width: width,
              height: height,
              child: hasHash
                  ? HashImage(hash: blurhash!, color: c.boardBackground)
                  : Container(color: c.boardBackground, child: Icon(CupertinoIcons.photo, color: c.textTertiary)),
            ),
          );
    if (radius > 0) img = ClipRRect(borderRadius: BorderRadius.circular(radius), child: img);
    return img;
  }
}

class _Shimmer extends StatefulWidget {
  const _Shimmer();
  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-1 + _c.value * 3, 0),
            end: Alignment(_c.value * 3, 0),
            colors: [c.boardBackground, c.stroke, c.boardBackground],
          ),
        ),
      ),
    );
  }
}

/// Star row for ratings (0-3).
class Stars extends StatelessWidget {
  const Stars({super.key, required this.count, this.size = 16, this.max = 3, this.animate = false});
  final int count;
  final double size;
  final int max;
  final bool animate;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < max; i++)
          Icon(i < count ? CupertinoIcons.star_fill : CupertinoIcons.star, size: size, color: i < count ? Brand.star : context.colors.textTertiary.withValues(alpha: 0.5)),
      ],
    );
  }
}

/// Rounded progress bar.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.height = 8, this.color, this.background, this.gradient});
  final double value;
  final double height;
  final Color? color;
  final Color? background;
  final Gradient? gradient;
  @override
  Widget build(BuildContext context) {
    final fill = color ?? context.accent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Container(color: background ?? context.colors.stroke),
            TweenAnimationBuilder<double>(
              tween: Tween(end: value.clamp(0, 1)),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => FractionallySizedBox(
                widthFactor: v,
                alignment: Alignment.centerLeft,
                child: Container(decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(height))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small label chip (category, status).
class Chip2 extends StatelessWidget {
  const Chip2({super.key, required this.label, this.icon, this.onImage = false, this.color, this.foreground});
  final String label;
  final IconData? icon;
  final bool onImage;
  final Color? color;
  final Color? foreground;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = color ?? (onImage ? Colors.black.withValues(alpha: 0.45) : c.canvas);
    final fg = foreground ?? (onImage ? Colors.white : c.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999), border: onImage || color != null ? null : Border.all(color: c.stroke)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Content-sized modal sheet in the iOS 26 style: glass surface, grabber,
/// light dim behind it, drag or tap outside to dismiss. For full-height
/// modals (Store, Wheel, Account) the router uses a CupertinoSheetRoute.
Future<T?> showAppSheet<T>(BuildContext context, {required WidgetBuilder builder, bool scrollable = false, bool dismissible = true}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // Root navigator: the sheet must cover the floating tab bar, which lives
    // above the tab shell's body.
    useRootNavigator: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    backgroundColor: Colors.transparent,
    elevation: 0,
    showDragHandle: false,
    shape: const RoundedRectangleBorder(),
    clipBehavior: Clip.none,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (ctx) => GlassSheet(
      grabber: dismissible,
      child: Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom), child: builder(ctx)),
    ),
  );
}

/// Root messenger; `CardJigsawApp` hosts a Scaffold above the Navigator for
/// it, so toasts float over every route, sheet barrier and the tab bar.
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

void showToast(BuildContext context, String message, {IconData? icon, Widget? leading}) {
  final messenger = appMessengerKey.currentState ?? ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  final fg = context.isDark ? context.colors.textPrimary : Colors.white;
  // Lift the toast 12pt above the floating tab bar (the host Scaffold is
  // above the tab shell, so the bar's slot is not in its insets).
  final safe = MediaQuery.viewPaddingOf(context).bottom;
  final lift = GlassTabBar.bottomGap(safe) + GlassTabBar.barHeight + 12 - safe;
  messenger.showSnackBar(SnackBar(
    margin: EdgeInsets.fromLTRB(16, 0, 16, lift),
    content: Row(
      children: [
        if (leading != null) ...[leading, const SizedBox(width: 10)] else if (icon != null) ...[Icon(icon, size: 20, color: fg), const SizedBox(width: 10)],
        Expanded(child: Text(message)),
      ],
    ),
    duration: const Duration(seconds: 2),
  ));
}

/// Empty-state placeholder.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: c.accentTint, shape: BoxShape.circle),
              child: Icon(icon, size: 30, color: context.accent),
            ),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary)),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Adaptive activity indicator.
class Loader extends StatelessWidget {
  const Loader({super.key, this.size = 28});
  final double size;
  @override
  Widget build(BuildContext context) => Center(child: SizedBox(width: size, height: size, child: const CupertinoActivityIndicator()));
}

/// Settings-style list row: leading icon tile, title, subtitle, chevron.
class ListRow extends StatelessWidget {
  const ListRow({super.key, required this.icon, required this.title, this.subtitle, this.onTap, this.trailing, this.tone});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Colours the icon tile, the title and the chevron (e.g. the theme's
  /// warning colour); the accent and neutral text by default.
  final Color? tone;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = this.tone;
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            tone == null ? IconTile(icon: icon, size: 34, radius: 10) : IconTile(icon: icon, size: 34, radius: 10, color: tone.withValues(alpha: 0.16), iconColor: tone),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: tone)),
                  if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
                ],
              ),
            ),
            trailing ?? Icon(CupertinoIcons.chevron_right, size: 16, color: tone ?? c.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// iOS 26 style alert: a glass card with a large radius, title, optional
/// message and child (e.g. an [AlertTextField]), and one or two actions.
/// Returns true when the confirm action was tapped. Use it for every
/// confirmation in the app so they all look the same. With a text field
/// child the card rises above the keyboard.
Future<bool> showAppAlert(
  BuildContext context, {
  required String title,
  String? message,
  Widget? child,
  String confirmLabel = 'OK',
  String? cancelLabel = 'Cancel',
  bool destructive = false,
  bool Function()? canConfirm,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: cancelLabel != null,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.28),
    transitionDuration: const Duration(milliseconds: 240),
    transitionBuilder: (ctx, anim, _, widget) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeIn);
      return FadeTransition(opacity: curved, child: ScaleTransition(scale: Tween(begin: 1.06, end: 1.0).animate(curved), child: widget));
    },
    pageBuilder: (ctx, _, _) => _AppAlert(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      canConfirm: canConfirm,
      child: child,
    ),
  );
  return result ?? false;
}

/// Text field styled for [showAppAlert]: rounded 12, filled, no outline, in
/// the iOS 26 alert idiom. Pass the same [controller] you read after the
/// alert resolves.
class AlertTextField extends StatelessWidget {
  const AlertTextField({
    super.key,
    required this.controller,
    this.placeholder,
    this.autofocus = true,
    this.maxLength,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = false,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction = TextInputAction.done,
  });
  final TextEditingController controller;
  final String? placeholder;
  final bool autofocus;
  final int? maxLength;
  final TextCapitalization textCapitalization;
  final bool autocorrect;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = context.isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05);
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      autofocus: autofocus,
      maxLength: maxLength,
      textCapitalization: textCapitalization,
      autocorrect: autocorrect,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textAlign: TextAlign.center,
      cursorColor: context.accent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      style: TextStyle(fontSize: 16, color: c.textPrimary, letterSpacing: -0.2),
      placeholderStyle: TextStyle(fontSize: 16, color: c.textTertiary, letterSpacing: -0.2),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(12)),
    );
  }
}

class _AppAlert extends StatelessWidget {
  const _AppAlert({required this.title, this.message, this.child, required this.confirmLabel, this.cancelLabel, required this.destructive, this.canConfirm});
  final String title;
  final String? message;
  final Widget? child;
  final String confirmLabel;
  final String? cancelLabel;
  final bool destructive;
  final bool Function()? canConfirm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = context.isDark;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final hairline = isDark ? Colors.white.withValues(alpha: 0.16) : Colors.black.withValues(alpha: 0.14);
    const radius = 28.0;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 290),
            child: Material(
              type: MaterialType.transparency,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16), blurRadius: 40, offset: const Offset(0, 16))],
                ),
                child: GlassSurface(
                  sigma: 36,
                  opacity: isDark ? 0.78 : 0.86,
                  borderRadius: BorderRadius.circular(radius),
                  hairline: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.8), width: 0.5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                        child: Column(
                          children: [
                            Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.textPrimary, letterSpacing: -0.3, height: 1.25)),
                            if (message != null) ...[
                              const SizedBox(height: 6),
                              Text(message!, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary)),
                            ],
                            if (child != null) ...[const SizedBox(height: 16), child!],
                          ],
                        ),
                      ),
                      SizedBox(height: 0.5, child: ColoredBox(color: hairline)),
                      SizedBox(
                        height: 50,
                        child: Row(
                          children: [
                            if (cancelLabel != null) ...[
                              Expanded(child: _AlertAction(label: cancelLabel!, onTap: () => Navigator.of(context).pop(false))),
                              SizedBox(width: 0.5, child: ColoredBox(color: hairline)),
                            ],
                            Expanded(
                              child: _AlertAction(
                                label: confirmLabel,
                                bold: true,
                                color: destructive ? c.danger : null,
                                onTap: () {
                                  if (canConfirm != null && !canConfirm!()) return;
                                  Navigator.of(context).pop(true);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlertAction extends StatelessWidget {
  const _AlertAction({required this.label, required this.onTap, this.bold = false, this.color});
  final String label;
  final VoidCallback onTap;
  final bool bold;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      sound: false,
      child: SizedBox.expand(
        child: Center(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color ?? context.accent, letterSpacing: -0.2)),
        ),
      ),
    );
  }
}
