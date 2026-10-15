import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as enums;
import 'package:appwrite/models.dart' as models;
import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:go_router/go_router.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/haptics.dart';
import '../../core/links.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories.dart';
import '../../models/models.dart';
import '../../state/account_deletion.dart';
import '../../state/auth.dart';
import '../../state/merge.dart';
import '../../state/merge_flow.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/settings.dart';
import '../../state/social.dart';
import '../../state/sync.dart';
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
  bool _emailOpen = false;
  late final Future<bool> _withApple = ref.read(authRepositoryProvider).hasAppleIdentity();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  late final _termsTap = TapGestureRecognizer()..onTap = () => openLink(AppLinks.termsOfUse);
  late final _privacyTap = TapGestureRecognizer()..onTap = () => openLink(AppLinks.privacyPolicy);

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  void _afterAuth() {
    // The merge wrote to the account after it loaded: take those rows in without the alert.
    ref.read(syncProvider.notifier).sync(silent: true);
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

  bool _deleting = false;

  /// Account > Delete account (App Store guideline 5.1.1(v)): guests and signed-in players alike.
  /// A sheet lists what goes (and, for VIP members, that Apple keeps billing until they cancel,
  /// with Manage subscription); its one red button asks a last time in an alert. Players who
  /// signed in with Apple then confirm with Apple once more, so the server can revoke the game's
  /// access to their Apple ID.
  Future<void> _deleteAccount() async {
    final isVip = (ref.read(profileProvider).value?.isVip ?? false) && !kIsWeb;
    final withApple = !kIsWeb && (Platform.isIOS || Platform.isMacOS) && await ref.read(authRepositoryProvider).hasAppleIdentity();
    if (!mounted) return;
    final proceed = await showAppSheet<bool>(context, builder: (_) => _DeleteAccountPanel(vip: isVip, withApple: withApple));
    if (proceed != true || !mounted) return;
    final ok = await showAppAlert(
      context,
      title: 'Delete account for good?',
      message: 'This cannot be undone.',
      confirmLabel: 'Delete account',
      cancelLabel: 'Cancel',
      destructive: true,
    );
    if (!ok || !mounted) return;
    String? appleCode;
    if (withApple) {
      try {
        appleCode = (await SignInWithApple.getAppleIDCredential(scopes: const [])).authorizationCode;
      } on SignInWithAppleAuthorizationException catch (e) {
        if (e.code == AuthorizationErrorCode.canceled) {
          if (mounted) showToast(context, 'Your account was not deleted', icon: AppIcons.xmarkCircle);
          return;
        }
        // Apple could not confirm: delete anyway; the server skips revoking the Apple tokens.
        debugPrint('Apple confirmation failed: ${e.code}');
      }
    }
    setState(() => _deleting = true);
    final deletion = ref.read(accountDeletionProvider);
    try {
      await deletion.deleteOnServer(appleAuthorizationCode: appleCode);
    } catch (e) {
      debugPrint('account deletion failed: $e');
      if (!mounted) return;
      setState(() => _deleting = false);
      await showAppAlert(
        context,
        title: 'Account not deleted',
        message: 'The game server could not be reached. Check your connection and try again.',
        confirmLabel: 'Close',
        cancelLabel: null,
      );
      return;
    }
    Haptics.medium();
    if (mounted) showToast(context, 'Your account was deleted', icon: AppIcons.trash);
    // The app starts over as a new guest on the welcome screens (the router follows onboarding).
    await deletion.startOver();
    if (mounted) setState(() => _deleting = false);
  }

  /// Delete account: a quiet red link at the foot of the guest sheet; a red row in its own group
  /// for a signed-in player, under Sign out.
  Widget _deleteButton(BuildContext context, {required bool guest}) {
    final c = context.colors;
    if (_deleting) return const Padding(padding: EdgeInsets.all(14), child: CupertinoActivityIndicator());
    final label = Text('Delete account', style: TextStyle(color: c.danger, fontWeight: FontWeight.w600, fontSize: guest ? TypeSize.footnote : TypeSize.callout));
    if (guest) {
      return Center(
        child: Pressable(
          key: const ValueKey('account-delete'),
          onTap: _busy ? null : _deleteAccount,
          child: TapTarget(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: label)),
        ),
      );
    }
    return SoftCard(
      padding: EdgeInsets.zero,
      child: Pressable(
        key: const ValueKey('account-delete'),
        scale: 0.99,
        onTap: _busy ? null : _deleteAccount,
        child: SizedBox(height: 50, width: double.infinity, child: Center(child: label)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).value;
    final profile = ref.watch(profileProvider).value;
    final isGuest = ref.watch(isGuestProvider);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        // A guest's sheet has its own large title ("Save your progress").
        title: Text(isGuest ? '' : 'Account'),
        // Close (X): Account is always a sheet (Home, Profile, Settings, links). Back if a page
        // ever pushes it.
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: RoundIconButton(icon: ModalRoute.of(context) is CupertinoSheetRoute ? AppIcons.xmark : AppIcons.back, size: 38, onTap: () => context.pop()),
        ),
      ),
      body: isGuest ? _guest(context, top) : _signedIn(context, top, user, profile),
    );
  }

  /// The guest sheet: what an account gives at the top, the two ways in at the bottom (Apple
  /// first, email on request), the legal line under them and a quiet Delete account at the foot.
  /// On a tall phone the actions sit low, near the thumb; on a short one the page scrolls.
  Widget _guest(BuildContext context, double top) {
    final c = context.colors;
    final bottom = GlassTabBar.scrollEndPadding(context, margin: 8);
    final form = _emailOpen || !_appleAvailable;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(24, top + 4, 24, bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: max(0, box.maxHeight - top - 4 - bottom)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---- What an account is for.
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: IconTile(icon: AppIcons.save, size: IconTile.large, radius: 18)),
                  const SizedBox(height: 16),
                  Text('Save your progress', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: TypeSize.title1, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                  const SizedBox(height: 8),
                  Text(
                    'A free account keeps your coins, stars and puzzles on every device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: TypeSize.body, height: 1.4, color: c.textSecondary),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: form
                        ? const SizedBox(width: double.infinity)
                        : const Padding(padding: EdgeInsets.only(top: 20), child: _Benefits()),
                  ),
                ],
              ),
              // ---- The ways in.
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  if (_appleAvailable) _AppleButton(onTap: _busy ? null : _apple),
                  if (_appleAvailable && !_emailOpen) ...[
                    const SizedBox(height: 12),
                    // Email is the second way in: one quiet button until the player picks it, so
                    // the sheet opens on two clear choices instead of a form.
                    _EmailButton(onTap: () => setState(() => _emailOpen = true)),
                  ],
                  if (form) ...[
                    SizedBox(height: _appleAvailable ? 24 : 0),
                    AppSegmentedControl<bool>(
                      key: const ValueKey('account-mode'),
                      value: _signUp,
                      segments: const {true: 'Create account', false: 'Sign in'},
                      onChanged: (v) => setState(() {
                        _signUp = v;
                        _error = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    _FieldGroup(
                      children: [
                        if (_signUp) _Field(controller: _name, hint: 'Display name', capitalization: TextCapitalization.words, action: TextInputAction.next),
                        _Field(controller: _email, hint: 'Email', keyboard: TextInputType.emailAddress, action: TextInputAction.next),
                        _Field(controller: _password, hint: _signUp ? 'Password (8+ characters)' : 'Password', obscure: true, action: TextInputAction.done, onSubmitted: _busy ? null : (_) => _submit()),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: TextStyle(color: c.danger, fontWeight: FontWeight.w500, fontSize: TypeSize.footnote)),
                    ],
                    const SizedBox(height: 16),
                    BigButton(key: const ValueKey('account-submit'), label: _signUp ? 'Create account' : 'Sign in', loading: _busy, onTap: _submit),
                  ],
                  const SizedBox(height: 14),
                  _legal(context),
                  const SizedBox(height: 12),
                  _deleteButton(context, guest: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legal(BuildContext context) {
    final c = context.colors;
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: TypeSize.caption, height: 1.45, color: c.textTertiary),
        children: [
          // Two balanced lines instead of a lone "policy." on the second.
          const TextSpan(text: 'By continuing you agree to the\n'),
          TextSpan(text: 'Terms of use', recognizer: _termsTap, style: TextStyle(color: context.accent, fontWeight: FontWeight.w600)),
          const TextSpan(text: ' and the '),
          TextSpan(text: 'Privacy policy', recognizer: _privacyTap, style: TextStyle(color: context.accent, fontWeight: FontWeight.w600)),
          const TextSpan(text: '.'),
        ],
      ),
      key: const ValueKey('account-legal'),
      textAlign: TextAlign.center,
    );
  }

  /// A signed-in player: the Apple ID page idiom. Who you are, centred, then grouped rows; Sign out
  /// and Delete account are rows too, each in its own group.
  Widget _signedIn(BuildContext context, double top, models.User? user, Profile? profile) {
    final c = context.colors;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, top + 8, 20, GlassTabBar.scrollEndPadding(context)),
      children: [
        const SizedBox(height: 8),
        Center(child: AvatarCircle(avatarKey: profile?.avatar, size: 76, border: true)),
        const SizedBox(height: 10),
        Text(user?.name.isNotEmpty == true ? user!.name : 'Player', textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 2),
        Text(user?.email ?? '', textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontSize: TypeSize.body)),
        const SizedBox(height: 20),
        SoftCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              FutureBuilder<bool>(
                future: _withApple,
                builder: (context, snap) => _AccountLine(label: 'Signed in with', value: snap.data == true ? 'Apple' : 'Email', icon: snap.data == true ? AppIcons.appleLogo : AppIcons.mail),
              ),
              Divider(height: 1, color: c.stroke),
              if (profile?.isVip == true) ...[
                _AccountLine(label: 'VIP', value: 'Active', icon: AppIcons.vip),
                Divider(height: 1, color: c.stroke),
              ],
              _AccountLine(
                label: 'Game ID',
                value: user?.$id ?? '',
                icon: AppIcons.copy,
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: user?.$id ?? ''));
                  if (context.mounted) showToast(context, 'Game ID copied', icon: AppIcons.copy);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SoftCard(
          padding: EdgeInsets.zero,
          child: Pressable(
            scale: 0.99,
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
            child: SizedBox(
              height: 50,
              width: double.infinity,
              child: Center(child: Text('Sign out', style: TextStyle(color: context.accent, fontWeight: FontWeight.w600, fontSize: TypeSize.callout))),
            ),
          ),
        ),
        const SizedBox(height: 28),
        _deleteButton(context, guest: false),
        const SizedBox(height: 8),
        Text('Removes your profile, progress and photos for good.', textAlign: TextAlign.center, style: TextStyle(fontSize: TypeSize.caption, color: c.textTertiary)),
      ],
    );
  }
}

