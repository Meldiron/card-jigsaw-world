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
| Install on the phone (USB or Wi-Fi) | `tools/dev/device.sh [--wipe] [--no-build]` | release build, installs on the paired iPhone |
| Next TestFlight build of the current version | `tools/dev/testflight.sh` | runs the `Release to TestFlight` workflow; build = 100 + run number; waits for processing, adds to internal + public groups, submits beta review only if the version has none |
| Start a new version cycle | `tools/dev/release.sh X.Y.Z` | bumps pubspec, commits, pushes, first build; only after the previous version shipped to the store or was abandoned |
| Submit to App Review | Actions → `Submit to App Store` (version, optional build) | `asc_publish.py release` + `submit --yes`; always human-started |
| Record a store release | `tools/dev/tag-store-release.sh X.Y.Z` | tag + GitHub release; never for TestFlight cuts |
| State of everything on Apple | `tools/store/asc_publish.py audit` / `status` | builds, review states, metadata gaps |
| Tester feedback | `asc_publish.py feedback` / `--resolve ID,ID --note ...` | list, then delete on Apple + local ledger after fixing |

Run scripts with the venv python that has pyjwt/requests (see tools/store/README.md)
or plain python3 with those packages installed. Credentials live in `secrets/`.

## Every build also updates the web site
After `tools/dev/testflight.sh` always run `tools/dev/deploy-web.sh` so https://card-jigsaw-world.appwrite.network ships the same commit (owner rule, 2026-10-12). Both can run in parallel only if the Flutter builds do not overlap; run the web deploy after the device/TestFlight build finishes.

## Before every upload
1. `git status` clean, main pushed, analyzer and tests green, QA runs silent
   (`--dart-define=CJW_MUTE=true`).
2. Check builds: if a build of the **current** version is already in or past beta
   review, keep it (its approval covers the new build). Do not upload an older
   version string than the one in review.
3. Expire superseded builds of other version strings (`PATCH /v1/builds/{id}` with
   `expired: true`); this also cancels their pending review so they do not compete.
4. Never expire the build that is attached to the App Store version while it is
   the only approved one.

## When the user says
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
