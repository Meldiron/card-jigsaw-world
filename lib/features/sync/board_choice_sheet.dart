import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../game/board.dart';
import '../../game/game_controller.dart' show GameState, GameStatus, formatDuration;
import '../../game/image_loader.dart';
import '../../models/models.dart';
import '../../state/settings.dart';
import '../../state/social.dart' show resolvedPuzzleProvider;
import '../../state/sync.dart';
import '../../widgets/hash_image.dart';
import '../../widgets/ui.dart';
import '../game/board_widget.dart';

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
    final name = title == null || title!.isEmpty ? 'this picture' : title!;
    return PopScope(
      canPop: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetHeader(
              title: 'Two boards in progress',
              subtitle: 'You played $name on another device too. Keep one board; stars and records from both stay.',
              center: false,
            ),
            const SizedBox(height: 16),
            // The choice is made on the board itself: each card keeps its own.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _BoardCard(label: 'This device', board: device, primary: true, onKeep: () => Navigator.of(context).pop(BoardChoice.device))),
                const SizedBox(width: 12),
                Expanded(child: _BoardCard(label: 'Other device', board: other, onKeep: () => Navigator.of(context).pop(BoardChoice.other))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the two boards as it stands: the real board in miniature (cards in
/// place fill their cell, loose cards keep their frame), how many cards are
/// in place, and the moves and time so far.
class _BoardCard extends ConsumerWidget {
  const _BoardCard({required this.label, required this.board, this.onKeep, this.primary = false});
  final String label;
  final PuzzleProgress board;

  /// Keeps this board (the card is the choice); null when buttons below choose.
  final VoidCallback? onKeep;
  final bool primary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final mode = GameMode.fromCode(board.mode);
    final spec = BoardSpec.fromCells(mode, board.gridSize);
    final layout = board.layout;
    final inPlace = layout == null ? null : [for (var i = 0; i < layout.length; i++) if (layout[i] == i) i].length;
    final puzzle = ref.watch(resolvedPuzzleProvider(board.puzzleId));
    final image = puzzle == null ? null : ref.watch(puzzleImageProvider(puzzle.imageUrl));
    final style = ref.watch(settingsProvider).cardStyle;
    const previewHeight = 118.0;
    Widget preview() {
      final img = image?.value;
      if (img == null || layout == null || layout.length != spec.cells) {
        // Until the picture is decoded: its colours, in the board's shape.
        return SizedBox(
          height: previewHeight,
          width: previewHeight * 0.75,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.sm),
            child: puzzle?.blurhash == null ? ColoredBox(color: c.boardBackground) : HashImage(hash: puzzle!.blurhash!, color: c.boardBackground),
          ),
        );
      }
      final b = Board(spec, layout);
      final size = b.tiling.fit(const Size(double.infinity, previewHeight), img.width / img.height);
      return IgnorePointer(
        child: BoardWidget(
          image: img,
          state: GameState(
            board: b,
            par: b.par,
            moves: board.moves,
            elapsed: board.elapsedSeconds,
            status: GameStatus.paused,
            selected: null,
            hintsUsed: 0,
            history: const [],
            justLocked: const {},
            justJoined: const {},
            hintSlot: null,
            hintTarget: null,
            peeking: false,
            chain: 0,
            tick: 0,
          ),
          width: size.width,
          height: size.height,
          cardStyle: style,
          onTap: (_) {},
          onDrop: (_, _) {},
        ),
      );
    }

    final card = Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(Radii.lg), border: Border.all(color: c.stroke)),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textPrimary)),
          Text('${mode.label} ${spec.code}', style: TextStyle(fontSize: TypeSize.caption, color: c.textSecondary)),
          const SizedBox(height: 8),
          SizedBox(height: previewHeight, child: Center(child: preview())),
          const SizedBox(height: 10),
          Text(
            inPlace == null ? '${board.gridSize} cards' : '$inPlace of ${board.gridSize} in place',
            style: TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w700, color: c.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            '${countOf(board.moves, 'move')} · ${formatDuration(board.elapsedSeconds)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: TypeSize.caption, color: c.textSecondary),
          ),
          if (onKeep != null) ...[
            const SizedBox(height: 12),
            BigButton(key: ValueKey(primary ? 'keep-this-board' : 'keep-other-board'), label: 'Keep', height: 40, kind: primary ? ButtonKind.primary : ButtonKind.secondary, onTap: onKeep),
          ],
        ],
      ),
    );
    return onKeep == null ? card : Pressable(onTap: onKeep, scale: 0.98, child: card);
  }
}
