import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics.dart';
import '../core/appwrite.dart';
import '../core/platform.dart';
import '../core/push.dart';
import '../core/qa.dart';
import '../core/reminders.dart';
import 'auth.dart';
import 'settings.dart';

/// The Appwrite Messaging providers (Apple key 2QJPJFW8JW, team C24QP73SQM): `apns` sends through
/// Apple's production service (TestFlight and App Store builds), `apns-sandbox` through the
/// development one (simulators, debug and device builds signed for development). A device token
/// works only with the service of its build's `aps-environment`.
class PushProviders {
  PushProviders._();
  static const production = 'apns';
  static const sandbox = 'apns-sandbox';

  /// The provider for a build whose provisioning profile says [environment].
  static String forEnvironment(String? environment) => environment == 'development' ? sandbox : production;
}

/// Settings > Gifts from friends: notifications when a friend sends a gift, stored on the device.
/// On unless the player turned it off; nothing arrives until iOS allows notifications.
class GiftNotificationsNotifier extends Notifier<bool> {
  static const _key = 'giftNotifications';

  @override
  bool build() => ref.watch(localStoreProvider).getText(_key) != 'off';

  void set(bool on) {
    ref.read(localStoreProvider).setText(_key, on ? 'on' : 'off');
    state = on;
  }
}

final giftNotificationsProvider = NotifierProvider<GiftNotificationsNotifier, bool>(GiftNotificationsNotifier.new);

/// Whether iOS allows Carden's notifications (read again when the app comes back to the front).
final notificationsAllowedProvider = FutureProvider<bool>((ref) async => supportsNotifications && await ReminderChannel.status() == ReminderPermission.granted);

/// Push targets of the signed-in Appwrite user. A target made through the account belongs to the
/// session (Appwrite deletes it with the session, and a session keeps one per provider, so a new
/// token updates it); a device token belongs to one user at a time.
abstract class PushTargets {
  /// Registers [token] for the current session and returns the target's id.
  Future<String> create(String token, String providerId);
  Future<void> update(String targetId, String token);
  Future<void> delete(String targetId);
}

class AccountPushTargets implements PushTargets {
  AccountPushTargets(this._account);
  final Account _account;

  @override
  Future<String> create(String token, String providerId) async =>
      (await _account.createPushTarget(targetId: ID.unique(), identifier: token, providerId: providerId)).$id;

  @override
  Future<void> update(String targetId, String token) => _account.updatePushTarget(targetId: targetId, identifier: token);

  @override
  Future<void> delete(String targetId) => _account.deletePushTarget(targetId: targetId);
}

final pushTargetsProvider = Provider<PushTargets>((ref) => AccountPushTargets(ref.watch(accountProvider)));

/// Keeps this iPhone registered for gift notifications (docs/friend-gifts.md, "Push"): the device
/// token from iOS becomes an Appwrite push target of the signed-in player, again whenever the token
/// or the player changes (sign-in, another account, a guest save merged into an account: each of
/// those starts a new session, and Appwrite dropped the old session's target with it). Only while
/// iOS allows notifications and Settings > Gifts from friends is on.
class PushRegistration {
  PushRegistration(this._ref);
  final Ref _ref;

  static const _storeKey = 'pushTarget';

  String? _token;
  String? _environment;

  /// `<user>|<token>|<provider>` last registered by this process: one request per change.
  String? _registered;

  /// Starts listening for tokens and taps; [onOpen] gets the link of a tapped notification and
  /// [onReceive] a notification that arrived while the game was open.
  Future<void> start({required void Function(String link) onOpen, required void Function(PushNote note) onReceive}) async {
    if (!supportsNotifications) return;
    _environment = await PushChannel.environment();
    await PushChannel.listen(onToken: onToken, onOpen: onOpen, onReceive: onReceive);
    await refresh();
  }

