import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_links.dart';
import '../../core/haptics.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories.dart';
import '../../models/models.dart';
import '../../state/auth.dart';
import '../../state/profile.dart';
import '../../state/social.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../home/header_bar.dart';

/// Social's tab: 0 the leaderboard, 1 friends. A provider, so a link (`/social?tab=friends`,
/// `/add-friend?code=...`) can pick it.
class SocialTab extends Notifier<int> {
  static const leaderboard = 0;
  static const friends = 1;

  @override
  int build() => leaderboard;

  void select(int tab) => state = tab;
}

final socialTabProvider = NotifierProvider<SocialTab, int>(SocialTab.new);

/// "Add friend by code": Social > Friends, and the link `/add-friend?code=<friend code>`, which
/// fills the code in.
Future<void> showAddFriendAlert(BuildContext context, {String? code}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final controller = TextEditingController(text: code?.trim() ?? '');
  final c = context.colors;
  final mine = container.read(currentUserIdProvider);
  final ok = await showAppAlert(
    context,
    title: 'Add friend by code',
    message: 'Paste the code your friend shared.',
    confirmLabel: 'Add friend',
    cancelLabel: 'Not now',
    canConfirm: () => controller.text.trim().isNotEmpty,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CupertinoTextField(
      key: const ValueKey('add-friend-field'),
      controller: controller,
      placeholder: 'Friend code',
      autofocus: code == null || code.trim().isEmpty,
      autocorrect: false,
      textAlign: TextAlign.center,
      cursorColor: context.accent,
      style: TextStyle(fontSize: TypeSize.callout, color: c.textPrimary, letterSpacing: -0.2),
      placeholderStyle: TextStyle(fontSize: TypeSize.callout, color: c.textTertiary, letterSpacing: -0.2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      // The look of AlertTextField (the other alert fields), keyed for the deep-link tests.
      decoration: BoxDecoration(color: context.isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
        ),
        // The player's own code, for a friend who adds by code instead of the link.
        if (mine != null) ...[const SizedBox(height: 2), _YourCode(code: mine)],
      ],
    ),
  );
  final entered = ok ? controller.text.trim() : null;
  if (entered == null || entered.isEmpty || !context.mounted) return;
  final me = container.read(currentUserIdProvider);
  if (me == null) return;
  if (entered == me) {
    showToast(context, 'That is your own code. Share it with a friend instead.', icon: AppIcons.profile);
    return;
  }
  try {
    final friend = await container.read(profileRepositoryProvider).findByUserId(entered);
    if (friend == null) {
      if (context.mounted) showToast(context, 'No player with that code. Check it and try again.', icon: AppIcons.search);
      return;
    }
    await container.read(socialRepositoryProvider).addFriend(me, friend);
    container.invalidate(friendsProvider);
    if (context.mounted) {
      Haptics.success();
      showToast(context, 'Added ${friend.displayName}', icon: AppIcons.addFriend);
    }
  } catch (e) {
    if (context.mounted) showToast(context, 'Could not add friend. Check your connection and try again.', icon: AppIcons.signal);
  }
}

/// "Your code 6acb...  [copy]" under the Add friend field: tap to copy. The alert sits above the
/// toasts, so the line itself confirms the copy.
class _YourCode extends StatefulWidget {
  const _YourCode({required this.code});
  final String code;
  @override
  State<_YourCode> createState() => _YourCodeState();
}

class _YourCodeState extends State<_YourCode> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      key: const ValueKey('add-friend-your-code'),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: widget.code));
        if (!mounted) return;
        setState(() => _copied = true);
        await Future<void>.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _copied = false);
      },
      child: TapTarget(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Your code', style: TextStyle(fontSize: TypeSize.caption, color: c.textSecondary)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _copied ? 'Copied' : widget.code,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w600, color: c.textPrimary, fontFeatures: tabularFigures),
              ),
            ),
            const SizedBox(width: 5),
            Icon(_copied ? AppIcons.checkmarkAlt : AppIcons.copy, size: 13, color: context.accent),
          ],
        ),
      ),
    );
  }
}

/// Social: the leaderboard (every player by total XP) and friends (add by friend code).
class SocialScreen extends ConsumerWidget {
  const SocialScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(socialTabProvider);
    return Scaffold(
      body: Column(
        children: [
          const HeaderBar(title: 'Social', sliver: false),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The large title alone on its line and the switch under it, full width (the iOS
                // pattern): neither squeezes the other at any text size.
                const PageTitle('Social'),
                const SizedBox(height: 10),
                AppSegmentedControl<int>(
                  value: tab,
                  segments: const {0: 'Leaderboard', 1: 'Friends'},
                  segmentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  onChanged: (v) => ref.read(socialTabProvider.notifier).select(v),
                ),
              ],
            ),
          ),
          Expanded(child: tab == SocialTab.leaderboard ? const _Leaderboard() : _Friends(onAdd: () => showAddFriendAlert(context))),
        ],
      ),
    );
  }
}

