# Board sizes

Owner, 2026-10-17, from TestFlight: "Smallest board is sometimes 3x3 and sometimes 3x4. I don't like
such surprise." Until then every size followed the picture's proportions (a 3:4 picture got 3x3, a
square one 4x3). Now a size deals the same board for every picture: as many pieces across as down,
in every mode. A picture of another shape is centre-cropped to the board, and the difficulty screen's
preview shows exactly the part that is played. **Expand** deals the same sizes laid out for the
picture instead, so the whole picture is played.

Code: `BoardSpec` and `BoardLayouts` in `lib/game/board.dart`; the switch in
`lib/features/game/difficulty_screen.dart` (`_ExpandTile`). Tests: `test/square_boards_test.dart`,
`test/board_layout_test.dart`, `test/giant_boards_test.dart`, `test/difficulty_screen_test.dart`;
on the simulator `integration_test/square_boards_test.dart`.

## Square boards (the default)

| Size | Cards | Squares | Triangles | Hexagons | Opens at level |
| --- | --- | --- | --- | --- | --- |
| Cozy | 3x3 (9) | 3x3 (9) | - | - | 1 |
| Relaxed | 4x4 (16) | 4x4 (16) | 4x4 (14) | - | 1 |
| Tricky | 5x5 (25) | 5x5 (25) | - | 5x5 (27) | 3 |
| Expert | 6x6 (36) | 6x6 (36) | 6x6 (36) | - | 7 |
| Master | 7x7 (49) | 7x7 (49) | 7x7 (49) | 7x7 (52) | 10 |

- **One name per side in every mode** (`BoardSpec.squareTierOfSide`), so switching modes keeps the
  board: 5x5 is Tricky everywhere. The piece counts are the Cards ladder's square steps (Master was
  6x8, 48), so quests, unlock levels, early-unlock prices and what a size pays stay as they were for
  Cards. Squares, Triangles and Hexagons used to have more pieces per size (up to 80, 108 and 84 at
  Master); now every mode has about N x N pieces and its multiplier pays for the harder shapes.
- **Gaps**: a strip of three or five rows of triangles, and a honeycomb with an even number of rows
  or three across, cannot be shuffled without a piece in place or a joined pair (`TriangleTiling`,
  `HexTiling`). Triangles therefore deal 4x4, 6x6 and 7x7, Hexagons 5x5 and 7x7. A size a mode lacks
  gives the nearest one, a tie the bigger (`BoardSpec.nearest`: Tricky in Triangles is 6x6), and a
  shape's smallest size is always open (Hexagons' 5x5 is a level 3 size).
- **Ends at 7x7**: seven across keeps cards about 55 pt wide on a phone (54 pt on a 402 pt iPhone,
  50 on the SE). Bigger boards are giant boards.
- **Board shapes**: Cards boards are 5:7 portrait, Squares square, Triangles tall (about 1:2: a row
  of N pieces is (N - 1) half triangles wide), Hexagons wide (about 5:4: rows of a honeycomb
  overlap).
- Easy, Medium and Hard have no square board. Levels 2 and 5 no longer name a new size in the level
  rewards; the tiers stay for boards saved before and for unlocks bought for them.

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
- Triangles and hexagons need more pieces to cover a portrait or square picture whole (a square
  board of triangles has at least 28), so their Expand sizes run bigger than the square ones; they
  pay for every piece.

## Giant boards (Giant packs)

| | Large | Huge | Giant | Colossal |
| --- | --- | --- | --- | --- |
| Cards | 10x10 (100) | 12x12 (144) | 14x14 (196) | 17x17 (289) |
| Squares | 13x13 (169) | 15x15 (225) | 18x18 (324) | 22x22 (484) |
| Triangles | 15x15 (225) | 18x18 (324) | 21x21 (441) | 26x26 (676) |
| Hexagons | 13x13 (175) | 15x15 (232) | 19x19 (370) | 23x23 (540) |

The square nearest each old giant target (`BoardSpec.giantTargets`) that the tiling can deal
(`giantSquareSides`). Every giant board has more pieces than any normal one
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
  exactly as it was (a 3x4 stays 3x4, as an Expand board). A piece count never names two different
  boards of one picture, which the tests check for pictures from 1:2 to landscape.
- **Older builds reading this build's rows** look the piece count up on their own ladder: a square
  board's count is either not on it (the board is not resumed and the picture starts fresh: the 4x4
  triangle strip and both honeycombs, which older builds never dealt, and any size their ladder for
  that picture lacks) or names that very board (Cards and Squares where their ladder had the same
  N x N). Expand boards likewise. Nothing breaks; at worst an older build starts that picture over.
- **Quests** that name a size ("a 4x4 or bigger board") count a square board as its side squared
  (`BoardSpec.sizeCells`: the 4x4 triangle strip has 14 pieces, the 7x7 honeycomb 52) and any other
  board by its pieces. New size quests name square sizes (`GridSpec.square`); quest keys made before
  (`size-4x5`) still read, and their shortcut opens the next square size up (`GridSpec.atLeast`).
