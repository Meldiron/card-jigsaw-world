# Content sources and licences

All catalogue images are hotlinked from sources whose terms allow it. Each puzzle row stores
`author` and `source` (the source string names the licence) so the difficulty and completion
screens can credit the work. `tools/content/state/provenance.json` keeps the source page, licence
and provider for every puzzle added by the content pipeline; `tools/content/reports/changes.jsonl`
is the append-only log of every create / delete / replace.

The rules every image must satisfy are in `docs/content-rules.md`; the workflow is the
`pack-making` skill (`.claude/skills/pack-making/SKILL.md`) and the CLI in `tools/content/`.

| Pack type | Sources | Licence | Notes |
|---|---|---|---|
| Library photo packs, event packs, daily packs (October 2026 repair onwards) | Wikimedia Commons search and categories (`upload.wikimedia.org` 1280 px renditions, 960 px thumbs) | CC0, Public domain, CC BY, CC BY-SA (NC/ND rejected) | Quality / Featured / Valued images first; `deepcategory:` trees such as "Quality images of food". Only the fixed thumbnail widths 960 / 1280 are served to anonymous clients. |
| AI category | Wikimedia Commons categories of AI-generated images (by generator and by subject) | Public domain (`PD-algorithm`: no human authorship) or CC as tagged | Author stored as `<prompter or uploader> / <generator>`, source marked `(AI-generated)`; never presented as human-made. |
| Abstract category | Wikimedia Commons (macro, texture, aerial and render photos), NASA Earth Observatory for topographic packs | as above / NASA public domain | |
| Original featured packs (Wild Nature, Animal Friends, Cozy Kitchen, City Lights) | Lorem Picsum (Unsplash photos) | Unsplash License | `picsum.photos/id/{id}/900/1200`; violating pictures replaced from Commons |
| Legacy art packs | Cleveland Museum of Art Open Access API | CC0 | `web` renditions are at most 900 px on the long side; landscape ones were removed, new art comes from Commons PD-Art museum uploads |
| Space packs | NASA Image and Video Library, Hubble/Webb/ESO uploads on Commons | Public domain, credit NASA / CC BY (ESO, ESA) | `~medium.jpg` renditions, `~orig.jpg` where medium is unavailable |
| Legacy library and event packs (October 2026 drop) | Openverse search (Flickr, rawpixel, StockSnap, iNaturalist hosts) | CC0, PDM, CC BY, CC BY-SA only | Anonymous Openverse allows 200 requests per day, so it is only a reserve source now |

Counts are maintained in the audit reports under `tools/content/reports/` (the latest
`audit-*.md` is the state of the catalogue).

Seed files of the first drop: `docs/seed-catalog.json`, `docs/seed-daily-packs.json`,
`docs/seed-events.json`, `docs/seed-packs-2.json` (historical; the database is the source of truth).
