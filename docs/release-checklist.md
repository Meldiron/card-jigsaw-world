# Release checklist

What the repository automates, and what only you can do.

## Continuous integration (automatic)

`.github/workflows/ci.yml` runs on every push and pull request: `flutter analyze`, `flutter test`, a syntax check of the Appwrite function, and unsigned iOS, Android and web builds.

## TestFlight release (automatic after one-time setup)

`.github/workflows/release-testflight.yml` runs when you **publish a GitHub release** (tag `vX.Y.Z`) or trigger it manually. It archives the app with Xcode, lets Xcode create the App Store provisioning profiles through the App Store Connect API, exports an IPA and uploads it to TestFlight. The version is the tag, the build number is the workflow run number.

### One-time setup (manual)

1. **Apple Developer Program**: the team `C24QP73SQM` must have an active membership. Accept the latest agreements in App Store Connect (Agreements, Tax, and Banking), including the Paid Applications agreement for in-app purchases.
2. **App record**: done. App Store Connect app "Card Jigsaw World", bundle id `com.matejbaco.cardjigsawworld`, Apple ID `6821644423`. The app is iPhone-only (no iPad screenshots are needed).
3. **App Store Connect API key**: Users and Access > Integrations > App Store Connect API > Team keys > Generate (role **App Manager** or Admin). Download the `.p8` once. Add these repository secrets (Settings > Secrets and variables > Actions):
   - `APP_STORE_CONNECT_KEY_ID` – the key id
   - `APP_STORE_CONNECT_ISSUER_ID` – the issuer id shown above the key list
   - `APP_STORE_CONNECT_API_KEY_P8` – `base64 -i AuthKey_XXXX.p8 | pbcopy`
4. **Distribution certificate**: in Xcode > Settings > Accounts > your team > Manage Certificates, create an **Apple Distribution** certificate if there is none, then in Keychain Access export it (with its private key) as a `.p12` with a password. Add secrets:
   - `IOS_DISTRIBUTION_P12` – `base64 -i dist.p12 | pbcopy`
   - `IOS_DISTRIBUTION_P12_PASSWORD`
5. **Capabilities**: in the developer portal the App ID needs In-App Purchase (on by default) and the widget extension bundle id `com.matejbaco.cardjigsawworld.DailyWidget` must exist (Xcode creates it on the first automatic-signing build; running the release workflow once also registers it).
6. **TestFlight testers**: add yourself as an internal tester in App Store Connect > TestFlight.

### Each release

1. Bump `version:` in `pubspec.yaml` (for example `1.6.0+9`) and the version row in `lib/features/profile/settings_screen.dart`; merge to `main`.
2. On GitHub create a release with tag `v1.6.0`. The workflow uploads the build; processing in TestFlight takes 10 to 30 minutes, then testers get it.

## In-app purchases (manual, once)

See `docs/purchases.md` for product ids and the verification function. In short:

1. App Store Connect > your app > In-App Purchases: create the consumables `coins_1000`, `coins_3000`, `coins_5500`, `coins_12000`, `tickets_5`, `tickets_15`, `hints_5`, `hints_15`, and a subscription group "VIP" with `vip_monthly` (7-day free introductory offer) and `vip_yearly`. Fill in localisations and screenshots, then submit them with the first app version.
2. Appwrite function variables are set: `APPLE_ENVIRONMENT=Sandbox` (switch to `Production` once the store build is live), `APPLE_APP_ID=6821644423`, `APPLE_BUNDLE_ID=com.matejbaco.cardjigsawworld`, `APPWRITE_DATABASE_ID=cjw`.
3. **App Store Server Notifications**: App Store Connect > App > App Information > App Store Server Notifications: set both the Production and Sandbox URL to `https://cjw-verify-purchase.fra.appwrite.run/notifications` (version 2 notifications).
3. Appwrite console > Functions > `verify-purchase` > Domains: enable the function domain, then in App Store Connect > App Information > App Store Server Notifications set the Production and Sandbox URLs to `https://<function-domain>/notifications` (version 2).
4. Create a Sandbox tester (Users and Access > Sandbox) and sign in with it on a device to test real purchases before release.

## Other optional setup

- **Sign in with Apple**: already configured. Appwrite console > Auth > Social providers > Apple has **Native sign-in** on with bundle id `com.matejbaco.cardjigsawworld`; the app holds the `com.apple.developer.applesignin` entitlement. Xcode registers the capability on the App ID on the first signed build (automatic signing). If you manage the App ID by hand, tick **Sign in with Apple** on it in the Apple Developer portal. Browser sign-in (service id, key, team id) is not needed. Google and Facebook are intentionally off for now.
- **Push notifications** for the daily reminder are not wired yet.

## After approval

- **VIP gift codes**: Apple only lets us mint offer codes once the app is live and the subscriptions are approved. Run `tools/store/offer_codes.py codes monthly 10` and `codes yearly 10` then (see `tools/store/README.md`). The offers themselves already exist.
