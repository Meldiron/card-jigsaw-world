---
name: apple-release
description: Ship Card Jigsaw World to TestFlight and the App Store without triggering extra Apple reviews. Use for any request to release, push a build, cut a version, submit for review, or get a build to public or internal testers.
---

# Apple release workflow for Card Jigsaw World

## The one rule
Apple reviews TestFlight builds for **external testers once per version string**
(CFBundleShortVersionString). Later builds of the same version reach public testers
with no review. A new version string always starts a new Beta App Review (1 to 7
days). The App Store version record must match the version string of the build you
attach to it. Therefore: **one version string per App Store release cycle; TestFlight
iterates by build number only.**

## Commands
| Goal | Command | Effect |
| --- | --- | --- |
| Install on the phone (only when the owner asks) | `tools/dev/device.sh [--wipe] [--no-build]` | release build, installs on the paired iPhone |
| Next TestFlight build of the current version (only when the owner asks) | `tools/dev/testflight.sh` | runs the `Release to TestFlight` workflow; build = 100 + run number; waits for processing, adds to internal + public groups, submits beta review only if the version has none |
| Start a new version cycle | `tools/dev/release.sh X.Y.Z` | bumps pubspec, commits, pushes, first build; only after the previous version shipped to the store or was abandoned |
| Submit to App Review | Actions → `Submit to App Store` (version, optional build) | `asc_publish.py release` + `submit --yes`; always human-started |
| Record a store release | `tools/dev/tag-store-release.sh X.Y.Z` | tag + GitHub release; never for TestFlight cuts |
| State of everything on Apple | `tools/store/asc_publish.py audit` / `status` | builds, review states, metadata gaps |
| Tester feedback | `asc_publish.py feedback` / `--resolve ID,ID --note ...` | list, then delete on Apple + local ledger after fixing |

Run scripts with the venv python that has pyjwt/requests (see tools/store/README.md)
or plain python3 with those packages installed. Credentials live in `secrets/`.

## Every build also updates the web site
After `tools/dev/testflight.sh` always run `tools/dev/deploy-web.sh` so https://card-jigsaw-world.appwrite.network ships the same commit (owner rule, 2026-10-12). Both can run in parallel only if the Flutter builds do not overlap; run the web deploy after the device/TestFlight build finishes.

## Per-build "What to Test"
Before each build rewrite `store/metadata/en-US/testflight_build_notes.txt` with a TL;DR of what
changed since the previous build (2-4 plain bullets, one "Please try:" line); the workflow sends it as
that build's TestFlight "What to Test". `release_notes.txt` stays the App Store "What's New" for the
whole version. `asc_publish.py --build N build-notes` rewrites one existing build's text.

## Before every upload
1. `git status` clean, main pushed, analyzer and tests green, QA runs silent and flagged
   (`tools/dev/qa-run.sh`: `CJW_MUTE=true`, `CJW_QA=true`, test players purged), and no test players
   left: `python3 tools/dev/purge_test_players.py purge` lists none (`--apply` removes them).
2. Check builds: if a build of the **current** version is already in or past beta
   review, keep it (its approval covers the new build). Do not upload an older
   version string than the one in review.
3. Expire superseded builds of other version strings (`PATCH /v1/builds/{id}` with
   `expired: true`); this also cancels their pending review so they do not compete.
4. Never expire the build that is attached to the App Store version while it is
   the only approved one.

## When the user says
- Never start a build, submission or web deploy on your own: only these explicit requests do.
- "release", "push a build", "ship to testers" → `testflight.sh`, keep the version.
- "new version", "bump", "App Store release" → `release.sh X.Y.Z`, then later the
  `Submit to App Store` workflow, then `tag-store-release.sh` after it is live.
- "cancel the review" → expire that build only if another build of the same version
  is not needed; otherwise leave it, the review carries over.

## Groups
- Internal testers (`hasAccessToAllBuilds`): see every processed build at once.
- Public testers: public link https://testflight.apple.com/join/7nPCfg6A, only
  builds of a version that passed Beta App Review.

## Related docs
`docs/release-flow.md`, `docs/release-checklist.md`, `tools/store/README.md`.

## Renaming in-app purchases while they sit in a review draft
If products were added to the app's open review submission ("Submit for Review" on the products in App
Store Connect), their en-GB localization (customer name and description) is locked: PATCH and DELETE
fail with 409 "version is not editable", even though the localization says PREPARE_FOR_SUBMISSION.
`asc_publish.py iap` still updates reference names and review notes. To change the customer text:
for each product, DELETE its `reviewSubmissionItems/{id}` (the item that points at its
`inAppPurchaseVersion`), PATCH the `inAppPurchaseLocalizations/{id}`, then POST a new
`reviewSubmissionItems` with relationships `reviewSubmission` + `inAppPurchaseVersion`. The draft is
never submitted by this. Done this way for the 2026-10-12 amount change (all 8 consumables).

## "expected 2 profiles, installed 1" in the workflow
Editing an App ID on the developer portal (its name, capabilities) turns its App Store profile
INVALID, and `tools/store/install_profiles.py` only installs ACTIVE ones. Recreate it under the same
name: `GET /v1/profiles?include=bundleId,certificates` to find the invalid one, its bundle id and the
distribution certificate, `DELETE /v1/profiles/{id}` (Apple refuses a second profile with the same
name), then `POST /v1/profiles` with `name` (`CJW AppStore cardjigsawworld` or `CJW AppStore
DailyWidget`), `profileType: IOS_APP_STORE` and relationships `bundleId` + `certificates`. Then
`gh run rerun <run id>`: nothing was uploaded, so the build number stays. Happened 2026-10-13 after the
App ID description was renamed.

## Payment function deploys
The repo's API keys cannot deploy functions. Package with
`COPYFILE_DISABLE=1 tar --exclude node_modules -czf verify-purchase.tar.gz -C functions/verify-purchase .`
and create the deployment through the Appwrite MCP (`functions_create_deployment`, base64 content,
`activate: true`, entrypoint `src/main.js`, commands `npm install`), then check
`https://cjw-verify-purchase.fra.appwrite.run/health`. Deploy the function before a build that shows
new amounts, so the server never credits less than the app displays.
