import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../game/board.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/giant.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../state/rewards.dart';
import '../../state/starter_packs.dart';
import '../../state/unlocks.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import 'giant_gate.dart';
import 'pack_progress.dart';

/// Pack detail: image hero, access state, and a grid of puzzles with stars.
/// Daily (monthly) packs render as a calendar; past months need VIP or coins.
class PackScreen extends ConsumerWidget {
  const PackScreen({super.key, required this.packId});
  final String packId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final packsAsync = ref.watch(packsProvider);
    final packs = packsAsync.value ?? const [];
    final pack = packs.where((p) => p.id == packId).firstOrNull;
    if (pack == null) {
      // A link to a pack the catalogue does not list (removed, an event not announced yet, or a
      // pack that opens with a pack code) says so instead of loading forever.
      final missing = packsAsync.hasValue && !packsAsync.isLoading;
      // The catalogue could not be read (offline on a first launch, or a link opened offline).
      final failed = packsAsync.hasError && !packsAsync.hasValue && !packsAsync.isLoading;
      return Scaffold(
        appBar: AppBar(
          leading: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: RoundIconButton(icon: AppIcons.back, size: 38, onTap: () => context.canPop() ? context.pop() : context.go('/library')),
          ),
        ),
        body: failed
            ? EmptyState(
                icon: AppIcons.signal,
                title: 'Packs did not load',
                message: 'Check your connection and try again.',
                action: BigButton(label: 'Try again', expand: false, onTap: () => ref.invalidate(catalogProvider)),
              )
            : missing
                ? const EmptyState(
                    key: ValueKey('pack-not-available'),
                    icon: AppIcons.library,
                    title: 'Pack not available',
                    message: 'The link may be out of date. A pack from a pack code shows here once the code is redeemed.',
                  )
                : const _PackSkeleton(),
      );
    }
    final puzzles = ref.watch(packPuzzlesProvider(packId));
    final progress = ref.watch(progressProvider).value ?? {};
    final profileN = ref.read(profileProvider.notifier);
    final profile = ref.watch(profileProvider).value;
    if (formerlyFreePacks.contains(pack.id)) ref.watch(playedPacksProvider); // stays open once played
    final unlocked = profile != null && profileN.isUnlocked(pack);
    final list = puzzles.value ?? const <Puzzle>[];
    final packProgress = ref.watch(packProgressProvider(packId));
    final available = list.where((p) => !p.isLockedByDate).length;
    final priceCurrency = pack.priceTickets > 0 ? Currency.tickets : Currency.coins;
    final priceValue = pack.priceTickets > 0 ? pack.priceTickets : pack.priceCoins;
    final balance = priceCurrency == Currency.tickets ? (profile?.tickets ?? 0) : (profile?.coins ?? 0);
    // A Giant pack plays only on giant boards, which open at a level: before it,
    // the pack is not sold (nothing in it could be played yet).
    final giantClosed = isGiantPack(pack) && !ref.watch(openFeaturesProvider).giant;

    Future<void> unlock() async {
      // 166: units in sentence case ("This costs 3,300 coins").
      final amount = countOf(priceValue, priceCurrency == Currency.tickets ? 'ticket' : 'coin');
      if (balance >= priceValue) {
        final sure = await showAppAlert(
          context,
          title: 'Unlock ${pack.name}?',
          message: 'This costs $amount. You have ${formatCount(balance)}.',
          confirmLabel: 'Pay $amount',
        );
        if (!sure || !context.mounted) return;
      }
      final ok = await profileN.unlockPack(pack);
      if (!context.mounted) return;
      if (ok) {
        Haptics.success();
        Sfx.instance.coin();
        showToast(context, '${pack.name} unlocked', icon: AppIcons.check);
      } else {
        Sfx.instance.error();
        final needTickets = pack.priceTickets > 0;
        showToast(
          context,
          needTickets ? 'Not enough tickets. Finish weekly quests or level up to earn more.' : 'Not enough coins. Play more puzzles or visit the store.',
          leading: needTickets ? const TicketIcon(size: 20) : const CoinIcon(size: 20),
        );
        context.push('/store');
      }
    }

    void goVip() => context.push('/store');
    void getMore() => context.push('/store');
    // The website layout: the cover runs across the window, its name and the back button line up
    // with the content column under it.
    final wide = context.isExpanded;
    final inset = pageInsetOf(context);
    final Widget? access = giantClosed
        ? GiantGateCard(gate: GiantGate.of(ref, pack), onOpenNow: () => openGiantEarly(context, ref, pack)).animate().fadeIn().slideY(begin: 0.1)
        : !unlocked
            ? _accessCard(context, pack, priceCurrency, priceValue, balance, goVip, unlock, getMore).animate().fadeIn().slideY(begin: 0.1)
            : null;
    final Widget details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A locked pack leads with the way in; the description and stats follow.
        if (access != null && !wide) ...[
          access,
          const SizedBox(height: 16),
        ],
        Text(pack.description, style: TextStyle(color: c.textSecondary, fontSize: TypeSize.body, height: 1.4)),
        const SizedBox(height: 14),
        // One progress line instead of three boxed numbers: solved and stars,
        // one bar. It reads like the progress line on the pack cards.
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('${packProgress.solved}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.headline, letterSpacing: -0.3)),
            Text(' of ${packProgress.total} solved', style: TextStyle(color: c.textSecondary, fontSize: TypeSize.body, fontWeight: FontWeight.w500)),
            const Spacer(),
            const Icon(AppIcons.star, size: 14, color: Brand.star),
            const SizedBox(width: 4),
            Text('${packProgress.stars}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.body)),
            Text(' of ${packProgress.maxStars}', style: TextStyle(color: c.textSecondary, fontSize: TypeSize.body, fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 8),
        ProgressBar(value: packProgress.complete ? packProgress.starRatio : packProgress.solvedRatio, height: 6, color: packProgress.complete ? Brand.star : null),
        if (unlocked && !giantClosed) ...[
          const SizedBox(height: 16),
          if (isGiantPack(pack))
            // A Giant pack says what kind of board waits behind every picture.
            Row(
              children: [
                Icon(AppIcons.bigBoard, color: context.accent, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text('Boards of 100 to 300 cards · pinch to zoom', style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w500))),
              ],
            )
          else if (pack.isDaily && list.any((p) => p.isToday))
            // The current month leads with today's picture, the reason to open it.
            Builder(builder: (context) {
              final today = list.firstWhere((p) => p.isToday);
              final pr = progress[today.id];
              return _TodayCard(
                puzzle: today,
                progress: pr,
                onTap: () => pr != null && pr.inProgress ? context.push('/game/${today.id}/${_gridCodeFor(pr)}') : context.push('/play/${today.id}'),
              );
            })
          else
          Row(
            children: [
              Icon(packProgress.perfect ? AppIcons.star : AppIcons.check, color: packProgress.perfect ? Brand.star : c.success, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  packProgress.perfect
                      ? 'Finished with every star · replay any picture'
                      : packProgress.complete
                          ? 'Finished · replay a picture for more stars'
                          : pack.isDaily && available < list.length
                              ? '$available of ${list.length} days open · a new picture every day'
                              : 'Unlocked · tap any picture to play',
                  style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ],
      ],
    );

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            // About a third of the screen: 280 on a Pro, 220 on an SE (where 280 took 42%
            // and pushed a locked pack's button under the tab bar), at most 300.
            expandedHeight: (MediaQuery.sizeOf(context).height * 0.32).clamp(220.0, 300.0),
            pinned: true,
            stretch: true,
            backgroundColor: Colors.transparent,
            scrolledUnderElevation: 0,
            leadingWidth: inset > 0 ? inset + kToolbarHeight : null,
            leading: Padding(
              padding: EdgeInsets.only(left: inset + 12),
              child: _HeroBackButton(onTap: () => context.pop()),
            ),
            title: _CollapsedTitle(
              pack.name,
              subtitle: giantClosed ? 'Opens at level ${Unlock.giant.level}' : !unlocked ? 'Locked' : (packProgress.complete ? 'Finished · ${packProgress.stars} of ${packProgress.maxStars} stars' : '${packProgress.solved} of ${packProgress.total} solved'),
            ),
            flexibleSpace: _CollapsedGlass(
              child: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(url: pack.coverUrl, blurhash: pack.blurhash),
                  DecoratedBox(decoration: BoxDecoration(gradient: Brand.scrim(strength: 0.7))),
                  // A soft shade under the status bar and the back button, so the white
                  // status bar text reads on bright covers (sky, snow, a white plate).
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: MediaQuery.paddingOf(context).top + kToolbarHeight + 24,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black.withValues(alpha: 0.36), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: inset + 20,
                    right: inset + 20,
                    bottom: 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Chip2(label: pack.category, icon: AppIcons.category(pack.category), onImage: true),
                            if (pack.hasWindow && !pack.isExpired) ...[
                              const SizedBox(width: 6),
                              Chip2(
                                label: pack.isUpcoming ? 'Opens in ${formatTimeLeft(pack.startAt!.difference(DateTime.now()))}' : endsIn(pack.endAt!.difference(DateTime.now())),
                                icon: pack.isUpcoming ? AppIcons.time : null,
                                onImage: true,
                                dot: pack.isUpcoming ? null : Brand.live,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(pack.name, style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ),
          ),
          SliverPage(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: wide && access != null
                      // A desktop puts the way in beside what the pack is.
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 7, child: details),
                            const SizedBox(width: 24),
                            Expanded(flex: 5, child: access),
                          ],
                        )
                      : wide
                          ? Align(alignment: Alignment.centerLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: PageWidth.reading), child: details))
                          : details,
                ),
              ),
              puzzles.when(
                // 169: the grid's shape while the pictures load (023's photo tiles).
                loading: () => SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  sliver: SliverGrid(
                    gridDelegate: _gridShape(pack),
                    delegate: SliverChildBuilderDelegate((_, _) => const Skeleton(radius: Radii.md), childCount: pack.isDaily ? 8 : 9),
                  ),
                ),
                error: (e, _) => SliverToBoxAdapter(
                  child: EmptyState(
                    icon: AppIcons.signal,
                    title: 'Pictures did not load',
                    message: 'Check your connection and try again.',
                    action: BigButton(label: 'Try again', expand: false, onTap: () => ref.invalidate(catalogProvider)),
                  ),
                ),
                data: (list) => SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, GlassTabBar.scrollEndPadding(context)),
                  sliver: SliverGrid(
                    gridDelegate: _gridShape(pack),
                    delegate: SliverChildBuilderDelegate((_, i) {
                      final p = list[i];
                      final pr = progress[p.id];
                      return _PuzzleTile(
                        puzzle: p,
                        progress: pr,
                        locked: !unlocked || giantClosed,
                        dateLocked: p.isLockedByDate,
                        daily: pack.isDaily,
                        onTap: () {
                          if (p.isLockedByDate) {
                            Haptics.medium();
                            showToast(context, 'Opens on ${formatDate(p.date!, year: false)}. Today\'s puzzle is ready now.', icon: AppIcons.lock);
                            return;
                          }
                          if (giantClosed) {
                            Haptics.medium();
                            showGiantGateSheet(context, ref, pack);
                            return;
                          }
                          if (!unlocked) {
                            Haptics.medium();
                            _showAccessSheet(context, pack, priceCurrency, priceValue, balance, goVip, unlock, getMore);
                            return;
                          }
                          if (pr != null && pr.inProgress) {
                            context.push('/game/${p.id}/${_gridCodeFor(pr)}');
                          } else {
                            context.push('/play/${p.id}');
                          }
                        },
                      );
                    }, childCount: list.length),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Builds the single access card used for every locked state.
  static Widget _accessCard(BuildContext context, Pack pack, Currency currency, int price, int balance, VoidCallback onVip, VoidCallback onUnlock, VoidCallback onGetMore, {VoidCallback? onClose}) {
    void wrap(VoidCallback f) {
      onClose?.call();
      f();
    }

    if (pack.hasWindow && pack.isUpcoming) {
      return _AccessCard(
        icon: AppIcons.time,
        title: 'Opens soon',
        reason: 'Opens in ${formatTimeLeft(pack.startAt!.difference(DateTime.now()))}.',
        ghost: ('Back to events', () => wrap(() => context.go('/events'))),
      );
    }
    if (pack.hasWindow && pack.isExpired) {
      return _AccessCard(
        icon: AppIcons.balloon,
        title: 'Event ended',
        reason: 'This pack was part of a past event.',
        ghost: ('Browse events', () => wrap(() => context.go('/events'))),
      );
    }
    if (pack.isDaily) {
      return _AccessCard(
        icon: AppIcons.lock,
        title: 'Past month',
        reason: 'Past months are included with VIP or can be unlocked once.',
        primary: ('Go VIP', AppIcons.vip, null, () => wrap(onVip)),
        secondary: ('Unlock for', null, (currency, price), () => wrap(onUnlock)),
      );
    }
    final tickets = currency == Currency.tickets;
    if (balance < price) {
      // Short of the price: say how far off the player is and lead to where the
      // currency comes from, instead of a button that can only fail.
      final missing = price - balance;
      return _AccessCard(
        icon: AppIcons.lock,
        title: 'Locked pack',
        reason: '${formatCount(missing)} more ${tickets ? 'tickets' : 'coins'} needed, or play every pack with VIP.',
        meter: (currency, balance, price),
        primary: (tickets ? 'Get tickets' : 'Get coins', null, null, () => wrap(onGetMore)),
        secondary: ('Go VIP', AppIcons.vip, null, () => wrap(onVip)),
      );
    }
    return _AccessCard(
      icon: AppIcons.lock,
      title: 'Locked pack',
      reason: 'Unlock once to play every picture.',
      primary: ('Unlock for', null, (currency, price), () => wrap(onUnlock)),
      secondary: ('Go VIP', AppIcons.vip, null, () => wrap(onVip)),
    );
  }

  static void _showAccessSheet(BuildContext context, Pack pack, Currency currency, int price, int balance, VoidCallback onVip, VoidCallback onUnlock, VoidCallback onGetMore) {
    showAppSheet(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetHeader(title: pack.name),
            const SizedBox(height: 12),
            _accessCard(ctx, pack, currency, price, balance, onVip, onUnlock, onGetMore, onClose: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    );
  }

  /// The picture grid: a month is a four-column calendar of nearly square days, other packs three
  /// columns of 3:4 photos. Tiles carry no caption (023), so the photos get the whole cell.
  /// On a wider window the grid takes as many columns as fit.
  static SliverGridDelegate _gridShape(Pack pack) => AdaptiveGridDelegate(
        compact: pack.isDaily ? 4 : 3,
        target: pack.isDaily ? 140 : 180,
        mainAxisSpacing: pack.isDaily ? 8 : 10,
        crossAxisSpacing: pack.isDaily ? 8 : 10,
        childAspectRatio: pack.isDaily ? 0.82 : 0.75,
      );

  /// Route path for resuming a saved board (mode + ladder entry by cell count).
  static String _gridCodeFor(PuzzleProgress pr) {
    final mode = GameMode.fromCode(pr.mode);
    return BoardCode.toPath(BoardSpec.fromCells(mode, pr.gridSize).fullCode);
  }
}

/// The pack's name in the bar: it fades in while the cover's last quarter
/// scrolls away (when the big name on the photo has gone under the bar), so
/// the page never loses its title, the same hand-over as an iOS large title.
class _CollapsedTitle extends StatelessWidget {
  const _CollapsedTitle(this.text, {this.subtitle});
  final String text;

  /// Where the player is in the pack ("3 of 24 solved", "Locked"), under the name.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final bar = context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final range = bar == null ? 0.0 : bar.maxExtent - bar.minExtent;
    final open = bar == null || range <= 0 ? 0.0 : ((bar.currentExtent - bar.minExtent) / range).clamp(0.0, 1.0);
    return Opacity(
      opacity: (1 - open / 0.2).clamp(0.0, 1.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
          if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w500, color: context.colors.textSecondary)),
        ],
      ),
    );
  }
}

