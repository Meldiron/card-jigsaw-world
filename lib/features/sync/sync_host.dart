import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
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
    _router?.routerDelegate.removeListener(_onRoute);
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
    // The top-most route, pushes included (the configuration's own uri stays on the tab below,
    // so a game opened with push would count as Home).
    final router = _router;
    final path = router == null || router.routerDelegate.currentConfiguration.isEmpty ? '' : router.state.uri.path;
    return path.isNotEmpty && !path.startsWith('/game/') && !path.startsWith('/auth/') && !path.startsWith('/welcome');
  }

  /// A route change can arrive from inside the navigator (a pop notifies while it is still
  /// popping, and an alert pushed then would fail): the check waits a moment.
  void _onRoute() => Future.delayed(const Duration(milliseconds: 300), _maybeShow);

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
      _router?.routerDelegate.removeListener(_onRoute);
      _router = router..routerDelegate.addListener(_onRoute);
    }
    ref.listen(syncNoticeProvider, (_, n) {
      if (!n.isEmpty) Future.delayed(const Duration(milliseconds: 600), _maybeShow);
    });
    return widget.child;
  }
}

/// One line of the alert: what changed, with its icon.
typedef SyncNoticeLine = ({SyncLineIcon icon, String text});

enum SyncLineIcon { coins, tickets, hints, peeks, magics, level, puzzle, star, board, unlock, avatar, quest, achievement, dailyGift, vip, profile, check, undone }

String _count(int n, String one, String many) => '${formatCount(n)} ${n == 1 ? one : many}';

String _signed(int n, String one, String many) => '${n > 0 ? '+' : '−'}${_count(n.abs(), one, many)}';

/// The alert's lines, in a fixed order: balances, level, pictures, unlocks, claims, identity, and
/// last what was not done twice.
List<SyncNoticeLine> syncNoticeLines(SyncNotice n, {Map<String, String> packNames = const {}}) {
  final names = [for (final id in n.packs) ?packNames[id]];
  return [
    if (n.coins != 0) (icon: SyncLineIcon.coins, text: _signed(n.coins, 'Coin', 'Coins')),
    if (n.tickets != 0) (icon: SyncLineIcon.tickets, text: _signed(n.tickets, 'Ticket', 'Tickets')),
    if (n.hints != 0) (icon: SyncLineIcon.hints, text: _signed(n.hints, 'Hint', 'Hints')),
    if (n.peeks != 0) (icon: SyncLineIcon.peeks, text: _signed(n.peeks, 'Peek', 'Peeks')),
    if (n.magics != 0) (icon: SyncLineIcon.magics, text: _signed(n.magics, 'Magic', 'Magic')),
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
    // Something undone here is not "fine": its own mark, not a tick.
    for (final r in [if (n.skipped.contains(SkipReason.notEnough)) SkipReason.notEnough, ...{...n.skipped}.where((r) => r != SkipReason.notEnough)])
      (icon: r == SkipReason.notEnough ? SyncLineIcon.undone : SyncLineIcon.check, text: skipText(r)),
  ];
}

/// Something done on this device that another device had already done; it counted once.
String skipText(SkipReason r) => switch (r) {
      SkipReason.questClaimed => 'A quest claimed on both devices, paid once',
      SkipReason.vipBonusPaid => "This week's VIP bonus, paid once",
      SkipReason.dailyClaimed => "Today's daily gift, paid once",
      SkipReason.streakRestored => 'Streak already restored, no tickets spent',
      SkipReason.unlocked => 'Already unlocked there, nothing charged',
      SkipReason.achievementClaimed => 'An achievement reward claimed on both devices, paid once',
      SkipReason.piggyEmpty => 'Piggy bank already opened on the other device',
      SkipReason.notEnough => 'One purchase here was undone: not enough was left after spending on the other device',
      SkipReason.messageClaimed => 'A message reward claimed on both devices, paid once',
    };

class SyncNoticeList extends StatefulWidget {
  const SyncNoticeList({super.key, required this.lines});
  final List<SyncNoticeLine> lines;

  @override
  State<SyncNoticeList> createState() => _SyncNoticeListState();
}

class _SyncNoticeListState extends State<SyncNoticeList> {
  final _scroll = ScrollController();
  bool _above = false, _below = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted || !_scroll.hasClients || !_scroll.position.hasContentDimensions) return;
    final above = _scroll.position.extentBefore > 0.5, below = _scroll.position.extentAfter > 0.5;
    if (above != _above || below != _below) {
      setState(() {
        _above = above;
        _below = below;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lines = widget.lines;
    const money = {SyncLineIcon.coins, SyncLineIcon.tickets, SyncLineIcon.hints, SyncLineIcon.peeks, SyncLineIcon.magics};
    const skips = {SyncLineIcon.check, SyncLineIcon.undone};
    final balances = [for (final l in lines) if (money.contains(l.icon)) l];
    final once = [for (final l in lines) if (skips.contains(l.icon)) l];
    final rest = [for (final l in lines) if (!money.contains(l.icon) && !skips.contains(l.icon)) l];
    Widget icon(SyncLineIcon i) => switch (i) {
          SyncLineIcon.coins => const CoinIcon(size: 18),
          SyncLineIcon.tickets => const TicketIcon(size: 18),
          SyncLineIcon.hints => const HintIcon(size: 18),
          SyncLineIcon.peeks => const BoosterIcon(AppIcons.peek, size: 18),
          SyncLineIcon.magics => const BoosterIcon(AppIcons.magic, size: 18),
          SyncLineIcon.star => Icon(AppIcons.star, size: 17, color: context.star),
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
                SyncLineIcon.undone => AppIcons.undo,
                _ => AppIcons.check,
              },
              size: 17,
              color: c.textSecondary,
            ),
        };
    // As tall as the screen allows (a long notice used to stop at 320 pt and
    // hide its last lines, often the ones about what was not done twice);
    // when it still scrolls, the edge with more fades out.
    Widget row(SyncNoticeLine l) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 22, child: Center(child: icon(l.icon))),
              const SizedBox(width: 10),
              Expanded(child: Text(l.text, style: TextStyle(fontSize: TypeSize.body, height: 1.3, color: c.textPrimary))),
            ],
          ),
        );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: math.max(200, MediaQuery.sizeOf(context).height - 300)),
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          _update();
          return false;
        },
        child: NotificationListener<ScrollUpdateNotification>(
          onNotification: (_) {
            _update();
            return false;
          },
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) {
              final f = (24 / math.max(rect.height, 1)).clamp(0.0, 0.5);
              return LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_above ? Colors.transparent : Colors.black, Colors.black, Colors.black, _below ? Colors.transparent : Colors.black],
                stops: [0, f, 1 - f, 1],
              ).createShader(rect);
            },
            child: SingleChildScrollView(
        controller: _scroll,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (balances.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final l in balances)
                      Semantics(
                        label: l.text,
                        excludeSemantics: true,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [icon(l.icon), const SizedBox(width: 5), Text(l.text.split(' ').first, style: TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w700, color: c.textPrimary))],
                        ),
                      ),
                  ],
                ),
              ),
            for (final l in rest) row(l),
            if (once.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Counted once', style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textSecondary)),
                ),
              ),
              for (final l in once) row(l),
            ],
          ],
        ),
      ),
          ),
        ),
      ),
    );
  }
}
