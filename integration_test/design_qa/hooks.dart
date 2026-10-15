// Design QA harness: sheets, alerts and overlays a scene can open directly ({"hook": "<name>", "args": {...}}).
// Add a hook here when a state is hard to reach by taps. Not part of the app.
import 'dart:async';

import 'package:card_jigsaw_world/features/ads/house_ads.dart';
import 'package:card_jigsaw_world/features/daily/daily_reward_sheet.dart';
import 'package:card_jigsaw_world/features/daily/piggy_sheet.dart';
import 'package:card_jigsaw_world/features/daily/wheel_screen.dart';
import 'package:card_jigsaw_world/features/game/unlock_intro.dart';
import 'package:card_jigsaw_world/features/profile/avatar_picker.dart';
import 'package:card_jigsaw_world/features/profile/merge_sheet.dart';
import 'package:card_jigsaw_world/features/profile/redeem_code_sheet.dart';
import 'package:card_jigsaw_world/features/social/player_safety.dart';
import 'package:card_jigsaw_world/features/social/social_screen.dart';
import 'package:card_jigsaw_world/features/sync/board_choice_sheet.dart';
import 'package:card_jigsaw_world/features/update/update_host.dart';
import 'package:card_jigsaw_world/data/sync/notice.dart';
import 'package:card_jigsaw_world/data/sync/ops.dart' show SkipReason;
import 'package:card_jigsaw_world/state/app_update.dart';
import 'package:card_jigsaw_world/state/sync.dart';
import 'package:appwrite/appwrite.dart' show TablesDB;
import 'package:appwrite/models.dart' as models;
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/router.dart';
import 'package:card_jigsaw_world/state/merge.dart';
import 'package:card_jigsaw_world/state/catalog.dart';
import 'package:card_jigsaw_world/state/rewards.dart';
import 'package:card_jigsaw_world/widgets/glass.dart';
import 'package:card_jigsaw_world/widgets/icons.dart';
import 'package:card_jigsaw_world/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef Hook = Future<void> Function(BuildContext context, ProviderContainer c, Map<String, dynamic> args);

/// Runs [fn] with a [WidgetRef] (some sheets need one): a hidden overlay entry lends its ref.
Future<void> withRef(BuildContext context, Future<void> Function(BuildContext context, WidgetRef ref) fn) async {
  // The root navigator's own overlay (the navigator's context has no Overlay above it).
  final overlay = rootNavigatorKey.currentState!.overlay!;
  late OverlayEntry entry;
  var started = false;
  entry = OverlayEntry(
    builder: (_) => Consumer(builder: (ctx, ref, _) {
      if (!started) {
        started = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(fn(ctx, ref)));
      }
      return const SizedBox.shrink();
    }),
  );
  overlay.insert(entry);
}

PuzzleProgress _row(String puzzleId, {required List<int> layout, int moves = 20, int seconds = 180, String mode = 'cards'}) => PuzzleProgress.fromRow('p', {
      'userId': 'dqa-player',
      'puzzleId': puzzleId,
      'gridSize': layout.length,
      'mode': mode,
      'layout': layout.join(','),
      'moves': moves,
      'elapsedSeconds': seconds,
    });

