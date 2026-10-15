import 'dart:io' show Directory;

import 'package:appwrite/appwrite.dart';
import 'package:card_jigsaw_world/core/links.dart';
import 'package:card_jigsaw_world/core/theme/app_theme.dart';
import 'package:card_jigsaw_world/data/repositories.dart';
import 'package:card_jigsaw_world/features/profile/help.dart';
import 'package:card_jigsaw_world/features/profile/settings_screen.dart';
import 'package:card_jigsaw_world/state/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The feedback table in memory; [fail] makes the next send fail as with no connection.
class _FakeFeedback extends FeedbackRepository {
  _FakeFeedback() : super(TablesDB(Client()));
  final sent = <Map<String, String?>>[];
  bool fail = false;

  @override
  Future<void> send({required String userId, required String message, String? appVersion, String? platform}) async {
    if (fail) throw AppwriteException('Failed host lookup');
    sent.add({'userId': userId, 'message': message, 'appVersion': appVersion, 'platform': platform});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => Directory.systemTemp.createTempSync('cjw-test').path,
  );

  test('the support email has a subject, and the version and player id under the message', () {
    final mail = AppLinks.supportMail(version: '1.7.0 (118)', platform: 'iPhone', playerId: 'abc123');
    expect(mail.scheme, 'mailto');
    expect(mail.path, AppLinks.supportEmail);
    expect(mail.queryParameters['subject'], 'Card Jigsaw World support');
    expect(mail.queryParameters['body'], '\n\n\n---\nVersion 1.7.0 (118) · iPhone\nPlayer id: abc123');
    expect(mail.toString(), isNot(contains('+')), reason: 'mail apps show a "+" for a space encoded the form way');
    expect(AppLinks.supportMail().queryParameters.containsKey('body'), isFalse);
  });

  testWidgets('feedback: sent only with text, closes with a thank you, and stays open when it fails', (tester) async {
    final repo = _FakeFeedback();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        feedbackRepositoryProvider.overrideWithValue(repo),
        currentUserIdProvider.overrideWithValue('player-1'),
        appVersionProvider.overrideWith((ref) async => '1.7.0 (118)'),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: Builder(builder: (context) => Center(child: TextButton(onPressed: () => showFeedbackSheet(context), child: const Text('open'))))),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Send feedback'), findsWidgets);

    // Nothing written yet: the button waits.
    await tester.tap(find.byKey(const ValueKey('feedback-send')));
    await tester.pumpAndSettle();
    expect(repo.sent, isEmpty);

    // No connection: the message stays for another try.
    repo.fail = true;
    await tester.enterText(find.byKey(const ValueKey('feedback-field')), '  More Giant packs, please.  ');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('feedback-send')));
    await tester.pumpAndSettle();
    expect(find.text('Could not send. Check your connection and try again.'), findsOneWidget);
    expect(find.text('  More Giant packs, please.  '), findsOneWidget);

    repo.fail = false;
    await tester.tap(find.byKey(const ValueKey('feedback-send')));
    await tester.pumpAndSettle();
    expect(repo.sent, [
      {'userId': 'player-1', 'message': 'More Giant packs, please.', 'appVersion': '1.7.0 (118)', 'platform': platformName},
    ]);
    expect(find.byKey(const ValueKey('feedback-field')), findsNothing, reason: 'the sheet closed');
    expect(find.text('Thank you. Your feedback was sent.'), findsOneWidget);
  });
}
