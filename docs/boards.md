# Board sizes

Owner, 2026-10-17, from TestFlight: "Smallest board is sometimes 3x3 and sometimes 3x4. I don't like
such surprise." Until then every size followed the picture's proportions (a 3:4 picture got 3x3, a
square one 4x3). Now a size deals the same board for every picture: as many pieces across as down,
in every mode. A picture of another shape is centre-cropped to the board, and the difficulty screen's
preview shows exactly the part that is played. **Expand** deals the same sizes laid out for the
picture instead, so the whole picture is played.

Code: `BoardSpec` and `BoardLayouts` in `lib/game/board.dart`; the switch in
`lib/features/game/difficulty_screen.dart` (`_ExpandTile`). Tests: `test/square_boards_test.dart`,
`test/board_layout_test.dart`, `test/preset_pieces_test.dart`, `test/giant_boards_test.dart`,
`test/difficulty_screen_test.dart`; on the simulator `integration_test/square_boards_test.dart` and
`integration_test/preset_pieces_test.dart`.

## Square boards (the default)

| Size | Cards | Squares | Triangles | Hexagons | Opens at level |
| --- | --- | --- | --- | --- | --- |
| Cozy | 3x3 (9) | 3x3 (9) | 3x3 (19 + 2 pre-set) | - | 1 |
| Relaxed | 4x4 (16) | 4x4 (16) | 4x4 (36) | 4x4 (14 + 4 pre-set) | 1 |
| Tricky | 5x5 (25) | 5x5 (25) | 5x5 (55) | 5x5 (27) | 3 |
| Expert | 6x6 (36) | 6x6 (36) | 6x6 (78) | 6x6 (37 + 2 pre-set) | 7 |
| Master | 7x7 (49) | 7x7 (49) | 7x7 (105) | 7x7 (52) | 10 |

- **One name per side in every mode** (`BoardSpec.squareTierOfSide`), so switching modes keeps the
  board: 5x5 is Tricky everywhere. The Cards counts are the Cards ladder's square steps (Master was
  6x8, 48), so quests, unlock levels, early-unlock prices and what a size pays stay as they were for
  Cards.
- **N columns and N rows** (`BoardSpec.squareDims`). A triangle column is one up and one down
  triangle (owner, 2026-10-17): a row of N columns holds 2N + 1 pieces (2N - 1 whole triangles and a
  half at each end), so the board is about as wide as it is tall (2:√3) and has about 2N² pieces;
  the chips read "4x4" for a board of 9 x 4 pieces (`BoardSpec.size`). Those counts are close to what
  Triangles had per size before square boards (42, 60, 88, 108 on a 3:4 picture). Squares and
  Hexagons have about N² pieces (they had up to 80 and 84 at Master); each mode's multiplier pays for
  its shapes.
- **Pre-set pieces** (below) fill the sizes some shapes could not deal before: Triangles 3x3,
  Hexagons 4x4 and 6x6. Hexagons have no 3x3 (below); Cozy gives the 4x4 honeycomb there (the
  nearest size, a tie the bigger: `BoardSpec.nearest`), which is open from level 1 like every
  Relaxed board.
- **Joined pairs at the start**: no board starts with a card in place, and almost none with a joined
  pair. With five rows of triangles each side edge's halves cannot all leave their neighbours (of
  the two orders that move all three halves of a shape, each joins one pair), so the 5x5 triangle
  board keeps one joined pair of halves on each side edge, the fewest it can. The 4x4 honeycomb keeps
  one pair in its bottom row of three (between its pre-set corners; a row of three of one shape
  always keeps two side by side in order). `Tiling.unavoidableJoins`, the last resort of
  `Board.shuffled`; every other board starts with none.
- **Ends at 7x7**: seven across keeps cards about 55 pt wide on a phone (54 pt on a 402 pt iPhone,
  50 on the SE); a 7x7 triangle is 54 pt wide at the base. Bigger boards are giant boards.
- **Board shapes**: Cards boards are 5:7 portrait, Squares square, Triangles a little wider than tall
  (2:√3), Hexagons wide (about 5:4: rows of a honeycomb overlap).
- Easy, Medium and Hard have no square board. Levels 2 and 5 no longer name a new size in the level
  rewards; the tiers stay for boards saved before and for unlocks bought for them.

## Pre-set pieces (owner, 2026-10-17)

Pieces never turn and only move within their shape (`Tiling.classOf`), so a piece no other piece
shares the shape of could only ever sit in its own place. Some square triangle and honeycomb boards
have such pieces along their edges. They were left out at first (owner: fill every size; drop one
only if a card would have to start in its place); cutting their edges into a zigzag instead was
turned down ("I don't want the image to look ugly in that weird final shape"). The owner's decision:
the board stays a proper rectangle, and those one-of-a-kind pieces are **pre-set**: they sit in their
place from the start, part of the picture's frame, and every other piece plays normally.