/// A context inside the tab shell's body (under the floating tab bar).
BuildContext? _tabPageContext() {
  BuildContext? found;
  void visit(Element e) {
    if (found != null) return;
    if (e.widget is GlassTabBarScope) {
      e.visitChildElements((c) => found ??= c);
      return;
    }
    e.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return found;
}

/// A `releases` row for [IosUpdateSource] (the update prompt's real copy).
class _ReleaseTables implements TablesDB {
  _ReleaseTables(this.build, this.version);
  final int build;
  final String version;
  @override
  Future<models.Row> getRow({required String databaseId, required String tableId, required String rowId, List<String>? queries, String? transactionId}) async =>
      models.Row($id: rowId, $sequence: '1', $tableId: tableId, $databaseId: databaseId, $createdAt: '', $updatedAt: '', $permissions: const [], data: {'build': build, 'version': version});
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final hooks = <String, Hook>{
  // Shows the status bar again (a variant that hides it leaves it hidden across hot restarts).
  'statusBar': (ctx, c, a) async => SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
  'alert': (ctx, c, a) => showAppAlert(
        ctx,
        title: a['title'] as String? ?? 'Discard progress?',
        message: a['message'] as String? ?? 'Your board for this picture will be cleared. This cannot be undone.',
        confirmLabel: a['confirm'] as String? ?? 'Discard',
        cancelLabel: a.containsKey('cancel') ? a['cancel'] as String? : 'Cancel',
        destructive: a['destructive'] as bool? ?? true,
      ),
  // {"text": "...", "delay": 1500}: the toast lasts 2 s, so it is shown late enough to be on screen at the shot.
  'toast': (ctx, c, a) async {
    await Future<void>.delayed(Duration(milliseconds: a['delay'] as int? ?? 1300));
    // "page": true shows it from a context under the tab bar (as a tab page's own call would).
    final from = a['page'] == true ? _tabPageContext() ?? ctx : ctx;
    if (from.mounted) showToast(from, a['text'] as String? ?? 'Saved', icon: a['icon'] == 'signal' ? AppIcons.signal : null);
  },
  'dailyGift': (ctx, c, a) => showDailyRewardSheet(ctx),
  'piggy': (ctx, c, a) => showPiggySheet(ctx),
  'avatarPicker': (ctx, c, a) => showAvatarPicker(ctx),
  'addFriend': (ctx, c, a) => showAddFriendAlert(ctx, code: a['code'] as String?),
  'blocked': (ctx, c, a) => showBlockedPlayersSheet(ctx),
  'wheelOdds': (ctx, c, a) => showWheelOdds(ctx),
  'redeem': (ctx, c, a) => showRedeemCodeSheet(ctx, code: a['code'] as String?),
  'report': (ctx, c, a) => showReportSheet(
        ctx,
        Profile.fromRow('player-3', {'userId': 'player-3', 'displayName': a['name'] ?? 'Dmitri', 'avatar': 'drop', 'xp': 4000}),
      ),
  'unlockIntro': (ctx, c, a) => withRef(ctx, (ctx, ref) => showUnlockIntro(ctx, ref, Unlock.values.byName(a['unlock'] as String? ?? 'squares'))),
  'lockedInfo': (ctx, c, a) => withRef(ctx, (ctx, ref) => showLockedInfo(ctx, ref, Unlock.values.byName(a['unlock'] as String? ?? 'hexagons'))),
  'rewardedAd': (ctx, c, a) => withRef(ctx, (ctx, ref) => showRewardedHouseAd(ctx, ref, rewardCoins: 40)),
  // A fixed house ad (deterministic creative and cover): {"creative": "vip-months", "pack": "pack-islands", "rewarded": true}.
  'houseAd': (ctx, c, a) async {
    final creative = houseCreatives.firstWhere((x) => x.id == (a['creative'] as String? ?? 'vip-months'));
    final packs = c.read(packsProvider).value ?? const <Pack>[];
    final pack = packs.where((p) => p.id == (a['pack'] as String? ?? 'pack-islands')).firstOrNull;
    final rewarded = a['rewarded'] as bool? ?? true;
    await Navigator.of(ctx, rootNavigator: true).push<Object?>(PageRouteBuilder(
      opaque: true,
      fullscreenDialog: true,
      pageBuilder: (_, _, _) => HouseAdScreen(
        creative: creative,
        coverUrl: pack == null ? null : (url: pack.coverUrl, hash: pack.blurhash),
        rewarded: rewarded,
        rewardCoins: rewarded ? 40 : 0,
      ),
    ));
  },
  'boardChoice': (ctx, c, a) => showBoardChoiceSheet(
        ctx,
        title: a['title'] as String?,
        device: _row(a['puzzle'] as String? ?? 'x', layout: [for (var i = 0; i < 16; i++) i < 9 ? i : 24 - i], moves: 31, seconds: 260),
        other: _row(a['puzzle'] as String? ?? 'x', layout: [for (var i = 0; i < 16; i++) i < 4 ? i : 19 - i], moves: 12, seconds: 95, mode: a['otherMode'] as String? ?? 'cards'),
      ),
  // The "Synced from another device" alert through the real SyncHost: {"size": "small" | "big" | "skips"}.
  'syncNotice': (ctx, c, a) async {
    final n = switch (a['size'] as String? ?? 'small') {
      'big' => const SyncNotice(
          coins: 1460, tickets: 3, hints: -1, level: 12, solved: 14, betterStars: 3, boards: ['a', 'b'],
          packs: ['wild-nature', 'ai-wild-animals'], quests: 4, achievements: 2, dailyStreak: 9, avatarChanged: true,
          skipped: [SkipReason.questClaimed, SkipReason.dailyClaimed]),
      'skips' => const SyncNotice(skipped: [SkipReason.notEnough, SkipReason.unlocked]),
      _ => const SyncNotice(coins: 240, solved: 3, boards: ['a']),
    };
    c.read(syncNoticeProvider.notifier).add(n);
  },
  // The update prompt through the real UpdateHost: {"channel": "testflight" | "appStore" | "web", "build": 119, "current": 118}.
  'updatePrompt': (ctx, c, a) async {
    UpdateHost.lastAsked = null;
    final channel = a['channel'] as String? ?? 'testflight';
    final AvailableUpdate? u;
    if (channel == 'web') {
      u = await WebUpdateSource(current: 'old', fetch: (_) async => '{"build": "new"}', reload: () {}).check();
    } else {
      u = await IosUpdateSource(_ReleaseTables(a['build'] as int? ?? 119, a['version'] as String? ?? '1.7.0'),
              channel: channel == 'appStore' ? IosChannel.appStore : IosChannel.testflight, currentBuild: a['current'] as int? ?? 118, open: (_) async => true)
          .check();
    }
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    c.read(appUpdateProvider.notifier).state = u;
  },
  // The one-time daily reminder question (real code; needs notification permission "not determined").
  'reminderOffer': (ctx, c, a) => offerRemindersAfterGift(ctx, c),
  // Realistic saves: the same player on both sides (a guest who signs in to their own older account).
  'merge': (ctx, c, a) {
    List<Map<String, dynamic>> solved(int n, int days) => [
          for (var i = 0; i < n; i++)
            {'puzzleId': 'z$i', 'completed': true, 'stars': 1 + i % 3, '\$updatedAt': DateTime.now().subtract(Duration(days: days, hours: i)).toIso8601String()},
        ];
    return showMergeSheet(
      ctx,
      device: SaveSnapshot(
        userId: 'dqa-player',
        profile: {'displayName': a['device'] ?? 'Mia', 'avatar': 'leaf', 'level': 5, 'coins': 1240, 'tickets': 4, 'hints': 2, 'xp': 880, 'streak': 3},
        progress: solved(17, 0),
      ),
      account: SaveSnapshot(
        userId: 'acc',
        profile: {'displayName': a['account'] ?? 'Mia', 'avatar': 'fox', 'level': 9, 'coins': 5400, 'tickets': 11, 'hints': 6, 'xp': 2310, 'streak': 12},
        progress: solved(41, 2),
        updatedAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
    );
  },
  // Types into the focused text field (else the first one on screen): {"hook": "type", "args": {"text": "owl"}}.
  'type': (ctx, c, a) async {
    final fields = <EditableTextState>[];
    void visit(Element e) {
      if (e is StatefulElement && e.state is EditableTextState) fields.add(e.state as EditableTextState);
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    if (fields.isEmpty) throw StateError('type: no text field');
    final field = fields.firstWhere((f) => f.widget.focusNode.hasFocus, orElse: () => fields.first);
    field.widget.controller.text = a['text'] as String? ?? '';
  },
  // Every pack category of the catalogue as the on-photo chip (pack cover, pack card), on a photo-dark panel.
  'categoryChips': (ctx, c, a) async {
    final packs = await c.read(packsProvider.future);
    final cats = <String>{for (final p in packs) p.category}.toList()..sort();
    if (!ctx.mounted) return;
    await showAppSheet<void>(
      ctx,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFF3A4A3A), borderRadius: BorderRadius.circular(16)),
          child: Wrap(spacing: 8, runSpacing: 10, children: [for (final cat in cats) Chip2(label: cat, icon: AppIcons.category(cat), onImage: true)]),
        ),
      ),
    );
  },
};
