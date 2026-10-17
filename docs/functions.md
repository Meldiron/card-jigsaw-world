# Appwrite Functions

Owner, 2026-10-17: every server call of the app goes to **one** function, `api`, with a path per
feature. A function that is called often stays warm; seven functions that are each called now and
then each start cold (4 to 5 s before the function's own work; 7.4 s for a co-op create). One function
shares everyone's calls, so a player meets a cold start far less often.

## `api` (functions/api)

| Path | Module | What | Was |
| --- | --- | --- | --- |
| `POST /purchase/verify` | `src/purchase.js` | a StoreKit transaction, granted once (docs/purchases.md) | `verify-purchase` `/verify` |
| `POST /purchase/notifications` | `src/purchase.js` | App Store Server Notifications V2; Apple still sends them to `verify-purchase` (below) | `verify-purchase` `/notifications` |
| `POST /account/delete` | `src/account.js` | Account > Delete account | `delete-account` `/delete` |
| `POST /code/redeem` | `src/code.js` | a pack code, on the web (docs/pack-codes.md) | `redeem-code` `/redeem` |
| `POST /coop/create`, `/join`, `/leave`, `/remove`, `/end`, `/next` | `src/coop/game.js` (+ `rules.js`) | Play together (docs/multiplayer.md) | `coop-game` `/<action>` |
| `POST /gift/send` | `src/gift/send.js` (+ `gift.js`) | friend gifts (docs/friend-gifts.md) | `send-gift` `/send` |
| `POST /coop/cleanup` | `src/coop/cleanup.js` | the co-op cleanup on demand, for a caller who is not a player (the owner's CLI) | `coop-cleanup` `/run` |
| `POST /admin/sweep` | `src/sweep/run.js` | the integrity sweep on demand, same callers: `{dryRun = true, full, qaOnly}` (below) | new |
| `GET /health` | `src/main.js` | `{ok, environment, maxPlayers, appleSignIn}`; the app's warm-up call | every function's `/health` |
| schedule `0 * * * *` | `src/coop/cleanup.js`, `src/sweep/run.js` | every hour: the co-op cleanup, then the integrity sweep (an execution with trigger `schedule`, whatever its path) | `coop-cleanup` |
| event `tablesdb.cjw.tables.blocks.rows.*.create` | `src/sweep/run.js` | a new `blocks` row is checked at once (subscribed as `databases.cjw.tables.blocks.rows.*.create`) | new |

Each module answers as its old function did (same bodies, same status codes), so the app reads the
same answers; only the router (`src/main.js`) is new. Modules load on their first call, so a cold
start loads only what that call needs (the App Store library only for purchases). Nothing runs at the
root path or at the old paths (`POST /` used to delete the caller's account on `delete-account`).

Settings: Node 22, entrypoint `src/main.js`, build `npm install`, execute `users` (guests too), timeout
300 s (the cleanup; a synchronous call from the app is cut at 30 s by Appwrite anyway), scopes `rows.read
rows.write users.read users.write files.read files.write teams.read teams.write messages.read
messages.write` (the union of the old functions'). Variables: `APPLE_BUNDLE_ID`, `APPLE_APP_ID`,
`APPLE_ENVIRONMENT` (`Production`), `APPWRITE_DATABASE_ID` (`cjw`), `APPLE_SIGNIN_KEY` (the contents of
`secrets/AuthKey_2QJPJFW8JW.p8`; `/health` says `appleSignIn: "set"` when it reads), all secret, and
`SWEEP_APPLY` (`true`: the scheduled and event sweeps change rows; anything else: they only report).
A changed variable reaches the function with its next deployment.

Deploy with the Appwrite CLI signed in as the owner, from a folder holding an `appwrite.config.json`
with `{"projectId": "6acb4de5003e38d5ebd9", "endpoint": "https://fra.cloud.appwrite.io/v1"}`: copy
`functions/api` without `node_modules`, then `appwrite functions create-deployment --function-id api
--code <copy> --activate --entrypoint src/main.js --commands "npm install"`. A deployment changes only the
code; the variables stay. Then `node tools/dev/api_check.mjs`: every route as QA players on the live
backend (purchase and notification refusals, a pack code made for the run, gifts, a co-op game, an
account deletion), answers and timings, everything cleaned up afterwards; `node
tools/dev/security_check.mjs` for the sweep and the gift limits (below). Tests: `cd functions/api &&
npm install && npm test` (router, purchases, co-op rules, gifts and their limits, the sweep, the twins
below).

Deployments: `6ad3928e2403472dffb0` (2026-10-17, the first live one), `6ad39945ee63affa160d` (2026-10-17:
the integrity sweep with `SWEEP_APPLY`, the `blocks` event, gift limits, names without links).
Deployed 2026-10-17 (deployment `6ad3b2b2b1585e1b9f4e`, `api_check.mjs` passed): Play together's live rows
(`coop_drags`, docs/multiplayer.md, "Live picks and drags"): made on `/coop/create` and `/coop/join`, deleted on
leave, remove, the cleanup, account deletion and by the sweep (`coop_drags:*`). Claims (first grab wins) need no
`api` change: they use the live rows and the server's `$updatedAt`.

## Which function serves which builds

| Function | Called by | Status |
| --- | --- | --- |
| `api` | builds after 124 and the web game from its next deploy | live |
| `verify-purchase` | builds up to 124 (`/verify`, `/health`); Apple's App Store Server Notifications for every build (`https://cjw-verify-purchase.fra.appwrite.run/notifications`, also in `tools/store/asc_publish.py`) | frozen, deployed |
| `delete-account` | builds up to 124 | frozen, deployed |
| `redeem-code` | builds up to 124 (the web game until its next deploy; iPhone builds from before 2026-10-16 had code entry too) | frozen, deployed |
| `coop-game` | builds up to 124 that have Play together | frozen, deployed |
| `send-gift` | builds up to 124 that have friend gifts | deployed, kept equal to `api`'s gift code (the gift limits must hold for every caller): `6ad3970c70f2bbcfaa22` |
| `catalog-snapshot` | its own daily schedule (03:00 UTC); every build reads the file it writes | stays apart (below) |
| `coop-cleanup` | its hourly schedule | deleted 2026-10-17 once `api`'s scheduled run had run |

`catalog-snapshot` stays its own function: it runs once a day for up to 5 minutes, reads the whole
catalogue and nobody waits for it, so it gains nothing from being warm, and inside `api` it would hold
an instance busy for minutes while players' calls queue behind it.

### Retiring an old function

Delete an old function only when no build that calls it can still be used:

- A TestFlight build expires 90 days after its upload, so the frozen functions can go 90 days after
  the last build that calls them (build 124) was uploaded (`asc_publish.py status` lists the
  dates), and not before the web game has been redeployed with `api`.
- No App Store version has shipped yet. If one ships with a build up to 124, its functions stay until a
  minimum build ("Update required", docs/app-updates.md) moves its players on.
- `verify-purchase` also stays until Apple's notification URL points elsewhere. Moving it to `api`:
  give `api` execute `any` and a domain, check `POST /purchase/notifications` there, change
  `NOTIFICATIONS_URL` in `tools/store/asc_publish.py`, run `asc_publish.py app-info` (Production and
  Sandbox URLs) and send a test notification from App Store Connect.

### Twins while old builds are in use

The frozen functions are copies of the modules. A change that old builds must get too goes into both,
and the old function is redeployed. Anything that limits players goes into both: the old functions are
callable by any signed-in client, whatever build it is.

- What an account deletion removes: `src/account.js` and `functions/delete-account/src/main.js` must
  hold the same code (`functions/api/test/twins.test.mjs`).
- Friend gifts: `src/gift/` and `functions/send-gift/src/` hold the same code (the daily limit, the
  notification rules, the name filter; `twins.test.mjs`, and `test/friend_gifts_test.dart` for the
  app's side).
- Purchase grants: `GRANTS` in `src/purchase.js` and `functions/verify-purchase/src/main.js`
  (`test/economy_test.dart`).
- Co-op: builds up to 124 (`coop-game`) and later builds (`api`) play in the same games (same rows and
  teams), so a change to the rules in `src/coop` must keep games made by either working.

## Security (review of 2026-10-17)

### Integrity sweep (`src/sweep/`)

Players write their own rows, and the app gives some of them a predictable id, md5 of
`<owner>:<key>` (progress, event_progress, friends, blocks). Another player can create a row at that
id first: the owner's write is then refused (401) and their read finds nothing (404); checked live.
Appwrite lets a client grant only roles it holds, so such a row names the wrong player in its
permissions, or carries an id that is not its owner's. The sweep, every hour over rows changed in the
last two hours and once a day (04:00 UTC) over everything:

| What | Rule | Action |
| --- | --- | --- |
| progress, event_progress, friends, blocks | the owner (`userId`, or `blockerId`) lacks `update`, another player is named, or a 32-character id is not md5 of owner and key | delete (the owner's app writes it again). Rows with a 20-character `ID.unique()` id (older rows, rows the app makes when its id is taken) are checked by permissions only |
| profiles | no user has the id (an hour after it was made); another player named in the permissions | delete |
| profiles | only the owner named, but not `read(any) update(user) delete(user)` | permissions put back (QA players' rows, `isTest`, are left to `purge_test_players.py`) |
| user-uploads | no My Puzzles row of a player the file belongs to, an hour after the upload | delete |
| user-uploads | readable or changeable by anyone but its owner | made `read(user) delete(user)` of the owner |
| user-uploads | more than 500 photos of one player (`FILES_PER_PLAYER`; "no limit with VIP" in the app, far above real use) | the newest past 500 go, row and file |
| names | `profiles.displayName`, `friends.friendName`, `blocks.blockedName` refused by the name filter (offensive, a link, an @handle or e-mail, a domain) | `Player` |

A new `blocks` row is checked by its create event at once, so nobody is kept from blocking a player
for an hour. Reads are paged, deletes go 100 at a time, the run logs its counts. On demand, as the
owner: `appwrite functions create-execution --function-id api --path /admin/sweep --method POST
--body '{"full":true}'` (a dry run; `"dryRun":false` applies; `"qaOnly":true` touches only rows of QA
players). The first full dry run on the live backend (2026-10-17: 122 users, 101 profiles, 333 progress
rows, 1 photo) found nothing to change; the rules were then checked live with QA players
(`tools/dev/security_check.mjs`: a squatted block and progress row, a name with a link, a public photo;
dry run, then the run; the victim blocks and saves again) and `SWEEP_APPLY` was set to `true`.

The app (builds after 124) also copes on its own: a row write refused with 401 while the session holds
is parked, not retried in a loop (docs/sync.md), and a friend or block row goes under a unique id when
its predictable one is taken (`SocialRepository._ownRow`).

### Friend gifts

20 gifts a day per sender (`limit`); a notification only between friends who added each other, and at
most 5 a day per recipient (later gifts land in the inbox quietly); names with a link, an @handle or a
domain show as "Player" in the message and the notification (docs/friend-gifts.md).

### Project settings

The app signs in only as a guest (anonymous), with e-mail and password, with Apple (OAuth and native
ID token) and uses JWT; memberships of co-op teams are made by the server. Turning off what it never
uses was approved by the owner and done on 2026-10-17 (run from a directory with the project's
appwrite.config.json):

```
appwrite project update-auth-method --method-id magic-url --enabled=false
appwrite project update-auth-method --method-id email-otp --enabled=false
appwrite project update-auth-method --method-id phone --enabled=false
appwrite project update-auth-method --method-id invites --enabled=false   # then play a co-op game (node tools/dev/api_check.mjs); if joining fails, turn it back on
appwrite project update-protocol --protocol-id graphql --enabled=false
```

Before (2026-10-17): every auth method on except passkey; protocols REST, GraphQL and WebSocket on.
Now: email-password, anonymous and JWT on (Apple is an OAuth provider); magic URL, email OTP, phone, invites
and passkey off; GraphQL off, REST and WebSocket on. `node tools/dev/api_check.mjs` passed afterwards (co-op
create, join, rejoin, leave, remove, next board and end; account deletion): server-made team memberships do
not need the invites method. To turn a method back on, run the same command with `--enabled=true`.

## Timings (live, 2026-10-17)

Wall time of a call from this Mac (Appwrite's execution duration includes the cold start):

| | cold | warm |
| --- | --- | --- |
| old functions, `GET /health` | 4.0-5.1 s (`coop-game` 4.0, `send-gift` 4.9, `redeem-code` 5.1, `delete-account` 4.4) | 0.1-0.2 s |
| `coop-game` create (docs/multiplayer.md) | 7.4 s | 0.1-1.2 s |
| `api`, `GET /health` (loads the purchase and account modules) | 5.2 s | 0.16-0.44 s |
| `api`, every route (`tools/dev/api_check.mjs`) | | 0.1-1.5 s; a pack code 2.8 s (its first claim grants 7 files); an account deletion 4.6 s |

A cold start costs the same as before (it is mostly Appwrite starting the runtime); what changes is
how often a player meets one. A runtime stays warm for about ten minutes after its last call
(`redeem-code` measured warm after 8 minutes idle, cold after 12; once still warm after 13), so with
every call on `api`, one player's call keeps it warm for the next.
