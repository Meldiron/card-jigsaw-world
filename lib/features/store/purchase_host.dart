import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../data/purchases.dart';
import '../../models/models.dart';
import '../../router.dart';
import '../../state/profile.dart';
import '../../state/purchases.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../profile/help.dart';

/// Shows the purchase flow ([purchaseFlowProvider]) wherever the player is: the purchase sheet
/// for a purchase they follow (waiting for the App Store, adding, added), a toast for one that
/// ends while the sheet is closed (paid while the app was closed, an approved Ask to Buy).
class PurchaseHost extends ConsumerStatefulWidget {
  const PurchaseHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<PurchaseHost> createState() => _PurchaseHostState();
}

class _PurchaseHostState extends ConsumerState<PurchaseHost> {
  bool _sheetOpen = false;

  void _onFlow(PurchaseFlowState? prev, PurchaseFlowState next) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final changed = prev?.stage != next.stage;
    if (changed && next.stage == PurchaseStage.added) {
      if (next.grant?.vipExpiresAt != null) {
        Sfx.instance.win();
      } else {
        Sfx.instance.coin();
      }
      Haptics.success();
    }
    switch (next.stage) {
      case PurchaseStage.waiting || PurchaseStage.adding when next.watching && !_sheetOpen:
        unawaited(_openSheet(ctx));
      case PurchaseStage.added || PurchaseStage.notAdded when changed && !_sheetOpen:
        _toast(ctx, next);
        ref.read(purchaseFlowProvider.notifier).clear();
      case PurchaseStage.storeError || PurchaseStage.awaitingApproval when changed:
        // The sheet, if open, closes itself.
        _toast(ctx, next);
        ref.read(purchaseFlowProvider.notifier).clear();
      default:
        break;
    }
  }

  Future<void> _openSheet(BuildContext ctx) async {
    _sheetOpen = true;
    await showAppSheet<void>(ctx, builder: (_) => const PurchaseSheet());
    _sheetOpen = false;
    if (mounted) ref.read(purchaseFlowProvider.notifier).closeSheet();
  }

  void _toast(BuildContext ctx, PurchaseFlowState s) {
    switch (s.stage) {
      case PurchaseStage.added:
        final g = s.grant!;
        if (g.vipExpiresAt != null) {
          showToast(ctx, 'VIP active until ${formatDate(g.vipExpiresAt!)}', icon: AppIcons.vip);
        } else {
          showToast(ctx, 'Added ${g.label}', leading: currencyIcon(_currencyOf(g), size: 20));
        }
      case PurchaseStage.notAdded:
        showToast(ctx, 'Purchase not added yet. It is checked again the next time you open the app.', icon: AppIcons.time);
      case PurchaseStage.storeError:
        showToast(ctx, s.message ?? PurchaseService.storeErrorMessage, icon: AppIcons.time);
      case PurchaseStage.awaitingApproval:
        showToast(ctx, 'Waiting for approval. Added once it is approved.', icon: AppIcons.time);
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(purchaseFlowProvider, _onFlow);
    return widget.child;
  }
}

/// The purchase the player follows, from "Waiting for the App Store" to "10 tickets added".
/// Closing it leaves the purchase to finish in the background.
class PurchaseSheet extends ConsumerWidget {
  const PurchaseSheet({super.key});

  static const _ends = {PurchaseStage.idle, PurchaseStage.storeError, PurchaseStage.awaitingApproval};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(purchaseFlowProvider.select((s) => s.stage), (_, stage) {
      // Only while it is the top route: once closed (Done), the flow going idle must not close
      // the screen beneath it.
      if (_ends.contains(stage) && (ModalRoute.of(context)?.isCurrent ?? false)) Navigator.of(context).pop();
    });
    final c = context.colors;
    final s = ref.watch(purchaseFlowProvider);
    final profile = ref.watch(profileProvider).value;
    final id = s.productId ?? '';
    final vip = ProductIds.isSubscription(id);
    final expected = StoreProducts.grant(id);
    final grant = s.grant;
    final currency = grant != null ? _currencyOf(grant) : (expected.tickets > 0 ? Currency.tickets : (expected.hints > 0 ? Currency.hints : Currency.coins));
    final working = s.stage == PurchaseStage.waiting || s.stage == PurchaseStage.adding;