| Board | Pieces | Pre-set (slots) | Plays |
| --- | --- | --- | --- |
| Triangles 3x3 (7 x 3) | 21 | the middle row's two end halves (7, 13) | 19 |
| Hexagons 4x4 | 18 | the second row's two halves and the bottom row's corners (4, 8, 13, 17) | 14 |
| Hexagons 6x6 | 39 | the bottom row's corners (32, 38) | 37 |

With an even number of honeycomb rows the bottom row is a shifted one, so its corners are halves cut
at the bottom too. Three rows of triangles leave the middle row's halves alone (the 3x3 Expand board
of three rows, 5 x 3, has the same two).

- **Which**: `Tiling.isPreset` (a piece whose shape class has one member), worked out from the
  tiling, so every board that has such a piece (an Expand board, a board an older build saved) treats
  it the same way. No other square board and no giant board has any (`test/preset_pieces_test.dart`).
- **Drawn as placed**: a pre-set piece is a card in its place (`slots[i] == i`), so it is drawn like
  any card in place: edge to edge, in full colour under Painting, fused with the cards locked next to
  it. It is never picked or dragged (a tap is the usual "no" of a card in place), never moved by a
  move, a push, Magic, Shuffle or Gather, and no card is ever dealt or moved onto it (no other card
  has its shape).
