import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories.dart';
import '../../models/models.dart';
import '../../state/auth.dart';
import '../../state/social.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../home/header_bar.dart';

/// Social: league leaderboard and friends (add by friend code).
class SocialScreen extends ConsumerStatefulWidget {
  const SocialScreen({super.key});
  @override
  ConsumerState<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends ConsumerState<SocialScreen> {
  int _tab = 0;

  Future<void> _addFriend() async {
    final controller = TextEditingController();
    final c = context.colors;
    final ok = await showAppAlert(
      context,
      title: 'Add friend by code',
      message: 'Paste the code your friend shared. Yours is on the Friends tab.',
      confirmLabel: 'Add friend',
      cancelLabel: 'Not now',
      canConfirm: () => controller.text.trim().isNotEmpty,
      child: CupertinoTextField(
        controller: controller,
        placeholder: 'Friend code',
        autofocus: true,
        autocorrect: false,
        style: TextStyle(fontFamily: 'Menlo', fontSize: 13.5, color: c.textPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.boardBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.stroke),
        ),
      ),
    );
    final code = ok ? controller.text.trim() : null;
    if (code == null || code.isEmpty || !mounted) return;
    final me = ref.read(currentUserIdProvider);
    if (me == null) return;
    if (code == me) {
      showToast(context, 'That is your own code. Share it with a friend instead.', icon: AppIcons.profile);
      return;
    }
    try {
      final friend = await ref.read(profileRepositoryProvider).findByUserId(code);
      if (friend == null) {
        if (mounted) showToast(context, 'No player with that code. Check it and try again.', icon: CupertinoIcons.search);
        return;
      }
      await ref.read(socialRepositoryProvider).addFriend(me, friend);
      ref.invalidate(friendsProvider);
      if (mounted) {
        Haptics.success();
        showToast(context, 'Added ${friend.displayName}', icon: AppIcons.addFriend);
      }
    } catch (e) {
      if (mounted) showToast(context, 'Could not add friend. Check your connection and try again.', icon: AppIcons.signal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: Column(
        children: [
          const HeaderBar(title: 'Social', sliver: false),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Row(
              children: [
                Expanded(child: Text('Social', style: Theme.of(context).textTheme.headlineLarge)),
                CupertinoSlidingSegmentedControl<int>(
                  groupValue: _tab,
                  backgroundColor: c.boardBackground,
                  thumbColor: c.card,
                  children: const {
                    0: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text('League', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    1: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text('Friends', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  },
                  onValueChanged: (v) => setState(() => _tab = v ?? 0),
                ),
              ],
            ),
          ),
          Expanded(child: _tab == 0 ? const _Leaderboard() : _Friends(onAdd: _addFriend)),
        ],
      ),
    );
  }
}

class _Leaderboard extends ConsumerWidget {
  const _Leaderboard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final board = ref.watch(leaderboardProvider);
    final me = ref.watch(currentUserIdProvider);
    return board.when(
      loading: () => const Loader(),
      error: (e, _) => const EmptyState(icon: AppIcons.signal, title: 'League could not load', message: 'Check your connection and pull to refresh.'),
      data: (list) {
        if (list.isEmpty) return const EmptyState(icon: AppIcons.trophy, title: 'The league is empty', message: 'Solve a puzzle to earn XP and take the first place.');
        final myRank = list.indexWhere((p) => p.userId == me);
        return RefreshIndicator.adaptive(
          onRefresh: () async => ref.invalidate(leaderboardProvider),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: EdgeInsets.fromLTRB(20, 0, 20, GlassTabBar.scrollEndPadding(context)),
            itemCount: list.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SoftCard(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const IconTile(icon: AppIcons.trophy, size: 44, radius: 12),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Crystal League', style: Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 2),
                              Text(
                                myRank >= 0 ? 'You are #${myRank + 1} of ${list.length} · Ranked by XP this season' : 'Ranked by XP this season',
                                style: TextStyle(color: c.textSecondary, fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final p = list[i - 1];
              final rank = i;
              final isMe = p.userId == me;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Pressable(
                  onTap: () => context.push('/player/${p.userId}'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isMe ? c.accentTint : c.card,
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(color: isMe ? context.accent : c.stroke),
                    ),
                    child: Row(
                      children: [
                        _RankBadge(rank: rank),
                        const SizedBox(width: 10),
                        AvatarCircle(avatarKey: p.avatar, size: 38),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(isMe ? '${p.displayName} (you)' : p.displayName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                              _SubStats(level: p.level, solved: p.puzzlesCompleted, stars: p.totalStars),
                            ],
                          ),
                        ),
                        Text('${p.xp} XP', style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(width: 6),
                        Icon(CupertinoIcons.chevron_right, size: 14, color: c.textTertiary),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
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
        SoftCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your friend code', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: c.boardBackground, borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        me ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Menlo', fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  RoundIconButton(
                    icon: CupertinoIcons.doc_on_doc,
                    onTap: me == null
                        ? null
                        : () {
                            Clipboard.setData(ClipboardData(text: me));
                            showToast(context, 'Copied your friend code', icon: AppIcons.copy);
                          },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              BigButton(label: 'Add friend by code', icon: AppIcons.addFriend, height: 48, onTap: onAdd),
            ],
          ),
        ),
        const SizedBox(height: 16),
        friends.when(
          loading: () => const Padding(padding: EdgeInsets.all(30), child: Loader()),
          error: (e, _) => const EmptyState(icon: AppIcons.signal, title: 'Friends could not load', message: 'Check your connection and pull to refresh.'),
          data: (list) => list.isEmpty
              ? const EmptyState(icon: AppIcons.wave, title: 'No friends yet', message: 'Share your code, or add a friend by theirs, to compare stars.')
              : Column(
                  children: [
                    for (final f in list.where((f) => !_removed.contains(f.id)))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Dismissible(
                          key: ValueKey(f.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(color: c.danger, borderRadius: BorderRadius.circular(Radii.md)),
                            child: const Icon(CupertinoIcons.trash, color: Colors.white),
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
                      ),
                  ],
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
          onTap: () => context.push('/player/${friend.friendId}'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: c.stroke),
            ),
            child: Row(
              children: [
                AvatarCircle(avatarKey: p?.avatar ?? friend.avatar, size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p?.displayName ?? friend.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      if (p == null) Text('Loading…', style: TextStyle(fontSize: 11.5, color: c.textSecondary)) else _SubStats(level: p.level, solved: p.puzzlesCompleted, stars: p.totalStars),
                    ],
                  ),
                ),
                if (p != null) Text('${p.xp} XP', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Icon(CupertinoIcons.chevron_right, size: 14, color: c.textTertiary),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});
  final int rank;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final medal = switch (rank) {
      1 => const Color(0xFFE0A200),
      2 => const Color(0xFFA3A8B5),
      3 => const Color(0xFFC27C4A),
      _ => null,
    };
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: medal ?? c.boardBackground, shape: BoxShape.circle),
      child: Text(
        '$rank',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: medal != null ? Colors.white : c.textSecondary),
      ),
    );
  }
}

class _SubStats extends StatelessWidget {
  const _SubStats({required this.level, required this.solved, required this.stars});
  final int level;
  final int solved;
  final int stars;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = TextStyle(fontSize: 11.5, color: c.textSecondary);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Level $level · $solved solved · $stars', style: style),
        const SizedBox(width: 3),
        const Icon(AppIcons.star, size: 11, color: Brand.star),
      ],
    );
  }
}
