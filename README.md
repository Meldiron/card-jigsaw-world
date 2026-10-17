# Carden

[![CI](https://github.com/Meldiron/carden/actions/workflows/ci.yml/badge.svg)](https://github.com/Meldiron/carden/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

<img src="docs/images/app-icon.png" width="96" alt="App icon" align="right" />

**Your calm picture puzzle.** Carden (until October 2026 called Card Jigsaw World) is a picture-puzzle game for iOS, Android and the web ([play.carden.page](https://play.carden.page); homepage [www.carden.page](https://www.carden.page)), built with Flutter and backed by [Appwrite](https://appwrite.io).
Every puzzle is a photo cut into cards and shuffled on a board. Tap a card and then where it should go, or drag it there.
Cards that belong next to each other **snap together anywhere on the board** and move as one group; a card that lands in its true spot **locks** into the picture. Fewer moves earn more stars.

<p align="center">
  <img src="docs/images/02_home.png" width="200" alt="Home" />
  <img src="docs/images/09b_game_group.png" width="200" alt="Cards snapped into a group" />
  <img src="docs/images/11b_complete.png" width="200" alt="Picture complete" />
  <img src="docs/images/25_game_dark.png" width="200" alt="Game, dark mode" />
</p>

## What is in the game

| Area | Features |
|---|---|
| Gameplay | Four tilings: Cards (portrait rectangles), Squares, Triangles and Hexagons, each with its own eight-step ladder and a reward multiplier (x1.0 to x1.5). Boards never start with a card in place or a pre-joined pair. Higher tiers unlock by level or can be bought early with coins. Card boards from 3x3 to 6x8. Correctly adjacent cards snap into groups anywhere on the board and travel together; cards in their true spot lock in place. Par-based 3-star scoring, optional timer, Shuffle (free), Peek, Hint and Magic (a card and its neighbours) boosters, groups a move lands on move aside whole, double-lock celebration, confetti win screen with photo credits, resume any board later |
| Economy | Coins, tickets (premium currency earned by levelling up and in events), hints, XP and levels with a reward table (coins, tickets, hints, board tiers) shown on a Home level card, piggy bank filled by every completed puzzle, coin ledger in the backend. Rewarded videos are capped at 5 per day, tracked on the profile |
| Daily | Monthly daily packs with one picture per day, every month back to January 2023 (1,400 puzzles); future days stay locked until their date; today's puzzle pays bonus coins. The current month is free, past months cost coins or come with VIP. 7-day daily gift streak with a streak card on Home and a ticket-priced restore to your longest streak; Lucky Wheel costs one ticket per spin and pays coins, hints, Peeks or Magic (a 1,000-coin jackpot at 1%; odds in `docs/economy.md`) |
| Content | 120 library packs, 97 event packs and 46 monthly packs (5,079 puzzles), every image with a stored BlurHash so galleries show blurred colour before the picture arrives. Featured starters: Wild Nature (free), Animal Friends, Cozy Kitchen, City Lights, Land of Fire & Ice (ticket pack), Masterpieces (Cleveland Museum of Art, CC0), Deep Space (NASA), Autumn Harvest (seasonal) |
| Events | Daily goals (coins) and weekly goals (tickets) with one-tap Play shortcuts and claimable rewards; world-day events (97 across Oct 2026 to Dec 2027, one to three per week, each running from three days before the day to four days after) with a dedicated themed pack, shown up to three days before they open |
| Avatars and achievements | 55 avatars: 4 free, 28 for coins, 23 earned through 24 achievement families; multi-step families upgrade the same avatar with silver, gold and double rings |
| Social | Leaderboard by total XP (only profiles with at least one solved puzzle appear), friends by friend code, native Sign in with Apple (ID token session, no browser redirect) |
| Account | Instant guest play (anonymous session) with a generated display name such as "Brave Otter", upgrade to email account without losing progress, sign in / out |
| My Puzzles | Upload your own photos to Appwrite Storage and play them as puzzles |
| Store | Coin and ticket bundles, two hint packs and VIP, which unlocks every pack including past monthly packs (sandbox purchases until StoreKit is wired) |
| iOS extras | Home Screen widget (small, medium and large) showing today's daily picture, fetched straight from the public catalogue and deep-linking into the puzzle (`carden://play/<id>`); a Home Screen quick action "One last game?" that opens today's puzzle |
| House ads | No ad network. A 15-second rewarded offer card (40 coins, 5 per day), a closable interstitial after every 4th puzzle, and a dismissible VIP banner, all promoting in-app purchases. Never shown to VIP. See `docs/house-ads.md` |
| Settings | Light / dark / auto theme, classic or minimal card style, music, sound effects, haptics, timer, reminders, account, credits |

## Screenshots

| Onboarding | Home | Daily gift | Library |
|---|---|---|---|
| ![](docs/images/01b_onboarding_3.png) | ![](docs/images/02_home.png) | ![](docs/images/03_daily_gift.png) | ![](docs/images/04_library.png) |

| Daily months | This month's calendar | Past month (locked) | Pack |
|---|---|---|---|
| ![](docs/images/04b_library_daily.png) | ![](docs/images/04c_daily_month.png) | ![](docs/images/04d_daily_locked.png) | ![](docs/images/05_pack.png) |

| Difficulty | Store | Goals | Live events |
|---|---|---|---|
| ![](docs/images/06_difficulty.png) | ![](docs/images/12_store.png) | ![](docs/images/15_events.png) | ![](docs/images/15b_events_live.png) |

| Tutorial | Game | Cards snapped into groups | Picture complete |
|---|---|---|---|
| ![](docs/images/07_tutorial.png) | ![](docs/images/10_game_progress.png) | ![](docs/images/09b_game_group.png) | ![](docs/images/11b_complete.png) |

| Mode picker | Squares | Triangles | Hexagons |
|---|---|---|---|
| ![](docs/images/26_difficulty_hexagons.png) | ![](docs/images/27_game_squares.png) | ![](docs/images/27_game_triangles.png) | ![](docs/images/27_game_hexagons.png) |

| Achievements | | | |
|---|---|---|---|
| ![](docs/images/28_achievements.png) | | | |

| Pause | Rewarded offer | Close early | Piggy bank |
|---|---|---|---|
| ![](docs/images/11_pause.png) | ![](docs/images/12b_rewarded_offer.png) | ![](docs/images/12c_rewarded_close_dialog.png) | ![](docs/images/14_piggy.png) |

| Store | Lucky Wheel | Piggy bank | Events |
|---|---|---|---|
| ![](docs/images/12_store.png) | ![](docs/images/13_wheel.png) | ![](docs/images/14_piggy.png) | ![](docs/images/15_events.png) |

| League | Friends | Profile | Settings |
|---|---|---|---|
| ![](docs/images/16_social_league.png) | ![](docs/images/17_social_friends.png) | ![](docs/images/18_profile.png) | ![](docs/images/19_settings.png) |

| Home (dark) | Pack (dark) | Game (dark) | Account (dark) |
|---|---|---|---|
| ![](docs/images/23_home_dark.png) | ![](docs/images/24_pack_dark.png) | ![](docs/images/25_game_dark.png) | ![](docs/images/22_account_dark.png) |

## Architecture

```
lib/
  core/        Appwrite config, theme tokens + ThemeData, haptics, sound
  models/      Profile, Pack, Puzzle, PuzzleProgress, GameEvent, Friend, MyPuzzle
  data/        Repositories over Appwrite TablesDB / Storage / Account, local cache
  state/       Riverpod notifiers: auth, profile (economy rules), catalog, progress, social, settings
  game/        Pure board model (permutation, par, stars), GameController, image loader
  features/    onboarding, home, gallery, game, store, daily, events, social, profile
  widgets/     Design system: Pressable, SoftCard, BigButton, CurrencyPill, Glass, ...
```

- **UI**: Material 3 theming with Cupertino navigation, sheets, switches and dialogs so it feels native on iOS. System font throughout; hierarchy comes from weight and size. Neutral surfaces with hairline borders, one accent colour for actions and selection, and no gradients except scrims over photos, so the puzzle images carry the colour. Full light and dark mode.
- **Icons**: no emoji anywhere. `lib/widgets/icons.dart` holds a semantic icon map (`AppIcons`), drawn currency marks (`CoinIcon`, `TicketIcon`, `HintIcon`), an `Amount` widget for prices and rewards, icon avatars and `IconTile`. Category, tier and event-type icons derive from data, so new content needs no artwork.
- **State**: Riverpod 3 (`Notifier` / `AsyncNotifier`). Economy changes are applied optimistically and persisted to Appwrite in the background, with a local cache for offline play.
- **Game engine**: `Board` is an immutable permutation (`slots[i]` = card at slot i). Groups are derived, never stored: two neighbouring slots are joined when their cards are picture-neighbours with the same offset, and a drag moves the whole connected group (displaced cards fall into the vacated cells). Par = n - cycles of single swaps. `GameController` emits events (pick, move, join, lock, double lock, win) that the screen turns into sound, haptics and particles.
- **Navigation**: go_router with a `StatefulShellRoute` for the five tabs and full-screen routes for play, store and account.

## Backend (Appwrite)

Project `6acb4de5003e38d5ebd9` in region `fra`, endpoint `https://fra.cloud.appwrite.io/v1`.

| Resource | Purpose |
|---|---|
| Auth | Anonymous sessions for instant play; email/password; native Sign in with Apple via `createIdTokenSession` (Google and Facebook can be added later) |
| `cjw.profiles` | Coins, tickets, hints, XP, level, piggy bank, streak, unlocked packs, stats. Row id = user id, public read for leaderboard |
| `cjw.packs`, `cjw.puzzles`, `cjw.events` | Catalog, public read. Featured packs seeded from `docs/seed-catalog.json`; monthly daily packs (puzzles carry a `date`) from `docs/seed-daily-packs.json` |
| `cjw.progress` | Per-user, per-puzzle board layout, moves, time, stars, best scores |
| `cjw.event_progress` | Per-user event counters; community totals are summed client-side |
| `cjw.friends`, `cjw.ledger`, `cjw.my_puzzles` | Friends list, coin/ticket audit log, user photo puzzles |
| Storage `user-uploads` | Player photos (file-level permissions) |
| Storage `puzzle-images` | Reserved for self-hosted catalog images |

Row-level security is on for every user table; rows carry `read/update/delete` permissions for their owner.

## Image sources

Catalog images are hotlinked from sources that permit it: [Openverse](https://openverse.org) (CC0, public domain, CC BY and CC BY-SA photographs with author and licence stored per puzzle), the [Cleveland Museum of Art Open Access API](https://openaccess-api.clevelandart.org/) (CC0), the [NASA Image and Video Library](https://images.nasa.gov) and [Lorem Picsum](https://picsum.photos) (Unsplash License). See `docs/content-sources.md`.
See `docs/research-card-jigsaw-and-image-apis.md` for the full evaluation of 11 free image APIs and the card-jigsaw genre study that informed the gameplay.

## Running

```bash
flutter pub get
tools/dev/qa-run.sh run -d "iPhone 17 Pro"   # iOS simulator
tools/dev/qa-run.sh run -d chrome            # web (register the hostname as a Web platform in Appwrite)
```

Every run while developing goes through `tools/dev/qa-run.sh`: silent (`CJW_MUTE`), a flagged test
player (`CJW_QA`, kept out of the league) and purged when the run ends
(`tools/dev/purge_test_players.py`).

Tests:

```bash
flutter test                                                 # board engine unit tests
tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshots_test.dart -d <simulator-id>   # walks the app and writes screenshots/
```

Regenerate launcher icons after editing `assets/icon/icon.png` with `dart run flutter_launcher_icons`.

## Roadmap / not yet wired

- StoreKit / Play Billing (purchases are sandboxed; the store credits coins locally).
- Sign in with Apple needs the capability on the App ID in the Apple Developer portal (Xcode adds it automatically with the entitlement) and native sign-in enabled on the Apple provider in the Appwrite console with the bundle id listed. No secret, key or team id is required for the native flow.
- Push notifications for daily reminders (toggle exists in settings).
- An Appwrite Function to validate economy writes server-side and to proxy a keyed image API (Pexels) for fresh packs.
- Web build: add the production hostname as a Web platform in Appwrite.

## Releasing

CI runs analysis, tests and unsigned builds on every push. Publishing a GitHub release tagged `vX.Y.Z` builds a signed archive and uploads it to TestFlight; the one-time secrets and App Store Connect steps are listed in `docs/release-checklist.md`. In-app purchases are verified server-side by the `verify-purchase` Appwrite Function (`docs/purchases.md`).

## License

MIT, see `LICENSE`. Puzzle images are hotlinked from their sources under their own licences (`docs/content-sources.md`).

## Shipping

The path from a USB-connected iPhone to the App Store is described in [docs/release-flow.md](docs/release-flow.md): `tools/dev/device.sh` installs on the phone, `tools/dev/release.sh` cuts a release that lands in TestFlight automatically, and the `Submit to App Store` workflow files the review when you decide to.
