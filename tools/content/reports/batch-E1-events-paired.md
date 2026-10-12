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

### evpack-coffee-2026 / evpack-coffee-2027
- Removed 11 of 14 (people 4, text 3, quality 2, off-theme 1, weak 1); kept 3 (espresso on stool, Chemex, latte art on wood).
- Pool: 3 rounds (first two lost most candidates to Commons 429s, recovered with the helper / `recover`). Candidate rejects: people 11 (hands pouring, barista, statue, portraits), text 6, similar 6, weak 8, off-theme 10.
- Added 20: latte art x3, coffee cherries, green beans, bean sacks, Irish coffee x2, Coffea blossom, Ethiopian jebena x4 (different pots/scenes), blue moka pot, pour-over, gilded cup, flat white x2, roaster drum, cafe flat-lay.
- Final 23 (one affogato removed on the final sheet for a blurred person at the edge). `verify` clean.
- Cloned to evpack-coffee-2027 (23). `verify` reports only the 23 clone same-URL notes.

### evpack-smile-day-2026 / evpack-smile-day-2027
- Removed all 14 (people 9, text 1, quality 1, off-theme 3). Re-themed through smiling animals, sunflowers, smiley treats and cheerful colours.
- Pool: 2 rounds (the "smiling X" phrasing returned nothing on Commons; plain nouns in `more_topics` fixed it). Candidate rejects: people 8, text 5, quality 4, similar 9, weak 14, off-theme 9.
- Added 24: quokka, puppy, alpacas, dolphins, flamingo, sprinkle ice cream, rubber duck, swirl lollipop, macarons, balloons in sky, crayons, gerberas x3, sunflowers x3, blanket flower, tulips x2, daisies x2, Burano facades x2.
- Final 24, `verify` clean. Cloned to evpack-smile-day-2027 (24; verify shows only clone same-URL notes).

