# Batch E1 — paired world-day event packs (2026 + 2027)

Worker E1. Method per pair: topic-first spec for the 2026 pack, strict puzzle review, Commons pool,
candidate review, apply to 24, final sheet, then `clone` into the 2027 pack. Reject reasons:
people/text/landscape/duplicate/quality are global, off-theme/weak/similar are pack-scoped.

## Puzzle review of the 2026 packs (and new-year-2027)

All 21 packs were reviewed from their puzzle sheets before sourcing. Removed per pack (reason: count):

| pack | people | text | landscape/dup | quality | weak/similar/off-theme | kept |
| --- | --- | --- | --- | --- | --- | --- |
| evpack-coffee-2026 | 4 | 3 | 0 | 2 | 2 | 3 (p06 espresso on stool, p07 Chemex, p12 latte art) |
| evpack-smile-day-2026 | 9 | 1 | 0 | 1 | 3 | 0 |
| evpack-animal-day-2026 | 1 | 4 | 0 | 4 (three foxes under 900 px, dark monkey) | 4 | 1 (fox cub) |
| evpack-teachers-2026 | 4 | 1 | 0 | 3 | 5 (three same-author school buildings) | 1 (vintage classroom) |
| evpack-mental-health-2026 | 1 | 0 | 0 | 2 (flat sunset silhouettes) | 8 (half-sky lakes) | 3 (autumn tree, two lily-pad ponds) |
| evpack-food-day-2026 | 5 | 1 | 0 | 1 | 7 (shelves, murals, plants) | 0 |
| evpack-un-day-2026 | 5 | 5 (one banner twice) | 0 | 0 | 4 | 0 |
| evpack-halloween-2026 | 3 | 0 | 0 | 1 (683 px) | 6 (dark porches, same-author pumpkins) | 4 |
| evpack-vegan-2026 | 0 | 0 | 0 | 1 | 6 (flat white bowls, two chicken salads, a hand) | 7 |
| evpack-diwali-2026 | 2 | 0 | 0 | 0 | 8 (lakes, roads, gulls, Machu Picchu) | 0 |
| evpack-remembrance-2026 | 2 | 0 | 0 | 0 | 6 | 6 poppy close-ups |
| evpack-kindness-2026 | 12 | 1 | 0 | 0 | 1 | 0 |
| evpack-universal-childrens-2026 | 13 | 0 | 0 | 0 | 1 | 0 |
| evpack-thanksgiving-2026 | 4 | 1 | 0 | 2 | 4 | 3 (cranberry drink, mini pumpkins, gourds) |
| evpack-volunteer-2026 | 1 | 0 | 2 dup | 0 | 9 | 2 (chard, borage) |
| evpack-mountain-day-2026 | 2 | 0 | 0 | 1 | 5 | 6 |
| evpack-tea-day-2026 | 8 | 0 | 0 | 0 | 5 (three same-author pagodas) | 1 (porcelain cup) |
| evpack-winter-solstice-2026 | 0 | 0 | 0 | 4 (b/w, bordered x2, dark fireworks) | 6 | 4 |
| evpack-christmas-2026 | 2 | 1 | 0 | 0 | 5 | 6 |
| evpack-new-years-eve-2026 | 5 (incl. two landscape paintings with figures) | 0 | 0 | 0 | 5 | 4 |
| evpack-new-year-2027 | 1 | 2 | 0 | 1 | 8 (seven same-author dark night views) | 2 |

Tooling note: Commons returns HTTP 429 for bursts of thumbnail fetches while several workers run; the
pool stores those as `bad http 429` and never retries them, and some searches silently return 0 results.
Workaround used: a scratchpad helper re-fetches the 429 candidates one at a time with backoff, drops them
from the pool file, then `pool` is re-run so they are evaluated from the warmed cache. Suggest `pool`
retries 429 with backoff and re-evaluates `bad` fetch failures on re-run.

## Per pack results

