# In-app purchases

Payment runs through StoreKit 2 (`in_app_purchase` plugin). Nothing is granted on the device: every finished transaction is sent to the `verify-purchase` Appwrite Function, which verifies Apple's signature and applies the grant to the player's profile exactly once.

## Products

| Product id | Type | Grant | Placeholder price |
|---|---|---|---|
| `coins_1000` | consumable | 1,000 coins | $0.99 |
| `coins_3000` | consumable | 3,000 coins | $2.99 |
| `coins_5500` | consumable | 5,500 coins | $4.99 |
| `coins_12000` | consumable | 12,000 coins | $9.99 |
| `tickets_5` | consumable | 5 tickets | $1.99 |
| `tickets_15` | consumable | 15 tickets | $4.99 |
| `hints_5` | consumable | 5 hints | $0.99 |
| `hints_15` | consumable | 15 hints | $2.49 |
| `vip_monthly` | auto-renewable, group `VIP` | VIP until `expiresDate`; 7-day free introductory offer | $2.99 / month (Apple price-point equalised per country) |
| `vip_yearly` | auto-renewable, group `VIP` | VIP until `expiresDate`; 7-day free introductory offer | $14.99 / year (Apple price-point equalised per country) |

The store screen shows the localised App Store price once products load; the table prices are the fallbacks.

## Flow

1. The app enables StoreKit 2, queries the products and starts a purchase (`buyConsumable` / `buyNonConsumable`).
2. StoreKit delivers the transaction on the purchase stream with `verificationData.serverVerificationData` = the signed JWS transaction.
3. The app calls the function: `POST /verify` with `{ "jws": ..., "productId": ... }` (Appwrite `Functions.createExecution`, user session attached).
4. The function verifies the JWS against Apple Root CA G3 (bundled in `certs/`), checks bundle id, product id and revocation, looks the transaction up in the `purchases` table (unique `transactionId`), applies the grant to `profiles/{userId}` (coins, tickets, hints or `vipExpiresAt` + `appleOriginalTransactionId`), writes a `ledger` row and a `purchases` row, and returns `{ ok, grant }`.
5. The app calls `completePurchase` only after a successful verification, so a failed verification is retried by StoreKit later.
6. Subscription renewals, refunds and expirations arrive through App Store Server Notifications V2 at `POST /notifications` and update `vipExpiresAt` on the matching profile (`appleOriginalTransactionId`).

`Profile.isVip` is true while `vipExpiresAt` is in the future (or while the debug `isVip` flag is set).

## Function configuration (Appwrite console → Functions → verify-purchase)

| Variable | Value |
|---|---|
| `APPLE_BUNDLE_ID` | `com.matejbaco.cardjigsawworld` |
| `APPLE_APP_ID` | `6821644423` |
| `APPLE_APP_ID` | the app's numeric Apple ID from App Store Connect (required for Production) |
| `APPLE_ENVIRONMENT` | `Sandbox` while testing, `Production` once live (sandbox receipts still verify, the function falls back automatically) |
| `APPWRITE_DATABASE_ID` | `cjw` |

Runtime Node 22, entrypoint `src/main.js`, build command `npm install`, scopes `rows.read`, `rows.write`, `users.read`, execute permission `users`. Deploy by zipping `functions/verify-purchase` (without `node_modules`) and creating a deployment, or via the Appwrite CLI `appwrite push functions`.

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
