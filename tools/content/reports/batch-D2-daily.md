# Batch D2: daily packs 2025-01 .. 2026-10

Shared pool `daily-2025` (specs `daily-2025.json` and `daily-2026.json` both point at it, so a picture is used once across
all D2 months). Replacements are in place (same puzzle ids, dates and order). Picks are made per month from topics the
month does not already show.

Tooling notes: `commons_search(quality=True)` without `quality_cat` returns 0 files (its
`incategory:"A" OR incategory:"B"` query matches nothing), so the quality pass never ran; both D2 specs now set
`quality_deepcat: "Quality images"`, which works. `daily-2026.json` listed places/art/space topics with source `inat`
(which does not index landmarks); switched to `commons`.

- daily-2025-01: replaced 32 (people 14, landscape 5, weak 10 incl. 3 flat kept ones, similar 3 same-species repeats inside the month); 31/31 dates; verified.
- daily-2025-02: replaced 27 (people 10, landscape 3, text 1, weak 12 incl. 4 kept ones: cluttered cafe table, flat fjord, dark aurora, dark still life; similar 1: fennec fox also added to pack-foxes meanwhile); 28/28 dates; verified.
- daily-2025-03: replaced 31 (people 13, landscape 4, text 2, weak 12 incl. 2 kept flat-sky landscapes and 1 stoat on flat bokeh); 31/31 dates; verified.
- daily-2025-04: replaced 30 (people 15, landscape 6, weak 9 incl. 1 kept misty forest, 1 cardinal on flat bokeh, 1 stoat carrying prey); 30/30 dates; verified.
- daily-2025-05: replaced 28 (people 13, landscape 6, text 2, weak 7 incl. 1 kept frosted-berries frame on flat haze, 1 snapshot of poppies on asphalt); 31/31 dates; verified.
