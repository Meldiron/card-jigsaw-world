import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../game/game_controller.dart' show formatDuration;
import '../../game/modes.dart';
import '../../models/models.dart';
import '../../state/sync.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// Asks which board to keep when the same picture has a board in progress on this device and a
/// different one from another device. Stars and records are never lost either way. Cannot be
/// dismissed without choosing; if the OS closes it anyway, this device's board is kept.
Future<BoardChoice> showBoardChoiceSheet(BuildContext context, {String? title, required PuzzleProgress device, required PuzzleProgress other}) async {
  final choice = await showAppSheet<BoardChoice>(
    context,
    dismissible: false,
    builder: (ctx) => BoardChoiceSheet(title: title, device: device, other: other),
  );
  return choice ?? BoardChoice.device;
}

class BoardChoiceSheet extends StatelessWidget {
  const BoardChoiceSheet({super.key, this.title, required this.device, required this.other});
  final String? title;
  final PuzzleProgress device;
  final PuzzleProgress other;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = title == null || title!.isEmpty ? 'this picture' : title!;
    return PopScope(
      canPop: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Two boards in progress', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'You played $name on another device too. Choose which board to keep; stars and records from both stay.',
              style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _BoardCard(label: 'This device', board: device)),
                const SizedBox(width: 12),
                Expanded(child: _BoardCard(label: 'Other device', board: other)),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: BigButton(label: "Keep this device's board", onTap: () => Navigator.of(context).pop(BoardChoice.device))),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: BigButton(label: "Keep the other device's board", kind: ButtonKind.secondary, onTap: () => Navigator.of(context).pop(BoardChoice.other)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.label, required this.board});
  final String label;
  final PuzzleProgress board;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mode = GameMode.fromCode(board.mode);
    Widget stat(IconData icon, String name, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(width: 18, child: Center(child: Icon(icon, size: 15, color: c.textTertiary))),
              const SizedBox(width: 6),
              Expanded(child: Text(name, style: TextStyle(fontSize: 12.5, color: c.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              Text(value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.textPrimary)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(Radii.lg), border: Border.all(color: c.stroke)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: c.textTertiary)),
          const SizedBox(height: 8),
          Text(mode.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          Divider(height: 1, color: c.stroke),
          const SizedBox(height: 6),
          stat(AppIcons.puzzle, 'Pieces', '${board.gridSize}'),
          stat(AppIcons.swaps, 'Moves', '${board.moves}'),
          stat(AppIcons.time, 'Time', formatDuration(board.elapsedSeconds)),
        ],
      ),
    );
  }
}
