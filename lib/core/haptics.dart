import 'package:flutter/services.dart';

/// Thin wrapper so haptics can be toggled from settings.
class Haptics {
  static bool enabled = true;

  static void light() { if (enabled) HapticFeedback.lightImpact(); }
  static void medium() { if (enabled) HapticFeedback.mediumImpact(); }
  static void heavy() { if (enabled) HapticFeedback.heavyImpact(); }
  static void selection() { if (enabled) HapticFeedback.selectionClick(); }
  static void success() {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 90), HapticFeedback.lightImpact);
  }
}