/// Once the cover has collapsed into a plain bar it becomes glass, with the
/// top of the picture blurred behind the title. While the cover shows under
/// the status bar, the status bar text is white (it sits on the photo); on the
/// collapsed glass bar it follows the theme again.
class _CollapsedGlass extends StatelessWidget {
  const _CollapsedGlass({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, cons) {
        final collapsed = cons.maxHeight <= MediaQuery.paddingOf(context).top + kToolbarHeight + 1;
        final lightText = !collapsed || context.isDark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (lightText ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(statusBarColor: Colors.transparent),
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              GlassSurface(visible: collapsed, hairline: Border(bottom: BorderSide(color: c.stroke, width: 0.5)), child: const SizedBox.expand()),
            ],
          ),
        );
      },
    );
  }
}

/// The back button of the pack cover: the shared [PhotoButton] (frosted dark
/// glass, white chevron) while it sits on the photo, the plain round button
/// once the cover has collapsed into the glass bar.
class _HeroBackButton extends StatelessWidget {
  const _HeroBackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bar = context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final onPhoto = bar == null || bar.currentExtent > bar.minExtent + 1;
    return Center(
      child: PhotoButton(icon: AppIcons.back, size: 38, semanticLabel: 'Back', onPhoto: onPhoto, onTap: onTap),
    );
  }
}