  /// Asks iOS for the token when notifications are allowed and wanted (start, resume, after the
  /// permission question). Without permission nothing is asked and nothing is registered.
  Future<void> refresh() async {
    if (!supportsNotifications || !_ref.read(giftNotificationsProvider)) return;
    if (await ReminderChannel.status() != ReminderPermission.granted) return;
    await PushChannel.register();
  }

  /// A device token from iOS (also the same one again on every launch).
  Future<void> onToken(String token, {String? environment}) async {
    _token = token;
    if (environment != null) _environment = environment;
    await sync();
  }

  /// Registrations run one after another (a token and a sign-in can arrive together).
  Future<void> _queue = Future.value();

  /// Registers the current token for the current player, unless that is already done.
  Future<void> sync() => _queue = _queue.then((_) => _syncOnce());

  Future<void> _syncOnce() async {
    final userId = _ref.read(currentUserIdProvider);
    final token = _token;
    if (userId == null || userId == 'local' || token == null || !_ref.read(giftNotificationsProvider)) return;
    final provider = PushProviders.forEnvironment(_environment);
    final key = '$userId|$token|$provider';
    if (_registered == key) return;
    final store = _ref.read(localStoreProvider);
    final targets = _ref.read(pushTargetsProvider);
    try {
      final targetId = await targets.create(token, provider);
      await store.setJson(_storeKey, {'userId': userId, 'targetId': targetId});
      _registered = key;
    } on AppwriteException catch (e) {
      // 409: the token is already a target, of an earlier session of this player (update it) or
      // of a player whose session this device lost (nothing to do until that session ends).
      final saved = store.getJson(_storeKey);
      if (e.code == 409 && saved?['userId'] == userId && saved?['targetId'] is String) {
        try {
          await targets.update(saved!['targetId'] as String, token);
          _registered = key;
          return;
        } catch (e2) {
          debugPrint('push target update failed: $e2');
        }
      }
      debugPrint('push target failed: ${e.code} ${e.message}');
    } catch (e) {
      debugPrint('push target failed: $e');
    }
  }

  /// Settings > Gifts from friends on: asks iOS the first time (quietly in integration runs) and
  /// registers. False when iOS does not allow notifications.
  Future<bool> enable() async {
    _ref.read(giftNotificationsProvider.notifier).set(true);
    var permission = await ReminderChannel.status();
    if (permission == ReminderPermission.notDetermined) {
      permission = await ReminderChannel.request(quiet: QaRun.enabled && QaRun.integrationRun) ? ReminderPermission.granted : ReminderPermission.denied;
      AppAnalytics.event('push_permission', {'result': permission == ReminderPermission.granted ? 'granted' : 'denied'});
      _ref.invalidate(notificationsAllowedProvider);
    }
    if (permission != ReminderPermission.granted) return false;
    await refresh();
    return true;
  }

  /// Settings > Gifts from friends off: this device's target goes, so no gift notification reaches it.
  Future<void> disable() async {
    _ref.read(giftNotificationsProvider.notifier).set(false);
    await _queue;
    _registered = null;
    final store = _ref.read(localStoreProvider);
    final saved = store.getJson(_storeKey);
    if (saved == null) return;
    if (saved['userId'] == _ref.read(currentUserIdProvider) && saved['targetId'] is String) {
      try {
        await _ref.read(pushTargetsProvider).delete(saved['targetId'] as String);
      } on AppwriteException catch (e) {
        if (e.code != 404) debugPrint('push target delete failed: $e');
      } catch (e) {
        debugPrint('push target delete failed: $e');
      }
    }
    await store.remove(_storeKey);
  }
}

final pushRegistrationProvider = Provider<PushRegistration>((ref) {
  final registration = PushRegistration(ref);
  // Sign-in, another account, a merge: the new session gets this device's token.
  ref.listen<String?>(currentUserIdProvider, (previous, next) {
    if (previous != next) registration.sync();
  });
  return registration;
});
