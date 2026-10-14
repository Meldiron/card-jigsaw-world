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
are the ones that make sense for it.

### No zones (owner, 2026-10-14)

Giant boards were dealt by zone for a day (each card shuffled inside an area of about a normal
board). The owner removed it: the player can zoom in as far as they like and Gather the cards for
the view, so zones only added lines and rules. A giant board is shuffled across the whole board like
any other (`Board.shuffled`: no card in place, no pair joined).

### Finding a card's place

- **Locate** (owner, 2026-10-14): tap a card on a zoomed board and the overview map shows where it
  belongs: a ring there and a line from the card, for as long as the card is selected. It only uses
  the map when the map is on (it never opens a hidden map), and the Locate switch in the bar turns it
  off (remembered, `GiantViews.locate`, on by default). The first zoom with the map and Locate on says
  so once ("Tap a card to see its place on the map").
- **Gather** (in the bar while zoomed in): every card that belongs in the view comes into it. Each
  card in view that belongs elsewhere trades places with one that belongs here, chosen so the card
  leaving lands as close to its own place as it can. Cards in place, joined groups and trades that
  would put a card straight into its place are left alone: Gather sorts, it never solves. It is not a
  move; Undo takes it back. (`gatherInto` in `lib/game/gather.dart`.)
- **Peek** (10 coins on every board; owner, 2026-10-14: no free Peek on giant boards): every card not in place flies to its place,
  the picture shows (3.2 s on a giant board, 2.4 s elsewhere) and the cards fly back, each a little
  later than the last, so the picture builds itself in a ripple. Using it still counts for the
  "without Peek" quests.

### The other tools

- **Pinch to zoom, two fingers to move; one finger plays as usual.** Tap-tap and drag work at
  every zoom, and a selected card stays selected while zooming and panning. The zoom changes only
  when the player asks (no automatic zoom: a top complaint elsewhere).
- **Double tap to zoom** in at that card, double tap again for the whole board (PuzzleTouch). Taps
  go through at once: the second tap of a double tap undoes the first one's select or deselect, so
  tap-tap moves never wait.
- **A zoom limit per board** (`BoardZoom.fitCell`): a card reaches about 96 pt on screen at most,
  so the 100-card board stops near 2.5x and the 300-card board at 4x. Never so close that only two
  cards show.
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
- An Edges switch (fade every card whose place is not on the outline) was tried and removed by the
  owner on 2026-10-14.

Code: Gather in `lib/game/gather.dart`; `BoardZoom`, the board's gestures and Peek's flight in
`lib/features/game/board_widget.dart`; the bar (Locate, Gather, map, zoom), the map, the pointer and
the milestones in `lib/features/game/giant_board.dart`; the saved views, the map and Locate switches
and the Locate tip in `lib/state/giant.dart`. Tests: `test/gather_test.dart`, `test/giant_ux_test.dart`.
QA: `integration_test/giant_ux_test.dart` and `integration_test/giant_tools_test.dart` play the real
Giant pack.
