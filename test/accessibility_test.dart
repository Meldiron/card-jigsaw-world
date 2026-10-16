import 'package:carden/core/a11y.dart';
import 'package:carden/core/theme/tokens.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG contrast ratio of two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Settings > Accessibility (owner, 2026-10-16): off until turned on, and when on the app meets
/// Apple's Larger Text, Reduced Motion, Sufficient Contrast and Differentiate Without Color criteria.
void main() {
  group('settings', () {
    test('everything is off by default, so the usual game is unchanged', () {
      const a = Accessibility();
      expect(a.isDefault, isTrue);
      expect(a.textSize, TextSize.standard);
      expect(a.textSize.scale, isNull, reason: 'Default keeps the iPhone text size in the usual range');
      expect(Accessibility.fromJson(null), a);
      expect(Accessibility.fromJson(const {}), a);
    });

    test('Largest is 200%, as Apple asks for Larger Text', () {
      expect(TextSize.largest.scale, 2.0);
      expect(TextSize.large.scale, 1.5);
    });

    test('the options survive a round trip through the store', () {
      const a = Accessibility(textSize: TextSize.largest, reduceMotion: true, increaseContrast: true, differentiateWithoutColour: true);
      expect(Accessibility.fromJson(a.toJson()), a);
      expect(Accessibility.fromJson(const {'textSize': 'huge'}).textSize, TextSize.standard, reason: 'an unknown size falls back');
    });

    testWidgets('widgets outside the app read the options as off', (tester) async {
      late Accessibility seen;
      await tester.pumpWidget(Builder(builder: (context) {
        seen = A11y.of(context);
        return const SizedBox();
      }));
      expect(seen.isDefault, isTrue);
    });
  });

  group('Increase contrast palettes', () {
    test('the usual palettes are unchanged', () {
      expect(AppColors.light.textTertiary, const Color(0xFF9A9AA8));
      expect(AppColors.light.textSecondary, const Color(0xFF5F5F6E));
      expect(AppColors.dark.textTertiary, const Color(0xFF86868F));
      expect(AppColors.light.highContrast, isFalse);
      expect(AppColors.light.controlStroke, AppColors.light.stroke);
      expect(AppColors.light.track, AppColors.light.stroke);
    });

    for (final (name, p) in [('light', AppColors.lightContrast), ('dark', AppColors.darkContrast), ('dark raised', AppColors.darkElevatedContrast)]) {
      test('$name: text reads at 4.5:1 or better on every surface', () {
        for (final (surface, bg) in [('canvas', p.canvas), ('card', p.card), ('raised card', p.cardElevated), ('accent tint', p.accentTint)]) {
          for (final (role, fg) in [('primary', p.textPrimary), ('secondary', p.textSecondary), ('tertiary', p.textTertiary), ('danger', p.danger)]) {
            expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '$role on $surface');
          }
        }
      });

      test('$name: control outlines read at 3:1 or better', () {
        for (final bg in [p.canvas, p.card]) {
          expect(contrast(p.controlStroke, bg), greaterThanOrEqualTo(3.0));
        }
      });
    }

    test('the raised palette keeps Increase contrast', () {
      expect(AppColors.darkContrast.elevated, AppColors.darkElevatedContrast);
      expect(AppColors.dark.elevated, AppColors.darkElevated);
    });
  });
}
