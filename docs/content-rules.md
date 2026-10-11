# Content rules for picture packs

These rules come from the owner's TestFlight feedback (October 2026) and from what works in a
card-swapping jigsaw. Every pack in the catalogue must satisfy them; `tools/content/run.sh audit`
reports the ones that do not. The pack-making workflow that enforces them is the
`pack-making` skill (`.claude/skills/pack-making/SKILL.md`).

## Hard rules (a pack that breaks one is broken)

1. **No people.** No faces, bodies, crowds, silhouettes, hands, or figures in paintings. Statues
   and dolls are tolerated only when they are clearly objects; when in doubt, reject.
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

## Quality rules (what makes a picture a good puzzle)

- **Clear subject**: one obvious thing to look at, in focus, filling a good part of the frame.
- **Colour variety**: several distinct colour regions so cards can be sorted by colour; avoid
  monochrome or one-tone images and black-and-white photos.
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