- **Not counted**: "N/M locked", the progress bars (Home's Continue, the pack page, the board in
  progress on the difficulty screen, the sync's board choice) and what a board pays count only the
  pieces the player plays (`Board.lockedCount`, `playableCells`, `BoardSpec.progressOf`). Par is the
  fewest swaps, so pre-set pieces never added to it; moves and stars are as on any board. A deal
  reads 0 locked.
- **The deal**: "no card starts in place" now reads "no playable card starts in place"
  (`Board.shuffled`). The twin deal never counts a pre-set piece as a card on a twin's place.
- **Twins**: a twin has the same shape, so a pre-set piece never has one (docs/twins.md).
- **Saves and co-op**: a saved layout and a shared board hold every piece, pre-set ones in their own
  slots; `progress.gridSize` stays the full piece count (21, 18, 39), which names the board
  (`BoardSpec.fromSaved`, `fromCells`). A co-op change carries the slots it changes, and a pre-set
  slot never changes. Older builds have none of these sizes: they start such a saved picture fresh
  (the count is on none of their ladders), and an old save resumes here as before.
- **Quests** count a square board as its side squared (`BoardSpec.sizeCells`): the 3x3 triangle
  board is a 3x3, the 4x4 and 6x6 honeycombs a 4x4 and a 6x6. The "6x6 or bigger" achievement counts
  the 6x6 honeycomb (39 pieces) as before by piece count.
- **Hexagons 3x3 stays out**: of its ten pieces two would be pre-set (the middle row's halves), and
  the other eight have only four deals with none in place: both rows of three move one step along
  and the middle row's two whole hexagons trade places, so every deal starts with six joined pairs
  and is solved in one move (`test/preset_pieces_test.dart` tries all four). Cozy gives the 4x4
  honeycomb in Hexagons.

## Expand

- A switch in the Board section, under the sizes and above Painting: **Expand**, "Cut to fit the
  whole picture". The same sizes (same names and tiers) with the columns and rows that suit the
  picture, each aiming at its square board's piece count and never under 16, 25, 36 and 48 pieces
  for Relaxed, Tricky, Expert and Master (so it counts for the same quests and achievements).
  They are chosen the way sizes were chosen before (`BoardLayouts.expandFor`: least crop and
  stretch, piece count close to the target, portrait or square boards; a landscape picture is
  still cropped to a square board).
- **Shown only when it shows more of the picture**: at least 5% of its area more than the square
  board on some size (`BoardSpec.offersExpand`, `expandMinGain`). Hidden for a square picture in
  Squares, a 2:3 to 4:5 picture in Cards, a landscape picture in Squares and Hexagons, a 1:2 one in
  Triangles; hidden while a board is in progress and until the picture has been read.
- **Remembered** on the device with the board chosen with Play (`LastBoard.expand`, next to the
  mode, size and Painting); off until the player turns it on. A picture that does not offer it is
  dealt square boards, and the choice stays for the next picture. The game's Next puzzle and Quick
  play's Another picture keep it (`?expand=1`).
- Hexagons need more pieces to cover a portrait picture whole, so their Expand sizes run bigger
  than the square ones; every piece pays. Triangle Expand sizes are a whole number of columns wide
  too (rows of an odd number of pieces), so they read as columns x rows.
- **The sizes added with pre-set pieces** (Triangles 3x3, Hexagons 4x4 and 6x6) keep every other
  size's Expand board exactly as before (so a board saved with Expand resumes) and fill the gaps
  between them: a size at least 10% bigger than the one below and 10% smaller than the one above
  where there is one, else any size between. They choose from the usual shapes, three-row triangle
  boards (5 x 3, with its two pre-set halves) and their own square board, so Expand never crops
  more than the square board. Triangles 3x3 with Expand (5 x 4, 5 x 3 or the square 7 x 3) crops at
  most 10% of a 9:16 to square picture (the square board up to 46%). Small honeycombs cannot follow
  a portrait picture closely (the Relaxed floor of 16 pieces rules out the two-wide one): the 4x4
  Expand board (4 x 5, 22 pieces, or 4 x 7) crops up to 31% of a 9:16 to square picture, against 13
  to 51% for the square 4x4; the 6x6 one mostly under 10%, up to 35% around 5:8, where only a wide
  board fits between Tricky and Master (the square 6x6: 10 to 49%).
- The older sizes' Expand boards are older builds' own, so a board of theirs resumes there and here
  alike.

## Giant boards (Giant packs)

| | Large | Huge | Giant | Colossal |
| --- | --- | --- | --- | --- |
| Cards | 10x10 (100) | 12x12 (144) | 14x14 (196) | 17x17 (289) |
| Squares | 13x13 (169) | 15x15 (225) | 18x18 (324) | 22x22 (484) |
| Triangles | 10x10 (210) | 13x13 (351) | 15x15 (465) | 18x18 (666) |
| Hexagons | 13x13 (175) | 15x15 (232) | 19x19 (370) | 23x23 (540) |

The square nearest each old giant target (`BoardSpec.giantTargets`) that the tiling can deal
(`giantSquareSides`). Their rows are many and odd where it matters (triangles 13 and 15, honeycombs
13 to 23), so every shape occurs many times: no giant board has a pre-set piece. Every giant board has more pieces than any normal one
(`BoardLayouts.giantFloor`), so a saved piece count names the giant ladder (and counts as giant
boards used for `OpenFeatures`). Expand on a giant picture deals the giant ladder older builds dealt
(`BoardSpec.giantTiers`). More in `docs/giant-boards.md`.

## Codes, links, saves and older builds

- **Codes** stay `mode:CxRtT` (routes `/game/<id>/<mode>-CxRtT`). A board other than its tier's
  square board is an Expand board; `?expand=1` on `/game` and `/play` marks a square one as chosen
  with Expand. Old codes and links (`hexagons-5x6`, `cards-3x4t1`) open the tier they name, as
  Expand boards; a quest's `5x5` is the square Tricky board.
- **Saves** are unchanged: `progress.gridSize` (pieces), `mode` and `layout`. A save is found by its
  piece count (`BoardSpec.fromSaved`): the square boards, then the picture's Expand sizes, then the
  ladder older builds dealt (`BoardSpec.tiers`). A board an older build saved therefore resumes
  exactly as it was (a 3x4 stays 3x4, as an Expand board). Where two boards of a picture have the
  same count (the 4x4 triangle board, 9 x 4 pieces, and the old 6x6 strip, both 36), the saved layout
  names the one it fits: the two boards' pieces have different shapes in different places
  (`Board.isValidLayout`). The tests check every board of pictures from 1:2 to landscape.
- **Older builds reading this build's rows** look the piece count up on their own ladder: a square
  board's count is either not on it (the board is not resumed and the picture starts fresh: every
  square triangle board and both honeycombs, which older builds never dealt, and any size their
  ladder for that picture lacks), or names that very board (Cards and Squares where their ladder had
  the same N x N), or names another board whose shapes the saved layout does not fit (the 36-piece
  triangle board and the old 6x6 strip), which older builds check before resuming, so they start
  fresh. Expand boards likewise. Nothing breaks; at worst an older build starts that picture over.
  The square boards with pre-set pieces (21, 18 and 39 pieces) are on no older ladder, so older
  builds start those pictures fresh; an Expand board of those sizes is on none either or is the very
  board an older build's ladder has (`test/square_boards_test.dart` checks every picture shape
  against older builds' square, Expand and old boards).
- **Quests** that name a size ("a 4x4 or bigger board") count a square board as its side squared
  (`BoardSpec.sizeCells`: the 4x4 triangle board has 36 pieces, the 7x7 honeycomb 52, the 4x4 one
  18 with its pre-set pieces) and any other board by its pieces. New size quests name square sizes (`GridSpec.square`); quest keys made before
  (`size-4x5`) still read, and their shortcut opens the next square size up (`GridSpec.atLeast`).
