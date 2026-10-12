# Batch AB1 — Abstract category (20 new packs, sortOrder 3000-3019)

Worker AB1. Method per pack: spec in `tools/content/specs/abstract-<slug>.json` (Commons search on
material/phenomenon words, `per_topic` 2, `fetch_per_topic` 5, `author_cap` 3, target 24), `newpack`,
`pool`, candidate sheets read and pruned by eye (representational pictures, people, text, borders,
flat/dark frames, near-identical frames out), `apply`, final puzzles sheet read, cover chosen from the
strongest portrait image, `finalize` (accent derived from the cover).

Prices: free = fluid-ink, macro-textures, bokeh, marbling, dunes, frost (6); tickets = topographic (3),
crystal (2); the rest 400-800 coins.

## Packs

Sourcing notes (apply to every pack below):
- Plain Commons search on abstract phrases ("ink in water", "light painting") matched junk (holy-water
  spouts, lithographs, paintbrushes), so every spec mixes precise Commons categories (`cat:` topics
  with `category_depth` 0-2, e.g. `Combed marbled paper`, `Close-up photographs of hoar frost`,
  `Smoke with black background`, `Fractal flames`) with English and German/French search phrases.
- Wikimedia throttled image downloads (HTTP 429) during the first pools; recovered with
  `run.sh recover` (tool fix shipped mid-batch) and a scratchpad sequential re-fetch.

### abstract-fluid-ink — "Ink & Dye" (free, sortOrder 3000) — 21 puzzles
- Theme adjusted: Commons has no ink-in-water / alcohol-ink / acrylic-pour categories and the
  phrase searches returned lithographs and lab photos. Widened to "Ink & Dye": ink in water
  (Jordan Mudrack series, Erich Ferdinand), ferrofluid, tie-dye / shibori / bandhani cloth, paint
  splashes, oil sheen, soap film.
- `author_cap` raised to 6 for this pack only (the Mudrack ink/splash frames are distinct scenes).
- Candidate review: 151 candidates; rejected 28 people, 9 text, 42 off-theme (lab gloves,
  frescoes, posters, kimono, workshop shots), 1 weak, 5 similar; 2 puzzles removed after apply
  (fabric pile, yarn shelf = representational).
- Topics that worked: cat:Ferrofluids, ink cloud / ink swirl / "Farbe in Wasser" (Mudrack),
  cat:Tie-dye, cat:Shibori, cat:Bandhani, cat:Paint splashes, cat:Oil sheen, cat:Soap films.
- Cover: Erich Ferdinand orange ink drop (p01). Unresolved: only 21 (pool exhausted); c105 has a
  554-char URL and was rejected globally.
- Tool bug: `apply` aborts mid-run on an imageUrl longer than 512 chars (Appwrite limit); it
  should skip such candidates (or shorten via the 960px rendition).


### Continuation (second AB1 worker, 2026-10-12)

- abstract-geometric-minimal — "Geometric Minimal" (400 coins) — 24 verified. Removed 7 (3 weak: palm shadow, street facades; 1 similar: second FingerWiki stair; 2 off-theme: Kandinsky, organic Heijnsbroek; 1 border: framed van Doesburg); added 7 via new topics (cat:Suprematism, Popova, Delaunay rythme, Muralla Roja) + Jules Verne Times facades (author_cap 5). Description widened to name the paintings; cover van Doesburg Composition XX (portrait).
- abstract-light-leaks — "Light Leaks & Prisms" (500 coins) — 24 verified (new). 123 candidates; rejected 10 people (Lycurgus cup reliefs, stick-figure light painting, portraits, crowds), 1 text, 34 off-theme (museum vases under "light painting", computers, landscapes), 1 B&W, 26 weak (plain sun flares, blur). Worked: prisms, steel wool, cat:Photoelasticity (Colin), ICM (Sergio Valle Duarte), CD diffraction, lasers, light trails. Dropped soap-film/thin-film topics (overlap with Ink & Dye). Cover: D-Kuru prism dispersion.
- abstract-macro-textures — "Macro Textures" (free) — 24 verified (new). 124 candidates; rejected 4 people (hands holding fruit/feather, kente wearers, illustration), 1 watermark, 6 similar (same-author bark/butterfly-wing/cabbage series), 38 off-theme (cicadas, mushrooms, shutters, whole plants), 33 weak (grey textiles, flat stone). Most texture categories are landscape-only; added Close-up leaves, Peacock feathers, butterfly wing scales, red cabbage, succulents, pine cones. Cover: peacock feather.
- abstract-kaleidoscope — "Kaleidoscope" (600 coins) — 21 verified (new). 179 candidates (Commons + Openverse); rejected 17 people (mandala thangkas with deities, performers, hand), 5 text, 6 quality (B&W, strip collages, bordered), ~70 off-theme (physical kaleidoscopes/teleidoscopes, plates, minarets, landscapes), 2 weak, 2 similar (incl. a Nasir al-Mulk photo already in daily-2025-06). Commons has almost no kaleidoscope imagery; Openverse Flickr kaleidoscope art carried it, plus 2 radial dome ceilings (description now names them). Cover: Magpieturtle kaleidoscope. Unresolved: 21 not 24 (pool exhausted).
- abstract-bokeh — "Bokeh" (free) — 24 verified (new). 131 candidates (Commons + Openverse); rejected 4 people (hand with crystal ball, figures), 1 text, 3 quality (B&W), ~55 off-theme (birds, flowers, cats, drinks, figurines: bokeh only as background), 11 weak (flat blur, grey sparkle), 2 similar. Description now names Christmas trees. Cover: George E. Koronaio colour bokeh.
