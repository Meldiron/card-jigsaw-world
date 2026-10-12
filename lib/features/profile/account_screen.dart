import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as enums;
import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/haptics.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories.dart';
import '../../state/auth.dart';
import '../../state/merge.dart';
import '../../state/merge_flow.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/settings.dart';
import '../../state/social.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import 'merge_sheet.dart';

/// Toast for what happened to the guest save after a sign-in.
String mergeMessage(MergeOutcome? outcome, {required String signedIn}) => switch (outcome) {
      null || MergeOutcome.linked => signedIn,
      MergeOutcome.keptAccount => 'Welcome back. Your newer progress was kept.',
      MergeOutcome.keptGuest => 'Welcome back. Your progress on this device was added to your account.',
    };

/// Where the web OAuth redirect comes back to. Matches the URL strategy in
/// use: with hash routing the path lives in the fragment.
({String success, String failure}) oauthCallbackUrls() {
  final origin = Uri.base.origin;
  final base = Uri.base.fragment.isNotEmpty ? '$origin/#/auth/callback' : '$origin/auth/callback';
  return (success: base, failure: '$base?error=1');
}

/// Account: sign up (links the guest session so progress is kept), sign in,
/// social providers via Appwrite OAuth2, and sign out.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});
  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _signUp = true;
  bool _busy = false;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _afterAuth() {
    ref.invalidate(profileProvider);
    ref.invalidate(progressProvider);
    ref.invalidate(friendsProvider);
    ref.invalidate(myPuzzlesProvider);
  }

  /// The guest save on this device, taken before a sign-in can switch the
  /// session to another account. Null when not a guest or nothing to keep.
  Future<SaveSnapshot?> _guestSnapshot() async {
    final user = ref.read(authProvider).value;
    if (user == null || user.email.isNotEmpty) return null;
    return ref.read(saveMergeProvider).snapshot(user.$id);
  }

  /// Combines the guest save into the account that is now signed in.
  Future<MergeOutcome?> _merge(SaveSnapshot? guest) async {
    if (guest == null) return null;
    final user = ref.read(authProvider).value;
    if (user == null) return null;
    return ref.read(saveMergeProvider).mergeInto(
      user.$id,
      guest,
      ask: (g, a) => mounted ? showMergeSheet(context, device: g, account: a) : Future.value(MergeChoice.account),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = ref.read(authProvider.notifier);
      MergeOutcome? outcome;
      if (_signUp) {
        await auth.signUp(email: _email.text.trim(), password: _password.text, name: _name.text.trim());
      } else {
        // Signing in from a guest switches accounts; carry the guest save over.
        final guest = await _guestSnapshot();
        await auth.signIn(email: _email.text.trim(), password: _password.text);
        outcome = await _merge(guest);
      }
      _afterAuth();
      if (!mounted) return;
      Haptics.success();
      showToast(context, _signUp ? 'Account created. Your progress is saved.' : mergeMessage(outcome, signedIn: 'Welcome back.'), icon: AppIcons.check);
      context.pop();
    } on AppwriteException catch (e) {
      setState(() => _error = e.message ?? 'Something went wrong');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Web: no system sheet, so the browser goes to Apple through Appwrite and
  /// comes back to `/auth/callback`. The guest save is parked in local
  /// storage first because the page reloads.
  Future<void> _appleWeb() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final merge = ref.read(saveMergeProvider);
      final guest = await _guestSnapshot();
      if (guest != null) {
        await merge.storePending(guest);
      } else {
        await merge.clearPending();
      }
      final urls = oauthCallbackUrls();
      ref.read(authRepositoryProvider).signInWithOAuthRedirect(provider: enums.OAuthProvider.apple, success: urls.success, failure: urls.failure);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _apple() async {
    if (kIsWeb) return _appleWeb();
    setState(() => _error = null);
    // Apple receives the SHA-256 of a fresh random nonce; Appwrite receives the
    // raw value and checks it against the token, which blocks replayed tokens.
    final random = Random.secure();
    final nonce = base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)));
    final hashedNonce = sha256.convert(utf8.encode(nonce)).toString();
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        nonce: hashedNonce,
      );
      final idToken = credential.identityToken;
      if (idToken == null) {
        setState(() => _error = 'Apple did not return a sign-in token. Please try again.');
        return;
      }
      // Apple only sends the name on the first authorization, never in the token.
      final name = [credential.givenName, credential.familyName].whereType<String>().where((s) => s.isNotEmpty).join(' ');
      setState(() => _busy = true);
      final guest = await _guestSnapshot();
      final switched = await ref.read(authProvider.notifier).signInWithApple(idToken: idToken, nonce: nonce, name: name);
      final outcome = switched ? await _merge(guest) : null;
      _afterAuth();
      if (!mounted) return;
      Haptics.success();
      showToast(context, mergeMessage(outcome, signedIn: 'Signed in with Apple. Your progress is saved.'), icon: AppIcons.check);
      context.pop();
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return;
      setState(() => _error = 'Sign in with Apple failed (${e.code.name}). Please try again.');
    } on AppwriteException catch (e) {
      setState(() => _error = e.message ?? 'Sign in with Apple failed. Please try again.');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sign in with Apple: the system sheet on Apple platforms, an OAuth
  /// redirect on the web.
  bool get _appleAvailable => kIsWeb || Platform.isIOS || Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = ref.watch(authProvider).value;
    final profile = ref.watch(profileProvider).value;
    final isGuest = ref.watch(isGuestProvider);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('Account'),
        leading: Padding(padding: const EdgeInsets.only(left: 12), child: RoundIconButton(icon: CupertinoIcons.xmark, size: 38, onTap: () => context.pop())),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + kToolbarHeight + 8, 20, GlassTabBar.scrollEndPadding(context)),
        children: [
          if (!isGuest) ...[
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(CupertinoIcons.checkmark_seal_fill, color: c.success),
                      const SizedBox(width: 8),
                      Text('Signed in', style: Theme.of(context).textTheme.titleLarge),
                      if (profile?.isVip == true) ...[
                        const Spacer(),
                        Chip2(label: 'VIP member', icon: AppIcons.vip, color: c.accentTint, foreground: context.accent),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(user?.name.isNotEmpty == true ? user!.name : 'Player', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  Text(user?.email ?? '', style: TextStyle(color: c.textSecondary)),
                  const SizedBox(height: 6),
                  Text('Game ID: ${user?.$id ?? ''}', style: TextStyle(fontSize: 11.5, color: c.textTertiary, fontFamily: 'Menlo')),
                  const SizedBox(height: 16),
                  BigButton(
                    label: 'Sign out',
                    kind: ButtonKind.ghost,
                    icon: CupertinoIcons.square_arrow_right,
                    onTap: () async {
                      final ok = await showAppAlert(
                        context,
                        title: 'Sign out?',
                        message: 'You will continue as a guest. Progress saved to this account stays safe.',
                        cancelLabel: 'Stay signed in',
                        confirmLabel: 'Sign out',
                        destructive: true,
                      );
                      if (!ok) return;
                      await ref.read(authProvider.notifier).signOut();
                      _afterAuth();
                      if (context.mounted) context.pop();
                    },
                  ),
                ],
              ),
            ),
          ] else ...[
            SoftCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const IconTile(icon: AppIcons.save, size: 44, radius: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Save your progress', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text('You are playing as a guest. Create a free account to keep coins, stars and puzzles on every device. Everything you have earned comes with you.', style: TextStyle(color: c.textSecondary, height: 1.4, fontSize: 13.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_appleAvailable) ...[
              const SizedBox(height: 16),
              _AppleButton(onTap: _busy ? null : _apple),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: Divider(color: c.stroke)),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('or with email', style: TextStyle(color: c.textTertiary, fontWeight: FontWeight.w500, fontSize: 12))),
                  Expanded(child: Divider(color: c.stroke)),
                ],
              ),
            ] else
              const SizedBox(height: 16),
            const SizedBox(height: 14),
            CupertinoSlidingSegmentedControl<bool>(
              groupValue: _signUp,
              backgroundColor: c.boardBackground,
              thumbColor: c.card,
              children: const {
                true: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Create account', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                false: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Sign in', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              },
              onValueChanged: (v) => setState(() => _signUp = v ?? true),
            ),
            const SizedBox(height: 14),
            if (_signUp) ...[
              TextField(controller: _name, decoration: const InputDecoration(hintText: 'Display name'), textCapitalization: TextCapitalization.words),
              const SizedBox(height: 10),
            ],
            TextField(controller: _email, decoration: const InputDecoration(hintText: 'Email'), keyboardType: TextInputType.emailAddress, autocorrect: false),
            const SizedBox(height: 10),
            TextField(controller: _password, decoration: const InputDecoration(hintText: 'Password (8+ characters)'), obscureText: true),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w500, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            BigButton(label: _signUp ? 'Create account' : 'Sign in', loading: _busy, onTap: _submit),
            const SizedBox(height: 12),
            Center(
              child: Text('By continuing you agree to the Terms and Privacy Policy.', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Black "Continue with Apple" button following Apple's Human Interface
/// Guidelines (black fill, white logo and label, 44pt minimum height).
class _AppleButton extends StatelessWidget {
  const _AppleButton({required this.onTap});
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? Colors.white : Colors.black;
    final fg = dark ? Colors.black : Colors.white;
    return Pressable(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.6 : 1,
        child: Container(
          height: 50,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.md)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.apple, color: fg, size: 24),
              const SizedBox(width: 8),
              Text('Continue with Apple', style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}


/// Landing page of the web OAuth redirect (`/auth/callback`). Turns the
/// returned token into a session, merges the guest save parked before the
/// redirect, and goes home. A `user_already_exists` failure on the first
/// attempt means the Apple ID belongs to another account: the guest session
/// is dropped and the redirect runs once more to sign into that account.
class AuthCallbackScreen extends ConsumerStatefulWidget {
  const AuthCallbackScreen({super.key, required this.query});
  final Map<String, String> query;
  @override
  ConsumerState<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends ConsumerState<AuthCallbackScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  void _invalidate() {
    ref.invalidate(profileProvider);
    ref.invalidate(progressProvider);
    ref.invalidate(friendsProvider);
    ref.invalidate(myPuzzlesProvider);
  }

  Future<void> _run() async {
    final merge = ref.read(saveMergeProvider);
    final auth = ref.read(authProvider.notifier);
    final repo = ref.read(authRepositoryProvider);
    final pending = merge.pending();
    try {
      if (widget.query.containsKey('error')) {
        if (kIsWeb && pending != null && pending.attempt == 1) {
          await repo.signOut();
          await merge.storePending(pending.snapshot, attempt: 2);
          final urls = oauthCallbackUrls();
          repo.signInWithOAuthRedirect(provider: enums.OAuthProvider.apple, success: urls.success, failure: urls.failure);
          return;
        }
        await merge.clearPending();
        await auth.refresh();
        if (mounted) setState(() => _error = 'Sign in with Apple did not complete. Please try again.');
        return;
      }
      final userId = widget.query['userId'], secret = widget.query['secret'];
      final user = userId != null && secret != null ? await auth.signInWithToken(userId: userId, secret: secret) : await auth.refresh();
      if (user == null) {
        await merge.clearPending();
        if (mounted) setState(() => _error = 'Could not reach the game server. Please try again.');
        return;
      }
      MergeOutcome? outcome;
      if (pending != null) {
        outcome = await merge.mergeInto(
          user.$id,
          pending.snapshot,
          ask: (g, a) => mounted ? showMergeSheet(context, device: g, account: a) : Future.value(MergeChoice.account),
        );
      }
      await merge.clearPending();
      _invalidate();
      if (!ref.read(settingsProvider).onboarded) ref.read(settingsProvider.notifier).setOnboarded();
      if (!mounted) return;
      showToast(context, mergeMessage(outcome, signedIn: 'Signed in with Apple. Your progress is saved.'), icon: AppIcons.check);
      context.go('/home');
    } on AppwriteException catch (e) {
      await merge.clearPending();
      if (mounted) setState(() => _error = e.message ?? 'Sign in failed. Please try again.');
    } catch (e) {
      await merge.clearPending();
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.canvas,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Loader(),
                    const SizedBox(height: 14),
                    Text('Signing you in', style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w500)),
                  ],
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: c.textPrimary, height: 1.4)),
                      const SizedBox(height: 18),
                      BigButton(label: 'Back to the game', onTap: () => context.go('/home')),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
