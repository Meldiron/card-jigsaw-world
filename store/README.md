# App Store assets

Everything in this folder is generated. Edit the sources under `tools/store/`
and the capture test, then rerun; do not hand-edit the PNGs.

Design rules: flat neutral backgrounds (light grey `#F2F2F4` or near-black),
one accent (`#4F46E5` indigo), colour only from the puzzle photos, system
font (SF Pro), no gradients, no emoji.

## Layout

| Path | What it is | Size |
| --- | --- | --- |
| `raw/*.png` | Untouched in-app captures from the iPhone 17 Pro Max simulator (6.9"). Numbered in capture order; see the list below. | 1320x2868 |
| `screenshots/iphone-6.9/01.png` ... `08.png` | Framed marketing screenshots for the App Store "iPhone 6.9-inch Display" slot. Upload in numeric order; `01` is gameplay. | 1320x2868, RGB |
| `review/subscription-review.png` | Store screen scrolled to the "Card Jigsaw VIP" card, for the App Store Connect subscription "Review screenshot" field (min 640x920). Same pixels as `raw/12_store_vip.png`. | 1320x2868 |
| `promo/app-icon-1024.png` | The app icon flattened to RGB (App Store rejects alpha). | 1024x1024 |
| `promo/vip-promotional-1024.png` | Promotional image for the VIP subscription (icon, "VIP" word mark, one-line benefit). | 1024x1024 |

Marketing slides (`screenshots/iphone-6.9/`), in upload order:

| Slide | Headline | Source capture |
| --- | --- | --- |
| `01.png` | Swap cards. Reveal the picture. | `raw/05_game_cards.png` |
| `02.png` | A new puzzle every day | `raw/03_daily_month.png` |
| `03.png` | Thousands of photos in packs | `raw/04_pack.png` |
| `04.png` | Hexagons, triangles, squares | `raw/16_game_hexagons_dark.png` |
| `05.png` | Three stars, real rewards | `raw/06_complete.png` |
| `06.png` | Climb the league | `raw/10_social_league.png` |
| `07.png` | Daily and weekly goals | `raw/09_events.png` |
| `08.png` | VIP: every pack, no breaks | `raw/12_store_vip.png` |

Raw captures:

| File | Screen |
| --- | --- |
| `01_home.png` | Home (today's daily, wheel, piggy bank, streak, level) |
| `02_library.png` | Library pack list |
| `03_daily_month.png` | Daily calendar pack for the current month |
| `04_pack.png` | "Wild Nature" pack gallery |
| `05_game_cards.png` | Cards mode, 3x3, partly solved, one card selected |
| `06_complete.png` | Win screen ("Picture complete", three stars) |
| `07_game_hexagons.png` | Hexagons mode, light theme |
| `08_game_triangles.png` | Triangles mode, light theme |
| `09_events.png` | Events (daily and weekly goals) |
| `10_social_league.png` | Social, league leaderboard |
| `11_store.png` | Store, top |
| `12_store_vip.png` | Store, scrolled to the VIP card |
| `13_profile.png` | Profile |
| `14_achievements.png` | Profile scrolled to achievements |
| `15_achievements_dark.png` | Achievements, dark theme |
| `16_game_hexagons_dark.png` | Hexagons mode, dark theme |
| `17_game_triangles_dark.png` | Triangles mode, dark theme |

## Regenerating

Prerequisites: Flutter at `~/flutter`, Xcode with the iPhone 17 Pro Max
simulator, and a Python 3 with Pillow (`pip install pillow`).

1. Capture the raw screens (about 8 minutes; talks to the live backend):

   ```sh
   export PATH="$HOME/flutter/bin:$PATH"
   xcrun simctl boot D03644FB-6169-4E87-8E0F-CCFC884FBE78   # iPhone 17 Pro Max
   flutter drive --dart-define=CJW_MUTE=true --driver=test_driver/store_screenshots.dart \
     --target=integration_test/store_screenshots_test.dart \
     -d D03644FB-6169-4E87-8E0F-CCFC884FBE78
   ```

   Captures are taken in-app (`binding.takeScreenshot`) and written to
   `store/raw/` by `test_driver/store_screenshots.dart`. If the simulator shows
   a stuck "Open in Card Jigsaw?" prompt, `xcrun simctl shutdown` it and boot
   again. The test starts from a fresh local state, but pack pages resume
   puzzles that were started on the simulator, so either pick untouched
   pictures or uninstall first for a clean state:
   `xcrun simctl uninstall D03644FB-6169-4E87-8E0F-CCFC884FBE78 com.matejbaco.cardjigsawworld`.
   Any `raw/zz_diag_*.png` files are diagnostics the test writes when it had
   to recover its navigation; delete them, they are not assets.

2. Compose the framed screenshots (copy and order live in `SLIDES` at the top
   of the script; pass slide numbers to rebuild only some):

   ```sh
   python tools/store/compose_screenshots.py        # all
   python tools/store/compose_screenshots.py 1 4    # just 01 and 04
   ```

3. Rebuild the icon, VIP promo and the subscription review screenshot:

   ```sh
   python tools/store/make_promo.py
   ```
