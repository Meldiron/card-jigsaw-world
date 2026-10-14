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
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/merge.dart';
import 'package:card_jigsaw_world/state/catalog.dart';
import 'package:card_jigsaw_world/state/rewards.dart';
import 'package:card_jigsaw_world/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef Hook = Future<void> Function(BuildContext context, ProviderContainer c, Map<String, dynamic> args);

/// Runs [fn] with a [WidgetRef] (some sheets need one): a hidden overlay entry lends its ref.
Future<void> withRef(BuildContext context, Future<void> Function(BuildContext context, WidgetRef ref) fn) async {
  // The hook context is the root Navigator's own element, which sits above its Overlay.
  final overlay = context is StatefulElement && context.state is NavigatorState
      ? (context.state as NavigatorState).overlay!
      : Overlay.of(context, rootOverlay: true);
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

PuzzleProgress _row(String puzzleId, {required List<int> layout, int moves = 20, int seconds = 180}) => PuzzleProgress.fromRow('p', {
      'userId': 'dqa-player',
      'puzzleId': puzzleId,
      'gridSize': 4,
      'mode': 'cards',
      'layout': layout.join(','),
      'moves': moves,
      'elapsedSeconds': seconds,
    });

final hooks = <String, Hook>{
  'alert': (ctx, c, a) => showAppAlert(
        ctx,
        title: a['title'] as String? ?? 'Discard progress?',
        message: a['message'] as String? ?? 'Your board for this picture will be cleared. This cannot be undone.',
        confirmLabel: a['confirm'] as String? ?? 'Discard',
        destructive: a['destructive'] as bool? ?? true,
      ),
  'toast': (ctx, c, a) async => showToast(ctx, a['text'] as String? ?? 'Saved'),
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
        other: _row(a['puzzle'] as String? ?? 'x', layout: [for (var i = 0; i < 16; i++) i < 4 ? i : 19 - i], moves: 12, seconds: 95),
      ),
  'merge': (ctx, c, a) => showMergeSheet(
        ctx,
        device: SaveSnapshot(userId: 'dqa-player', profile: {'coins': 1240, 'tickets': 4, 'hints': 2, 'xp': 2200, 'puzzlesCompleted': 17, 'streak': 3}, progress: const []),
        account: SaveSnapshot(userId: 'acc', profile: {'coins': 5400, 'tickets': 11, 'hints': 6, 'xp': 9100, 'puzzlesCompleted': 88, 'streak': 12}, progress: const [], updatedAt: DateTime.now().subtract(const Duration(days: 2))),
      ),
};
