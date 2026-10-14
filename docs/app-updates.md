# Update prompt (web and iPhone)

Owner request, 2026-10-14: when a newer build is out, the app says so and offers to update.

## Behaviour

- Looks for a newer build 8 seconds after start, then every 5 minutes while the app is in front and
  every hour while the tab is hidden or the app is in the background (`UpdatePolicy` in
  `lib/state/app_update.dart`). Coming back to the app looks again when the last look is 5+ minutes old.
- "Update available" alert (`UpdateHost`, `lib/features/update/update_host.dart`): **Update** or
  **Later**. Later closes it for an hour. Every reload (web) or launch (iPhone) asks again; it stops
  only on the newest build. Like the sync alert it waits for a calm moment: never during a game, a
  sign-in or the welcome screens.
- Update flushes the save sync, then: web reloads the page; iPhone opens TestFlight
  (`itms-beta://beta.itunes.apple.com/v1/app/6821644423`, the browser page as fallback) or the App
  Store page, by how the app was installed (`PackageInfo.installerStore`).
- Off in `flutter run` on web (no build id), in iPhone debug builds (unless
  `--dart-define=CJW_UPDATE_CHECK=true`) and in integration tests.

## Where "newest" comes from

| Platform | Running build | Newest build | Written by |
| --- | --- | --- | --- |
| Web | `--dart-define=CJW_WEB_BUILD=<UTC time>-<commit>` | `/app-version.json` on the site (`{"build", "version", "commit"}`) | `tools/dev/deploy-web.sh`, every deploy |
| iPhone, TestFlight (also simulator and Xcode installs) | `CFBundleVersion` | row `ios-testflight` of table `releases` | `tools/dev/publish_release.py testflight --build N`, run by `tools/dev/testflight.sh` once Apple has the build out to public testers |
| iPhone, App Store | `CFBundleVersion` | row `ios-appstore` | `publish_release.py appstore --version X.Y.Z`, run by `tools/dev/tag-store-release.sh` |

The site serves every file with `max-age=0, must-revalidate`, so a reload always runs the newest
deployment (no service worker: the generated one only removes itself).

Table `releases` (database `cjw`): `read("any")`, columns `version` (varchar 32), `build` (integer),
`publishedAt` (datetime). Created with the Appwrite CLI (the repo keys cannot create tables; see
`publish_release.py init`). A row never goes back to a lower build. One read per look, so about 12
reads an hour per open iPhone app; the web look is a static file, not a database read.

When a workflow is dispatched by hand (`gh workflow run ...`), announce the build afterwards:
`.venv/bin/python tools/dev/publish_release.py testflight --build <100 + run number>` (it waits up to
an hour for Apple, then writes the row). `publish_release.py show` prints both rows.
