# App Store screenshots: research and direction

How the iPhone 6.9" screenshot set (`store/screenshots/iphone-6.9/`) is
designed, and why. Two composers read the raw captures of
`integration_test/store_screenshots_test.dart`: `tools/store/compose_glass.py`
(the Carden glass set below, 2026-10-16) and `tools/store/compose_screenshots.py`
(the dark gallery set of 2026-10-13, further down; it also draws the phone frame
and status bar both use). The steps are in `store/README.md`.

## Glass set (2026-10-16)

One light set in the brand's coloured glass, with a dark finale. Edit the copy
and slides in `SLIDES` at the top of `tools/store/compose_glass.py` and the look
in `tools/store/glass/slides.html`, then rerun the script.

- **One set for both appearances.** App Store Connect takes one screenshot set;
  its product page preview (October 2026) only shows how the page looks in Dark
  Mode. So slides 1-9 show the light app on a light canvas and the last slide switches
  to the dark app on a dark canvas ("Just as calm in the dark").
- **Glass panes on white**: two large panes in the lotus colours (pink, gold,
  blue, teal) on every seam, drawn with the app icon's glass recipe (see-through
  tinted body, top sheen, light edge zone, rim of light, crisp edge, tinted
  shadow). The bodies multiply on the white canvas, so overlaps mix like stained
  glass, and white shows between them. The set reads as one strip while each
  slide stands alone: only the background crosses a seam. The dark finale draws
  the same panes as deep jewel tones.
- **One phone size** everywhere: 1,000 px wide on the 1,320 px canvas.
- **The story:** the hook (1-3: how it plays, how much there is, and playing it
  together with friends, new in 2.0.0; the three that search results show), why
  you come back (4: the daily picture and the streak), the depth (5-9: four ways
  to cut a picture, Painting, giant boards, your own photos, quests and world-day
  events) and the dark finale (10). Read in order the headlines are one text:
  "Swap cards. Reveal the picture. Thousands of pictures. Play together with
  friends. A new picture every day. One picture, four ways to cut it. Bring the
  colour back, card by card. Giant boards of hundreds of cards. Puzzle your own
  photos. Quests and world-day events. Just as calm in the dark." Dropped on the
  owner's word: "Fewer moves, more stars" (a scoring rule) and VIP ("I don't like
  talking about VIP"). Dropped for Play together (2026-10-17; Apple takes 10
  slides and both are about friends): "Climb the ranks with friends", kept for
  custom pages as `EXTRA_SLIDES` key `league`. No AI pictures.
- **The player grows** across the slides: level 4 in the Library and 9 on Quests,
  each with another avatar, and a 23-day streak on the daily slide.
- **Contrast:** every headline is measured against what lies behind it
  (`compose_glass.py --contrast`); all reach 4.5:1 or more (2026-10-17: 4.8 on
  the dark slide, 5.3 to 12.3 on the others; Play together 10.7).
- **Layouts take turns:** the headline sits top, bottom, middle, left or right,
  and the phones move with it (flat, tilted, pushed to one side, two phones split
  around the headline on slide 5, a phone in front of a wall of pack covers on
  slide 2). The owner found "headline on top, phone below" on every slide boring.
  Slides 1-3 keep their phones flat.
- **Boards mid-build:** every board in play shows some cards locked, some loose
  and some joined (Painting mostly still grey; the giant board in 324 tiny squares
  with only a small part solved).