/// What an account gives, three one-line promises with their marks: the guest sheet's middle.
class _Benefits extends StatelessWidget {
  const _Benefits();
  @override
  Widget build(BuildContext context) {
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox(width: 26, child: Icon(icon, size: 20, color: context.accent)),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: const TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w500))),
            ],
          ),
        );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          children: [
            line(AppIcons.lockShield, 'Coins, stars and packs kept safe'),
            line(AppIcons.devicePhonePortrait, 'Carry on from any device'),
            line(AppIcons.friends, 'Keep your friends and league place'),
          ],
        ),
      ),
    );
  }
}

/// "Continue with email": the second way in, a quiet filled button the same size as Apple's.
class _EmailButton extends StatelessWidget {
  const _EmailButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      key: const ValueKey('account-email-open'),
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(color: context.isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(Radii.md)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(AppIcons.mail, color: c.textPrimary, size: 19),
            const SizedBox(width: 8),
            Text('Continue with email', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: TypeSize.headline, letterSpacing: -0.3)),
          ],
        ),
      ),
    );
  }
}

/// The email form's fields in one inset group, hairlines between them (the iOS sign-in idiom).
class _FieldGroup extends StatelessWidget {
  const _FieldGroup({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: 16, color: c.stroke),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.hint, this.keyboard, this.obscure = false, this.capitalization = TextCapitalization.none, this.action, this.onSubmitted});
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboard;
  final bool obscure;
  final TextCapitalization capitalization;
  final TextInputAction? action;
  final ValueChanged<String>? onSubmitted;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      obscureText: obscure,
      autocorrect: false,
      textCapitalization: capitalization,
      textInputAction: action,
      onSubmitted: onSubmitted,
      cursorColor: context.accent,
      style: TextStyle(fontSize: TypeSize.callout, color: c.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        filled: false,
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: TextStyle(fontSize: TypeSize.callout, color: c.textTertiary),
      ),
    );
  }
}

