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
simulator `integration_test/twins_test.dart` (a sky) and `twins_night_test.dart` (a night sky). Evidence: `tools/dev/twins_report_test.dart` and
`tools/dev/twins_sheets.py` (below).

## The rules

1. **Twins look the same to the eye**, not "95% of pixels" (see the measure). A faint cloud, a wire,
   a bird or a speck on one card and not the other keeps them apart; noise and the faintest stars of
   a night sky do not (near black the eye tells much less apart).
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
- **Specks**: for every sample, how far its darkest and its lightest pixel stand out from its mean,
  and on a near-black sample how far its darkest and brightest 3 x 3 spot stand out by their glow
  (the brightest channel, so a red light trail counts like a white star), looking no further than
  the card's own pixels.

Two cards of one shape are compared sample by sample in CIELAB with **CIEDE2000** (ΔE00; about 1 is
a just-noticeable difference side by side). They are twins only when all of these hold:

| Limit | Value | Catches |
| --- | --- | --- |
| Mean ΔE00 of all samples | 1.0 | a lighter or bluer card (gradients: rows of a sky differ) |
| 95% of samples, and 95% of the outline's | 1.8 | a faint cloud or haze over part of the card, a band along an edge |
| Every sample | 3.0 | anything distinct |
| Speck: a sample's darkest or lightest pixel stands out more on one card | 1.6 lightness, or 3x the card's grain | a wire, a bird, a speck of dust; grainy cards may differ by their grain, which hides as much from the eye |
| Spot, on samples of both cards at L* 15 or less: the brightest or darkest 3 x 3 pixels stand out more on one card | 3.4 glow, or 3x the card's spot grain | a star that shows, a lamp, a lit window, a light trail; not sensor noise, JPEG blocks or the faintest stars |

### Near black and near white

Owner, TestFlight build 124 (Sydney Opera House night, 7x7 Cards): "Top right corner is all black,
as the picture is. The system that makes cards work when they are similar enough is not working,
or is still too strict." On that board no card had a twin: the night sky's cards differ by sensor
noise, JPEG chroma blocks and single-pixel stars, which CIEDE2000 and the pixel speck count in full
though nobody sees them on a phone. Near black the eye tells much less apart (low light, little
colour vision, and a screen's black level and reflections), so a difference between two colours
counts as seen (`TwinFinder.seen`):

- below L* 20 it counts less, down to 0.7 of itself at black (`darkBelow`, `darkFloor`), and their
  chroma counts less, down to a quarter at black (`darkChroma`: colour fades first in the dark);
- on samples of both cards at L* 15 or less a speck counts by its glow over 3 x 3 pixels instead of
  single pixels (`spotBelow`, `spotLimit`): a 1-pixel star loses most of its weight, a star that
  shows, a lamp, a window or a light trail does not;
- above L* 90 a difference counts a little less, down to 0.8 of itself at white (`brightAbove`,
  `brightFloor`): pale skies, snow and paper keep faint bands of a screen's whites and a photo's
  compression that the eye does not hold against each other. Specks on white count in full.

Evidence: the Sydney picture and 24 more of the darkest catalogue pictures (night cities, Milky Way,
aurora, fireworks, lanterns, nebulae) and 24 of the brightest (frost, snow, white walls, paper), on
every square board, with the contact sheets of the pairs nearest the limits.

| | Before | Now |
| --- | --- | --- |
| Sydney night, 7x7 Cards | no twins | 9 black cards in one class: 0, 1, 2, 3, 8, 11 (sky), 35, 42, 48 (water) |
| 25 dark pictures, boards with twins | Cards 16%, Squares 14%, Triangles 21%, Hexagons 16% | 33%, 28%, 43%, 38% |
| 25 dark pictures, cards that have a twin | 2.2% | 6.7% |
| 24 bright pictures | Cards 18%, Squares 8%, Triangles 15%, Hexagons 4% of boards with twins; 183 twin pairs | the same boards; 209 twin pairs |
| 83 pictures of the first sample (mid tones unchanged), boards with twins | Cards 25%, Squares 21%, Triangles 32%, Hexagons 27% | 28%, 24%, 35%, 29% (its dark backgrounds) |

On the Sydney board the cards that show something stay apart: the bridge's truss and lamp (5, 6),
its edge (4, 12, 13), a star (7) and a few stars together (14): `docs/images/twins-night-sydney.jpg`
shows each as on a phone and with the darks lifted 5x. Three tries were rejected by the sheets:
relaxing differences to half at black let the truss through; a spot limit of 4.5 let a firework's
thin red light trail and a launch tower's lattice through; measuring spots by lightness instead of
glow let the red trail through at 3.2. Sheets: `docs/images/twins-dark-accepted-borderline.jpg`,
`twins-dark-rejected-borderline.jpg`, `twins-dark-speck-rejected.jpg`,
`twins-bright-accepted-borderline.jpg`.

Cards are compared only when their mean colours are close (a pair whose means differ more than the
mean limit allows cannot pass), and a 4 x 4 grid of part colours rejects most other pairs at once,
so even a 666-piece board compares only the near pairs in full. Timings in a debug test run (the
app's release build is faster): a normal board 5 to 170 ms (a dark one up to about 250 ms: its
spots are read too), the sample's giant boards 220 to 575 ms, a synthetic 666-piece board with a
plain sky over a third of it about 1 s, and its deal with 222 twin cards 150 ms (measured once per
picture and board, in an isolate; the deal on the UI thread while "Dealing the cards" shows).

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
