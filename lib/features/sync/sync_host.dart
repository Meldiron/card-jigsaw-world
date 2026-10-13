import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../data/purchases.dart' show groupThousands;
import '../../data/sync/notice.dart';
import '../../data/sync/ops.dart';
import '../../models/models.dart';
import '../../router.dart';
import '../../state/catalog.dart';
import '../../state/social.dart';
import '../../state/sync.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import 'board_choice_sheet.dart';

/// Shows what the save sync has to tell the player: the "Synced from another device" alert
/// (between screens, never during a game) and the board choice when this device and another
/// one both have a board in progress for the same picture.
class SyncHost extends ConsumerStatefulWidget {
  const SyncHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<SyncHost> createState() => _SyncHostState();
}

class _SyncHostState extends ConsumerState<SyncHost> {
  GoRouter? _router;
  bool _showing = false;
  late final SyncController _sync;

  @override
  void initState() {
    super.initState();
    _sync = ref.read(syncProvider.notifier)..resolver = _resolve;
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_maybeShow);
    if (_sync.resolver == _resolve) _sync.resolver = null;
    super.dispose();
  }

  Future<BoardChoice> _resolve(BoardConflict c) async {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return BoardChoice.device;
    final title = ref.read(resolvedPuzzleProvider(c.puzzleId))?.title;
    return showBoardChoiceSheet(ctx, title: title, device: c.device, other: c.other);
  }

  /// Not during a game, a sign-in or the welcome screens.
  bool get _calm {
    final path = _router?.routerDelegate.currentConfiguration.uri.path ?? '';
    return path.isNotEmpty && !path.startsWith('/game/') && !path.startsWith('/auth/') && !path.startsWith('/welcome');
  }

  Future<void> _maybeShow() async {
    if (_showing || !mounted || !_calm || ref.read(syncNoticeProvider).isEmpty) return;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    _showing = true;
    final notice = ref.read(syncNoticeProvider.notifier).take();
    final packs = <String, String>{for (final p in ref.read(packsProvider).value ?? const <Pack>[]) p.id: p.name};
    await showAppAlert(
      ctx,
      title: 'Synced from another device',
      child: SyncNoticeList(lines: syncNoticeLines(notice, packNames: packs)),
      confirmLabel: 'Continue',
      cancelLabel: null,
    );
    _showing = false;
    if (mounted) Future.delayed(const Duration(milliseconds: 300), _maybeShow);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    if (router != _router) {
      _router?.routerDelegate.removeListener(_maybeShow);
      _router = router..routerDelegate.addListener(_maybeShow);
    }
    ref.listen(syncNoticeProvider, (_, n) {
      if (!n.isEmpty) Future.delayed(const Duration(milliseconds: 600), _maybeShow);
    });
    return widget.child;
  }
}

/// One line of the alert: what changed, with its icon.
typedef SyncNoticeLine = ({SyncLineIcon icon, String text});

enum SyncLineIcon { coins, tickets, hints, level, puzzle, star, board, unlock, avatar, quest, achievement, dailyGift, vip, profile, check }

String _count(int n, String one, String many) => '${groupThousands(n)} ${n == 1 ? one : many}';

String _signed(int n, String one, String many) => '${n > 0 ? '+' : '−'}${_count(n.abs(), one, many)}';

