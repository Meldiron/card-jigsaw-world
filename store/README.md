# App Store assets

Everything in this folder is generated. Edit the sources under `tools/store/`
and the capture test, then rerun; do not hand-edit the PNGs.

Design rules: a flat, very dark canvas per slide whose hue comes from that
slide's photo (or one graphite with `--canvas neutral`), white SF Pro
captions of 2-5 words sized for search-result thumbnails, real captures in a
slim iPhone frame, colour only from the photos, no gradients, no emoji, no
ratings or awards. The research and reasoning are in
`docs/store-screenshots.md`.

## Layout

| Path | What it is | Size |
| --- | --- | --- |
| `raw/*.png` | Untouched in-app captures from the iPhone 17 Pro Max simulator (6.9"), dark theme. Numbered in capture order; see the list below. | 1320x2868 |
| `raw/boards.json` | Board rectangle (physical px: left, top, width, height) of every game capture, written by the capture driver; the composer crops boards with it. | |
| `collage/*.jpg` | Pack covers for the slide-2 wall, downloaded from our Storage bucket (`--refresh-collage`; pack ids in `COLLAGE_PACKS`). | 600 px wide |
| `screenshots/iphone-6.9/01.png` ... `08.png` | Marketing screenshots for the App Store "iPhone 6.9-inch Display" slot. Upload in numeric order. | 1320x2868, RGB |
| `review/subscription-review.png` | Store screen scrolled to the "Card Jigsaw VIP" card, for the App Store Connect subscription "Review screenshot" field (min 640x920). Same pixels as `raw/12_store_vip.png`. | 1320x2868 |
| `promo/app-icon-1024.png` | The app icon flattened to RGB (App Store rejects alpha). | 1024x1024 |
| `promo/vip-promotional-1024.png` | Promotional image for the VIP subscription (icon, "VIP" word mark, one-line benefit). | 1024x1024 |

Marketing slides (`screenshots/iphone-6.9/`), in upload order. Slides 1-3
appear in search results, so they carry the core loop, the catalogue and the
daily hook.

| Slide | Headline | Shows |
| --- | --- | --- |
| `01.png` | Swap pieces. Reveal the picture. | `raw/03_game_cards.png`: Monarch, 9 of 12 cards placed, one lifted |
| `02.png` | Thousands of pictures | `raw/13_library.png` in front of a wall of real pack covers (`collage/`) |
| `03.png` | A new picture every day | `raw/15_daily_month.png` with Home's "Today" card as a callout (work in progress: the callout hides the day grid) |
| `04.png` | Four ways to play | Board crops of `raw/06`-`09`: Bora Bora lagoon as cards, squares, triangles, hexagons |
| `05.png` | Fewer moves, more stars | `raw/04_complete.png`: Key West sunset, three stars, coins and XP |
| `06.png` | Quests and live events | `raw/17_quests.png` with a World Food Day card (`raw/18_quests_live.png`) as a callout |
| `07.png` | Climb the league | `raw/19_social_league.png` |
| `08.png` | Every pack with VIP | `raw/12_store_vip.png` |

Raw captures (dark theme; a `--dart-define=CJW_STORE_THEME=light` run writes
the same names with a `_light` suffix):

| File | Screen |
| --- | --- |
| `01_home.png` | Home: today's daily picture, Lucky Wheel, piggy bank, 1-day streak, level |
| `02_difficulty.png` | Difficulty screen of "Monarch butterfly": preview, mode and board pickers |
| `03_game_cards.png` | Cards, "Monarch butterfly" (Butterflies), 12 cards, middle placed, one group, one card lifted |
| `04_complete.png` | Win screen of "Key West sunset" (Sunsets) in hexagons: three stars, coins, XP, pack progress |
| `05_complete_view.png` | "View picture" on the win screen: the finished photo |
| `06_mode_cards.png` ... `09_mode_hexagons.png` | "Bora Bora lagoon" (Tropical Beaches) mid-game in cards, squares, triangles and hexagons |
| `10_game_hexagons.png` | The hexagons board of 09 with one piece lifted |
| `11_store.png` | Store, top |
| `12_store_vip.png` | Store, scrolled to the VIP card |
| `13_library.png` | Library, all packs |
| `14_library_daily.png` | Library, Daily filter (monthly daily packs) |
| `15_daily_month.png` | Daily calendar of the current month |
| `16_pack.png` | "Butterflies" pack page (the Monarch solved) |
| `17_quests.png` | Quests tab: daily and weekly quests with progress |
| `18_quests_live.png` | Quests tab scrolled to the live (world-day) events |
| `19_social_league.png` | Social, league leaderboard |
| `20_wheel.png` | Lucky Wheel sheet |
| `21_profile.png` | Profile |

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
   flutter drive --dart-define=CJW_MUTE=true --driver=test_driver/store_screenshots.dart \
     --target=integration_test/store_screenshots_test.dart \
     -d D03644FB-6169-4E87-8E0F-CCFC884FBE78
   ```

   Captures are taken in-app (`binding.takeScreenshot`), so they have no
   status bar; the composer draws a clean one. The driver writes them to
   `store/raw/` plus the board rectangles to `store/raw/boards.json`. The
   pictures are fixed by id at the top of the test (`heroPuzzle`,
   `modesPuzzle`, `hexPuzzle`, `galleryPack`); if one leaves the catalogue,
   pick another people-free, vivid picture from a free pack. If the
   simulator shows a stuck "Open in Card Jigsaw?" prompt, `xcrun simctl
   shutdown` it and boot again. Any `raw/zz_diag_*.png` files are
   diagnostics the test writes when a step failed; delete them, they are not
   assets.

2. Compose the slides (copy, order, layouts and callouts live in `SLIDES` at
   the top of the script; pass slide numbers to rebuild only some):

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

4. Uploading: `asc_publish.py screenshots` skips files whose name is already
   in the App Store set and never deletes extras, so delete the old
   screenshots in App Store Connect (or the set) before uploading a new set
   with the same file names.
