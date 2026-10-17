import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics.dart';
import '../../core/app_links.dart';
import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../state/inbox.dart';
import '../../state/profile.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../links/deep_links.dart';

/// Social > Inbox (owner, 2026-10-16): messages from Carden to this player, newest first. A row
/// shows the subject, when it came, the start of the text and a reward still waiting; an unopened
/// message has a dot (and the Social tab too). A row swipes away to delete it.
class InboxList extends ConsumerWidget {
  const InboxList({super.key});

  static const _dividerIndent = 30.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final loaded = ref.watch(inboxMessagesProvider);
    final items = ref.watch(inboxProvider);
    final side = 20 + pageInsetOf(context, maxWidth: PageWidth.reading);
    final Widget body;
    if (!loaded.hasValue && loaded.isLoading) {
      body = const Padding(padding: EdgeInsets.all(30), child: Loader());
    } else if (loaded.hasError && !loaded.hasValue) {
      body = EmptyState(
        icon: AppIcons.signal,
        title: 'Messages could not load',
        message: 'Check your connection and try again.',
        action: BigButton(label: 'Try again', kind: ButtonKind.secondary, height: 44, expand: false, onTap: () => ref.invalidate(inboxMessagesProvider)),
      );
    } else if (items.isEmpty) {
      body = const EmptyState(icon: AppIcons.mail, title: 'No messages', message: 'Messages from Carden show here, now and then with a small gift.');
    } else {
      body = SoftCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (final (i, item) in items.indexed) ...[
              if (i > 0) Divider(height: 1, thickness: 1, indent: _dividerIndent, color: c.stroke),
              Dismissible(
                key: ValueKey('message-${item.message.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: c.danger,
                  child: const Icon(AppIcons.trash, color: Colors.white),
                ),
                confirmDismiss: (_) => confirmDeleteMessage(context, item),
                onDismissed: (_) => ref.read(profileProvider.notifier).deleteMessage(item.message.id),
                child: _MessageRow(item: item),
              ),
            ],
          ],
        ),
      );
    }
    return RefreshIndicator.adaptive(
      onRefresh: () => ref.refresh(inboxMessagesProvider.future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(side, 0, side, GlassTabBar.scrollEndPadding(context)),
        children: [body],
      ),
    );
  }
}

/// Asks before a message is deleted (it leaves the inbox on every device).
Future<bool> confirmDeleteMessage(BuildContext context, InboxItem item) => showAppAlert(
      context,
      title: 'Delete message?',
      message: item.claimable ? 'Its gift has not been claimed yet. The message leaves your inbox on every device.' : 'It leaves your inbox on every device.',
      confirmLabel: 'Delete',
      destructive: true,
    );

