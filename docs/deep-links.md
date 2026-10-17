# Deep links

One set of paths opens the same screen everywhere:

| Form | Example | Where it works |
| --- | --- | --- |
| Web address | `https://play.carden.page/library/pack/pack-owls` | The web site; on an iPhone with the app installed it opens the app (universal link) |
| App scheme | `carden://library/pack/pack-owls` | The iPhone app (and Android builds); used by the widget and the App Store In-App Events |

The game was called Card Jigsaw World until build 118. Its links keep working: the app still registers and reads
`cardjigsaw://` (`AppLink.legacyScheme`), and the earlier web addresses, `https://carden.appwrite.network` and
`https://card-jigsaw-world.appwrite.network`, serve the same site. New links use `carden://` and
`https://play.carden.page` (`AppLink.webOrigin`).

Share the web address: it works for everyone, in the app where it is installed and in the
browser everywhere else. `AppLink.webUrl` / `AppLink.appUrl` (`lib/core/app_links.dart`) build
either form from a link.

## Links

| Path | Opens | Notes |
| --- | --- | --- |
| `/` or `/home` | Home | A new player still sees the welcome screens |
| `/library` | Library | `?filter=` picks a chip: `all`, `new`, `finished`, `started`, `unlocked`, `daily` or a category with a chip (`giant`, `ai`, `animals`), any case; anything else (`event`: events live on Home and in Quests) opens All |
| `/library/pack/<packId>` (also `/pack/<packId>`) | A pack | "Pack not available" for a pack the catalogue does not list (removed, an event not announced yet, a pack-code pack not redeemed) |
| `/play/<puzzleId>` (also `/picture/<id>`) | A picture's mode and board picker | `?grid=hexagons-5x6`, `?mode=triangles`, `?painting=1` preselect. A picture in a pack the player has not opened (or a daily picture not out yet) shows its pack instead, with the price. "Picture not available" for an unknown id |
| `/game/<puzzleId>/<grid>` | The same picker, that board chosen | Never starts a board directly, so board and pack locks apply |
| `/daily` (also `/today`) | Today's picture | |
| `/quick` | Quick play | A random picture, as the Home card picks it |
| `/events` (also `/quests`) | Quests | |
| `/social` (also `/leaderboard`) | Social, Leaderboard | `?tab=friends` (or `/friends`) for Friends |
| `/add-friend?code=<friend code>` (also `/friend/<code>`) | Social > Friends with "Add friend by code" filled in | The player still taps Add friend |
| `/profile` | My profile | |
| `/profile/settings` (also `/settings`) | Settings | |
| `/profile/my-puzzles` (also `/my-puzzles`) | My Puzzles | |
| `/account` (also `/sign-in`, `/profile/account`) | Account: sign in or create account, or the signed-in account (a sheet) | Account is a sheet wherever it opens |
| `/player/<userId>` (also `/user/<userId>`) | A player's profile | The user id is the friend code |
| `/store` (also `/shop`) | Store | `?vip=1` (or `/vip`) opens at VIP |
| `/wheel` | Lucky Wheel | |
| `/redeem?code=<pack code>` (also `/redeem/<code>`, `/code/<code>`) | "Redeem a pack code" with the code filled in | The player still taps Redeem; without a code the field is empty |
| `/inbox?message=<id>` (also `/inbox/<id>`, `/messages/<id>`) | Social > Inbox with that message open | The friend gift notification's link (docs/friend-gifts.md); "Message not available" once it expired or was deleted. Without a valid id, the Inbox |
| `/gift` | Home with the daily gift | |
| `/piggy` | Home with the piggy bank | |

Keywords are case-insensitive; ids keep their case. Anything else (unknown paths, site files,
`/auth/callback`) is not a link: the web site shows Home for an unknown path.

## How a link is shown

