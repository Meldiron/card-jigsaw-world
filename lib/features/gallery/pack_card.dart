import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/profile.dart';
import '../../state/starter_packs.dart';
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
                  if (showLock)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(999)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(AppIcons.lock, size: 11, color: Colors.white),
                            const SizedBox(width: 5),
                            Amount(
                              currency: pack.priceTickets > 0 ? Currency.tickets : Currency.coins,
                              value: pack.priceTickets > 0 ? pack.priceTickets : pack.priceCoins,
                              size: 12,
                              color: Colors.white,
                              fontSize: 11,
                              weight: FontWeight.w600,
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (pack.isNew)
                    const Positioned(
                      left: 8,
                      bottom: 8,
                      child: Chip2(key: ValueKey('pack-new'), label: 'New', color: Brand.live, foreground: Colors.white),
                    ),
                  if (pack.hasWindow && !pack.isExpired)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: pack.isUpcoming
                          ? const Chip2(label: 'Soon', icon: AppIcons.time, onImage: true)
                          : const Chip2(label: 'Live', color: Brand.live, foreground: Colors.white),
                    )
                  else if (pack.isSeasonal)
                    const Positioned(
                      right: 8,
                      bottom: 8,
                      child: Chip2(label: 'Limited', color: Brand.live, foreground: Colors.white),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pack.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: -0.2)),
                  const SizedBox(height: 6),
                  PackProgressLine(progress: progress),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
