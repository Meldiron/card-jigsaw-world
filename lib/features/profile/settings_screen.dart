import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform.dart';
import '../../core/reminders.dart';
import '../../core/theme/tokens.dart';
import '../../state/auth.dart';
import '../../state/sync.dart';
import '../../state/purchases.dart';
import '../../state/reminders.dart';
import '../../state/settings.dart';
import '../../data/purchases.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import 'redeem_code_sheet.dart';

/// The App Store page where a player writes a review of the game.
final appStoreReviewUrl = Uri.parse('https://apps.apple.com/app/id6821644423?action=write-review');

/// "1.7.0 (115)": the version and build number of the running build (the web build has no
/// build number, so it shows the version alone).
String formatAppVersion(String version, String build) => build.isEmpty || build == version ? version : '$version ($build)';

final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return formatAppVersion(info.version, info.buildNumber);
});

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
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + kToolbarHeight, bottom: GlassTabBar.scrollEndPadding(context)),
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
            // Reminders are local iOS notifications; the rows are hidden elsewhere.
            if (caps.notifications) ...[
              _SwitchRow(
                key: const ValueKey('settings-reminders'),
                icon: CupertinoIcons.bell_fill,
                label: 'Daily reminders',
                value: s.reminders,
                onChanged: (v) => _toggleReminders(context, ref, v),
              ),
              if (s.reminders)
                _ValueRow(
                  key: const ValueKey('settings-reminder-time'),
                  icon: CupertinoIcons.clock_fill,
                  label: 'Reminder time',
                  value: _minutesOfDay(s.reminderMinutes).format(context),
                  onTap: () => _pickReminderTime(context, ref, s.reminderMinutes),
                ),
              // A note before a world-day event opens, for players who have not played for a while.
              if (s.reminders)
                _SwitchRow(
                  key: const ValueKey('settings-event-reminders'),
                  icon: CupertinoIcons.flag_fill,
                  label: 'New events',
                  value: ref.watch(eventRemindersProvider),
                  onChanged: (v) {
                    ref.read(eventRemindersProvider.notifier).set(v);
                    ref.read(remindersProvider).refresh();
                  },
                ),
            ],
          ]),
          group('Account', [
            _NavRow(icon: CupertinoIcons.person_crop_circle, label: isGuest ? 'Sign in or create account' : 'Manage account', onTap: () => context.push('/account')),
            // Pack codes (giveaways, special posts) work everywhere, the web included.
            _NavRow(
              key: const ValueKey('settings-redeem-pack-code'),
              icon: AppIcons.packCode,
              label: 'Redeem a pack code',
              onTap: () => showRedeemCodeSheet(context),
            ),
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
                    ref.read(syncProvider.notifier).sync(silent: true);
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
            // App Store features (gift codes, reviews) exist on Apple platforms only.
            if (caps.giftCodes)
              _NavRow(
                key: const ValueKey('settings-rate'),
                icon: CupertinoIcons.star,
                label: 'Rate Card Jigsaw World',
                onTap: () async {
                  var opened = false;
                  try {
                    opened = await launchUrl(appStoreReviewUrl, mode: LaunchMode.externalApplication);
                  } catch (_) {}
                  if (!opened && context.mounted) showToast(context, 'The App Store could not open. Try again later.', icon: CupertinoIcons.star);
                },
              ),
            _InfoRow(key: const ValueKey('settings-version'), label: 'Version', value: ref.watch(appVersionProvider).value ?? ''),
          ]),
        ],
      ),
    );
  }

  static TimeOfDay _minutesOfDay(int minutes) => TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  /// On: asks iOS for permission the first time. When iOS says no, the switch
  /// stays off and the alert leads to the app's page in iOS Settings.
  Future<void> _toggleReminders(BuildContext context, WidgetRef ref, bool on) async {
    final reminders = ref.read(remindersProvider);
    if (!on) {
      await reminders.disable();
      return;
    }
    final granted = await reminders.enable();
    if (!context.mounted) return;
    if (granted) {
      final time = _minutesOfDay(ref.read(settingsProvider).reminderMinutes).format(context);
      showToast(context, 'Daily reminder at $time', icon: CupertinoIcons.bell_fill);
      return;
    }
    final open = await showAppAlert(
      context,
      title: 'Notifications are off',
      message: 'Allow notifications for Card Jigsaw World in iOS Settings to get a daily reminder.',
      confirmLabel: 'Open Settings',
      cancelLabel: 'Not now',
    );
    if (open) await ReminderChannel.openSettings();
  }

  Future<void> _pickReminderTime(BuildContext context, WidgetRef ref, int current) async {
    var picked = current;
    final save = await showAppSheet<bool>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reminder time', style: Theme.of(ctx).textTheme.headlineSmall),
            const SizedBox(height: 2),
            Text(
              "One a day with the daily puzzle. None on days you have already claimed your daily gift.",
              style: TextStyle(color: ctx.colors.textSecondary, fontSize: 13.5, height: 1.35),
            ),
            SizedBox(
              height: 180,
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                minuteInterval: 5,
                use24hFormat: MediaQuery.alwaysUse24HourFormatOf(ctx),
                initialDateTime: DateTime(2000, 1, 1, current ~/ 60, current % 60 - current % 5),
                onDateTimeChanged: (t) => picked = t.hour * 60 + t.minute,
              ),
            ),
            const SizedBox(height: 8),
            BigButton(key: const ValueKey('reminder-time-save'), label: 'Set time', onTap: () => Navigator.pop(ctx, true)),
          ],
        ),
      ),
    );
    if (save != true) return;
    await ref.read(remindersProvider).setTime(picked);
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
  const _SwitchRow({super.key, required this.icon, required this.label, required this.value, required this.onChanged});
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
  const _NavRow({super.key, required this.icon, required this.label, required this.onTap});
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

/// A setting with its current value on the right; tapping changes it.
class _ValueRow extends StatelessWidget {
  const _ValueRow({super.key, required this.icon, required this.label, required this.value, required this.onTap});
  final IconData icon;
  final String label;
  final String value;
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
              Text(value, style: TextStyle(color: context.colors.textSecondary, fontSize: 15)),
              const SizedBox(width: 6),
              Icon(CupertinoIcons.chevron_right, size: 16, color: context.colors.textTertiary),
            ],
          ),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({super.key, required this.label, required this.value});
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
