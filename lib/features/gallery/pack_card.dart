import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/profile.dart';
import '../../state/progress.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

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
    final unlocked = profile != null && ref.read(profileProvider.notifier).isUnlocked(pack);
    final vip = profile?.isVip ?? false;
    final showLock = !unlocked && !vip && !pack.hasWindow;
    final puzzles = ref.watch(packPuzzlesProvider(pack.id)).value ?? const [];
    final progress = ref.watch(progressProvider).value ?? {};
    final done = puzzles.where((p) => progress[p.id]?.completed == true).length;
    final total = puzzles.isEmpty ? pack.imageCount : puzzles.length;
    final stars = puzzles.fold<int>(0, (s, p) => s + (progress[p.id]?.stars ?? 0));
    final maxStars = total * 3;
    final complete = total > 0 && done >= total;

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
                  if (complete && !showLock)
                    const Positioned(
                      right: 8,
                      top: 8,
                      child: _DoneBadge(),
                    ),
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
                  Row(
                    children: [
                      Expanded(
                        child: complete
                            // Every picture solved: the bar now tracks stars, in the
                            // star colour over a muted solved bar, so only a pack
                            // with all three stars everywhere reads as full.
                            ? ProgressBar(value: maxStars == 0 ? 0 : stars / maxStars, height: 5, color: Brand.star, background: context.accent.withValues(alpha: 0.28))
                            : ProgressBar(value: total == 0 ? 0 : done / total, height: 5),
                      ),
                      const SizedBox(width: 8),
                      if (complete) ...[
                        Text('$done/$total · $stars/$maxStars', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: c.textSecondary)),
                        const SizedBox(width: 2),
                        const Icon(AppIcons.star, size: 10, color: Brand.star),
                      ] else
                        Text('$done/$total', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: c.textSecondary)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Green check shown on the cover once every picture in the pack is solved.
class _DoneBadge extends StatelessWidget {
  const _DoneBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(color: Brand.success, shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.5)),
      child: const Icon(CupertinoIcons.checkmark, size: 14, color: Colors.white),
    );
  }
}
