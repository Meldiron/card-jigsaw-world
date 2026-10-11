import 'package:flutter/material.dart';

/// Design tokens.
///
/// The interface is deliberately quiet: neutral surfaces, one accent colour
/// for actions and selection, and a small set of semantic colours. Pictures
/// provide the colour; chrome stays out of their way.
class Brand {
  /// Single accent used for primary actions, selection and links.
  static const accent = Color(0xFF4F46E5);
  static const accentDark = Color(0xFF6366F1);

  /// Semantic colours. Used small (icons, badges), never as large fills.
  static const coin = Color(0xFFE0A200);
  static const coinDeep = Color(0xFFB97800);
  static const ticket = Color(0xFF0F9D8F);
  static const hint = Color(0xFFF59E0B);
  static const success = Color(0xFF16A34A);
  static const danger = Color(0xFFDC2626);
  static const live = Color(0xFFE11D48); // "today", "new", "ready" markers
  static const star = Color(0xFFF5B301);

  // Legacy names kept so older call sites keep compiling; all map onto the
  // reduced palette above.
  static const violet = accent;
  static const violetDeep = Color(0xFF4338CA);
  static const violetSoft = Color(0xFFC7D2FE);
  static const coral = live;
  static const gold = coin;
  static const goldDeep = coinDeep;
  static const teal = ticket;
  static const mint = success;
  static const sky = accent;
  static const pink = live;
  static const orange = hint;

  // Gradients are only used on top of imagery (scrims).
  static const gradientHero = LinearGradient(colors: [accent, accent]);
  static const gradientSunset = LinearGradient(colors: [live, live]);
  static const gradientGold = LinearGradient(colors: [coin, coin]);
  static const gradientTeal = LinearGradient(colors: [ticket, ticket]);

  static LinearGradient scrim({double strength = 0.75}) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black.withValues(alpha: strength)],
      );
}

class Radii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const pill = 999.0;
}

class Spacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// Theme-aware semantic colours that are not part of ColorScheme.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.canvas,
    required this.card,
    required this.cardElevated,
    required this.stroke,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.boardBackground,
    required this.cardFace,
    required this.shadow,
    required this.success,
    required this.danger,
    required this.accentTint,
  });

  final Color canvas;
  final Color card;
  final Color cardElevated;
  final Color stroke;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color boardBackground;
  final Color cardFace;
  final Color shadow;
  final Color success;
  final Color danger;
  final Color accentTint;

  static const light = AppColors(
    canvas: Color(0xFFF6F6F8),
    card: Colors.white,
    cardElevated: Colors.white,
    stroke: Color(0xFFE7E7EC),
    textPrimary: Color(0xFF111118),
    textSecondary: Color(0xFF5F5F6E),
    textTertiary: Color(0xFF9A9AA8),
    boardBackground: Color(0xFFECECF1),
    cardFace: Colors.white,
    shadow: Color(0x0F101020),
    success: Brand.success,
    danger: Brand.danger,
    accentTint: Color(0xFFEEEDFC),
  );

  static const dark = AppColors(
    canvas: Color(0xFF0D0D11),
    card: Color(0xFF17171C),
    cardElevated: Color(0xFF1F1F26),
    stroke: Color(0xFF2A2A33),
    textPrimary: Color(0xFFF2F2F5),
    textSecondary: Color(0xFFA6A6B4),
    textTertiary: Color(0xFF6E6E7C),
    boardBackground: Color(0xFF15151A),
    cardFace: Color(0xFF2A2A33),
    shadow: Color(0x55000000),
    success: Color(0xFF4ADE80),
    danger: Color(0xFFF87171),
    accentTint: Color(0xFF24233A),
  );

  @override
  AppColors copyWith({Color? canvas}) => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardElevated: Color.lerp(cardElevated, other.cardElevated, t)!,
      stroke: Color.lerp(stroke, other.stroke, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      boardBackground: Color.lerp(boardBackground, other.boardBackground, t)!,
      cardFace: Color.lerp(cardFace, other.cardFace, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      accentTint: Color.lerp(accentTint, other.accentTint, t)!,
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get accent => isDark ? Brand.accentDark : Brand.accent;
}
