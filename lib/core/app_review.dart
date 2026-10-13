import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The App Store rating prompt (`AppReview` in `ios/Runner/AppDelegate.swift`). StoreKit decides
/// whether it really appears (Apple shows it at most three times a year per person); it talks only
/// to Apple. iPhone app only: a no-op on web and Android.
class AppReviewChannel {
  AppReviewChannel._();

  static const _channel = MethodChannel('cjw/review');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Asks StoreKit for the prompt. True when there was a window to ask in.
  static Future<bool> request() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('request') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('review request failed: $e');
      return false;
    }
  }
}
