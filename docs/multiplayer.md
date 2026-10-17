# Play together (co-op)

Up to five players play one board at the same time (owner-approved design, 2026-10-17). The host taps
**Play together** in a board's pause menu; the game starts and the share sheet opens with a link,
`https://play.carden.page/join/<code>`, for Messages, WhatsApp, Messenger, Instagram, Snapchat and the
rest. Whoever opens it joins the board: in the app where it is installed (universal link), else in the
web game. Everyone moves cards at once.

Status: done in the app (2026-10-17). Phase 1: backend live, engine, links, share, link preview, the
co-op screens as widgets. Phase 2: the shared board wired into the game screen (`game_screen.dart`, one
method in `game_controller.dart`, `board_widget.dart`, `giant_board.dart`); see "The game screen"
below. It reaches players with the first build after the site is deployed (the association file and
the invite page).

## What players see

- Their own picks and moves look as today (cobalt). Every other player has a fixed colour on this
  device, by seat: orange, purple, teal, pink (`PlayerColors` in `lib/core/theme/tokens.dart`; never red
  or cobalt), and their **initial** on the card they hold and the cards they just moved
  (`PlayerInitialBadge`, `CoopCardMark`), so players are told apart without colour too.
- Short toasts when someone joins or leaves ("Rowan joined", "Rowan left").
- Live (owner, 2026-10-17): a card another player picks with a tap shows in their colour with their
  initial within a fraction of a second, and goes as soon as they put it down or place it. A card they
  drag lifts out of its slot and travels with their finger (with its joined group), outlined in their
  colour with their initial; when their move arrives it lands from there in its slot. A drag they
  cancel, one not heard from for 2 s, or a drop whose move does not come within 2 s goes back. Reduce
  motion: the card is drawn at the newest position, without the glide. See "Live picks and drags".
- Moves at the same moment: the server's order decides. A move shows at once; if an earlier move took
  one of its cards, its cards slide back.
- A players chip in the game's top bar (people icon and a count, `CoopPlayersChip`) opens the player
  list (`CoopPlayersPanel`): avatar in the player's colour ring with their initial, name, Host / You,
  Here / Away. A tap on another player opens their profile (Report and Block are there). The host has
  **Remove** on each player, **Invite** while a seat is free and **End game for everyone**; a guest has
  **Leave game**. All three ask first (`coop_alerts.dart`).
- In the pause sheet, during a game "Play together" becomes "End game for everyone" (host) or
  "Leave game" (guest), red, confirmed. A guest's "Save & quit" is "Quit": leaving the board keeps the
  seat, and a toast offers Return.
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
  reason (the host ended it, the host left, a day without play). Behind the alert the guest's board
  keeps its guest look (no completion card of their own, nothing saved); after Close a guest goes to
  Home, or to the welcome pages when they came straight in from an invite. The host keeps the board
  ("Game ended. The board is yours.").
- Return to game: the game is remembered on the device (`coop.active` in the local store) while the
  player has a seat. Leaving the board (Quit) shows "The game goes on. Return to it any time." with
  Return; after a restart, the first screen that is not the welcome pages or a board shows "Your game
  with <host> is still on" with Return (`offerReturnToGame`). Forgotten when the game ends, or the
  player leaves or is removed.
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

### The co-op calls (`/coop/<action>` on function `api`)

Since 2026-10-17 the game calls are paths of the `api` function (docs/functions.md): source
`functions/api/src/coop/game.js`, rules without a database in `functions/api/src/coop/rules.js`
(`functions/api/test/coop-rules.test.mjs`). Builds up to 124 call the function `coop-game` (Node 22,
`execute: users`, scopes `rows.read rows.write teams.read teams.write users.read`, deployment
`6ad3442da89202830eef`) at `/<action>`: the same code, frozen, deployed for them. Both write the same rows
and teams, so players of old and new builds play in one game.

