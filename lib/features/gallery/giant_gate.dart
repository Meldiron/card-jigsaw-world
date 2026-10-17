import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics.dart';
import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/profile.dart';
import '../../state/rewards.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../game/unlock_intro.dart' show showLockedInfo;

/// Where a player below level 10 stands with giant boards, and what opening them now costs.
class GiantGate {
  const GiantGate({required this.xp, required this.price, required this.packTickets, required this.owned, required this.balance});

  /// The player's XP (their level and the way to level 10 come from it).
  final int xp;

  /// The pack's ticket price when it is bought with the early opening (0 when the player has it).
  final int packTickets;

  /// The player has the pack already (bought, VIP, free): only the fee is left to pay.
  final bool owned;
  final int balance;

  /// Tickets "Open now" takes ([ProfileNotifier.giantEarlyPrice]): the pack's price unless the
  /// player has it, plus [Economy.giantEarlyFee].
  final int price;

  factory GiantGate.of(WidgetRef ref, Pack pack) {
    final profile = ref.watch(profileProvider).value;
    final profileN = ref.read(profileProvider.notifier);
    final owned = profile != null && profileN.isUnlocked(pack);
    return GiantGate(
      xp: profile?.xp ?? 0,
      price: profile == null ? pack.priceTickets + Economy.giantEarlyFee(1) : profileN.giantEarlyPrice(pack),
      packTickets: owned ? 0 : pack.priceTickets,
      owned: owned,
      balance: profile?.tickets ?? 0,
    );
  }

  int get level => LevelRewards.levelForXp(xp);
  int get target => Unlock.giant.level;
  int get levelsToGo => (target - level).clamp(0, target);
  int get xpToGo => (LevelRewards.xpToReach(target) - xp).clamp(0, 1 << 30);

  /// Share of the way from no XP to level 10.
  double get progress {
    final need = LevelRewards.xpToReach(target);
    return need == 0 ? 1 : (xp / need).clamp(0.0, 1.0);
  }

  bool get affordable => balance >= price;
}

/// Opens giant boards now for the Giant [pack] (and buys the pack unless the player has it), after
/// one alert that says what the tickets pay for. Short of tickets: says so and opens the store.
Future<void> openGiantEarly(BuildContext context, WidgetRef ref, Pack pack) async {
  final profileN = ref.read(profileProvider.notifier);
  final profile = ref.read(profileProvider).value;
  if (profile == null) return;
  final owned = profileN.isUnlocked(pack);
  final price = profileN.giantEarlyPrice(pack);
  final fee = price - (owned ? 0 : pack.priceTickets);
  final levels = Unlock.giant.level - profile.level;
  if (profile.tickets < price) {
    Sfx.instance.error();
    showToast(context, '${countOf(price - profile.tickets, 'more ticket')} needed. Finish weekly quests or level up to earn more.', leading: const TicketIcon(size: 20));
    context.push('/store');
    return;
  }
  // The rule in words: 1 ticket for each level still to go (Economy.giantEarlyTicketsPerLevel).
  final perLevel = levels == 1 ? '${countOf(fee, 'ticket')} for the last level to go' : '${formatCount(Economy.giantEarlyTicketsPerLevel)} for each of the $levels levels to go';
  final sure = await showAppAlert(
    context,
    title: owned ? 'Open giant boards now?' : 'Open ${pack.name} now?',
    message: owned
        ? 'This costs ${countOf(price, 'ticket')}, $perLevel. Giant boards then stay open. You have ${formatCount(profile.tickets)}.'
        : 'This costs ${countOf(price, 'ticket')}: ${formatCount(pack.priceTickets)} for the pack and $perLevel. Giant boards then stay open. You have ${formatCount(profile.tickets)}.',
    confirmLabel: 'Pay ${countOf(price, 'ticket')}',
  );
  if (!sure || !context.mounted) return;
  final ok = await profileN.openGiantEarly(pack);
  if (ok) AppAnalytics.event('pack_unlocked', {'pack': pack.id, 'paid': 'early_giant', 'price': price, 'levelsToGo': levels});
  if (!context.mounted || !ok) return;
  Haptics.success();
  Sfx.instance.coin();
  showToast(context, owned ? 'Giant boards are open' : '${pack.name} is open', icon: AppIcons.check);
}

/// The gate in a sheet, for a tap on one of the pack's pictures.
Future<void> showGiantGateSheet(BuildContext context, WidgetRef ref, Pack pack) => showAppSheet<void>(
      context,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SheetHeader(title: pack.name),
              const SizedBox(height: 12),
              GiantGateCard(
                gate: GiantGate.of(ref, pack),
                onOpenNow: () {
                  Navigator.pop(ctx);
                  openGiantEarly(context, ref, pack);
                },
              ),
            ],
          ),
        ),
      ),
    );

