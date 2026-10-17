# Twin cards

Owner, 2026-10-17: "Sometimes small pieces look almost identical, but they don't fit into place. We
should do a similarity check, and if it's > 95% or more, the move is marked as correct (linking or
placing into the correct place), invisibly swapping textures on the cards." Two patches of the same
plain sky are the usual case: the player puts one where the other belongs, it looks right, and the
board said no. Now cards that cannot be told apart are **twins**, and the board counts what it
shows.

Code: `lib/game/twins.dart` (`Twins`, `TwinFinder`), `lib/game/twins_loader.dart`
(`boardTwinsProvider`: reads the picture and measures off the UI thread), `Board.shuffled(twins:)`
in `lib/game/board.dart`, `shuffleLoose` / `gatherInto` / `canGather` in `lib/game/gather.dart`,
`GameController.useTwins` and `_apply` in `lib/game/game_controller.dart`, the widget keys and
`_TwinFade` in `lib/features/game/board_widget.dart`. Tests: `test/twins_test.dart`; on the
simulator `integration_test/twins_test.dart`. Evidence: `tools/dev/twins_report_test.dart` and
`tools/dev/twins_sheets.py` (below).

## The rules

1. **Twins look the same to the eye**, not "95% of pixels" (see the measure). A faint cloud, a wire,
   a bird or a speck on one card and not the other keeps them apart.
2. **Only cards of one shape** (`Tiling.classOf`: Cards and Squares have one; triangles up, down and
   each kind of half piece; hexagons whole and each kind of cut piece). A class of twins is a set in
   which every two cards are twins (built in card order, so every device builds the same classes).
3. **Only loose cards trade identities**: never a card in place, never a card in a joined group, so
   nothing the player built changes.
4. **Placing and joining.** After a move (a drop, a tap-tap, Magic), every card the move put
   somewhere new, in slot order:
   - **placed**: it sits on a twin's place, so it takes the identity of that place's card, which
     takes its identity where it waits (`Twins.settle`, first pass);
   - **joined**: it sits next to a neighbour where its twin belongs, so it takes the twin's identity;
     or the neighbour's twin belongs next to it, so the neighbour takes its twin's identity (second
     pass).

   Both cards of a trade must be loose. The twin that gives up its identity keeps its place and its
   look; if it then locks or joins where it waits, it already looked in place or joined there (it
   looks like the card it becomes), so that counts too. A board on which every card looks in place
   is finished (the last trades may then involve groups: the picture is complete).
5. **The deal, Shuffle and Gather never put a card on a twin's place, and avoid putting one where a
   twin would join a neighbour** (`Twins.looksPlaced`, `looksJoined`; the deal's repair
   `Board._untwin`, Shuffle's `untangle`, Gather's candidate filter). They are not moves, so nothing
   they do is counted by a trade. The deal leaves no pair looking joined (apart from the two pairs
   of halves a five-row triangle board always keeps; a giant board with a very large plain sky
   stops after three tries with the fewest it found); Shuffle and Gather avoid it where another
   order allows, as they already did for joined pairs (the small classes of edge halves on triangle
   and honeycomb boards leave some orders forced). Only a twin class covering more than half of its
   shape forces a card onto a twin's place: two of the three half pieces on an edge of a small
   triangle or honeycomb board, both plain sky. That card then starts in place (it takes its twin's
   identity), as it looks; in the sample below such a class occurred on 15 of 200 triangle boards
   and 11 of 100 honeycombs of the flattest pictures, never otherwise.
6. **The swap is invisible.** The two cards keep their places on screen and trade pictures that
   look the same: the controller keeps a widget key per card (`GameState.cardKeys`), so the card
   the player dropped keeps its widget where it landed, now showing its twin's picture, and the
   twin keeps its widget where it waits. The old picture fades out over the new one in 180 ms
   (`_TwinFade`), so not even a rendering difference flashes. It is a fade, kept under Reduce motion
   like every fade.

## The measure

`TwinFinder` reads the part of the picture the board shows (the same crop the board draws, the
1400 px decode, giant pictures at 2048 px) and samples every card the same way:

- **Boxes**: a grid over the card, about 4 px each (12 to 32 across, about 2 pt on screen), each the
  mean colour of its pixels, so grain and JPEG noise average out. A rectangle is covered edge to
  edge; other shapes keep the boxes wholly inside.
- **Outline strips**: each edge in pieces one box long, the outermost two pixels and the band inside
  them, where a line or the start of a neighbouring shape shows (a player compares the edges with
  the neighbours).
