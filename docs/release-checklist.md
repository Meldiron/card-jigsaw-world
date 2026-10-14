# Release checklist

What the repository automates, and what only you can do.

## Continuous integration (automatic)

`.github/workflows/ci.yml` runs on every push and pull request: `flutter analyze`, `flutter test`, a syntax check of the Appwrite function, and unsigned iOS, Android and web builds.

## TestFlight release (started by hand)

`.github/workflows/release-testflight.yml` runs only when started (`tools/dev/testflight.sh` or
`gh workflow run "Release to TestFlight" --ref main -f version=X.Y.Z`; never on a push or a tag). It
installs the App Store profiles named in `ios/ExportOptions.plist` with the App Store Connect API
(`tools/store/install_profiles.py`), switches the Release configuration to manual signing, archives,
exports and uploads the IPA (symbols included), waits for processing, sets "What to Test" from
`store/metadata/en-US/testflight_build_notes.txt`, adds the build to the internal and public groups
and files the beta review. Version = `pubspec.yaml` (or the input), build number = 100 + run number.
The workflow runs no tests: run the gates first (`flutter analyze --fatal-infos --fatal-warnings`,
`flutter test`) or check that CI passed on the commit. Afterwards announce the build to the update
prompt (`publish_release.py testflight --build N`; `testflight.sh` does it) and deploy the web site
from the same commit (`tools/dev/deploy-web.sh`).

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

A TestFlight build keeps the version and gets the next build number (apple-release skill). A new
App Store cycle starts with `tools/dev/release.sh X.Y.Z`. Before submitting a version for review,
follow "Before an App Store submission" in the apple-release skill (fresh store screenshots, specific
review notes, privacy policy and App Privacy answers that match the build).

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

## Day-to-day

See `docs/release-flow.md`: `tools/dev/device.sh` for the phone, `tools/dev/release.sh X.Y.Z` for TestFlight, the `Submit to App Store` workflow for review.

## After approval

- **VIP gift codes**: Apple only lets us mint offer codes once the app is live and the subscriptions are approved. Run `tools/store/offer_codes.py codes monthly 10` and `codes yearly 10` then (see `tools/store/README.md`). The offers themselves already exist.

## Sign in with Apple in the browser (web build)

Native sign-in needs no secrets, but the web build uses Apple's redirect flow,
which Appwrite calls "Browser sign-in". Apple only lets these be created in
the developer portal (no API), so three manual steps:

1. developer.apple.com > Certificates, Identifiers & Profiles > Identifiers >
   **+** > Services IDs. Identifier `com.matejbaco.cardjigsawworld.signin`,
   description "Card Jigsaw World Web". Enable **Sign in with Apple**,
   Configure: primary App ID `com.matejbaco.cardjigsawworld`, domain
   `fra.cloud.appwrite.io`, return URL
   `https://fra.cloud.appwrite.io/v1/account/sessions/oauth2/callback/apple/6acb4de5003e38d5ebd9`.
2. Keys > **+** > name "Card Jigsaw World Sign in with Apple", tick Sign in
   with Apple, configure with the same primary App ID, register, download the
   `.p8` once. Note the Key ID.
3. Send the Services ID, Key ID and the `.p8` file (team id is `C24QP73SQM`);
   it gets stored in `secrets/` and the Apple provider is switched to
   "Browser sign-in" enabled with `asc_publish.py`'s sibling command or the
   Appwrite console (Auth > Social providers > Apple).

Done 2026-10-13: Services ID `com.matejbaco.cardjigsawworld.signin`, Key ID
`2QJPJFW8JW` (`secrets/AuthKey_2QJPJFW8JW.p8`), browser sign-in enabled on the
Appwrite Apple provider (native sign-in settings unchanged). The redirect from
the web app reaches Apple's page "Use your Apple Account to sign in to
'Card Jigsaw World Web'".
