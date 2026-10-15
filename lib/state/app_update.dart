import 'dart:async';
import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/appwrite.dart';
import '../core/qa.dart';
import '../core/web_page.dart';

/// When the app looks for a newer build and when it asks the player to update
/// (owner, 2026-10-14): every 5 minutes while the app is in front, every hour
/// while the tab is hidden or the app is in the background, and on every
/// return to the app once the last look is 5 minutes old. The prompt can be
/// closed; it comes back an hour later and after every reload or launch,
/// until the player runs the newest build.
class UpdatePolicy {
  UpdatePolicy._();

  static const checkEvery = Duration(minutes: 5);
  static const checkEveryInBackground = Duration(hours: 1);
  static const askAgainAfter = Duration(hours: 1);

  /// The first look waits until launch has settled (catalogue, sync, gifts).
  static const firstCheckAfter = Duration(seconds: 8);

  static bool checkDue({DateTime? lastCheck, required DateTime now, required bool foreground}) =>
      lastCheck == null || now.difference(lastCheck) >= (foreground ? checkEvery : checkEveryInBackground);

  /// [lastAsked] lives in memory only, so a reload or a fresh launch asks again.
  static bool askDue({DateTime? lastAsked, required DateTime now}) => lastAsked == null || now.difference(lastAsked) >= askAgainAfter;
}

/// A newer build than the one running.
@immutable
class AvailableUpdate {
  const AvailableUpdate({required this.latest, required this.message});

  /// The newest build's id (web deploy id, or iOS build number).
  final String latest;

  /// The alert's text: what is new and where the update comes from (its button says Update).
  final String message;

  @override
  bool operator ==(Object other) => other is AvailableUpdate && other.latest == latest && other.message == message;

  @override
  int get hashCode => Object.hash(latest, message);
}

/// Where this install learns about newer builds and how it gets one.
abstract interface class UpdateSource {
  /// The newer build, or null when this one is the newest (or the newest is unknown: offline).
  Future<AvailableUpdate?> check();

  /// Gets the newest build: reloads the web page, or opens TestFlight or the App Store.
  Future<void> update();
}

/// Web: `tools/dev/deploy-web.sh` builds with `--dart-define=CJW_WEB_BUILD=<deploy id>` and writes
/// the same id to `app-version.json` next to `index.html`. Any other id on the site means a newer
/// deployment; a reload runs it.
class WebUpdateSource implements UpdateSource {
  WebUpdateSource({required this.current, Future<String?> Function(String url)? fetch, void Function()? reload})
      : _fetch = fetch ?? fetchFresh,
        _reload = reload ?? reloadPage;

  /// `--dart-define=CJW_WEB_BUILD`, empty in `flutter run` (no checks then).
  static const buildId = String.fromEnvironment('CJW_WEB_BUILD');

  final String current;
  final Future<String?> Function(String url) _fetch;
  final void Function() _reload;

  /// Where the deployed build id is published, read past every cache.
  static String versionUrl(Uri base, DateTime now) => base.replace(path: '/app-version.json', query: 't=${now.millisecondsSinceEpoch}', fragment: '').toString();

  @override
  Future<AvailableUpdate?> check() async {
    final body = await _fetch(versionUrl(Uri.base, DateTime.now()));
    if (body == null) return null;
    final latest = '${(jsonDecode(body) as Map<String, dynamic>)['build'] ?? ''}';
    if (latest.isEmpty || latest == current) return null;
    return AvailableUpdate(latest: latest, message: 'A new version of Card Jigsaw World is out. Updating reloads the page and keeps your progress.');
  }

  @override
  Future<void> update() async => _reload();
}

/// The two ways the iPhone app is installed, and where each one's newest build is announced:
/// a row of the public `releases` table (`tools/dev/publish_release.py` writes it once Apple has the
/// build out to testers, or once a version is live on the App Store).
enum IosChannel {
  testflight('ios-testflight', 'itms-beta://beta.itunes.apple.com/v1/app/6821644423', 'https://beta.itunes.apple.com/v1/app/6821644423', 'TestFlight'),
  appStore('ios-appstore', 'itms-apps://apps.apple.com/app/id6821644423', 'https://apps.apple.com/app/id6821644423', 'the App Store');

  const IosChannel(this.row, this.appUrl, this.webUrl, this.storeName);

  /// Row id in the `releases` table.
  final String row;

  /// Opens the app's page in TestFlight or the App Store.
  final String appUrl;

  /// The same page through the browser when the app link does not open.
  final String webUrl;
  final String storeName;

  /// From `PackageInfo.installerStore`: `com.apple.testflight` for TestFlight (a sandbox
  /// receipt), the simulator and debug installs follow TestFlight too.
  static IosChannel of(String? installerStore) => installerStore == 'com.apple' ? appStore : testflight;
}

