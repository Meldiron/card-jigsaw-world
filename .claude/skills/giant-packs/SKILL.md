---
name: giant-packs
description: Build, extend, repair and audit Giant packs for Card Jigsaw World (category Giant, boards of about 100 to 300 cards). Use for any request to add a giant pack, add or replace pictures in one, source very large and highly detailed pictures, or check that a picture is good enough for a 300-card board.
---

# Giant packs for Card Jigsaw World

A Giant pack is a library pack in category **`Giant`** (exactly that string: the app offers its giant
board ladder, about 100 to 300 cards, only for this category). Each picture is cut into up to ~300 cards
of about 200 px of a 4096 px hosted copy, so it has to be huge, sharp at 100% and full of detail and
colour that tell the cards apart. Everything in the `pack-making` skill and `docs/content-rules.md`
still applies (no people, no repeats, portrait or square only, no walls of text, at least 20 pictures,
one theme, free licences with author and source). This skill adds the giant rules, the tooling and
the lessons from the first giant pack, `pack-colourful-houses` (Colourful Houses, 24 pictures,
2026-10-14).

## Giant rules (on top of the content rules)

1. **Huge source**: at least ~4000 px on the long side (`GIANT_MIN_LONG` 3800, because Commons' largest
   standard rendition is 3840 px wide). Portrait or square, as always.
2. **Sharp at 100%**: `sharp` >= 1.8 (a sharp museum scan scores ~2.8, the same scan upscaled 3x 0.98,
   good photos 3 to 11). Always read the 100% crop sheet as well: soft focus, motion blur, heavy noise
   reduction, JPEG blocks and HDR halos show there and nowhere else.
3. **Every card must be tellable**: measured at a 300-card cut,
   - `flat` <= 22%: cards that are almost uniform (sky, plain painted wall, water, studio backdrop);
   - `dark` <= 15%: nearly black cards (shadows, night, dark varnish);
   - `alike` <= 30%: cards whose colour and texture match 8 or more others (repeating patterns,
     symmetric designs, foliage, backgrounds).
   These limits are in `tools/content/cjw/giant.py`; they were calibrated on Colourful Houses. Do not
   loosen them for one picture; loosen them only with a reason that holds for the whole category, and
   note it in the module.
4. **No large plain or repeating areas**: no big skies, plain walls, dark or olive painted backgrounds,
   mirror-like water reflections (they double the look-alike cards), tiled or symmetric patterns
   (rose windows, mosaics, carpets), rows of identical windows.
