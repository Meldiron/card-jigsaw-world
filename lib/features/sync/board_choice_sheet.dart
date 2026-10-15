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
            SheetHeader(title: 'Two boards in progress', subtitle: 'You played $name on another device too. Choose the board to keep; stars and records from both stay.'),
            const SizedBox(height: 16),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _BoardCard(label: 'This device', board: device),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BoardCard(label: 'Other device', board: other),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            BigButton(key: const ValueKey('keep-this-board'), label: "Keep this device's board", onTap: () => Navigator.of(context).pop(BoardChoice.device)),
            const SizedBox(height: 10),
            BigButton(key: const ValueKey('keep-other-board'), label: "Keep the other device's board", kind: ButtonKind.secondary, onTap: () => Navigator.of(context).pop(BoardChoice.other)),
          ],
        ),
      ),
    );
  }
}

/// One of the two boards as it stands, drawn exactly as the game draws it (cards locked in
/// place, groups with their cobalt outline, loose cards in their frames, Painting in black and
/// white), then how far it is: the game's own "10/16 locked" line and bar, and the moves and time.
class _BoardCard extends ConsumerWidget {
  const _BoardCard({required this.label, required this.board});
  final String label;
  final PuzzleProgress board;

  static const previewHeight = 132.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final mode = GameMode.fromCode(board.mode);
    final layout = board.layout;
    final puzzle = ref.watch(resolvedPuzzleProvider(board.puzzleId));
    final img = puzzle == null ? null : ref.watch(puzzleImageProvider(puzzle.imageUrl)).value;
    // The board this save was dealt on: settled by the picture's shape once it is decoded, as
    // the game does; until then the best guess from the piece count.
    final spec = (img == null ? null : BoardSpec.fromSaved(mode, board.gridSize, img.width / img.height)) ?? BoardSpec.fromCells(mode, board.gridSize);
    final b = layout != null && layout.length == spec.cells ? Board(spec, layout) : null;
    final locked =
        b?.lockedCount ??
        (layout == null
            ? 0
            : [
                for (var i = 0; i < layout.length; i++)
                  if (layout[i] == i) i,
              ].length);
    final style = ref.watch(settingsProvider).cardStyle;

    Widget preview() {
      if (img == null || b == null) {
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
      // Drawn at the size the game gives this board on this phone and scaled down, so gaps,
      // corners and group outlines keep the proportions the player saw.
      final screen = MediaQuery.sizeOf(context);
      final full = b.tiling.fit(Size(screen.width - 24, screen.height * 0.62), img.width / img.height);
      return FittedBox(
        child: SizedBox.fromSize(
          size: full,
          child: IgnorePointer(
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
              width: full.width,
              height: full.height,
              painting: board.painting,
              cardStyle: style,
              onTap: (_) {},
              onDrop: (_, _) {},
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textPrimary),
          ),
          Text(
            '${mode.label} ${spec.code}${board.painting ? ' · Painting' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: TypeSize.caption, color: c.textSecondary),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: previewHeight,
            width: double.infinity,
            child: Center(child: preview()),
          ),
          const Spacer(),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$locked',
                  style: TextStyle(fontSize: TypeSize.headline, fontWeight: FontWeight.w700, color: c.textPrimary),
                ),
                TextSpan(
                  text: ' of ${board.gridSize} locked',
                  style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textPrimary),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          ProgressBar(value: board.gridSize == 0 ? 0 : locked / board.gridSize, height: 6),
          const SizedBox(height: 6),
          Text(
            '${countOf(board.moves, 'move')} · ${formatDuration(board.elapsedSeconds)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: TypeSize.caption, color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}