- **Break-out cards** lift one real part of the app out of the phone (another
  player's card in their colour and the player list, today's puzzle, the other three shapes, a loose and a locked Painting card, the giant
  board's map, your own photo, the live event, the VIP trial). A card that enlarges part of the same screen
  sits centred over that part, and every card shares its phone's frame, so it
  tilts with a tilted phone.
- **Headlines only:** 2 lines of about five words, 136 px (a slide shrinks only
  if a line would pass 1,180 px), straight on the glass (no halo or glow behind
  them; the owner found its blurred shape ugly). No subtext: it is unreadable at
  thumbnail size.
- **Headline face:** SF Pro Rounded by default (`--font display` and
  `--font newyork` render the alternatives).

Research for this set (vendor guides; treat numbers as heuristics):
- First three frames carry the listing; each must stand alone:
  https://www.mobiloud.com/blog/design-app-store-screenshots/
- Two or three layouts in one visual system, tilts of 5-15 degrees, flat phones in
  the first frames: https://appscreenshotstudio.com/blog/app-store-screenshot-layout-patterns-2026
- Panoramas: only the background crosses seams:
  https://appscreenshotstudio.com/blog/panoramic-app-store-screenshot-dimensions-slicing-2026
- Short bold captions legible at thumbnail size:
  https://trysonar.app/blog/app-store-screenshot-captions
- Apple's preview tool and creative assets (no separate dark-mode screenshots):
  https://developer.apple.com/news/?id=ljpl7kyn

## Dark gallery set (2026-10-13)

Research done 2026-10-13.

### What the research says

1. **The first three slides decide.** Without an app preview video, search
   results show the first three portrait screenshots. Only 11% of visitors
   swipe through a full portrait set (SplitMetrics, 1,800 tests). Put the core
   loop, the catalogue and the daily hook in slides 1-3.
2. **Short, big captions at the top.** Apple asks for "a short phrase that
   enhances your visual". The jigsaw leaders (Easybrain, Magic Jigsaw) use
   2-4 words at roughly 100-125 px per line on a 1320 px canvas. Short
   captions in bigger type beat long ones by about 10% (SplitMetrics,
   FreshPlanet). In search results a slide is about 114 pt wide, so a caption
   needs roughly 125-130 px type to read like 11 pt; Things-style 60 px copy
   is illegible there.
3. **Show the real game, mostly assembled.** Guideline 2.3.3 says screenshots
   "should show the app in use". Every puzzle leader shows real boards. The
   pictures are about 90% assembled, never a scrambled start, so the photo
   reads and the puzzle still shows. Every slide uses a different picture.
   The daily hook comes early ("New Jigsaw Every Day!" is Magic's slide 1),
   and the catalogue size comes early too ("Over 30,000 Puzzles", Easybrain
   slide 2).
4. **Frames, panoramas, callouts.** Jigsaw apps go full-bleed. Design-led
   apps (Things, NYT Games, Calm) use a modern frame. Panoramas are rare
   (about 4% of top games) and have no evidence of lift: each slide must
   stand alone. Zoomed-in UI callouts have a documented win (OLBG +45%).
5. **Social proof, count, theme.** Apple's asset guidance forbids
   Apple-designated recognitions (Editor's Choice, App of the Day, Design
   Award) and unverifiable claims. The store already shows the rating above
   the screenshots. Leaders use 5-10 slides, median about 7. Pure white or
   pure black backgrounds blend into the store; darker tinted backgrounds
   stand out in both light and dark mode. Apple suggests showing Dark Mode
   if the app supports it.

### Direction

A dark gallery wall where the photographs are the only colour.

- **Canvas**: one flat tone per slide, taken from that slide's photo (its
  dominant hue at low saturation and about 10% lightness). Monarch slides sit
  on a deep umber, lagoon slides on a deep teal. No gradients, no texture.
  The tint sets each thumbnail apart from the store and from the next slide
  and still reads as neutral. `--canvas neutral` switches every slide to
  one graphite tone.
- **Caption**: SF Pro Display Bold, white, centred at the top, 2-5 words,
  auto-sized between 104 and 132 px. One muted line under it (46 px) for the
  product page; it is not needed at thumbnail size.
- **App**: real captures, dark theme, inside a slim iPhone 17 Pro Max frame
  (Dynamic Island, a clean 9:41 status bar drawn in, since in-app captures
  have none). The phone is large (about 87% of the width) and runs off the
  bottom edge, so the content is big in thumbnails.
- **Story in the first three**: 1) the core loop on a nearly finished photo;
  2) the size of the catalogue as a wall of real pack covers behind the
  Library; 3) the daily picture (the month calendar with solved days).
- **Order (9 slides)**: Swap pieces. Reveal the picture. / Thousands of
  pictures / A new picture every day / Four ways to play / Puzzle your own
  photos / Fewer moves, more stars / Quests and live events / Climb the
  league / Every pack with VIP.
- **One signature slide**: the same photo cut four ways (cards, squares,
  triangles, hexagons), as four real board crops. No competitor can show
  this.
- **Your own photos**: right after the modes, My Puzzles with four real
  uploads (CC0 / public-domain pictures from our catalogue, no people) and
  the newest one, a corgi, lifted out as a board mid-game.
- **Accent**: cobalt only where the app uses it (selection and group
  outlines on the boards, the selected tab). No accent-coloured words.
- **Honesty**: every number and claim is checked against the code or the
  live catalogue (150+ library packs and about 3,700 library pictures as of
  2026-10-13; eight board sizes per mode; 7-day VIP trial). No ratings,
  awards, reviews or download counts.

### Sources

- Apple, Creating your product page: https://developer.apple.com/app-store/product-page/
- Apple, Asset best practices: https://developer.apple.com/app-store/asset-best-practices/
- App Review Guidelines 2.3.3, 2.3.4, 2.3.7: https://developer.apple.com/app-store/review/guidelines/
- Screenshot specifications: https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications
- Product page optimization: https://developer.apple.com/app-store/product-page-optimization/
- SplitMetrics, scroll depth and caption tests: https://splitmetrics.com/blog/apple-screenshots-scroll-depth/
- SplitMetrics, FreshPlanet case: https://splitmetrics.com/cases/freshplanet-optimizes-ios-screenshots/
- 2019 study of top games' screenshot sets: https://wnhub.io/news/stores-and-publishing/item-15571
- AppTweak, screenshot optimisation: https://www.apptweak.com/en/aso-blog/how-to-optimize-your-app-screenshots
- Gummicube, dark mode creative sets: https://www.gummicube.com/blog/designing-your-creative-sets-for-dark-mode
- On panoramas (claims of lift are unsupported): https://appscreenshotstudio.com/blog/panoramic-app-store-screenshots-convert-better-2026
- Competitor sets were viewed through the iTunes Lookup API
  (`https://itunes.apple.com/lookup?id=<app id>`). For some apps this returns
  an older 5.5" set.
