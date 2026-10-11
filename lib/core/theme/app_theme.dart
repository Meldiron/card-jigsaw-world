import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Builds light/dark themes. Everything uses the platform font (SF on iOS,
/// Roboto on Android); hierarchy comes from weight and size, not typefaces.
class AppTheme {
  static ThemeData light() => _build(Brightness.light, AppColors.light);
  static ThemeData dark() => _build(Brightness.dark, AppColors.dark);

  static ThemeData _build(Brightness b, AppColors c) {
    final isDark = b == Brightness.dark;
    final accent = isDark ? Brand.accentDark : Brand.accent;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: b,
      primary: accent,
      secondary: accent,
      tertiary: Brand.ticket,
      surface: c.card,
      onSurface: c.textPrimary,
      error: c.danger,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.canvas,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      extensions: [c],
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: b,
        primaryColor: accent,
        scaffoldBackgroundColor: c.canvas,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      }),
    );

    final text = base.textTheme.apply(bodyColor: c.textPrimary, displayColor: c.textPrimary);
    TextStyle d(double size, FontWeight w, {double? height, double ls = 0}) =>
        TextStyle(fontSize: size, fontWeight: w, height: height, letterSpacing: ls, color: c.textPrimary);

    return base.copyWith(
      textTheme: text.copyWith(
        displayLarge: d(40, FontWeight.w700, height: 1.05, ls: -1.0),
        displayMedium: d(34, FontWeight.w700, height: 1.05, ls: -0.8),
        displaySmall: d(28, FontWeight.w700, height: 1.1, ls: -0.6),
        headlineLarge: d(26, FontWeight.w700, height: 1.15, ls: -0.5),
        headlineMedium: d(22, FontWeight.w700, height: 1.15, ls: -0.4),
        headlineSmall: d(18, FontWeight.w700, height: 1.2, ls: -0.3),
        titleLarge: d(17, FontWeight.w700, height: 1.25, ls: -0.2),
        titleMedium: d(15, FontWeight.w600),
        titleSmall: d(13, FontWeight.w600),
        bodyLarge: d(16, FontWeight.w400, height: 1.4),
        bodyMedium: d(14, FontWeight.w400, height: 1.4),
        labelLarge: d(15, FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: d(17, FontWeight.w700, ls: -0.2),
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: c.card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      ),
      dividerTheme: DividerThemeData(color: c.stroke, thickness: 1, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
        showDragHandle: true,
        dragHandleColor: c.stroke,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? c.cardElevated : c.canvas,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide(color: c.stroke)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide(color: c.stroke)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide(color: accent, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(color: c.textTertiary),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Brand.success : c.stroke),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? c.cardElevated : c.textPrimary,
        contentTextStyle: TextStyle(color: isDark ? c.textPrimary : Colors.white, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      ),
    );
  }
}
