# Carden — project instructions for Claude Code

Flutter card-swapping picture puzzle game (iOS first, web secondary, Android builds in CI only) with an
Appwrite backend. Owner: Matej Bačo (GitHub `Meldiron`). Read this file fully before any work; the
skills under `.claude/skills/` hold the detailed workflows.

**Name** (owner, 2026-10-15): the game is **Carden** ("Carden: Your calm picture puzzle"; App Store name
"Carden: Calm Picture Puzzle", the 30-character limit). It was Card Jigsaw World until build 118. Renamed: app
and Home Screen name, Flutter package `carden` (`CardenApp`), link scheme `carden://`, web address
https://carden.appwrite.network, repo `Meldiron/carden`, Appwrite project/site/platform names, store copy. Kept on
purpose (old builds, Apple records, data): bundle id `com.matejbaco.cardjigsawworld`, the Services ID and product
ids, the Appwrite project/site/database ids (`card-jigsaw-world` site id, database `cjw`), the `CJW_` dart-defines,
the old scheme `cardjigsaw://` and the old address card-jigsaw-world.appwrite.network (both still open the game;
web guests keep their saves per address), and the local folder and `~/.local/share/card-jigsaw-world`.

## Skills (load them when the task matches)

| Skill | Use for |
| --- | --- |
| `.claude/skills/testflight-feedback/` | Pulling TestFlight feedback, fixing it, QA, shipping a build, resolving items on Apple |
| `.claude/skills/apple-release/` | Any build, TestFlight push, version bump, App Store submission |
| `.claude/skills/pack-making/` | Picture packs: adding, repairing, auditing, sources, licences |
| `.claude/skills/giant-packs/` | Giant packs (category Giant, 100-300 card boards): sources, `giantcheck`, 4096 px hosting |
| `.claude/skills/store-screenshots/` | App Store screenshots: captures, the glass slides (`tools/store/compose_glass.py`), copy and story, preview, upload |

## Owner rules (non-negotiable, learned from feedback)

- **Design**: no emojis anywhere, no vivid gradients, neutral professional look, colour comes from the
  photos. One accent: cobalt `Brand.accent` 0xFF2F4FBF (dark 0xFF7C9AFF) in `lib/core/theme/tokens.dart`.
  Icons only from `lib/widgets/icons.dart` (CoinIcon, TicketIcon = upright "pass" design, HintIcon,
  AppIcons). Native iOS 26 feel: glass bars/sheets (`lib/widgets/glass.dart`), every confirmation via
  `showAppAlert`, every sheet via `showAppSheet` and every menu of actions via `showAppActionSheet` in
  `lib/widgets/ui.dart`; switches are the glass `AppSegmentedControl`, round buttons over photos `PhotoButton`,
  the VIP card family is `lib/widgets/vip.dart`, and counts go through `formatCount` / `compactCount`
  (`lib/core/numbers.dart`). Costs on buttons use `BigButton.cost` / `CostLabel` (currency icon + amount);
  destructive actions are red and always ask first. See `docs/native-ui.md`.
- **Onboarding is instant** (owner, 2026-10-15): every picture the welcome pages show is bundled in
  `assets/welcome/` (PD/CC0 catalogue picks), never loaded from Storage.
- **Copy**: calm, precise, short; terms and CTA style in `docs/copy-guide.md`. The `/events` tab is
  called **Quests**: daily quests, weekly quests and the world-day "Live events" section.
- **QA is silent**: never start the app without `--dart-define=CJW_MUTE=true` (or `tools/dev/qa.sh`).
  The owner does not want to hear the game's music while you work.