class _Leaderboard extends ConsumerStatefulWidget {
  const _Leaderboard();
  @override
  ConsumerState<_Leaderboard> createState() => _LeaderboardState();
}

class _LeaderboardState extends ConsumerState<_Leaderboard> {
  final _scroll = ScrollController();
  final _meKey = GlobalKey();

  /// Whether the player's own row is on screen; the pinned "your place" bar shows only when it is not.
  bool _meOnScreen = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _checkMe() {
    final box = _meKey.currentContext?.findRenderObject() as RenderBox?;
    var on = false;
    if (box != null && box.attached && box.hasSize) {
      final top = box.localToGlobal(Offset.zero).dy;
      final screen = MediaQuery.sizeOf(context).height;
      // Between the Social title row and the pinned bar above the tab bar.
      on = top + box.size.height > 200 && top < screen - GlassTabBar.scrollEndPadding(context, margin: 0) - 70;
    }
    if (on != _meOnScreen && mounted) setState(() => _meOnScreen = on);
  }

  /// Scrolls to the player's row when it is loaded; otherwise opens their own profile.
  Future<void> _showMe(List<Profile> list, String? me) async {
    final index = list.indexWhere((p) => p.userId == me);
    if (index < 0) {
      if (me != null) context.push('/player/$me');
      return;
    }
    if (_meKey.currentContext == null) {
      // Rows are about 57 pt; land near it, then let ensureVisible place it exactly.
      await _scroll.animateTo((30.0 + index * 57).clamp(0, _scroll.position.maxScrollExtent), duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    }
    final ctx = _meKey.currentContext;
    if (ctx != null && ctx.mounted) await Scrollable.ensureVisible(ctx, alignment: 0.4, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final board = ref.watch(leaderboardProvider);
    final me = ref.watch(currentUserIdProvider);
    final place = ref.watch(leaderboardRankProvider).value;
    final myProfile = ref.watch(profileProvider).value;
    final showBar = place != null && myProfile != null && !_meOnScreen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkMe();
    });
    return board.when(
      loading: () => const Loader(),
      error: (e, _) => EmptyState(
        icon: AppIcons.signal,
        title: 'Leaderboard could not load',
        message: 'Check your connection and try again.',
        action: BigButton(
          label: 'Try again',
          kind: ButtonKind.secondary,
          height: 44,
          expand: false,
          onTap: () {
            ref.invalidate(leaderboardProvider);
            ref.invalidate(leaderboardRankProvider);
          },
        ),
      ),
      data: (paged) {
        final list = paged.items;
        if (list.isEmpty) return const EmptyState(icon: AppIcons.trophy, title: 'The leaderboard is empty', message: 'Solve a puzzle to earn XP and take the first place.');
        final listView = RefreshIndicator.adaptive(
          onRefresh: () async {
            ref.invalidate(leaderboardProvider);
            ref.invalidate(leaderboardRankProvider);
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (_) {
              // After the frame: rows that scroll in are built during layout.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _checkMe();
              });
              return false;
            },
            child: ListView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            // Room for the pinned bar, so the last rows can scroll above it.
            padding: EdgeInsets.fromLTRB(20, 0, 20, GlassTabBar.scrollEndPadding(context) + (place != null ? 72 : 0)),
            itemCount: list.length + 1 + (paged.hasMore ? 1 : 0),
            itemBuilder: (_, i) {
              // Next page when the list nears its end (infinite scroll).
              if (paged.hasMore && i >= list.length - 10) {
                WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(leaderboardProvider.notifier).loadMore());
              }
              if (i == list.length + 1) {
                return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CupertinoActivityIndicator()));
              }
              if (i == 0) {
                // One quiet line instead of a card that repeats the tab's name; the player's own
                // place is the pinned bar at the bottom.
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                  child: Text(
                    place != null ? '${formatCount(place.total)} players · ranked by total XP' : 'Ranked by total XP. Solve a puzzle to join.',
                    style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote),
                  ),
                );
              }
              final p = list[i - 1];
              final rank = leaguePlace(list, i - 1);
              final isMe = p.userId == me;
              // One grouped list (iOS inset style): rounded ends, hairlines between rows.
              final first = i == 1, last = i == list.length;
              return Pressable(
                key: isMe ? _meKey : null,
                scale: 0.99,
                onTap: () => context.push('/player/${p.userId}'),
                child: Container(
                  decoration: BoxDecoration(
                    color: isMe ? c.accentTint : c.card,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(first ? Radii.lg : 0), bottom: Radius.circular(last ? Radii.lg : 0)),
                  ),
                  child: Column(
                    children: [
                      _PlayerRow(rank: rank, profile: p, me: isMe),
                      if (!last) Divider(height: 1, thickness: 1, indent: 96, color: c.stroke),
                    ],
                  ),
                ),
              );
            },
          ),
          ),
        );
        return Stack(
          children: [
            listView,
            Positioned(
              left: 20,
              right: 20,
              bottom: GlassTabBar.scrollEndPadding(context, margin: 0),
              child: IgnorePointer(
                ignoring: !showBar,
                child: AnimatedSlide(
                  offset: showBar ? Offset.zero : const Offset(0, 0.3),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: showBar ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: myProfile == null || place == null
                        ? const SizedBox.shrink()
                        : _MyPlaceBar(profile: myProfile, rank: place.rank, total: place.total, onTap: () => _showMe(list, me)),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The player's own league row, pinned above the tab bar while their row is off screen: place,
/// avatar, name and XP, so "where am I" never needs a scroll through the whole league.
class _MyPlaceBar extends StatelessWidget {
  const _MyPlaceBar({required this.profile, required this.rank, required this.total, required this.onTap});
  final Profile profile;
  final int rank;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.lg),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? 0.4 : 0.08), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: GlassSurface(
          opacity: context.isDark ? 0.8 : 0.88,
          borderRadius: BorderRadius.circular(Radii.lg),
          hairline: Border.all(color: context.accent.withValues(alpha: 0.55)),
          child: _PlayerRow(rank: rank, profile: profile, me: true),
        ),
      ),
    );
  }
}

