# daily-2027b batch (daily-2027-06 to daily-2027-12)

Spec: `tools/content/specs/daily-2027b.json` (pool `daily-2027b`, Commons only, 312 topics plus a
reserve in `more_topics`; subjects that daily-2027a covers were left out). Pool at the end: 1191
candidates, every one reviewed on contact sheets; people, text and quality rejects are recorded in
`state/rejects.json`. Every day is an explicit pick; titles were set by hand with `retitle` (common
names, no scientific names).

| Pack | Days | Seasonal feel | Replaced after the sheet review |
| --- | --- | --- | --- |
| daily-2027-06 June 2027 | 30 | summer flowers, orchids, lighthouses, coastal cliffs | 6: 4 people (calanque swimmers, lighthouse and Bonifacio visitors, Villa d'Este tourists), 2 weak (common spotted orchid, emperor dragonfly) |
| daily-2027-07 July 2027 | 31 | seaside, harbours, summer fruit, lilies | 0 |
| daily-2027-08 August 2027 | 31 | late-summer meadows, butterflies, alpine lakes | 1 weak (tanager on a flat white background) |
| daily-2027-09 September 2027 | 30 | harvest, fungi, deer and squirrels, vineyards | 1 weak (rose hips against a plain sky) |
| daily-2027-10 October 2027 | 31 | autumn trees and leaves, pumpkin soup, caramel apples | 0 |
| daily-2027-11 November 2027 | 30 | forest fungi, castles, autumn gardens, cakes | 1 people (Trakai Island Castle: visitors on the bridge) |
| daily-2027-12 December 2027 | 31 | snow, winter birds and animals, festive bakes, Christmas Tree Cluster | 3 weak (two-tone ice, two subjects on plain white) |

Audit (`run.sh audit --pack daily-2027-06 ... daily-2027-12`, 2026-10-13 13:54): 0 violations, 0
cross-pack near-duplicates, all dates present; `verify` marked all seven packs verified. All pictures
and covers are hosted in Storage. Prices untouched (packs were created at the tool default; the
coordinator runs `tools/store/apply_pack_prices.py`).

Dedupe note: one planned November pick (velvet shank, Commons file shared with the daily-2027a pool) was
refused by the "already used in another pack" check because daily-2026-12-22 had taken it first; a
different picture was used.
