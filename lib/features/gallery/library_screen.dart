import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/profile.dart';
import '../../state/settings.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../home/header_bar.dart';
import 'pack_card.dart';
import 'pack_progress.dart';

/// The Library's selected chip. Other tabs set it before switching to the
/// Library, e.g. Home's "All months" opens it on Daily and the finished
/// packs row on Finished.
class LibraryFilter extends Notifier<String> {
  static const all = 'All';
  static const finished = 'Finished';
  static const started = 'Started';
  static const unlocked = 'Unlocked';
  static const daily = 'Daily';

  /// Chips that are not pack categories; they carry an icon before the label.
  static const special = {all, finished, started, unlocked};

  @override
  String build() => all;

  void select(String filter) => state = filter;
}

final libraryFilterProvider = NotifierProvider<LibraryFilter, String>(LibraryFilter.new);

/// The chips in order: All, Finished, Started, Unlocked (only useful without
/// VIP, which opens everything), Daily, then the library categories.
List<String> libraryChips(List<Pack> packs, {required bool showUnlocked}) => [
      LibraryFilter.all,
      LibraryFilter.finished,
      LibraryFilter.started,
      if (showUnlocked) LibraryFilter.unlocked,
      LibraryFilter.daily,
      ...{for (final p in packs) if (!p.isDaily && !p.hasWindow) p.category},
    ];

/// Icon for a chip that is not a pack category, null for categories.
IconData? libraryChipIcon(String chip) => switch (chip) {
      LibraryFilter.all => AppIcons.filterAll,
      LibraryFilter.finished => AppIcons.filterFinished,
      LibraryFilter.started => AppIcons.filterStarted,
      LibraryFilter.unlocked => AppIcons.filterUnlocked,
      _ => null,
    };

/// Lower case without accents, apostrophes or hyphens, so "Kraków",
/// "krakow" and "KRAKOW" all match and "world's" finds "worlds".
String foldForSearch(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    b.write(_fold[ch] ?? ch);
  }
  return b.toString();
}

const _fold = <String, String>{
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a', 'æ': 'ae',
  'ç': 'c', 'ć': 'c', 'ĉ': 'c', 'ċ': 'c', 'č': 'c', 'ď': 'd', 'đ': 'd', 'ð': 'd',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ĕ': 'e', 'ė': 'e', 'ę': 'e', 'ě': 'e',
  'ĝ': 'g', 'ğ': 'g', 'ġ': 'g', 'ģ': 'g', 'ĥ': 'h', 'ħ': 'h',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ĩ': 'i', 'ī': 'i', 'į': 'i', 'ı': 'i', 'ĵ': 'j', 'ķ': 'k',
  'ĺ': 'l', 'ļ': 'l', 'ľ': 'l', 'ŀ': 'l', 'ł': 'l', 'ñ': 'n', 'ń': 'n', 'ņ': 'n', 'ň': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ŏ': 'o', 'ő': 'o', 'œ': 'oe',
  'ŕ': 'r', 'ŗ': 'r', 'ř': 'r', 'ś': 's', 'ŝ': 's', 'ş': 's', 'š': 's', 'ș': 's', 'ß': 'ss',
  'ţ': 't', 'ť': 't', 'ț': 't', 'þ': 'th',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ũ': 'u', 'ū': 'u', 'ŭ': 'u', 'ů': 'u', 'ű': 'u', 'ų': 'u',
  'ŵ': 'w', 'ý': 'y', 'ÿ': 'y', 'ŷ': 'y', 'ź': 'z', 'ż': 'z', 'ž': 'z',
  '\'': '', '’': '', '‘': '', '-': ' ', '–': ' ', '—': ' ',
};

