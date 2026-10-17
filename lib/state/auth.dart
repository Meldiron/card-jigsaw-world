import 'package:appwrite/models.dart' as models;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics.dart';
import '../core/qa.dart';
import '../data/repositories.dart';
import 'settings.dart';

/// Holds the current Appwrite user. A guest (anonymous) session is created
/// automatically so players can start immediately and link an email later.
class AuthNotifier extends AsyncNotifier<models.User?> {
  @override
  Future<models.User?> build() async {
    final repo = ref.watch(authRepositoryProvider);
    // Integration tests must be QA runs, or their guest would join the public league.
    QaRun.requireForIntegrationRuns();
    try {
      final user = await repo.currentUser();
      // A QA build reusing a guest from an earlier run marks it too (no-op in release builds).
      if (user != null) return _remember(await repo.markQaGuest(user));
      // The web OAuth callback is about to create the real session; a
      // throwaway guest here would only get in its way.
      if (isOAuthCallback) return null;
      return _remember(await repo.signInAnonymously());
    } catch (e) {
      // Offline or backend unreachable: keep playing as the player this device last saw (the
      // session itself is stored by the SDK, so requests work again once the server answers).
      // A device that never reached the server plays without an account until it does.
      _offline = true;
      return _remembered();
    }
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  static const _userKey = 'authUser';

  /// The user came from the device's copy because the server did not answer.
  bool _offline = false;

  models.User _remember(models.User user) {
    _offline = false;
    ref.read(localStoreProvider).setJson(_userKey, user.toMap());
    return user;
  }

  models.User? _remembered() {
    final j = ref.read(localStoreProvider).getJson(_userKey);
    if (j == null) return null;
    try {
      return models.User.fromMap(j);
    } catch (_) {
      return null;
    }
  }

  /// Called when the connection may be back (or, with [force], when the server refused the
  /// session): confirms the remembered player, or makes the guest a device that started without a
  /// connection never got. The state changes only when the player does, so screens do not reload
  /// for nothing. A session that is gone is left for the next start (as before).
  Future<void> reconnect({bool force = false}) async {
    final current = state.value;
    if (current != null && !_offline && !force) return;
    try {
      final user = await _repo.currentUser();
      if (user != null) {
        _remember(user);
        if (user.$id != current?.$id) state = AsyncData(user);
        return;
      }
      if (isOAuthCallback || current != null) return;
      state = AsyncData(_remember(await _repo.signInAnonymously()));
    } catch (e) {
      debugPrint('reconnect failed: $e');
    }
  }

  /// True while the web app is loading on `/auth/callback` (path or hash routing).
  static bool get isOAuthCallback => kIsWeb && (Uri.base.path.contains('/auth/callback') || Uri.base.fragment.contains('/auth/callback'));

  Future<void> signUp({required String email, required String password, required String name}) async {
    final current = state.value;
    final isAnon = current != null && current.email.isEmpty;
    final user = isAnon
        ? await _repo.linkAnonymous(email: email, password: password, name: name)
        : await _repo.signUp(email: email, password: password, name: name);
    state = AsyncData(_remember(user));
    AppAnalytics.event('sign_up', {'method': 'email', 'fromGuest': isAnon});
  }

  Future<void> signIn({required String email, required String password}) async {
    // If we are a guest, end that session first.
    await _repo.signOut();
    final user = await _repo.signIn(email: email, password: password);
    state = AsyncData(_remember(user));
    AppAnalytics.event('sign_in', {'method': 'email'});
  }

  /// Native Sign in with Apple: the credential comes from the system sheet,
  /// Appwrite verifies the ID token and either links it to the current guest
  /// or signs the returning player into their existing account.
  /// Returns true when the player was signed in to an existing account
  /// (the guest progress on this device is left behind in that case).
  Future<bool> signInWithApple({required String idToken, required String nonce, String? name}) async {
    final result = await _repo.signInWithAppleIdToken(idToken: idToken, nonce: nonce, name: name);
    state = AsyncData(_remember(result.user));
    // Linked to the guest: a new account; switched: the player's existing one.
    AppAnalytics.event(result.switched ? 'sign_in' : 'sign_up', {'method': 'apple', 'fromGuest': !result.switched});
    return result.switched;
  }

  /// Web OAuth redirect: the callback brings a token; this turns it into a
  /// session (the guest session, if any, is replaced).
  Future<models.User> signInWithToken({required String userId, required String secret}) async {
    // Appwrite refuses a token session while another session is active, and
    // whatever session is here (the guest, or a stale one) is being replaced.
    await _repo.signOut();
    final user = await _repo.createSessionFromToken(userId: userId, secret: secret);
    state = AsyncData(_remember(user));
    AppAnalytics.event('sign_in', {'method': 'apple_web'});
    return user;
  }

  /// Re-reads the session after the page reloaded (web OAuth callback) and
  /// returns the user, falling back to a fresh guest.
  Future<models.User?> refresh() async {
    await retry();
    return state.value;
  }

  Future<void> signOut() async {
    AppAnalytics.event('sign_out');
    await _repo.signOut();
    state = const AsyncLoading();
    state = AsyncData(_remember(await _repo.signInAnonymously()));
  }

  /// The account was deleted on the server: drops its session and the copy of the player this
  /// device remembers, and starts a fresh guest.
  Future<models.User> startOverAfterDeletion() async {
    await _repo.signOut();
    await ref.read(localStoreProvider).remove(_userKey);
    state = const AsyncLoading();
    final user = _remember(await _repo.signInAnonymously());
    state = AsyncData(user);
    return user;
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = await _repo.currentUser();
      return _remember(user ?? await _repo.signInAnonymously());
    });
  }

  Future<void> updateName(String name) async {
    await _repo.updateName(name);
    final user = await _repo.currentUser();
    if (user != null) state = AsyncData(_remember(user));
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, models.User?>(AuthNotifier.new);

final currentUserIdProvider = Provider<String?>((ref) => ref.watch(authProvider).value?.$id);
final isGuestProvider = Provider<bool>((ref) {
  final u = ref.watch(authProvider).value;
  return u == null || u.email.isEmpty;
});
