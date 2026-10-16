import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/a11y.dart';
import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/giant.dart';
import '../../state/profile.dart';
import '../../state/rewards.dart';
import '../../state/starter_packs.dart';
import '../../state/unlocks.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import 'pack_progress.dart';

/// Pack tile for grids: image-first cover, category chip, lock state,
/// name and progress. The photo carries the colour; chrome stays neutral.
class PackCard extends ConsumerWidget {
  const PackCard({super.key, required this.pack, required this.onTap});
  final Pack pack;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final profile = ref.watch(profileProvider).value;
    if (formerlyFreePacks.contains(pack.id)) ref.watch(playedPacksProvider); // stays open once played
    final unlocked = profile != null && ref.read(profileProvider.notifier).isUnlocked(pack);
    final vip = profile?.isVip ?? false;
    final showLock = !unlocked && !vip && !pack.hasWindow;
    final progress = ref.watch(packProgressProvider(pack.id));
    // A Giant pack before giant boards open says when it opens instead of a price (027): its
    // page offers the early opening.
    final giantClosed = isGiantPack(pack) && !ref.watch(openFeaturesProvider).giant;

    return Pressable(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: c.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(url: pack.coverUrl, blurhash: pack.blurhash),
                  if (!unlocked) Container(color: Colors.black.withValues(alpha: 0.2)),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Chip2(label: pack.category, icon: AppIcons.category(pack.category), onImage: true),
                  ),
                  if (progress.complete && !showLock) Positioned(right: 8, top: 8, child: PackDoneBadges(progress: progress)),
                  if (pack.isNew)
                    const Positioned(
                      left: 8,
                      bottom: 8,
                      child: Chip2(key: ValueKey('pack-new'), label: 'New', onImage: true, dot: Brand.live),
                    ),
                  if (pack.hasWindow && !pack.isExpired)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: pack.isUpcoming
                          ? const Chip2(label: 'Soon', icon: AppIcons.time, onImage: true)
                          : const Chip2(label: 'Live', onImage: true, dot: Brand.live),
                    )
                  else if (pack.hasWindow && pack.isExpired && !unlocked && A11y.symbolsOf(context))
                    // Differentiate without colour: an event that is over says so, not only by darkening.
                    const Positioned(
                      right: 8,
                      bottom: 8,
                      child: Chip2(label: 'Ended', icon: AppIcons.lock, onImage: true),
                    )
                  else if (pack.isSeasonal)
                    const Positioned(
                      right: 8,
                      bottom: 8,
                      child: Chip2(label: 'Limited', icon: AppIcons.time, onImage: true),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pack.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.body, letterSpacing: -0.2)),
                  const SizedBox(height: 6),
                  // A locked pack shows its price where an open one shows its progress (0/24 says
                  // nothing yet), so the photo carries one chip, the category.
                  if (giantClosed)
                    SizedBox(
                      height: 16,
                      child: Row(
                        children: [
                          Icon(AppIcons.lock, size: 12, color: c.textSecondary),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text('Opens at level ${Unlock.giant.level}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    )
                  else if (showLock)
                    SizedBox(
                      height: 16,
                      child: Row(
                        children: [
                          Icon(AppIcons.lock, size: 12, color: c.textSecondary),
                          const SizedBox(width: 6),
                          Amount(
                            currency: pack.priceTickets > 0 ? Currency.tickets : Currency.coins,
                            value: formatCount(pack.priceTickets > 0 ? pack.priceTickets : pack.priceCoins),
                            size: 14,
                            fontSize: TypeSize.footnote,
                            weight: FontWeight.w700,
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(height: 16, child: Center(child: PackProgressLine(progress: progress))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
