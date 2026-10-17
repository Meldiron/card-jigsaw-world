import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics.dart';
import '../../core/platform.dart';
import '../../core/theme/tokens.dart';
import '../../game/board.dart';
import '../../models/models.dart';
import '../../router.dart';
import '../../state/auth.dart';
import '../../state/catalog.dart';
import '../../state/coop/coop_controller.dart';
import '../../state/coop/coop_models.dart';
import '../../state/settings.dart';
import '../../widgets/ui.dart';
import 'coop_alerts.dart';
import 'coop_routes.dart';
import 'share_invite.dart';

/// Opens an invite (`/join/<code>`, docs/multiplayer.md): joins the game and shows its board. From
/// a fresh install the board opens straight away, as a guest; the welcome pages and the guided
/// start begin after the player leaves the game. Called by `DeepLinks`.
Future<void> openInvite(Ref ref, String code) async {
  final router = ref.read(routerProvider);
  final coop = ref.read(coopProvider.notifier);
  final now = ref.read(coopProvider);
  if (now.playing && now.game!.code == code) {
    _show(router, now.game!);
    return;
  }
  if (now.playing) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted || !await confirmSwitchGame(ctx)) return;
    await coop.leave();
  }
  // The player plays as everyone does: a guest account is made on first launch.
  try {
    await ref.read(authProvider.future).timeout(const Duration(seconds: 20));
  } catch (_) {}
  final fresh = !ref.read(settingsProvider).onboarded;
  while (true) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final result = await runWithProgress(ctx, title: 'Joining the game', task: () => coop.join(code));
    if (result.value != null) {
      final g = result.value!;
      AppAnalytics.event('coop_game_joined', {'freshInstall': fresh, 'platform': isWeb ? 'web' : 'app', 'players': g.playerIds.length, 'cards': g.layout.length});
      _show(router, g);
      return;
    }
    final again = rootNavigatorKey.currentContext;
    if (again == null || !again.mounted || !await showRefusal(again, result.refusal!)) return;
  }
}

void _show(GoRouter router, CoopGame game) {
  final at = CoopRoutes.top(router);
  if (at != null && CoopRoutes.isCoop(at)) {
    router.pushReplacement(game.route);
  } else {
    router.push(game.route);
  }
}

/// Whether [puzzle] can be played together: catalogue pictures only (not My Puzzles photos, which
/// are private, nor pictures of a pack-code pack). The server checks it again.
bool canPlayTogether(WidgetRef ref, Puzzle puzzle) {
  if (puzzle.packId == 'my-puzzles') return false;
  final pack = (ref.read(packsProvider).value ?? const <Pack>[]).where((p) => p.id == puzzle.packId).firstOrNull;
  return pack != null && !pack.hidden;
}

/// The pause menu's Play together (phase 2 calls it): starts a game on the board being played
/// ([layout] as it is now, the host's own board) and opens the share sheet with the invite.
/// Returns the game, or null when it did not start.
Future<CoopGame?> startPlayTogether(BuildContext context, WidgetRef ref, {required Puzzle puzzle, required String grid, required List<int> layout, bool painting = false}) async {
  if (!canPlayTogether(ref, puzzle)) {
    await showRefusal(context, const CoopRefusal(CoopRefusalReason.picture));
    return null;
  }
  final coop = ref.read(coopProvider.notifier);
  while (true) {
    if (!context.mounted) return null;
    final result = await runWithProgress(context, title: 'Starting the game', task: () => coop.create(puzzleId: puzzle.id, grid: grid, layout: layout, painting: painting));
    if (!context.mounted) return result.value;
    if (result.value != null) {
      final spec = BoardSpec.fromCode(grid);
      AppAnalytics.event('coop_game_created', {'mode': spec.mode.code, 'board': spec.code, 'cards': layout.length, 'painting': painting, 'giant': spec.isGiant});
      await shareInvite(context, result.value!, pictureTitle: puzzle.title);
      return result.value;
    }
    if (!await showRefusal(context, result.refusal!)) return null;
  }
}

/// Runs [task] under a sheet with a spinner (the function can take a few seconds to wake up), and
/// closes the sheet when it is done.
Future<({T? value, CoopRefusal? refusal})> runWithProgress<T>(BuildContext context, {required String title, required Future<T> Function() task}) async {
  final done = ValueNotifier(false);
  final sheet = showAppSheet<void>(context, dismissible: false, builder: (_) => CoopProgressPanel(title: title, done: done));
  ({T? value, CoopRefusal? refusal}) result;
  try {
    result = (value: await task(), refusal: null);
  } on CoopRefusal catch (e) {
    result = (value: null, refusal: e);
  } catch (e) {
    result = (value: null, refusal: CoopRefusal(CoopRefusalReason.server, '$e'));
  }
  done.value = true;
  // What comes next (the board, an alert) opens once the sheet is gone.
  await sheet;
  return result;
}

/// A sheet with a spinner that closes itself once [done] turns true.
class CoopProgressPanel extends StatefulWidget {
  const CoopProgressPanel({super.key, required this.title, required this.done});
  final String title;
  final ValueNotifier<bool> done;

  @override
  State<CoopProgressPanel> createState() => _CoopProgressPanelState();
}

class _CoopProgressPanelState extends State<CoopProgressPanel> {
  @override
  void initState() {
    super.initState();
    widget.done.addListener(_close);
    if (widget.done.value) WidgetsBinding.instance.addPostFrameCallback((_) => _close());
  }

  void _close() {
    if (!mounted) return;
    widget.done.removeListener(_close);
    // This sheet's own route, wherever it is: an alert may already be on top of it.
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final nav = Navigator.of(context);
    if (route.isCurrent) {
      nav.pop();
    } else {
      nav.removeRoute(route);
    }
  }

  @override
  void dispose() {
    widget.done.removeListener(_close);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Padding(
        key: const ValueKey('coop-progress'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(title: widget.title, subtitle: 'This can take a few seconds.', center: true),
            const SizedBox(height: 20),
            const Loader(),
            const SizedBox(height: Spacing.sm),
          ],
        ),
      ),
    );
  }
}
