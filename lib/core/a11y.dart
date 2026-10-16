import 'package:flutter/widgets.dart';

import '../state/settings.dart';

/// Settings > Accessibility for the widgets below the app (lib/app.dart puts it above the
/// Navigator, so pages, sheets and alerts all see it). Everything the app changes for these options
/// reads them from here, never from the iPhone's own accessibility switches: the options are off
/// until the player turns them on in Settings (owner, 2026-10-16).
///
/// - Text size: applied once, as the app's `MediaQuery.textScaler`.
/// - Reduce motion: [reduceMotionOf]; spinning, zooming, sliding and looping motion become fades.
/// - Increase contrast: [increaseContrastOf]; the theme switches palettes (AppColors.*Contrast) and
///   glass becomes solid.
/// - Differentiate without colour: [symbolsOf]; states that colour shows get a symbol or text too.
class A11y extends InheritedWidget {
  const A11y({super.key, required this.prefs, required super.child});

  final Accessibility prefs;

  static Accessibility of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<A11y>()?.prefs ?? const Accessibility();

  static bool reduceMotionOf(BuildContext context) => of(context).reduceMotion;
  static bool increaseContrastOf(BuildContext context) => of(context).increaseContrast;
  static bool symbolsOf(BuildContext context) => of(context).differentiateWithoutColour;

  /// Text is set larger than the app's usual range (Settings > Accessibility > Text size: Large or
  /// Largest): side-by-side layouts stack so neither part is squeezed.
  static bool largeText(BuildContext context) => MediaQuery.textScalerOf(context).scale(10) > 13.5;

  /// [normal], or [Duration.zero] when motion is reduced (for implicit animations whose movement
  /// should simply jump to the end).
  static Duration motion(BuildContext context, Duration normal) => reduceMotionOf(context) ? Duration.zero : normal;

  @override
  bool updateShouldNotify(A11y oldWidget) => oldWidget.prefs != prefs;
}
