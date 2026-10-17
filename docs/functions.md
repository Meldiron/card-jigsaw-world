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
| `GET /health` | `src/main.js` | `{ok, environment, maxPlayers, appleSignIn}`; the app's warm-up call | every function's `/health` |
| schedule `0 * * * *` | `src/coop/cleanup.js` | the hourly co-op cleanup: an execution with trigger `schedule` runs it whatever its path | `coop-cleanup` |

Each module answers as its old function did (same bodies, same status codes), so the app reads the
same answers; only the router (`src/main.js`) is new. Modules load on their first call, so a cold
start loads only what that call needs (the App Store library only for purchases). Nothing runs at the
root path or at the old paths (`POST /` used to delete the caller's account on `delete-account`).

Settings: Node 22, entrypoint `src/main.js`, build `npm install`, execute `users` (guests too), timeout
300 s (the cleanup; a synchronous call from the app is cut at 30 s by Appwrite anyway), scopes `rows.read
rows.write users.read users.write files.read files.write teams.read teams.write messages.read
messages.write` (the union of the old functions'). Variables (all secret): `APPLE_BUNDLE_ID`,
`APPLE_APP_ID`, `APPLE_ENVIRONMENT` (`Production`), `APPWRITE_DATABASE_ID` (`cjw`), `APPLE_SIGNIN_KEY`
(the contents of `secrets/AuthKey_2QJPJFW8JW.p8`; `/health` says `appleSignIn: "set"` when it reads).

Deploy with the Appwrite CLI signed in as the owner, from a folder holding an `appwrite.config.json`
with `{"projectId": "6acb4de5003e38d5ebd9", "endpoint": "https://fra.cloud.appwrite.io/v1"}`: copy
`functions/api` without `node_modules`, then `appwrite functions create-deployment --function-id api
--code <copy> --activate --entrypoint src/main.js --commands "npm install"`. A deployment changes only the
code; the variables stay. Then `node tools/dev/api_check.mjs`: every route as QA players on the live
backend (purchase and notification refusals, a pack code made for the run, gifts, a co-op game, an
account deletion), answers and timings, everything cleaned up afterwards. Tests: `cd functions/api &&
npm install && npm test` (router, purchases, co-op rules, gifts, the deletion twin below).

Deployments: `6ad3928e2403472dffb0` (2026-10-17, the first live one).

## Which function serves which builds

| Function | Called by | Status |
| --- | --- | --- |
| `api` | builds after 124 and the web game from its next deploy | live |
| `verify-purchase` | builds up to 124 (`/verify`, `/health`); Apple's App Store Server Notifications for every build (`https://cjw-verify-purchase.fra.appwrite.run/notifications`, also in `tools/store/asc_publish.py`) | frozen, deployed |
| `delete-account` | builds up to 124 | frozen, deployed |
| `redeem-code` | builds up to 124 (the web game until its next deploy; iPhone builds from before 2026-10-16 had code entry too) | frozen, deployed |
| `coop-game` | builds up to 124 that have Play together | frozen, deployed |
| `send-gift` | builds up to 124 that have friend gifts; `tools/dev/notification_check` before this change | frozen, deployed |
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
and the old function is redeployed:

- What an account deletion removes: `src/account.js` and `functions/delete-account/src/main.js` must
  hold the same code (`functions/api/test/account-twin.test.mjs`).
- Purchase grants: `GRANTS` in `src/purchase.js` and `functions/verify-purchase/src/main.js`
  (`test/economy_test.dart`).
- Gift amounts and the name filter: `src/gift/gift.js` and `functions/send-gift/src/gift.js`
  (`test/friend_gifts_test.dart`).
- Co-op: builds up to 124 (`coop-game`) and later builds (`api`) play in the same games (same rows and
  teams), so a change to the rules in `src/coop` must keep games made by either working.

## Timings (live, 2026-10-17)

Wall time of a call from this Mac (Appwrite's execution duration includes the cold start):

| | cold | warm |
| --- | --- | --- |
| old functions, `GET /health` | 4.0-5.1 s (`coop-game` 4.0, `send-gift` 4.9, `redeem-code` 5.1, `delete-account` 4.4) | 0.1-0.2 s |
| `coop-game` create (docs/multiplayer.md) | 7.4 s | 0.1-1.2 s |
| `api`, `GET /health` (loads the purchase and account modules) | 5.2 s | 0.16-0.44 s |
| `api`, every route (`tools/dev/api_check.mjs`) | | 0.1-1.5 s; a pack code 2.8 s (its first claim grants 7 files); an account deletion 4.6 s |

A cold start costs the same as before (it is mostly Appwrite starting the runtime); what changes is
how often a player meets one.