| POST path | Body | Does |
| --- | --- | --- |
| `/coop/create` | `puzzleId, grid, layout, painting` | checks the picture (a `puzzles` row in a pack that is not `hidden`, not in `private-packs`) and the layout (a permutation, 4-1000 cards), leaves the caller's other games (ends those they host, `replaced`), creates the team (`Co-op <id>`), the host's membership (`host`, `seat0`) and the row |
| `/coop/join` | `code` | refuses `ended`, `removed`, `full` (5) and `blocked` (either way, against every player), leaves the caller's other games, adds a membership with the smallest free seat and seats everyone again (below); a second tap on the link keeps the same seat |
| `/coop/leave` | `gameId` | a guest: membership gone, seat freed; the host: the game ends (`host-left`) |
| `/coop/remove` | `gameId, userId` | host only: the row first (`removed`, seat freed, so the player's app hears it), then the membership |
| `/coop/end` | `gameId` | host only: `status: ended`, `endReason: host` |
| `/coop/next` | `gameId, puzzleId, grid, layout, painting` | host only: `board + 1` and the new board |

Answers: `{ok: true, game}` or `{ok: false, reason, error}` with `reason` one of `full`, `removed`,
`ended`, `blocked`, `picture`, `board`, `host`, `auth`, `server` (the app's `CoopRefusalReason`).

Seats live in the memberships' roles (`seat0`-`seat4`). Two joins at the same moment can take one seat,
or a sixth player can slip in: every call that looks at the memberships decides the same way
(`seating` in rules.js: earliest membership first; a seat taken twice stays with the earlier one, the
later moves to the smallest free seat; past five, the latest are over and removed), and `players` is
written twice (once more after a fresh read). Checked live: four players joining at once got four
distinct seats, a fifth was refused as full.

### The hourly cleanup (function `api`'s schedule)

Hourly (`0 * * * *`, function `api`: a scheduled execution runs `functions/api/src/coop/cleanup.js`;
it was the function `coop-cleanup` until 2026-10-17). Ends games idle for a day (the newest of `activeAt` and the newest move;
`endReason: idle`), deletes games ended an hour ago (moves, team, row), deletes the moves of boards a
game has moved past, and teams `Co-op <id>` without a row (an hour old). `POST /coop/cleanup` does the
same on demand for a caller who is not a player (`appwrite functions create-execution --function-id api
--path /coop/cleanup --method POST`). TablesDB has no row expiry, hence this job.

### Elsewhere

- Account deletion (`/account/delete` on `api`; `delete-account` for builds up to 124): deletes the
  player's moves and live rows, the games they host with every move and live row in them, and empties
  their seat (and `removed` entry) in other games. Teams left without a game go with the hourly cleanup.
- `tools/dev/cjw_admin.py` (`PLAYER_TABLES`, `HOST_TABLES`) and `tools/dev/purge_test_players.py`:
  a QA player's moves, live rows and the games they host go with them (backup first, as for every table).
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
| `lib/state/coop/coop_live.dart` | live picks and drags: `CoopLive` (a live row's state), `LiveSender` (pace, budget, what goes at once), `DragPath` and `LiveTracks` (the others' drags played back) |
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

### Live picks and drags (`coop_drags`)

Owner, 2026-10-17: "When I drag a piece and move it around the screen, it should also move around
for the other players", and the card each player has picked must show at once too. Presence allows
about 30 messages a minute per socket and is throttled to one per 3 s, so it now only says who is here
or away (it still carries the picked card, `h`, for builds without live rows).

**One row per player and game** in `coop_drags` (live since 2026-10-17; row security on, **no table
permissions**: players cannot create rows). Row id = md5 of `live:<game>:<player>` (`CoopLive.rowId`,
`liveRowId` in `functions/api/src/coop/rules.js`; both tests check one value). Permissions
`read("team:<game>")` and `update("user:<player>")`, so a row proves its player and a player who left
cannot reach the others through it. Columns: `gameId`, `userId` (varchar 36, required; indexes
`idx_game`, `idx_user`), `board`, `drag` (the drag's start in ms), `seq` (increasing per player, in ms,
so a restarted app still sends higher numbers), `t` (ms since the drag started, when the finger was
there), `card` (-1: none), `x`, `y` (double: the card's centre as a fraction of the board, so any
screen size and any zoom work), `phase` (`''` nothing in hand, `pick`, `drag`, `drop`, `cancel`).

- The `api` function makes the row on `/coop/create` (the host) and `/coop/join` (also a second join
  of the same player), and deletes it on `/coop/leave` (a guest) and `/coop/remove`. The hourly cleanup
  deletes the rows of the games it deletes (and of teams without a game); account deletion and the
  purge tool delete a player's rows and those of the games they host; the integrity sweep deletes a
  row whose id, permissions, game or seat is wrong (`liveVerdict`: a player who changed its columns, a
  player no longer in the game, a game that is gone).
- Sending (`LiveSender`): a pick, a put-down, the start and the end of a drag go at once; positions
  every 200 ms while the finger moves (the newest only). One update at a time; while one is on its way
  only the newest state waits, but the end of a drag (drop or cancel) is never folded into what
  follows. Appwrite allows **120 row updates a minute per player** (measured: `X-RateLimit-Limit: 120`,
  a fixed one-minute window, the 121st refused with 429), so the sender keeps under 110 in any minute:
  5 positions a second while under 45% of that, 3 under 70%, 2 under 85%, 1 under 95%, then no
  positions (picks and drag ends still go, waiting for the minute if they must); after a 429 it waits
  10 s. A missing row (a game made before live rows, or through `coop-game`) stops sending for that game.
- Receiving: a third realtime subscription on `coop_drags` rows with `gameId = <game>` and
  `userId != <me>` (checked live: no echo of the player's own updates). `CoopLive.fromRow` drops a row
  whose `userId` is not backed by `update("user:...")`; states older than one already heard are
  dropped (`seq`). Picks become the held marks (`CoopMarks.held`; the presence's `h` only for players
  whose live row was never heard). A drag is played back (`DragPath`) on the sender's own clock (`t`),
  150 to 600 ms behind the newest position (one gap between positions plus the network's jitter), with
  straight lines between positions, never backwards. The others' move (or a skipped one) carrying the
  card ends the drag: the board takes the card from where it is drawn to its slot.
- The board (`BoardWidget.ghosts`, a `ValueListenable` the game screen updates every frame while a
  drag is shown) draws the card and its joined group lifted at that place, above other cards and below
  this player's own drag, in the player's colour with their initial (`coop-drag-<card>`); a card in
  place is never lifted. This player's drags are reported by `BoardWidget.onDragMove` / `onDragEnd`
  (fractions of the board, the end after the drop). Giant boards: the same fractions; a drag out of view
  shows on the off-screen pointer (`OffscreenSelection.point`, their initial) and as a dot on the map
  (`GiantMinimap.otherPoints`); picks there as before.
- Builds up to 125 neither write nor read live rows: they play as before (their picks travel by
  presence, every 3 s at most), and new builds see them that way.
- Twin cards: a dragged card that lands on a twin's place traded identities on the mover's screen;
  the move carries both cards, so the drag ends there too and `sharedCardKeys` keeps the widgets.

### The game screen (phase 2, wired)

`/game/<puzzleId>/<grid>?coop=<id>` plays the game's shared board (`&next=1`: the host deals the next
board on that screen and hands it to the game). What the screen does in a game:

- The board starts from the shared layout (`CoopLog.layout`); the host keeps their moves and time, a
  guest starts at 0. The first-board coach and the fit-to-picture step are skipped.
- Every local change (a move, a drop, Magic, Shuffle, Gather) goes through `bridge.localChange` with
  its kind; the others' changes come in through `_SharedBoard.showShared`, which calls
  `GameController.showShared(layout)`: the board changes without a move, without Undo history, and
  with the lock and win events (the only change in `game_controller.dart`).
- Picking a card up sends `coop.hold(card)`; the board draws `coopCardMarks` (outline in the player's
  colour and their initial; held cards solid, just moved ones faded). Giant boards: marks at any zoom,
  the others' held cards as dots on the overview map and an off-screen pointer with the player's
  initial.
- No Undo anywhere (toolbar, the Gather toast); Hint and Peek stay local.
- The host's board is saved and counted as always (also after the others' changes). A guest's board is
  never saved, and its finish is `CoopGuestFinish`: rewards (`ProfileNotifier.recordCoopReward`, sync
  op `coopReward`: coins, XP, level and its rewards, piggy bank; nothing else) only when a move of
  theirs locked a card.
- The host's finish is the normal completion card; Next puzzle (and Replay) deal the next board,
  `coop.nextBoard`, and move the guests onto it.
- Twin cards (`docs/twins.md`): a board dealt here is dealt again once its twins are measured, so
  Play together and the next board wait for that (`awaitsTwins`) and share the final deal; a guest's
  board is made from the shared layout and is never dealt again. A move can trade two twins'
  identities on the mover's screen (`Twins.settle`); the change then holds the two cards exchanging
  slots, and `GameController.sharedCardKeys` keeps their widgets where the mover's screen keeps them
  (the dropped card's widget lands, the twin's widget stays and fades to its new picture) instead of
  flying them across the board. Twins are measured on each device from its own decode of the picture:
  if two devices ever disagree, the shared log still decides the board (changes are slot
  permutations, checked card by card), so only that animation differs. Old rows need nothing new.

### The seam

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
Carden** and **Play in the browser**; the game itself loads only after the second, so an invite opened in the
app never takes a seat in the browser too. Open in Carden opens `carden://join/<code>`, which iOS always hands
to the installed app (after asking "Open in Carden?"), whatever the phone's copy of the association file
says: a phone whose copy predates `/join` (iOS fetches it on install or update and only now and then after)
shows this page even with the app installed, and the universal-link route it used before (2026-10-17, build
124: `https://carden.appwrite.network/join/<code>?open=1`) then did nothing for the owner's friend. If the
page is still on screen 2.5 s after the try, the app is not there and the card offers Play in the browser
first, then Get Carden. Instagram's and Snapchat's browsers never open universal links,
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
| `api` `/coop/*` (warm, `tools/dev/api_check.mjs`) | create 0.9 s, join 0.8-1.3 s, leave 1.5 s, remove 0.9 s, next 0.6 s, end 0.3 s | | |

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

Live picks and drags (measured 2026-10-17; from this Mac, the app on the iPhone 17 Pro simulator):

| What | Measured |
| --- | --- |
| row update on one client to the realtime event on another (Node, 5 a second for 25 s) | p50 108-119 ms, p90 230 ms; 1 in 82 took 2.2 s (a slow request); no event out of order |
| the bot's pick to the mark on the app's board / its put-down to the mark gone (two runs, 5 each) | p50 157-225 ms (97-240) / p50 104-127 ms (95-138; once 2.0 s) |
| the app's pick and put-down to the bot's socket | 92-194 ms (once 1.4 s) |
| the app's drag positions to the bot's socket (two runs) | p50 98-124 ms, p90 171-208 ms, max 181-236 ms; 5 a second |
| the bot's first drag update to the card lifted on the app / its move to the card landed in its slot | 103-156 ms (p50 145) / 110-369 ms (p50 125) |
| two simulators, the host's finger to the guest's screen (`coop_pair_test.dart`, timed through the relay, which adds up to 0.7 s) | pick 358 ms, drag lifted 705 ms, drop to landed 333 ms |

Now and then one request takes 1.4-2.2 s (seen in every kind of run, about 1 in 50-80): a pick or a
put-down then shows that late; a drag stalls and catches up (it is never shown backwards).

The card on the other screen follows the finger about a quarter to half a second behind: the network
(about 0.1-0.25 s) plus the play-back buffer (0.15-0.3 s with these numbers), which turns 5 positions a
second into a glide.

Cost of live rows: every update is 1 write and 1 realtime message for each other player connected
(no echo to the sender).

- Worst case, 5 players dragging without a pause: at most 110 updates a minute each, so 550 writes and
  2,200 messages a minute for the game.
- Normal play: a drag of about a second is about 6 updates (start, 4 positions, drop), a tap-and-tap
  move 2 (pick, put-down). A 20-card board with 3 players (about 40 moves, half of them dragged) adds
  about 160 writes and 320 messages to the moves' 40 writes and 250 messages: about 200 writes and 570
  messages a game.
- So the included writes (750k a month on Pro) last for about 3,700 such games a month (about 125 a
  day) before extra writes are billed, and the messages (6M) for about 10,000. Writes are the limit
  now; if they matter, 3 positions a second cut a drag's writes by about a third.

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

## Analytics

`coop_game_created`, `coop_invite_shared`, `coop_game_joined` (fresh install or not, app or web),
`coop_game_left`, `coop_game_ended` (by the host, or heard: host, host-left, idle, replaced),
`coop_player_removed`, `coop_next_board`, `coop_returned`; props are counts and board sizes only (no
codes, game ids or player ids). Table in `docs/analytics.md`.

## Get Carden

Until the App Store release, "Get Carden" (the invite page's fallback, `GET_CARDEN` in
`web/index.html`, and `AppLinks.getCarden`) opens the public TestFlight link; both switch to the App
Store page at launch (`docs/release-checklist.md`, "After approval"). `test/deep_links_test.dart` keeps
the two equal.

## QA

- Unit: `test/coop_log_test.dart` (100 seeds of three players moving at random with random delivery
  and answers end on the server's board everywhere; conflicts; late answers; doubles; catch-up start),
  `test/coop_controller_test.dart` (devices on `test/support/fake_coop.dart`: joining, any delivery
  order, a lost answer, a lost connection, removal, end, next board, presence, marks, rewards, the
  bridge), `test/coop_ui_test.dart` (colours and contrast, the chip, the list as host and guest, the
  guest's finish at the SE size, both themes, Increase contrast, Largest text), `test/deep_links_test.dart`
  (`/join` links, the association file, an invite from a fresh install, a full game).
- `functions/api`: `npm test` (co-op rules in `test/coop-rules.test.mjs`); live, every co-op route: `node tools/dev/api_check.mjs`.
- Live: `node tools/dev/coop_bot.mjs &` then `tools/dev/qa-run.sh drive
  --driver=test_driver/integration_test.dart --target=integration_test/coop_live_test.dart -d <sim>`:
  a fresh install joins the bot's game from an invite, moves go both ways, presence, a toast, the player
  list as guest and host, removed, full, ended, dark and Increase contrast at Largest text
  (`screenshots/coop_*.png`). The bot cleans up its players when the test sends `/quit`. Passed on
  2026-10-17 (iPhone 17 Pro, iOS 26.5).
- Phase 2, on the real game screen (the bot plays the other player; the same `node tools/dev/coop_bot.mjs &`):
  `integration_test/coop_live_test.dart` is the guest (a fresh install joins by link; the host's moves
  and held card with colour and initial; a move of its own; a conflict slides back; Magic and Shuffle;
  background and catch-up; Quit and Return; Return to game after a restart; the player list; next
  board; a finish without and with rewards, the rewards rule checked on the profile and progress;
  removed; ended; Gather on a giant board; Leave game; `screenshots/coop2_*.png`), and
  `integration_test/coop_host_test.dart` is the host (Play together from the pause sheet, the share
  text, the friend joins and moves, the host's move reaches the friend, the completion card, Next
  puzzle moves the friend, Remove, End game for everyone; `screenshots/coop2h_*.png`). The share sheet
  is replaced by a recorder (`share_plus_platform_interface`, a dev dependency).
- Two simulators: `integration_test/coop_pair_test.dart` runs as the host on one
  (`--dart-define=CJW_COOP_ROLE=host`) and, once its log says "COOP_PAIR waiting for the guest", as
  the guest on the other (`CJW_COOP_ROLE=guest`, a fresh install); they hand the code and boards over
  through the bot's `/relay`. Start the second run only after the first build has finished (two
  builds at once in one checkout break each other). Screens: `screenshots/pair_*.png`.
- Web: `tools/dev/qa-run.sh run -d web-server --web-port 8137`, the bot hosts (`/game`), a browser
  opens `http://localhost:8137/join/<code>` (a fresh visit goes straight onto the board), then the
  bot's `/move`, `/hold`, `/solve`, `/end`. A run stopped from outside keeps its guest: purge it with
  `purge_test_players.py purge --run <id> --apply`.
- Passed on 2026-10-17 (iPhone 17 Pro simulators, iOS 26.5, and Chromium): the guest, host and pair
  suites, and the web flow (join, the host's moves and held card, a move from the browser, the
  guest's finish with rewards, the end).
- `test/coop_board_test.dart`: `GameController.showShared` (no move, no history, selection kept unless
  its card moved) and two screens converging through the bridge.
- Live picks and drags: `integration_test/coop_drag_test.dart` (the bot hosts and streams picks and
  drags: `/pick`, `/drag`; `/live` says what its socket heard, for the delays; `/liverows` makes the live
  rows as the api function does, for QA before the function is deployed with them): the host's pick
  and put-down, a drag across the board in five screenshots and its landing, timed drags, a cancelled
  drag going back, this player's pick and drag reaching the host, and a giant board's off-screen
  pointer for a drag (`screenshots/live_*.png`, delays as `COOP_TIMING`). `coop_pair_test.dart` drags a
  card with the host's finger on one simulator while the other takes screenshots
  (`pair_g03b_host_drag_*.png`). Unit tests: `test/coop_live_test.dart` (the row, the sender's pace,
  budget and refusals on a fake clock, the play-back, the others' states, two devices on the fake
  server), `test/coop_live_board_test.dart` (the board draws and drops a drag, a group, the reports).
- Store: `32_coop_board` in `integration_test/store_screenshots_test.dart` (a scripted game with two
  made-up friends on a stage backend; `CJW_STORE_ONLY=32_coop_board`).
- The invite page: serve a copy of `web/` with `<base href="/">` and the single-page fallback, open
  `/join/<code>` in the simulator's Safari (`xcrun simctl openurl`): the card shows and the game does
  not load (`flutter_bootstrap.js` is not requested) until Play in the browser; Open in Carden opens
  `carden://join/<code>` (with the app installed: the app joins; without it, after 2.5 s the card offers Play in
  the browser first, then Get Carden).
