# Batch E2 - world-day event packs

Worker E2. Packs: 16 event packs January-March 2027. Target 24 each, minimum 20.

## Review of existing puzzles (14 per pack) and rejections

| Pack | Kept | Rejected (reason: count) |
| --- | --- | --- |
| evpack-bean-day-2027 | 0 | people 3 (mural figure, stencilled face, hand), off-theme 11 (all coffee beans) |
| evpack-hot-tea-2027 | 3 | text 1, off-theme 4 (rocks, empty glass, bowl), quality 2 (dark), weak 4 |
| evpack-squirrel-2027 | 2 | text 1 (sign), weak 1 (feeder with van), similar 10 (one photographer's red squirrels) |
| evpack-education-2027 | 0 | people 4, text 3, off-theme 7 (bird prints, scaffolding) |
| evpack-croissant-2027 | 3 | text 3 (shop signs), off-theme 5 (eggs, teddy), weak 2, quality 1 |
| evpack-wetlands-2027 | 5 | off-theme 1 (carving), similar 8 (herons) |
| evpack-lunar-new-year-2027 | 6 | people 4 (incl. human-figure lantern), duplicate 1, off-theme 2, similar 1 |
| evpack-pizza-2027 | 3 | people 4 (hands), text 5 (brand storefronts), weak 2 |
| evpack-valentines-2027 | 2 | people 2, off-theme 7 (shops, houses), similar 1, weak 2 |
| evpack-love-your-pet-2027 | 6 | people 1, duplicate 1, quality 1, off-theme 1 (nebula), weak 2, similar 2 |
| evpack-polar-bear-2027 | 0 | people 8 (polar plunge crowds), off-theme 3, quality 1, text 1, weak 1 |
| evpack-wildlife-2027 | 7 | people 2, quality 4 (dark night lions), weak 1 |
| evpack-womens-day-2027 | 0 | people 14 (painted portraits) |
| evpack-pi-day-2027 | 4 | people 3 (hands, person), text 1, off-theme 2, weak 4 |
| evpack-st-patricks-2027 | 3 | text 1, similar 3, quality 1, weak 6 (muddy phone shots) |
| evpack-happiness-2027 | 1 | people 12, text 1 |

Specs written for all 16 packs (`tools/content/specs/evpack-*-2027.json`), 30 topics + more_topics each.
Women's Day re-themed through symbols (mimosa, purple and yellow flowers, tulips, jewellery, ribbons, gardens, stained glass); name kept.

## Sourcing log

Note (tooling): the first pools (bean-day, hot-tea) lost most candidates to upload.wikimedia.org HTTP 429 throttling
(93 of 123 bean candidates cached as permanent "bad"). The tool owner shipped `run.sh recover PACK`; both pools were
recovered with it before any apply. Later pools ran with the paced fetcher.

### evpack-bean-day-2027 (National Bean Day)
- Removed 14 (people 3, off-theme 11: the pack was coffee beans). Pool 123 candidates after recover; rejected candidates: people 10, text 3, off-theme 11 (coffee, cocoa, vanilla), weak 50.
- Added 24 by explicit pick: kidney, pinto, cannellini, borlotti, lima, black-eyed and lupin beans, long beans, bean pods and flowers, falafel, hummus, baked beans, bean salad, dal thali, minestrone, lentil soup, pulses stall.
- Final count 24. Cover: red kidney beans (first puzzle).
