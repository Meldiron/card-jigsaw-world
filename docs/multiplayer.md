# Play together (co-op)

Up to five players play one board at the same time (owner-approved design, 2026-10-17). The host taps
**Play together** in a board's pause menu; the game starts and the share sheet opens with a link,
`https://play.carden.page/join/<code>`, for Messages, WhatsApp, Messenger, Instagram, Snapchat and the
rest. Whoever opens it joins the board: in the app where it is installed (universal link), else in the
web game. Everyone moves cards at once.

Status: **phase 1** is done (backend live, engine, links, share, link preview, the co-op screens as
widgets). **Phase 2** wires the shared board into the game screen (`game_screen.dart`,
`game_controller.dart`, `board_widget.dart`); see "The seam" below.

## What players see

- Their own picks and moves look as today (cobalt). Every other player has a fixed colour on this
  device, by seat: orange, purple, teal, pink (`PlayerColors` in `lib/core/theme/tokens.dart`; never red
  or cobalt), and their **initial** on the card they hold and the cards they just moved
  (`PlayerInitialBadge`, `CoopCardMark`), so players are told apart without colour too.
- Short toasts when someone joins or leaves ("Rowan joined", "Rowan left").
- Moves at the same moment: the server's order decides. A move shows at once; if an earlier move took
  one of its cards, its cards slide back.
- A players chip in the game's top bar (people icon and a count, `CoopPlayersChip`) opens the player
  list (`CoopPlayersPanel`): avatar in the player's colour ring with their initial, name, Host / You,
  Here / Away. A tap on another player opens their profile (Report and Block are there). The host has
  **Remove** on each player, **Invite** while a seat is free and **End game for everyone**; a guest has
  **Leave game**. All three ask first (`coop_alerts.dart`).
- In the pause sheet (phase 2), during a game "Play together" becomes "End game for everyone" (host) or
  "Leave game" (guest), red, confirmed.
- Tools: Shuffle, Magic and Gather change the shared board (sent as changes; whoever uses Magic pays).
  Hint and Peek only show to the player who used them. No Undo in a shared game.
- Finish: the host sees the normal completion card. Guests see their rewards, "Waiting for <host> to
  pick the next board" and Leave game (`CoopGuestFinish`); when the host opens the next board, guests
  are moved onto it (`CoopHost`).
- Rewards: a guest gets the board's usual rewards (XP, coins, piggy bank, level) only if a move of
  their own locked at least one card (`CoopState.placedACard`). A shared board does not count toward a
  guest's quests, achievements, pack progress or first-steps counted pictures (`CoopState.isGuest`).
  The host's board is the host's normal board, saved and counted as always.
- Removed: "Removed from the game" (the player cannot rejoin that game). Ended: "Game ended" with the
  reason (the host ended it, the host left, a day without play). After either, a guest goes to Home, or
  to the welcome pages when they came straight in from an invite.
- Disconnects: switching apps keeps the seat (the others see Away); on return the app reconnects and
  catches up. If the host's app closes, guests can finish the board. A host leaving on purpose (after
  confirming) ends the game. A game idle for a day ends itself.
- Only catalogue pictures can be shared: not My Puzzles photos (private) nor pictures of pack-code
  packs (`canPlayTogether`, checked again by the server).
- Players who blocked each other (either way) cannot join each other's games.

## Backend (Appwrite, live since 2026-10-17)

### Tables

`coop_games` (row security on, **no table permissions**: only the functions write it). Row id = game
id = team id. Each row: `read("team:<id>")`.

