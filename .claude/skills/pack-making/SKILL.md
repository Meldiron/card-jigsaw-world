---
name: pack-making
description: Build, repair and audit picture packs for Card Jigsaw World (library packs, world-day event packs, daily packs, AI and Abstract categories). Use for any request to add a pack, fix a pack, replace images, source freely licensed pictures, review contact sheets, or audit the catalogue against the content rules.
---

# Pack making for Card Jigsaw World

Tooling lives in `tools/content/` (run everything through `tools/content/run.sh`; it reads
`tools/content/.local-env` for the python with Pillow/numpy and the image cache directory).
The rules are in `docs/content-rules.md`; this skill is the procedure.

## The rules you enforce (owner's words, non-negotiable)

1. Never people: no faces, bodies, crowds, hands, silhouettes, painted figures.
2. Never repeats inside a pack: same picture, near-duplicate, same scene re-shot, same
   photographer doing the same subject. Reject all but the best one.
3. Never landscape: every image is portrait or square (height >= width).
4. Never a wall of text: signs, posters, manuscript pages, documents, maps full of labels, menus.
5. Never fewer than 20 images in a pack; aim for 24 in themed packs.
6. One clear theme per pack; every image obviously belongs to it.
7. Only free licences (CC0 / PDM / public domain / CC BY / CC BY-SA / NASA); keep author,
   source and licence on every puzzle; never claim AI art is human-made.
8. Events: choose concrete image topics for the day first, then one best image per topic.

Plus the puzzle-quality rules: one clear subject, several distinct colours, detail in every
region (no big flat sky/water/wall), sharp, no borders or watermarks, >= 900 px short side.

## Sources (what to use for what)

| Need | Source | Notes |
| --- | --- | --- |
| Photos of places, animals, plants, food, objects | Wikimedia Commons search (`commons`) | Quality/Featured images first, then plain search; 1280 px renditions, CC BY-SA mostly. The main engine: no daily limit with a proper User-Agent. |
| Extra photo variety | Openverse (`openverse`) | Only 190 anonymous requests/day for the whole session, shared by all workers. Use it only for a topic Commons cannot serve. |
| Paintings, prints, textiles | Commons search with terms like `painting`, `oil on canvas`, artist names (PD-Art uploads from museums at high resolution); CMA (`cma`) as fallback (its renditions are only ~700 px wide) | Reject figures, portraits and manuscript pages. |
| Space | NASA (`nasa`) | Many NASA images are landscape; fetch more than you need. |
| AI-generated art | Commons categories (`cat:Category name` topics) under *AI-generated images by subject/artstyle/software* | Licence shows as "Public domain" (PD-algorithm) or CC; author = prompter + generator. |

## Pack spec (tools/content/specs/<packId>.json)

```json
{
 "id": "pack-owls", "name": "Owls", "category": "Animals",
 "description": "Barn, snowy, eagle and pygmy owls, mostly staring straight back at you.",
 "price": "coins", "priceCoins": 500,            // or "free" / "tickets" + priceTickets (new packs only)
 "target": 24, "per_topic": 1, "fetch_per_topic": 4, "author_cap": 2,
 "sources": ["commons"], "commons_quality": true, "openverse_category": "photograph",
 "topics": ["snowy owl portrait", "barn owl in flight", "great horned owl", "...20 to 30 of these"],
 "more_topics": ["..."],                             // used by `pool --more` when the pool runs dry
 "allow_words": ["hand"],                            // keyword-filter exceptions, rarely needed
 "accent": "#B45309", "cover": "https://...",       // optional; cover defaults to the first puzzle
 "accent_from_cover": true                           // new packs: derive accent from the cover's dominant colour
}
```

