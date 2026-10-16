# App Store assets

Everything in this folder is generated. Edit the sources under `tools/store/`
and the capture test, then rerun; do not hand-edit the PNGs.

Design rules (glass set, `tools/store/compose_glass.py`): panes of coloured
glass in the lotus colours on a white canvas, running across the whole set, light app
captures on a light canvas for slides 1-8 and a dark finale (slide 9), one
phone size, varied layouts, boards mid-build, no AI pictures, two-line headlines in SF Pro Rounded sized for
search-result thumbnails, no subtext, no emoji, no ratings or awards. The
older dark gallery style is still `tools/store/compose_screenshots.py`. The
research and reasoning are in `docs/store-screenshots.md`.

## Layout

| Path | What it is | Size |
| --- | --- | --- |
| `raw/*.png` | Untouched in-app captures from the iPhone 17 Pro Max simulator (6.9"), dark theme; `raw/*_light.png` the same screens in the light theme. Numbered in capture order; see the list below. | 1320x2868 |
| `raw/boards.json` | Board rectangle (physical px: left, top, width, height) of every game capture, written by the capture driver; the composer crops boards with it. | |
| `collage/*.jpg` | Pack covers for the slide-2 wall, downloaded from our Storage bucket (`--refresh-collage`; pack ids in `COLLAGE_PACKS`). | 600 px wide |
| `screenshots/iphone-6.9/01.png` ... `09.png` | Marketing screenshots for the App Store "iPhone 6.9-inch Display" slot. Upload in numeric order. | 1320x2868, RGB |
| `review/subscription-review.png` | Store screen scrolled to the "Carden VIP" card, for the App Store Connect subscription "Review screenshot" field (min 640x920). Same pixels as `raw/12_store_vip.png`. | 1320x2868 |
| `promo/app-icon-1024.png` | The app icon flattened to RGB (App Store rejects alpha). | 1024x1024 |
| `promo/vip-promotional-1024.png` | Promotional image for the VIP subscription (icon, "VIP" word mark, one-line benefit). | 1024x1024 |

Marketing slides (`screenshots/iphone-6.9/`), in upload order. Slides 1-3
appear in search results, so they carry the core loop, the catalogue and the
daily hook.

| Slide | Headline | Headline and phones | Shows (light captures unless noted) |
| --- | --- | --- | --- |
| `01.png` | Swap cards. Reveal the picture. | top + icon, flat phone | `raw/25_hero`: Painted lady mid-build (12 of 24 locked, two joined groups) |
| `02.png` | Thousands of pictures | bottom, flat phone on a wall of covers | `raw/28_library_more` (the Library past the AI packs) in front of a masonry wall of `collage/` covers |
| `03.png` | A new picture every day | top right, phone pushed left | `raw/18_daily_month_grid`, today's card lifted; three solved days with stars on the right |
| `04.png` | One picture, four ways to cut it | middle, two phones | `raw/06_mode_cards` from the top, `raw/09_mode_hexagons` from the bottom, squares and triangles lifted, all four labelled |
| `05.png` | Bring the colour back, card by card | lower middle, tilted phone from the top | `raw/26_painting`: Monet's chrysanthemums, 6 of 20 in colour; a loose and a locked card lifted |
| `06.png` | Giant boards of up to 300 cards | top left, tilted phone pushed right | `raw/27_giant`: Hölderlin Tower, 210 tiny cards, 25 locked; a close-up lifted |
| `07.png` | Puzzle your own photos | bottom left, phone pushed right | `raw/20_my_puzzles`, the corgi board of `raw/21_my_puzzle_game` lifted |
| `08.png` | Quests and world-day events | top, tilted phone | `raw/13_quests`, the World Food Day card of `raw/14_quests_live` lifted |
| `09.png` | Just as calm in the dark | top, flat phone, dark | `raw/29_dark_board`: the Monarch mid-build in the dark theme |

Raw captures (dark theme; a `--dart-define=CJW_STORE_THEME=light` run writes
the same names with a `_light` suffix):

| File | Screen |
| --- | --- |
| `01_home.png` | Home: today's daily picture, Lucky Wheel, piggy bank, 1-day streak, level |
| `02_difficulty.png` | Difficulty screen of "Monarch butterfly": preview, mode and board pickers |
| `03_game_cards.png` | Cards, "Monarch butterfly" (Butterflies), 12 cards, middle placed, one card lifted |
| `04_complete.png` | Win screen of "Key West sunset" (Sunsets) in hexagons: three stars, coins, XP, pack progress |
| `05_complete_view.png` | "View picture" on the win screen: the finished photo |
| `06_mode_cards.png` ... `09_mode_hexagons.png` | "Bora Bora lagoon" (Tropical Beaches) in cards, squares, triangles and hexagons: edges placed, scattered whole pieces open, one fused group |
| `10_game_hexagons.png` | The hexagons board of 09 with one piece lifted |
| `11_store.png` | Store, top |
| `12_store_vip.png` | Store, scrolled to the VIP card |
| `13_quests.png` | Quests tab: daily and weekly quests with progress and two Claim buttons |
| `14_quests_live.png` | Quests tab scrolled to the live (world-day) events |
| `15_library.png` | Library, all packs |
| `16_library_daily.png` | Library, Daily filter (monthly daily packs) |
| `17_daily_month.png` | Daily calendar of the current month, top |
| `18_daily_month_grid.png` | The same calendar scrolled to the day grid (five past days solved, today outlined) |
| `19_pack.png` | "Butterflies" pack page |
| `20_my_puzzles.png` | My Puzzles with four photos uploaded to live Storage (CC0 / public-domain catalogue pictures: Corgi puppy, Tuxedo kitten II, Chania lighthouse, Macarons) |
| `21_my_puzzle_game.png` | The Corgi photo as a squares board, mid-game |
| `22_social_league.png` | Social, league leaderboard |
| `23_wheel.png` | Lucky Wheel sheet |
| `24_profile.png` | Profile |
| `boards.json` | Board rectangles of the game captures |

## Regenerating

Prerequisites: Flutter at `~/flutter`, Xcode with the iPhone 17 Pro Max
simulator, and a Python 3 with Pillow (`pip install pillow`).

1. Capture the raw screens (about 6 minutes; talks to the live backend and
   plays real moves). Uninstall first: the test needs a fresh guest (daily
   gift unclaimed, no boards in progress).

   ```sh
   export PATH="$HOME/flutter/bin:$PATH"
   xcrun simctl boot D03644FB-6169-4E87-8E0F-CCFC884FBE78   # iPhone 17 Pro Max
   xcrun simctl uninstall D03644FB-6169-4E87-8E0F-CCFC884FBE78 com.matejbaco.cardjigsawworld
   tools/dev/qa-run.sh drive --driver=test_driver/store_screenshots.dart \
     --target=integration_test/store_screenshots_test.dart \
     -d D03644FB-6169-4E87-8E0F-CCFC884FBE78
   # only some glass-set captures (25_hero, 26_painting, 27_giant, 28_library_more), others kept:
   #   add --dart-define=CJW_STORE_ONLY=25_hero,27_giant (about 4 minutes instead of 13)
   # the light theme, written as raw/<name>_light.png (slides 1-8 of the glass set):
   tools/dev/qa-run.sh drive --driver=test_driver/store_screenshots.dart \
     --target=integration_test/store_screenshots_test.dart \
     -d D03644FB-6169-4E87-8E0F-CCFC884FBE78 --dart-define=CJW_STORE_THEME=light
   ```

   Captures are taken in-app (`binding.takeScreenshot`), so they have no
   status bar; the composer draws a clean one. The driver writes them to
   `store/raw/` plus the board rectangles to `store/raw/boards.json`. The
   pictures are fixed by id at the top of the test (`heroPuzzle`,
   `modesPuzzle`, `hexPuzzle`, `galleryPack`); if one leaves the catalogue,
   pick another people-free, vivid picture from a free pack. Each run
   uploads four photos to My Puzzles for its new guest (real uploads to the
   `user-uploads` bucket through the app's `UploadRepository`; the native
   photo picker cannot be driven from a test). On a rerun that only needs
   the other screens, add `--dart-define=CJW_STORE_SKIP_UPLOAD=true`: the
   upload and captures 20-21 are skipped and the earlier files kept. Every
   run also leaves its guest in the live league (about 430 XP); guests with
   equal XP make the league header's "#N" disagree with the row, so check
   slide 8 after a rerun. If the
   simulator shows a stuck "Open in Carden?" prompt, `xcrun simctl
   shutdown` it and boot again. Any `raw/zz_diag_*.png` files are
   diagnostics the test writes when a step failed; delete them, they are not
   assets.

2. Compose the slides. The glass set: copy, order, layouts, phones and
   break-out cards live in `SLIDES` at the top of the script, the look in
   `tools/store/glass/slides.html`; pass slide numbers to rebuild only some.

   ```sh
   .venv/bin/python tools/store/compose_glass.py                  # all, SF Pro Rounded
   .venv/bin/python tools/store/compose_glass.py 1 4              # just 01 and 04
   .venv/bin/python tools/store/compose_glass.py --font newyork   # or display
   .venv/bin/python tools/store/compose_glass.py --out /tmp/try --sheet /tmp/sheet.png
   ```

   The dark gallery set of 2026-10-13 (same captures, dark theme):

   ```sh
   python3 tools/store/compose_screenshots.py                 # all
   python3 tools/store/compose_screenshots.py 1 4             # just 01 and 04
   python3 tools/store/compose_screenshots.py --canvas neutral   # one graphite canvas
   python3 tools/store/compose_screenshots.py --refresh-collage  # re-download the covers
   ```

   Callout crops are given in raw-capture pixels; after a recapture, look at
   every slide at full size (a moved card shifts its crop).

3. Rebuild the icon, VIP promo and the subscription review screenshot:

   ```sh
   python3 tools/store/make_promo.py
   ```

4. Uploading: `asc_publish.py screenshots` replaces a slide whose file changed
   (by checksum), removes slides that are no longer in the folder and keeps the
   file order. The review screenshots go up with `asc_publish.py iap`
   (`review/iap-review.png`, the top of the store: copy `raw/11_store.png`) and
   `subscriptions` (`review/subscription-review.png`), which also replace a
   changed file; while the products sit in the app's review draft Apple refuses
   that until they are taken out of it (apple-release skill, "Renaming in-app
   purchases while they sit in a review draft").
