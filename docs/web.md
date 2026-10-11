# Web build

Card Jigsaw World runs in the browser as the same Flutter app, built with
`flutter build web`. The web version is deliberately limited to what works
without native plugins; everything else is the iPhone app.

## What is limited on web, and why

| Feature | Web | Why |
| --- | --- | --- |
| Coin, ticket and hint bundles, VIP subscription | Not sold. The store shows a notice card, the free sources (bonus video, quests, piggy bank, Lucky Wheel) and the VIP benefits with an "Available on iPhone" label. | Purchases go through StoreKit and are verified by the `verify-purchase` Appwrite Function with a StoreKit 2 JWS. `in_app_purchase` has no web implementation. A VIP bought on iPhone is active on web too (it lives on the profile). |
| Gift codes ("Redeem a gift code", "Have a gift code?") | Hidden. | App Store offer codes are redeemed through the StoreKit sheet. |
| Restore purchases | Hidden. | StoreKit only. |
| House ads | Shown. The rewarded "Watch" card still pays coins; CTAs that lead to a purchase show "Purchases are available in the iPhone app." instead of opening the store. | The ads are in-app promotions, not an ad network. |
| Daily reminders switch | Hidden. | No notification plugin is wired on web. |
| Home Screen widgets, quick actions | Not present. | WidgetKit and `quick_actions` are native. |
| Sign in with Apple | OAuth redirect through Appwrite, returning to `/auth/callback`. | The native `sign_in_with_apple` sheet needs an app. Handled in `account_screen.dart` / `state/auth.dart`. |
| Sound, music, haptics | Sound and music work (`audioplayers` web). Haptics are a no-op. | Browsers block autoplay until the first tap; the music starts on the first interaction. |
| My Puzzles uploads | Work (`image_picker` web uses a file chooser). | |

Every one of these is gated by `lib/core/platform.dart`:

- `isWeb`, `supportsPurchases`, `supportsGiftCodes`, `supportsQuickActions`,
  `supportsWidgets`, `supportsNotifications`, `supportsNativeAppleSignIn`
  for services.
- `platformCapsProvider` (a `PlatformCaps` snapshot) for widgets, so tests
  can pump the web and iOS layouts on the VM (`test/platform_guards_test.dart`).

`PurchaseService` never reads `InAppPurchase.instance` on web: `start()` is a
no-op, `isAvailable()` is false, `queryProducts()` is empty,
`presentCodeRedemptionSheet()` is false and `restorePurchases()` reports zero.

## Known gap: images without CORS headers

The browser only lets Flutter decode an image into a puzzle board when the
host sends `Access-Control-Allow-Origin`. Probed on 2026-10-11 against the
catalog hosts:

| Host | CORS | Puzzles |
| --- | --- | --- |
| live.staticflickr.com (Openverse) | yes | 5,117 |
| openaccess-cdn.clevelandart.org (Masterpieces) | **no** | 2,432 |
| picsum.photos | yes | 1,816 |
| images.rawpixel.com | yes | 406 |
| images-assets.nasa.gov (Deep Space) | **no** | 339 |
| cdn.stocksnap.io | 403 to the probe, unverified | 304 |
| inaturalist-open-data.s3.amazonaws.com, pd.w.org | yes | 106 |

Cleveland Museum of Art and NASA pictures therefore fail to load on web
(console: "blocked by CORS policy"); the covers stay on their BlurHash and
the board cannot start. The fix is server-side: either copy those files into
the `puzzle-images` bucket (Appwrite Storage sends CORS headers for
registered web platforms) or add an image proxy function and rewrite
`imageUrl` for those packs. The iPhone app is unaffected.

## Layout

On wide windows the app is centred in a 520 px column on the canvas colour
(`PhoneFrame` in `lib/app.dart`), and the inherited `MediaQuery` is narrowed to
that column so the phone layout is not stretched. Narrow windows are untouched.

## Routing

`main.dart` calls `usePathUrlStrategy()` on web, so links are plain paths:
`/play/<puzzleId>`, `/library/pack/<packId>`, `/store`, `/auth/callback`.
Unknown paths fall back to Home (`onException` in `lib/router.dart`) instead
of the framework's error page.

The host must serve `index.html` for every path (single-page fallback), or
deep links and the OAuth callback return a 404.

## Build

```sh
export PATH="$HOME/flutter/bin:$PATH"
flutter build web --release --base-href /
```

Output: `build/web` (about 36 MB with CanvasKit; the renderer is Flutter's
default, CanvasKit). `web/index.html` carries `<base href="$FLUTTER_BASE_HREF">`,
which the build replaces with `/`.

Text is drawn by the engine with its bundled Roboto fallback (fetched from
fonts.gstatic.com on first load); the loading splash uses the system font
stack. The splash disappears on Flutter's `flutter-first-frame` event.

Icons: `web/icons/Icon-192.png`, `Icon-512.png`, maskable variants and
`web/favicon.png` are generated from the 1024 px app icon
(`ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png`)
with Pillow. Regenerate them if the icon changes.

## Run locally

```sh
flutter run -d chrome --dart-define=CJW_MUTE=true   # silent, for QA
```

`CJW_MUTE=true` silences music and effects. To test the release bundle with
path routing, serve `build/web` with any static server that falls back to
`index.html`.

## Tests

```sh
flutter test                                                   # VM, all suites
flutter test --platform chrome test/platform_guards_test.dart  # in Chrome, kIsWeb = true
```

## Deploy (Appwrite Sites)

The main session deploys to Appwrite Sites (project `6acb4de5003e38d5ebd9`,
Frankfurt). The site must have the single-page fallback file set to
`index.html`, and the site's hostname must be registered as a Web platform on
the Appwrite project (the OAuth redirect and session cookies depend on it).

```sh
flutter build web --release --base-href /
appwrite sites create-deployment --site-id <site-id> --code ./build/web --activate true
```

Nothing in `build/web` is secret: the Appwrite endpoint and project id are
public, and all writes are protected by Appwrite permissions and the
server-side functions.