5. **People, looked for at full size**: 4096 px shows what a 480 px thumbnail hides. Giant packs may
   keep small incidental figures (owner, 2026-10-14): a distant passer-by, a figurine or finial on a
   shelf, a relief on a vase, a cherub on a teapot lid, a tiny statue on a roof, as long as each covers
   about 2% of the frame at most (some 6 cards of 300), is never the subject, never in the foreground and
   never the focus. Reject a person you notice first: someone sitting or standing as the focus (the
   owner's example: "a guy sitting on a bench"), a vendor at the stall, a recognisable face, a large
   statue, bust or mural figure, a mannequin in a window, several figures together. Use the review sheets
   (below) for every pick.
6. **No space** (owner, 2026-10-14): no nebulae, galaxies, planets or star fields, however detailed
   (ESA/Hubble, ESA/Webb and ESO were sampled and excluded). Earth seen from orbit or the air is fine.

## The target: hidden-object art (owner's reference, 2026-10-14)

The owner's model of a perfect giant picture is hidden-object game art, for example "Hidden Object
Adventure" by Cú Xanh (Behance, **© All Rights Reserved: a reference only, never in the catalogue**; the
owner's local copies stay out of the repo). Its seven 3840 x 5973 px scenes measure, with `giantcheck` at
4096 px and 300 cards: **sharp 8.6-12.7, flat 0-0.7%, dark 0%, alike 0-7%**. The real photos that passed
for Colourful Houses measure sharp 4.0 (median), flat 7% (p90 17%), dark 1%, alike 15% (p90 29%). The
limits above are the floor, not the goal: rank a shortlist towards the reference, prefer **flat <= 8% and
alike <= 15%**, and take a picture near a limit only when nothing better is left.

What makes that art work, and how to find the same in real pictures:

1. **No horizon, no sky.** A bird's-eye or three-quarter view from above: the whole frame is ground
   covered with things. In photos: looking down onto a stall, a table, a shelf wall, a square seen from a
   tower. More than a strip of sky costs the picture.
2. **An object in every card.** Something you can name every 200-300 px of the 4K picture (a card at the
   300-card cut is about 200 px), big landmarks and small props mixed. In photos: goods fill the frame edge
   to edge, at a distance where each object spans a few cards (too close: one object over 40 cards; too
   far: mush).
3. **Every object once.** Nothing repeats, which keeps `alike` near zero. Rows of identical jars, bricks,
   windows, tiles or leaves are the enemy; mixed assortments (a junk shop, a spice stall with twenty
   spices, a mixed fruit stall) are the friend.
4. **Even the "empty" ground carries marks.** Paths have tiles, sand has spots, grass has tufts, everything
   has an outline. In photos: textured surfaces (cobbles, wood grain, baskets, worn paint) instead of
   smooth walls, plain cloth, sky or still water.
5. **Each area its own palette.** A farm, a pond, an orchard and a market side by side, so a card says
   where it belongs (and each zone of a giant board gets a look of its own). Prefer scenes with several
   distinct colour areas over one colour everywhere (an all-red façade, all-green foliage).
6. **Bright, even light.** No deep shadows and no black (`dark` 0%); its night scenes are saturated blues
   and purples, not black. In photos: daylight or well-lit interiors; dim shops and backlit windows fail.
7. **Tall portrait.** The reference is 2:3 (0.64), which suits the phone board.

Real-world themes with these traits, still to try: market stalls and shop displays seen slightly from
above; antique, junk and toy shops; flea-market tables from above; model villages and miniature parks
(Madurodam, Miniatur Wunderland, Mini-Europe) from above, but their tiny figurines are figures, so any
visible figure rejects the picture; top-down drone views of harbours full of small boats, rows of beach
huts, flower markets (no visible people); crazy quilts and patchwork (Met and Smithsonian open access,
CC0: every patch a different fabric; reject figurative embroidery); illustrated bird's-eye panoramas only
when portrait and without large labels (most are landscape and labelled).

## What works, what does not (first pack, measured)

| Theme | Result | Why |
| --- | --- | --- |
| Dutch and Flemish flower still lifes (museum scans 5000-16000 px) | fails | Dark or olive backgrounds: 45-80% look-alike cards at 300 cards; only 1 of 25 passed |
| Autumn forests | weak | Foliage looks alike everywhere (30-60% alike) |
| Flower gardens and borders | mixed | Good close shots, but sky and lawns creep in |
| Coral reefs | weak | Few portrait originals, chaotic, blue water backgrounds |
| Colourful houses (facade fills the frame) | works | Every house its own colour, windows, shutters and balconies make cards distinct |
| Painted Paradises: crowded old masters, tapestries, bird parks (Savery, Hondecoeter, verdures, millefleurs, palampores) | fails | 59-96% look-alike, dark varnish; Jakuchū scans top out at 2695 px (2026-10-14) |
| Painted Paradises: colour painting 1880-1920 (Caillebotte, Sorolla, Marc, Klee, Séraphine, Van Gogh gardens) | works | Brushwork everywhere and strong colour: 17 of 20 picks at flat <= 8%, alike <= 15%; find them with targeted `intitle:` Commons topics after a 500 px prescreen |
| Curiosity shops, flea markets, cabinets (photos) | weak | Figurines everywhere (strict rule) and dim interiors behind glass; 4 of about 340 passed before the giant people rule was relaxed and the Commons size fix landed |
| Quilts (museum scans) | weak | Grey backdrops, colour strips, borders; one very low-alike Cleveland quilt |

Good topic shapes are named streets, squares, shophouses, balconies and single houses ("Calle Santiago
Hondarribia", "Joo Chiat shophouses", "Largo Santa Luzia Alfama"), not "colourful town" panoramas,
which bring sky, cars and crowds. Expect about 1 usable giant picture per 6 to 8 candidates.

## Sources with huge originals

| Provider | How to get full size | Notes |
| --- | --- | --- |
| `commons` | `commons_width: 3840`, `commons_extra: "fileh:>3800"` | Main source. Quality images rank first. 3840 is the largest standard rendition (Commons rejects other widths). |
| `nga` | `source_box: 4096` (IIIF `!4096,4096`) | Serves up to 4096 px; images capped by `maxpixels` are skipped automatically. |
| `rijks` | `source_box: 4096` | Micrio caps at about 17.5 MP (2915 x 4096 fits). |
| `met` | nothing: the candidate URL is the original | Originals 3000-6000 px. The v1.1 search returned HTTP 404 on 2026-10-14: check `run.sh sources met` first. |
| `nasa` | originals | No space pictures (owner). Earth from orbit can work. |
| USGS Earth as Art (not a provider yet) | S3 "Original" per media page | About 7200 px square Landsat art, public domain; the best giant source sampled (flat 0, alike 0) but every file is a poster: crop the inner square (no logos). See the pack-making skill's approved sources. |
| Negative Space, NPS NPGallery (not providers yet) | originals | Top-down flat-lays (Negative Space) and geology textures (NPS staff photos) can pass; mostly normal-pack material. |
| `inat`, `cma` | too small | 2048 px and ~900 px. |

The pool fetches the candidates with the largest known originals first. Museum results have no size
until downloaded, so in a mixed spec Commons fills every `fetch_per_topic` slot: pool museum sources in
a spec of their own (or raise `fetch_per_topic`).

## Spec (tools/content/specs/<packId>.json)

```json
{
 "id": "pack-colourful-houses", "name": "Colourful Houses", "category": "Giant",
 "description": "Painted façades, shutters and flower boxes from Burano to Valparaíso, sharp enough for boards of 300 cards.",
 "price": "tickets", "priceTickets": 4, "premium": true,     // 4 = the old scale's top tier -> 12 tickets
 "sortOrder": 1250, "accent_from_cover": true, "cover": "<source URL of the cover pick>",
 "sources": ["commons"], "commons_quality": true, "commons_width": 3840, "commons_extra": "fileh:>3800",
 "source_box": 4096,                                          // nga / rijks renditions
 "host_max_px": 4096,                                         // hosting keeps 4096 px (long side)
 "min_short": 2800, "target": 24, "per_topic": 1, "fetch_per_topic": 3, "author_cap": 2,
 "topics": ["Burano houses", "Calle Santiago Hondarribia", "..."], "more_topics": ["..."]
}
```

## Pipeline

```
tools/content/run.sh pool PACK                       # 3-4 min per 30 topics; several hundred MB
tools/content/run.sh sheet PACK --candidates-only    # read it; reject people/text/quality/weak
tools/content/run.sh reject PACK c04 c10 --reason quality
tools/content/run.sh giantcheck PACK --candidates-only --thumbs     # rough prescreen, no downloads
tools/content/run.sh giantcheck PACK --candidates-only --keys c01 c02 ...   # full check + 100% crops
tools/content/run.sh giantcheck PACK --candidates-only --review --keys ...  # 2x2 sheets for the people check
tools/content/run.sh pool PACK --more                # new more_topics when the shortlist is short
tools/content/run.sh newpack PACK
tools/content/run.sh apply PACK --no-auto --pick c211 c01 ...       # explicit picks only, cover first
tools/content/run.sh retitle PUZZLE_ID Exact place, Town          # every picture (see Titles)
tools/content/run.sh finalize PACK                   # bumps puzzlesUpdatedAt after the retitles
.venv/bin/python tools/store/apply_pack_prices.py --only PACK       # dry run, then --apply
tools/content/run.sh verify PACK
tools/content/run.sh giantcheck PACK --puzzles-only  # every puzzle passes
tools/content/run.sh sheet PACK --puzzles-only       # final read: clean, >= 20
```

Crop and review sheets land in `<cache>/sheets/giant/<pack>/`. Keep the pool's two download workers:
giant renditions are 3-8 MB each and the owner's line saturates.

## Hosting

`"host_max_px": 4096` makes `apply` (and `host --pack`, `clone`) store each picture as a JPEG of at most
4096 px on the long side, quality 90 (about 1.7 to 3.8 MB), instead of the normal 1200 px. The giant copy
has its own file id and `state/hosted.json` key (`<source URL>|4096px`), so a picture hosted at 1200 px
for another pack is never reused at the wrong size. Thumbs (`/preview?width=600`) and covers
(`/preview?width=1080`) are unchanged. If `secrets/appwrite-storage-key.txt` is missing, `host.py` falls
back to `secrets/appwrite-users-key.txt` (files scopes too) and says so in the log.

## Titles

Commons pictures are titled from their search topic, and a giant topic is usually a place that the
search only approximately hit (the "Lisbon tiled facade" topic returned a square in Salvador). Retitle
every picture with its exact place, in the catalogue's plain style ("Calle Tibaldon, Burano", "Wharf
houses on the Nidelva, Trondheim"); check the file's Commons categories when the file name is vague.

## Review checklist (before `apply`, and again on the final sheet)

- [ ] category is exactly `Giant`, `host_max_px` 4096, at least 20 pictures (aim 24)
- [ ] every pick passes `giantcheck` (long side, sharp, flat, dark, alike) and its crop sheet looks sharp
- [ ] review sheets read for people, reflections, statues, faces, framed images, murals
- [ ] no wall of text; small shop signs and house numbers are fine
- [ ] author cap 2, and no photographer twice on the same subject; one place at most 3 times
- [ ] colour and composition vary across the pack (not 24 times the same street angle)
- [ ] titles name the exact place; cover is the strongest picture
- [ ] price applied (12 tickets for the top ticket tier), `puzzlesUpdatedAt` set, `verify` clean
