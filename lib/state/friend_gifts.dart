import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as enums;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/appwrite.dart';
import '../data/repositories.dart';
import 'auth.dart';

/// What a friend gift is (owner, 2026-10-17; docs/friend-gifts.md): one ticket or 150 coins,
/// chosen by the sender and free for them, at most one a day for each friend. The friend gets it
/// in Social > Inbox (and as a notification on iPhone) and has 24 hours to claim it.
enum GiftKind {
  tickets(1, 'ticket', 'tickets'),
  coins(150, 'coin', 'coins');

  const GiftKind(this.amount, this.one, this.many);

  /// The amounts the server grants (KINDS in functions/api/src/gift/gift.js).
  final int amount;
  final String one, many;

  /// "1 ticket", "150 coins".
  String get label => '$amount ${amount == 1 ? one : many}';
}

/// The one-a-day rule, as the server keeps it (`/gift/send`).
class FriendGifts {
  FriendGifts._();

  /// The sender's calendar day of [local] ('2026-10-17'): the limit turns at the sender's midnight.
  static String dayOf(DateTime local) =>
      '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';

  /// Row id of the gift [senderId] sent [recipientId] on [day] (`giftRowId` in the function), so
  /// the app can look up today's gift without a list.
  static String rowId(String senderId, String recipientId, String day) => deterministicId(senderId, '$recipientId:$day');

  /// The device's offset from UTC in minutes, sent with a gift so the server counts the same day.
  static int utcOffsetMinutes(DateTime local) => local.timeZoneOffset.inMinutes;
}

/// What sending a gift did.
class GiftResult {
  const GiftResult({required this.ok, this.error, this.friendName});
  final bool ok;

  /// `already` (today's gift to this friend is sent), `not-friend`, `unavailable` (a block either
  /// way, or the friend's account is gone), `signin`, `network` or `server`.
  final String? error;
  final String? friendName;

  /// The toast after a send.
  String message(String name) => ok
      ? 'Gift sent to $name'
      : switch (error) {
          'already' => 'You already sent $name a gift today',
          'not-friend' => 'Add $name as a friend to send a gift',
          'unavailable' => 'This gift could not be sent',
          'network' => 'Could not reach the server. Check your connection and try again.',
          _ => 'Something went wrong on our side. Try again in a moment.',
        };
}

/// Sends gifts through `/gift/send` on the `api` function (functions/api/src/gift) and reads whether
/// today's gift to a friend is sent (the sender may read their own `gifts` rows).
class FriendGiftRepository {
  FriendGiftRepository(this._functions, this._tables);
  final Functions _functions;
  final TablesDB _tables;

  static const functionId = AppwriteConfig.apiFunction;
  static const path = '/gift/send';
  static const table = 'gifts';

  Future<GiftResult> send(String friendId, GiftKind kind, {DateTime? now}) async {
    final local = now ?? DateTime.now();
    try {
      final exec = await _functions.createExecution(
        functionId: functionId,
        body: jsonEncode({'friendId': friendId, 'kind': kind.name, 'utcOffset': FriendGifts.utcOffsetMinutes(local)}),
        method: enums.ExecutionMethod.pOST,
        path: path,
      );
      final body = exec.responseBody.isEmpty ? <String, dynamic>{} : jsonDecode(exec.responseBody) as Map<String, dynamic>;
      return GiftResult(
        ok: body['ok'] == true,
        error: body['ok'] == true ? null : (body['error']?.toString() ?? 'server'),
        friendName: body['friendName']?.toString(),
      );
    } on AppwriteException catch (e) {
      return GiftResult(ok: false, error: e.code == 401 ? 'signin' : 'server');
    } catch (e) {
      debugPrint('send gift failed: $e');
      return const GiftResult(ok: false, error: 'network');
    }
  }

  /// Whether [senderId] already sent [recipientId] a gift on [day].
  Future<bool> sent(String senderId, String recipientId, String day) async {
    try {
      await _tables.getRow(databaseId: AppwriteConfig.databaseId, tableId: table, rowId: FriendGifts.rowId(senderId, recipientId, day));
      return true;
    } on AppwriteException catch (e) {
      if (e.code == 404) return false;
      rethrow;
    }
  }
}

final friendGiftRepositoryProvider = Provider((ref) => FriendGiftRepository(Functions(ref.watch(appwriteClientProvider)), ref.watch(tablesProvider)));

/// Whether the signed-in player sent this friend a gift on this day (the key carries the day, so
/// the answer turns at midnight). A failed read counts as not sent: the server still refuses a
/// second gift.
final giftSentProvider = FutureProvider.family<bool, ({String friendId, String day})>((ref, key) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return false;
  try {
    return await ref.watch(friendGiftRepositoryProvider).sent(me, key.friendId, key.day);
  } catch (e) {
    debugPrint('gift status failed: $e');
    return false;
  }
});