| Column | Type | Notes |
| --- | --- | --- |
| `code` | varchar 12, required | the join code: 8 characters of `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (no 0/O, 1/I/L); unique index `idx_code` |
| `hostId` | varchar 36, required | index `idx_host` |
| `players` | varchar 36 array | user id per seat 0-4, `''` for a free seat; seat 0 is the host's |
| `removed` | varchar 36 array | players the host removed |
| `status` | varchar 16, required | `playing` or `ended`; index `idx_status_active` with `activeAt` |
| `board` | integer, default 1 | the board number; moves carry it |
| `puzzleId`, `grid`, `painting` | varchar 36, varchar 32, boolean | the board (grid in path form, `cards-4x5t3`) |
| `layout` | text, required | the board as dealt, card numbers separated by commas |
| `activeAt`, `endedAt`, `endReason` | datetime, datetime, varchar 16 | `endReason`: `host`, `host-left`, `replaced`, `idle` |
| `isTest` | boolean | a game made by a QA player |

`coop_moves` (row security on, table permission `create("users")` only, no table read). Players create
their own rows with `read("team:<game>")` and `read("user:<self>")` and no update or delete permission.

| Column | Type | Notes |
| --- | --- | --- |
| row id | client-made (20 hex) | fixed per change, so a retry after a lost answer finds the row instead of adding one |
| `gameId`, `board` | varchar 36, integer | index `idx_game` (`gameId`, `board`) |
| `userId` | varchar 36 | index `idx_user` |
| `kind` | varchar 16 | `move`, `magic`, `shuffle`, `gather`; an unknown kind (a later build) still applies |
| `changes` | text | `slot:before:after` per slot, comma separated |

Why a move proves its author: Appwrite lets a client grant only roles it holds (checked live: a row
with `read("user:<someone else>")` is refused with 401), so `read("user:X")` on a row means X wrote it;
`CoopOp.fromRow` drops a row whose `userId` is not backed by its permissions. A player who left or was
removed is no longer in the team and cannot create a row with `read("team:<game>")` (checked live: 401).

### Function `coop-game`

Node 22, `execute: users`, timeout 30 s, scopes `rows.read rows.write teams.read teams.write users.read`
(per-execution key). Deployed 2026-10-17 (deployment `6ad3442da89202830eef`). Source
`functions/coop-game`, rules without a database in `src/rules.js` (`node --test` in the folder).

| POST path | Body | Does |
| --- | --- | --- |
| `/create` | `puzzleId, grid, layout, painting` | checks the picture (a `puzzles` row in a pack that is not `hidden`, not in `private-packs`) and the layout (a permutation, 4-1000 cards), leaves the caller's other games (ends those they host, `replaced`), creates the team (`Co-op <id>`), the host's membership (`host`, `seat0`) and the row |
| `/join` | `code` | refuses `ended`, `removed`, `full` (5) and `blocked` (either way, against every player), leaves the caller's other games, adds a membership with the smallest free seat and seats everyone again (below); a second tap on the link keeps the same seat |
| `/leave` | `gameId` | a guest: membership gone, seat freed; the host: the game ends (`host-left`) |
| `/remove` | `gameId, userId` | host only: the row first (`removed`, seat freed, so the player's app hears it), then the membership |
| `/end` | `gameId` | host only: `status: ended`, `endReason: host` |
| `/next` | `gameId, puzzleId, grid, layout, painting` | host only: `board + 1` and the new board |

Answers: `{ok: true, game}` or `{ok: false, reason, error}` with `reason` one of `full`, `removed`,
`ended`, `blocked`, `picture`, `board`, `host`, `auth`, `server` (the app's `CoopRefusalReason`).

Seats live in the memberships' roles (`seat0`-`seat4`). Two joins at the same moment can take one seat,
or a sixth player can slip in: every call that looks at the memberships decides the same way
(`seating` in rules.js: earliest membership first; a seat taken twice stays with the earlier one, the
later moves to the smallest free seat; past five, the latest are over and removed), and `players` is
written twice (once more after a fresh read). Checked live: four players joining at once got four
distinct seats, a fifth was refused as full.

### Function `coop-cleanup`

Hourly (`0 * * * *`), scopes `rows.read rows.write teams.read teams.write`, deployment
`6ad3442e6d5e7af8c7a1`. Ends games idle for a day (the newest of `activeAt` and the newest move;
`endReason: idle`), deletes games ended an hour ago (moves, team, row), deletes the moves of boards a
game has moved past, and teams `Co-op <id>` without a row (an hour old). `POST /run` does the same on
demand. TablesDB has no row expiry, hence this function.

### Elsewhere

- `delete-account` (redeployed 2026-10-17, `6ad34499b06c74cf5cab`): deletes the player's moves, the
  games they host with every move in them, and empties their seat (and `removed` entry) in other games.
  Teams left without a game go with `coop-cleanup`.
- `tools/dev/cjw_admin.py` (`PLAYER_TABLES`, `HOST_TABLES`) and `tools/dev/purge_test_players.py`:
  a QA player's moves and the games they host go with them (backup first, as for every table).
- Old builds never read these tables or call these functions: nothing a live build reads changed.

## The app

| File | What |
| --- | --- |
| `lib/state/coop/board_change.dart` | `BoardChange`: the slots whose card changed, with the card expected before and the card after; `fits`, `applyTo`, `inverse`, `locks`, `encode` / `decode` (rejects anything that is not a permutation of its own cards) |
| `lib/state/coop/coop_models.dart` | `CoopGame` (row or function answer, `route`, `joinUrl`), `CoopOp` (a move row, author proven by permissions), `CoopPresence`, `CoopRefusal` |
| `lib/state/coop/coop_log.dart` | `CoopLog`, the deterministic shared board (below) |
| `lib/state/coop/coop_controller.dart` | `CoopController` / `coopProvider`: the game on this device, sending, realtime, catch-up, presence, notices |
| `lib/state/coop/coop_backend.dart`, `lib/data/coop_repository.dart` | the server interface and its Appwrite implementation (`coopBackendProvider`) |
| `lib/state/coop/coop_bridge.dart` | `CoopBridge` / `CoopBoardTarget`: the seam for the game screen |
| `lib/features/coop/` | `CoopHost` (toasts, alerts, next board, app life; in `lib/app.dart`), `players_sheet.dart` (chip and list), `coop_alerts.dart`, `guest_finish.dart`, `join_flow.dart` (`openInvite`, `startPlayTogether`, `canPlayTogether`), `share_invite.dart`, `coop_players.dart` (seats, colours, initials, card marks), `coop_routes.dart` |

### The shared board (`CoopLog`)

- A change applies only when every one of its slots holds the card it expects; otherwise the whole
  change is skipped. Every device applies the same changes in the server's order (`$sequence`) with
  this rule, so every device shows the same board whatever order the changes arrive in.
- Realtime keeps no order (measured: 6 to 11 of 30 events of a burst arrived after a higher
  `$sequence`), and a catch-up brings changes twice. A change is kept once (row id); one that belongs
  before changes already applied undoes them (exact inverses), takes its place and applies them again.
- Own changes show at once (pending) and are applied after the confirmed ones. When the server's order
  puts another player's change first and it took their cards, they leave the board shown:
  `LogUpdate.dropped`, their cards slide back. They are still sent (they may be in flight); when their
  place in the order arrives, the rule decides for everyone.
- This device's changes are sent one at a time in the order made (a change builds on the one before),
  retried with backoff (1 s to 30 s); a refusal (not in the team any more) drops them all.
- Catch-up (`movesAfter`, `$sequence` greater than n, every page): on start, on resume, after a
  realtime error, when this device's own presence stops coming back over its socket (the presence is
  re-sent every minute as a keep-alive; its echo proves the socket; an echo nobody asked for is the
  SDK re-sending it after a reconnect), and every 2 minutes anyway. It starts
  from the change received 30 s before the newest one (`catchUpFrom`), because a change committed a
  moment before another can arrive after it.
- `locksBy(user)`: cards a player's own moves locked (Magic, Shuffle and Gather do not count).
- Boards: changes of another board number are ignored; the host's next board starts a new log.

### Presence

`realtime.upsertPresence(status: online|away, presenceId: md5(coop:<game>:<user>), permissions:
[read(team:<game>)], metadata: {g: game, b: board, h: held card or -1})`, on its own subscription to
`presences` (a query on a subscription applies to all its channels, so it cannot share the moves'
one). At most one update per 3 s (`CoopTiming.presenceGap`): a socket may send about 32 messages a
minute and the SDK's heartbeat takes 3. Gone when the socket closes (checked live: the others get a
`delete` event). In the background the app sends `away`; on resume `online` and a catch-up.

### The seam (phase 2)

The game screen makes a `CoopBridge(ref.read(coopProvider.notifier), target)` while `?coop=<id>` is
in its route (`CoopGame.route` = `/game/<puzzleId>/<grid>?coop=<id>`, plus `&painting=1`), where
`target` implements `CoopBoardTarget` over its `GameController`:

- after every change the player makes (a move, Magic, Shuffle, Gather):
  `bridge.localChange(CoopOpKind.move, before, after)` with the board's `slots` before and after
  (returns false when the board had changed under it; the screen is put back on the shared board);
- `CoopBoardTarget.showShared(CoopBoardUpdate u)`: put `u.update.after` on the board without counting a
  move or adding Undo history; animate `u.update.changedSlots`; `u.update.applied` names who moved what;
  `u.update.dropped` is this player's own change sliding back;
- `coop.hold(card)` when the player picks a card up, `coop.hold(null)` when they put it down;
- the board draws `coopCardMarks(context, ref, state)` (card number to outline colour and initial);
- the HUD shows `CoopPlayersChip`; the pause sheet swaps Play together for End game for everyone /
  Leave game; the guest's completion shows `CoopGuestFinish(rewards: ...)` (rewards only when
  `state.placedACard`); the finish is `state.solved` (every device agrees);
- the host's "Next puzzle" calls `coop.nextBoard(puzzleId:, grid:, layout:)` then opens its route;
- Play together in the pause sheet calls `startPlayTogether(context, ref, puzzle:, grid:, layout:,
  painting:)`; hide it when `!canPlayTogether(ref, puzzle)`;
- guests: no Undo; Hint and Peek stay local; the guest's progress, quests, achievements, pack progress
  and first-steps counts are not written for a shared board.

### Links

`/join/<code>` (`AppLink.parse`, kind action, code normalised to upper case) on the web address,
`carden://` and `cardjigsaw://`; `/join/*` in `web/.well-known/apple-app-site-association` (the site
must be deployed before a build that shares links). `DeepLinks.show` hands it to `openInvite`: a
"Joining the game" sheet (the function can take seconds to wake up), the function, then the board's
route above what is on screen. A new install goes straight to the board; onboarding is not set, so the
welcome pages and the guided start begin when the player leaves the game (the router's redirect
ignores `?coop=` routes; a web visit on `/join/` starts on the welcome pages).