`AppLink.parse` reads the web address, the `carden://` form (where the first word lands in the
URL's host) or a bare path into a route and a kind; `DeepLinks.show`
(`lib/features/links/deep_links.dart`) puts it on screen:

- **page** (a tab, a pack, Settings): replaces what is on screen (`go`).
- **overlay** (a picture, the store, the wheel, a player, sign-in): opens above what is on screen,
  or above Home when the app has just started or shows the welcome screens. The same overlay is
  never stacked twice.
- **action** (a pack code, a friend code, today's picture, Quick play, the daily gift, the piggy
  bank, one inbox message): opens the sheet or alert over the screen it belongs to.

Any link other than plain Home counts as onboarding: a new install opened from a link goes
straight to it.

Where links come in:

- **iPhone**: iOS hands a tapped link (scheme or universal link) to Flutter
  (`FlutterDeepLinkingEnabled` in `Info.plist`), which sends it as `pushRouteInformation`.
  `CardJigsawApp.didPushRouteInformation` sees it before the router and passes the game's links to
  `DeepLinks`; other schemes (the Appwrite sign-in redirect) go on to the router.
- **Web**: the link is the address the visit starts on. `routerProvider` opens a plain page (for
  example `/library/pack/<id>`) itself; anything else (an alias, a query, an overlay that needs Home
  beneath it, an action) starts on Home and goes to `DeepLinks` after the first frame. Browser back
  and forward stay with the router.
- **Inside the app**: a `go` or `push` to a path the router has no page for (an alias, `/redeem`)
  reaches `onException`, which passes it to `DeepLinks`.

Inbox links (2026-10-16): `/inbox` (and `/messages`, `/social?tab=inbox`) opens Social > Inbox, and
`/feedback` opens the Send feedback sheet; inbox messages use any of these paths as their button.
`/inbox?message=<id>` (2026-10-17, an action) opens one message over the Inbox, after reading the
inbox again: a tapped gift notification arrives as this link (`PushRegistration`, docs/friend-gifts.md).

## Universal links (iPhone)

Status (2026-10-16): on from version 2.0.0. The App ID has the Associated Domains capability, the App Store
profile was remade after it, and `Runner.entitlements` claims play.carden.page, carden.appwrite.network and
card-jigsaw-world.appwrite.network. Builds before 2.0.0 open web addresses in the browser; `carden://` links
work everywhere.

The web address opens the app when:

1. the app carries `applinks:play.carden.page` (`ios/Runner/Runner.entitlements`); the App ID needs the
   Associated Domains capability and the App Store profile used by CI must be made after it was turned on
   (see "expected 2 profiles" in the apple-release skill), and
2. the site serves `web/.well-known/apple-app-site-association` (deployed with the site by
   `tools/dev/deploy-web.sh`). It lists the link paths above and keeps `/auth/*` (the web sign-in
   callback) and the pack code links `/redeem*` and `/code*` (redeemed on the web only) in the browser. Apple's CDN caches it; after a change it can take a day to reach
   devices. Check what Apple sees with
   `curl https://app-site-association.cdn-apple.com/a/v1/play.carden.page`.

A link typed into Safari's address bar, or tapped on a page of the site itself, stays in the
browser (iOS rule). Long-press a link and choose "Open in Carden" to switch; iOS
remembers the choice.

`test/deep_links_test.dart` checks that every link reads the same in all three forms, that the
association file covers every link path and nothing else, and how `DeepLinks` shows each kind.
`integration_test/deep_links_test.dart` follows every kind of link on the real app.

## Trying a link

- iPhone: type `carden://daily` into Safari's address bar (iOS asks to open the app), or tap a
  link in Notes or Messages.
- Simulator: `xcrun simctl openurl booted 'carden://redeem?code=ABCD-EFGH-JKLM-NPQR'` while the
  app runs (start it with `tools/dev/qa-run.sh run -d <udid>`).
- Web: open the address, e.g. `https://play.carden.page/quests`.

## Adding a link

1. Add the path (and any alias) to `AppLink.parse` with its kind.
2. If it is an action, handle it in `DeepLinks._action`.
3. Add the path to `web/.well-known/apple-app-site-association`.
4. Add it to the table above and to `_links` in `test/deep_links_test.dart`.