/// The alert's lines, in a fixed order: balances, level, pictures, unlocks, claims, identity, and
/// last what was not done twice.
List<SyncNoticeLine> syncNoticeLines(SyncNotice n, {Map<String, String> packNames = const {}}) {
  final names = [for (final id in n.packs) ?packNames[id]];
  return [
    if (n.coins != 0) (icon: SyncLineIcon.coins, text: _signed(n.coins, 'Coin', 'Coins')),
    if (n.tickets != 0) (icon: SyncLineIcon.tickets, text: _signed(n.tickets, 'Ticket', 'Tickets')),
    if (n.hints != 0) (icon: SyncLineIcon.hints, text: _signed(n.hints, 'Hint', 'Hints')),
    if (n.level != null) (icon: SyncLineIcon.level, text: 'Level ${n.level}'),
    if (n.solved > 0) (icon: SyncLineIcon.puzzle, text: '${_count(n.solved, 'picture', 'pictures')} solved'),
    if (n.betterStars > 0) (icon: SyncLineIcon.star, text: 'More stars on ${_count(n.betterStars, 'picture', 'pictures')}'),
    if (n.boards.isNotEmpty) (icon: SyncLineIcon.board, text: '${n.boards.length == 1 ? 'Board' : 'Boards'} in progress on ${_count(n.boards.length, 'picture', 'pictures')}'),
    if (n.packs.isNotEmpty)
      (
        icon: SyncLineIcon.unlock,
        text: names.length == n.packs.length ? 'Unlocked: ${names.join(', ')}' : '${_count(n.packs.length, 'pack', 'packs')} unlocked',
      ),
    if (n.tiers > 0) (icon: SyncLineIcon.unlock, text: '${_count(n.tiers, 'board size', 'board sizes')} unlocked'),
    if (n.avatars > 0) (icon: SyncLineIcon.avatar, text: '${_count(n.avatars, 'avatar', 'avatars')} unlocked'),
    if (n.quests > 0) (icon: SyncLineIcon.quest, text: '${_count(n.quests, 'quest', 'quests')} claimed'),
    if (n.achievements > 0) (icon: SyncLineIcon.achievement, text: '${_count(n.achievements, 'achievement reward', 'achievement rewards')} claimed'),
    if (n.dailyStreak != null) (icon: SyncLineIcon.dailyGift, text: 'Daily gift claimed · Streak: ${_count(n.dailyStreak!, 'day', 'days')}'),
    if (n.vipStarted) (icon: SyncLineIcon.vip, text: 'VIP active'),
    if (n.vipEnded) (icon: SyncLineIcon.vip, text: 'VIP ended'),
    if (n.name != null) (icon: SyncLineIcon.profile, text: 'Name: ${n.name}'),
    if (n.avatarChanged) (icon: SyncLineIcon.avatar, text: 'New avatar'),
    for (final r in {...n.skipped}) (icon: SyncLineIcon.check, text: skipText(r)),
  ];
}

/// Something done on this device that another device had already done; it counted once.
String skipText(SkipReason r) => switch (r) {
      SkipReason.questClaimed => 'Quest already claimed on another device; paid once',
      SkipReason.vipBonusPaid => "This week's VIP bonus was already paid",
      SkipReason.dailyClaimed => "Today's daily gift was already claimed; paid once",
      SkipReason.streakRestored => 'Streak already restored; no Tickets spent',
      SkipReason.unlocked => 'Already unlocked on another device; nothing charged',
      SkipReason.achievementClaimed => 'Achievement reward already claimed; paid once',
      SkipReason.piggyEmpty => 'Piggy bank already opened on another device',
      SkipReason.notEnough => 'Not enough left after spending on another device; one purchase here was undone',
    };

class SyncNoticeList extends StatelessWidget {
  const SyncNoticeList({super.key, required this.lines});
  final List<SyncNoticeLine> lines;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget icon(SyncLineIcon i) => switch (i) {
          SyncLineIcon.coins => const CoinIcon(size: 18),
          SyncLineIcon.tickets => const TicketIcon(size: 18),
          SyncLineIcon.hints => const HintIcon(size: 18),
          SyncLineIcon.star => const Icon(AppIcons.star, size: 17, color: Brand.star),
          _ => Icon(
              switch (i) {
                SyncLineIcon.level => AppIcons.level,
                SyncLineIcon.puzzle => AppIcons.puzzle,
                SyncLineIcon.board => AppIcons.filterStarted,
                SyncLineIcon.unlock => AppIcons.unlock,
                SyncLineIcon.avatar => AppIcons.profile,
                SyncLineIcon.quest => AppIcons.quests,
                SyncLineIcon.achievement => AppIcons.trophy,
                SyncLineIcon.dailyGift => AppIcons.dailyGift,
                SyncLineIcon.vip => AppIcons.vip,
                SyncLineIcon.profile => AppIcons.profile,
                _ => AppIcons.check,
              },
              size: 17,
              color: c.textSecondary,
            ),
        };
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 22, child: Center(child: icon(l.icon))),
                    const SizedBox(width: 10),
                    Expanded(child: Text(l.text, style: TextStyle(fontSize: 14, height: 1.3, color: c.textPrimary))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