- **QA players stay out of the league** (owner rule, 2026-10-13): every QA run plays a guest on the LIVE
  backend, so every run (flutter drive, flutter run on a simulator or Chrome, store screenshots) goes
  through `tools/dev/qa-run.sh <run|drive|test> ...` (or `tools/dev/qa.sh`), which passes `CJW_MUTE=true`,
  `CJW_QA=true` and a run id, then purges that run's test players. `CJW_QA` flags the guest
  (`profiles.isTest`, user prefs `qa`/`qaRun`); the league and its counts filter `isTest` on the server
  (a QA player sees only its own row). Integration tests refuse to start without the flag
  (`QaRun.requireForIntegrationRuns`, `test/qa_test_players_test.dart`). Leftovers:
  `python3 tools/dev/purge_test_players.py purge --apply` (dry run without `--apply`; `audit` explains
  every player; backups in `secrets/purged/`). Never purge by hand outside the tool.
- **QA the exact user path**: when fixing a reported problem, reproduce and verify the path the user
  described (e.g. Home > Continue > puzzle > pause menu), with a simulator screenshot you have looked
  at. Describing a fix on a screen the user never reaches is not a fix.
- **Pictures are self-hosted** (owner rule, 2026-10-13): every catalogue picture and cover is served
  from the Appwrite Storage bucket `puzzle-images` (`/view` for the game, `/preview?width=600` for tiles,
  `/preview?width=1080` for covers). Never write a third-party image URL to the database. The content
  tool hosts each pick on apply (`tools/content/cjw/host.py`); `tools/content/run.sh host` migrates
  anything left. The original address stays in `sourceUrl` (puzzles) / `coverSourceUrl` (packs, events).
- **The app talks only to Appwrite and Apple** (owner rule, 2026-10-13): no analytics, crash or ad SDKs,
  no CDNs. Pictures come from our Storage (above); the web build bundles CanvasKit
  (`--no-web-resources-cdn` in `tools/dev/deploy-web.sh`) and serves its default font from
  `web/fallback-fonts/` (`fontFallbackBaseUrl` in `web/flutter_bootstrap.js`). Apple traffic is
  StoreKit, Sign in with Apple and the widget/App Store system services. Check new dependencies for
  network use before adding them.
- **Builds only when the owner asks** (owner rule, 2026-10-13): never dispatch a TestFlight/App Store build
  (`gh workflow run`, `tools/dev/testflight.sh`, submissions) on your own initiative. Fix, QA, commit, push, then
  report that it is ready for a build. Same for installs on the owner's iPhone.
- **No single-page reads** (owner rule, 2026-10-13): never read a list with a fixed `Query.limit`.
  Data the app needs whole goes through `listAllRows` (cursor pagination over every page), counts
  through `countRows`, and lists people scroll (league, My Puzzles) through `listRowsPage` + a
  `PagedNotifier` (`lib/state/paged.dart`) that loads the next page near the end. Filter and sort on
  the server (`Query.equal`, `orderDesc`, `select`). `test/pagination_test.dart` fails on a fixed limit.
- **Every build also redeploys the web site** (`tools/dev/deploy-web.sh`) from the same commit.
- **Update prompt** (`docs/app-updates.md`): web and iPhone ask "Update available" when a newer build
  is out (looks every 5 min, Later = 1 hour, again after every reload/launch). Web compares its
  `CJW_WEB_BUILD` with the site's `app-version.json` (written by `deploy-web.sh`); iPhone compares its
  build number with table `releases` (`tools/dev/publish_release.py`, run by `testflight.sh` once
  Apple has the build out; after a hand-dispatched workflow run it yourself).
- **Versioning**: one version string per App Store cycle; TestFlight builds only bump the build number.
  Details in the apple-release skill. Never bump the version for a TestFlight cut.
- **Old builds stay in use** (lessons the owner collected, 2026-10-15): assume the client is outdated,
  the network unreliable and releases slow. Backend changes stay compatible with every build testers
  still have (add with defaults, never rename or remove what a live build reads; server before build).
  Server switches may only turn on or off what a reviewed build already contains; new features ship
  in a build and are described in the review notes. Details: "Old builds stay in use" and "What may
  change without a build" in the apple-release skill.
- **Resolve feedback** on Apple after fixing it (`asc_publish.py feedback --resolve`), so items are not
  fixed twice.
