/// Links into the game (docs/deep-links.md). One set of paths works everywhere:
///
/// - the web site: `https://card-jigsaw-world.appwrite.network/library/pack/pack-owls`
/// - the app's own scheme: `cardjigsaw://library/pack/pack-owls` (the widget, In-App Events)
/// - universal links: the web address opens the iPhone app where it is installed
///   (`web/.well-known/apple-app-site-association`, `applinks:` in `Runner.entitlements`).
///
/// [AppLink.parse] reads any of them into the route the app shows; `DeepLinks`
/// (`lib/state/deep_links.dart`) puts it on screen.
library;

/// How a link is shown.
enum LinkKind {
  /// A tab or a page inside one (Home, Library, a pack, Quests, Social, Profile and its pages):
  /// it replaces what is on screen.
  page,

  /// A page above the tabs (a picture, the store, the wheel, a player, sign-in): it opens on top
  /// of what is on screen, or on top of Home when the app has just started.
  overlay,

  /// An alert or sheet (pack code, friend code, daily gift, piggy bank) or a pick the device makes
  /// (today's picture, Quick play).
  action,
}

class AppLink {
  const AppLink._(this.location, this.kind);

  /// Path and query as the app's router knows them, e.g. `/library/pack/pack-owls` or
  /// `/redeem?code=ABCD-EFGH-JKLM-NPQR`.
  final Uri location;
  final LinkKind kind;

  static const webOrigin = 'https://card-jigsaw-world.appwrite.network';
  static const scheme = 'cardjigsaw';

  String get path => location.path;
  Map<String, String> get query => location.queryParameters;

  /// The address to share: the web site, which opens the app where it is installed.
  Uri get webUrl => Uri.parse('$webOrigin$location');

  /// The same link in the app's own scheme (App Store In-App Events, the widget).
  Uri get appUrl => Uri.parse('$scheme:/$location');

  @override
  bool operator ==(Object other) => other is AppLink && other.location == location && other.kind == kind;

  @override
  int get hashCode => Object.hash(location, kind);

  @override
  String toString() => '$kind $location';

  /// Pack, picture and player ids (Appwrite ids and the catalogue's slugs).
  static final _id = RegExp(r'^[A-Za-z0-9._-]{1,64}$');

  /// Reads [uri] (web address, `cardjigsaw://` link or a bare path) into the link it opens, or
  /// null when it is not one of the game's links: another scheme (the Appwrite sign-in redirect),
  /// the web sign-in callback, site files, or a path the app has no screen for.
  static AppLink? parse(Uri uri) {
    final List<String> raw;
    switch (uri.scheme.toLowerCase()) {
      case scheme:
        // cardjigsaw://library/pack/x puts "library" in the host; cardjigsaw:///library/pack/x does not.
        raw = [if (uri.host.isNotEmpty) uri.host, ...uri.pathSegments];
      case 'http' || 'https' || '':
        raw = uri.pathSegments;
      default:
        return null;
    }
    final s = [for (final x in raw) if (x.isNotEmpty) x];
    final q = uri.queryParameters;
    final head = s.isEmpty ? '' : s.first.toLowerCase();
    final rest = s.length > 1 ? s.sublist(1) : const <String>[];

    AppLink page(String path, [Map<String, String>? query]) => AppLink._(_uri(path, query), LinkKind.page);
    AppLink overlay(String path, [Map<String, String>? query]) => AppLink._(_uri(path, query), LinkKind.overlay);
    AppLink action(String path, [Map<String, String>? query]) => AppLink._(_uri(path, query), LinkKind.action);
    String? id(int i) => i < rest.length && _id.hasMatch(rest[i]) ? rest[i] : null;
    // A code from the path (/redeem/ABCD-...) or the query (?code=ABCD-...).
    String? code() {
      final c = (rest.isNotEmpty ? rest.first : q['code'])?.trim();
      return c == null || c.isEmpty || c.length > 64 ? null : c;
    }

    Map<String, String> only(Iterable<String> keys) => {for (final k in keys) if (q[k] != null && q[k]!.isNotEmpty) k: q[k]!};

    switch (head) {
      case '' || 'home' when rest.isEmpty:
        return page('/home');
      case 'library' when rest.isEmpty:
        return page('/library', only(const ['filter']));
      case 'library' when rest.length == 2 && rest.first.toLowerCase() == 'pack' && _id.hasMatch(rest[1]):
        return page('/library/pack/${rest[1]}');
      case 'pack' || 'packs' when rest.length == 1 && id(0) != null:
        return page('/library/pack/${id(0)}');
      case 'play' || 'picture' || 'puzzle' when rest.length == 1 && id(0) != null:
        return overlay('/play/${id(0)}', only(const ['grid', 'mode', 'painting']));
      // A board link opens the picture with that board chosen, so its locks still apply.
      case 'game' when rest.length == 2 && id(0) != null && id(1) != null:
        return overlay('/play/${id(0)}', {'grid': id(1)!, ...only(const ['painting'])});
      case 'events' || 'quests' when rest.isEmpty:
        return page('/events');
      case 'social' || 'leaderboard' || 'league' when rest.isEmpty:
        return page('/social', q['tab']?.toLowerCase() == 'friends' ? const {'tab': 'friends'} : null);
      case 'friends' when rest.isEmpty:
        return page('/social', const {'tab': 'friends'});
      case 'add-friend' || 'friend' when rest.length <= 1:
        final c = code();
        return action('/add-friend', c == null ? null : {'code': c});
      case 'profile' when rest.isEmpty:
        return page('/profile');
      case 'profile' when rest.length == 1 && const {'settings', 'account', 'my-puzzles'}.contains(rest.first.toLowerCase()):
        return page('/profile/${rest.first.toLowerCase()}');
      case 'settings' when rest.isEmpty:
        return page('/profile/settings');
      case 'my-puzzles' when rest.isEmpty:
        return page('/profile/my-puzzles');
      case 'account' || 'sign-in' when rest.isEmpty:
        return overlay('/account');
      case 'player' || 'user' when rest.length == 1 && id(0) != null:
        return overlay('/player/${id(0)}');
      case 'store' || 'shop' when rest.isEmpty:
        return overlay('/store', q['vip'] == '1' ? const {'vip': '1'} : null);
      case 'vip' when rest.isEmpty:
        return overlay('/store', const {'vip': '1'});
      case 'wheel' || 'lucky-wheel' when rest.isEmpty:
        return overlay('/wheel');
      case 'redeem' || 'code' when rest.length <= 1:
        final c = code();
        return action('/redeem', c == null ? null : {'code': c});
      case 'daily' || 'today' when rest.isEmpty:
        return action('/daily');
      case 'quick' || 'quick-play' when rest.isEmpty:
        return action('/quick');
      case 'gift' || 'daily-gift' when rest.isEmpty:
        return action('/gift');
      case 'piggy' || 'piggy-bank' when rest.isEmpty:
        return action('/piggy');
    }
    return null;
  }

  static Uri _uri(String path, Map<String, String>? query) =>
      query == null || query.isEmpty ? Uri(path: path) : Uri(path: path, queryParameters: query);
}
