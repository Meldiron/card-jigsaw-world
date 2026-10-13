# Batch N1: new packs so Mountains, Patterns and Vintage each reach 6 (2026-10-13)

Owner request: every Library filter holds at least 6 packs. This batch adds 5 Mountains, 4 Patterns and
1 Vintage pack (Premium and Seasonal are another worker's). Ideas were checked against every existing
pack and event (Snowy Peaks, Alpine Lakes, Patagonia, Scenic Roads, Swiss Villages, Textiles, Tiles &
Mosaics, Abstract Spirals/Kaleidoscope/Macro Textures, Globes & Instruments, which already holds clocks).
Specs: `tools/content/specs/<id>.json`; sortOrder 1120-1129 (0-10 is reserved for Home "Featured").
Prices are left at the tool default; `tools/store/apply_pack_prices.py` sets them afterwards.
Every pick was reviewed on enlarged sheets; long Commons author strings ("This Photo was taken by X.
Feel free ...") were shortened to the photographer's name, and topic titles were corrected per picture.

| Pack | Category | Puzzles | Notes |
| --- | --- | --- | --- |
| pack-dolomites (Dolomites) | Mountains | 24 | 103 candidates, 52 rejected (19 people, 9 black-and-white/old prints, 2 text, 8 same scene, 14 weak); verified |
| pack-quilts (Quilts) | Patterns | 24 | Met CC0 objects and Commons museum photos (MFA Boston via Daderot, Met donations); 40 rejected: Index of American Design watercolour renderings (paper margins, signatures), Smithsonian SAAM / Cooper Hewitt files (Smithsonian Open Access is excluded by the owner), a signature quilt (text), modern quilts (copyright), b&w record shots; author_cap 6 because "American" is the Met's credit for anonymous makers; verified |
| pack-mountain-huts (Mountain Huts) | Mountains | 24 | Three pool rounds (210 candidates): most hut-name searches return interiors, signs, plaques, ski-lift stations, birds or town buildings named after huts; 25 people (incl. a terrace of diners at Äscher and hikers at Meilerhütte and Zelené pleso found on zoomed crops), 26 signs/plaques, ~130 off-theme or weak; titles corrected from file descriptions; Téryho chata (p04) is a Commons "Images from Unsplash" CC0 upload (pre-2017 Unsplash photos were CC0); verified |
| pack-embroidery (Embroidery) | Patterns | 24 | Two pool rounds (175 candidates), Met CC0 plus Commons museum and field photos; rejected 14 people (costumes worn, portraits embroidered on cloth), 11 text (samplers, watermarks, building signs), 11 b&w record shots, Cooper Hewitt files (Smithsonian excluded), weak museum shots; author_cap 4 for anonymous makers; verified |
| pack-wallpapers (Wallpapers) | Patterns | 24 | Two pool rounds (205 candidates); the Met API search is fuzzy and returned almost no sidewalls, so 14 of the 24 are Cooper Hewitt sidewall scans uploaded to Wikimedia Commons (public domain / CC0; same route as 10 Cooper Hewitt files already in Textiles, Marbling and Ceramics). The owner excluded Smithsonian Open Access as a source; if that also covers Commons copies, these 14 need replacing (flagged in the hand-off). Others: Met CC0 designs, BnF borders, Zuber (Google Art Project), Chinese rooms at Hellbrunn, Chatsworth and Badenburg. Rejected cherubs and figure medallions (people), the possibly in-copyright Flögl design (d. 1958), a Peche sheet with a colour bar, b&w record shots, a museum building; verified |
| pack-folk-art (Folk Art) | Patterns | 24 | Two pool rounds (149 candidates; native-language terms: Хохлома, Петриківський розпис, festett kazettás mennyezet, Bauernschrank); Met results were plain furniture; rejected artists posing with work, cupboards with painted saints, Kosiv lithograph plates (printed captions), a ZALIPIE sign, b&w archive photos, workshops with workers, church towers; the description was rewritten to match the final picks; verified |
| pack-alpine-meadows (Alpine Meadows) | Mountains | 24 | Three pool rounds (208 candidates): round 1 species topics returned mostly flower close-ups with no mountain setting (52 rejected off-theme), rounds 2-3 used meadow and place topics (Logan Pass, Paradise, Hurricane Ridge, Kazbegi, Allgäu, Narzissenwiesen); rejected hikers, trail signs, herbarium sheets, villas named "Alpenrosen", wildlife; author_cap 3 ("NPS Photo" is a shared credit); description rewritten to match the picks; verified |
| pack-rocky-mountains (Rocky Mountains) | Mountains | 24 | Replaces the planned Rainbow Mountains as the fifth Mountains pack (see below). Two pool rounds (144 candidates); avoided peaks already in Snowy Peaks (Assiniboine, Robson), the Mountain Day event (Grand Teton, Mount Sam, Sunburst) and road shots covered by Scenic Roads; rejected NZ's Mount Hector (same name), a plaque, b&w archive photos, Mount Stephen House interiors, Chester (England) street views, a portrait; verified |
| pack-rainbow-mountains (Rainbow Mountains) | Mountains | not built | Three pool rounds (126 candidates) gave only about 16 truly striped frames: Vinicunca and Hornocal shots are crowded or flat, the rest are muted tan badlands and canyons that overlap the Canyons pack. Spec and pool kept for a later attempt; no pack row was created. |
| pack-mountain-autumn (Autumn in the Mountains) | Mountains | 24 | Three pool rounds (114 candidates): English "autumn" searches were thin, so round 2 added fall / Herbst / automne / jesień / 紅葉 topics; rejected hikers, a signpost, close-ups without mountains, park scenes, mineral photos returned for "Telluride"; author_cap kept at 2 (two NARA and two NPS Photo credits); verified |
| pack-clocks (Antique Clocks) | Vintage | 24 | Chosen over Carousels (two rounds gave only ~17 people-free carousels; riders, operators, signs, watermarks). Domestic clocks only, so no overlap with the tower clocks, pocket watch and chronometer in Antique Globes & Instruments. Rejected 40 figural clocks (gilt figures, cupids, busts, Sèvres nudes, painted porcelain scenes count as people), Prague astronomical clock repeats, b&w record shots, museum rooms; verified |
| pack-carousels (Carousels) | Vintage | not built | Spec and three pool rounds kept; not needed once Antique Clocks filled the Vintage slot. |

Final audit (`reports/audit-2026-10-13-1647.md`, the 10 new packs): 0 violations, 0 duplicate pairs, 0 cross-pack repeats,
0 landscape, 0 small; 4 title/author keyword hints, all false positives checked by eye ("Agner north face", the Commons user
"family picture", "Grandmother's Flower Garden", "Robert Graves Co.").

Process notes for the next worker:
- A global reject reason (`people`, `text`, `quality`, `duplicate`, `landscape`) on a candidate whose URL is also a live puzzle in
  another pack makes that pack's next `apply` delete the puzzle. Use `similar`/`off-theme` for "already used elsewhere". Found one
  pre-existing case: `evpack-food-day-2027` p-fe0a61c6b8de still shows the spice-market photo rejected for people in the 2026 pack.
- Cooper Hewitt (Smithsonian) scans reach Commons as "(CH 18xxxxxx)" files; they were already in Textiles, Marbling and Ceramics
  before this batch and are 14 of the 24 Wallpapers. Owner decision needed on whether the Smithsonian exclusion covers them.
