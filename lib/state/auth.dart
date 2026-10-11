import 'package:appwrite/models.dart' as models;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories.dart';

/// Holds the current Appwrite user. A guest (anonymous) session is created
/// automatically so players can start immediately and link an email later.
class AuthNotifier extends AsyncNotifier<models.User?> {
  @override
  Future<models.User?> build() async {
    final repo = ref.watch(authRepositoryProvider);
    try {
      final user = await repo.currentUser();
      if (user != null) return user;
      return await repo.signInAnonymously();
    } catch (e) {
      // Offline or backend unreachable: continue as a local guest.
      return null;
    }
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

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
  Future<void> signInWithApple({required String idToken, required String nonce, String? name}) async {
    final user = await _repo.signInWithAppleIdToken(idToken: idToken, nonce: nonce, name: name);
    state = AsyncData(user);
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