/// The one access card used for every locked state: icon, title, reason,
/// and up to two actions. Keeps locked packs, past months and event packs
/// visually identical. An action with a cost is a [BigButton.cost]
/// ("Unlock for [ticket] 10"): no leading icon, the price says it all.
class _AccessCard extends StatelessWidget {
  const _AccessCard({required this.icon, required this.title, required this.reason, this.meter, this.primary, this.secondary, this.ghost});
  final IconData icon;
  final String title;
  final String reason;

  /// Balance against the price ("[coin] 1,240 of 3,300" and a bar), when the player is short.
  final (Currency, int, int)? meter;
  final (String, IconData?, (Currency, int)?, VoidCallback)? primary;
  final (String, IconData?, (Currency, int)?, VoidCallback)? secondary;
  final (String, VoidCallback)? ghost;

  static Widget _action((String, IconData?, (Currency, int)?, VoidCallback) a, ButtonKind kind) {
    final (label, icon, cost, onTap) = a;
    if (cost == null) return BigButton(label: label, icon: icon, kind: kind, onTap: onTap);
    return BigButton.cost(label: label, currency: cost.$1, amount: cost.$2, kind: kind, onTap: onTap);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(icon: icon, size: IconTile.medium),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.body, letterSpacing: -0.2)),
                    const SizedBox(height: 2),
                    Text(reason, style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote, height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
          if (meter != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                CostLabel(label: 'Unlock for', currency: meter!.$1, amount: meter!.$3, fontSize: TypeSize.body),
                const Spacer(),
                Text('You have ${formatCount(meter!.$2)}', style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote, fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 8),
            ProgressBar(value: meter!.$3 == 0 ? 0 : (meter!.$2 / meter!.$3).clamp(0.0, 1.0), height: 6, color: meter!.$1 == Currency.tickets ? Brand.ticket : Brand.coin),
          ],
          if (primary != null) ...[
            const SizedBox(height: 14),
            _action(primary!, ButtonKind.primary),
          ],
          if (secondary != null) ...[
            const SizedBox(height: 8),
            _action(secondary!, ButtonKind.secondary),
          ],
          if (ghost != null) ...[
            const SizedBox(height: 14),
            BigButton(label: ghost!.$1, kind: ButtonKind.ghost, onTap: ghost!.$2),
          ],
        ],
      ),
    );
  }
}

