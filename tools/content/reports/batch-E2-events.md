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
- verify: the audit keyword filter flagged the title "Scarlet runner beans" (people:runner) although the image is a bean pod; swapped it for lima bean flowers (c74) and renamed the topic. Tooling note: `audit` does not honour the spec's `allow_words`, so plant names like "runner bean" cannot be used as topics.

### evpack-hot-tea-2027 (National Hot Tea Day)
- Removed 11 (text 1, off-theme 4, quality 2, weak 4); kept 3 (tea glass on sill, mug with tea bag, ceramic cup).
- Pool 118 candidates (after recover); rejected: people 4, text 9, off-theme 25 (museum pots with scale rulers, moorland, mint plants, iced drinks), quality 1, weak 12, similar 3.
- Added 21: jasmine pearls, samovars, yixing teapot, milk tea cups, hibiscus petals, porcelain cups, green/oolong/white tea leaves, gaiwan, darjeeling cups, tea bag cup, afternoon tea pour.
- Final count 24, verified.

### evpack-squirrel-2027 (Squirrel Appreciation Day)
- Resumed at 14 with 12 rejects pending (sign 1, feeder 1, same-photographer red squirrels 10); removed 1 more of the same photographer (similar), keeping one. Candidate rejects: off-theme 9 (acorn woodpeckers, hawks, sea creatures from "flying squirrel", painting), weak 7 (museum mounts, skeleton, illustrations).
- Added 23 by pick, one per species/scene: Eurasian red x3 (hazelnut, branch, standing), eastern grey x4, fox, black, Indian giant x2, Siberian chipmunk x2, eastern chipmunk, Abert's, Douglas, golden-mantled x2, California ground squirrels, red-bellied x2, American red x2. Final 24, verified.

### Resume (second session): one line per pack
- evpack-croissant-2027: removed 12 (text 3, off-theme 5, weak 2, quality 1, people 1 hand found on final sheet); pool 53 usable, candidate rejects people 5, text 2, off-theme 11, weak 10; added 22 by pick (croissants, pain au chocolat, almond, pistachio, kouign amann, pain aux raisins, brioche, danish pastries); all picks cross-checked against the live catalogue (no URL or near-duplicate hits); final 24, verified.
- evpack-education-2027: removed all 14 (people 4, text 3, off-theme 7); pool 144 candidates after `--more` with named libraries (Admont, Melk, Wiblingen, Joanina, Real Gabinete, Rijksmuseum), candidate rejects people 31 (incl. ceiling frescoes with painted figures, statues), text 9, quality 3, off-theme 10, weak 19, similar 3; added 24 by pick (8 libraries, books, 2 schools, abacus, inkwell, pencil case, paper plane, bookshop, Celsus, Strahov cabinet, eagle owl, flask, pencils); 14 titles fixed; description rewritten (no globes/microscopes); live-catalogue cross-check clean; final 24, verified.
- evpack-happiness-2027: removed 13 (people 12, text 1), kept 1 (hot air balloon); pool 127 after `--more` (lorikeet, jelly beans, Burano, rainbow eucalyptus, Keukenhof, ducklings, puppies), candidate rejects people 13 (incl. Rizzi House painted faces), text 8, quality 1, off-theme 7, weak 22, similar 4 (c27 balloon already live in pack-hot-air-balloons, caught by the live cross-check); added 23 by pick; 13 titles fixed; description rewritten; final 24, verified.
- evpack-love-your-pet-2027: removed 9 (people 1, duplicate 1, quality 1, off-theme 1, weak 2, similar 3 incl. a second near-identical spitz shot); pool 82 (68 usable), candidate rejects people 3 (dogs held in arms, finger), text 1, off-theme 7 (stained glass, statues, beetle, painting), weak 20 (cage shots); added 19 by pick (dachshund, golden puppy, guinea pig, hamster, cockatiel, beagle, ragdoll, Siamese, seal point, 2 labradors, British shorthair, Maine coon, border collie, rabbit, chinchilla, bearded dragon, betta, budgies); 12 titles fixed; live cross-check clean; final 24, verified.

### Grey-rule follow-up (E1/E2 worker, third session)
- evpack-education-2027: removed 2 (quality: grey inkwell from grey-pictures.json, near-grey paper plane on grey); pooled 4 topics (microscope, school bus, mortarboard, desk globe); added antique terrestrial globe and yellow school bus; final 24, re-verified.
- evpack-love-your-pet-2027: removed 1 (quality: black labrador in grey snow, on grey list); pooled 4 topics (goldfish, tortoise, ferret, canary); added yellow canary; final 24, re-verified.
- evpack-lunar-new-year-2027: removed all 14 (8 earlier: people, watermark; 6 more quality: every remaining legacy lantern-festival shot carried the photographer's signature watermark, all one author). Topics rewritten as plain nouns (Commons + Openverse, 44 topics in 4-topic chunks, 181 candidates). Candidate rejects: people 17, text 11, quality 8 (watermarks incl. phone stamps, collages), off-theme 30, weak 43, similar 8. Added 24 by pick: red paper lantern (cover), temple gate, red lanterns, red envelope, jiaozi, plum blossom, kumquat tree, Chinese knot, incense coils, goat, lantern festival lion, mandarin oranges, golden temple dragons, temple roof dragon, famille jaune vase, lucky bamboo, bánh chưng, spring rolls, lantern strings, pomelo, moth orchid, xiaolongbao, eight treasure rice, yellow chrysanthemum. All checked unused elsewhere; titles cleaned. Final 24, verified.
- evpack-pi-day-2027: resumed at 14 with 10 rejects pending (birthday portrait, hands, Moon Pie packs, bars); removed 1 more (off-theme: layered cake); kept 3 legacy (lemon meringue, pecan, lattice berry pie). Topics rewritten as plain pie and tart names (Commons + Openverse, 44 topics in 4-topic chunks, 125 candidates). Candidate rejects: people 12, text 3, quality 1, off-theme 5, weak 38 (plus unpicked leftovers). Added 21 by pick: apple-peach lattice pie (cover, set in spec), pumpkin, blueberry, onion tarte tatin, mince pies, galette des rois, egg custard tarts, banoffee tartlets, strawberry tart, chicken pot pie, strawberry rhubarb, pastel de nata, apricot tarts, apple rose tart, lemon tart, plum lattice, pear rose tart, cherry almond, blackberry pie, cinnamon rolls, chocolate blueberry tart. All checked unused elsewhere; titles cleaned. Final 24, verified.
