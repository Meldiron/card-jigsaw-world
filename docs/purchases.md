# In-app purchases

Payment runs through StoreKit 2 (`in_app_purchase` plugin). Nothing is granted on the device: every finished transaction is sent to the `verify-purchase` Appwrite Function, which verifies Apple's signature and applies the grant to the player's profile exactly once.

## Products

Apple product ids cannot be renamed, so the number in a consumable id is historical. The grants below come from the economy model in `docs/economy.md` (section 7): every coin and ticket bundle is worth about the same per dollar, counting a ticket as 500 coins; the two booster bundles (ids `hints_*`) give Peeks, Hints and Magic and are on purpose the better deal (owner, 2026-10-17).

| Product id | Type | Grant | Placeholder price |
|---|---|---|---|
| `coins_1000` | consumable | 2,500 coins | $0.99 |
| `coins_3000` | consumable | 8,000 coins | $2.99 |
| `coins_5500` | consumable | 14,000 coins | $4.99 |
| `coins_12000` | consumable | 30,000 coins | $9.99 |
| `tickets_5` | consumable | 10 tickets | $1.99 |
| `tickets_15` | consumable | 30 tickets | $4.99 |
| `hints_5` | consumable | 15 Peeks, 10 Hints, 5 Magic (16 hints until 2026-10-17) | $0.99 |
| `hints_15` | consumable | 50 Peeks, 30 Hints, 15 Magic (48 hints until 2026-10-17) | $2.49 |
| `vip_monthly` | auto-renewable, group `VIP`, Family Sharing | VIP until `expiresDate`; 7-day free introductory offer; win-back offer | $2.99 / month (Apple price-point equalised per country) |
| `vip_yearly` | auto-renewable, group `VIP`, Family Sharing | VIP until `expiresDate`; 7-day free introductory offer; win-back offer | $14.99 / year (Apple price-point equalised per country) |

The store screen shows the localised App Store price once products load; the table prices are the fallbacks.

### Changing what a purchase gives

Three places hold the amounts and `test/economy_test.dart` fails unless they agree:

1. `StoreProducts.grants` and `StoreProducts.usdPrices` in `lib/data/purchases.dart`: what the store screen, the house ads and the debug sandbox show.
2. `GRANTS` in `functions/verify-purchase/src/main.js`: what the server credits. Redeploy the function (below) before the build that shows new amounts ships.
3. `store/metadata/subscriptions/consumables.json`: App Store display names (30 characters), descriptions (45) and review notes, pushed with `.venv/bin/python tools/store/asc_publish.py iap` (try `--dry-run` first).

## Sources of truth

Two, and the app is neither: **Apple** for payments and subscription status (signed transactions,
App Store Server Notifications), **our backend** for what a player owns (`profiles`, `purchases`,
`ledger`, written only by `verify-purchase`). The app shows what the backend says; it never grants
anything itself in a release build.

## Flow

1. **At launch** (once the player is signed in) the app listens for transactions (StoreKit 2 `Transaction.updates`, as Apple asks) and checks every transaction the App Store still has open (`Transaction.unfinished`): a purchase paid while the app was closed or restarted, an approved Ask to Buy, a gift code redeemed in the App Store. It checks them again whenever the app comes back to the foreground (`PurchaseService.checkOpenPurchases`).
2. **Buy**: the tapped tile shows a spinner while the App Store sheet is open (`PurchaseFlow.buy`, stage `paying`), and the app wakes the function with an async `GET /health` so the check after the payment does not wait for a cold start (about 5 s cold, under 1 s warm). If the sheet closes and the App Store is still processing (TestFlight's sandbox can take a while), the purchase sheet opens with "Waiting for the App Store".
3. StoreKit delivers the transaction with `verificationData.serverVerificationData` = the signed JWS transaction. The purchase sheet says "Adding 10 tickets" and the app calls the function: `POST /verify` with `{ "jws": ..., "productId": ... }` (Appwrite `Functions.createExecution`, user session attached). The same transaction is never sent twice at once.
4. The function verifies the JWS against Apple Root CA G3 (bundled in `certs/`), checks bundle id, product id and revocation, then **claims** the transaction by creating its `purchases` row (unique index on `transactionId`): of two calls for one transaction only one grants, the other answers `alreadyApplied`. It adds the grant to `profiles/{userId}` with atomic increments (`Operator.increment`, like the app's own changes, so a coin or ticket spent at the same moment is never overwritten) or sets `vipExpiresAt` + `appleOriginalTransactionId`, writes `ledger` rows (coins, tickets and hints; Peeks and Magic have none, the ledger's `currency` enum stays as old builds know it) and returns `{ ok, grant, balances }` (`balances`: coins, tickets, hints, Peeks and Magic after the grant). If the grant fails, the claim is deleted so the next try applies it.
5. On `ok` the app reads the save again (quietly: `SyncController.expectServerChange` keeps a purchase from showing as "Synced from another device"), then the sheet says "10 tickets added · You now have 15 tickets" (a booster bundle: "15 Peeks, 10 Hints, 5 Magic added · You now have 16 Peeks, 12 Hints and 5 Magic"), and only then calls `completePurchase`. A purchase the player did not follow (sheet closed, paid while the app was closed) ends in a toast ("Added 10 tickets"); a VIP renewal stays quiet.
6. **No answer** (offline, 5xx, a timeout, no session yet): the check runs again after 2, 4, 8, 15, 30 and 60 s, then every minute, and at once when the app comes back; after 10 s the sheet says it is taking longer and that the purchase is saved. **Refused** (4xx: not verifiable, refunded, the family limit): the sheet says "Not added yet" with the reason; the transaction stays open with the App Store, so the next launch checks it again.
7. Subscription renewals, refunds and expirations arrive through App Store Server Notifications V2 at `POST /notifications` and update `vipExpiresAt` on the matching profile (`appleOriginalTransactionId`).

Code: `PurchaseService` (`lib/data/purchases.dart`: StoreKit, the checks, retries), `PurchaseFlow` (`lib/state/purchases.dart`: the stages screens follow), `PurchaseHost` and `PurchaseSheet` (`lib/features/store/purchase_host.dart`, mounted in `app.dart`). Tests: `test/purchase_flow_test.dart`; the function's own `functions/verify-purchase/test/verify.test.mjs` (`cd functions/verify-purchase && npm install && node --test --experimental-test-module-mocks test/verify.test.mjs`); on the simulator `integration_test/purchase_flow_test.dart` drives the real app with a stand-in App Store (StoreKit's sheet cannot be driven, and Xcode-signed transactions do not verify).

