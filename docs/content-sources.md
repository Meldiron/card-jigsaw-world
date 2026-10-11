# Content sources and licences

All catalog images are hotlinked from sources whose terms allow it. Each puzzle row stores
`author` and `source` so the difficulty and completion screens can credit the work.

| Pack type | Sources | Licence | Notes |
|---|---|---|---|
| Featured photo packs (Wild Nature, Animal Friends, …) | Lorem Picsum (Unsplash photos) | Unsplash License | `picsum.photos/id/{id}/900/1200` |
| Masterpieces, daily-pack art, art library packs | Cleveland Museum of Art Open Access API | CC0 | `openaccess-cdn.clevelandart.org` web renditions, paintings/prints/drawings/textiles only |
| Deep Space and space library packs | NASA Image and Video Library | Public domain, credit NASA | `~medium.jpg` renditions, `~orig.jpg` where medium is unavailable |
| Library photo packs (`pack-*`) and event packs (`evpack-*`) | Openverse search (Flickr, rawpixel, StockSnap, iNaturalist hosts) | CC0, Public Domain Mark, CC BY, CC BY-SA only | `license_type=commercial`, photographs, tall aspect, width ≥ 700; creator and licence stored in `source` |
| Fallback | Lorem Picsum | Unsplash License | used to top up 11 packs that fell short of the minimum |

Counts after the October 2026 content drop: 97 world-day events with one event pack each
(10–14 puzzles), 112 library packs (12–20 puzzles), 46 monthly daily packs (1,400 puzzles),
8 original featured packs. Every image URL was validated with an HTTP request before seeding.

Seed files: `docs/seed-catalog.json`, `docs/seed-daily-packs.json`, `docs/seed-events.json`, `docs/seed-packs-2.json`.
