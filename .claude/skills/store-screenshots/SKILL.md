---
name: store-screenshots
description: Make, change or refresh Carden's App Store screenshots (the glass set) - capture the app on the simulator, compose the slides with tools/store/compose_glass.py, check them, preview them for the owner and upload them only when asked. Use for any request about store screenshots, their copy, layout, glass panes, a new slide or new app screens in them.
---

# App Store screenshots (the glass set)

Nine 1320 x 2868 slides for the App Store "iPhone 6.9-inch Display" slot, in
`store/screenshots/iphone-6.9/01.png` ... `09.png`. Everything is generated: edit the sources and
rerun, never hand-edit a PNG. Research, story and design rules: `docs/store-screenshots.md`
("Glass set"); step-by-step commands: `store/README.md`.

## The pieces

| What | Where |
| --- | --- |
| The slides: copy, order, headline position, phones and their placement, lifted cards, pictures | `slides()` near the top of `tools/store/compose_glass.py` |
| Pane colours and glass strength | `GLASS_BASE`, `PANE_COLOURS`, `BODY_OPACITY`, `SHADOW_OPACITY`, `panes()` in the same file |
| The look (glass panes in SVG, headline, phones, lifted cards, picture rows) | `tools/store/glass/slides.html` (filled in and rendered by the script) |
| Phone frame and clean 9:41 status bar | `phone()` / `draw_status_bar()` in `tools/store/compose_screenshots.py` (the older dark gallery composer; both share it) |
| App captures | `integration_test/store_screenshots_test.dart` + `test_driver/store_screenshots.dart` -> `store/raw/` (git-ignored) |
| Pack covers for slide 2 | `store/collage/` (`compose_screenshots.py --refresh-collage`) |
| Upload | `.venv/bin/python tools/store/asc_publish.py screenshots` (replaces only changed slides) |

## The story (owner approved, 2026-10-16)

Read in order the headlines are one text: the hook (1-3, what search results show), the depth
(4-8), the dark finale (9). No VIP slide (the owner does not want to talk about VIP here), no
leaderboard, no AI pictures anywhere.

| # | Headline | Headline position | Phones |
| --- | --- | --- | --- |
| 1 | Swap cards. / Reveal the picture. | top, centre, icon + name | `25_hero` flat, mid-build |
| 2 | Thousands / of pictures | bottom, centre | `28_library_more` (Library past the AI packs) flat, in front of a masonry wall of pack covers |
| 3 | A new picture / every day | top, right | `18_daily_month_grid` flat, pushed left, today's card lifted; solved days with stars down the right |
| 4 | One picture, / four ways to cut it | middle | split: `06_mode_cards` from the top, `09_mode_hexagons` from the bottom, squares and triangles lifted, labels |
| 5 | Bring the colour / back, card by card | lower middle | `26_painting` tilted from the top, mostly grey; a loose and a locked card lifted |
| 6 | Giant boards of / up to 300 cards | top, left | `27_giant` (Hölderlin Tower, 210 tiny cards, a small part solved) tilted, pushed right, a close-up lifted |
| 7 | Puzzle your / own photos | bottom, left | `20_my_puzzles` pushed right, the corgi board lifted |
| 8 | Quests and / world-day events | top, centre | `13_quests` tilted, the World Food Day card lifted |
| 9 | Just as calm / in the dark | top, centre | `29_dark_board` (dark theme) flat, mid-build |

Boards in play are shown mid-build: some cards locked, some loose, some joined (`midBuild()` in
the capture test). Before changing the story, write the new running order as text and check it
reads as one story; every claim must be true in the code or the live catalogue (copy voice:
`docs/copy-guide.md`).

## Workflow

1. **Captures.** Light captures for slides 1-8, dark for the last slide. Uninstall first (the test needs
   a fresh guest), always through `tools/dev/qa-run.sh` (silent, flagged, purged):
   ```sh
   U=D03644FB-6169-4E87-8E0F-CCFC884FBE78   # iPhone 17 Pro Max
   xcrun simctl uninstall $U com.matejbaco.cardjigsawworld
   tools/dev/qa-run.sh drive --driver=test_driver/store_screenshots.dart \
     --target=integration_test/store_screenshots_test.dart -d $U \
     --dart-define=CJW_STORE_THEME=light --dart-define=CJW_STORE_SKIP_UPLOAD=true
   ```
   About 13 minutes. `--dart-define=CJW_STORE_ONLY=25_hero,27_giant` re-takes only those glass
   captures (25-29) in about 4 minutes; such a run plays a level-1 guest, so board sizes past
   Relaxed are locked there (giant sizes are open). Drop `CJW_STORE_SKIP_UPLOAD` only when the My Puzzles
   captures (20, 21) must change: it uploads four photos to live Storage. Without
   `CJW_STORE_THEME` the run writes the dark captures (slide 9: `CJW_STORE_ONLY=29_dark_board`).
2. **Look at every new capture** before composing (contact sheet with Pillow). Check the board
   reads as a nearly whole picture, nothing private shows, and the crop boxes in `SLIDES` still
   match (a recapture can move a card or a tile; draw a coordinate grid on the capture to pick
   boxes).
3. **Compose:** `.venv/bin/python tools/store/compose_glass.py` (all slides into the repo), or
   `... 3 5` for some, `--out /tmp/x --sheet /tmp/sheet.png` to try things without touching the
   set, `--font display|newyork` for the alternative headline faces (default SF Pro Rounded).
4. **Check** a contact sheet of the whole set, then each changed slide at full size: headline fits and
   reads on the panes, nothing clipped at the edges, lifted cards line up with their phone, no
   empty band at the bottom, the set still reads as one strip.
5. **Show the owner** only the final slides (no before/after): a page of the images in order
   with a full-size view of each file (the session's artifact viewer; reuse its URL when there is
   one).
6. **Commit** the script, template, docs and `store/screenshots/iphone-6.9/` (paths, not `-A`).
7. **Upload only when the owner asks**: `asc_publish.py screenshots`. Apple shows one set for light
   and dark mode; there are no separate dark-mode screenshots.

## How a slide is described (slides() in compose_glass.py)

- `text`: (anchor, y, align): the headline's top, bottom or centre at y; left, centre or right.
  Vary it from slide to slide: the owner found "headline on top, phone below" on every slide boring.
- `phones`: one or two phones, all the same size, each with x, y (top-left, may run off an edge)
  and `rot`. `out` = cards lifted from a capture (`crop` = (capture, box) or (capture, "board");
  without x/y a card centres over the same part of the screen; with x/y it sits in phone px);
  `tags` = small labels in phone px. Cards and tags turn with their phone.
- `pics`: pictures behind the phones: pack covers (`covers`, indexes into `COLLAGE_PACKS`) or capture
  crops, as a `masonry` wall, a `fan` row or at fixed `spots`. Fill the slide; empty bands look
  unfinished.
- `cell()` and `board_part()` give crop boxes of a board from `store/raw/boards.json`.

## Owner's rules for these slides

- White canvas with big panes of coloured glass (lotus colours) on every seam, drawn like the app
  icon's glass; overlaps mix like stained glass. Only the background crosses a seam.
- One phone size on every slide, varied layouts (headline top, bottom, middle, left, right), the
  real app on every slide, boards mid-build (locked, loose and joined cards).
- No AI art and no VIP talk on the slides; the Library capture is scrolled past the AI packs.
- Headlines only: two short lines, big, SF Pro Rounded. No subtext, no halo or glow behind text.
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
