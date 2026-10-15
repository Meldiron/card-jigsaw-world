import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/links.dart';
import '../../core/platform.dart';
import '../../core/reminders.dart';
import '../../core/theme/tokens.dart';
import '../../state/auth.dart';
import '../../state/sync.dart';
import '../../state/catalog.dart';
import '../../models/models.dart';
import 'stats.dart' show formatCount;
import '../../state/purchases.dart';
import '../../state/reminders.dart';
import '../../state/settings.dart';
import '../../data/purchases.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../social/player_safety.dart';
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
                      if (i < rows.length - 1) Divider(height: 1, color: c.stroke, indent: _Row.textInset),
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
              icon: CupertinoIcons.circle_lefthalf_fill,
              label: 'Theme',
              value: s.themeMode,
              options: const {ThemeMode.system: 'Auto', ThemeMode.light: 'Light', ThemeMode.dark: 'Dark'},
              onChanged: n.setThemeMode,
            ),
          ]),
          group('Sound', [
            _SwitchRow(icon: CupertinoIcons.music_note, label: 'Music', value: s.music, onChanged: n.setMusic),
            _SwitchRow(icon: CupertinoIcons.speaker_2, label: 'Sound effects', value: s.sound, onChanged: n.setSound),
            _SwitchRow(icon: CupertinoIcons.waveform, label: 'Haptics', value: s.haptics, onChanged: n.setHaptics),
          ]),
          group('Gameplay', [
            _SwitchRow(icon: CupertinoIcons.timer, label: 'Show timer', value: s.showTimer, onChanged: n.setShowTimer),
            // Reminders are local iOS notifications; the rows are hidden elsewhere.
            if (caps.notifications) ...[
              _SwitchRow(
                key: const ValueKey('settings-reminders'),
                icon: CupertinoIcons.bell,
                label: 'Daily reminders',
                subtitle: 'One a day with the daily puzzle',
                value: s.reminders,
                onChanged: (v) => _toggleReminders(context, ref, v),
              ),
              if (s.reminders)
                _ValueRow(
                  key: const ValueKey('settings-reminder-time'),
                  icon: CupertinoIcons.clock,
                  label: 'Reminder time',
                  value: _minutesOfDay(s.reminderMinutes).format(context),
                  onTap: () => _pickReminderTime(context, ref, s.reminderMinutes),
                ),
              // A note before a world-day event opens, for players who have not played for a while.
              if (s.reminders)
                _SwitchRow(
                  key: const ValueKey('settings-event-reminders'),
                  icon: CupertinoIcons.flag,
                  label: 'New events',
                  subtitle: 'The evening before an event opens',
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
            _NavRow(key: const ValueKey('settings-blocked'), icon: AppIcons.block, label: 'Blocked players', onTap: () => showBlockedPlayersSheet(context)),
            // Pack codes (giveaways, special posts): a row on the web only. On iPhone a code opens
            // through its link (`/redeem?code=`, docs/deep-links.md), never from a menu (owner, 2026-10-15).
            if (caps.isWeb)
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
            _NavRow(
              key: const ValueKey('settings-support'), external: true,
              icon: CupertinoIcons.question_circle,
              label: 'Support',
              onTap: () async {
                if (!await openLink(AppLinks.support) && context.mounted) showToast(context, AppLinks.supportEmail, icon: AppIcons.mail);
              },
            ),
            _NavRow(key: const ValueKey('settings-privacy'), external: true, icon: CupertinoIcons.lock_shield, label: 'Privacy policy', onTap: () => _open(context, AppLinks.privacyPolicy)),
            _NavRow(key: const ValueKey('settings-terms'), external: true, icon: CupertinoIcons.doc_plaintext, label: 'Terms of use', onTap: () => _open(context, AppLinks.termsOfUse)),
            // App Store features (gift codes, reviews) exist on Apple platforms only.
            if (caps.giftCodes)
              _NavRow(
                key: const ValueKey('settings-rate'), external: true,
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
            _InfoRow(key: const ValueKey('settings-version'), icon: CupertinoIcons.info_circle, label: 'Version', value: ref.watch(appVersionProvider).value ?? ''),
          ]),
        ],
      ),
    );
  }

  static TimeOfDay _minutesOfDay(int minutes) => TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  static Future<void> _open(BuildContext context, Uri url) async {
    if (!await openLink(url) && context.mounted) showToast(context, 'The page could not open. Check your connection and try again.', icon: AppIcons.signal);
  }

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
            const SheetHeader(
              title: 'Reminder time',
              subtitle: 'One a day with the daily puzzle. None on days you have already claimed your daily gift.',
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
    showAppSheet(context, builder: (_) => const _CreditsSheet());
  }
}

/// One picture source of the catalogue: its name, how many pictures it gave and their licences.
typedef CreditSource = ({String name, int count, List<String> licences});

