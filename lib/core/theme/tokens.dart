import 'package:flutter/material.dart';

/// Design tokens.
///
/// The interface is deliberately quiet: neutral surfaces, one accent colour
/// for actions and selection, and a small set of semantic colours. Pictures
/// provide the colour; chrome stays out of their way.
class Brand {
  /// Single accent used for primary actions, selection and links.
  static const accent = Color(0xFF2F4FBF);
  static const accentDark = Color(0xFF7C9AFF);

  /// The accent as a fill under white text in dark mode (buttons, selected
  /// chips and tiles, play discs). [accentDark] is tuned for text and icons on
  /// the dark canvas; as a fill it leaves white labels at 2.6:1. This deeper
  /// cobalt keeps white labels at 5.1:1 and still stands off the canvas
  /// (3.8:1). Light mode fills with [accent] (white 7:1).
  static const accentFillDark = Color(0xFF4065DD);

  /// Semantic colours. Used small (icons, badges), never as large fills.
  static const coin = Color(0xFFE0A200);
  static const coinDeep = Color(0xFFB97800);
  static const ticket = Color(0xFF14B8A6);
  static const hint = Color(0xFFF59E0B);
  static const success = Color(0xFF16A34A);
  static const danger = Color(0xFFDC2626);
  static const warning = Color(0xFFB45309); // unsaved guest progress and similar cautions
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

  /// The dark fade under text on a photo. With Settings > Accessibility > Increase contrast
  /// ([contrast]) it darkens sooner and further, so every line on it reads at 4.5:1 or better.
  static LinearGradient scrim({double strength = 0.75, bool contrast = false}) => contrast
      ? LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.30, 0.55, 1.0],
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.30), Colors.black.withValues(alpha: 0.62), Colors.black.withValues(alpha: 0.85)],
        )
      : LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: strength)],
        );
}

/// Play together (docs/multiplayer.md): the other players' colours. Every player sees their own
/// cards in the accent (cobalt) and the others in these four, by seat; never red (danger) or cobalt.
/// The colour is never alone: the player's initial goes with it.
///
/// Light mode fills carry white text at 5:1 or better and outline cards at 4.4:1 or better on the
/// board; dark mode fills are light and carry dark text ([onFill]) at 7:1 or better. The Contrast
/// sets (Settings > Accessibility > Increase contrast) go further: 6:1 and more everywhere.
class PlayerColors {
  PlayerColors._();

  static const count = 4;

  /// Orange, purple, teal, pink.
  static const light = [Color(0xFFC2410C), Color(0xFF7E22CE), Color(0xFF0F766E), Color(0xFFBE185D)];
  static const lightContrast = [Color(0xFF9A3412), Color(0xFF6B21A8), Color(0xFF115E59), Color(0xFF9D174D)];
  static const dark = [Color(0xFFFB923C), Color(0xFFC084FC), Color(0xFF2DD4BF), Color(0xFFF472B6)];
  static const darkContrast = [Color(0xFFFDBA74), Color(0xFFD8B4FE), Color(0xFF5EEAD4), Color(0xFFF9A8D4)];

  /// Text (the initial) on a player colour.
  static const onLight = Colors.white;
  static const onDark = Color(0xFF111118);

  /// The palette for a theme.
  static List<Color> of({required bool dark, required bool contrast}) => dark ? (contrast ? darkContrast : PlayerColors.dark) : (contrast ? lightContrast : PlayerColors.light);
}

class Radii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const pill = 999.0;
}

/// The type ramp: every text in the app uses one of these sizes (iOS text
/// styles at the default Dynamic Type size). Weights: 400 for reading, 600
/// for labels and row titles, 700 for headings and numbers; nothing heavier.
///
/// | size | name | for |
/// | --- | --- | --- |
/// | 40 | display | one big number (piggy bank) |
/// | 34 | largeTitle | page titles (Quests, Social, Profile) |
/// | 28 | title1 | hero titles |
/// | 22 | title2 | sheet and alert-sized titles |
/// | 20 | title3 | section headers |
/// | 17 | headline | card titles, bar titles, stat values |
/// | 16 | callout | buttons |
/// | 15 | body | row titles, body copy |
/// | 13 | footnote | subtitles, secondary lines, links |
/// | 12 | caption | chips, meta lines, captions |
/// | 11 | micro | tab labels, badges, axis labels (the smallest size iOS allows) |
class TypeSize {
  static const display = 40.0;
  static const largeTitle = 34.0;
  static const title1 = 28.0;
  static const title2 = 22.0;
  static const title3 = 20.0;
  static const headline = 17.0;
  static const callout = 16.0;
  static const body = 15.0;
  static const footnote = 13.0;
  static const caption = 12.0;
  static const micro = 11.0;
}

class Spacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// Card insets: every card (`SoftCard`) uses one of two, so the content of stacked cards starts on
/// the same line (page margin 20 + 16 = 36 pt from the screen edge).
class Insets {
  /// Cards with a title and body (the default).
  static const card = EdgeInsets.all(Spacing.lg);

  /// One-line rows and compact cards (a title and a subtitle beside a button).
  static const cardCompact = EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md);
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
    required this.warning,
    required this.warningTint,
    required this.accentTint,
    this.highContrast = false,
    Color? controlStroke,
    Color? track,
  })  : controlStroke = controlStroke ?? stroke,
        track = track ?? stroke;

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

  /// A caution the player should act on (guest progress not saved to an
  /// account): [warning] for the icon, outline and title, [warningTint] as
  /// the card's quiet fill.
  final Color warning;
  final Color warningTint;
  final Color accentTint;

  /// Settings > Accessibility > Increase contrast: the palettes below marked Contrast. Every text
  /// colour reads at 4.5:1 or better on its surfaces, and meaningful outlines at 3:1.
  final bool highContrast;

  /// The outline of a control when it is the control's only edge (text fields, outlined chips and
  /// buttons, the segmented control's thumb); [stroke] stays for hairlines and dividers.
  final Color controlStroke;

  /// The empty part of a progress bar or meter.
  final Color track;

  /// The same palette one level up (dark sheets and alerts), keeping [highContrast].
  AppColors get elevated => highContrast ? darkElevatedContrast : darkElevated;

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
    warning: Brand.warning,
    warningTint: Color(0xFFFFF6E5),
    accentTint: Color(0xFFE9EEFB),
  );

  static const dark = AppColors(
    canvas: Color(0xFF0D0D11),
    card: Color(0xFF17171C),
    cardElevated: Color(0xFF1F1F26),
    stroke: Color(0xFF2A2A33),
    textPrimary: Color(0xFFF2F2F5),
    textSecondary: Color(0xFFA6A6B4),
    // 4.9:1 on cards and 5.4:1 on the canvas: tertiary text carries real
    // information at 10-12 pt (counts, costs, captions, legal lines).
    textTertiary: Color(0xFF86868F),
    boardBackground: Color(0xFF15151A),
    cardFace: Color(0xFF2A2A33),
    shadow: Color(0x55000000),
    success: Color(0xFF4ADE80),
    danger: Color(0xFFF87171),
    warning: Color(0xFFF2B045),
    warningTint: Color(0xFF261E10),
    accentTint: Color(0xFF1C2440),
  );

  /// Dark mode one level up: the colours for content on a raised surface
  /// (content sheets, alerts, the full-height Store, Wheel and Account
  /// sheets). In dark mode a surface shows its height by being lighter, as
  /// iOS's elevated colours do; with the page colours, cards, round buttons,
  /// chips and tonal buttons inside a sheet were darker than the sheet and
  /// looked sunk into it. Text and semantic colours are unchanged.
  static const darkElevated = AppColors(
    canvas: Color(0xFF1C1C22),
    card: Color(0xFF28282F),
    cardElevated: Color(0xFF303038),
    stroke: Color(0xFF3A3A44),
    textPrimary: Color(0xFFF2F2F5),
    textSecondary: Color(0xFFA6A6B4),
    textTertiary: Color(0xFF92929E), // 4.8:1 on raised cards (145)
    boardBackground: Color(0xFF222228),
    cardFace: Color(0xFF34343D),
    shadow: Color(0x55000000),
    success: Color(0xFF4ADE80),
    danger: Color(0xFFF87171),
    warning: Color(0xFFF2B045),
    warningTint: Color(0xFF2E2414),
    accentTint: Color(0xFF263463),
  );

  /// Increase contrast, light (values checked against WCAG: text 4.5:1, outlines 3:1).
  static const lightContrast = AppColors(
    canvas: Color(0xFFF6F6F8),
    card: Colors.white,
    cardElevated: Colors.white,
    stroke: Color(0xFFC8C8D0),
    textPrimary: Color(0xFF111118),
    textSecondary: Color(0xFF4B4B57),
    textTertiary: Color(0xFF616170),
    boardBackground: Color(0xFFECECF1),
    cardFace: Colors.white,
    shadow: Color(0x0F101020),
    success: Color(0xFF107736),
    danger: Color(0xFFB91C1C),
    warning: Color(0xFF9F4908),
    warningTint: Color(0xFFFFF6E5),
    accentTint: Color(0xFFE9EEFB),
    highContrast: true,
    controlStroke: Color(0xFF80808C),
    track: Color(0xFFE7E7EC),
  );

  /// Increase contrast, dark.
  static const darkContrast = AppColors(
    canvas: Color(0xFF0D0D11),
    card: Color(0xFF17171C),
    cardElevated: Color(0xFF1F1F26),
    stroke: Color(0xFF3A3A45),
    textPrimary: Color(0xFFF2F2F5),
    textSecondary: Color(0xFFC0C0CA),
    textTertiary: Color(0xFFA2A2AC),
    boardBackground: Color(0xFF15151A),
    cardFace: Color(0xFF2A2A33),
    shadow: Color(0x55000000),
    success: Color(0xFF4ADE80),
    danger: Color(0xFFF98B8B),
    warning: Color(0xFFF2B045),
    warningTint: Color(0xFF261E10),
    accentTint: Color(0xFF1C2440),
    highContrast: true,
    controlStroke: Color(0xFF7A7A86),
    track: Color(0xFF2A2A33),
  );

  /// Increase contrast, dark, one level up.
  static const darkElevatedContrast = AppColors(
    canvas: Color(0xFF1C1C22),
    card: Color(0xFF28282F),
    cardElevated: Color(0xFF303038),
    stroke: Color(0xFF4A4A55),
    textPrimary: Color(0xFFF2F2F5),
    textSecondary: Color(0xFFC0C0CA),
    textTertiary: Color(0xFFA2A2AC),
    boardBackground: Color(0xFF222228),
    cardFace: Color(0xFF34343D),
    shadow: Color(0x55000000),
    success: Color(0xFF4ADE80),
    danger: Color(0xFFF98B8B),
    warning: Color(0xFFF2B045),
    warningTint: Color(0xFF2E2414),
    accentTint: Color(0xFF263463),
    highContrast: true,
    controlStroke: Color(0xFF888894),
    track: Color(0xFF3A3A44),
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
      warning: Color.lerp(warning, other.warning, t)!,
      warningTint: Color.lerp(warningTint, other.warningTint, t)!,
      accentTint: Color.lerp(accentTint, other.accentTint, t)!,
      highContrast: t < 0.5 ? highContrast : other.highContrast,
      controlStroke: Color.lerp(controlStroke, other.controlStroke, t)!,
      track: Color.lerp(track, other.track, t)!,
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  bool get highContrast => colors.highContrast;
  Color get accent => isDark ? (highContrast ? const Color(0xFF8CA7FF) : Brand.accentDark) : Brand.accent;

  /// The accent as a fill with white content on top: buttons, selected chips
  /// and tiles, play discs, the off-screen pointer. Use [accent] for text,
  /// icons, outlines and progress.
  Color get accentFill => isDark ? (highContrast ? const Color(0xFF3F62D6) : Brand.accentFillDark) : Brand.accent;

  /// Star gold; a deeper gold with Increase contrast in light mode (3:1 on white).
  Color get star => highContrast && !isDark ? const Color(0xFFA97C01) : Brand.star;

  /// Text and icons on an [accentFill] surface.
  Color get onAccent => Colors.white;

  /// Play together: another player's colour ([PlayerColors]); [index] 0 to 3.
  Color playerColor(int index) => PlayerColors.of(dark: isDark, contrast: highContrast)[index % PlayerColors.count];

  /// Text (a player's initial) on [playerColor].
  Color get onPlayerColor => isDark ? PlayerColors.onDark : PlayerColors.onLight;
}