class _Friends extends ConsumerStatefulWidget {
  const _Friends({required this.onAdd});
  final VoidCallback onAdd;
  @override
  ConsumerState<_Friends> createState() => _FriendsState();
}

class _FriendsState extends ConsumerState<_Friends> {
  /// Rows swiped away and confirmed; hidden at once while the delete runs.
  final _removed = <String>{};

  Future<void> _remove(Friend f) async {
    setState(() => _removed.add(f.id));
    try {
      await ref.read(socialRepositoryProvider).removeFriend(f.id);
    } catch (_) {
      if (mounted) {
        setState(() => _removed.remove(f.id));
        showToast(context, 'Could not remove friend. Check your connection and try again.', icon: AppIcons.signal);
      }
      return;
    }
    ref.invalidate(friendsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final onAdd = widget.onAdd;
    final c = context.colors;
    final friends = ref.watch(friendsProvider);
    final me = ref.watch(currentUserIdProvider);
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 0, 20, GlassTabBar.scrollEndPadding(context)),
      children: [
        // Invite: the link opens the game with this player's code filled in (Social > Friends >
        // Add friend by code), in the app where it is installed and on the web elsewhere.
        SoftCard(
          padding: Insets.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Invite friends', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Friends who open your link can add you in one tap.', style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: BigButton(
                      key: const ValueKey('copy-invite'),
                      label: 'Copy link',
                      kind: ButtonKind.secondary,
                      height: 44,
                      onTap: me == null
                          ? null
                          : () {
                              Clipboard.setData(ClipboardData(text: '${AppLink.webOrigin}/add-friend?code=${Uri.encodeQueryComponent(me)}'));
                              showToast(context, 'Copied your invite link', icon: AppIcons.copy);
                            },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: BigButton(key: const ValueKey('add-friend-open'), label: 'Add friend', kind: ButtonKind.secondary, height: 44, onTap: onAdd)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        friends.when(
          loading: () => const Padding(padding: EdgeInsets.all(30), child: Loader()),
          error: (e, _) => EmptyState(
            icon: AppIcons.signal,
            title: 'Friends could not load',
            message: 'Check your connection and try again.',
            action: BigButton(label: 'Try again', kind: ButtonKind.secondary, height: 44, expand: false, onTap: () => ref.invalidate(friendsProvider)),
          ),
          data: (list) => list.isEmpty
              ? const EmptyState(icon: AppIcons.wave, title: 'No friends yet', message: 'Send your invite link, or add a friend by their code, to compare stars.')
              : SoftCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (i, f) in list.where((f) => !_removed.contains(f.id)).indexed) ...[
                        if (i > 0) Divider(height: 1, thickness: 1, indent: 58, color: c.stroke),
                        Dismissible(
                            key: ValueKey(f.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: c.danger,
                              child: const Icon(AppIcons.trash, color: Colors.white),
                            ),
                            confirmDismiss: (_) => showAppAlert(
                              context,
                              title: 'Remove friend?',
                              message: '${f.name} will leave your friends list. You can add them again with their code.',
                              confirmLabel: 'Remove',
                              destructive: true,
                            ),
                            onDismissed: (_) => _remove(f),
                            child: _FriendRow(friend: f),
                          ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _FriendRow extends ConsumerWidget {
  const _FriendRow({required this.friend});
  final Friend friend;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return FutureBuilder<Profile?>(
      future: ref.read(profileRepositoryProvider).findByUserId(friend.friendId),
      builder: (_, snap) {
        final p = snap.data;
        return Pressable(
          scale: 0.99,
          onTap: () => context.push('/player/${friend.friendId}'),
          child: Container(
            color: c.card,
            padding: const EdgeInsets.fromLTRB(12, 9, 16, 9),
            child: Row(
              children: [
                AvatarCircle(avatarKey: p?.avatar ?? friend.avatar, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PlayerName(name: p?.displayName ?? friend.name),
                      const SizedBox(height: 1),
                      if (p == null) Text('Loading…', style: TextStyle(fontSize: TypeSize.caption, color: c.textSecondary)) else _SubStats(solved: p.puzzlesCompleted, stars: p.totalStars),
                    ],
                  ),
                ),
                if (p != null) ...[const SizedBox(width: 8), _XpColumn(xp: p.xp, level: p.level)],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A league row: place, avatar, name with solved count and stars, XP and level on the right.
class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.rank, required this.profile, required this.me});
  final int rank;
  final Profile profile;
  final bool me;
  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 16, 9),
      child: Row(
        children: [
          _RankBadge(rank: rank),
          const SizedBox(width: 10),
          AvatarCircle(avatarKey: p.avatar, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PlayerName(name: p.displayName, me: me),
                const SizedBox(height: 1),
                _SubStats(solved: p.puzzlesCompleted, stars: p.totalStars),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _XpColumn(xp: p.xp, level: p.level),
        ],
      ),
    );
  }
}

/// "428 solved · 1,000 [star]": the star is part of the text, so it always sits right after its
/// number and can never be drawn after an ellipsis.
class _SubStats extends StatelessWidget {
  const _SubStats({required this.solved, required this.stars});
  final int solved;
  final int stars;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '${formatCount(solved)} solved · ${formatCount(stars)} '),
        const WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(AppIcons.star, size: 11, color: Brand.star)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: TypeSize.caption, color: c.textSecondary),
    );
  }
}

/// The ranking number on top, the level under it: "60,020 XP" / "Level 44".
class _XpColumn extends StatelessWidget {
  const _XpColumn({required this.xp, required this.level});
  final int xp;
  final int level;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('${formatCount(xp)} XP', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.body, fontFeatures: tabularFigures)),
        const SizedBox(height: 1),
        Text('Level $level', style: TextStyle(fontSize: TypeSize.caption, color: c.textSecondary)),
      ],
    );
  }
}

