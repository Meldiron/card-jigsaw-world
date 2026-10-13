import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Owner rule: web sign-in uses Appwrite's OAuth2 *token* flow (createOAuth2Token endpoint, then
/// account.createSession on /auth/callback), which keeps working when browsers block third-party
/// cookies. The session flow (createOAuth2Session, /account/sessions/oauth2/...) must never return.
void main() {
  final sources = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  test('no OAuth2 session flow anywhere in the app', () {
    for (final f in sources) {
      final text = f.readAsStringSync();
      expect(text.contains('createOAuth2Session'), isFalse, reason: '${f.path} uses createOAuth2Session');
      expect(text.contains('sessions/oauth2'), isFalse, reason: '${f.path} links the OAuth2 session endpoint');
    }
  });

  test('web redirect goes to the OAuth2 token endpoint and finishes with createSession', () {
    final repo = File('lib/data/repositories.dart').readAsStringSync();
    expect(repo.contains('/account/tokens/oauth2/'), isTrue);
    expect(repo.contains('createSession(userId: userId, secret: secret)'), isTrue);
  });
}
