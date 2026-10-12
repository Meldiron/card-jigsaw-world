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
- `verify`: Ensor "Garden of the Rousseau Family" flagged by the title keyword; replaced with Bosschaert's
  niche bouquet. Verified, 24 puzzles.

### pack-dutch-masters — Dutch Masters (Art) — final 24, verified
- Removed 18 (people 11, landscape 7). Kept Kalf and van Beyeren.
- Added 22: van Huysum, Ruysch, Bosschaert, Coorte, de Heem, Marseus van Schrieck, Mignon (2), van der Ast,
  Ruisdael waterfall, Potter cattle, Claesz (2), Heda, Peeters, Beert (2), de Bray, Marrel, Haverman, Verelst,
  de Ring. 39 candidates rejected (framed gallery photos, Jane023 detail crops of one Oosterwijck, Cézanne,
  Snyders market with a woman, red-carpet photo, second versions of the same bouquet).
- Two picks were the same files already used in Masterpieces (verify caught them); swapped for the other
  van Huysum and Ruysch.

## Wave 2 (museum sources: NGA, Rijksmuseum)

- pack-impressionists — verified, 24: removed all 20 old (people 12, landscape 7, quality 1) plus 2 new picks with borders (quality); added 19 Commons PD-Art (Monet x8, Renoir x5, Manet, Morisot, Caillebotte, Signac x2, Twachtman) and 5 NGA (Cézanne x2, Morisot Peonies, Boudin, Redon); 92 candidates rejected (framed gallery shots, photos, figures, repeat Rouen/Poplars/Belle-Île views); spec sources commons+nga, author_cap 8.
- pack-still-life — verified, 24: removed all 20 old (landscape 8, people 5, quality 4, text 1, weak 2) plus 2 picks with statues or relief figures (people); added 24 from NGA (22 paintings: Meléndez, Coorte x2, Binoit, Bosschaert, Roesen, Monet, Redon, Vallotton, Brueghel workshop, de Heem, Morel, Eelkema, American folk) and Rijksmuseum; 26 candidates rejected (dark varnish, statues, prints, ceramics); spec sources nga+rijks+commons, cover Binoit tulips.

## Wave 3 (resume; museum sources first)

