import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          padding: const EdgeInsets.fromLTRB(10, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The dot of a message not opened yet (with the bold subject, so it never rests on colour).
              SizedBox(
                width: 20,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: unseen ? Center(child: Container(width: 9, height: 9, decoration: BoxDecoration(color: context.accent, shape: BoxShape.circle))) : null,
                ),
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
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: TypeSize.body, fontWeight: unseen ? FontWeight.w700 : FontWeight.w500, color: c.textPrimary)),
                        ),
                        const SizedBox(width: 8),
                        Text(_when(context, m.sentAt), style: TextStyle(fontSize: TypeSize.caption, color: c.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(m.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: TypeSize.footnote, height: 1.35, color: c.textSecondary)),
                    if (item.claimable) ...[
                      const SizedBox(height: 8),
                      _RewardChips(message: m),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Padding(padding: const EdgeInsets.only(top: 3), child: Icon(AppIcons.chevronRight, size: 15, color: c.textTertiary)),
            ],
          ),
        ),
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
              decoration: BoxDecoration(color: context.colors.accentTint, borderRadius: BorderRadius.circular(Radii.pill)),
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
  }

  void _claim(InboxMessage m) {
    final paid = ref.read(profileProvider.notifier).claimMessage(m.id, coins: m.coins, tickets: m.tickets, hints: m.hints, peeks: m.peeks, magics: m.magics);
    if (!paid) return;
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
            const SizedBox(height: 16),
            SoftCard(
              padding: Insets.cardCompact,
              child: Row(
                children: [
                  Icon(AppIcons.gift, size: 20, color: context.accent),
                  const SizedBox(width: 10),
                  Expanded(child: _RewardChips(message: m, large: true)),
                  if (item.claimed) ...[
                    const SizedBox(width: 8),
                    Icon(AppIcons.checkmarkCircleFill, size: 16, color: c.success),
                    const SizedBox(width: 4),
                    Text('Claimed', style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textSecondary)),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (link != null) ...[
            BigButton(key: const ValueKey('message-cta'), label: m.ctaLabel ?? 'Open', kind: ButtonKind.secondary, onTap: () => _openLink(link)),
            const SizedBox(height: 10),
          ],
          if (item.claimable)
            BigButton(key: const ValueKey('message-claim'), label: 'Claim', icon: AppIcons.gift, onTap: () => _claim(m))
          else
            BigButton(key: const ValueKey('message-close'), label: 'Close', kind: link == null ? ButtonKind.primary : ButtonKind.ghost, onTap: () => Navigator.of(context).pop()),
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
