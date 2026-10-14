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

### Dealt by zone (owner feedback 2026-10-14: "feels impossible, cards are all over the place")

A giant board shuffled across all of its cards cannot be read on a phone: zoomed in, the cards in
view could belong anywhere among 300 places. Giant boards are therefore **dealt by zone**
(`lib/game/zones.dart`, `BoardZones`): the board is cut into zones of about a normal board each
(cards 30, squares 48, triangles 66, hexagons 52; zones as close to square as the board allows), and
every card is shuffled only inside its own zone. The smallest size (Large, 100 cards) has 4 zones,
Huge and Giant 6, Colossal 12. Zoomed in, what is in view belongs within a few cards of where it
lies, and one huge puzzle becomes a handful of normal ones that build one picture (what jigsaw
players do by sorting pieces into areas first).

- Faint lines (a thin light line over a soft dark one) run between the zones; the line between two
  finished zones goes, so finished areas merge into the picture. A finished zone's outline glows once
  and a toast says "Zone complete · 3 of 12". The overview map outlines the zones still to finish.
- The deal keeps the usual rules inside each zone: no card in place, no pair joined. Edge half
  pieces of triangle and hexagon boards that are too few in a zone to shuffle (fewer than 5) share a
  pool with the nearest zone, so those few may start one zone over.
- Zones depend only on the board (shape and size), so a saved board finds them again. A giant board
  saved before zones (shuffled across the whole board) plays on without zone lines
  (`BoardZones.dealtIn`); Restart deals it by zone. `GameState.zoned` carries the choice.

### Finding a card's place

- **Locate**: hold a card still for a moment (or pick it up to drag it) on a zoomed board and the
  overview map shows where it belongs: a ring there and a line from the card. It stays while the card
  is held, dragged or selected, and the map shows for it even when it is hidden. The first zoom on a
  giant board says so once ("Hold a card to see its place on the map"). Dragging towards the ring
  uses auto-pan, so one drag crosses the board.
- **Gather** (in the bar while zoomed in): every card that belongs in the view comes into it. Each
  card in view that belongs elsewhere trades places with one that belongs here, chosen so the card
  leaving lands as close to its own place as it can. Cards in place, joined groups and trades that
  would put a card straight into its place are left alone: Gather sorts, it never solves. It is not a
  move; Undo takes it back. (`gatherInto` in `zones.dart`.)
- **Peek is free on giant boards** (10 coins elsewhere): every card not in place flies to its place,
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
- **Milestones**: a calm toast for each zone finished, when the frame is complete and at halfway,
  once each per board (one toast per move: a zone, else the frame, else halfway).

Code: zones, the zoned deal and Gather in `lib/game/zones.dart`; `BoardZoom`, the board's gestures,
the zone lines, Locate and Peek's flight in `lib/features/game/board_widget.dart`; the bar, the map,
the pointer and the milestones in `lib/features/game/giant_board.dart`; the saved views and the
Locate tip in `lib/state/giant.dart`. Tests: `test/zones_test.dart`. QA:
`integration_test/giant_ux_test.dart` and `integration_test/giant_zones_test.dart` play the real
Giant pack.
