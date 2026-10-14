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
| Library photo packs, event packs, daily packs (October 2026 repair onwards) | Wikimedia Commons search and categories (`upload.wikimedia.org` 1280 px renditions, 960 px thumbs) | CC0, Public domain, CC BY, CC BY-SA (NC/ND rejected) | Quality / Featured / Valued images first; `deepcategory:` trees such as "Quality images of food". Wikimedia only serves its standard thumbnail steps (20, 40, 60, 120, 250, 330, 500, 960, 1280, 1920, 3840 px; other widths are rounded up by the API and rejected when hotlinked, see [Common thumbnail sizes](https://www.mediawiki.org/wiki/Common_thumbnail_sizes)); the tool uses 1280 / 960. |
| AI category | Wikimedia Commons categories of AI-generated images (by generator and by subject) | Public domain (`PD-algorithm`: no human authorship) or CC as tagged | Author stored as `<prompter or uploader> / <generator>`, source marked `(AI-generated)`; never presented as human-made. |
| Abstract category | Wikimedia Commons (macro, texture, aerial and render photos), NASA Earth Observatory for topographic packs | as above / NASA public domain | |
| Original featured packs (Wild Nature, Animal Friends, Cozy Kitchen, City Lights) | Lorem Picsum (Unsplash photos) | Unsplash License | `picsum.photos/id/{id}/900/1200`; violating pictures replaced from Commons |
| Legacy art packs | Cleveland Museum of Art Open Access API | CC0 | `web` renditions are at most 900 px on the long side; landscape ones were removed, new art comes from Commons PD-Art museum uploads |
| Space packs (existing only) | NASA Image and Video Library, Hubble/Webb/ESO uploads on Commons | Public domain, credit NASA / CC BY (ESO, ESA) | `~medium.jpg` renditions, `~orig.jpg` where medium is unavailable. No new space pictures: the owner does not want them (2026-10-14). |
| Legacy library and event packs (October 2026 drop) | Openverse search (Flickr, rawpixel, StockSnap, iNaturalist hosts) | CC0, PDM, CC BY, CC BY-SA only | Now a registered, verified client (10,000 requests/day); anonymous fallback 190/day when the client keys are missing |

## Picture providers in the content tool

`tools/content/run.sh sources` lists every provider with whether it is active, its licence policy and a
live health check. A spec uses a provider only when its `sources` list names it (default `["commons"]`).
API keys live in `secrets/content-keys.env` (git-ignored, `KEY=VALUE` lines; empty value = off).

| Provider id | What it serves | Licence kept | Stored author / source | Image URL used | Key and limits |
|---|---|---|---|---|---|
| `commons` | Wikimedia Commons search and categories | CC0, PD, CC BY, CC BY-SA (NC/ND rejected) | Artist field / `Wikimedia Commons, <licence>` | 1280 px rendition, 960 px thumb (Wikimedia standard thumbnail steps; spec `commons_width` opts into 1920/3840) | keyless |
| `openverse` | Openverse search (Flickr, StockSnap, rawpixel, ...) | CC0, PDM, CC BY, CC BY-SA | creator / `<host> via Openverse, <licence>` | host URL | `OPENVERSE_CLIENT_ID` + `OPENVERSE_CLIENT_SECRET` (registered client: OAuth2 bearer token cached until expiry, budget 9,800/day, ~0.7 s spacing); without them anonymous, 190/day |
| `cma` | Cleveland Museum of Art | CC0 | creator / `Cleveland Museum of Art, CC0` | `web` rendition (~700-900 px) | keyless |
| `nasa` | NASA Image and Video Library | Public domain (NASA) | photographer or NASA / `NASA Image and Video Library, public domain` | `~medium.jpg` (`~orig.jpg` fallback) | keyless |
| `met` | The Metropolitan Museum of Art Open Access (`/v1.1/search`, then `/v1/objects/{id}`) | CC0, only objects with `isPublicDomain: true` | artist / `The Metropolitan Museum of Art, CC0` | `primaryImage` (the original: the Met has no mid-size rendition, `web-large` is ~600 px) | keyless; 0.1 s spacing (Met allows 80 req/s); objects cached 60 days; physically landscape objects skipped |
| `nga` | National Gallery of Art, Washington open data (GitHub CSVs, ~170 MB, downloaded once into the cache and indexed; search is local) | CC0, only `openaccess = 1` images | attribution / `National Gallery of Art, Washington, CC0` | IIIF `<iiifurl>/full/!2000,2000/0/default.jpg`, thumb `!960,960` | keyless; index refreshed after 30 days; spec `nga_classes` (e.g. `["Painting"]`) narrows the classification |
| `inat` | iNaturalist research-grade observation photos, ordered by votes (`taxon_name`, then free text) | per photo: CC0 or CC BY | observer name (login) / `iNaturalist, CC0` or `iNaturalist, CC BY` | `original` (at most 2048 px), thumb `large` | keyless; 1 request/s across all workers |
| `rijks` | Rijksmuseum linked-data search (title, then description), resolved object -> VisualItem -> DigitalObject -> Micrio IIIF | Public domain (PDM) or CC0 as stated on the image | maker / `Rijksmuseum, Public domain` | IIIF `/full/!2000,2000/0/default.jpg`, thumb `!960,960` | keyless; 0.5 s spacing; resolutions cached 60 days |
| `pexels` | Pexels search, portrait | Pexels License | photographer / `Pexels, Pexels License` | original resized to fit 2000 px | `PEXELS_API_KEY`; inactive without it; owner review required (see content rules) |
| `pixabay` | Pixabay search, vertical, safesearch | Pixabay Content License | user / `Pixabay, Pixabay Content License` | `largeImageURL` (1280 px) | `PIXABAY_API_KEY`; Pixabay forbids permanent hotlinking, so `apply` refuses these candidates until they are re-hosted; owner review required |
| `unsplash` | Unsplash search, portrait | Unsplash License | photographer / `Unsplash, Unsplash License` (+ photographer page, `download_location` in the pool and provenance) | hotlinked `images.unsplash.com` raw URL fitted to 2000 px | `UNSPLASH_ACCESS_KEY` (demo apps 50 requests/hour); `apply` pings `download_location` as the API guidelines require; owner review required |
| `flickr` | Flickr search with licences 4, 5, 9, 10 | CC BY 2.0, CC BY-SA 2.0, CC0, Public domain (PDM) | owner name / `Flickr, <licence>` | `url_k` (2048) or `url_h` (1600) or `url_b` (1024) | `FLICKR_API_KEY` (free keys are non-commercial: owner review of the key terms) |
| `flickr-commons` | Flickr Commons (`is_commons=1`) | "No known copyright restrictions (Flickr Commons)" | institution / `Flickr, No known copyright restrictions (Flickr Commons)` | as `flickr` | `FLICKR_API_KEY`; licence is not a CC licence: owner review + `allow_licences` |

Licences outside the free set (Pexels License, Pixabay Content License, Unsplash License, Flickr Commons
"no known copyright restrictions") are dropped by the pool unless the spec lists them in `allow_licences`,
which a spec may only do after the owner has approved that licence (`docs/content-rules.md`).

Deliberately not used: Europeana (excluded by the owner) and space sources (ESA/Hubble, ESA/Webb, ESO;
the owner does not want space pictures, 2026-10-14); the Art Institute of Chicago and Library of Congress
image servers block automated clients (Cloudflare challenges). Smithsonian Open Access, excluded earlier,
is now approved for pattern packs.

Owner-approved new sources (2026-10-14), not providers in the content tool yet: USGS Earth as Art
(drawings and patterns), SMK National Gallery of Denmark, the J. Paul Getty Museum and Paris Musées
(drawings), Smithsonian Open Access (patterns), ISO Republic, Negative Space, NPS NPGallery and the Yale
Center for British Art and Yale University Art Gallery (pictures). Licences, credits, access and caveats
are in the pack-making skill (`.claude/skills/pack-making/SKILL.md`, "Owner-approved new sources").

Attribution: every puzzle row keeps `author` and a `source` string that names the provider and the
licence (`Rijksmuseum, Public domain`, `iNaturalist, CC BY`); `state/provenance.json` adds the object or
observation page, the provider id and, where the provider has them, the photographer page and Unsplash
`download_location`. CC BY and CC BY-SA images must stay credited by name in the app.

Counts are maintained in the audit reports under `tools/content/reports/` (the latest
`audit-*.md` is the state of the catalogue).

Seed files of the first drop: `docs/seed-catalog.json`, `docs/seed-daily-packs.json`,
`docs/seed-events.json`, `docs/seed-packs-2.json` (historical; the database is the source of truth).