/// The packs a Library view shows, in order.
///
/// [filter] picks the chip's packs; [hideFinished] then drops packs whose
/// every picture is solved (never in the Finished view, which would empty
/// it); [query] keeps packs whose name, category or description contain every
/// word of it, ignoring case and accents, with name matches first.
List<Pack> libraryPacks(
  List<Pack> packs, {
  required String filter,
  required Map<String, PackProgress> progress,
  required bool Function(Pack) isUnlocked,
  bool hideFinished = false,
  String query = '',
}) {
  bool finished(Pack p) => progress[p.id]?.complete ?? false;
  final library = packs.where((p) => !p.isDaily && !p.hasWindow);
  final live = packs.where((p) => p.hasWindow && p.isLive);
  final daily = packs.where((p) => p.isDaily);
  final inAllOrder = [...library, ...live, ...daily];

  var out = switch (filter) {
    LibraryFilter.all => inAllOrder,
    // Finished event packs stay here after the event ends: they are the player's.
    LibraryFilter.finished => [...library, ...live, ...packs.where((p) => p.hasWindow && p.isExpired), ...daily].where(finished).toList(),
    // Begun and not finished, or a finished pack with a board left mid-way.
    LibraryFilter.started => inAllOrder.where((p) {
        final pr = progress[p.id];
        return pr != null && pr.started && (!pr.complete || pr.playing > 0);
      }).toList(),
    // Same rule as the pack page: free, current month, bought, live event.
    LibraryFilter.unlocked => inAllOrder.where(isUnlocked).toList(),
    LibraryFilter.daily => daily.toList(),
    _ => packs.where((p) => p.category == filter).toList(),
  };
  if (hideFinished && filter != LibraryFilter.finished) out = out.where((p) => !finished(p)).toList();

  final words = foldForSearch(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return out;
  bool all(String text) => words.every(text.contains);
  final byName = <Pack>[], byText = <Pack>[];
  for (final p in out) {
    if (all(foldForSearch(p.name))) {
      byName.add(p);
    } else if (all(foldForSearch('${p.name} ${p.category} ${p.description}'))) {
      byText.add(p);
    }
  }
  return [...byName, ...byText];
}

/// Library: every pack behind filter chips and a search field, plus the
/// "My Puzzles" entry.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _search.addListener(_onQuery);
  }

  String _query = '';

  void _onQuery() {
    if (_search.text != _query) setState(() => _query = _search.text);
  }

  @override
  void dispose() {
    _search.removeListener(_onQuery);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final packs = ref.watch(packsProvider);

    return Scaffold(
      body: packs.when(
        loading: () => const Loader(),
        error: (e, _) => EmptyState(
          icon: AppIcons.signal,
          title: 'Packs did not load',
          message: 'Check your connection and try again.',
          action: BigButton(label: 'Try again', expand: false, onTap: () => ref.invalidate(packRowsProvider)),
        ),
        data: _library,
      ),
    );
  }

  Widget _library(List<Pack> list) {
    final c = context.colors;
    final profile = ref.watch(profileProvider).value;
    final progress = ref.watch(allPackProgressProvider);
    final hideFinished = ref.watch(settingsProvider.select((s) => s.hideFinished));
    final profileN = ref.read(profileProvider.notifier);
    // VIP opens everything, so the "Unlocked" chip only helps everyone else.
    final chips = libraryChips(list, showUnlocked: profile != null && !profile.isVip);
    // A chip that is no longer offered (e.g. Unlocked after going VIP) falls back to All.
    final selected = ref.watch(libraryFilterProvider);
    final filter = chips.contains(selected) ? selected : LibraryFilter.all;
    final inFinished = filter == LibraryFilter.finished;

    List<Pack> view({String? f, bool? hide, String? q}) => libraryPacks(
          list,
          filter: f ?? filter,
          progress: progress,
          isUnlocked: profileN.isUnlocked,
          hideFinished: hide ?? hideFinished,
          query: q ?? _query,
        );
    final filtered = view();
    final finishedCount = inFinished ? view(q: '').length : 0;
    final searching = _query.trim().isNotEmpty;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        const HeaderBar(title: 'Library'),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Row(
              crossAxisAlignment: inFinished ? CrossAxisAlignment.end : CrossAxisAlignment.center,
              children: [
                Expanded(child: Text('Library', style: Theme.of(context).textTheme.headlineLarge)),
                // In Finished, hiding finished packs would empty the view; the count says more.
                if (inFinished)
                  Text('$finishedCount finished', key: const ValueKey('library-finished-count'), style: TextStyle(color: c.textSecondary, fontSize: 13))
                else
                  _HideFinishedToggle(value: hideFinished, onChanged: ref.read(settingsProvider.notifier).setHideFinished),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: CupertinoSearchTextField(
              key: const ValueKey('library-search'),
              controller: _search,
              focusNode: _searchFocus,
              placeholder: 'Search packs',
              onSubmitted: (_) => _searchFocus.unfocus(),
              style: TextStyle(color: c.textPrimary, fontSize: 16, letterSpacing: -0.2),
              placeholderStyle: TextStyle(color: c.textTertiary, fontSize: 16, letterSpacing: -0.2),
              itemColor: c.textTertiary,
              decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.stroke)),
              padding: const EdgeInsetsDirectional.fromSTEB(6, 9, 6, 9),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 54,
            child: ListView.separated(
              key: const ValueKey('library-chips'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              physics: const BouncingScrollPhysics(),
              itemCount: chips.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _FilterChip(
                key: ValueKey('library-chip-${chips[i]}'),
                label: chips[i],
                icon: libraryChipIcon(chips[i]),
                selected: chips[i] == filter,
                onTap: () => ref.read(libraryFilterProvider.notifier).select(chips[i]),
              ),
            ),
          ),
        ),
        if (!searching)
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
          SliverToBoxAdapter(child: _empty(filter, hideFinished: hideFinished, view: view))
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
  }

  /// Why the view is empty, most specific reason first: the search, the
  /// hide-finished toggle, then the chip itself.
  Widget _empty(String filter, {required bool hideFinished, required List<Pack> Function({String? f, bool? hide, String? q}) view}) {
    final q = _query.trim();
    final showFinished = BigButton(label: 'Show finished', kind: ButtonKind.secondary, expand: false, onTap: () => ref.read(settingsProvider.notifier).setHideFinished(false));
    if (q.isNotEmpty) {
      if (hideFinished && view(hide: false).isNotEmpty) {
        return EmptyState(icon: AppIcons.filterFinished, title: 'Only finished packs match', message: 'Finished packs are hidden. Show them to see what matches "$q".', action: showFinished);
      }
      if (filter != LibraryFilter.all && view(f: LibraryFilter.all).isNotEmpty) {
        return EmptyState(
          icon: CupertinoIcons.search,
          title: 'No packs found',
          message: 'Nothing in $filter matches "$q". Other packs do.',
          action: BigButton(label: 'Search all packs', kind: ButtonKind.secondary, expand: false, onTap: () => ref.read(libraryFilterProvider.notifier).select(LibraryFilter.all)),
        );
      }
      return EmptyState(icon: CupertinoIcons.search, title: 'No packs found', message: 'No pack name or description matches "$q". Try another word.');
    }
    if (hideFinished && view(hide: false).isNotEmpty) {
      return EmptyState(icon: AppIcons.filterFinished, title: 'Every pack here is finished', message: 'Finished packs are hidden. Show them again to replay a picture.', action: showFinished);
    }
    return switch (filter) {
      LibraryFilter.finished => const EmptyState(icon: AppIcons.filterFinished, title: 'No finished packs yet', message: 'A pack lands here once every picture in it is solved. Open a pack you have started to finish it.'),
      LibraryFilter.started => const EmptyState(icon: AppIcons.filterStarted, title: 'Nothing started yet', message: 'Packs you have begun and not finished show up here. Open a pack to start one.'),
      LibraryFilter.unlocked => const EmptyState(icon: AppIcons.filterUnlocked, title: 'Nothing unlocked yet', message: 'Packs you can play right now show up here.'),
      _ => const EmptyState(icon: AppIcons.library, title: 'Nothing here yet', message: 'New packs arrive with events and every month.'),
    };
  }
}

/// A Library chip; the special views (All, Finished, Started, Unlocked) lead
/// with an icon in the label colour, so it reads on the cobalt and the plain chip.
class _FilterChip extends StatelessWidget {
  const _FilterChip({super.key, required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? Colors.white : c.textSecondary;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.only(left: icon == null ? 14 : 11, right: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? context.accent : c.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? context.accent : c.stroke),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 5)],
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// "Hide finished" with a compact native switch; the label toggles it too.
class _HideFinishedToggle extends StatelessWidget {
  const _HideFinishedToggle({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(!value),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('Hide finished', style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ),
          const SizedBox(width: 8),
          // 80% of the system switch: a view option, not a setting.
          SizedBox(
            width: 51 * 0.8,
            height: 31 * 0.8,
            child: FittedBox(
              child: CupertinoSwitch(key: const ValueKey('library-hide-finished'), value: value, activeTrackColor: Brand.success, onChanged: onChanged),
            ),
          ),
        ],
      ),
    );
  }
}
