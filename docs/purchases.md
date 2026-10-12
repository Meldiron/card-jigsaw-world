# In-app purchases

Payment runs through StoreKit 2 (`in_app_purchase` plugin). Nothing is granted on the device: every finished transaction is sent to the `verify-purchase` Appwrite Function, which verifies Apple's signature and applies the grant to the player's profile exactly once.

## Products

Apple product ids cannot be renamed, so the number in a consumable id is historical. The grants below come from the economy model in `docs/economy.md` (section 7): every bundle is worth about the same per dollar, counting a ticket as 500 coins and a hint as 60.

| Product id | Type | Grant | Placeholder price |
|---|---|---|---|
| `coins_1000` | consumable | 2,500 coins | $0.99 |
| `coins_3000` | consumable | 8,000 coins | $2.99 |
| `coins_5500` | consumable | 14,000 coins | $4.99 |
| `coins_12000` | consumable | 30,000 coins | $9.99 |
| `tickets_5` | consumable | 10 tickets | $1.99 |
| `tickets_15` | consumable | 30 tickets | $4.99 |
| `hints_5` | consumable | 16 hints | $0.99 |
| `hints_15` | consumable | 48 hints | $2.49 |
| `vip_monthly` | auto-renewable, group `VIP` | VIP until `expiresDate`; 7-day free introductory offer | $2.99 / month (Apple price-point equalised per country) |
| `vip_yearly` | auto-renewable, group `VIP` | VIP until `expiresDate`; 7-day free introductory offer | $14.99 / year (Apple price-point equalised per country) |

The store screen shows the localised App Store price once products load; the table prices are the fallbacks.

### Changing what a purchase gives

Three places hold the amounts and `test/economy_test.dart` fails unless they agree:

1. `StoreProducts.grants` and `StoreProducts.usdPrices` in `lib/data/purchases.dart`: what the store screen, the house ads and the debug sandbox show.
2. `GRANTS` in `functions/verify-purchase/src/main.js`: what the server credits. Redeploy the function (below) before the build that shows new amounts ships.
3. `store/metadata/subscriptions/consumables.json`: App Store display names (30 characters), descriptions (45) and review notes, pushed with `.venv/bin/python tools/store/asc_publish.py iap` (try `--dry-run` first).

## Flow

1. The app enables StoreKit 2, queries the products and starts a purchase (`buyConsumable` / `buyNonConsumable`).
2. StoreKit delivers the transaction on the purchase stream with `verificationData.serverVerificationData` = the signed JWS transaction.
3. The app calls the function: `POST /verify` with `{ "jws": ..., "productId": ... }` (Appwrite `Functions.createExecution`, user session attached).
4. The function verifies the JWS against Apple Root CA G3 (bundled in `certs/`), checks bundle id, product id and revocation, looks the transaction up in the `purchases` table (unique `transactionId`), applies the grant to `profiles/{userId}` (coins, tickets, hints or `vipExpiresAt` + `appleOriginalTransactionId`), writes a `ledger` row and a `purchases` row, and returns `{ ok, grant }`.
5. The app calls `completePurchase` only after a successful verification, so a failed verification is retried by StoreKit later.
6. Subscription renewals, refunds and expirations arrive through App Store Server Notifications V2 at `POST /notifications` and update `vipExpiresAt` on the matching profile (`appleOriginalTransactionId`).

`Profile.isVip` is true while `vipExpiresAt` is in the future (or while the debug `isVip` flag is set).

## VIP benefits

What `isVip` unlocks in the app (keep this list, the `_VipCard` bullets in `lib/features/store/store_screen.dart` and the VIP paragraph of `store/metadata/en-US/description.txt` in sync):

- Every pack unlocked, including past monthly daily packs (`ProfileNotifier.isUnlocked`).
- A fourth daily quest and a sixth weekly quest (`Goals.daily` / `Goals.weekly` mark the last entry `vipOnly`; non-VIP players see it as a locked card that opens the Store VIP card, and `claimGoal` refuses it). The free counts are `Goals.dailyFree = 3` and `Goals.weeklyFree = 5`.
- No bonus videos (house promotions) anywhere.
- Unlimited My Puzzles uploads.
- +500 coins every week: paid automatically once per week when a VIP member opens the app (`ProfileNotifier.claimVipWeeklyBonus`, called from `HomeShell`; marker `Goals.vipBonusKey` in `claimedGoals`). It is not a quest: VIP has exactly one extra weekly quest.