`Profile.isVip` is true while `vipExpiresAt` is in the future (or while the debug `isVip` flag is set).

## Family Sharing (VIP)

Both VIP plans have Family Sharing on since 2026-10-14 (Apple: it can never be turned off again). A family
member's device gets its own transaction for the plan (`inAppOwnershipType: FAMILY_SHARED`, its own
`transactionId`) and sends it to `/verify` like any purchase, so the member's game account gets VIP too.

- **At most 6 accounts per subscription.** One `originalTransactionId` unlocks VIP on at most
  `MAX_ACCOUNTS_PER_SUBSCRIPTION` = 6 distinct game accounts (the organiser plus five members, the size of an
  Apple family). A 7th account gets 403 "This subscription is already in use on the most accounts it can
  unlock." This also caps one purchaser spreading renewals over many accounts.
- **Rows.** `purchases` records `ownership` (`PURCHASED` / `FAMILY_SHARED`) and the transaction's
  `appTransactionId` (one per Apple account and app, indexed) next to the transaction ids.
- **Notifications.** A purchaser's notification (renewal, expiry, refund) updates every profile linked to
  the subscription (`appleOriginalTransactionId`), so family members follow renewals. Family-only
  notifications (`REVOKE` when sharing stops or a member leaves, `DID_RECOVER`, `DID_FAIL_TO_RENEW`) update
  only that member's accounts, found by the notification's `transactionId`, else its `appTransactionId`.
  `DID_RECOVER` now renews like `DID_RENEW`.

## Win-back offers (VIP)

StoreKit win-back offers for people whose VIP lapsed, recorded in `winBackOffers` of
`store/metadata/subscriptions/vip_monthly.json` / `vip_yearly.json` and created by
`asc_publish.py subscriptions`. Defaults (2026-10-14, change them in the files): VIP Monthly first month back
for $0.99, VIP Yearly first year back for $7.99; for people who paid at least a month and lapsed 1 to 12
months ago, at most once a year; promoted with Apple's generated assets. Apple only creates offers for
approved subscriptions, so the command waits until the plans are approved (run it once after the first
approval).

The App Store shows the offers itself (subscription settings, the product page, and in the app as a StoreKit
message). Redeemed offers are ordinary transactions of `vip_monthly` / `vip_yearly` (`offerType` 4), which
`/verify` and the notifications handle like any other. The app's own store screen does not show the offer
yet. The StoreKit plugin we already use (`in_app_purchase_storekit` 0.4.13) supports it without a new
dependency: `InAppPurchaseStoreKitPlatform.isWinBackOfferEligible(productId, offerId)` tells whether the
player may take it, and buying with `Sk2PurchaseParam(productDetails: ..., winBackOfferId: offerId)` applies
it (offer ids `vip_monthly_winback`, `vip_yearly_winback`).

## VIP benefits

What `isVip` unlocks in the app (keep this list, the `_VipCard` bullets in `lib/features/store/store_screen.dart` and the VIP paragraph of `store/metadata/en-US/description.txt` in sync):