Topics are specific nouns a search engine understands ("Eibsee Zugspitze lake", not "nice
lake"). For events write 20–24 topics that are objects, dishes, plants, places or symbols of the
day. Daily packs share `specs/daily.json` (pool `daily`): generic, pleasant, varied subjects.
Category topics (`"cat:AI-generated images of nature"`) list a Commons category instead of
searching.

## Pipeline (per pack)

```
tools/content/run.sh dump                      # snapshot the live catalogue (once per session)
tools/content/run.sh audit [--pack ID ...]     # rule violations -> tools/content/reports/audit-<stamp>.md
tools/content/run.sh sheet PACK --puzzles-only # contact sheet of what is in the pack now
tools/content/run.sh reject PACK p03 p07 --reason people      # p = position on the puzzles sheet
tools/content/run.sh pool PACK                 # source candidates from the spec topics (2-3 min)
tools/content/run.sh sheet PACK --candidates-only
tools/content/run.sh reject PACK c12 c15 --reason off-theme   # c = candidate key
tools/content/run.sh apply PACK --pick c02 c05 ... [--no-auto] [--target 24] [--dry]
tools/content/run.sh sheet PACK --puzzles-only # final check: read it again
tools/content/run.sh newpack PACK              # create the pack row for a new spec (before pool/apply)
tools/content/run.sh status PACK ...           # counts, pool size, openverse budget
```

Reject reasons: `people`, `text`, `landscape`, `duplicate`, `quality` (global: the image is never
used again anywhere) and `off-theme`, `weak`, `similar` (scoped to this pack only).

`apply` deletes rejected puzzles, adds explicit picks first, then auto-fills round-robin over
topics until `target`, skipping near-duplicates of kept images, authors over `author_cap`,
landscape and small images. For daily packs (`daily-YYYY-MM`) it replaces rejected puzzles in
place (same id, date, order). It syncs `imageCount`, cover, blurhash, accent and the event cover.

## Visual review (you are the last filter)

Read every contact sheet you produce. Look at each cell and reject:

- any person, even tiny or from behind, hands, reflections of people, painted figures;
- text-dominated images; borders; watermarks; collages; screenshots; black-and-white;
- the same scene twice (watch the author under each thumbnail: same author + same subject = same scene);
- anything that does not obviously match the pack name; images where the subject is a speck;
- flat images (half sky, half water, blurred backgrounds dominate), dark/underexposed images.

Prefer explicit `--pick` lists over auto-fill for anything the owner will see first (covers,
event packs). After `apply`, read the final puzzles sheet; the job is not done until that sheet is
clean and the count is >= 20.

## Batching etiquette

- Workers share Commons, Appwrite and the state files; keep one pack at a time per worker and do
  not run `dump` while others are writing (use `status`/`sheet`, which refresh one pack).
- Log every pack you finish in `tools/content/reports/<batch>.md`: id, removed (with reasons),
  added, final count, anything unresolved. `reports/changes.jsonl` is written automatically.
- Never touch `lib/`, `ios/`, other tools, git. Only `tools/content/**` and the database.

## Re-theming a pack

If a pack cannot satisfy the rules under its current theme (e.g. "Portraits" needs people,
"Medieval Manuscripts" is text, "Vintage Posters" is text), rewrite its spec with a new name and
description that keeps the pack id, note it in the batch report, and rebuild the content.

## New categories

AI packs: Commons categories of AI-generated images (nature, animals, architecture, food,
abstract art, fantasy, science fiction, paintings, pixel art, woodcuts, line drawings, textures,
Moon, objects, geometric shapes, clothing, beverages, utopias, dystopias, paleoart). Author is
"<prompter> / <generator>", source "Wikimedia Commons, Public domain (AI-generated)".
Abstract packs: fluid ink, geometric minimal, light leaks, macro textures, kaleidoscope, bokeh,
smoke, topographic, paper collage, brutalist concrete, stained glass, neon lines, marbling,
fractals, crystal macro, glitch, dunes, water ripples, frost, rust. Search Commons with the
material/phenomenon words ("ink in water macro", "fractal flame", "paper marbling", "hoarfrost
macro") and reject anything representational.
