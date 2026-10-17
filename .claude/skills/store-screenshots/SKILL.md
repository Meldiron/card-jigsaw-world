---
name: store-screenshots
description: Make, change or refresh Carden's App Store screenshots (the glass set) - capture the app on the simulator, compose the slides with tools/store/compose_glass.py, check them, preview them for the owner and upload them only when asked. Use for any request about store screenshots, their copy, layout, glass panes, a new slide or new app screens in them.
---

# App Store screenshots (the glass set)

Ten 1320 x 2868 slides (Apple's maximum) for the App Store "iPhone 6.9-inch Display" slot, in
`store/screenshots/iphone-6.9/01.png` ... `10.png`. Everything is generated: edit the sources and
rerun, never hand-edit a PNG. Research, story and design rules: `docs/store-screenshots.md`
("Glass set"); step-by-step commands: `store/README.md`.

## The pieces

| What | Where |
| --- | --- |
| The slides: copy, order, headline position, phones and their placement, lifted cards, pictures | `slides()` near the top of `tools/store/compose_glass.py` (each with a `key` the custom pages reuse it by; `EXTRA_SLIDES` keeps slides out of the set) |
| Pane colours and glass strength | `GLASS_BASE`, `PANE_COLOURS`, `BODY_OPACITY`, `SHADOW_OPACITY`, `panes()` in the same file |
| The look (glass panes in SVG, headline, phones, lifted cards, picture rows) | `tools/store/glass/slides.html` (filled in and rendered by the script) |
| Phone frame and clean 9:41 status bar | `phone()` / `draw_status_bar()` in `tools/store/compose_screenshots.py` (the older dark gallery composer; both share it) |
| App captures | `integration_test/store_screenshots_test.dart` + `test_driver/store_screenshots.dart` -> `store/raw/` (git-ignored) |
| Pack covers for slide 2 | `store/collage/` (`compose_screenshots.py --refresh-collage`) |
| Upload | `.venv/bin/python tools/store/asc_publish.py screenshots` (replaces only changed slides) |

## The story (owner approved 2026-10-16; Play together added for 2.0.0, 2026-10-17)

Read in order the headlines are one text: the hook (1-3: how it plays, how much there is, playing it
together; what search results show), why you come back and the depth (4-9), the dark finale (10). No VIP
slide (the owner does not want to talk about VIP here), no AI pictures anywhere. Apple takes 10 slides, so
Play together replaced "Climb the ranks with friends" (the leaderboard; kept as `EXTRA_SLIDES` key
`league` for custom pages).

| # | Headline | Headline position | Phones |
| --- | --- | --- | --- |
| 1 | Swap cards. / Reveal the picture. | top, centre, icon + name | `25_hero` (Tulip Fields 8) flat, mid-build |
| 2 | Thousands / of pictures | top, centre | one straight row of full-resolution pack covers running off both edges (endless); `15_library` (curated packs, scrolled one row so no My Puzzles tile shows) rising from the bottom edge |
| 3 | Play together / with friends | top, left | `32_coop_board` (a scripted game, no live backend, the host named Mia by `storePlayerName`: Bora Bora lagoon in Cards 7x7 Master mid-build (the middle and two corners locked, a few groups), the players chip, Leo's purple "L" on the cards he moved, Ava's orange "A" on the card she holds) flat, pushed right; Ava's card (`COOP_HELD`) lifted on the left, the player list of `33_coop_players` (`COOP_LIST`: colour rings, Host · You, Here, Remove) lifted over the toolbar just under the board |
| 4 | A new picture / every day | top, right | `18_daily_month_grid` flat, pushed left, today's card and Home's 23-day streak card (`31_home_streak`, straight, low) lifted; two solved days on the right |
| 5 | One picture, / four ways to cut it | middle | split: `06_mode_cards` from the top, `09_mode_hexagons` from the bottom, squares and triangles lifted; big mode badges on the edge of each board or card that faces the headline |
| 6 | Bring the colour / back, card by card | lower middle | `26_painting` straight and centred from the top (owner: no tilt here), mostly grey; a loose and a locked card lifted |
| 7 | Giant boards of / hundreds of cards | top, left | Squares, Giant size (18x18 = 324 squares): `30_giant_zoom` (zoomed in, the overview map in the corner) tilted, pushed right; the whole board of `27_giant` lifted |
| 8 | Puzzle your / own photos | bottom, right | `20_my_puzzles` (five photos, no gap) pushed left, the corgi board lifted on the right |
| 9 | Quests and / world-day events | top, centre | `13_quests` tilted, the World Food Day card lifted, cut exactly at its own edges and corners |
| 10 | Just as calm / in the dark | top, centre | `29_dark_board` (dark theme) flat, mid-build |

The player grows from slide to slide: the capture test sets XP, level and avatar before each
screen with a header (`setProgress()`: level 4 and the leaf avatar in the Library, 9 and the
flower on Quests, 17 and the diamond on the leaderboard, which the website and the `league` slide
still use), and a 23-day streak for Home.

Boards in play are shown mid-build and clearly unfinished: about a third locked, the rest loose,
two or three joined groups (`midBuild()` in the capture test; the owner asked twice for less
finished boards). Pictures are chosen, not left to chance ("mocked"): the hero, Painting, giant and
My Puzzles pictures are fixed ids at the top of the test (high resolution, public domain or CC0,
no people, no AI), and `libraryFirst` puts the strongest pack covers first in the Library (a
`packsProvider` override that only changes the order). My Puzzles gets five photos, so the grid
with its Add photo tile has no empty slot. Before changing the story, write the new running order as text and check it
reads as one story; every claim must be true in the code or the live catalogue (copy voice:
`docs/copy-guide.md`).

## Workflow

1. **Captures.** Light captures for slides 1-9, dark for the last slide. Uninstall first (the test needs
   a fresh guest), always through `tools/dev/qa-run.sh` (silent, flagged, purged):
   ```sh
   U=D03644FB-6169-4E87-8E0F-CCFC884FBE78   # iPhone 17 Pro Max
   xcrun simctl uninstall $U com.matejbaco.cardjigsawworld
   tools/dev/qa-run.sh drive --driver=test_driver/store_screenshots.dart \
     --target=integration_test/store_screenshots_test.dart -d $U \
     --dart-define=CJW_STORE_THEME=light --dart-define=CJW_STORE_SKIP_UPLOAD=true
   ```
   About 13 minutes. `--dart-define=CJW_STORE_ONLY=25_hero,27_giant` re-takes only those glass
   captures (15_library, 22_social_league, 25-33; 32 brings 33 with it) in about 4 minutes; such a run plays a level-1 guest, so board sizes past
   Relaxed are locked there (giant sizes are open). Drop `CJW_STORE_SKIP_UPLOAD` only when the My Puzzles
   captures (20, 21) must change: it uploads four photos to live Storage. Without
   `CJW_STORE_THEME` the run writes the dark captures (the last slide: `CJW_STORE_ONLY=29_dark_board`).
2. **Look at every new capture** before composing (contact sheet with Pillow). Check the board
   reads as a nearly whole picture, nothing private shows, and the crop boxes in `SLIDES` still
   match (a recapture can move a card or a tile; draw a coordinate grid on the capture to pick
   boxes).
3. **Compose:** `.venv/bin/python tools/store/compose_glass.py` (all slides into the repo), or
   `... 3 5` for some, `--out /tmp/x --sheet /tmp/sheet.png` to try things without touching the
   set, `--font display|newyork` for the alternative headline faces (default SF Pro Rounded).
4. **Contrast:** `.venv/bin/python tools/store/compose_glass.py --contrast` renders each slide
   without its headline and measures the ink against the darkest 2% behind each line (the
   brightest for the dark slide). Every slide must reach 4.5:1; if one is low, move a pane away
   from the headline (`panes()`), switch its colour, or move the headline, keeping the colour
   balance across the strip.
5. **Check** a contact sheet of the whole set, then each changed slide at full size: headline fits and
   reads on the panes, nothing clipped at the edges, lifted cards line up with their phone, no
   empty band at the bottom, the set still reads as one strip.
6. **Show the owner** only the final slides (no before/after): a page of the images in order
   with a full-size view of each file (the session's artifact viewer; reuse its URL when there is
   one).
7. **Commit** the script, template, docs and `store/screenshots/iphone-6.9/` (paths, not `-A`).
8. **Upload only when the owner asks**: `asc_publish.py screenshots`. Apple shows one set for light
   and dark mode; there are no separate dark-mode screenshots.

## How a slide is described (slides() in compose_glass.py)

- `text`: (anchor, y, align): the headline's top, bottom or centre at y; left, centre or right.
  Vary it from slide to slide: the owner found "headline on top, phone below" on every slide boring.
- `phones`: one or two phones, all the same size, each with x, y (top-left, may run off an edge)
  and `rot`. `out` = cards lifted from a capture (`crop` = (capture, box) or (capture, "board");
  without x/y a card centres over the same part of the screen; with x/y it sits in phone px);
  `tags` = small labels in phone px. Cards and tags turn with their phone.
- `pics`: pictures behind the phones: pack covers at full resolution (`packs`: pack ids, fetched by
  `cover()`), the small collage covers (`covers`) or capture crops, laid out as a `hand` of cards,
  a `masonry` wall, a `fan` row or at fixed `spots`. Fill the slide; empty bands look
  unfinished.
- `cell()` and `board_part()` give crop boxes of a board from `store/raw/boards.json`.

## Owner's rules for these slides

- White canvas with big panes of coloured glass (lotus colours) on every seam, drawn like the app
  icon's glass; overlaps mix like stained glass. Only the background crosses a seam.
- One phone size on every slide, varied layouts (headline top, bottom, middle, left, right), the
  real app on every slide, boards mid-build (locked, loose and joined cards).
- No AI art and no VIP talk on the slides; the Library capture is scrolled past the AI packs.
- Headlines only: two short lines, big, SF Pro Rounded. No subtext, no halo or glow behind text.
- A lifted card is cut exactly at the edges and corners of the app's own card (no extra rounding
  cutting into it); the player levels up across the slides.
