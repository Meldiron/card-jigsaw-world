import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../home/header_bar.dart';
import 'pack_card.dart';

/// The Library's selected category chip. Other tabs set it before switching
/// to the Library, e.g. Home's "All months" opens it on Daily.
class LibraryFilter extends Notifier<String> {
  static const all = 'All';
  static const daily = 'Daily';

  @override
  String build() => all;

  void select(String filter) => state = filter;
}

final libraryFilterProvider = NotifierProvider<LibraryFilter, String>(LibraryFilter.new);

/// Library: every pack grouped by category chips, plus "My puzzles" entry.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          action: BigButton(label: 'Try again', expand: false, onTap: () => ref.invalidate(packRowsProvider)),
        ),
        data: (list) {
          final hasEvents = list.any((p) => p.hasWindow && !p.isExpired);
          // VIP opens everything, so the "Unlocked" chip only helps everyone else.
          final showUnlocked = profile != null && !profile.isVip;
          final categories = [LibraryFilter.all, if (showUnlocked) 'Unlocked', if (hasEvents) 'Events', LibraryFilter.daily, 'Started', ...{for (final p in list) if (!p.isDaily && !p.hasWindow) p.category}];
          // A chip that is no longer offered (e.g. Events after the last one ended) falls back to All.
          final selected = ref.watch(libraryFilterProvider);
          final filter = categories.contains(selected) ? selected : LibraryFilter.all;
          final inAllOrder = [
            ...list.where((p) => !p.isDaily && !p.hasWindow),
            ...list.where((p) => p.hasWindow && p.isLive),
            ...list.where((p) => p.isDaily),
          ];
          List<Pack> filtered;
          if (filter == LibraryFilter.all) {
            filtered = inAllOrder;
          } else if (filter == 'Unlocked') {
            // Same rule as the pack page: free, current month, bought, live event.
            final profileN = ref.read(profileProvider.notifier);
            filtered = inAllOrder.where(profileN.isUnlocked).toList();
          } else if (filter == 'Events') {
            filtered = [
              ...list.where((p) => p.hasWindow && p.isLive),
              ...list.where((p) => p.hasWindow && p.isUpcoming),
            ];
          } else if (filter == 'Daily') {
            filtered = list.where((p) => p.isDaily).toList();
          } else if (filter == 'Started') {
            final all = ref.watch(allPuzzlesProvider).value ?? const <Puzzle>[];
            final startedPacks = all.where((p) => progress[p.id]?.inProgress == true).map((p) => p.packId).toSet();
            filtered = list.where((p) => startedPacks.contains(p.id)).toList();
          } else {
            filtered = list.where((p) => p.category == filter).toList();
          }
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              const HeaderBar(title: 'Library'),
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
                      final selected = cat == filter;
                      return Pressable(
                        onTap: () => ref.read(libraryFilterProvider.notifier).select(cat),
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
                SliverToBoxAdapter(child: EmptyState(icon: AppIcons.library, title: filter == 'Started' ? 'No puzzles in progress' : (filter == 'Unlocked' ? 'Nothing unlocked yet' : 'Nothing here yet'), message: filter == 'Started' ? 'Boards you leave unfinished show up here. Open a pack to start one.' : (filter == 'Unlocked' ? 'Packs you can play right now show up here.' : 'New packs arrive with events and every month.')))
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.78),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => PackCard(pack: filtered[i], onTap: () => context.go('/library/pack/${filtered[i].id}')),
                      childCount: filtered.length,
                    ),
                  ),
                ),
              SliverToBoxAdapter(child: SizedBox(height: GlassTabBar.scrollEndPadding(context))),
            ],
          );
        },
      ),
    );
  }
}
