import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../home/header_bar.dart';
import 'pack_card.dart';

/// Library: every pack grouped by category chips, plus "My puzzles" entry.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final packs = ref.watch(packsProvider);
    final progress = ref.watch(progressProvider).value ?? {};
    final profile = ref.watch(profileProvider).value;

    return Scaffold(
      body: packs.when(
        loading: () => const Loader(),
        error: (e, _) => EmptyState(
          icon: AppIcons.signal,
          title: 'Packs did not load',
          message: 'Check your connection and try again.',
          action: BigButton(label: 'Try again', expand: false, onTap: () => ref.invalidate(packsProvider)),
        ),
        data: (list) {
          final hasEvents = list.any((p) => p.hasWindow && !p.isExpired);
          final categories = ['All', if (hasEvents) 'Events', 'Daily', 'Started', ...{for (final p in list) if (!p.isDaily && !p.hasWindow) p.category}];
          List<Pack> filtered;
          if (_filter == 'All') {
            filtered = [
              ...list.where((p) => !p.isDaily && !p.hasWindow),
              ...list.where((p) => p.hasWindow && p.isLive),
              ...list.where((p) => p.isDaily),
            ];
          } else if (_filter == 'Events') {
            filtered = [
              ...list.where((p) => p.hasWindow && p.isLive),
              ...list.where((p) => p.hasWindow && p.isUpcoming),
            ];
          } else if (_filter == 'Daily') {
            filtered = list.where((p) => p.isDaily).toList();
          } else if (_filter == 'Started') {
            final all = ref.watch(allPuzzlesProvider).value ?? const <Puzzle>[];
            final startedPacks = all.where((p) => progress[p.id]?.inProgress == true).map((p) => p.packId).toSet();
            filtered = list.where((p) => startedPacks.contains(p.id)).toList();
          } else {
            filtered = list.where((p) => p.category == _filter).toList();
          }
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: HeaderBar(title: 'Library')),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: Text('Library', style: Theme.of(context).textTheme.headlineLarge)),
                      Text('${profile?.puzzlesCompleted ?? 0} solved', style: TextStyle(color: c.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 54,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                    physics: const BouncingScrollPhysics(),
                    itemCount: categories.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final cat = categories[i];
                      final selected = cat == _filter;
                      return Pressable(
                        onTap: () => setState(() => _filter = cat),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected ? context.accent : c.card,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: selected ? context.accent : c.stroke),
                          ),
                          child: Text(cat, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: selected ? Colors.white : c.textSecondary)),
                        ),
                      );
                    },
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: SoftCard(
                    padding: EdgeInsets.zero,
                    child: ListRow(
                      icon: AppIcons.photo,
                      title: 'My Puzzles',
                      subtitle: 'Turn your photos into puzzles',
                      onTap: () => context.go('/profile/my-puzzles'),
                    ),
                  ),
                ),
              ),
              if (filtered.isEmpty)
                SliverToBoxAdapter(child: EmptyState(icon: AppIcons.library, title: _filter == 'Started' ? 'No puzzles in progress' : 'Nothing here yet', message: _filter == 'Started' ? 'Boards you leave unfinished show up here. Open a pack to start one.' : 'New packs arrive with events and every month.'))
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.78),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => PackCard(pack: filtered[i], onTap: () => context.go('/library/pack/${filtered[i].id}')),
                      childCount: filtered.length,
                    ),
                  ),
                ),
              SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 12)),
            ],
          );
        },
      ),
    );
  }
}
