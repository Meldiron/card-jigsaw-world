import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform.dart';
import '../../core/theme/tokens.dart';
import '../../state/auth.dart';
import '../../state/profile.dart';
import '../../state/purchases.dart';
import '../../state/settings.dart';
import '../../data/purchases.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final isGuest = ref.watch(isGuestProvider);
    final caps = ref.watch(platformCapsProvider);

    Widget group(String title, List<Widget> rows) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(title.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: c.textTertiary)),
              ),
              SoftCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      rows[i],
                      if (i < rows.length - 1) Divider(height: 1, color: c.stroke, indent: 16),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('Settings'),
        leading: Padding(padding: const EdgeInsets.only(left: 12), child: RoundIconButton(icon: CupertinoIcons.back, size: 38, onTap: () => context.pop())),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + kToolbarHeight, bottom: 40),
        children: [
          group('Appearance', [
            _SegRow(
              label: 'Theme',
              value: s.themeMode,
              options: const {ThemeMode.system: 'Auto', ThemeMode.light: 'Light', ThemeMode.dark: 'Dark'},
              onChanged: n.setThemeMode,
            ),
          ]),
          group('Sound', [
            _SwitchRow(icon: CupertinoIcons.music_note_2, label: 'Music', value: s.music, onChanged: n.setMusic),
            _SwitchRow(icon: CupertinoIcons.speaker_2_fill, label: 'Sound effects', value: s.sound, onChanged: n.setSound),
            _SwitchRow(icon: CupertinoIcons.waveform, label: 'Haptics', value: s.haptics, onChanged: n.setHaptics),
          ]),
          group('Gameplay', [
            _SwitchRow(icon: CupertinoIcons.time, label: 'Show timer', value: s.showTimer, onChanged: n.setShowTimer),
            // Reminders are not wired on web, so the switch is hidden there.
            if (caps.notifications) _SwitchRow(icon: CupertinoIcons.bell_fill, label: 'Daily reminders', value: s.notifications, onChanged: n.setNotifications),
          ]),
          group('Account', [
            _NavRow(icon: CupertinoIcons.person_crop_circle, label: isGuest ? 'Sign in or create account' : 'Manage account', onTap: () => context.push('/account')),
            // Gift codes and restores go through StoreKit; both rows are
            // hidden where there is no store (web).
            if (caps.purchases) _NavRow(
              icon: CupertinoIcons.gift,
              label: 'Redeem a gift code',
              onTap: () async {
                final opened = await ref.read(purchaseServiceProvider).presentCodeRedemptionSheet();
                if (!opened && context.mounted) showToast(context, 'Gift codes can be redeemed on iPhone and iPad through the App Store.', icon: CupertinoIcons.gift);
              },
            ),
            if (caps.purchases) _NavRow(
              icon: CupertinoIcons.bag,
              label: 'Restore purchases',
              onTap: () async {
                showToast(context, 'Restoring purchases…', icon: AppIcons.receipt);
                final service = ref.read(purchaseServiceProvider);
                await service.start();
                final sub = service.events.listen((e) {
                  if (!context.mounted) return;
                  if (e is RestoreFinished) {
                    ref.read(profileProvider.notifier).refresh();
                    showToast(context, e.count > 0 ? 'Purchases restored' : 'No purchases to restore', icon: AppIcons.receipt);
                  } else if (e is PurchaseFailed) {
                    showToast(context, e.message, icon: AppIcons.receipt);
                  }
                });
                await service.restorePurchases();
                await Future.delayed(const Duration(seconds: 1));
                await sub.cancel();
              },
            ),
          ]),
          group('About', [
            _NavRow(icon: CupertinoIcons.doc_text, label: 'Image credits and licences', onTap: () => _showCredits(context)),
            _NavRow(icon: CupertinoIcons.question_circle, label: 'Support', onTap: () => showToast(context, 'support@almostapps.eu', icon: AppIcons.mail)),
            const _InfoRow(label: 'Version', value: '1.6.0 (9)'),
          ]),
        ],
      ),
    );
  }

  void _showCredits(BuildContext context) {
    showAppSheet(
      context,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Image credits', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              'Photo packs use images from Lorem Picsum (Unsplash License). '
              'The Masterpieces pack uses public-domain works from the Cleveland Museum of Art (CC0). '
              'Deep Space uses imagery from the NASA Image and Video Library. '
              'Each puzzle shows its author on the difficulty and completion screens.',
              style: TextStyle(color: context.colors.textSecondary, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.icon, required this.label, required this.value, required this.onChanged});
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: context.accent),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
            CupertinoSwitch(value: value, activeTrackColor: Brand.success, onChanged: onChanged),
          ],
        ),
      );
}

class _SegRow<T extends Object> extends StatelessWidget {
  const _SegRow({required this.label, required this.value, required this.options, required this.onChanged});
  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
            CupertinoSlidingSegmentedControl<T>(
              groupValue: value,
              backgroundColor: context.colors.boardBackground,
              thumbColor: context.colors.card,
              children: {for (final e in options.entries) e.key: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(e.value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))},
              onValueChanged: (v) => v == null ? null : onChanged(v),
            ),
          ],
        ),
      );
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        scale: 0.99,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: context.accent),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
              Icon(CupertinoIcons.chevron_right, size: 16, color: context.colors.textTertiary),
            ],
          ),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
            Text(value, style: TextStyle(color: context.colors.textSecondary)),
          ],
        ),
      );
}