/// A player's name on one line (long names end in an ellipsis) and, on the player's own row, a
/// small "You" tag that never gets cut.
class _PlayerName extends StatelessWidget {
  const _PlayerName({required this.name, this.me = false});
  final String name;
  final bool me;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.body),
          ),
        ),
        if (me) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.pill),
              border: Border.all(color: context.accent),
            ),
            child: Text(
              'You',
              style: TextStyle(fontSize: TypeSize.micro, fontWeight: FontWeight.w700, color: context.accent),
            ),
          ),
        ],
      ],
    );
  }
}

/// League place in a disc. The top three are tinted with their medal colour and keep a dark number
/// (white on gold and silver was about 2:1); the disc grows into a capsule for three- and four-digit
/// places.
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});
  final int rank;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = context.isDark;
    // (fill, number) per medal; light and dark themes.
    final medal = switch (rank) {
      1 => dark ? (const Color(0x4DE0A200), const Color(0xFFF5C84A)) : (const Color(0x33E0A200), const Color(0xFF7A5600)),
      2 => dark ? (const Color(0x40A3A8B5), const Color(0xFFD5D8E0)) : (const Color(0x40A3A8B5), const Color(0xFF4B505C)),
      3 => dark ? (const Color(0x4DC27C4A), const Color(0xFFE5A577)) : (const Color(0x33C27C4A), const Color(0xFF7D4520)),
      _ => null,
    };
    return Container(
      constraints: const BoxConstraints(minWidth: 28),
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: medal?.$1 ?? c.boardBackground,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: medal == null ? null : Border.all(color: medal.$2.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Text(
        '$rank',
        style: TextStyle(fontWeight: medal != null ? FontWeight.w700 : FontWeight.w600, fontSize: TypeSize.footnote, color: medal?.$2 ?? c.textSecondary, fontFeatures: tabularFigures),
      ),
    );
  }
}