    final (String title, String body) = switch (s.stage) {
      PurchaseStage.waiting => ('Waiting for the App Store', 'The App Store is confirming your payment. This usually takes a few seconds.'),
      PurchaseStage.adding => (
          vip ? 'Starting VIP' : 'Adding ${expected.label}',
          s.slow ? 'This is taking longer than usual. Your purchase is saved and is added automatically, even if you close this.' : 'Payment received. This takes a few seconds.',
        ),
      PurchaseStage.added when vip || grant?.vipExpiresAt != null => (
          'VIP is active',
          grant?.vipExpiresAt != null ? 'Until ${formatDate(grant!.vipExpiresAt!)}. Every pack is unlocked.' : 'Every pack is unlocked.',
        ),
      PurchaseStage.added => (
          '${grant?.label ?? expected.label} added',
          (grant?.product ?? expected).helpers ? _helpersLine(s.balances, profile) ?? '' : _balanceLine(currency, s.balances, profile) ?? '',
        ),
      PurchaseStage.notAdded => (
          'Not added yet',
          '${_sentence(s.message)}Your purchase is saved and checked again the next time you open the app. If it does not arrive, contact support.',
        ),
      _ => ('', ''),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The crown in the Store VIP card's gold tint; a currency on the accent tint.
          if (vip)
            IconTile(icon: AppIcons.vip, size: IconTile.large, color: Brand.coin.withValues(alpha: context.isDark ? 0.18 : 0.14), iconColor: context.isDark ? Brand.coin : Brand.coinDeep)
          else
            Container(
              width: IconTile.large,
              height: IconTile.large,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.accentTint, shape: BoxShape.circle),
              child: currencyIcon(currency, size: 34),
            ),
          const SizedBox(height: 12),
          // A status sheet: its header is centred (design QA 130 B).
          SizedBox(width: double.infinity, child: SheetHeader(key: const ValueKey('purchase-title'), title: title, subtitle: body.isEmpty ? null : body, center: true)),
          const SizedBox(height: 20),
          if (working) ...[
            const SizedBox(height: 28, child: CupertinoActivityIndicator()),
            if (s.slow || s.stage == PurchaseStage.waiting) ...[
              const SizedBox(height: 16),
              BigButton(label: 'Close', kind: ButtonKind.secondary, onTap: () => Navigator.of(context).pop()),
            ],
          ] else if (s.stage == PurchaseStage.added)
            BigButton(label: 'Done', onTap: () => Navigator.of(context).pop())
          else if (s.stage == PurchaseStage.notAdded) ...[
            BigButton(label: 'Close', onTap: () => Navigator.of(context).pop()),
            const SizedBox(height: 4),
            // A plain text button, as on the other sheets.
            Pressable(
              onTap: () => contactSupport(context, ref),
              child: SizedBox(
                height: 44,
                width: double.infinity,
                child: Center(child: Text('Contact support', style: TextStyle(fontSize: TypeSize.callout, fontWeight: FontWeight.w600, color: context.accent))),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// "You now have 15 tickets." The server's answer when it gave one, else the save.
  static String? _balanceLine(Currency currency, PurchaseBalances? balances, Profile? profile) {
    final (int? n, String noun) = switch (currency) {
      Currency.tickets => (balances?.tickets ?? profile?.tickets, 'ticket'),
      Currency.hints => (balances?.hints ?? profile?.hints, 'hint'),
      _ => (balances?.coins ?? profile?.coins, 'coin'),
    };
    if (n == null) return null;
    return 'You now have ${countOf(n, noun)}.';
  }

  /// "You now have 16 Peeks, 12 Hints and 5 Magic." after a helper bundle.
  static String? _helpersLine(PurchaseBalances? balances, Profile? profile) {
    final b = balances ?? (profile == null ? null : (coins: profile.coins, tickets: profile.tickets, hints: profile.hints, peeks: profile.peeks, magics: profile.magics));
    if (b == null) return null;
    return 'You now have ${countOf(b.peeks, 'Peek')}, ${countOf(b.hints, 'Hint')} and ${formatCount(b.magics)} Magic.';
  }

  /// The server's reason as a sentence followed by a space ("Transaction could not be verified. ").
  static String _sentence(String? message) {
    final m = (message ?? '').trim();
    if (m.isEmpty) return '';
    return m.endsWith('.') ? '$m ' : '$m. ';
  }
}

/// The mark a grant is shown with: a helper bundle (Peeks, Hints, Magic) shows the hint.
Currency _currencyOf(PurchaseGrant g) => g.tickets > 0 ? Currency.tickets : (g.hints > 0 || g.product.helpers ? Currency.hints : Currency.coins);
