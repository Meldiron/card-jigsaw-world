import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_links.dart';
import '../../models/models.dart';
import '../../router.dart';
import '../../state/catalog.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/quick_play.dart';
import '../../state/settings.dart';
import '../daily/daily_reward_sheet.dart';
import '../daily/piggy_sheet.dart';
import '../gallery/library_screen.dart';
import '../profile/redeem_code_sheet.dart';
import '../social/social_screen.dart';

final deepLinksProvider = Provider<DeepLinks>(DeepLinks.new);

/// Puts a link (`lib/core/app_links.dart`, docs/deep-links.md) on screen. Links reach it from
/// outside the app on iPhone (`CardJigsawApp.didPushRouteInformation`: the `cardjigsaw://` scheme,
/// universal links, the widget), from the address a web visit starts on (`routerProvider`), and
/// from paths the router has no page for (`onException`).
class DeepLinks {
  DeepLinks(this._ref);
  final Ref _ref;
  final _random = Random();

  Future<void> show(AppLink link) async {
    if (!_ref.read(settingsProvider).onboarded) {
      // A plain Home link leaves a new player on the welcome screens; any other link counts as
      // onboarding, so the welcome screens never cover where it leads.
      if (link.kind == LinkKind.page && link.path == '/home') return;
      _ref.read(settingsProvider.notifier).setOnboarded();
    }
    final router = _ref.read(routerProvider);
    switch (link.kind) {
      case LinkKind.page:
        await _page(router, link);
      case LinkKind.overlay:
        await _overlay(router, link);
      case LinkKind.action:
        await _action(router, link);
    }
  }

  Future<void> _page(GoRouter router, AppLink link) async {
    switch (link.path) {
      case '/library':
        final filter = link.query['filter'];
        if (filter != null) await _libraryFilter(filter);
      case '/social':
        _ref.read(socialTabProvider.notifier).select(link.query['tab'] == 'friends' ? SocialTab.friends : SocialTab.leaderboard);
    }
    // The query was for the screen state above; the route itself is the path.
    router.go(link.path);
  }

  Future<void> _overlay(GoRouter router, AppLink link) async {
    if (link.path.startsWith('/play/')) {
      // A picture of a pack the player has not opened (or a day not out yet) shows its pack,
      // with the price or the calendar, instead of a board.
      final packId = await _closedPackOf(link.path.substring('/play/'.length));
      if (packId != null) {
        router.go('/library/pack/$packId');
        return;
      }
    }
    await _onPage(router);
    final location = link.location.toString();
    if (_top(router) == location) return;
    unawaited(router.push(location));
  }

  Future<void> _action(GoRouter router, AppLink link) async {
    switch (link.path) {
      case '/redeem':
        await _onPage(router);
        final ctx = rootNavigatorKey.currentContext;
        if (ctx != null && ctx.mounted) await showRedeemCodeSheet(ctx, code: link.query['code']);
      case '/add-friend':
        _ref.read(socialTabProvider.notifier).select(SocialTab.friends);
        await _onPage(router, '/social');
        final ctx = rootNavigatorKey.currentContext;
        if (ctx != null && ctx.mounted) await showAddFriendAlert(ctx, code: link.query['code']);
      case '/daily':
        await _ready();
        final puzzle = _ref.read(dailyPuzzleProvider);
        if (puzzle == null) return _onPage(router, '/home');
        await _overlay(router, AppLink.parse(Uri(path: '/play/${puzzle.id}'))!);
      case '/quick':
        await _ready(progress: true);
        final location = _quickPlay();
        if (location == null) return _onPage(router, '/home');
        await _onPage(router);
        unawaited(router.push(location));
      case '/gift':
        await _onPage(router, '/home');
        final ctx = rootNavigatorKey.currentContext;
        if (ctx != null && ctx.mounted) await showDailyRewardSheet(ctx);
      case '/piggy':
        await _onPage(router, '/home');
        final ctx = rootNavigatorKey.currentContext;
        if (ctx != null && ctx.mounted) await showPiggySheet(ctx);
    }
  }

