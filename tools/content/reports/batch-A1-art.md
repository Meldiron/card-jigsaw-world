# Batch A1 — Art-type packs (worker A1)

Scope: masterpieces, pack-dutch-masters, pack-impressionists, pack-japanese-prints, pack-still-life,
pack-portraits, pack-seascapes, pack-botanical, pack-manuscripts, pack-renaissance, pack-oil-landscapes,
pack-winter-scenes, pack-gardens-art, pack-textiles, pack-tiles, pack-old-maps, pack-vintage-posters.

Method: puzzle sheet reviewed per pack, rejections recorded, spec rewritten (Commons PD-Art uploads,
`fetch_per_topic` 5), pool built, candidate sheets reviewed, `apply --target 24`, final sheet re-read.
Prices untouched. Re-themed packs keep their id and category.

## Puzzle review (before re-sourcing)

| pack | kept | removed (reason: count) |
| --- | --- | --- |
| masterpieces | 8 | landscape 11, quality 3 (short side < 640 px: Sesshu, Hoashi Kyo, Segantini) |
| pack-dutch-masters | 2 | people 11, landscape 7 |
| pack-impressionists | 0 | people 12, landscape 7, quality 1 (B&W photo) |
| pack-japanese-prints | 4 | landscape 5, people 2, duplicate 3 (second impressions of triptych panels), similar 6 (other panels of the same triptychs) |
| pack-still-life | 0 | landscape 8, people 5, quality 4 (B&W / < 640 px), text 1 (trompe-l'oeil with newspaper), weak 2 |
| pack-portraits | 0 | people 20 (whole pack: portraits) -> re-themed |
| pack-seascapes | 0 | landscape 9, off-theme 7 (church, stained glass, field, greenhouse photos), people 3, weak 1 |
| pack-botanical | 3 | landscape 5, quality 4 (< 640 px), weak 3 (mostly blank paper), people 3, off-theme 2 (Etna eruption, stag print) |
| pack-manuscripts | 0 | text 6, weak 4 (plain leather book covers), people 2 -> re-themed |
| pack-renaissance | 0 | people 20 (Madonnas, saints, figure studies) -> re-themed |
| pack-oil-landscapes | 0 | landscape 18, quality 1, people 1 |
| pack-winter-scenes | 0 | landscape 13, people 3, quality 3 (B&W photos, monochrome scrolls), text 1 (calligraphy leaf) |
| pack-gardens-art | 0 | people 10, landscape 8, quality 1, weak 1 |
| pack-textiles | 2 | weak 7 (seven near-identical faded Peruvian fragments with figures), landscape 9, quality 2 (< 640 px) |
| pack-tiles | 2 | landscape 10, people 3, off-theme 2 (feather tapestry, Moon photo), weak 2, similar 1 |
| pack-old-maps | 0 | landscape 9, text 7 (bookplates, labelled map), off-theme 2, people 1, quality 1 -> re-themed |
| pack-vintage-posters | 0 | text 13, people 4, landscape 2, quality 1 -> re-themed |

## Re-themes

- pack-portraits: Portraits -> **Animals in Art** (paintings and prints of animals).
- pack-manuscripts: Medieval Manuscripts -> **Ceramics & Porcelain** (museum ceramics).
- pack-renaissance: Renaissance -> **Renaissance Architecture** (domes, courtyards, façades; Renaissance
  paintings without figures are too rare, and Dürer's nature studies are mostly blank paper).
- pack-old-maps: Old Maps -> **Antique Globes & Instruments** (maps are label-heavy by nature).
- pack-vintage-posters: Vintage Posters -> **Antique Glass & Crystal** (posters are text by nature).

## Per-pack log

### masterpieces — Masterpieces (Art) — final 24
- Removed 14 (landscape 11, quality 3). Kept 8 CMA paintings (Redon, Bosschaert, Monet, two anonymous
  flower pieces, Ensor, Verkade, Heade).
- Added 16 from Commons PD-Art museum uploads: Van Gogh Sunflowers, Irises, Cypresses; Monet Water Lilies,
  Rouen Cathedral, Poplars; Dürer Great Piece of Turf; van Huysum; Ruysch; Hiroshige Plum Garden and Naruto
  whirlpool; Rousseau Equatorial Jungle; Fantin-Latour lilies; Renoir chrysanthemums; Stubbs Whistlejacket;
  Fabritius Goldfinch. 65 candidates rejected on the sheets (framed gallery photos, duplicates of the same
  series, photos of live hares/peonies/forests instead of paintings, red-carpet photos found under
  "Fabritius", Van Gogh corridor with a figure, Friedrich paintings with shepherd/hunter).
- Spec `author_cap` raised to 4 (several Van Gogh / Monet works are the point of the pack).
- Tool note: the first `pool` run lost all 110 candidates to Commons HTTP 429; `recover` restored 77.
