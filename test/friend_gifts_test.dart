// Friend gifts (docs/friend-gifts.md): the app and the server (function `api`, and `send-gift` for
// builds up to 124) agree on the gifts, the day and the row id; the server's copy of the name filter
// keeps the app's lists; the push registration follows the player from session to session.
import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/friend_gifts.dart';
import 'package:carden/state/push.dart';
import 'package:carden/state/settings.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _giftPath = 'functions/api/src/gift/gift.js';
final _giftJs = File(_giftPath).readAsStringSync();

/// The frozen copy in the send-gift function, which builds up to 124 call (docs/functions.md).
final _oldGiftJs = File('functions/send-gift/src/gift.js').readAsStringSync();

/// The quoted words of the first `{ ... }` or `[ ... ]` block after [start] in [source].
Set<String> _words(String source, String start, String close) {
  final from = source.indexOf(start);
  expect(from, greaterThanOrEqualTo(0), reason: start);
  final block = source.substring(from + start.length, source.indexOf(close, from));
  return {for (final m in RegExp(r"'([^']*)'").allMatches(block.replaceAll(RegExp(r'//[^\n]*'), ''))) m[1]!};
}

void main() {
  group('the gifts', () {
    test('1 ticket or 150 coins, the amounts the function grants', () {
      expect(GiftKind.tickets.amount, 1);
      expect(GiftKind.coins.amount, 150);
      expect(GiftKind.tickets.label, '1 ticket');
      expect(GiftKind.coins.label, '150 coins');
      for (final k in GiftKind.values) {
        for (final (path, js) in [(_giftPath, _giftJs), ('functions/send-gift/src/gift.js', _oldGiftJs)]) {
          expect(RegExp('${k.name}: \\{ amount: ${k.amount},').hasMatch(js), isTrue, reason: '${k.name} in $path');
        }
      }
    });

    test("the sender's calendar day and the row id the function creates", () {
      expect(FriendGifts.dayOf(DateTime(2026, 10, 7, 23, 59)), '2026-10-07');
      expect(FriendGifts.dayOf(DateTime(2026, 1, 1, 0, 0)), '2026-01-01');
      final id = FriendGifts.rowId('a1', 'b2', '2026-10-17');
      expect(id, md5.convert(utf8.encode('a1:b2:2026-10-17')).toString(), reason: 'giftRowId in gift.js');
      expect(id, isNot(FriendGifts.rowId('b2', 'a1', '2026-10-17')));
    });

    test('what the sender reads after a send', () {
      expect(const GiftResult(ok: true).message('Anna'), 'Gift sent to Anna');
      expect(const GiftResult(ok: false, error: 'already').message('Anna'), 'You already sent Anna a gift today');
      expect(const GiftResult(ok: false, error: 'unavailable').message('Anna'), 'This gift could not be sent');
      expect(const GiftResult(ok: false, error: 'network').message('Anna'), startsWith('Could not reach the server'));
    });
  });

  test("the function's name filter keeps the app's word lists", () {
    final dart = File('lib/core/name_filter.dart').readAsStringSync();
    expect(_words(_giftJs, 'ROOTS = new Set([', ']);'), _words(dart, '_roots = {', '};'));
    expect(_words(_giftJs, 'WORDS = new Set([', ']);'), _words(dart, '_words = {', '};'));
    expect(_words(_giftJs, 'NUMBERS = [', '];'), _words(dart, '_numbers = [', '];'));
    for (final (start, close) in [('ROOTS = new Set([', ']);'), ('WORDS = new Set([', ']);'), ('NUMBERS = [', '];')]) {
      expect(_words(_oldGiftJs, start, close), _words(_giftJs, start, close), reason: 'send-gift keeps the same $start');
    }
  });

  test('a build signed for development pushes through the sandbox provider', () {
    expect(PushProviders.forEnvironment('development'), 'apns-sandbox');
    expect(PushProviders.forEnvironment('production'), 'apns');
    expect(PushProviders.forEnvironment(null), 'apns', reason: 'App Store and TestFlight builds carry no embedded profile');
  });

  group('push registration', () {
    late _Targets targets;
    late ProviderContainer c;

    Future<void> setUpContainer({Map<String, Object> prefs = const {}}) async {
      SharedPreferences.setMockInitialValues(prefs);
      final store = await LocalStore.open();
      targets = _Targets(() => c.read(currentUserIdProvider));
      c = ProviderContainer(overrides: [
        localStoreProvider.overrideWithValue(store),
        pushTargetsProvider.overrideWithValue(targets),
        currentUserIdProvider.overrideWith((ref) => ref.watch(_user)),
      ]);
      addTearDown(c.dispose);
      // Watched, as CardenApp watches it (a provider nobody listens to is paused).
      c.listen(pushRegistrationProvider, (_, _) {});
    }

    test('the token goes to the player, again after a sign-in to another account', () async {
      await setUpContainer();
      final push = c.read(pushRegistrationProvider);
      c.read(_user.notifier).set('guest1');
      await push.onToken('tok1', environment: 'development');
      expect(targets.calls, ['create guest1 tok1 apns-sandbox']);
      await push.onToken('tok1');
      expect(targets.calls, hasLength(1), reason: 'the same token for the same player is registered once');
      // Sign in to another account: a new session, which needs its own target.
      c.read(_user.notifier).set('anna');
      await pumpEventQueue();
      expect(targets.calls.last, 'create anna tok1 apns-sandbox');
      // iOS hands out a new token.
      await push.onToken('tok2');
      expect(targets.calls.last, 'create anna tok2 apns-sandbox');
    });

    test('a token already taken by an earlier session of the player is updated', () async {
      await setUpContainer(prefs: {'pushTarget': jsonEncode({'userId': 'anna', 'targetId': 't-old'})});
      targets.conflict = true;
      c.read(_user.notifier).set('anna');
      await c.read(pushRegistrationProvider).onToken('tok1', environment: 'production');
      expect(targets.calls, ['create anna tok1 apns', 'update t-old tok1']);
    });

    test('Gifts from friends off: the target goes and nothing is registered', () async {
      await setUpContainer();
      final push = c.read(pushRegistrationProvider);
      c.read(_user.notifier).set('anna');
      await push.onToken('tok1', environment: 'production');
      await push.disable();
      expect(targets.calls, ['create anna tok1 apns', 'delete target-1']);
      expect(c.read(giftNotificationsProvider), isFalse);
      await push.onToken('tok2');
      expect(targets.calls, hasLength(2), reason: 'off stays off until the player turns it on');
    });

    test('no player yet, no target', () async {
      await setUpContainer();
      await c.read(pushRegistrationProvider).onToken('tok1');
      expect(targets.calls, isEmpty);
    });
  });
}

class _User extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? id) => state = id;
}

final _user = NotifierProvider<_User, String?>(_User.new);

class _Targets implements PushTargets {
  _Targets(this._currentUser);
  final String? Function() _currentUser;
  final calls = <String>[];
  bool conflict = false;
  var _n = 0;

  @override
  Future<String> create(String token, String providerId) async {
    calls.add('create ${_currentUser() ?? '?'} $token $providerId');
    if (conflict) throw AppwriteException('A target with the same ID already exists.', 409, 'user_target_already_exists');
    return 'target-${++_n}';
  }

  @override
  Future<void> update(String targetId, String token) async => calls.add('update $targetId $token');

  @override
  Future<void> delete(String targetId) async => calls.add('delete $targetId');
}