- **Subagents run on Opus** (`model: "opus"` on every Agent call).
- **Long multi-agent jobs**: watch the active account's 5-hour usage and pause everything when it
  passes the threshold the owner sets (default 50%): run `tools/dev/usage-watch.sh <LIMIT>` in the
  background; it exits when the limit is crossed, then stop the agents, push a checkpoint, tell the
  owner. If the owner asks to continue on the other account past a limit, `tools/dev/usage-relay.sh
  FIRST TARGET` switches with `cswap switch TARGET` when FIRST is crossed. Keep worker counts modest (4 to 5): many parallel downloads saturated the owner's internet.
- **Installing on the owner's iPhone: only when the owner asks** (owner rule, 2026-10-13; releases and
  feedback rounds do not install, TestFlight reaches the phone). When asked, `tools/dev/device.sh` works over Wi-Fi (the phone is paired;
  UDID 00008110-000024E63650401E). `--wipe` reinstalls fresh (onboarding), `--no-build` pushes the
  last build. Release builds keep sound; debug runs are muted.
- **Commits**: `git -c user.name="Matej Bačo" -c user.email="matej@appwrite.io" commit ...`, push to
  `origin main` (public repo `Meldiron/carden`). End messages with the Co-Authored-By
  trailer the harness gives you. Never `git add -A` while another agent works in the repo; add paths.

## Toolchain

