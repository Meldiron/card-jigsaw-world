import 'package:carden/core/app_links.dart';
import 'package:carden/core/dates.dart';
import 'package:carden/data/sync/changes.dart';
import 'package:carden/data/sync/ops.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/inbox.dart';
import 'package:carden/state/profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Social > Inbox (lib/state/inbox.dart): messages are read-only rows; what the player did with
/// each lives in `profiles.inbox` through `SyncOp.inbox`.
void main() {
  Map<String, dynamic> apply(Map<String, dynamic> row, SyncOp op) => applyChanges(row, op.build(row).changes);

  group('SyncOp.inbox', () {
    test('a claim pays the gift once and records it', () {
      final op = SyncOp.inbox('m1', 'claimed', coins: 500, tickets: 2, hints: 3, peeks: 4, magics: 1);
      final row = {'coins': 100, 'tickets': 1, 'hints': 0, 'peeks': 0, 'magics': 0, 'inbox': <String>[]};
      final plan = op.build(row);
      final after = applyChanges(row, plan.changes);
      expect((after['coins'], after['tickets'], after['hints'], after['peeks'], after['magics']), (600, 3, 3, 4, 1));
      expect(after['inbox'], ['claimed:m1']);
      expect(plan.ledger.map((l) => '${l.amount} ${l.currency} ${l.reason}'), ['500 coins inbox:m1', '2 tickets inbox:m1', '3 hints inbox:m1']);
      // The same claim again (another device, a retry): skipped, nothing paid twice.
      final again = op.build(after);
      expect(again.skipped, SkipReason.messageClaimed);
      expect(again.changes, isEmpty);
    });

    test('seen and deleted are recorded once, and silently when already there', () {
      final seen = apply({'inbox': <String>[]}, SyncOp.inbox('m1', 'seen'));
      expect(seen['inbox'], ['seen:m1']);
      final twice = SyncOp.inbox('m1', 'seen').build(seen);
      expect(twice.skipped, isNull, reason: 'no "already done" notice for opening a message twice');
      expect(twice.changes, isEmpty);
      expect(apply(seen, SyncOp.inbox('m1', 'deleted'))['inbox'], ['seen:m1', 'deleted:m1']);
    });

    test('the op survives a round trip through the queue', () {
      final op = SyncOp.inbox('m9', 'claimed', coins: 50);
      final back = SyncOp.fromJson(op.toJson());
      expect((back.kind, back.args['id'], back.args['state'], back.args['coins']), (OpKind.inbox, 'm9', 'claimed', 50));
      expect(back.needsFresh, isTrue, reason: 'a claim is checked against the server row');
    });
  });

  group('inbox list', () {
    final now = DateTime.now();
    InboxMessage msg(String id, {Duration? expiresIn, int coins = 0}) => InboxMessage(
          id: id,
          subject: 'Subject $id',
          body: 'Body',
          sentAt: now.subtract(const Duration(hours: 1)),
          expiresAt: expiresIn == null ? null : now.add(expiresIn),
          coins: coins,
        );

    List<InboxItem> items(List<InboxMessage> messages, List<String> state) {
      final c = ProviderContainer(overrides: [
        inboxMessagesProvider.overrideWith((ref) async => messages),
        profileProvider.overrideWith(() => _Profile(state)),
      ]);
      addTearDown(c.dispose);
      return c.read(inboxProvider);
    }

    test('expired and deleted messages leave the inbox; seen and claimed are read from the profile', () async {
      final c = ProviderContainer(overrides: [
        inboxMessagesProvider.overrideWith((ref) async => [msg('a', coins: 10), msg('b', expiresIn: const Duration(hours: -1)), msg('c'), msg('d', expiresIn: const Duration(days: 2))]),
        profileProvider.overrideWith(() => _Profile(['deleted:c', 'seen:a', 'claimed:a'])),
      ]);
      addTearDown(c.dispose);
      await c.read(inboxMessagesProvider.future);
      await c.read(profileProvider.future);
      final list = c.read(inboxProvider);
      expect(list.map((i) => i.message.id), ['a', 'd']);
      expect((list[0].seen, list[0].claimed, list[0].claimable), (true, true, false));
      expect((list[1].seen, list[1].claimable), (false, false));
      expect(c.read(inboxUnseenProvider), isTrue, reason: '"d" is not opened yet: the Social tab shows a dot');
    });

    test('no messages, no dot', () {
      expect(items(const [], const []), isEmpty);
    });
  });

  test('a message reads its row, gift and button', () {
    final m = InboxMessage.fromRow('r1', {
      'subject': 'Welcome',
      'body': 'Hello',
      'sentAt': '2026-10-16T19:00:00.000+00:00',
      'expiresAt': '2026-10-23T19:00:00.000+00:00',
      'rewardCoins': 500,
      'rewardTickets': 2,
      'ctaLabel': 'Open the pack',
      'ctaLink': '/library/pack/pack-owls',
    });
    expect(m.hasReward, isTrue);
    expect(m.reward.length, 2);
    expect(m.expiresAt, isNotNull);
    expect(AppLink.parse(Uri.parse(m.ctaLink!))?.location.toString(), '/library/pack/pack-owls');
    expect(AppLink.parse(Uri.parse('/feedback'))?.kind, LinkKind.action);
  });

  test('message dates read Today, Yesterday or the day', () {
    final now = DateTime(2026, 10, 16, 21, 30);
    expect(formatMessageDate(DateTime(2026, 10, 16, 9, 5), '09:05', now: now), 'Today, 09:05');
    expect(formatMessageDate(DateTime(2026, 10, 15, 23, 0), '23:00', now: now), 'Yesterday, 23:00');
    expect(formatMessageDate(DateTime(2026, 10, 2, 8, 0), '08:00', now: now), '2 Oct, 08:00');
    expect(formatMessageDate(DateTime(2025, 12, 24, 8, 0), '08:00', now: now), '24 Dec 2025, 08:00');
  });
}

class _Profile extends ProfileNotifier {
  _Profile(this.inbox);
  final List<String> inbox;

  @override
  Future<Profile> build() async => Profile.guest('u1').copyWith(inbox: inbox);
}
