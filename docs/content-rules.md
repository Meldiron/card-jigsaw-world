# Content rules for picture packs

These rules come from the owner's TestFlight feedback (October 2026) and from what works in a
card-swapping jigsaw. Every pack in the catalogue must satisfy them; `tools/content/run.sh audit`
reports the ones that do not. The pack-making workflow that enforces them is the
`pack-making` skill (`.claude/skills/pack-making/SKILL.md`).

## Hard rules (a pack that breaks one is broken)

1. **No people.** No faces, bodies, crowds, silhouettes, hands, or figures in paintings. Statues
   and dolls are tolerated only when they are clearly objects; when in doubt, reject.
   **Giant packs** (category `Giant`, owner 2026-10-14) may keep small incidental figures: a distant
   person, a figurine on a shelf, a finial, a relief on a vase, as long as each covers only a small part
   of the picture (about 2% of the frame at most, some 6 cards of a 300-card board), is never the subject,
   never in the foreground and never the focus (the owner's example of what must go: "a guy sitting on a
   bench"). A recognisable face, a vendor at the stall, a person you notice first: reject. Normal packs
   keep the strict rule.
2. **No repeats.** Within a pack no two images may be the same picture, a near-duplicate, the same
   scene from a slightly different angle, or the same photographer shooting the same subject the same
   way. The tools flag perceptual-hash matches; the reviewer rejects the rest by eye.
3. **Portrait or square only.** `height >= width` for every image. Landscape images are never
   cropped on the fly; they are rejected.
4. **No walls of text.** No signs, posters, manuscript pages, documents, maps dominated by labels,
   book pages, newspapers, menus, stamps, banknotes. A small inscription inside a scene is fine.
5. **At least 20 images per pack.** Themed packs aim for 24. Daily packs keep exactly one puzzle
   per calendar day.
6. **One coherent theme.** The pack name promises something specific and every picture visibly
   delivers it ("Alpine Lakes" = a lake with mountains in every frame, never a hut or a slope).
7. **Free licences only, credited.** CC0, Public Domain / PDM, CC BY, CC BY-SA, NASA public domain,
   Unsplash licence via Picsum. Never NC or ND. Every puzzle row stores `author` and `source`
   (which names the licence); `tools/content/state/provenance.json` keeps the source page per
   puzzle. AI-generated images are stored with their generator and prompter and are never
   presented as human-made.

   **Stock-site licences need the owner's review first.** The Pexels License, Pixabay Content
   License, Unsplash License (new API sources, not the legacy Picsum packs) and Flickr Commons' "no
   known copyright restrictions" are not CC licences, and the free Flickr API key is non-commercial.
   The tool keeps `pexels`, `pixabay`, `unsplash`, `flickr` and `flickr-commons` inactive until their
   key is in `secrets/content-keys.env`, and drops their licences unless a spec lists them in
   `allow_licences`. No pack may use these sources or set `allow_licences` until the owner has
   reviewed and approved that licence (and, for Pixabay, a re-hosting plan: Pixabay forbids
   permanent hotlinking).

8. **No space.** No new packs or pictures of nebulae, galaxies, planets, star fields or telescope
   images (owner, 2026-10-14: "I don't like space ones"). The existing Space packs stay as they are; no
   source is used for space pictures (ESA/Hubble, ESA/Webb and ESO were evaluated and excluded). Earth
   seen from orbit or from the air (USGS Earth as Art, NASA Earth Observatory) is not space and is fine.

## Quality rules (what makes a picture a good puzzle)

- **Clear subject**: one obvious thing to look at, in focus, filling a good part of the frame.
- **Colour variety**: several distinct colour regions so cards can be sorted by colour; avoid
  monochrome or one-tone images and black-and-white photos.
- **No line drawings or sketches**: faint ink or pencil lines on plain paper, prints with large blank
  areas, and pale single-tone artworks are near impossible to solve (owner feedback 2026-10-12, a
  Cleveland ink drawing on beige paper). Reject them as `quality` even when the subject fits.
- **Detail everywhere**: texture or edges in every region. Reject images where more than about half
  of the frame is flat sky, water, wall or bokeh (the tools compute a `flat` score; above 0.55 is
  rejected automatically).
- **Not chaotic**: a dense market is fine, visual noise with no structure is not.
- **Resolution**: new images need at least 900 px on the short side (hard floor 640 px for legacy
  rows); Commons images are hotlinked as 1280 px renditions.
- **No borders, frames, watermarks, captions** inside the image.

## Events (world days)

Pick 20–24 concrete **topics** for the day first (World Food Day: "bowl of ramen", "fresh bread
loaf", "spice market stall", ...), then find one best picture per topic. Never search the event
name itself. Days that are about people (Women's Day, Families, Dance, Teachers, Friendship,
Youth, Children's Day, Mother's/Father's Day, Grandparents, Yoga, Volunteers, Kindness, Smile Day,
Peace) are themed through objects, places and symbols associated with the day, never through
people.

## Categories

Library categories: Nature, Animals, Flowers, Oceans, Cities, Travel, Architecture, Food, Space,
Art, Patterns, Vintage, Mountains, plus **AI** (AI-generated art, 20 themed packs) and
**Abstract** (20 distinct abstract themes). Event packs use category `Event`, monthly daily packs
use `Daily`.

## Prices

Keep prices consistent with neighbours in the same category: free starter packs (`isFree`),
coin packs 300–900 coins, ticket packs 2–4 tickets for premium subjects. New AI and Abstract packs
follow the same spread (about a third free, most 400–800 coins, one or two ticket packs).


## Hosting (owner rule, 2026-10-13)

The app never loads a picture from a third party. Every picture and cover is downloaded once, normalised
to a JPEG of at most 1200 px wide (quality 86) and stored in the Appwrite Storage bucket `puzzle-images`
under an id derived from its source URL. Rows point at our endpoints: `imageUrl` = `/view`, `thumbUrl` =
`/preview?width=600&quality=80`, pack and event `coverUrl` = `/preview?width=1080&quality=82`. The source
address stays in `sourceUrl` / `coverSourceUrl` for attribution, rejects and duplicate checks.
`tools/content/cli.py apply` hosts its picks itself; `cli.py host [--pack ID]` migrates anything left
(idempotent; `reports/host-failures.json` lists sources that could not be fetched).

## Giant packs

Packs in category `Giant` are played on boards of about 100 to 300 cards, so on top of every rule above
their pictures must be huge (about 4000 px on the long side), sharp at 100%, and carry detail and colour
in every card: at a 300-card cut at most 22% near-uniform cards, 15% nearly black cards and 30% cards that
look like 8 or more others. Large skies, plain walls, dark painted backgrounds, mirror reflections and
repeating or symmetric patterns fail. They are hosted at up to 4096 px (`host_max_px`). The procedure,
sources and checks (`tools/content/run.sh giantcheck`) are in the `giant-packs` skill
(`.claude/skills/giant-packs/SKILL.md`).
