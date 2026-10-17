import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/appwrite.dart';
import '../core/name_filter.dart';
import '../data/repositories.dart';
import '../widgets/icons.dart' show Currency;
import 'auth.dart';
import 'profile.dart';

/// A message from Carden (Social > Inbox, owner 2026-10-16). Rows of the `messages` table are
/// written by `tools/dev/inbox.py` (skill: .claude/skills/inbox-messages) and readable only by the
/// players their row permissions name (one player, a label such as `early`, or everyone); what the player did with one (opened, claimed, deleted) is kept in
/// `profiles.inbox`, so nobody can change a reward and every device agrees.
class InboxMessage {
  const InboxMessage({
    required this.id,
    required this.subject,
    required this.body,
    required this.sentAt,
    this.expiresAt,
    this.coins = 0,
    this.tickets = 0,
    this.hints = 0,
    this.peeks = 0,
    this.magics = 0,
    this.ctaLabel,
    this.ctaLink,
    this.fromUserId,
    this.fromName,
    this.fromAvatar,
  });

  final String id;
  final String subject;
  final String body;
  final DateTime sentAt;

  /// After this the message leaves the inbox (null: it stays until deleted).
  final DateTime? expiresAt;
  final int coins, tickets, hints, peeks, magics;

  /// An extra button: its label and a link the app opens (`/library/pack/<id>`, `/feedback`, ...,
  /// any path `AppLink.parse` reads).
  final String? ctaLabel;
  final String? ctaLink;

  /// A friend gift (`/gift/send`, docs/friend-gifts.md): who sent it, their name then
  /// (shown through [NameFilter]) and avatar. Null for messages from Carden.
  final String? fromUserId;
  final String? fromName;
  final String? fromAvatar;

  bool get fromFriend => fromUserId != null;

  /// The sender's name as shown: the friend's (filtered), or Carden.
  String get sender => fromFriend ? NameFilter.shown(fromName ?? NameFilter.fallback) : 'Carden';

  bool get hasReward => coins > 0 || tickets > 0 || hints > 0 || peeks > 0 || magics > 0;

  /// The reward, currency by currency, in the order the store lists them.
  List<(Currency, int)> get reward => [
        if (coins > 0) (Currency.coins, coins),
        if (tickets > 0) (Currency.tickets, tickets),
        if (hints > 0) (Currency.hints, hints),
        if (peeks > 0) (Currency.peeks, peeks),
        if (magics > 0) (Currency.magics, magics),
      ];

  bool expiredAt(DateTime now) => expiresAt != null && !expiresAt!.isAfter(now);

  factory InboxMessage.fromRow(String id, Map<String, dynamic> d) {
    int n(String k) => (d[k] as num?)?.toInt() ?? 0;
    String? s(String k) {
      final v = (d[k] as String?)?.trim();
      return v == null || v.isEmpty ? null : v;
    }

    return InboxMessage(
      id: id,
      subject: (d['subject'] as String?) ?? '',
      body: (d['body'] as String?) ?? '',
      sentAt: DateTime.tryParse((d['sentAt'] as String?) ?? '')?.toLocal() ?? DateTime.now(),
      expiresAt: DateTime.tryParse((d['expiresAt'] as String?) ?? '')?.toLocal(),
      coins: n('rewardCoins'),
      tickets: n('rewardTickets'),
      hints: n('rewardHints'),
      peeks: n('rewardPeeks'),
      magics: n('rewardMagics'),
      ctaLabel: s('ctaLabel'),
      ctaLink: s('ctaLink'),
      fromUserId: s('fromUserId'),
      fromName: s('fromName'),
      fromAvatar: s('fromAvatar'),
    );
  }
}

/// A message as the player sees it now.
class InboxItem {
  const InboxItem(this.message, {required this.seen, required this.claimed});
  final InboxMessage message;
  final bool seen;
  final bool claimed;

  /// A reward is waiting: the message's button says Claim instead of Close.
  bool get claimable => message.hasReward && !claimed;
}

/// The player's messages from the server, newest first (scheduled ones wait for their time).
/// Read again when the app comes back to the front and when the inbox is pulled down.
final inboxMessagesProvider = FutureProvider<List<InboxMessage>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const [];
  // Row-level permissions decide what a player gets: messages to them (`user:<id>`), to a label
  // they carry (`label:early`) and to everyone (`users`).
  final rows = await listAllRows(ref.read(tablesProvider), AppwriteConfig.messages, [
    Query.lessThanEqual('sentAt', DateTime.now().toUtc().toIso8601String()),
    Query.orderDesc('sentAt'),
  ]);
  // Newest first; messages sent in the same instant keep the order they were written in.
  final list = [for (final models.Row r in rows) InboxMessage.fromRow(r.$id, r.data)];
  return list..sort((a, b) => b.sentAt.compareTo(a.sentAt));
});

/// The inbox: messages not deleted and not past their expiry, with what the player did with each.
/// A message leaves on the dot of its expiry (a friend's gift after 24 hours), also while the inbox
/// or the message is on screen.
final inboxProvider = Provider<List<InboxItem>>((ref) {
  final messages = ref.watch(inboxMessagesProvider).value ?? const <InboxMessage>[];
  final state = ref.watch(profileProvider.select((p) => p.value?.inbox ?? const <String>[])).toSet();
  final now = DateTime.now();
  final next = nextExpiry(messages, now);
  if (next != null) {
    final timer = Timer(next.difference(now) + const Duration(milliseconds: 500), ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return [
    for (final m in messages)
      if (!state.contains('deleted:${m.id}') && !m.expiredAt(now)) InboxItem(m, seen: state.contains('seen:${m.id}'), claimed: state.contains('claimed:${m.id}')),
  ];
});

/// The soonest expiry after [now] among [messages] (when the inbox must look again).
DateTime? nextExpiry(Iterable<InboxMessage> messages, DateTime now) {
  DateTime? next;
  for (final m in messages) {
    final at = m.expiresAt;
    if (at != null && at.isAfter(now) && (next == null || at.isBefore(next))) next = at;
  }
  return next;
}

/// A message not opened yet: the Social tab shows a dot.
final inboxUnseenProvider = Provider<bool>((ref) => ref.watch(inboxProvider).any((i) => !i.seen));
