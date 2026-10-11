# App Store Connect automation

`asc_publish.py` pushes the metadata in `store/metadata/` to App Store Connect
through the official API, idempotently: it reads what exists, creates what is
missing and updates what differs, so it can be rerun after a partial failure.
`upload_build.sh` archives and uploads the iOS build. `compose_screenshots.py`
(separate tool) renders the screenshots the publisher uploads.

## Credentials

| What | Where |
| --- | --- |
| Team API key `9QC72A5QMN` (role App Manager or Admin) | `secrets/AuthKey_9QC72A5QMN.p8` (never committed) |
| Issuer ID | env var `ASC_ISSUER_ID`, or the file `secrets/app-store-connect-issuer-id.txt` |

To find the Issuer ID: App Store Connect > Users and Access > Integrations >
App Store Connect API. It is shown at the top of the page as "Issuer ID"
(a UUID), above the list of team keys. Copy it:

```bash
echo "<issuer id>" > secrets/app-store-connect-issuer-id.txt
# or, per shell session
export ASC_ISSUER_ID=<issuer id>
```

The script exits with a message if neither is present. `secrets/` is
git-ignored; nothing in it is printed by the tools.

## Python

The script needs `pyjwt`, `cryptography` and `requests`:

```bash
python3 -m venv .venv && .venv/bin/pip install pyjwt cryptography requests
```

Below, `asc` stands for `.venv/bin/python tools/store/asc_publish.py`.

## What each subcommand does

| Subcommand | App Store Connect resources |
| --- | --- |
| `app-info` | `apps` (content rights = uses third-party content, App Store Server Notification URLs), `appInfos` categories (`categories.json`), `appInfoLocalizations` for the app's primary locale: name, subtitle, privacy policy URL |
| `version` | the editable `appStoreVersions` record renamed to 1.7.0 (or created), copyright, and the `appStoreVersionLocalizations`: description, keywords, promotional text, support and marketing URL, what's new |
| `age-rating` | `ageRatingDeclarations` from `age_rating.json` |
| `price-free` | `appPriceSchedules` with the free USA price point (Apple equalises the rest) and `appAvailabilities` (v2) for every territory |
| `screenshots` | one `appScreenshotSets` of type `APP_IPHONE_67` and every PNG in `store/screenshots/iphone-6.9/` in file order (reserve, upload, commit with MD5; files already uploaded are skipped by name) |
| `iap` | the eight consumables from `subscriptions/consumables.json` (`/v2/inAppPurchases`), localizations, USD price equalised to all territories through `inAppPurchasePricePoints/{id}/equalizations`, availability, optional review screenshot |
| `subscriptions` | group `VIP` and its localization, `vip_monthly` / `vip_yearly` attributes and localizations, one `subscriptionPrices` per territory from `subscriptionPricePoints/{id}/equalizations`, one `subscriptionIntroductoryOffers` (1 week free) per territory, review screenshot, promotional image, availability |
| `review-info` | `appStoreReviewDetails`: contact from `review_contact.json` and `review_notes.txt` |
| `testflight` | `betaAppLocalizations` (feedback email, what to test, URLs), `betaAppReviewDetails`, `betaLicenseAgreements`, the latest build's `usesNonExemptEncryption=false` and what-to-test text, and an external `betaGroups` "Public testers" with a public link containing the latest build |
| `status` | prints what exists; `--categories` also lists the category ids |
| `audit` | read-only checklist (OK / MISSING / N/A) for submission and for a public TestFlight link; exit code 1 while something is missing |
| `all` | `app-info`, `version`, `age-rating`, `price-free`, `screenshots`, `iap`, `subscriptions`, `review-info`, `testflight`, in that order |

Every subcommand accepts `--dry-run`, which prints each request (method, URL,
JSON body) instead of sending it, and `-v` to also print GET requests.

Locale: the app's `primaryLocale` in App Store Connect is `en-GB`. The script
reads it from the app record and writes every localization to that locale; the
text itself lives in `store/metadata/en-US/` (the folder name is just where the
copy is kept).

## Before running

1. Fill in `store/metadata/en-US/review_contact.json` (name, phone, email).
   Placeholders in square brackets are skipped with a warning, and `audit`
   reports them as missing.
2. Generate the screenshots and the subscription images:
   `python tools/store/compose_screenshots.py` (writes
   `store/screenshots/iphone-6.9/*.png`, `store/review/subscription-review.png`,
   `store/promo/vip-promotional-1024.png`).
3. Check the prices in `store/metadata/subscriptions/consumables.json` against
   `docs/purchases.md` and `lib/features/store/store_screen.dart`.

## Commands, in order

```bash
asc status                       # confirms the key works and shows what exists
asc all --dry-run                # review every request
asc app-info
asc version
asc age-rating
asc price-free
asc screenshots
asc iap
asc subscriptions
asc review-info
tools/store/upload_build.sh      # archive, export, upload (10 to 30 min of processing follows)
asc testflight                   # after the build shows up as processed
asc audit                        # everything should be OK or N/A
```

`asc all` runs the same steps without the upload. Rerunning any step is safe.

## Uploading a build

`tools/store/upload_build.sh` runs `flutter build ios --release --no-codesign`
(so the Flutter assets exist), then `xcodebuild archive` and
`xcodebuild -exportArchive` with `ios/ExportOptions.plist`
(method `app-store-connect`, automatic signing through the API key), then
`xcrun altool --upload-app` with the same key. The build number comes from
`pubspec.yaml` (`1.7.0+10`).

Export compliance: the app only uses HTTPS, which is exempt. Add
`ITSAppUsesNonExemptEncryption` = `NO` to `ios/Runner/Info.plist` so every
upload is marked exempt automatically; `asc testflight` also sets
`usesNonExemptEncryption=false` on the latest build for builds uploaded before
the key was added.

## Done in App Store Connect by hand

- **App Store Server Notifications**: the production and sandbox URLs are
  app attributes (`subscriptionStatusUrl`, `subscriptionStatusUrlForSandbox`,
  version V2) and `app-info` sets both to
  `https://cjw-verify-purchase.fra.appwrite.run/notifications`. If the console
  shows something else, set it under App > App Information > App Store Server
  Notifications.
- **App Privacy** (data collection questionnaire) has no public API: fill in
  App Store Connect > App Privacy. The honest answers for this app are in
  `docs/privacy-policy.md` (account id, email if given, purchase history,
  gameplay content; no tracking, no third-party advertising).
- **Agreements**: Paid Applications agreement, banking and tax forms
  (App Store Connect > Business).
- **Submitting**: attach the processed build to version 1.7.0 and submit the
  version together with the in-app purchases and subscriptions
  (they are submitted with the first version that uses them).
- **Sandbox tester** for verifying purchases on a device:
  Users and Access > Sandbox.

## Files the script reads

```
store/metadata/en-US/
  name.txt subtitle.txt promotional_text.txt description.txt keywords.txt
  release_notes.txt support_url.txt marketing_url.txt privacy_url.txt
  copyright.txt review_notes.txt review_contact.json age_rating.json
  categories.json testflight_what_to_test.txt beta_license_agreement.txt
store/metadata/subscriptions/
  group.json vip_monthly.json vip_yearly.json consumables.json
store/screenshots/iphone-6.9/*.png
store/review/subscription-review.png
store/promo/vip-promotional-1024.png
```
