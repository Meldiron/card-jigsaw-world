import 'package:appwrite/models.dart' as models;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/qa.dart';
import '../data/repositories.dart';

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
      if (user != null) return await repo.markQaGuest(user);
      // The web OAuth callback is about to create the real session; a
      // throwaway guest here would only get in its way.
      if (isOAuthCallback) return null;
      return await repo.signInAnonymously();
    } catch (e) {
      // Offline or backend unreachable: continue as a local guest.
      return null;
    }
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// True while the web app is loading on `/auth/callback` (path or hash routing).
  static bool get isOAuthCallback => kIsWeb && (Uri.base.path.contains('/auth/callback') || Uri.base.fragment.contains('/auth/callback'));

  Future<void> signUp({required String email, required String password, required String name}) async {
    final current = state.value;
    final isAnon = current != null && current.email.isEmpty;
    final user = isAnon
        ? await _repo.linkAnonymous(email: email, password: password, name: name)
        : await _repo.signUp(email: email, password: password, name: name);
    state = AsyncData(user);
  }

  Future<void> signIn({required String email, required String password}) async {
    // If we are a guest, end that session first.
    await _repo.signOut();
    final user = await _repo.signIn(email: email, password: password);
    state = AsyncData(user);
  }

  /// Native Sign in with Apple: the credential comes from the system sheet,
  /// Appwrite verifies the ID token and either links it to the current guest
  /// or signs the returning player into their existing account.
  /// Returns true when the player was signed in to an existing account
  /// (the guest progress on this device is left behind in that case).
  Future<bool> signInWithApple({required String idToken, required String nonce, String? name}) async {
    final result = await _repo.signInWithAppleIdToken(idToken: idToken, nonce: nonce, name: name);
    state = AsyncData(result.user);
    return result.switched;
  }

  /// Web OAuth redirect: the callback brings a token; this turns it into a
  /// session (the guest session, if any, is replaced).
  Future<models.User> signInWithToken({required String userId, required String secret}) async {
    // Appwrite refuses a token session while another session is active, and
    // whatever session is here (the guest, or a stale one) is being replaced.
    await _repo.signOut();
    final user = await _repo.createSessionFromToken(userId: userId, secret: secret);
    state = AsyncData(user);
    return user;
  }

  /// Re-reads the session after the page reloaded (web OAuth callback) and
  /// returns the user, falling back to a fresh guest.
  Future<models.User?> refresh() async {
    await retry();
    return state.value;
  }

  Future<void> signOut() async {
    await _repo.signOut();
    state = const AsyncLoading();
    state = AsyncData(await _repo.signInAnonymously());
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = await _repo.currentUser();
      return user ?? await _repo.signInAnonymously();
    });
  }

  Future<void> updateName(String name) async {
    await _repo.updateName(name);
    final user = await _repo.currentUser();
    if (user != null) state = AsyncData(user);
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, models.User?>(AuthNotifier.new);

final currentUserIdProvider = Provider<String?>((ref) => ref.watch(authProvider).value?.$id);
final isGuestProvider = Provider<bool>((ref) {
  final u = ref.watch(authProvider).value;
  return u == null || u.email.isEmpty;
});