/// Account > Delete account: what goes, in calm rows; for VIP members that Apple keeps billing,
/// with Manage subscription; then one red button and a plain Cancel. The red button pops `true`;
/// the alert after it asks a last time.
class _DeleteAccountPanel extends StatelessWidget {
  const _DeleteAccountPanel({required this.vip, required this.withApple});
  final bool vip;
  final bool withApple;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget loss(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox(width: 22, child: Icon(icon, size: 19, color: c.textSecondary)),
              const SizedBox(width: 14),
              Expanded(child: Text(text, style: const TextStyle(fontSize: TypeSize.body))),
            ],
          ),
        );
    final losses = [
      loss(AppIcons.puzzle, 'Your progress, stars and level'),
      loss(AppIcons.coinGlyph, 'Coins, Tickets and Hints'),
      loss(AppIcons.bag, 'Purchases, packs and avatars'),
      loss(AppIcons.photo, 'My Puzzles photos'),
      loss(AppIcons.friends, 'Friends and your place in the league'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(title: 'Delete your account?', subtitle: 'This removes from every device, for good:'),
          const SizedBox(height: 14),
          SoftCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < losses.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, indent: 52, color: c.stroke),
                  losses[i],
                ],
              ],
            ),
          ),
          if (vip) ...[
            const SizedBox(height: 12),
            SoftCard(
              key: const ValueKey('delete-vip-note'),
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 22, child: Padding(padding: const EdgeInsets.only(top: 1), child: Icon(AppIcons.vip, size: 19, color: context.accent))),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('VIP is billed by Apple', style: TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text('Deleting your account does not cancel it. Cancel VIP in the App Store first.', style: TextStyle(fontSize: TypeSize.footnote, height: 1.35, color: c.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, thickness: 1, indent: 52, color: c.stroke),
                  Pressable(
                    key: const ValueKey('delete-manage-subscription'),
                    scale: 0.99,
                    onTap: () => launchUrl(Uri.parse('https://apps.apple.com/account/subscriptions'), mode: LaunchMode.externalApplication),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(52, 13, 16, 13),
                      child: Row(
                        children: [
                          Expanded(child: Text('Manage subscription', style: TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w600, color: context.accent))),
                          Icon(AppIcons.arrowUpRight, size: 14, color: context.accent),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (withApple) ...[
            const SizedBox(height: 10),
            Text('Apple asks you to confirm with your Apple ID once more.', style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary)),
          ],
          const SizedBox(height: 20),
          BigButton(key: const ValueKey('account-delete-continue'), label: 'Delete account', kind: ButtonKind.destructive, onTap: () => Navigator.of(context).pop(true)),
          const SizedBox(height: 6),
          BigButton(key: const ValueKey('account-delete-cancel'), label: 'Cancel', kind: ButtonKind.plain, height: 46, onTap: () => Navigator.of(context).pop(false)),
        ],
      ),
    );
  }
}

/// "Label ............ value [icon]": one fact about the signed-in account; tappable when [onTap] is set.
class _AccountLine extends StatelessWidget {
  const _AccountLine({required this.label, required this.value, required this.icon, this.onTap});
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w500)),
            const SizedBox(width: 12),
            Expanded(child: Text(value, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: TypeSize.body, color: c.textSecondary))),
            const SizedBox(width: 8),
            Icon(icon, size: 17, color: onTap == null ? c.textTertiary : context.accent),
          ],
        ),
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
              // Apple's proportions: the title is about 40% of the button height, the logo matches it.
              Icon(AppIcons.appleLogo, color: fg, size: 22),
              const SizedBox(width: 6),
              Text('Continue with Apple', style: TextStyle(color: fg, fontWeight: FontWeight.w500, fontSize: TypeSize.title3, letterSpacing: -0.3)),
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
    ref.read(syncProvider.notifier).sync(silent: true);
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
