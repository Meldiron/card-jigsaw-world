# Batch D1: daily packs 2023-01 .. 2024-12

Worker D1. Shared pool specs: `tools/content/specs/daily-2023.json` and `daily-2024.json` (different topic lists,
~115 topics plus `more_topics` each; Commons only, per_topic 2, fetch_per_topic 6, author_cap 3).

Note on the spec format: the brief asked for `"id": "daily-2023"` inside the year spec, but `specs.load` keeps a
file `id` verbatim and `writer.apply` then looks up a pack row with that id, so `apply daily-2023-01` would stop with
"pack daily-2023 does not exist". The `id` field is therefore omitted; the pool name comes from the file stem.

## Pools

The first `run.sh pool daily-2023` run lost 106 of its first 129 fetched candidates to HTTP 429 from
upload.wikimedia.org (Commons throttles per User-Agent; all workers' pools share the tool's UA, so parallel
pools push the shared bucket over the limit) and the CLI cached each 429 as a permanent "bad" candidate.
Reported; the tooling agent fixed `cjw/imagecache.fetch` (pacing, Retry-After, 429 never cached as permanent)
and added `run.sh recover <pool>`. Interim scratchpad workaround scripts (a sequential fetcher that, wrongly,
sent a worker-specific UA containing the owner's email address; 23 topics were fetched through it) were deleted
on the tooling agent's request; everything from topic 24 on uses `run.sh pool` / `run.sh recover`.

## Review pass (all 24 month sheets read; rejections recorded before any apply)

| month | people | landscape | text | weak | similar | rejected | kept |
| --- | --- | --- | --- | --- | --- | --- | --- |
| daily-2023-01 | 11 | 7 | 0 | 4 | 0 | 22 | 9 |
| daily-2023-02 | 12 | 1 | 1 | 3 | 0 | 17 | 11 |
| daily-2023-03 | 14 | 6 | 3 | 3 | 0 | 26 | 5 |
| daily-2023-04 | 11 | 6 | 1 | 6 | 0 | 24 | 6 |
| daily-2023-05 | 9 | 5 | 0 | 9 | 0 | 23 | 8 |
| daily-2023-06 | 9 | 3 | 0 | 6 | 0 | 18 | 12 |
| daily-2023-07 | 13 | 5 | 2 | 5 | 0 | 25 | 6 |
| daily-2023-08 | 12 | 6 | 1 | 4 | 0 | 23 | 8 |
| daily-2023-09 | 14 | 2 | 3 | 5 | 0 | 24 | 6 |
| daily-2023-10 | 13 | 5 | 2 | 3 | 0 | 23 | 8 |
| daily-2023-11 | 14 | 3 | 1 | 5 | 0 | 23 | 7 |
| daily-2023-12 | 11 | 4 | 0 | 7 | 0 | 22 | 9 |
| daily-2024-01 | 12 | 3 | 0 | 5 | 0 | 20 | 11 |
| daily-2024-02 | 10 | 5 | 0 | 4 | 1 | 20 | 9 |
| daily-2024-03 | 16 | 2 | 3 | 6 | 0 | 27 | 4 |
| daily-2024-04 | 14 | 2 | 0 | 7 | 0 | 23 | 7 |
| daily-2024-05 | 11 | 3 | 2 | 3 | 0 | 19 | 12 |
| daily-2024-06 | 11 | 4 | 1 | 3 | 0 | 19 | 11 |
| daily-2024-07 | 18 | 1 | 0 | 4 | 0 | 23 | 8 |
| daily-2024-08 | 13 | 6 | 2 | 2 | 0 | 23 | 8 |
| daily-2024-09 | 14 | 4 | 3 | 4 | 0 | 25 | 5 |
| daily-2024-10 | 17 | 3 | 0 | 6 | 0 | 26 | 5 |
| daily-2024-11 | 19 | 0 | 1 | 5 | 0 | 25 | 5 |
| daily-2024-12 | 14 | 4 | 2 | 3 | 0 | 23 | 8 |

"people" includes painted figures, hands, feet, silhouettes and tiny figures in scenes; "weak" covers flat
sky/sea frames, monochrome ink sketches, dark interiors, laptops/desks and bokeh-only frames. Landscape
paintings that also had figures were logged as people (global reject) rather than landscape.

## Apply pass

Shared pool: `daily-2024.json` now sets `"pool": "daily-2023"`, so every daily year draws from one pool and the
pool's `used` status keeps pictures unique across months. Pool review before applying: 667 candidates, 602 usable;
8 already used elsewhere in the catalogue (similar), 329 rejected on the sheets (people 48, text 14, quality 45,
weak 135, similar 87), leaving 265. Top-ups after the first apply use explicit `--pick` from topics not yet in the
month (auto-fill's round-robin ignores the topics of kept puzzles and repeated a month's subjects).

- daily-2023-01: replaced 22 in place (people 11, landscape 7, weak 4) + 3 weak kept ones (flat lake, hazy valley, dark painting); 31/31 dates; verified. Exact dup of its 01-27 lake in daily-2025-07 (01) is removed on the 2025 side.
- daily-2023-02: replaced 17 (people 12, landscape 1, text 1, weak 3) + 5 weak kept ones (rain-on-glass bokeh, pale harbour painting, traffic glare, half mist, two-tone bridge underside); 28/28 dates; verified.
- daily-2023-03: replaced 26 (people 14, landscape 6, text 3, weak 3) + 3 weak kept ones (bokeh cactus macro, half cloud, half flat sea); 31/31 dates; verified.
- daily-2023-04: replaced 24 (people 11, landscape 6, text 1, weak 6) + 3 weak kept ones (hazy boulders, Ferris wheel on flat sky, foggy railway); 30/30 dates; verified.
- daily-2023-05: replaced 23 (people 9, landscape 5, weak 9) + 5 kept ones (weak 4: half cloud, sepia pier on flat sky, faded railway, half flat sky; people 1: mandala painting with figures); 31/31 dates; verified.
- daily-2023-06: replaced 18 (people 9, landscape 3, weak 6) + 5 kept ones (people 2: figure by parked cars, ground crew by an aircraft tug; weak 3: flat sea aerial, flat beige painting background, half sky); 30/30 dates; verified.
- daily-2023-07: replaced 25 (people 13, landscape 5, text 2, weak 5) + 5 kept ones (weak 4: flat haze/sunset frames; people 1: London street with pedestrians); 31/31 dates; verified.
- daily-2023-08: replaced 23 (people 12, landscape 6, text 1, weak 4) + 6 kept ones (weak 5: flat sunset sea, fog bridge, road on flat sky, jellyfish in plain blue, cable cars in fog; similar 1: fireworks also in evpack-new-years-eve-2026); 31/31 dates; verified.
- daily-2023-09: replaced 24 (people 14, landscape 2, text 3, weak 5) + 5 weak kept ones (town under pale sky, hazy beach, single-tone canopy, typewriter on flat boards, grey misty rooftops); 30/30 dates; verified.
- daily-2023-10: replaced 23 (people 13, landscape 5, text 2, weak 3) + 12 more (weak 6: hazy valley, swings, orange haze, grass bokeh, horses under flat sky, stave church over graves; similar 6: second Jupiter, second fiddlehead, three extra waterfalls); 31/31 dates; verified.

## Resume (2026-10-12, after pause)

Pool grown with unpooled `daily-2024` topics (spec `sources` now `["commons", "openverse"]`, Openverse asks for tall/square only); `recover daily-2023` re-fetched 21 of 26 throttled candidates. Before each apply the remaining candidates are checked against the live catalogue (exact URL, same Commons file, perceptual hash) with a read-only scratchpad script; hits (so far only images D2 already placed in daily-2025) are rejected as `similar` for the month, which keeps the other pack's row untouched.

- daily-2023-11: replaced 24 in place (people 14, landscape 3, text 1, weak 6, from the review pass); 26 candidates rejected from the pool (people 5, quality 1, weak 18, similar 2) + 2 already in daily-2025; 30/30 dates; verified.
- daily-2023-12: replaced 24 in place (people 11, landscape 4, weak 9: review-pass reasons incl. flat sky gradient and flat underwater frame); pool candidates rejected: people 1, text 2, quality 1, weak 14, similar 1; 31/31 dates; verified.
- daily-2024-01: replaced 28 in place (people 13: review pass 12 + horse-cart painting; landscape 3; weak 5; quality 1: chestnut photo with corner watermark; plus the review pass's 6 others); pool candidates rejected: quality 4 (3 unlabelled AI-looking bison renders, 1 black-and-white), text 1, weak 17 (2 of them URLs over the 512-char column), similar 2; 31/31 dates; verified.

Pool growth note: Commons downloads were taking ~20-30 s each (429 back-off with ~10 workers pooling), so the shared pool was extended with iNaturalist species topics (50 species, `sources: ["inat"]`), NASA space topics and Openverse food/pattern/vehicle topics (spec `sources` switched per phase). A strict pass over the 423 usable candidates rejected roughly 60% (hands holding animals, snapshot-grade iNat frames, AI renders without a label, watermarks, captions, mosaics with figures).

- daily-2024-02: replaced 23 in place (review-pass reasons: people 10, landscape 5, weak 4, similar 1, plus 3 more); pool candidates rejected during this month's review: people 27, text 13, quality 18, weak 233, similar 13 (shared pool, covers later months too); 29/29 dates; verified.
- daily-2024-03: replaced 29 in place (review pass: people 16, landscape 2, text 3, weak 6, plus 1 more; weak 1 added now: faded Shitao landscape); 31/31 dates; verified.
- daily-2024-04: replaced 25 in place (review pass: people 14, landscape 2, weak 7, plus 2 more); 30/30 dates; verified.
- daily-2024-05: replaced 26 in place (review pass: people 11, landscape 3, text 2, weak 3, plus 6 more; quality 1: kept Cropsey painting was 630x893, under the 640 px floor); 31/31 dates; verified.