/// Today's picture of the current month: thumbnail, date, title and the one
/// action (Play, Continue, or its stars once solved).
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.puzzle, required this.progress, required this.onTap});
  final Puzzle puzzle;
  final PuzzleProgress? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final solved = progress?.completed == true;
    final playing = progress?.inProgress == true;
    final d = puzzle.date!;
    return SoftCard(
      onTap: onTap,
      padding: Insets.cardCompact,
      child: Row(
        children: [
          NetImage(url: puzzle.thumbUrl, blurhash: puzzle.blurhash, width: 56, height: 56, radius: Radii.sm + 2),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Today · ${formatDate(d, year: false)}', style: TextStyle(color: context.accent, fontSize: TypeSize.footnote, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(puzzle.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: TypeSize.callout, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (solved)
            Stars(count: progress!.stars, size: 16)
          else
            BigButton(label: playing ? 'Continue' : 'Play', expand: false, height: 38, onTap: onTap),
        ],
      ),
    );
  }
}

/// A picture of a pack grid: the photo and its state, no words (owner, 023 C: "no need for author
/// or photo name in this view"). A month reads as a calendar of photos with the day as the label;
/// every grid shows the same states: the lock, the day to come, a board in progress (its share
/// of locked cards as a bar along the bottom edge, as on a video thumbnail), and the stars of a
/// solved picture. The title is read out by VoiceOver and shown where the picture is played,
/// with its credit (difficulty screen).
class _PuzzleTile extends StatelessWidget {
  const _PuzzleTile({required this.puzzle, required this.progress, required this.locked, required this.onTap, this.dateLocked = false, this.daily = false});
  final Puzzle puzzle;
  final PuzzleProgress? progress;
  final bool locked;
  final bool dateLocked;
  final bool daily;
  final VoidCallback onTap;

