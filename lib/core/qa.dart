import 'package:flutter/widgets.dart';

/// QA runs against the live backend: every simulator or browser run made while working on the game
/// (`tools/dev/qa-run.sh`, which builds with `--dart-define=CJW_QA=true`) flags the guest it plays
/// as a test player, so it never shows in the league and `tools/dev/purge_test_players.py` can
/// delete it afterwards. Never set in release builds.
///
/// Two marks, both written only for guests (an account with an email or Apple ID is never marked):
/// the profile row gets `isTest: true` (the league and its counts filter on it, server-side), and
/// the Appwrite user gets the prefs `{"qa": true, "qaRun": <CJW_QA_RUN>}` (a user whose profile
/// never got written can still be found and purged, one run at a time).
class QaRun {
  QaRun._();

  /// `--dart-define=CJW_QA=true`.
  static const bool enabled = bool.fromEnvironment('CJW_QA');

  /// `--dart-define=CJW_QA_RUN=<id>`: the wrapper's run id, so it purges exactly its own players.
  static const String id = String.fromEnvironment('CJW_QA_RUN');

  /// Whether a user with [prefs] still needs the QA prefs written.
  static bool needsPrefs(Map<String, dynamic> prefs) => prefs['qa'] != true || (id.isNotEmpty && prefs['qaRun'] != id);

  /// [prefs] with the QA marks added (other keys are kept).
  static Map<String, dynamic> markedPrefs(Map<String, dynamic> prefs) => {...prefs, 'qa': true, if (id.isNotEmpty) 'qaRun': id};

  /// True inside `flutter drive` integration tests (they run the real app on the live backend).
  static bool get integrationRun {
    try {
      return WidgetsBinding.instance.runtimeType.toString() == 'IntegrationTestWidgetsFlutterBinding';
    } catch (_) {
      return false;
    }
  }

  /// Refuses to start a player on the live backend from an integration test built without the
  /// flag: that player would land in the public league with a random name. Called before the
  /// guest session is read or created.
  static void requireForIntegrationRuns() {
    if (integrationRun && !enabled) {
      throw StateError('Integration tests play on the live backend: run them through tools/dev/qa-run.sh '
          '(or pass --dart-define=CJW_QA=true) so the test player stays out of the league and is purged.');
    }
  }
}
