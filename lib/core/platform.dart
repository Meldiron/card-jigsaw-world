import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the app is running and which native features exist there.
///
/// The web build is deliberately limited: no StoreKit, no gift-code sheet,
/// no Home Screen widgets or quick actions, no local notifications. Every
/// call site that touches one of those plugins checks a flag here first so
/// nothing throws `MissingPluginException` at runtime on web.
///
/// Widgets read [platformCapsProvider] so tests can override the
/// capabilities; services use the top-level getters.
const bool isWeb = kIsWeb;

bool get _isApple => !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);

/// StoreKit / Play Billing through `in_app_purchase`. The plugin has no web
/// implementation, so `InAppPurchase.instance` must never be touched on web.
bool get supportsPurchases => !kIsWeb;

/// App Store subscription offer codes (`presentCodeRedemptionSheet`).
bool get supportsGiftCodes => _isApple;

/// Home Screen long-press shortcuts (`quick_actions`).
bool get supportsQuickActions => !kIsWeb;

/// Home Screen / Lock Screen widgets (WidgetKit bridge). iOS only.
bool get supportsWidgets => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Daily reminder notifications. Not wired on web.
bool get supportsNotifications => !kIsWeb;

/// Native Sign in with Apple sheet. The web signs in through an OAuth redirect.
bool get supportsNativeAppleSignIn => _isApple;

/// Copy shown wherever a purchase or store-only feature is tapped on web.
const String availableOnIphoneMessage = 'Available in the iPhone app.';
const String purchasesOnIphoneMessage = 'Purchases are available in the iPhone app.';

/// Immutable snapshot of the platform capabilities.
@immutable
class PlatformCaps {
  const PlatformCaps({
    required this.isWeb,
    required this.purchases,
    required this.giftCodes,
    required this.quickActions,
    required this.widgets,
    required this.notifications,
    required this.nativeAppleSignIn,
  });

  /// The running platform.
  factory PlatformCaps.current() => PlatformCaps(
        isWeb: kIsWeb,
        purchases: supportsPurchases,
        giftCodes: supportsGiftCodes,
        quickActions: supportsQuickActions,
        widgets: supportsWidgets,
        notifications: supportsNotifications,
        nativeAppleSignIn: supportsNativeAppleSignIn,
      );

  /// What a browser gets. Used by tests and as documentation of the web cut.
  static const web = PlatformCaps(isWeb: true, purchases: false, giftCodes: false, quickActions: false, widgets: false, notifications: false, nativeAppleSignIn: false);

  /// What the iPhone app gets.
  static const ios = PlatformCaps(isWeb: false, purchases: true, giftCodes: true, quickActions: true, widgets: true, notifications: true, nativeAppleSignIn: true);

  final bool isWeb;
  final bool purchases;
  final bool giftCodes;
  final bool quickActions;
  final bool widgets;
  final bool notifications;
  final bool nativeAppleSignIn;
}

final platformCapsProvider = Provider<PlatformCaps>((ref) => PlatformCaps.current());
