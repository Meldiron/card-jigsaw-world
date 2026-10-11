import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as enums;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/theme/tokens.dart';
import '../../state/auth.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/social.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

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

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = ref.read(authProvider.notifier);
      if (_signUp) {
        await auth.signUp(email: _email.text.trim(), password: _password.text, name: _name.text.trim());
      } else {
        await auth.signIn(email: _email.text.trim(), password: _password.text);
      }
      _afterAuth();
      if (!mounted) return;
      Haptics.success();
      showToast(context, _signUp ? 'Account created. Your progress is saved.' : 'Welcome back.', icon: AppIcons.check);
      context.pop();
    } on AppwriteException catch (e) {
      setState(() => _error = e.message ?? 'Something went wrong');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _oauth(enums.OAuthProvider provider) async {
    setState(() => _error = null);
    try {
      await ref.read(authProvider.notifier).signInWithProvider(provider);
      _afterAuth();
      if (mounted) context.pop();
    } on AppwriteException catch (e) {
      setState(() => _error = '${provider.name} sign-in is not configured yet (${e.message}). Enable it in the Appwrite console under Auth → Settings.');
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = ref.watch(authProvider).value;
    final profile = ref.watch(profileProvider).value;
    final isGuest = ref.watch(isGuestProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
        leading: Padding(padding: const EdgeInsets.only(left: 12), child: RoundIconButton(icon: CupertinoIcons.xmark, size: 38, onTap: () => context.pop())),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
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
                      final ok = await showCupertinoDialog<bool>(
                        context: context,
                        builder: (ctx) => CupertinoAlertDialog(
                          title: const Text('Sign out?'),
                          content: const Text('You will continue as a guest. Progress saved to this account stays safe.'),
                          actions: [
                            CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay signed in')),
                            CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
                          ],
                        ),
                      );
                      if (ok != true) return;
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
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _Social(label: 'Apple', icon: Icons.apple, onTap: () => _oauth(enums.OAuthProvider.apple))),
                const SizedBox(width: 8),
                Expanded(child: _Social(label: 'Google', icon: Icons.g_mobiledata_rounded, onTap: () => _oauth(enums.OAuthProvider.google))),
                const SizedBox(width: 8),
                Expanded(child: _Social(label: 'Facebook', icon: Icons.facebook, color: const Color(0xFF1877F2), onTap: () => _oauth(enums.OAuthProvider.facebook))),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: Divider(color: c.stroke)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('or with email', style: TextStyle(color: c.textTertiary, fontWeight: FontWeight.w500, fontSize: 12))),
                Expanded(child: Divider(color: c.stroke)),
              ],
            ),
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

class _Social extends StatelessWidget {
  const _Social({required this.label, required this.icon, required this.onTap, this.color});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(Radii.md), border: Border.all(color: c.stroke)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color ?? c.textPrimary, size: 22),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
