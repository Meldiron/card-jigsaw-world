// tools/dev/qa-run.sh purges the run's test players once, however the run ends: a normal end, a
// failing run, Ctrl-C, TERM, HUP (the terminal or the parent went away), a signal to the script
// alone (flutter is stopped too). Runs the real script in a scratch folder with a fake flutter and a
// fake purge tool, so nothing reaches the backend.
@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late File purges;

  setUp(() {
    root = Directory.systemTemp.createTempSync('qa_run_test');
    Directory('${root.path}/tools/dev').createSync(recursive: true);
    File('tools/dev/qa-run.sh').copySync('${root.path}/tools/dev/qa-run.sh');
    Directory('${root.path}/secrets').createSync();
    File('${root.path}/secrets/appwrite-users-key.txt').writeAsStringSync('fake');
    purges = File('${root.path}/purges.log');
    void script(String path, String body) {
      File(path)
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/bash\n$body\n');
      Process.runSync('chmod', ['+x', path]);
    }

    // The fake flutter runs for FAKE_SECONDS and ends with FAKE_CODE; TERM or HUP ends it at once.
    script('${root.path}/home/flutter/bin/flutter', r'''
sleep "${FAKE_SECONDS:-0}" >/dev/null 2>&1 &
s=$!
trap 'kill $s 2>/dev/null; exit 143' TERM HUP
wait $s
exit "${FAKE_CODE:-0}"''');
    // The fake purge tool (run as `.venv/bin/python tools/dev/purge_test_players.py ...`) writes a
    // line, notes its arguments (the purge) and takes a moment, as the real one does. Writing to a
    // closed pipe would end it before the purge.
    script('${root.path}/.venv/bin/python', 'echo "purging"; echo "\$*" >> "${purges.path}"; sleep 0.2; echo "1 test player(s) purged, 0 kept"');
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<Process> start({double seconds = 0, int code = 0, Map<String, String> env = const {}}) => Process.start(
        'bash',
        ['${root.path}/tools/dev/qa-run.sh', 'drive', '--target=integration_test/x_test.dart', '-d', 'sim'],
        environment: {'HOME': '${root.path}/home', 'FAKE_SECONDS': '$seconds', 'FAKE_CODE': '$code', ...env},
      );

  Future<(int, String)> finish(Process p) async {
    final out = StringBuffer();
    final done = [p.stdout.transform(utf8.decoder).forEach(out.write), p.stderr.transform(utf8.decoder).forEach(out.write)];
    final code = await p.exitCode.timeout(const Duration(seconds: 20));
    await Future.wait(done);
    return (code, out.toString());
  }

  List<String> purgeCalls() => purges.existsSync() ? purges.readAsLinesSync() : const [];

  test('a normal end purges the run once, and only its own players', () async {
    final (code, out) = await finish(await start());
    expect(code, 0);
    expect(purgeCalls(), hasLength(1));
    final run = RegExp(r'qa-run: (qa-\S+)').firstMatch(out)!.group(1)!;
    expect(purgeCalls().single, contains('purge --run $run --apply'));
    expect(out, contains('1 test player(s) purged'));
  });

  test('a failing run purges once and keeps its exit code', () async {
    final (code, _) = await finish(await start(code: 3));
    expect(code, 3);
    expect(purgeCalls(), hasLength(1));
  });

  for (final (signal, exit) in [(ProcessSignal.sighup, 129), (ProcessSignal.sigint, 130), (ProcessSignal.sigterm, 143)]) {
    test('$signal purges once, then the run ends with $exit', () async {
      final p = await start(seconds: 1.5);
      // Past the traps (bash starts in a few milliseconds), while the run is still going.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      p.kill(signal);
      final (code, _) = await finish(p);
      expect(code, exit);
      expect(purgeCalls(), hasLength(1), reason: 'the signal trap and the EXIT trap together purge once');
    });
  }

  test('stopped from outside (TERM to the script alone), a long run ends at once and is purged', () async {
    final p = await start(seconds: 30);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final t0 = DateTime.now();
    p.kill(ProcessSignal.sigterm);
    final (code, _) = await finish(p);
    expect(code, 143);
    expect(DateTime.now().difference(t0).inSeconds, lessThan(10), reason: 'flutter is stopped, not waited for');
    expect(purgeCalls(), hasLength(1));
  });

  test('QA_KEEP keeps the players', () async {
    final (code, out) = await finish(await start(env: {'QA_KEEP': '1'}));
    expect(code, 0);
    expect(purgeCalls(), isEmpty);
    expect(out, contains('kept the test players'));
  });

  test('the purge finishes when nobody reads the output any more', () async {
    final p = await start(seconds: 1);
    // The reader goes away (the parent was killed): the pipes close while the run goes on.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await p.stdout.listen(null).cancel();
    await p.stderr.listen(null).cancel();
    await p.exitCode.timeout(const Duration(seconds: 20));
    expect(purgeCalls(), hasLength(1));
  });
}
