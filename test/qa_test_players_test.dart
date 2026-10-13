// QA test players: QA runs flag their guest, the league leaves flagged players out on the server,
// and every documented way to start the app for QA goes through the flag.
import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:card_jigsaw_world/core/qa.dart';
import 'package:card_jigsaw_world/data/repositories.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// A client that is never asked for anything (the fakes answer first).
class _NoClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('no network in unit tests');
}

/// Records every listRows call and answers with an empty page.
class _Tables extends TablesDB {
  _Tables() : super(_NoClient());
  final calls = <List<dynamic>>[];

  @override
  Future<models.RowList> listRows({required String databaseId, required String tableId, List<String>? queries, String? transactionId, bool? total, int? ttl}) async {
    calls.add([for (final q in queries ?? const <String>[]) jsonDecode(q)]);
    return models.RowList(total: 0, rows: const []);
  }
}

const _notTest = {'method': 'equal', 'attribute': 'isTest', 'values': [false]};
const _solved = {'method': 'greaterThan', 'attribute': 'puzzlesCompleted', 'values': [0]};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('league', () {
    test('test players are left out on the server, for real players and guests alike', () {
      for (final viewer in [null, Profile.guest('real'), Profile.fromRow('real', {'userId': 'real', 'isTest': false})]) {
        final q = ProfileRepository.leagueQueries(viewer: viewer).map(jsonDecode).toList();
        expect(q, contains(equals(_notTest)));
        expect(q, contains(equals(_solved)));
        expect(q.where((x) => x['method'] == 'or'), isEmpty, reason: 'nothing else is let in');
      }
    });

    test('a QA viewer sees the real league plus its own row, never other test players', () {
      final me = Profile.fromRow('qa-1', {'userId': 'qa-1', 'isTest': true});
      final q = ProfileRepository.leagueQueries(viewer: me).map(jsonDecode).toList();
      expect(q, contains(equals(_solved)));
      expect(q, isNot(contains(equals(_notTest))));
      final or = q.singleWhere((x) => x['method'] == 'or');
      expect(or['values'], [
        _notTest,
        {'method': 'equal', 'attribute': '\$id', 'values': ['qa-1']},
      ]);
    });

    test('the league page and both rank counts use the same filter', () async {
      final tables = _Tables();
      final repo = ProfileRepository(tables);
      await repo.leaderboardPage(limit: 50);
      await repo.leaderboardRank(Profile.fromRow('me', {'userId': 'me', 'xp': 120, 'puzzlesCompleted': 2}));
      expect(tables.calls, hasLength(3));
      for (final call in tables.calls) {
        expect(call, containsAll([equals(_notTest), equals(_solved)]));
      }
      expect(tables.calls[0], contains(equals({'method': 'orderDesc', 'attribute': 'xp'})));
      expect(tables.calls[2], contains(equals({'method': 'greaterThan', 'attribute': 'xp', 'values': [120]})));
    });
  });

  group('profile', () {
    test('rows from before the columns existed read as a real player with no quests', () {
      final p = Profile.fromRow('old', {'userId': 'old', 'isTest': null, 'questsCompleted': null});
      expect(p.isTest, isFalse);
      expect(p.questsCompleted, 0);
      expect(p.picturesSolved, 0);
    });

    test('the flag and the public numbers survive a write and a copy', () {
      final p = Profile.fromRow('qa', {'userId': 'qa', 'isTest': true, 'questsCompleted': 7, 'picturesSolved': 40, 'picturesPerfect': 31, 'packsCompleted': 2, 'packsPerfect': 1});
      final again = Profile.fromRow('qa', p.toData());
      expect(again.isTest, isTrue);
      expect([again.questsCompleted, again.picturesSolved, again.picturesPerfect, again.packsCompleted, again.packsPerfect], [7, 40, 31, 2, 1]);
      final renamed = p.copyWith(displayName: 'Renamed');
      expect(renamed.isTest, isTrue);
      expect(renamed.questsCompleted, 7);
      expect(Profile.guest('x').copyWith(isTest: true).isTest, isTrue);
    });
  });

  group('QA prefs', () {
    test('marking keeps the other prefs and is written once', () {
      final marked = QaRun.markedPrefs({'theme': 'dark'});
      expect(marked['theme'], 'dark');
      expect(marked['qa'], isTrue);
      expect(QaRun.needsPrefs(const {}), isTrue);
      if (QaRun.id.isEmpty) expect(QaRun.needsPrefs(marked), isFalse);
    });

    test('unit tests never run as a QA run (release builds neither)', () {
      expect(QaRun.enabled, isFalse);
      expect(QaRun.integrationRun, isFalse);
      QaRun.requireForIntegrationRuns(); // does not throw outside integration tests
    });
  });

  group('every QA run goes through the flag', () {
    // Where commands that start the app are written down for people and agents to copy.
    final sources = <File>[
      File('CLAUDE.md'),
      File('README.md'),
      File('store/README.md'),
      ...Directory('docs').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.md')),
      ...Directory('.claude/skills').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.md')),
      ...Directory('tools/dev').listSync().whereType<File>().where((f) => f.path.endsWith('.sh')),
      ...Directory('tools/store').listSync().whereType<File>().where((f) => f.path.endsWith('.md') || f.path.endsWith('.sh')),
      ...Directory('integration_test').listSync().whereType<File>().where((f) => f.path.endsWith('.dart')),
    ];
    // Runs on the owner's iPhone are the owner's own play, not QA.
    const exempt = {'tools/dev/device.sh'};

    test('commands that start the app pass CJW_QA=true or use qa-run.sh', () {
      // A command, not prose: `flutter drive --...`, `flutter run -d ...`, `flutter test integration_test/...`.
      final start = RegExp(r'flutter\s+(drive|run)\s+-|flutter\s+test\s+integration_test');
      for (final f in sources.where((f) => f.existsSync() && !exempt.contains(f.path))) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (!start.hasMatch(lines[i])) continue;
          // The whole command, with its continuation lines.
          var cmd = lines[i];
          for (var j = i; j < lines.length - 1 && lines[j].trimRight().endsWith('\\'); j++) {
            cmd += ' ${lines[j + 1]}';
          }
          final viaWrapper = cmd.contains('qa-run.sh') || cmd.contains('CJW_QA=true') || cmd.contains(r'"$cmd"');
          expect(viaWrapper, isTrue, reason: '${f.path}:${i + 1} starts the app without the QA flag: ${lines[i].trim()}');
        }
      }
    });

    test('integration tests refuse to start without the flag', () {
      final auth = File('lib/state/auth.dart').readAsStringSync();
      expect(auth, contains('QaRun.requireForIntegrationRuns()'), reason: 'the guard runs before any guest is read or created');
      final repo = File('lib/data/repositories.dart').readAsStringSync();
      expect(repo, contains('return markQaGuest(await _account.get());'), reason: 'every new QA guest gets the prefs');
    });
  });
}