class IosUpdateSource implements UpdateSource {
  IosUpdateSource(this._tables, {required this.channel, required this.currentBuild, Future<bool> Function(Uri url)? open})
      : _open = open ?? ((url) => launchUrl(url, mode: LaunchMode.externalApplication));

  final TablesDB _tables;
  final IosChannel channel;
  final int currentBuild;
  final Future<bool> Function(Uri url) _open;

  static const table = 'releases';

  @override
  Future<AvailableUpdate?> check() async {
    final Map<String, dynamic> row;
    try {
      row = (await _tables.getRow(databaseId: AppwriteConfig.databaseId, tableId: table, rowId: channel.row)).data;
    } on AppwriteException catch (e) {
      if (e.code == 404) return null;
      rethrow;
    }
    final build = (row['build'] as num?)?.toInt() ?? 0;
    if (build <= currentBuild) return null;
    final version = row['version'] as String?;
    final hasVersion = version != null && version.isNotEmpty;
    // Testers compare builds; App Store players know versions, not build numbers.
    final message = channel == IosChannel.appStore
        ? '${hasVersion ? 'Version $version' : 'A new version'} is ready in the App Store. Your progress is kept.'
        : '${hasVersion ? 'Version $version ($build)' : 'Build $build'} is ready in TestFlight. You have build $currentBuild.';
    return AvailableUpdate(latest: '$build', message: message);
  }

  @override
  Future<void> update() async {
    if (await _open(Uri.parse(channel.appUrl))) return;
    await _open(Uri.parse(channel.webUrl));
  }
}

/// Whether this run looks for updates at all: web deploys with a build id, and iPhone release
/// builds. Integration tests never do (the alert would cover their screens); a debug run does with
/// `--dart-define=CJW_UPDATE_CHECK=true` (QA of the prompt itself).
const bool _forceCheck = bool.fromEnvironment('CJW_UPDATE_CHECK');

/// The update source of this install, or null when it never checks.
final updateSourceProvider = FutureProvider<UpdateSource?>((ref) async {
  if (QaRun.integrationRun) return null;
  if (kIsWeb) return WebUpdateSource.buildId.isEmpty ? null : WebUpdateSource(current: WebUpdateSource.buildId);
  if (defaultTargetPlatform != TargetPlatform.iOS || !(kReleaseMode || _forceCheck)) return null;
  final info = await PackageInfo.fromPlatform();
  final build = int.tryParse(info.buildNumber);
  if (build == null) return null;
  return IosUpdateSource(ref.watch(tablesProvider), channel: IosChannel.of(info.installerStore), currentBuild: build);
});

/// The newer build, or null. Looks on launch, then on the [UpdatePolicy] schedule.
class AppUpdateController extends Notifier<AvailableUpdate?> {
  Timer? _tick;
  Timer? _first;
  AppLifecycleListener? _life;
  DateTime? _lastCheck;
  bool _foreground = true;
  bool _checking = false;

  @override
  AvailableUpdate? build() {
    ref.onDispose(() {
      _tick?.cancel();
      _first?.cancel();
      _life?.dispose();
    });
    final source = ref.watch(updateSourceProvider).value;
    if (source == null) return null;
    _first = Timer(UpdatePolicy.firstCheckAfter, check);
    // One tick a minute decides whether a look is due; browsers slow timers down in hidden tabs
    // but still run them at least once a minute.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => _maybeCheck());
    _life = AppLifecycleListener(onStateChange: (s) {
      // On the web, inactive is a visible tab without focus; hidden is a tab in the background.
      _foreground = s == AppLifecycleState.resumed || s == AppLifecycleState.inactive;
      if (s == AppLifecycleState.resumed) _maybeCheck();
    });
    return null;
  }

  void _maybeCheck() {
    if (UpdatePolicy.checkDue(lastCheck: _lastCheck, now: DateTime.now(), foreground: _foreground)) check();
  }

  /// Looks for a newer build now.
  Future<void> check() async {
    final source = ref.read(updateSourceProvider).value;
    if (source == null || _checking) return;
    _checking = true;
    _lastCheck = DateTime.now();
    try {
      final found = await source.check();
      if (ref.mounted) state = found;
    } catch (e) {
      // Offline or the site is mid-deploy: the next look tries again.
      debugPrint('update check failed: $e');
    } finally {
      _checking = false;
    }
  }

  /// Gets the newest build (see [UpdateSource.update]).
  Future<void> update() async => (await ref.read(updateSourceProvider.future))?.update();
}

final appUpdateProvider = NotifierProvider<AppUpdateController, AvailableUpdate?>(AppUpdateController.new);