- Light app on light slides; one dark finale shows dark mode.
- No emoji, ratings, awards, download prompts or web addresses on the slides.

## Pitfalls seen

- `flutter drive` sends every screenshot at the end of the run: no files appear until the test
  finishes. A run stuck on a white simulator screen after "Xcode build done" never connected:
  stop it, `xcrun simctl shutdown/boot` the simulator, uninstall, rerun.
- Check for leftover `flutter_tester` processes after test runs (`ps aux | grep flutter_tester`);
  one left from a `flutter test` run once took 25 GB of memory.
- Captures are 16-bit PNGs; read them with Pillow `.convert("RGB")` (OpenCV needs
  `IMREAD_UNCHANGED` and a 65535 scale).
- Headless Chrome paints a little less than its window height; the script renders in a taller
  window and crops. Output is RGB without alpha, as App Store Connect requires.
- `store/raw/` is git-ignored: a fresh machine has to run the captures before composing.
- The difficulty screen remembers Painting from the last board: before 2026-10-17 the giant and
  dark-finale boards came out grey because the Painting capture ran just before them. `startGame`
  now sets Painting to what each capture asks for; look for grey boards after any reorder.
- A mid-build board can leave fewer than two single cards, so the co-op scene falls back to any loose
  card for Leo's move and Ava's hold. Ava's card moves from run to run: the test records its
  rectangle (`32_coop_held[_light]` in `boards.json`) and the slide crops `"rect:32_coop_held"`.