## Function configuration (Appwrite console → Functions → verify-purchase)

| Variable | Value |
|---|---|
| `APPLE_BUNDLE_ID` | `com.matejbaco.cardjigsawworld` |
| `APPLE_APP_ID` | `6821644423` |
| `APPLE_APP_ID` | the app's numeric Apple ID from App Store Connect (required for Production) |
| `APPLE_ENVIRONMENT` | `Sandbox` while testing, `Production` once live (sandbox receipts still verify, the function falls back automatically) |
| `APPWRITE_DATABASE_ID` | `cjw` |

Runtime Node 22, entrypoint `src/main.js`, build command `npm install`, scopes `rows.read`, `rows.write`, `users.read`, execute permission `users`. Deploy by packing `functions/verify-purchase` (without `node_modules`) and creating a deployment:

```
COPYFILE_DISABLE=1 tar --exclude node_modules -czf /tmp/verify-purchase.tar.gz -C functions/verify-purchase .
```

The API keys in `secrets/` have no function scope, so create the deployment with the Appwrite MCP (`appwrite_call_tool`, `project_id: "6acb4de5003e38d5ebd9"`, `tool_name: "functions_create_deployment"`, `confirm_write: true`, arguments `{function_id: "verify-purchase", code: {filename: "code.tar.gz", content: <base64 of the tarball>, encoding: "base64", mime_type: "application/gzip"}, activate: true, entrypoint: "src/main.js", commands: "npm install"}`) or upload the tarball in Console > Functions > verify-purchase > Deployments. With a key that has `functions.write`, `tools/dev/appwrite_upload.py <endpoint> <project> <key> /functions/verify-purchase/deployments /tmp/verify-purchase.tar.gz true` works too. Check `https://cjw-verify-purchase.fra.appwrite.run/health` answers `{"ok":true}` afterwards.

### App Store Server Notifications

The execution URL (`/v1/functions/verify-purchase/executions`) is not a public endpoint. Give the function a domain: Appwrite console → Functions → verify-purchase → Domains → add the generated `*.appwrite.network` domain (or your own). Then in App Store Connect → App → App Information → App Store Server Notifications set the **Version 2** production and sandbox URLs to `https://<function-domain>/notifications`.

## Manual setup checklist (App Store Connect)

1. Accept the Paid Applications agreement and fill in banking and tax forms.
2. Create the eight consumables with the ids above and the subscription group `VIP` with `vip_monthly` and `vip_yearly` (both with a 7-day free introductory offer); the yearly`; add localisations and screenshots; submit them with the first build.
3. Create sandbox tester accounts for testing on devices.
4. Set the function variables above and enable the function domain; paste the notification URL into App Store Connect.

## Local testing

- Simulator: the Runner scheme references `ios/Runner/Products.storekit`, so debug runs use local StoreKit testing with fake products; transactions are signed by Xcode and the function cannot verify them (expect "Transaction could not be verified"). Use Xcode's Transaction Manager to inspect them.
- Device with a sandbox tester account: purchases are real sandbox transactions and verify end to end with `APPLE_ENVIRONMENT=Sandbox`.
- Debug builds without any store (plain simulator with no StoreKit config) fall back to a dialog titled "Sandbox purchase (debug build)" that grants items locally. This path is compiled out of release builds.


## Public endpoint

The function has the generated domain `https://cjw-verify-purchase.fra.appwrite.run` and execute access `any`, which is required for unauthenticated calls from Apple. `/verify` still refuses requests without an Appwrite user session. App Store Server Notifications (V2) must point to:

```
https://cjw-verify-purchase.fra.appwrite.run/notifications
```

Set it in App Store Connect > App > App Information > App Store Server Notifications, for both Production and Sandbox URLs.