/// "Today, 21:05" in the device's own clock format.
String _when(BuildContext context, DateTime local) => formatMessageDate(local, TimeOfDay.fromDateTime(local).format(context));

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.item});
  final InboxItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = item.message;
    final unseen = !item.seen;
    return Semantics(
      button: true,
      label: [if (unseen) 'New', m.subject, _when(context, m.sentAt), if (item.claimable) 'Gift to claim'].join(', '),
      excludeSemantics: true,
      child: Pressable(
        key: ValueKey('message-row-${m.id}'),
        scale: 0.99,
        onTap: () => showMessageSheet(context, m.id),
        child: Container(
          color: c.card,
          padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // The dot of a message not opened yet (with the bold subject, so it never rests on colour).
              SizedBox(
                width: 20,
                child: unseen ? Center(child: Container(width: 9, height: 9, decoration: BoxDecoration(color: context.accent, shape: BoxShape.circle))) : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(m.subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: TypeSize.body, fontWeight: unseen ? FontWeight.w700 : FontWeight.w500, color: c.textPrimary)),
                        ),
                        const SizedBox(width: 8),
                        // A gift still waiting: a small gift mark before the time.
                        if (item.claimable) ...[Icon(AppIcons.gift, size: 13, color: context.accent), const SizedBox(width: 4)],
                        Text(_when(context, m.sentAt), style: TextStyle(fontSize: TypeSize.caption, color: c.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(m.body, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(AppIcons.chevronRight, size: 15, color: c.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// A message's gift: what it is, what claiming does, the amounts and the Claim button; once
/// claimed, a check and where it went.
class _GiftCard extends StatelessWidget {
  const _GiftCard({required this.item, required this.onClaim});
  final InboxItem item;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final claimed = item.claimed;
    return Container(
      key: const ValueKey('message-gift'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: c.accentTint,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: context.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: context.accentFill, shape: BoxShape.circle),
                child: Icon(AppIcons.gift, size: 18, color: context.onAccent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('A gift from Carden', style: TextStyle(fontSize: TypeSize.headline, fontWeight: FontWeight.w700, color: c.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      claimed ? 'Claimed. It is in your balance, ready for your next pack.' : 'Claim it to add it to your balance. It stays here until you do.',
                      style: TextStyle(fontSize: TypeSize.footnote, height: 1.35, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _RewardChips(message: item.message, large: true),
          const SizedBox(height: 14),
          if (claimed)
            Row(
              key: const ValueKey('message-claimed'),
              children: [
                Icon(AppIcons.checkmarkCircleFill, size: 18, color: c.success),
                const SizedBox(width: 6),
                Text('Claimed', style: TextStyle(fontSize: TypeSize.callout, fontWeight: FontWeight.w600, color: c.textPrimary)),
              ],
            )
          else
            BigButton(key: const ValueKey('message-claim'), label: 'Claim', icon: AppIcons.gift, onTap: onClaim),
        ],
      ),
    );
  }
}

/// The gift of a message, one chip per currency.
class _RewardChips extends StatelessWidget {
  const _RewardChips({required this.message, this.large = false});
  final InboxMessage message;
  final bool large;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (currency, amount) in message.reward)
            Container(
              padding: EdgeInsets.symmetric(horizontal: large ? 12 : 9, vertical: large ? 7 : 4),
              decoration: BoxDecoration(color: large ? context.colors.card : context.colors.accentTint, borderRadius: BorderRadius.circular(Radii.pill)),
              child: Amount(currency: currency, value: amount, size: large ? 18 : 14, fontSize: large ? TypeSize.body : TypeSize.footnote, weight: FontWeight.w700),
            ),
        ],
      );
}

/// A message on its own: subject, when it came, the whole text, its gift, an optional button that
/// opens a place in the app, and Claim (a gift still waiting) or Close. Opening it marks it seen.
Future<void> showMessageSheet(BuildContext context, String id) => showAppSheet(context, scrollable: true, builder: (_) => _MessageSheet(id: id));

class _MessageSheet extends ConsumerStatefulWidget {
  const _MessageSheet({required this.id});
  final String id;

  @override
  ConsumerState<_MessageSheet> createState() => _MessageSheetState();
}

class _MessageSheetState extends ConsumerState<_MessageSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(profileProvider.notifier).markMessageSeen(widget.id);
    });
    AppAnalytics.event('inbox_message_opened');
  }

  void _claim(InboxMessage m) {
    final paid = ref.read(profileProvider.notifier).claimMessage(m.id, coins: m.coins, tickets: m.tickets, hints: m.hints, peeks: m.peeks, magics: m.magics);
    if (!paid) return;
    AppAnalytics.event('inbox_message_claimed', {'coins': m.coins, 'tickets': m.tickets, 'hints': m.hints, 'peeks': m.peeks, 'magics': m.magics});
    Sfx.instance.coin();
    Haptics.success();
    final words = [
      for (final (currency, amount) in m.reward) '${formatCount(amount)} ${_unit(currency, amount)}',
    ];
    showToast(context, 'Added ${words.join(', ')}', icon: AppIcons.gift);
  }

  static String _unit(Currency c, int n) => switch (c) {
        Currency.coins => n == 1 ? 'coin' : 'coins',
        Currency.tickets => n == 1 ? 'ticket' : 'tickets',
        Currency.hints => n == 1 ? 'hint' : 'hints',
        Currency.peeks => n == 1 ? 'Peek' : 'Peeks',
        Currency.magics => 'Magic',
      };

  Future<void> _delete(InboxItem item) async {
    if (!await confirmDeleteMessage(context, item) || !mounted) return;
    ref.read(profileProvider.notifier).deleteMessage(item.message.id);
    Navigator.of(context).pop();
    showToast(context, 'Message deleted', icon: AppIcons.trash);
  }

  void _openLink(AppLink link) {
    final deepLinks = ref.read(deepLinksProvider);
    Navigator.of(context).pop();
    AppAnalytics.event('inbox_button_tapped', {'to': DeepLinks.linkTarget(link.path)});
    deepLinks.show(link);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final item = ref.watch(inboxProvider).where((i) => i.message.id == widget.id).firstOrNull;
    // Deleted or expired meanwhile: nothing left to show.
    if (item == null) {
      return const Padding(padding: EdgeInsets.all(30), child: EmptyState(icon: AppIcons.mail, title: 'Message not available', message: 'It may have expired or been deleted.'));
    }
    final m = item.message;
    final link = m.ctaLink == null ? null : AppLink.parse(Uri.parse(m.ctaLink!));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        key: ValueKey('message-sheet-${m.id}'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetHeader(title: m.subject, subtitle: _when(context, m.sentAt)),
          const SizedBox(height: 14),
          Text(m.body, style: TextStyle(fontSize: TypeSize.callout, height: 1.45, color: c.textPrimary)),
          if (m.expiresAt != null) ...[
            const SizedBox(height: 10),
            Text('In your inbox until ${_when(context, m.expiresAt!)}', style: TextStyle(fontSize: TypeSize.footnote, color: c.textTertiary)),
          ],
          if (m.hasReward) ...[
            const SizedBox(height: 18),
            _GiftCard(item: item, onClaim: () => _claim(m)),
          ],
          const SizedBox(height: 20),
          if (link != null) ...[
            BigButton(key: const ValueKey('message-cta'), label: m.ctaLabel ?? 'Open', kind: ButtonKind.secondary, onTap: () => _openLink(link)),
            const SizedBox(height: 10),
          ],
          // The gift is claimed in its card; this one closes the message.
          BigButton(key: const ValueKey('message-close'), label: 'Close', kind: link == null && !item.claimable ? ButtonKind.primary : ButtonKind.ghost, onTap: () => Navigator.of(context).pop()),
          const SizedBox(height: 6),
          Center(
            child: Pressable(
              key: const ValueKey('message-delete'),
              onTap: () => _delete(item),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(AppIcons.trash, size: 14, color: c.danger),
                    const SizedBox(width: 6),
                    Text('Delete message', style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.danger)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
