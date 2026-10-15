import 'dart:io' show Directory;

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:carden/state/app_update.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Tables extends TablesDB {
  _Tables(this.row) : super(Client());
  final Map<String, dynamic>? row;
  final asked = <String>[];

  @override
  Future<models.Row> getRow({required String databaseId, required String tableId, required String rowId, List<String>? queries, String? transactionId}) async {
    asked.add('$tableId/$rowId');
    if (row == null) throw AppwriteException('Row not found', 404);
    return models.Row.fromMap({'\$id': rowId, ...row!});
  }
}

class _Source implements UpdateSource {
  _Source(this.next);
  AvailableUpdate? next;
  int checks = 0;
  int updates = 0;

  @override
  Future<AvailableUpdate?> check() async {
    checks++;
    return next;
  }

  @override
  Future<void> update() async => updates++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    // The Appwrite IO client asks path_provider for its cookie jar folder.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.createTempSync('cjw-test').path,
    );
  }

  final now = DateTime(2026, 10, 14, 12);

  group('UpdatePolicy', () {
    test('looks every 5 minutes in front and every hour in the background', () {
      expect(UpdatePolicy.checkDue(now: now, foreground: true), isTrue, reason: 'first look');
      expect(UpdatePolicy.checkDue(lastCheck: now.subtract(const Duration(minutes: 4)), now: now, foreground: true), isFalse);
      expect(UpdatePolicy.checkDue(lastCheck: now.subtract(const Duration(minutes: 5)), now: now, foreground: true), isTrue);
      expect(UpdatePolicy.checkDue(lastCheck: now.subtract(const Duration(minutes: 30)), now: now, foreground: false), isFalse);
      expect(UpdatePolicy.checkDue(lastCheck: now.subtract(const Duration(hours: 1)), now: now, foreground: false), isTrue);
    });

    test('asks on every launch, then again an hour after "Later"', () {
      expect(UpdatePolicy.askDue(now: now), isTrue);
      expect(UpdatePolicy.askDue(lastAsked: now.subtract(const Duration(minutes: 59)), now: now), isFalse);
      expect(UpdatePolicy.askDue(lastAsked: now.subtract(const Duration(hours: 1)), now: now), isTrue);
    });
  });

  group('web', () {
    test('a different build id on the site is an update; the same one is not', () async {
      final fetched = <String>[];
      var reloads = 0;
      var body = '{"build":"20261014-abc","version":"1.7.0"}';
      final source = WebUpdateSource(
        current: '20261014-abc',
        fetch: (url) async {
          fetched.add(url);
          return body;
        },
        reload: () => reloads++,
      );
      expect(await source.check(), isNull);
      body = '{"build":"20261015-def","version":"1.7.0"}';
      final u = await source.check();
      expect(u?.latest, '20261015-def');
      expect(u?.message, isNot(contains(r'$')));
      await source.update();
      expect(reloads, 1);
      expect(fetched.every((u) => Uri.parse(u).path == '/app-version.json'), isTrue);
    });

    test('a missing file or an empty id is no update', () async {
      expect(await WebUpdateSource(current: 'a', fetch: (_) async => null, reload: () {}).check(), isNull);
      expect(await WebUpdateSource(current: 'a', fetch: (_) async => '{}', reload: () {}).check(), isNull);
    });

    test('the version file is read from the site root past every cache', () {
      final url = Uri.parse(WebUpdateSource.versionUrl(Uri.parse('https://carden.appwrite.network/library/pack/x?y=1#z'), now));
      expect(url.path, '/app-version.json');
      expect(url.queryParameters['t'], '${now.millisecondsSinceEpoch}');
      expect(url.fragment, isEmpty);
    });
  });

  group('iPhone', () {
    test('TestFlight, simulator and Xcode installs follow TestFlight; App Store installs the App Store', () {
      expect(IosChannel.of('com.apple.testflight'), IosChannel.testflight);
      expect(IosChannel.of('com.apple.simulator'), IosChannel.testflight);
      expect(IosChannel.of(null), IosChannel.testflight);
      expect(IosChannel.of('com.apple'), IosChannel.appStore);
    });

    test('a higher build in the channel row is an update', () async {
      final tables = _Tables({'version': '1.7.0', 'build': 121});
      expect(await IosUpdateSource(tables, channel: IosChannel.testflight, currentBuild: 121).check(), isNull);
      final u = await IosUpdateSource(tables, channel: IosChannel.testflight, currentBuild: 118).check();
      expect(u?.latest, '121');
      expect(u?.message, 'Version 1.7.0 (121) is ready in TestFlight. You have build 118.');
      expect(tables.asked, everyElement('releases/ios-testflight'));
    });

    test('no row yet is no update', () async {
      expect(await IosUpdateSource(_Tables(null), channel: IosChannel.appStore, currentBuild: 1).check(), isNull);
    });

    test('Update opens TestFlight, or its web page when the app link does not open', () async {
      final opened = <String>[];
      final source = IosUpdateSource(_Tables(null), channel: IosChannel.testflight, currentBuild: 1, open: (url) async {
        opened.add('$url');
        return url.scheme == 'https';
      });
      await source.update();
      expect(opened, [IosChannel.testflight.appUrl, IosChannel.testflight.webUrl]);
    });
  });

  test('the controller looks for an update and gets it through its source', () async {
    final source = _Source(null);
    final container = ProviderContainer(overrides: [updateSourceProvider.overrideWith((ref) async => source)]);
    addTearDown(container.dispose);
    container.listen(appUpdateProvider, (_, _) {});
    await container.read(updateSourceProvider.future);
    await container.read(appUpdateProvider.notifier).check();
    expect(container.read(appUpdateProvider), isNull);
    source.next = const AvailableUpdate(latest: '2', message: 'm');
    await container.read(appUpdateProvider.notifier).check();
    expect(container.read(appUpdateProvider)?.latest, '2');
    await container.read(appUpdateProvider.notifier).update();
    expect(source.updates, 1);
    expect(source.checks, 2);
  });
}