- Every pack unlocked, including past monthly daily packs (`ProfileNotifier.isUnlocked`).
- A fourth daily quest and a sixth weekly quest (`Goals.daily` / `Goals.weekly` mark the last entry `vipOnly`; non-VIP players see it as a locked card that opens the Store VIP card, and `claimGoal` refuses it). The free counts are `Goals.dailyFree = 3` and `Goals.weeklyFree = 5`.
- No bonus videos (house promotions) anywhere.
- Unlimited My Puzzles uploads (free players keep up to `Economy.freeMyPuzzles` = 5 photos; the My Puzzles screen shows the count and a VIP alert at the limit).
- +500 coins every week: paid automatically once per week when a VIP member opens the app (`ProfileNotifier.claimVipWeeklyBonus`, called from `HomeShell`; marker `Goals.vipBonusKey` in `claimedGoals`). It is not a quest: VIP has exactly one extra weekly quest.

## Function configuration (Appwrite console → Functions → verify-purchase)

| Variable | Value |
|---|---|
| `APPLE_BUNDLE_ID` | `com.matejbaco.cardjigsawworld` |
| `APPLE_APP_ID` | `6821644423` |
| `APPLE_APP_ID` | the app's numeric Apple ID from App Store Connect (required for Production) |
| `APPLE_ENVIRONMENT` | `Production` since 2026-10-16 (sandbox transactions from TestFlight and App Review still verify: the function falls back to Sandbox automatically). `GET /health` answers `{"ok":true,"environment":"Production"}` |
| `APPWRITE_DATABASE_ID` | `cjw` |

Runtime Node 22, entrypoint `src/main.js`, build command `npm install`, scopes `rows.read`, `rows.write`, `users.read`, execute permission `users`. Deploy by packing `functions/verify-purchase` (without `node_modules`) and creating a deployment:

```
COPYFILE_DISABLE=1 tar --exclude node_modules -czf /tmp/verify-purchase.tar.gz -C functions/verify-purchase .
```

The API keys in `secrets/` have no function scope, so create the deployment with the Appwrite MCP (`appwrite_call_tool`, `project_id: "6acb4de5003e38d5ebd9"`, `tool_name: "functions_create_deployment"`, `confirm_write: true`, arguments `{function_id: "verify-purchase", code: {filename: "code.tar.gz", content: <base64 of the tarball>, encoding: "base64", mime_type: "application/gzip"}, activate: true, entrypoint: "src/main.js", commands: "npm install"}`) or upload the tarball in Console > Functions > verify-purchase > Deployments. With a key that has `functions.write`, `tools/dev/appwrite_upload.py <endpoint> <project> <key> /functions/verify-purchase/deployments /tmp/verify-purchase.tar.gz true` works too. The Appwrite CLI signed in as the owner deploys it as well: copy `functions/verify-purchase` without `node_modules` into a folder that holds an `appwrite.config.json` with `{"projectId": "6acb4de5003e38d5ebd9", "endpoint": "https://fra.cloud.appwrite.io/v1"}`, then from that folder `appwrite functions create-deployment --function-id verify-purchase --code <copy> --activate --entrypoint src/main.js --commands "npm install"`. A deployment changes only the code: the variables (secret ones included) stay. Check `https://cjw-verify-purchase.fra.appwrite.run/health` answers `{"ok":true}` afterwards.

Deployments worth knowing: `6ad3442026e53b31add0` (2026-10-17, CLI): the booster bundles (`hints_5` and `hints_15` give Peeks, Hints and Magic), `balances` with Peeks and Magic; `/health` answered `{"ok":true,"environment":"Production"}`.

### App Store Server Notifications

The execution URL (`/v1/functions/verify-purchase/executions`) is not a public endpoint. Give the function a domain: Appwrite console → Functions → verify-purchase → Domains → add the generated `*.appwrite.network` domain (or your own). Then in App Store Connect → App → App Information → App Store Server Notifications set the **Version 2** production and sandbox URLs to `https://<function-domain>/notifications`.

## Manual setup checklist (App Store Connect)

1. Accept the Paid Applications agreement and fill in banking and tax forms.
2. Create the eight consumables with the ids above and the subscription group `VIP` with `vip_monthly` and `vip_yearly` (both with a 7-day free introductory offer); the yearly`; add localisations and screenshots; submit them with the first build.
3. Create sandbox tester accounts for testing on devices.
4. Set the function variables above and enable the function domain; paste the notification URL into App Store Connect.

## Local testing

- Simulator: the Runner scheme references `ios/Runner/Products.storekit`, so debug runs use local StoreKit testing with fake products; transactions are signed by Xcode and the function cannot verify them (expect "Transaction could not be verified"). Use Xcode's Transaction Manager to inspect them.
- Device with a sandbox tester account: purchases are real sandbox transactions and verify end to end (the Sandbox fallback).
- Debug builds without any store (plain simulator with no StoreKit config) fall back to a dialog titled "Sandbox purchase (debug build)" that grants items locally. This path is compiled out of release builds.


## Public endpoint

The function has the generated domain `https://cjw-verify-purchase.fra.appwrite.run` and execute access `any`, which is required for unauthenticated calls from Apple. `/verify` still refuses requests without an Appwrite user session. App Store Server Notifications (V2) must point to:

```
https://cjw-verify-purchase.fra.appwrite.run/notifications
```

Set it in App Store Connect > App > App Information > App Store Server Notifications, for both Production and Sandbox URLs.