- Flutter 3.47 at `~/flutter` (not on PATH): `export PATH="$HOME/flutter/bin:$PATH"`.
- Gates before any build: `flutter analyze --fatal-infos --fatal-warnings` and `flutter test`.
- Simulators: iPhone 17 Pro `CDD7317C-19D6-486D-B258-8AB8A607297D` (QA), iPhone 17 Pro Max
  `D03644FB-6169-4E87-8E0F-CCFC884FBE78` (App Store 6.9" screenshots).
- Screenshot QA: `tools/dev/qa.sh shots` = `tools/dev/qa-run.sh drive
  --driver=test_driver/integration_test.dart --target=integration_test/screenshots_test.dart -d <pro>`
  → `screenshots/*.png`. Any other suite: `tools/dev/qa-run.sh drive --driver=... --target=... -d <udid>`
  (never a bare `flutter drive`/`flutter run`; `QA_KEEP=1` keeps the run's players for inspection). Store captures: `test_driver/store_screenshots.dart` +
  `integration_test/store_screenshots_test.dart` → `store/raw/`. Extra suites:
  `integration_test/social_profile_test.dart`, `merge_sheet_test.dart`.
  Quirks: capture is in-app (host `simctl io screenshot` fires too late); uninstall the app before a
  second same-day run (`xcrun simctl uninstall <udid> com.matejbaco.cardjigsawworld`, the daily gift is
  otherwise already claimed); a stuck "Open in Carden?" prompt needs a simulator reboot; started
  puzzles resume directly, so tests needing the difficulty screen open an untouched picture.
- Board shape harness: `flutter test test/board_widget_test.dart` renders fused-group shapes for all
  modes to `build/board_shapes/`.
- Python helpers (store tooling, content): the venv and the content cache live in
  `~/.local/share/card-jigsaw-world/` (persistent, outside the iCloud-synced Desktop); `.venv` in the
  repo is a symlink to that venv, so `.venv/bin/python tools/store/asc_publish.py ...` works.
  `tools/content/.local-env` points the content tool at both. Recreate with `python3 -m venv
  ~/.local/share/card-jigsaw-world/venv && ... pip install -r tools/content/requirements.txt`.

## Code map

- `lib/game/`: `board.dart` (permutation board; shuffle is a derangement with zero joined pairs),
  `tiling.dart` (Grid/Triangle/Hex tilings, `fit`/`crop`, `boardAspect`, neighbours, vertex geometry),
  `modes.dart` (cards ×1.0, squares ×1.15, triangles ×1.35, hexagons ×1.5; route code
  `<mode>-CxR`), `image_loader.dart`.
- `lib/features/game/`: `board_widget.dart` (one render path for all modes: unplaced pieces dimmed
  16%, joined groups fused with a cobalt outer outline, locked clusters fused without outline),
  `game_screen.dart` (HUD, toolbar Undo/Peek/Magic/Hint, pause sheet with "Change mode or board",
  completion overlay with pack progress and "View picture"), `difficulty_screen.dart` (real-aspect
  preview, rewards chips, Discard progress).
- `lib/state/catalog.dart`: `catalogProvider` is the catalogue (packs, puzzles, events; refresh by
  invalidating it); `packRowsProvider`, `allPuzzlesProvider` and `eventsProvider` read it.
  `packsProvider` is what screens see: `Pack.isReleasedAt` hides daily months until their first day and
  event packs until 3 days before they open (content is created up to a year ahead).
- **Catalogue sync** (`docs/catalog-sync.md`): `lib/state/catalog_sync.dart` (`CatalogSync`, snapshot +
  delta sync). A launch reads only rows changed since the newest one on the device (about 30 reads); the
  base comes from the daily snapshot file (function `catalog-snapshot`) on first launch and weekly. Never
  read a whole catalogue table on launch (8k+ rows, each one a billed read). The content tool sets
  `packs.puzzlesUpdatedAt` whenever it changes a pack's puzzles (`finalize_pack`): that is how devices
  and the snapshot see removed puzzles. Its duplicate check uses `catalog.sync()`, not a full dump.
- `lib/state/`: `profile.dart` (`Economy` constants, VIP, piggy 5/picture up to 500), `rewards.dart`
  (level curve `LevelRewards.levelForXp`, daily 3 + 1 VIP / weekly 5 + 1 VIP quests), `achievements.dart`,
  `progress.dart`, `merge.dart` + `merge_flow.dart` (guest→account save merge), `auth.dart`, `social.dart`.
- **Save sync** (`docs/sync.md`): `lib/state/sync.dart` (`SyncController`: queued ops, fetch on start/resume/
  focus/sign-in, conflicts) + `lib/data/sync/` (`ops.dart` intents → atomic operators, `notice.dart`,
  `backend.dart`). Profile and progress changes go through `enqueue(SyncOp...)`; never write totals
  computed on the device. "Synced from another device" alert and "Two boards in progress" sheet live in
  `lib/features/sync/`.
- `lib/features/ads/house_ads.dart`: house ads only (no ad network). Break offer every 3rd completion
  or when the last break is 3+ minutes old, closable after 5 s, rewarded 15 s; the offer CTA never
  skips the rewarded countdown.
- `lib/data/purchases.dart`: StoreKit products (coins_1000/3000/5500/12000, tickets_5/15, hints_5/15,
  vip_monthly/yearly), verified server-side by the `verify-purchase` function. `PurchaseService` listens from
  launch, checks open transactions on resume and retries checks without an answer; `PurchaseFlow`
  (`lib/state/purchases.dart`) and `PurchaseHost` (`lib/features/store/purchase_host.dart`) show the tile
  spinner, the purchase sheet ("Adding 10 tickets" > "10 tickets added") and toasts. Flow: `docs/purchases.md`.
- `lib/widgets/adaptive.dart`: wide windows on the web (top bar from 900 px, centred pages, adaptive
  grids, shelves with arrows, sheets as centred panels); phones keep their layout. `docs/web.md`, "Layout".
- `lib/core/platform.dart`: web capability flags.
  `lib/core/sfx.dart`: `CJW_MUTE`. `lib/core/qa.dart`: `CJW_QA` / `CJW_QA_RUN` (test players).
- Daily reminders: local iOS notifications, no server. `lib/state/reminders.dart` (`planReminders`: one a
  day for a week at the Settings time, none on a day the daily gift is claimed; replanned on start, resume
  and background), `lib/core/reminders.dart` (channel `cjw/reminders`), native side `DailyReminders` in
  `ios/Runner/AppDelegate.swift`. Integration runs ask for provisional permission (no prompt to tap);
  `integration_test/quests_reminders_test.dart` checks a reminder really fires. `planEventReminders`
  (Settings > New events): the evening before an event opens, only for notes 5+ days out (lapsed players).
  They are promotional, so they are off until the player says yes (the switch, or Turn on in the reminder
  question, whose copy names them; guideline 4.5.4).
- Painting and giant boards: `progress.painting`; `lib/state/giant.dart` (`isGiantPack`,
  `isGiantPuzzleProvider`: packs of category `Giant` get the Large/Huge/Giant/Colossal ladder only, about
  100-300 cards in Cards), `puzzleImageFullProvider` (full-resolution decode), `BoardZoom` in
  `board_widget.dart` (pinch, two-finger pan, `fitCell` zoom limit, auto-pan; no double tap); the bar,
  overview map, off-screen pointer and milestones in `lib/features/game/giant_board.dart`; saved views and
  the map switch in `GiantViews` (`lib/state/giant.dart`). No zones and no Edges (owner removed both
  2026-10-14): Locate (tap a card, the map shows its place, only while the map is on; always on),
  Gather at any zoom (`lib/game/gather.dart`; with nothing to bring in it shuffles the loose cards in
  view, `shuffleInView`), Magic puts the selected card in place, and Peek (10 coins on every board) flies
  the cards to their places and back. Design and research: `docs/giant-boards.md`. QA:
  `integration_test/giant_ux_test.dart` (real Giant pack, about 4 minutes) and `giant_tools_test.dart`.
- Progression: `lib/state/unlocks.dart` (`openFeaturesProvider`, intro bookkeeping) and `Unlocks` /
  `OpenFeatures` in `lib/state/rewards.dart`: Squares, Triangles, Hexagons, Painting and giant boards open at
  levels 2/4/6/8/10 or once used; `lib/features/game/unlock_intro.dart` (intro sheet, `UnlockIntroHost`).
  Giant boards can be opened early from a giant pack's gate: the pack's tickets plus `Economy.giantEarlyFee`
  (1 ticket per level to go), recorded as `early:giant` in `profiles.unlockedTiers`.
  Quests: `Goals.daily` / `weekly` rotate by day and week and take `open`, `level`, `claimed` (and the
  daily puzzle); each quest comes from a different lane, chosen against the player's `PlayHabits`, so
  ordinary play finishes only "Solve 3 puzzles" and one board never finishes two (docs/economy.md, "Quests
  that do not overlap");
  `lib/features/events/quest_rewards.dart` (`questsFor`, `readyGoals`, `readyEventsProvider`, Claim all).
  Integration suites that play every shape override `openFeaturesProvider` and `pendingUnlockIntroProvider`.
- Deep links (`docs/deep-links.md`): `lib/core/app_links.dart` (`AppLink.parse`: one path set for the web
  address, `carden://` (and the first name's `cardjigsaw://`) and universal links; kinds page/overlay/action) and
  `lib/features/links/deep_links.dart` (`DeepLinks.show`: Home beneath overlays, sheets for `/redeem?code=`,
  `/add-friend?code=`, `/gift`, `/piggy`; a picture in a pack the player has not opened shows the pack). iPhone
  links arrive in `CardJigsawApp.didPushRouteInformation`, a web visit's start address in `routerProvider`.
  Universal links: `applinks:` in `Runner.entitlements` + `web/.well-known/apple-app-site-association`. A new
  link goes into `AppLink.parse`, the association file, the doc and `test/deep_links_test.dart`.
- `lib/state/app_update.dart` + `lib/features/update/update_host.dart`: update prompt (above).
  Web-only page helpers (fetch past the cache, reload) in `lib/core/web_page.dart`; Safari trackpad
  pinch (gesture events) is turned into Flutter's ctrl+wheel zoom by a script in `web/index.html`.
- `lib/state/account_deletion.dart`, `lib/state/review_prompt.dart` (`ReviewRules`: App Store rating after a
  3-star solve or finished pack, 5+ solves, once per version and 120 days), `lib/core/app_review.dart`
  (channel `cjw/review`).
- Routes (`lib/router.dart`): /welcome /home /library /library/pack/:packId /events (Quests) /social
  /profile (+settings, account, my-puzzles) /play/:puzzleId (difficulty) /game/:puzzleId/:grid /store
  /wheel /account /auth/callback /player/:userId. One `GoRouter` for the app's life (it listens to
  `onboarded` instead of being rebuilt, so a link that finishes onboarding keeps its screen).

## Backend (Appwrite Cloud)

- Endpoint `https://fra.cloud.appwrite.io/v1`, project `6acb4de5003e38d5ebd9`, database `cjw`
  (tables profiles, packs, puzzles, progress, events, event_progress, friends, ledger, my_puzzles,
  purchases, meta, releases, reports, blocks, feedback). Profiles are readable by anyone; `level` mirrors XP; aggregates `totalMoves`,
  `totalSeconds`, `solvedByMode`, `questsCompleted` and the "Total Completion" numbers
  (`picturesSolved`, `picturesPerfect`, `packsCompleted`, `packsPerfect`, kept in step by
  `ProfileNotifier.syncCompletion`, backfill `tools/dev/backfill_profile_stats.py`) are public.
  `isTest` marks QA players (excluded from the league). `profiles.appliedOps` / `event_progress.appliedOps` (ids
  of applied sync ops, exactly-once retries) and `progress.session` (play-through id) belong to the save sync.
  `progress.painting` marks a Painting board (x1.25); `progress.par` / `peeked` / `bestLock` feed the quests. `purchases.ownership` / `purchases.appTransactionId`
  (index `idx_apptx`) track Family Sharing (VIP is family-shared since 2026-10-14, irreversible; at most 6
  game accounts per subscription).
- Report and block (guideline 1.2, owner 2026-10-15): Player > Report writes a `reports` row (reporterId,
  reportedId, reportedName, reason as text) with no permissions, so only the server reads it; read and close
  them with `tools/dev/reports.py` (look regularly: Apple wants timely responses). Player > Block writes a
  `blocks` row readable only by the blocker; blocked players are left out of their leaderboard (one
  `Query.notEqual('$id')` each) and their friendship ends; Settings > Blocked players unblocks. Both tables are
  deleted in both directions with an account (`delete-account`, `PAIR_TABLES` in `tools/dev/cjw_admin.py`).
  `lib/state/social.dart` (`PlayerSafety`, `blockedPlayersProvider`), `lib/features/social/player_safety.dart`.
- Help (owner, 2026-10-15): Settings > Help > Contact support opens an email to support@almostapps.eu with
  the version and player id below the message (copies the address when there is no mail app); Send
  feedback writes a `feedback` row (userId, message, appVersion, platform) with no permissions, so only the
  server reads it: `tools/dev/feedback.py` lists and closes them. Deleted with the account (`delete-account`)
  and with QA players. `lib/features/profile/help.dart`.
- Legal links: `AppLinks` in `lib/core/links.dart` (privacy policy = `docs/privacy-policy.md` on GitHub, the
  same URL as the listing; terms of use = Apple's standard EULA) in Settings > About, under the VIP plans in
  the store and on the sign-in screen. Keep `docs/privacy-policy.md` true to what the app does.
- Pack codes (`docs/pack-codes.md`): `packs.hidden` packs are listed only for players who own them;
  codes in the server-only `pack_codes` table (SHA-256 hashes) and `code_claims`; function `redeem-code`
  (`/redeem?code=` links everywhere; the Settings row exists on the web only, never in the iPhone app
  (owner, 2026-10-15; guideline 3.1.1)); private pack pictures in bucket `private-packs`, readable
  per claimant. Tools: `tools/dev/private_pack.py`, `tools/dev/pack_codes.py`. The Hidden Object Adventure
  test pack (`pack-hidden-object-test`) is unlicensed art for an internal test only: never make it public.
- Functions: `verify-purchase` (StoreKit 2 JWS verification, grants, App Store Server Notifications at
  `https://cjw-verify-purchase.fra.appwrite.run/notifications`; secret vars can only be updated with
  `secret: true`); `catalog-snapshot` (daily 03:00 UTC: catalogue file in bucket `catalog`, pointer row
  `meta/catalog`; see `docs/catalog-sync.md`; pack rows keep `$createdAt` for the New badge); `delete-account`
  (Profile > Account > Delete account: deletes the caller's rows, uploads and user with a per-execution key;
  secret variable `APPLE_SIGNIN_KEY` (contents of `AuthKey_2QJPJFW8JW.p8`, set 2026-10-15) revokes Sign in
  with Apple tokens; without it the revoke is skipped and logged; it also deletes the player's reports and
  blocks). Deploy functions with the Appwrite CLI (`appwrite functions create-deployment --code functions/<name>`). There is no image proxy: pictures load straight from Storage on every platform.
- Site `card-jigsaw-world` (named Carden) → https://carden.appwrite.network, and the old address
  https://card-jigsaw-world.appwrite.network still serves it (static, fallback index.html),
  deployed by `tools/dev/deploy-web.sh` (chunked upload). Web build hides purchases, gift codes,
  widgets. Apple sign-in on web (configured 2026-10-13): Services ID `com.matejbaco.cardjigsawworld.signin`,
  key `secrets/AuthKey_2QJPJFW8JW.p8`, team `C24QP73SQM`. **Web OAuth must use the token flow** (owner
  rule): full-page redirect to `/account/tokens/oauth2/apple` (the `createOAuth2Token` endpoint), then
  `account.createSession(userId, secret)` on `/auth/callback`, which stores the third-party-cookie
  fallback. Never `createOAuth2Session` (guarded by `test/web_oauth_flow_test.dart`).
- Player photos (My Puzzles, bucket `user-uploads`) are private: each file is `read(user:<owner>)` only, and
  the app fetches them through the signed-in client (`lib/core/image_files.dart`), never as a public URL.
  `test/private_uploads_test.dart` fails if an upload grants `Role.any()`.
- Auth: anonymous guests, email, native Sign in with Apple (`createIdTokenSession`, nonce flow; falls
  back to the existing account on 409). Google/Facebook intentionally removed.
- Appwrite MCP: pass `project_id` as the top-level call parameter, not inside `arguments`.

## App Store / TestFlight

- Bundle `com.matejbaco.cardjigsawworld` (widget `.DailyWidget`), team `C24QP73SQM`, app id
  `6821644423`, primary locale en-GB, iPhone only. Current cycle: version **1.7.0**; build 103 passed the
  full Beta App Review. Apple still wants a beta review submission for every later 1.7.0 build (the workflow
  files it; the log says WAITING_FOR_REVIEW), but those are approved automatically within minutes (108-118
  all were), so public testers get each build shortly after it processes. Apple may still hold any build
  for a real review, most often one that adds a permission prompt or entitlement.
- Groups: "Internal testers" (all builds instantly), "Public testers"
  (https://testflight.apple.com/join/7nPCfg6A).
- Subscriptions: vip_monthly 6821645754 ($2.99), vip_yearly 6821646642 ($14.99), both 1-week trial;
  eight consumables (see `lib/data/purchases.dart`). Gift offer codes exist ("VIP Monthly gift", "VIP Yearly
  gift"); single-use codes can only be minted after the app is live (`tools/store/offer_codes.py`).
- `tools/store/asc_publish.py`: `audit`, `status`, `feedback [--resolve IDS --note TEXT]`,
  `testflight`, `release`, `submit`, metadata/screenshots/iap/subscriptions commands, `events --window N`
  (In-App Event drafts from `store/metadata/app_events.json`, made by `tools/store/make_app_events.py`;
  never submits; Apple allows 15 approved / 10 published), `platforms` (Mac and Vision Pro: TestFlight on;
  App Store availability is two manual ticks in Pricing and Availability). Win-back offers are recorded in
  `store/metadata/subscriptions/vip_*.json`; `subscriptions` creates them once Apple approves the plans. Docs:
  `tools/store/README.md`, `docs/release-flow.md`, `docs/release-checklist.md`.
- Not yet done (owner): App Privacy questionnaire, App Store submission (Paid Apps agreement, banking and tax active since 2026-10-14),
  Mac / Vision Pro availability ticks, restoring
  `secrets/appwrite-storage-key.txt` (the content tool falls back to the users key), pushing the local
  branch `workflow-dsym-check` (needs a GitHub token with the `workflow` scope: `gh auth refresh -s workflow`).
- **Changing what a purchase gives** (coins, tickets, hints per product): three places must agree:
  `functions/verify-purchase/src/main.js` (server grant, then redeploy the function as in
  `docs/purchases.md`), `lib/data/purchases.dart` (what the store screen shows) and
  `store/metadata/subscriptions/consumables.json` (App Store names and descriptions, pushed with
  `asc_publish.py iap`). Product ids such as `coins_1000` cannot be renamed on Apple; keep them.
- **Pack prices** live in the `packs` rows (`priceCoins`, `priceTickets`, `isFree`). The policy and the
  earnings model behind it are in `docs/economy.md`; `tools/store/apply_pack_prices.py` applies it
  (dry run by default, `--apply` writes). The content tool creates new packs at 400 coins or 3 tickets
  and never touches existing prices, so re-run the script after every content session. Only six starter
  library packs are free (`STARTER_PACKS` in that script; owner, 2026-10-14); the script prices any other
  free library pack, and `lib/state/starter_packs.dart` keeps the 45 packs that were free until then open
  for players who had played them.

## Secrets

`secrets/` is git-ignored (only `app-store-connect-issuer-id.txt` is tracked): App Store Connect key
`AuthKey_9QC72A5QMN.p8`, Sign in with Apple key `AuthKey_2QJPJFW8JW.p8` (web browser sign-in, stored in
Appwrite's Apple provider), distribution `Certificates.p12` + password, Appwrite keys
(`appwrite-api-key.txt` rows/tables scopes, `appwrite-storage-key.txt` files/rows scopes for picture
hosting, `appwrite-sites-key.txt`, `appwrite-users-key.txt` users/rows/files scopes for the QA player
purge and stats backfills), `content-keys.env` (`PIXABAY_API_KEY`; the Openverse client id and secret
belong there too but are missing on this Mac, so Openverse runs anonymously at 190 requests a day). Never print or commit their
values. GitHub Actions has the signing secrets.

## Work that may be running in parallel

A picture-catalogue repair may be running in another session (Opus workers under the pack-making
skill, state in `tools/content/reports/state.json`, checkpoints pushed every 30 minutes). If it is:
do not edit `tools/content/**`, the pack-making skill or content docs, do not stop those agents, and
leave these five TestFlight feedback items open (they are the content work's):
AAX-tfwxcKgwk8WC7ZmPEIM, AFs4NDzzaDynNOI55qyTIkM, ANO-zfTaIYOjY-ueQhFp1QM, AEkB37H2zKX9inL57pfg2gE,
AOZ2T5f4FZgO6tNrSO3BovQ (picture quality). Every other open item, including pack prices and the
economy model, is app work.
Their checkpoints commit only their own paths. Content files change every few seconds while it runs,
so integrate remote commits with `git fetch origin main && git merge --no-edit origin/main`; never
`git pull --rebase`, `--autostash` or `git stash` (an autostash once hid the workers' changes), and
never `git checkout`/`restore` files under `tools/content`. `tools/dev/testflight.sh` refuses a dirty
tree, so dispatch the workflow directly as described in the testflight-feedback skill.

## Docs index

`docs/native-ui.md` (glass components), `docs/copy-guide.md`, `docs/sync.md` (save sync), `docs/catalog-sync.md`, `docs/deep-links.md`, `docs/house-ads.md`,
`docs/purchases.md`, `docs/web.md`, `docs/app-updates.md`, `docs/release-flow.md`, `docs/release-checklist.md`,
`docs/content-rules.md`, `docs/content-sources.md`, `store/README.md` (store assets),
`tools/store/README.md`, `README.md`.