- pack-botanical — verified, 24: removed 17 old (landscape 5, quality 4, weak 3, people 3, off-theme 2); kept Brookshaw plums, Thornton Blue Passion Flower and Dragon Arum; added 21 (NGA: Redouté x2, Dietzsch thistle, lotus, Pink Roses, Pillement/Allen; Rijks: van Leen tulip, Marrel tulip; Met: Redouté rose; Commons: Thornton x3, Merian x2, Reichenbachia, Haeckel orchids, Fitch x2, Weinmann x3); 77 candidates rejected over both passes (Met fuzzy-search junk: ceramics, reliefs, statues; Vuillard interiors; monochrome sketches; third passion flower; second Haeckel scan with page border); spec sources nga+met+rijks+commons, cover Redouté Four Peonies and a Crown Imperial.
- pack-gardens-art — verified, 20: removed all 20 old (people 10, landscape 8, quality 1, weak 1) plus 1 pick with a black edge (quality); added 20 Commons PD-Art (Monet x2, Caillebotte x3, Van Gogh x4, Sorolla x3, Klimt, Rusiñol, Le Sidaner, Liebermann, Hiroshige, Seurat, Mønsted, Denis); ~95 candidates rejected (Giverny/Alhambra photos, figures in Vuillard/Hassam/Rysselberghe/Mønsted, framed gallery shots, book pages, statues); NGA added nothing (garden paintings there are landscape or have figures); only 20 because portrait garden paintings without people are scarce. Note: Commons puzzles take the topic as title, so the Maurice Denis snow garden is titled "Gustave Loiseau garden painting".
- pack-japanese-prints — verified, 24: removed 16 old (landscape 5, people 2, duplicate 3, similar 6) plus 3 kept old prints under 640 px (quality, flagged by verify); kept Hiroshige Evening View; added 23 Commons uploads (Hiroshige x9, Hokusai x3, Koson x4, Kuniyoshi x3, Jakuchu x2, Kyosai, Seitei); ~70 candidates rejected (Hokusai waterfall series and Asakusa cat print for tiny figures, repeat impressions of the same print, extra crows, Kono Bairei prints with printed borders, scroll photos on black, noren/vase/tsuba photos); NGA has no open Japanese prints, Rijks not needed; cover Hokusai Peonies and Canary.
- pack-manuscripts (re-themed Ceramics & Porcelain) — verified, 24: removed all 12 old (text 6, weak 4, people 2); added 24 Commons museum photos (Qing x3, Satsuma x2, Iznik x2, Talavera x2, Royal Copenhagen x2, Kutani x2, moon flasks x2, Meissen, Sèvres, Imari, Hispano-Moresque, Nabeshima, Zsolnay, Art Nouveau, Rookwood, Kütahya); 32 candidates rejected (painted figure scenes on Ming, Kangxi, Sèvres, Satsuma and Minton pieces, mask reliefs, museum portraits in the background, pale or muddy glazes, a B&W photo, tiles, a Cézanne still life); author_cap raised to 12 because Daderot photographed 11 different museum objects; NGA ceramics are mostly figurative maiolica, so Commons only.
- pack-oil-landscapes — verified, 24: removed all 20 old (landscape 18, quality 1, people 1) plus 2 picks (framed Hodler photo: quality; Thomson "Northern River" sketch next to the canvas: similar); added 24 Commons PD-Art (Thomson x2, Klimt x3, Hodler x2, Gallen-Kallela x3, Carr x2, Cézanne x2, Bierstadt, Shishkin, Kuindzhi, Durand, Whittredge, Hill, Monet, Cropsey, Vasilyev, Van Gogh); 34 candidates rejected (gallery frames, tree photos, figures in Friedrich/Bierstadt/Savrasov, B&W, dark varnish, Rousseau lion details, Savrasov rooks kept for Winter Scenes); NGA has almost no portrait-format landscapes; cover Thomson Soft Maple in Autumn.
- Titles: per the new brief section, 103 topic-derived titles in pack-botanical, pack-gardens-art, pack-japanese-prints, pack-manuscripts and pack-oil-landscapes were replaced with the works' real titles via `retitle` (e.g. "Utagawa Kuniyoshi cats print II" -> "Tiger", "Gustave Loiseau garden painting" -> "Convent Garden").
- pack-old-maps (re-themed Antique Globes & Instruments) — verified, 24: removed all 20 old (landscape 9, text 7, off-theme 2, people 1, quality 1) plus the Wells clock pick (jousting-knight figures: people); added 24 Commons museum photos (celestial and terrestrial globes x7, armillary spheres x4, astrolabes x2, nocturnals x2, sextants x3, orreries x2, astronomical clock dials x3, chronometer, pocket watch); 41 candidates rejected (constellation gores with figures, maps and title pages, Prague clock statues, stone sundials, repeat shots of the same orrery, chronometer and sextant, people in museum halls); author_cap raised to 10 (Daderot photographed 8 different objects); titles set from the museum labels.
- pack-portraits (re-themed Animals in Art) — verified, 24: removed all 20 old portraits (people); added 24 (Commons: Marc x3, Barraband parrots x3, Seba x3, Haeckel x3, Gould x2, Ronner-Knip x2, Wolf x2, Hondecoeter, Thorburn, Liljefors, Mansur peacocks, Gould/Lear eagle owl; NGA: American 19th-century Blue Jay); 45 candidates rejected (riders, statues, Macke/Marc Paradise figures, gallery frames, Dürer hare with mount lines, B&W prints, live-animal photos, Mughal album mounts, pale Haeckel plates); dropped the Japanese topics so the pack does not repeat Japanese Prints; NGA Audubon/Gould/Catesby prints are already used elsewhere in the catalogue; titles set from the source files; cover Marc Blue Horse I.

## Wave 4 (resume 2026-10-12 evening; picks checked against the live catalogue before apply)

- pack-renaissance (re-themed Renaissance Architecture) — verified, 24: removed all 20 old (people 20, rejected in wave 1); added 24 Commons quality photos picked by hand (Florence dome, Tempietto, St Peter's, Sant'Andrea Mantua, Chenonceau, Azay-le-Rideau x2, Todi, Colleoni, Chambord, Escorial, Litomyšl, Charles V palace x2, Blois staircase, Chiericati, Villa Barbaro, San Zaccaria, Casa de las Conchas, Frederiksborg x2, Bremen, Zamość, San Pietro in Montorio); pool extended with 22 more topics; ~60 candidates rejected (statues and busts at Villa Medici/Heidelberg/Telč/Maser, altar paintings with figures, sepia Rijksmuseum prints, B&W, tourists at San Zaccaria/Zamość, repeat Litomyšl/Casa de las Conchas shots, flat water views); titles set by hand.
