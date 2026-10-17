import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'qa.dart';

/// Usage analytics through Appwrite Analytics (owner, 2026-10-17; docs/analytics.md): screen views,
/// the app going to the background and back, and the game's own events (`puzzle_completed`,
/// `tool_used`, ...), sent only to our Appwrite project (property "Carden"), on the app's one
/// Appwrite client.
///
/// Nothing is sent from debug and profile builds, from QA runs (`CJW_QA`), or while the player has
/// Settings > Privacy > Share usage data off; `--dart-define=CJW_ANALYTICS=true` sends from any
/// build, for a deliberate check that events arrive. Props are small and never personal: no names,
/// emails, free text, or player or friend ids.
///
/// Call sites stay one line: `AppAnalytics.event('pack_opened', {'pack': pack.id})`. Every event
/// carries the screen it happened on as its page (`app://ios/game`, `https://play.carden.page/game`).
class AppAnalytics {
  AppAnalytics._();

  /// The Appwrite Analytics property "Carden" (domain carden.page).
  static const trackingId = '6ad3426500307dfae727';

  /// `--dart-define=CJW_ANALYTICS=true`: sends from a debug build or a QA run too (verification).
  static const bool forced = bool.fromEnvironment('CJW_ANALYTICS');

  /// Whether a build sends: a release build outside a QA run, or one built with [forced].
  static bool buildSends({required bool release, required bool qa, required bool forced}) => forced || (release && !qa);

  static bool get _thisBuildSends => buildSends(release: kReleaseMode, qa: QaRun.enabled, forced: forced);

  static bool _buildSends = _thisBuildSends;

  static _AppTracking? _tracking;
  static bool _shareUsage = true;

  /// The screen on show and the one before it (screen names, see [screenNameFor]).
  static String? _screen;
  static String? _previous;

  /// The tab on show in the tab shell (0 Home, 1 Library, 2 Quests, 3 Social, 4 Profile).
  static int _tab = 0;
  static final _tabs = <int, ScreenObserver>{};

  /// Events go out now: the build may send, the player shares usage data and the client is attached.
  static bool get sending => _tracking != null && _buildSends && _shareUsage;

  /// The screen on show, for events that say where they happened.
  static String? get screen => _screen;

  /// The screen before [screen] (what the store was opened from).
  static String? get previousScreen => _previous;

  /// Attaches analytics to the app's Appwrite client, once, as the app starts (before the router
  /// is made, so its navigators get their observers).
  static void attach(Client client) {
    if (_tracking == null) _use(_AppTracking(Analytics(client), trackingId));
  }

  /// Settings > Privacy > Share usage data (on by default). Off stops every event at once,
  /// lifecycle events included.
  static set shareUsage(bool on) {
    _shareUsage = on;
    _applyLifecycle();
  }

  static bool get shareUsage => _shareUsage;

  static void _use(_AppTracking tracking) {
    _tracking?.disableAutoLifecycleEvents();
    _tracking = tracking;
    _applyLifecycle();
  }

  /// `app_backgrounded` / `app_foregrounded` (with the engagement time) only while sending.
  static void _applyLifecycle() {
    final t = _tracking;
    if (t == null) return;
    if (sending) {
      t.start();
    } else {
      t.disableAutoLifecycleEvents();
    }
  }

  /// A custom event: [name] in snake_case, [props] small values (null ones are left out).
  static void event(String name, [Map<String, Object?> props = const {}]) {
    assert(RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name), 'event names are snake_case: $name');
    assert(props.length <= 16, 'Appwrite takes at most 16 props per event: $name');
    final t = _tracking;
    if (t == null || !sending) return;
    t.event(name, url: _screen, props: {for (final e in props.entries) if (e.value != null) e.key: e.value});
  }

  /// Navigator observers for the router: one per navigator (the root's, and each tab's with its
  /// [tab] index). None until [attach] (unit tests that build the router send nothing).
  static List<NavigatorObserver> observers({int? tab}) {
    final t = _tracking;
    if (t == null) return const [];
    final o = ScreenObserver(t, tab: tab);
    if (tab != null) _tabs[tab] = o;
    return [o];
  }

  /// The tab shell shows tab [index] (called as it builds). A tab seen before reports its screen
  /// after the frame: its navigator does not change when it comes back into view.
  static void showTab(int index) {
    if (index == _tab) return;
    _tab = index;
    _tabShownLater('tab', previous: _screen);
  }

  /// The screen on top of the tab on show (null before its navigator has a page).
  static String? _tabScreen() => _tabs[_tab]?._top;

  static void _tabShownLater(String trigger, {String? previous}) {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        final name = _tabScreen();
        // A tab opened for the first time reported its page as its navigator was built.
        if (name != null && name != _screen) _screenView(name, trigger: trigger, previous: previous);
      })
      ..ensureVisualUpdate();
  }

  /// A `screen_view` in the shape [TrackingObserver] sends ({screen, trigger, previous}).
  static void _screenView(String name, {required String trigger, String? previous}) {
    if (name != _screen) _previous = _screen;
    _screen = name;
    final t = _tracking;
    if (t == null || !sending) return;
    t.event('screen_view', url: name, props: {'screen': name, 'trigger': trigger, 'previous': ?previous});
  }

  /// Unit tests: a fresh start that sends through [service], as a release build would ([build]
  /// true; null keeps the rule of the build running the tests, a debug build).
  @visibleForTesting
  static void debugAttach(Analytics service, {bool? build = true, bool shareUsage = true}) {
    debugReset();
    _buildSends = build ?? _thisBuildSends;
    _shareUsage = shareUsage;
    _use(_AppTracking(service, trackingId));
  }

  @visibleForTesting
  static void debugReset() {
    _tracking?.disableAutoLifecycleEvents();
    _tracking = null;
    _buildSends = _thisBuildSends;
    _shareUsage = true;
    _screen = _previous = null;
    _tab = 0;
    _tabs.clear();
  }
}

