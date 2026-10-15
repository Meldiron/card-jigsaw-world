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
import 'package:card_jigsaw_world/router.dart';
import 'package:card_jigsaw_world/state/merge.dart';
import 'package:card_jigsaw_world/state/rewards.dart';
import 'package:card_jigsaw_world/state/catalog.dart';
import 'package:card_jigsaw_world/widgets/icons.dart';
import 'package:card_jigsaw_world/widgets/ui.dart';
import 'package:flutter/material.dart';
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
  'boardChoice': (ctx, c, a) => showBoardChoiceSheet(
        ctx,
        title: a['title'] as String?,
        device: _row(a['puzzle'] as String? ?? 'x', layout: [for (var i = 0; i < 16; i++) i < 9 ? i : 24 - i], moves: 31, seconds: 260),
        other: _row(a['puzzle'] as String? ?? 'x', layout: [for (var i = 0; i < 16; i++) i < 4 ? i : 19 - i], moves: 12, seconds: 95),
      ),
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
