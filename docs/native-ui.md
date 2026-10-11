# Native UI on iOS 26 and 27

How the app's chrome (tab bar, headers, dialogs, sheets) is built so it reads
as native on iOS 26+ while still working on iOS 15 and on the simulator.

## Decision

**First-party Cupertino widgets for every modal, plus a small in-house glass
material (`lib/widgets/glass.dart`) for bars and sheets. No package.**

What is used where:

| Component | Implementation |
| --- | --- |
| Confirmations, destructive prompts, text-entry prompts (rename, friend code) | `showCupertinoDialog` + `CupertinoAlertDialog`. Flutter draws the system alert (blurred popup surface, hairlines, bold default action). Cancel left, confirm right, destructive in red. |
| Pickers and menus (add a photo) | `showCupertinoModalPopup` + `CupertinoActionSheet`. |
| Content-sized sheets (pause menu, daily gift, piggy bank, tier unlock, pack access, avatar picker, credits) | `showAppSheet` in `lib/widgets/ui.dart`: a modal bottom sheet rendered on `GlassSheet` (28pt top radius, grabber, 32% dim, blur + saturation + tint, home-indicator inset). This is what iOS 26 partial-height sheets look like. |
| Full-height modals (Store, Wheel, Account) | `CupertinoSheetRoute` via `_SheetPage` in `lib/router.dart`: the real stacked-sheet presentation. The sheet stops below the status bar, the page behind scales back, drag down to dismiss. |
| Bottom tab bar | `GlassTabBar`: floating capsule inset 16pt from the edges, hovering above the home indicator, blurred content underneath, soft tinted pill behind the selected tab (iOS 26 shape). Icons and labels unchanged. `Scaffold.extendBody: true` so pages scroll beneath it. |
| Tab headers (Home, Library, Events, Profile) | `GlassSliverHeader` / `HeaderBar`: pinned, transparent while the list is at the top, glass with a hairline once content scrolls under. Same rule as `CupertinoNavigationBar.automaticBackgroundVisibility`. |
| App bars on pushed pages (Settings, Store, Account, My Puzzles, Difficulty, Wheel) | `GlassAppBar` with `extendBodyBehindAppBar: true`. Transparent at rest, glass when scrolled under. |
| Pack cover | `SliverAppBar` whose collapsed state turns into glass over the blurred top of the cover. |
| Toasts | Material floating `SnackBar`, shown through the root `ScaffoldMessenger` so it sits on the outermost Scaffold: above the floating tab bar and above sheet barriers. |

## Why not a package

Evaluated on 2026-10-11:

- **`cupertino_native`** (serverpod, 0.1.1): three releases, all 13 months old,
  self-described "more of a proof of concept than a full package", built
  against the Xcode 26 beta. Provides a tab bar, buttons, slider, switch,
  segmented control and popup button through platform views; no navigation
  bar, no sheets, scroll-view integration "still under investigation".
  A platform-view tab bar would also sit outside the Flutter tree: no
  go_router shell integration, the daily-gift badge and press feedback would
  have to be rebuilt in Swift, and the simulator screenshot flow could not
  drive it through `WidgetTester`.
- **`liquid_glass_native`** (0.3.1, unverified publisher, ~180 downloads):
  SwiftUI glass tab bar, nav bar, buttons and sheets via platform views with
  fallbacks below iOS 26. Same platform-view objections; too young to pin a
  shipping app to.
- **`liquid_glass_renderer`** (0.2.0-dev.4): pure-Flutter refraction shader.
  Marked "EXPERIMENTAL - USE WITH CAUTION", Impeller only, re-renders every
  frame when anything under it moves, known memory spikes while animating.
  The board animates constantly, so the bars would pay that cost on every
  frame.
- **Flutter 3.47 Cupertino**: `CupertinoAlertDialog`, `CupertinoActionSheet`,
  `CupertinoSheetRoute`, `CupertinoNavigationBar` and `CupertinoTabBar` all
  blur a translucent background (`BackdropFilter`), which is the pre-26
  system material. Core Cupertino has no Liquid Glass material yet
  (tracked in flutter/flutter#170310), so a bar built from first-party parts
  and a bar built from `GlassSurface` look the same; ours keeps the app's
  layout (avatar, level, currency pills) and tokens.

## What "glass" means here

`GlassSurface` = `BackdropFilter(blur 24, saturation 1.35)` + surface tint
(white 72% in light, `#1C1C22` 62% in dark) + 0.5pt hairline. That is the
recipe of `UIBlurEffect.systemChromeMaterial`: the look of bars up to iOS 18
and what iOS 26 falls back to when Reduce Transparency is on. True Liquid
Glass refraction and specular edges are not reachable from Dart; if that
ever matters, the tab bar is the one place where a platform view would pay
off, and `GlassTabBar` can be swapped without touching the pages.

The material degrades to exactly the same pixels on iOS 15 and on the
simulator, because it is all drawn by Flutter.

## Rules kept

- No emoji, no gradients; the only colour in chrome is the indigo accent on
  the selected tab and default buttons.
- Alerts keep platform order: Cancel left, confirm right (bold).
- Pages that scroll under a bar pad their first and last item with
  `MediaQuery.paddingOf(context).top` / `.bottom`; the Scaffold sets both to
  the bar heights when `extendBody` / `extendBodyBehindAppBar` is on.
