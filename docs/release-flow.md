# Release flow

One path from a USB-connected iPhone to the App Store, with exactly two human
decisions: when to cut a release, and when to submit to App Review.

```
local iPhone  ──►  GitHub release  ──►  TestFlight  ──►  App Review  ──►  App Store
tools/dev/device.sh   tools/dev/release.sh   automatic          manual workflow   manual click
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

## 3. Cutting a release → TestFlight (automatic)

```
tools/dev/release.sh 1.8.0                 # notes from store/metadata/en-US/release_notes.txt
tools/dev/release.sh 1.8.0 --notes FILE
```

The script bumps `pubspec.yaml`, runs analyze and tests, commits, tags
`v1.8.0`, pushes and publishes a GitHub release. Publishing the release starts
`Release to TestFlight` (`.github/workflows/release-testflight.yml`), which:

1. downloads the App Store provisioning profiles and switches the Release
   configurations to manual signing with the distribution certificate;
2. archives, exports and uploads the build (build number = 100 + run number,
   always above hand-uploaded builds);
3. waits for Apple to process it, writes the release notes as the build's
   "what to test", adds it to the internal tester group (installable at once)
   and to "Public testers", and submits it to Beta App Review (the public link
   only works for builds that passed it).

The same workflow can be started by hand from the Actions tab.

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

Because the version uses manual release, approval does not publish. In App
Store Connect open the approved version and press **Release this version**.

## 6. After the app is live

- `tools/store/offer_codes.py codes monthly 10` / `codes yearly 10` mint the
  single-use VIP gift codes (Apple only allows this for live apps).
- The purchase function verifies transactions against Production and falls back
  to Sandbox, so App Review's sandbox purchases and real purchases both work
  without changing `APPLE_ENVIRONMENT`.

## Metadata and assets

Copy lives in `store/metadata`, screenshots in `store/screenshots`; the
`asc_publish.py` subcommands (`app-info`, `version`, `screenshots`, `iap`,
`subscriptions`, `review-info`, `testflight`, `release`, `submit`, `audit`) push
them to App Store Connect and are idempotent. Regenerate screenshots with
`flutter drive` on the iPhone 17 Pro Max simulator and
`tools/store/compose_screenshots.py` (see `store/README.md`).

## Secrets

`secrets/` holds the App Store Connect key, the distribution certificate and
its password. Only the issuer id file is tracked. GitHub Actions has the same
values as repository secrets: `APP_STORE_CONNECT_KEY_ID`,
`APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8`,
`IOS_DISTRIBUTION_P12`, `IOS_DISTRIBUTION_P12_PASSWORD`.
