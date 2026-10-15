---
name: store-screenshots
description: Make, change or refresh Carden's App Store screenshots (the ten-slide glass set) - capture the app on the simulator, compose the slides with tools/store/compose_glass.py, check them, preview them for the owner and upload them only when asked. Use for any request about store screenshots, their copy, layout, glass panes, a new slide or new app screens in them.
---

# App Store screenshots (the glass set)

Ten 1320 x 2868 slides for the App Store "iPhone 6.9-inch Display" slot, in
`store/screenshots/iphone-6.9/01.png` ... `10.png`. Everything is generated: edit the sources and
rerun, never hand-edit a PNG. Research, story and design rules: `docs/store-screenshots.md`
("Glass set"); step-by-step commands: `store/README.md`.

## The pieces

| What | Where |
| --- | --- |
| The slides: copy, order, layout, which capture each phone shows, lifted cards, picture rows | `SLIDES` at the top of `tools/store/compose_glass.py` |
| Pane colours and glass strength | `GLASS_BASE`, `PANE_COLOURS`, `BODY_OPACITY`, `SHADOW_OPACITY`, `panes()` in the same file |
| The look (glass panes in SVG, headline, phones, lifted cards, picture rows) | `tools/store/glass/slides.html` (filled in and rendered by the script) |
| Phone frame and clean 9:41 status bar | `phone()` / `draw_status_bar()` in `tools/store/compose_screenshots.py` (the older dark gallery composer; both share it) |
| App captures | `integration_test/store_screenshots_test.dart` + `test_driver/store_screenshots.dart` -> `store/raw/` (git-ignored) |
| Pack covers for slide 2 | `store/collage/` (`compose_screenshots.py --refresh-collage`) |
| Upload | `.venv/bin/python tools/store/asc_publish.py screenshots` (replaces only changed slides) |

## The story (owner approved, 2026-10-16)

Read in order the headlines are one text, in three acts: the hook (1-3, what search results show),
the depth (4-8), the close (9-10).

1. Swap cards. / Reveal the picture. (icon + name; `25_hero`)
2. Thousands / of pictures (`15_library`, covers beside it and in a row)
3. A new picture / every day (`18_daily_month_grid`, today's card lifted)
4. One picture, / four ways to cut it (`09_mode_hexagons`, the other three shapes lifted)
5. Bring the colour / back, card by card (`26_painting`, a loose grey and a locked colour card)
6. Giant boards of / up to 300 cards (`27_giant`, the overview map lifted)
7. Puzzle your / own photos (`20_my_puzzles`, the corgi board lifted)
8. Quests and / world-day events (`13_quests`, the World Food Day card lifted)
9. Open every pack / with VIP (`12_store_vip`, the trial lifted, locked packs of `28_library_more` below)
10. Just as calm / in the dark (`03_game_cards` in the dark theme)

Before changing the story, write the new running order as text and check it reads as one story;
every claim must be true in the code or the live catalogue (copy voice: `docs/copy-guide.md`).

## Workflow

1. **Captures.** Light captures for slides 1-9, dark for slide 10. Uninstall first (the test needs
   a fresh guest), always through `tools/dev/qa-run.sh` (silent, flagged, purged):
   ```sh
   U=D03644FB-6169-4E87-8E0F-CCFC884FBE78   # iPhone 17 Pro Max
   xcrun simctl uninstall $U com.matejbaco.cardjigsawworld
   tools/dev/qa-run.sh drive --driver=test_driver/store_screenshots.dart \
     --target=integration_test/store_screenshots_test.dart -d $U \
     --dart-define=CJW_STORE_THEME=light --dart-define=CJW_STORE_SKIP_UPLOAD=true
   ```
   About 13 minutes. `--dart-define=CJW_STORE_ONLY=25_hero,27_giant` re-takes only those glass
   captures (25-28) in about 4 minutes. Drop `CJW_STORE_SKIP_UPLOAD` only when the My Puzzles
   captures (20, 21) must change: it uploads four photos to live Storage. Without
   `CJW_STORE_THEME` the run writes the dark captures (slide 10).
2. **Look at every new capture** before composing (contact sheet with Pillow). Check the board
   reads as a nearly whole picture, nothing private shows, and the crop boxes in `SLIDES` still
   match (a recapture can move a card or a tile; draw a coordinate grid on the capture to pick
   boxes).
3. **Compose:** `.venv/bin/python tools/store/compose_glass.py` (all slides into the repo), or
   `... 3 5` for some, `--out /tmp/x --sheet /tmp/sheet.png` to try things without touching the
   set, `--font display|newyork` for the alternative headline faces (default SF Pro Rounded).
4. **Check** a contact sheet of all ten, then each changed slide at full size: headline fits and
   reads on the panes, nothing clipped at the edges, lifted cards line up with their phone, no
   empty band at the bottom, the set still reads as one strip.
5. **Show the owner** only the final slides (no before/after): a page of the ten images in order
   with a full-size view of each file (the session's artifact viewer; reuse its URL when there is
   one).
6. **Commit** the script, template, docs and `store/screenshots/iphone-6.9/` (paths, not `-A`).
7. **Upload only when the owner asks**: `asc_publish.py screenshots`. Apple shows one set for light
   and dark mode; there are no separate dark-mode screenshots.

## Lifted cards and rows (how SLIDES works)

- `out`: a card cut from a capture, `crop` = (capture, (l, t, r, b) in capture px) or (capture,
  "board") (board rects come from `store/raw/boards.json`). Without `x`/`y` the card centres
  itself over the same part of the phone's screen, so it never shows twice; with `x`/`y` it sits
  in phone pixels (0,0 = phone top-left). Cards live in the phone's frame, so they tilt with it.
- `pics`: pictures on the slide itself, pack covers (`covers`: indexes into `COLLAGE_PACKS`) or
  capture crops (`crops`), laid out by `fan()` as a neat arc or at fixed `spots`.
- Layouts: `A` headline on top + flat phone, `B` phone from the top edge + headline + a picture row
  (fill the bottom; an empty band looks unfinished), `C` tilted phone (7 degrees, alternate the
  direction). Keep slides 1-3 flat.

## Owner's rules for these slides

- White canvas with big panes of coloured glass (lotus colours) on every seam, drawn like the app
  icon's glass; overlaps mix like stained glass. Only the background crosses a seam.
- One phone size on every slide, several layouts, the real app on every slide.
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