/// The gate sheet for the Giant pack [packId], for a giant picture opened before giant boards
/// (the difficulty screen's locked button); the plain level info when the pack is not known.
Future<void> showGiantGateFor(BuildContext context, WidgetRef ref, String? packId) {
  final pack = (ref.read(packsProvider).value ?? const <Pack>[]).where((p) => p.id == packId).firstOrNull;
  if (pack == null) return showLockedInfo(context, ref, Unlock.giant);
  return showGiantGateSheet(context, ref, pack);
}

/// A Giant pack before giant boards open: what the pack is, how far level 10 is, and the two
/// ways in side by side: at level 10 for the usual price, or now for the usual price plus one
/// ticket for every level to go (owner, 2026-10-15). The track counts levels, so "5 levels early"
/// can be seen on it.
class GiantGateCard extends StatelessWidget {
  const GiantGateCard({super.key, required this.gate, required this.onOpenNow});
  final GiantGate gate;
  final VoidCallback onOpenNow;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final early = gate.levelsToGo == 1 ? '1 level early' : '${gate.levelsToGo} levels early';
    return SoftCard(
      key: const ValueKey('giant-gate'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconTile(icon: AppIcons.bigBoard, size: IconTile.medium),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Giant boards open at level ${gate.target}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: TypeSize.body, letterSpacing: -0.2)),
                    const SizedBox(height: 2),
                    Text('Every picture in this pack is a board of 100 to 300 cards.', style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote, height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Level ${gate.level}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: TypeSize.body)),
              Text(' of ${gate.target}', style: TextStyle(color: c.textSecondary, fontSize: TypeSize.body)),
              const SizedBox(width: 12),
              Expanded(
                child: Text('${formatCount(gate.xpToGo)} XP to go', textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _LevelTrack(gate: gate),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Way(
                    key: const ValueKey('giant-way-wait'),
                    title: 'At level ${gate.target}',
                    amount: gate.owned ? null : gate.packTickets,
                    note: gate.owned ? 'Nothing more' : 'The usual price',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Way(key: const ValueKey('giant-way-now'), title: 'Now', amount: gate.price, note: early, highlight: true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          BigButton.cost(key: const ValueKey('giant-open-now'), label: 'Open now for', currency: Currency.tickets, amount: gate.price, onTap: onOpenNow),
          if (!gate.affordable)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('You have ${countOf(gate.balance, 'ticket')}', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: TypeSize.footnote, fontWeight: FontWeight.w500)),
            ),
        ],
      ),
    );
  }
}

/// One way into the pack: when, what it costs, and what that means.
class _Way extends StatelessWidget {
  const _Way({super.key, required this.title, required this.amount, required this.note, this.highlight = false});
  final String title;

  /// Tickets it costs; null when the pack is the player's already ("Included").
  final int? amount;
  final String note;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: highlight ? c.accentTint : null,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: highlight ? context.accent.withValues(alpha: 0.35) : c.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: highlight ? context.accent : c.textSecondary, fontSize: TypeSize.footnote, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          // Larger Text on a small phone: the figure shrinks to fit instead of running out.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: amount == null
                ? const Text('Included', style: TextStyle(fontSize: TypeSize.headline, fontWeight: FontWeight.w700, letterSpacing: -0.3))
                : Amount(currency: Currency.tickets, value: amount!, size: 20, fontSize: TypeSize.headline),
          ),
          const SizedBox(height: 4),
          Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontSize: TypeSize.caption, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// The way to level 10 as one segment a level-up (1 to 2 ... 9 to 10): the ones done in cobalt,
/// the current one filled as far as its XP goes, the rest in the track colour ([ProgressBar]'s
/// colours). The segments not yet full are the levels to go, one ticket each when skipped.
class _LevelTrack extends StatelessWidget {
  const _LevelTrack({required this.gate});
  final GiantGate gate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // How far into the current level the player is.
    final from = LevelRewards.xpToReach(gate.level), to = LevelRewards.xpToReach(gate.level + 1);
    final partial = to <= from ? 0.0 : ((gate.xp - from) / (to - from)).clamp(0.0, 1.0);
    return Semantics(
      label: 'Level ${gate.level} of ${gate.target}',
      child: Row(
        children: [
          for (var l = 1; l < gate.target; l++) ...[
            if (l > 1) const SizedBox(width: 3),
            Expanded(
              child: Container(
                height: 6,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: c.stroke, borderRadius: BorderRadius.circular(3)),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: l < gate.level ? 1 : (l == gate.level ? partial : 0),
                  child: Container(color: context.accent),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