/// The catalogue's picture sources, read from each puzzle's `source` ("Wikimedia Commons, CC BY-SA
/// 4.0", "flickr via Openverse, CC BY"), largest first, licences without versions. Built from the
/// catalogue itself, so the credits stay true as packs change.
List<CreditSource> creditSources(Iterable<Puzzle> puzzles) {
  const known = {'Unsplash via Lorem Picsum': 'Unsplash License', 'NASA Image and Video Library': 'Public domain'};
  const hosts = {'flickr': 'Flickr', 'stocksnap': 'StockSnap', 'rawpixel': 'rawpixel', 'wordpress': 'WordPress', 'inaturalist': 'iNaturalist'};
  String licence(String l) {
    l = l.replaceAll(' (AI-generated)', '').replaceAll('CC CC0', 'CC0').trim();
    final low = l.toLowerCase();
    if (low.contains('public domain') || low.startsWith('pdm') || low == 'cc pdm') return 'Public domain';
    if (l == 'Attribution') return 'CC BY';
    return RegExp(r'^CC BY(-SA)?').firstMatch(l)?.group(0) ?? l;
  }

  final counts = <String, int>{};
  final licences = <String, Set<String>>{};
  for (final p in puzzles) {
    final raw = p.source.trim();
    if (raw.isEmpty) continue;
    final cut = raw.lastIndexOf(', ');
    final tail = cut > 0 ? raw.substring(cut + 2) : '';
    final hasLicence = RegExp(r'CC|[Pp]ublic|Attribution|PDM').hasMatch(tail);
    var name = hasLicence ? raw.substring(0, cut) : raw;
    if (name == 'NASA Image Library') name = 'NASA Image and Video Library';
    if (name == 'Lorem Picsum / Unsplash') name = 'Unsplash via Lorem Picsum';
    final via = RegExp(r'^(\w+) via Openverse$').firstMatch(name);
    if (via != null) name = '${hosts[via.group(1)!.toLowerCase()] ?? via.group(1)!} via Openverse';
    final lic = hasLicence ? licence(tail) : known[name];
    counts[name] = (counts[name] ?? 0) + 1;
    if (lic != null) (licences[name] ??= <String>{}).add(lic);
  }
  const order = ['CC0', 'Public domain', 'CC BY', 'CC BY-SA'];
  int rank(String l) => order.contains(l) ? order.indexOf(l) : order.length;
  return [
    for (final e in counts.entries) (name: e.key, count: e.value, licences: (licences[e.key]?.toList() ?? [])..sort((a, b) => rank(a).compareTo(rank(b)))),
  ]..sort((a, b) => b.count.compareTo(a.count));
}

class _CreditsSheet extends ConsumerWidget {
  const _CreditsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final sources = creditSources(ref.watch(allPuzzlesProvider).value ?? const <Puzzle>[]);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.82),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        physics: const BouncingScrollPhysics(),
        children: [
          const SheetHeader(
            title: 'Image credits and licences',
            subtitle: 'The pictures come from these open collections, each in the public domain or under a licence that allows this use.',
          ),
          const SizedBox(height: 14),
          if (sources.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Loader())
          else
            SoftCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < sources.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: c.stroke, indent: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(sources[i].name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                                if (sources[i].licences.isNotEmpty)
                                  Text(sources[i].licences.join(', '), style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            formatCount(sources[i].count),
                            style: TextStyle(fontSize: 13, color: c.textTertiary, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Every picture names its author and licence on the difficulty and completion screens.',
            style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// The one settings row: a 22 pt icon column, the label (with an optional line under it), and a
/// trailing control, at least 52 pt high whatever the control (switch, chevron, value, segmented),
/// so every row lines up.
class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, this.subtitle, this.trailing, this.onTap});
  final IconData icon;
  final String label;

  /// What the row does, when the label alone does not say it.
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Where the label starts; dividers start here too, as in iOS lists.
  static const textInset = 16.0 + 22 + 12;

  @override
  Widget build(BuildContext context) {
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 22, child: Icon(icon, size: 20, color: context.accent)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 12.5, color: context.colors.textSecondary)),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
    return onTap == null ? row : Pressable(onTap: onTap, scale: 0.99, child: row);
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({super.key, required this.icon, required this.label, required this.value, required this.onChanged, this.subtitle});
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => _Row(icon: icon, label: label, subtitle: subtitle, trailing: CupertinoSwitch(value: value, activeTrackColor: Brand.success, onChanged: onChanged));
}

class _SegRow<T extends Object> extends StatelessWidget {
  const _SegRow({required this.icon, required this.label, required this.value, required this.options, required this.onChanged});
  final IconData icon;
  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => _Row(
        icon: icon,
        label: label,
        trailing: CupertinoSlidingSegmentedControl<T>(
          groupValue: value,
          backgroundColor: context.colors.boardBackground,
          thumbColor: context.colors.card,
          children: {for (final e in options.entries) e.key: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(e.value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))},
          onValueChanged: (v) => v == null ? null : onChanged(v),
        ),
      );
}

class _NavRow extends StatelessWidget {
  const _NavRow({super.key, required this.icon, required this.label, required this.onTap, this.external = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Opens a web page, mail or the App Store: an arrow out of the app instead of a chevron.
  final bool external;
  @override
  Widget build(BuildContext context) => _Row(
        icon: icon,
        label: label,
        onTap: onTap,
        trailing: Icon(external ? CupertinoIcons.arrow_up_right : CupertinoIcons.chevron_right, size: external ? 14 : 16, color: context.colors.textTertiary),
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
  Widget build(BuildContext context) => _Row(
        icon: icon,
        label: label,
        onTap: onTap,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: TextStyle(color: context.colors.textSecondary, fontSize: 15)),
            const SizedBox(width: 6),
            Icon(CupertinoIcons.chevron_right, size: 16, color: context.colors.textTertiary),
          ],
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({super.key, required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => _Row(icon: icon, label: label, trailing: Text(value, style: TextStyle(color: context.colors.textSecondary, fontSize: 15)));
}