  /// Share of the cards in place on a board in progress (0 before the first card locks).
  static double placedShare(List<int> layout) {
    if (layout.isEmpty) return 0;
    var placed = 0;
    for (var i = 0; i < layout.length; i++) {
      if (layout[i] == i) placed++;
    }
    return placed / layout.length;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final completed = progress?.completed == true;
    final started = progress?.inProgress == true;
    final state = [
      if (dateLocked) 'opens on ${formatDate(puzzle.date!, year: false)}' else if (locked) 'locked',
      if (started) 'in progress',
      if (completed) 'solved, ${countOf(progress!.stars, 'star')}',
    ].join(', ');
    return Semantics(
      button: true,
      // A day to come keeps its title secret, as on screen.
      label: [if (daily && puzzle.date != null) formatDate(puzzle.date!, year: false), if (!dateLocked) puzzle.title, if (state.isNotEmpty) state].join(', '),
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: c.stroke),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // A day still to come is a plain calendar cell: its date, nothing to tap into.
              if (dateLocked)
                Container(
                  color: c.boardBackground,
                  alignment: Alignment.center,
                  child: Text('${puzzle.date!.day}', style: TextStyle(color: c.textTertiary, fontSize: TypeSize.headline, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
                )
              else
                NetImage(url: puzzle.thumbUrl, blurhash: puzzle.blurhash),
              if (locked && !dateLocked)
                Container(color: Colors.black.withValues(alpha: 0.4), child: const Icon(AppIcons.lock, color: Colors.white, size: 18)),
              if (daily && puzzle.date != null && !dateLocked)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      // Today is marked in the accent only (badge and outline agree).
                      color: puzzle.isToday ? context.accentFill : Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Text('${puzzle.date!.day}', style: const TextStyle(color: Colors.white, fontSize: TypeSize.micro, fontWeight: FontWeight.w600)),
                  ),
                ),
              // A board in progress: how far it got, along the bottom edge.
              if (started && !locked)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 4,
                    color: Colors.black.withValues(alpha: 0.45),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: placedShare(progress!.layout!).clamp(0.06, 1.0),
                      child: Container(color: context.accentFill),
                    ),
                  ),
                ),
              if (started && !locked)
                Positioned(
                  left: 6,
                  bottom: 10,
                  child: PhotoChip(child: Icon(AppIcons.playFill, size: 11, color: Colors.white)),
                )
              else if (completed)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(Radii.pill)),
                    child: Stars(count: progress!.stars, size: 10),
                  ),
                ),
              // Today's outline sits just inside the clip so its corners follow
              // the tile's radius exactly instead of being shaved by the clip.
              if (puzzle.isToday)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.all(1),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Radii.md - 1),
                          border: Border.all(color: context.accent, width: 2),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pack page while the catalogue loads (a link opened on a slow connection): cover, name and
/// pictures to come, under the back button.
class _PackSkeleton extends StatelessWidget {
  const _PackSkeleton();
  @override
  Widget build(BuildContext context) => PageColumn(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          physics: const NeverScrollableScrollPhysics(),
          children: [
            const Skeleton(height: 180, radius: Radii.lg),
            const SizedBox(height: 20),
            const Skeleton(width: 180, height: 28, radius: Radii.sm),
            const SizedBox(height: 12),
            const Skeleton(height: 14),
            const SizedBox(height: 8),
            const Skeleton(width: 240, height: 14),
            const SizedBox(height: 24),
            GridView(
              gridDelegate: const AdaptiveGridDelegate(compact: 3, target: 180, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.75),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [for (var i = 0; i < (context.isWide ? 12 : 9); i++) const Skeleton(radius: Radii.md)],
            ),
          ],
        ),
      );
}
