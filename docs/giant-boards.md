# Giant boards

Pictures of a pack with category `Giant` deal only four giant sizes (Large, Huge, Giant, Colossal:
about 100 to 300 cards in Cards, more cells in the other shapes; `BoardSpec.giantTiers`). The
pictures are hosted at up to 4096 px on the long side and decoded at full size, so the board can be
zoomed in and stay sharp. This page records how other big-board jigsaw apps help players on a phone
and what Card Jigsaw World does on a giant board.

## What other games do (research, October 2026)

| App | What it offers for big puzzles | Source |
|---|---|---|
| Jigsaw Puzzle by MobilityWare | Edges-only view and a piece tray, hints, image preview | [App Store](https://apps.apple.com/app/id1603688971) |
| Jigsaw Puzzle⁺ | Zoom and pan, show all pieces or edge pieces only, tray on or off | [App Store](https://apps.apple.com/app/id1571760112) |
| Jigsaw Explorer (web) | Show only edge pieces, autosave of progress | [Educators Technology](https://www.educatorstechnology.com/2023/03/jigsaw-explorer-free-online-jigsaw.html) |
| Jigsaw Puzzle HD | Zoom and pan; a guided mode that sorts pieces by colour and edge | [App Store](https://apps.apple.com/app/id6453471674) |
| Jigsawscapes / desktop puzzles | Sort by shape and colour, "arrange at edge", magnifying glass, ghost image | [App Store](https://apps.apple.com/app/id435749624), [Jigsaws Galore](https://lutris.net/games/jigsaws-galore/) |
| PuzzleTouch | Double tap on the table to zoom in and out, performance work for big puzzles | [Microsoft Store](https://microsoft.com/nl-be/p/puzzletouch/9wzdncrfj45p) |
| Magic Jigsaw Puzzles | Up to 1,200 pieces, several puzzles in progress, preview | [App Store](https://apps.apple.com/us/app/magic-jigsaw-puzzles-games-hd/id439873467) |
| Jigsaw Puzzle ++ | Players like working on a zoomed-in quarter of the puzzle (sight issues) | [review summary](https://mwm.ai/apps/jigsaw-puzzle/1477002422) |

What reviews complain about on big boards ([Justuseapp](https://justuseapp.com/en/app/796882776/jigsaw-puzzles-epic/reviews),
[App Store 1000 Jigsaw Puzzles](https://apps.apple.com/app/id571230079), [MobilityWare reviews](https://justuseapp.com/en/app/495583717/jigsaw-puzzle/reviews)):
pieces too small; the board growing or shrinking on its own when touched; zoom that does not work;
a preview too small to read; and finding the last unplaced pieces once the board is nearly full.

## What a giant board does here

The swap board has no free table and no tray (every card is always on the board), so the tools
are the ones that make sense for it:

- **Pinch to zoom, two fingers to move; one finger plays as usual.** Tap-tap and drag work at
  every zoom, and a selected card stays selected while zooming and panning. The zoom changes only
  when the player asks (no automatic zoom: a top complaint elsewhere).
- **Double tap to zoom** in at that card, double tap again for the whole board (PuzzleTouch). Taps
  go through at once: the second tap of a double tap undoes the first one's select or deselect, so
  tap-tap moves never wait.
- **A zoom limit per board** (`BoardZoom.fitCell`): a card reaches about 96 pt on screen at most,
  so the 100-card board stops near 2.5x and the 300-card board at 4x. Never so close that only two
  cards show.
- **Edges** (MobilityWare, Jigsaw Puzzle⁺, Jigsaw Explorer): a switch in the bar that keeps the
  cards whose place is on the board's outline bright and fades every other card back. It works for
  every shape (an edge cell is a cell with a missing neighbour).
- **Overview map** while zoomed in: the whole board in miniature in the corner, cards in place
  bright and the rest darker (so the unfinished areas are easy to find, the "last pieces" problem),
  the view outlined, the selected card marked. Tap or drag on it to move the view. A button in the
  bar hides it (remembered).
- **A pointer to the selected card** when it is out of view: a round cobalt arrow on the edge of
  the view, turned towards the card; tap it to go back.
- **Auto-pan**: drag a card to the edge of the view and hold it there, the board slides under it,
  so one drag can cross the board.
- **Resume on the same view**: the zoom and the part of the picture in view are saved per board on
  the device (`GiantViews`) and restored when the board is continued; finishing the board forgets it.
- **Thin frames on giant boards**: the board is scaled as a whole, so gutters, frames and outlines
  are kept thin for the close view and outlines thin out in steps as the zoom grows (at 4x a
  normal frame took a third of every card).
- **Milestones**: a calm toast when the frame is complete and at halfway, once each per board.

Code: `BoardZoom` and the board's gestures in `lib/features/game/board_widget.dart`, the bar, the
map, the pointer and the milestones in `lib/features/game/giant_board.dart`, the saved views in
`lib/state/giant.dart`. QA: `integration_test/giant_ux_test.dart` plays the real Giant pack.