- **Specks**: for every sample, how far its darkest and its lightest pixel stand out from its mean.

Two cards of one shape are compared sample by sample in CIELAB with **CIEDE2000** (ΔE00; about 1 is
a just-noticeable difference side by side). They are twins only when all of these hold:

| Limit | Value | Catches |
| --- | --- | --- |
| Mean ΔE00 of all samples | 1.0 | a lighter or bluer card (gradients: rows of a sky differ) |
| 95% of samples, and 95% of the outline's | 1.8 | a faint cloud or haze over part of the card, a band along an edge |
| Every sample | 3.0 | anything distinct |
| Speck: a sample's darkest or lightest pixel stands out more on one card | 1.6 lightness, or 3x the card's grain | a wire, a bird, a speck of dust; grainy cards may differ by their grain, which hides as much from the eye |

Cards are compared only when their mean colours are close (a pair whose means differ more than the
mean limit allows cannot pass), and a 4 x 4 grid of part colours rejects most other pairs at once,
so even a 666-piece board compares only the near pairs in full. Timings in a debug test run (the
app's release build is faster): a normal board 5 to 170 ms, the sample's giant boards 220 to
575 ms, a synthetic 666-piece board with a plain sky over a third of it about 1 s, and its deal
with 222 twin cards 150 ms (measured once per picture and board, in an isolate; the deal on the
UI thread while "Dealing the cards" shows).

## The evidence (October 2026)

83 catalogue pictures: the 50 flattest of 462 sampled across every category (most plain sky, sea,
snow, walls, dark backgrounds), 25 picked at random from the rest, and 8 Giant pack pictures. Each
measured on every square board from 4x4 to 7x7 in every mode (14 boards; giant ones on their biggest
board in every mode), 1082 boards in all.

| Pictures | Boards with twins | Cards that have a twin (mean, most) |
| --- | --- | --- |
| 50 flattest | Cards 36%, Squares 30%, Triangles 46%, Hexagons 39% | 4 to 5%, at most 44% |
| 25 at random | 2 to 4% (2 pictures of 25) | 0.2%, at most 8% |
| 8 giant | Cards 5 of 8, other modes 2 of 8 | 1 to 5%, at most 13% |

So twins are rare in ordinary pictures and common where the content rules already warn (large plain
areas). The thresholds were set from contact sheets of the pairs nearest the limits (card A, card B,
their difference amplified 8x), looked at by eye: every pair just accepted looks the same, the
difference showing only grain or a smooth gradient; the pairs just rejected are mostly grain too (the
measure errs on the side of keeping cards apart). Two earlier versions were rejected by the sheets:
without the outline strips, a dark line at a card's very edge passed; with a fixed speck limit of 8
(then 3) faint wires across a sky, a bird and dust specks passed, so the speck limit follows the
card's grain. Sheets: `docs/images/twins-accepted-borderline.jpg`, `twins-rejected-borderline.jpg`,
`twins-speck-accepted.jpg`, `twins-speck-rejected.jpg`.

To measure again (pictures listed in a JSON file, see the tool's header):

```
TWINS_SAMPLE=sample.json TWINS_OUT=out flutter test tools/dev/twins_report_test.dart
.venv/bin/python tools/dev/twins_sheets.py out/twins_report.json out/sheets
```

## In the game

- **Measured once per picture and board** when the picture is decoded (`boardTwinsProvider`, kept
  30 s after the last use). A board dealt fresh waits for its twins under "Dealing the cards" (a
  moment longer: tens of milliseconds, up to a second on a giant board) and is dealt again with them
  before it shows (`GameController.useTwins`, `awaitsTwins`). A resumed board keeps its cards where
  they are. A picture that cannot be read in 8 s plays without twins.
- **Moves, par and stars**: a twin trade is not a move; the move that made it counts once, as
  always. Par stays as dealt, so twins can only make a board easier to finish in fewer moves. A lock
  by a twin trade is a lock (it counts for "Lock N cards in one move" and the double lock when the
  player's move locks two).
- **Saves, sync and co-op**: a board is still a permutation of card numbers; a trade only changes
  which number sits where, so saves and the save sync need no change. Every decision depends only on
  the board and the twin classes, never on chance. Co-op (later) sends the resulting changes; a
  device that applies another player's twin trade should exchange the two cards' widget keys too
  (`GameState.cardKeys`), or the two cards fly across the board.
- **Hints and Magic** still show and send a card's own place.