  /// Overlays and sheets open above a page: [page] when the link needs that one, else Home when
  /// the app has only just started or still shows the welcome screens.
  Future<void> _onPage(GoRouter router, [String? page]) async {
    final at = Uri.parse(_top(router)).path;
    final target = page ?? (at.isEmpty || at == '/' || at == '/welcome' || at.startsWith('/auth/') ? '/home' : null);
    if (target == null || at == target) return;
    router.go(target);
    for (var i = 0; i < 60 && Uri.parse(_top(router)).path != target; i++) {
      await WidgetsBinding.instance.endOfFrame;
    }
    // One more frame so the page is built before a sheet opens over it.
    await WidgetsBinding.instance.endOfFrame;
  }

  /// The route on top, a page pushed above the tabs included; empty before the first route.
  String _top(GoRouter router) => router.routerDelegate.currentConfiguration.isEmpty ? '' : router.state.uri.toString();

  /// Waits (at most 15 seconds) for the catalogue and the player's profile, which a link
  /// opened at launch may arrive before.
  Future<void> _ready({bool progress = false}) async {
    try {
      await Future.wait<Object?>([
        _ref.read(packsProvider.future),
        _ref.read(allPuzzlesProvider.future),
        _ref.read(profileProvider.future),
        if (progress) _ref.read(progressProvider.future),
      ]).timeout(const Duration(seconds: 15));
    } catch (_) {
      // Screens show their own loading and error states.
    }
  }

  /// The pack to show instead of the picture [puzzleId]: its pack when the player cannot play
  /// the picture yet, null when the picture can open (or is unknown: its screen says so).
  Future<String?> _closedPackOf(String puzzleId) async {
    await _ready();
    final puzzle = (_ref.read(allPuzzlesProvider).value ?? const <Puzzle>[]).where((p) => p.id == puzzleId).firstOrNull;
    if (puzzle == null) return null;
    final pack = (_ref.read(packsProvider).value ?? const <Pack>[]).where((p) => p.id == puzzle.packId).firstOrNull;
    if (pack == null || puzzle.isLockedByDate) return puzzle.packId;
    if (_ref.read(profileProvider).value == null) return puzzle.packId;
    return _ref.read(profileProvider.notifier).isUnlocked(pack) ? null : pack.id;
  }

  /// `/library?filter=`: a chip by its label (All, New, Finished, Started, Unlocked, Daily) or a
  /// category the Library has a chip for (Animals, Giant), in any case. Event has no chip (events
  /// live on Home and in Quests): such a link, like any filter without a chip, opens it on All.
  Future<void> _libraryFilter(String filter) async {
    final want = filter.trim().toLowerCase();
    const chips = [LibraryFilter.all, LibraryFilter.fresh, LibraryFilter.finished, LibraryFilter.started, LibraryFilter.unlocked, LibraryFilter.daily];
    var chip = chips.where((c) => c.toLowerCase() == want).firstOrNull;
    if (chip == null) {
      await _ready();
      final packs = _ref.read(packsProvider).value ?? const <Pack>[];
      chip = libraryChips(packs, showUnlocked: true).where((c) => c.toLowerCase() == want).firstOrNull;
    }
    _ref.read(libraryFilterProvider.notifier).select(chip ?? LibraryFilter.all);
  }

  /// Where Quick play on Home would go now, or null when there is nothing to play.
  String? _quickPlay() {
    final puzzle = pickQuickPlay(_ref.read(quickPlayPoolProvider), _random);
    if (puzzle == null) return null;
    final board = openQuickPlayBoard(
      _ref.read(quickPlayBoardProvider),
      level: _ref.read(profileProvider).value?.level ?? 1,
      hasTier: _ref.read(profileProvider.notifier).hasTier,
    );
    return quickPlayRoute(puzzle, saved: _ref.read(progressProvider).value?[puzzle.id], board: board);
  }
}
