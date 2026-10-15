# Release flow

One path from a USB-connected iPhone to the App Store, with exactly two human
decisions: when to cut a release, and when to submit to App Review.

```
local iPhone  ──►  TestFlight build  ──►  App Review  ──►  App Store  ──►  GitHub release
tools/dev/device.sh  tools/dev/testflight.sh   manual workflow   manual click   tag-store-release.sh
```

## 1. Local testing over USB

```
tools/dev/device.sh          # release build, install, keep data
tools/dev/device.sh --wipe   # fresh install, lands on onboarding
tools/dev/device.sh --debug  # flutter run with hot reload
```

Signing is automatic with the development certificate; Sign in with Apple,
widgets and StoreKit (sandbox) all work on the device.

## 2. Every push to `main`

`CI` (`.github/workflows/ci.yml`) runs the analyzer with fatal infos, the unit
tests, a syntax check of the Appwrite function, and unsigned iOS, Android and
web builds. Nothing is published.

## 3. TestFlight builds (automatic, no review after the first)

```
tools/dev/testflight.sh        # next build of the current version, from main
```

Apple reviews the **first build of each version string** for external testers
(1 to 7 days) and lets later builds of the same version through on their own.
So the version in `pubspec.yaml` stays the same for the whole cycle and only
the build number rises (100 + workflow run number). `Release to TestFlight`
(`.github/workflows/release-testflight.yml`) archives, signs, uploads, waits
for processing, writes `store/metadata/en-US/release_notes.txt` as "what to
test", adds the build to the internal and public groups and submits Beta App
Review only when the version has none yet.

Starting the next cycle after an App Store release:

```
tools/dev/release.sh 1.8.0     # bumps pubspec, commits, pushes, first build
```

Expired builds and the one-time review live on Apple's side; the publish
script's `audit` shows them.

## 4. Submitting to App Review (manual, one click)

Actions → `Submit to App Store` → Run workflow with the version (and
optionally the build number). It runs `asc_publish.py release`, which finds or
creates the App Store version, attaches the build, sets "what's new" and marks
the version for **manual release**, then `asc_publish.py submit --yes`, which
files the review submission together with any in-app purchases that are ready.

Before the first submission the App Privacy questionnaire and the Paid
Applications agreement must be completed in App Store Connect; neither has an
API. `asc_publish.py audit` lists everything else.

## 5. Going live (manual)

After pressing Release in App Store Connect, record it in GitHub:

```
tools/dev/tag-store-release.sh 1.7.0
```

Tags and GitHub releases mark App Store releases only, never TestFlight cuts.


Because the version uses manual release, approval does not publish. In App
Store Connect open the approved version and press **Release this version**.

## 6. After the app is live

- `tools/store/offer_codes.py codes monthly 10` / `codes yearly 10` mint the
  single-use VIP gift codes (Apple only allows this for live apps).
- `asc_publish.py subscriptions` creates the VIP win-back offers from
  `store/metadata/subscriptions/vip_*.json` (Apple only allows offers for
  approved subscriptions).
- Roll the In-App Event window forward every few weeks:
  `make_app_events.py --media-next 10` and `asc_publish.py events`.
- The purchase function verifies transactions against Production and falls back
  to Sandbox, so App Review's sandbox purchases and real purchases both work
  without changing `APPLE_ENVIRONMENT`.

## Crash reports

Apple collects crashes from TestFlight and App Store users with no SDK in the app. Every build uploads its
debug symbols: `ios/ExportOptions.plist` has `uploadSymbols`, the Dart code is not obfuscated (so
`App.framework.dSYM` covers it), and the "Release to TestFlight" workflow checks that the archive holds
`Runner.app.dSYM`, `DailyWidget.appex.dSYM`, `App.framework.dSYM` and `Flutter.framework.dSYM` (a missing one
is a warning in the run) and keeps them as the run artifact `dsyms-<version>-<build>` for 90 days.

Where to read them:
- Xcode > Window > Organizer > Crashes, select Carden and a version or build (signed in with the
  team account). Reports arrive a day or so after the crash and are symbolicated with the uploaded dSYMs.
- App Store Connect > TestFlight > Crashes (crashes testers sent with feedback) and App Analytics > Crashes.
- For an old report that is not symbolicated, download the run's `dsyms-...` artifact and drag the report
  into Xcode's Organizer, or run `symbolicatecrash` against those dSYMs.

## In-App Events, Mac and Vision Pro

- World-day events as App Store In-App Events: `tools/store/make_app_events.py`, then `asc_publish.py events`
  (drafts only, see `tools/store/README.md`, "In-App Events"). The first ones go to review with the first App
  Store version.
- The iPhone app can run on Apple silicon Macs and Apple Vision Pro. TestFlight already offers builds on both
  (`asc_publish.py platforms`); App Store availability is two ticks in Pricing and Availability (steps in
  `tools/store/README.md`, "Done in App Store Connect by hand"). Test a build on a Mac through TestFlight before
  ticking them: notifications, Sign in with Apple, StoreKit, the photo picker and the portrait-only layout.

## Metadata and assets

Copy lives in `store/metadata`, screenshots in `store/screenshots`; the
`asc_publish.py` subcommands (`app-info`, `version`, `screenshots`, `iap`,
`subscriptions`, `review-info`, `testflight`, `release`, `submit`, `audit`) push
them to App Store Connect and are idempotent. Regenerate screenshots with
`tools/dev/qa-run.sh drive` on the iPhone 17 Pro Max simulator and
`tools/store/compose_screenshots.py` (see `store/README.md`).

## Secrets

`secrets/` holds the App Store Connect key, the distribution certificate and
its password. Only the issuer id file is tracked. GitHub Actions has the same
values as repository secrets: `APP_STORE_CONNECT_KEY_ID`,
`APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8`,
`IOS_DISTRIBUTION_P12`, `IOS_DISTRIBUTION_P12_PASSWORD`.