/// The SDK's [Tracking] with the gate in front: nothing leaves unless [AppAnalytics.sending].
class _AppTracking extends Tracking {
  _AppTracking(super.analytics, super.propertyId);

  @override
  void event(String name, {String? url, Map<String, dynamic>? props, int? engagementTime}) {
    if (AppAnalytics.sending) super.event(name, url: url, props: props, engagementTime: engagementTime);
  }
}

/// Readable screen names for the router's paths, never ids: `/library/pack/:packId` is `pack`.
/// A path not listed (a new route) is named after its last fixed segment (`/join/:code` is `join`).
const screenNames = {
  '/welcome': 'welcome',
  '/home': 'home',
  '/library': 'library',
  '/library/pack/:packId': 'pack',
  '/events': 'quests',
  '/social': 'social',
  '/profile': 'profile',
  '/profile/settings': 'settings',
  '/profile/my-puzzles': 'my_puzzles',
  '/play/:puzzleId': 'play_setup',
  '/game/:puzzleId/:grid': 'game',
  '/store': 'store',
  '/wheel': 'wheel',
  '/account': 'account',
  '/auth/callback': 'sign_in_return',
  '/player/:userId': 'player',
};

/// The screen name for a route's path pattern (`GoRouterState.fullPath`).
String screenNameFor(String? fullPath) {
  final known = screenNames[fullPath];
  if (known != null) return known;
  final fixed = (fullPath ?? '').split('/').where((s) => s.isNotEmpty && !s.startsWith(':'));
  return fixed.isEmpty ? 'home' : fixed.last.replaceAll('-', '_');
}

/// Screen views from one navigator (lib/router.dart gives the root navigator and each tab's
/// navigator one). Pages report the name the router gives them ([screenNameFor]); sheets, alerts
/// and menus are not screens, so opening or closing one reports nothing. The root navigator's
/// tab shell page has no name: it stands for the tab on show, reported once the frame has settled
/// which tab that is.
///
/// A [TrackingObserver] that sends the same `screen_view` events ({screen, trigger, previous}), with
/// its own bookkeeping of the pages on its navigator, so the screen under a closed sheet is not
/// counted twice and a page pushed over the tabs knows which tab it came from.
class ScreenObserver extends TrackingObserver {
  ScreenObserver(super.tracking, {this.tab});

  /// The tab whose navigator this is; null for the root navigator.
  final int? tab;

  /// The navigator's pages, bottom to top, and the navigator they belong to (a tab's navigator is
  /// made again after the tab shell was gone, with this same observer).
  final _pages = <Route<dynamic>>[];
  NavigatorState? _of;

  /// The name of the page on top (null for the tab shell, or before the first page).
  String? get _top => _pages.isEmpty ? null : _nameOf(_pages.last);

  static bool _isPage(Route<dynamic>? route) => route?.settings is Page;
  static String? _nameOf(Route<dynamic> route) => route.settings.name;

  /// What [route] shows: its name, or the tab on show for the tab shell's page.
  String? _screenOf(Route<dynamic>? route) => route == null ? null : _nameOf(route) ?? AppAnalytics._tabScreen();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_isPage(route)) return;
    if (!identical(navigator, _of)) {
      _of = navigator;
      _pages.clear();
    }
    final below = _pages.isEmpty ? null : _pages.last;
    _pages.add(route);
    // The tab shell's page: its tab's navigator reports the page it opens on.
    final name = _nameOf(route);
    if (name != null) AppAnalytics._screenView(name, trigger: 'push', previous: _screenOf(below));
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _gone(route, 'pop');

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _gone(route, 'remove');

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute == null || !_isPage(newRoute)) return;
    final i = oldRoute == null ? -1 : _pages.indexOf(oldRoute);
    if (i < 0) return didPush(newRoute, oldRoute);
    _pages[i] = newRoute;
    if (i == _pages.length - 1) _shown(newRoute, oldRoute, 'replace');
  }

  /// [route] left the navigator: when it was on top, the page under it is on show again.
  void _gone(Route<dynamic> route, String trigger) {
    if (!_isPage(route)) return;
    final wasTop = _pages.isNotEmpty && identical(_pages.last, route);
    _pages.remove(route);
    if (wasTop && _pages.isNotEmpty) _shown(_pages.last, route, trigger);
  }

  void _shown(Route<dynamic> route, Route<dynamic>? previous, String trigger) {
    final name = _nameOf(route);
    final from = previous == null ? null : _nameOf(previous);
    if (name != null) {
      AppAnalytics._screenView(name, trigger: trigger, previous: from);
    } else {
      // Back on the tab shell: the tab on show, once this frame has settled which tab that is.
      AppAnalytics._tabShownLater(trigger, previous: from);
    }
  }
}