The web page of an invite (`web/index.html`): on an iPhone or iPad the page first offers **Open in
Carden** (a link to `https://carden.appwrite.network/join/<code>?open=1`: another domain the app claims,
which iOS hands to the app, also from in-app browsers that keep same-domain links) and **Play in the
browser**; the game itself loads only after the second, so an invite opened in the app never takes a
seat in the browser too. Without the app, that address shows the page again with "open this page in
Safari", the browser and the App Store. Instagram's and Snapchat's browsers never open universal links,
Messenger's only sometimes, hence the page.

### Share and preview

`shareInvite` (share_plus 13.3.1): "Play <picture> with me in Carden" and the link, on the iPhone's
share sheet or the browser's (Web Share API); without one the link is copied. share_plus was read
before it was added: on iOS it opens `UIActivityViewController` and builds the preview title itself
(no metadata fetch); on the web its mailto fallback is turned off. The link preview is
`web/invite-card.jpg` (1200 x 630, 92 KB; `tools/brand/invite_card.py`), the `og:image` of every page
with `og:image:width/height`: Messages and WhatsApp read static tags only.

## Measured (live backend, QA players, 2026-10-17)

From this Mac (Node, raw protocol; rerun after the Mac's hibernation at 11:57, same numbers):

| What | p50 | p90 | max |
| --- | --- | --- | --- |
| create a move row (HTTP round trip) | 94-127 ms | 185-222 ms | about 1.1 s (first request) |
| create on one client to the realtime event on another | 101-129 ms | 188-275 ms | about 1.1 s (first) |
| presence update to the other client | 127-149 ms | 207-254 ms | |
| `coop-game`: create (cold) / create, join, leave, remove, end (warm) | 7.4 s cold; 0.1-1.2 s warm; 4 joins at once about 2 s each | | |

`$sequence`: unique under 30 concurrent creates from two clients; HTTP answers came back out of order
(9-10 of 30) and realtime events too (6-11 of 30 per socket); `$createdAt` order disagreed with
`$sequence` 6-8 times (do not order by it). `Query.greaterThan('$sequence', n)` with `orderAsc` works.
On the iPhone 17 Pro simulator (the app's real SDK, `integration_test/coop_live_test.dart`, while the
Mac ran other builds at a load of several hundred): a move of this device reached the host bot's socket
in 100-206 ms (median 175); a host move reached the device's board in 199-666 ms (median 333), which
includes the test's HTTP request to the bot on the Mac and the bot's own create. Also checked there:
`Query.greaterThan('$sequence', 0)` is refused (400), so a catch-up from the start sends no
`$sequence` filter.

## Limits and costs

- Appwrite: 120 row creates a minute per user and IP (a fast player makes well under 60 moves a
  minute); about 32 socket messages a minute (presence throttled to 20 at most); Pro plan: 500
  concurrent realtime connections, 6M realtime messages and 750k writes a month.
- A move = 1 write + 1 realtime message per connected player (the author's own echo included); a
  presence update (a pick, the keep-alive once a minute) = 1 message per player. A 20-card board with 3 players takes about 40 moves:
  about 40 writes, 120 move messages and up to 120 presence messages, plus a few dozen row reads
  (joining, catch-ups, the 2-minute safety read).
- So one such game is about 40 writes and 250 messages: 300 games a day stay inside Pro (about 360k
  writes and 2.3M messages a month); about 600 games a day reach the included writes (750k) and 800 the
  included messages (6M).

## QA

- Unit: `test/coop_log_test.dart` (100 seeds of three players moving at random with random delivery
  and answers end on the server's board everywhere; conflicts; late answers; doubles; catch-up start),
  `test/coop_controller_test.dart` (devices on `test/support/fake_coop.dart`: joining, any delivery
  order, a lost answer, a lost connection, removal, end, next board, presence, marks, rewards, the
  bridge), `test/coop_ui_test.dart` (colours and contrast, the chip, the list as host and guest, the
  guest's finish at the SE size, both themes, Increase contrast, Largest text), `test/deep_links_test.dart`
  (`/join` links, the association file, an invite from a fresh install, a full game).
- `functions/coop-game`: `node --test`.
- Live: `node tools/dev/coop_bot.mjs &` then `tools/dev/qa-run.sh drive
  --driver=test_driver/integration_test.dart --target=integration_test/coop_live_test.dart -d <sim>`:
  a fresh install joins the bot's game from an invite, moves go both ways, presence, a toast, the player
  list as guest and host, removed, full, ended, dark and Increase contrast at Largest text
  (`screenshots/coop_*.png`). The bot cleans up its players when the test sends `/quit`. Passed on
  2026-10-17 (iPhone 17 Pro, iOS 26.5).
- The invite page: serve a copy of `web/` with `<base href="/">` and the single-page fallback, open
  `/join/<code>` in the simulator's Safari (`xcrun simctl openurl`): the card shows and the game does
  not load (`flutter_bootstrap.js` is not requested) until Play in the browser; `?open=1` shows the
  fallback (Play in the browser first, Get Carden on the App Store).
