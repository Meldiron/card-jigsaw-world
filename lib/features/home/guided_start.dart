import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/a11y.dart';
import '../../core/haptics.dart';
import '../../core/theme/tokens.dart';
import '../../state/first_steps.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// The guided start on screen (lib/state/first_steps.dart, docs/first-steps.md): the next step on
/// Home, the blurred look at what is still to come with "Unlock
/// anyway", locked sections and tabs that say when they open, and one-time tips.

/// Home's one suggestion: the next small thing worth doing, with its picture. With [heroHeight]
/// it takes the top of Home as a large picture (while the daily puzzle is not open yet).
class NextStepCard extends ConsumerWidget {
  const NextStepCard({super.key, this.heroHeight});
  final double? heroHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = ref.watch(nextStepProvider);
    if (step == null) return const SizedBox.shrink();
    final c = context.colors;
    final puzzle = step.puzzle;
    void open() {
      Haptics.light();
      if (step.route == '/library') {
        context.go('/library');
      } else {
        context.push(step.route);
      }
    }

    if (heroHeight != null && puzzle != null) {
      return Pressable(
        key: ValueKey('next-step-${step.key}'),
        onTap: open,
        scale: 0.985,
        child: Container(
          height: heroHeight,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: c.boardBackground, borderRadius: BorderRadius.circular(Radii.lg), border: Border.all(color: c.stroke)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetImage(url: puzzle.imageUrl, blurhash: puzzle.blurhash),
              DecoratedBox(decoration: BoxDecoration(gradient: Brand.scrim(strength: 0.8, contrast: A11y.increaseContrastOf(context)))),
              Positioned(left: 14, top: 14, child: Chip2(label: step.label, icon: AppIcons.playFill, onImage: true)),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(step.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white)),
                          const SizedBox(height: 4),
                          Text(step.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: TypeSize.footnote, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(AppIcons.playFill, color: Colors.black, size: 20),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return SoftCard(
      key: ValueKey('next-step-${step.key}'),
      onTap: open,
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      child: Row(
        children: [
          if (puzzle != null)
            SizedBox(width: 52, height: 52, child: NetImage(url: puzzle.thumbUrl, blurhash: puzzle.blurhash, radius: 10))
          else
            const Padding(padding: EdgeInsets.all(6), child: IconTile(icon: AppIcons.library, size: IconTile.medium)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(step.label, style: TextStyle(fontSize: TypeSize.caption, fontWeight: FontWeight.w600, color: context.accent, letterSpacing: -0.1)),
                const SizedBox(height: 1),
                Text(step.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(step.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: TypeSize.footnote, height: 1.25, color: c.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: context.accentFill, shape: BoxShape.circle),
            child: Icon(step.route == '/library' ? AppIcons.chevronRight : AppIcons.playFill, color: context.onAccent, size: 18),
          ),
        ],
      ),
    );
  }
}

/// The end of the guided Home: what is still to come, blurred and fading behind a card that
/// says why it waits, lists what opens when, and offers "Unlock anyway".
class MoreToComeCard extends ConsumerWidget {
  const MoreToComeCard({super.key, required this.preview});

  /// The hidden part of Home (Lucky Wheel and piggy bank, packs, level), drawn blurred.
  final Widget preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcoming = ref.watch(upcomingRevealsProvider);
    if (upcoming.isEmpty) return const SizedBox.shrink();
    final solved = ref.watch(solvedCountProvider);
    final c = context.colors;
    final shown = upcoming.take(4).toList();
    return Stack(
      key: const ValueKey('more-to-come'),
      children: [
        // The real sections, out of focus: there is more, and it looks like Home.
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: ClipRect(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
                    stops: [0, 0.08, 0.6, 1],
                  ).createShader(rect),
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4, tileMode: TileMode.decal),
                    child: Opacity(
                      opacity: 0.8,
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        maxHeight: double.infinity,
                        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24), child: preview),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 150, 28, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: PageWidth.sheet),
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: c.stroke, width: 0.5),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? 0.4 : 0.10), blurRadius: 28, offset: const Offset(0, 8))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const IconTile(icon: AppIcons.lock, size: IconTile.small, radius: 9),
                        const SizedBox(width: 10),
                        Expanded(child: Text('More opens as you play', style: Theme.of(context).textTheme.titleLarge)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Carden starts simple, so there is time to settle in. The rest opens as you solve pictures; '
                      'you have solved ${solved == 1 ? '1 picture' : '$solved pictures'} so far.',
                      style: TextStyle(fontSize: TypeSize.footnote, height: 1.35, color: c.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    for (final r in shown)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // The name and when it opens; at a large text size the chip moves under the name.
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(r.label, style: TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w600, color: c.textPrimary)),
                                Chip2(label: r.short),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(r.blurb, style: TextStyle(fontSize: TypeSize.footnote, height: 1.3, color: c.textSecondary)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    BigButton(
                      key: const ValueKey('unlock-anyway'),
                      label: 'Unlock anyway',
                      kind: ButtonKind.secondary,
                      height: 44,
                      onTap: () {
                        Haptics.light();
                        ref.read(firstStepsProvider.notifier).showEverything();
                        showToast(context, 'Everything is open. Settings > Guided start brings the steps back.', icon: AppIcons.unlock);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A section that waits for the player (Profile's achievements): when it opens, and "Unlock anyway".
class LockedSectionCard extends ConsumerWidget {
  const LockedSectionCard({super.key, required this.reveal});
  final Reveal reveal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return SoftCard(
      key: ValueKey('locked-${reveal.name}'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconTile(icon: AppIcons.lock, size: IconTile.medium),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(reveal.opensTitle, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(reveal.blurb, style: TextStyle(fontSize: TypeSize.footnote, height: 1.3, color: c.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          BigButton(
            key: ValueKey('unlock-${reveal.name}'),
            label: 'Unlock anyway',
            kind: ButtonKind.secondary,
            height: 40,
            onTap: () => ref.read(firstStepsProvider.notifier).openEarly(reveal),
          ),
        ],
      ),
    );
  }
}

/// A locked tab was tapped: what it is, when it opens, and "Unlock anyway". True when it opened.
Future<bool> askUnlockEarly(BuildContext context, WidgetRef ref, Reveal r) async {
  final yes = await showAppAlert(
    context,
    title: r.opensTitle,
    message: '${r.blurb} ${r.plural ? 'They wait' : 'It waits'} until then to keep the start simple.',
    confirmLabel: 'Unlock anyway',
    cancelLabel: 'Not now',
  );
  if (yes) ref.read(firstStepsProvider.notifier).openEarly(r);
  return yes;
}

/// A tip said once, where it matters (the Library, the board picker), with a close.
class OneTimeTip extends ConsumerWidget {
  const OneTimeTip({super.key, required this.id, required this.icon, required this.text, this.padding = EdgeInsets.zero});
  final String id;
  final IconData icon;
  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final steps = ref.watch(firstStepsProvider);
    if (!steps.guided || steps.tips.contains('tip:$id')) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: padding,
      child: SoftCard(
        key: ValueKey('tip-$id'),
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            IconTile(icon: icon, size: IconTile.small, radius: 9),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: TextStyle(fontSize: TypeSize.footnote, height: 1.35, color: c.textPrimary))),
            IconButton(
              key: ValueKey('tip-$id-close'),
              tooltip: 'Close',
              onPressed: () => ref.read(firstStepsProvider.notifier).sawTip('tip:$id'),
              icon: Icon(AppIcons.xmark, size: 18, color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
