import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform.dart';

/// A notification that arrived while the game was open (iOS shows no banner then).
class PushNote {
  const PushNote({required this.title, required this.body, this.link});
  final String title;
  final String body;
  final String? link;
}

/// Bridge to the native push registration (`GiftPush` in `ios/Runner/AppDelegate.swift`): Apple's
/// own push service, no third-party SDK. The device token goes to Appwrite as a push target
/// (`PushRegistration`, lib/state/push.dart); Appwrite Messaging sends gift notifications to it.
/// Notification permission is shared with the daily reminders ([ReminderChannel]). Every call is a
/// no-op where [supportsNotifications] is false (web, Android).
class PushChannel {
  PushChannel._();

  static const _channel = MethodChannel('cjw/push');

  /// The APNs environment this build's device tokens belong to: `development` (simulators and
  /// builds signed for development) or `production` (TestFlight and the App Store), read from the
  /// app's own provisioning profile.
  static Future<String?> environment() => _call<String>('environment');

  /// Asks iOS for the device token (no prompt: permission is asked before this). The token comes
  /// back through [listen]'s `onToken`, now and whenever iOS changes it.
  static Future<void> register() => _call<void>('register');

  /// Calls [onToken] with every device token, [onOpen] with the link of every notification the
  /// player taps (including the one that launched the app) and [onReceive] with a notification
  /// that arrived while the game was open.
  static Future<void> listen({
    required void Function(String token) onToken,
    required void Function(String link) onOpen,
    required void Function(PushNote note) onReceive,
  }) async {
    if (!supportsNotifications) return;
    _channel.setMethodCallHandler((call) async {
      final args = call.arguments;
      switch (call.method) {
        case 'token' when args is String && args.isNotEmpty:
          onToken(args);
        case 'tokenError':
          debugPrint('push registration failed: $args');
        case 'open' when args is String && args.isNotEmpty:
          onOpen(args);
        case 'received' when args is Map:
          final link = args['link'] as String?;
          onReceive(PushNote(title: '${args['title'] ?? ''}', body: '${args['body'] ?? ''}', link: link == null || link.isEmpty ? null : link));
      }
    });
    final launch = await _call<String>('ready');
    if (launch != null && launch.isNotEmpty) onOpen(launch);
  }

  static Future<T?> _call<T>(String method, [Object? arguments]) async {
    if (!supportsNotifications) return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('push $method failed: $e');
      return null;
    }
  }
}
