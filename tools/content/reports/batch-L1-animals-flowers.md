# Batch L1: Animals and Flowers (worker L1)

Packs: animal-friends, pack-big-cats, pack-owls, pack-horses, pack-butterflies, pack-puppies, pack-kittens,
pack-elephants, pack-penguins, pack-hummingbirds, pack-parrots, pack-foxes, pack-deer, pack-farm-life,
pack-birds-of-prey, pack-frogs, pack-pandas, pack-cherry-blossom, pack-tulip-fields, pack-wild-roses,
pack-sunflowers, pack-lavender, pack-orchids.

## Stage 1: review of the existing puzzles (all 23 packs)

Every pack was rendered as a puzzles sheet and reviewed cell by cell. Most of the keyword-sourced
content was unrelated to the pack (Detroit Tigers memorabilia in Big Cats, party balloons in Foxes,
sagebrush in Horses, botanical plates in Orchids) or showed people. Counts below are what was
rejected per reason; "kept" is what survived into the rebuilt pack.

| pack | people | text | quality | off-theme | weak | similar | kept |
| --- | --- | --- | --- | --- | --- | --- | --- |
| animal-friends | 0 | 0 | 0 | 0 | 6 | 1 | 11 |
| pack-big-cats | 7 | 10 | 0 | 3 | 0 | 0 | 0 |
| pack-owls | 2 | 0 | 6 | 3 | 5 | 0 | 4 |
| pack-horses | 6 | 3 | 1 | 10 | 0 | 0 | 0 |
| pack-butterflies | 1 | 0 | 1 | 6 | 1 | 3 | 8 |
| pack-puppies | 6 | 0 | 1 | 4 | 4 | 0 | 5 |
| pack-kittens | 5 | 0 | 0 | 4 | 4 | 0 | 7 |
| pack-elephants | 5 | 2 | 1 | 7 | 0 | 0 | 5 |
| pack-penguins | 3 | 1 | 2 | 5 | 1 | 0 | 8 |
| pack-hummingbirds | 0 | 0 | 1 | 6 | 8 | 1 | 4 |
| pack-parrots | 4 | 4 | 0 | 5 | 0 | 0 | 7 |
| pack-foxes | 1 | 14 | 0 | 0 | 3 | 0 | 2 |
| pack-deer | 3 | 1 | 3 | 8 | 4 | 0 | 1 |
| pack-farm-life | 6 | 2 | 1 | 5 | 0 | 0 | 6 |
| pack-birds-of-prey | 2 | 4 | 2 | 6 | 2 | 0 | 4 |
| pack-frogs | 3 | 0 | 0 | 1 | 7 | 3 | 6 |
| pack-pandas | 8 | 4 | 0 | 6 | 0 | 0 | 2 |
| pack-cherry-blossom | 7 | 0 | 0 | 3 | 4 | 1 | 5 |
| pack-tulip-fields | 0 | 0 | 3 | 1 | 1 | 0 | 15 |
| pack-wild-roses | 9 | 0 | 0 | 1 | 2 | 3 | 4 |
| pack-sunflowers | 2 | 0 | 1 | 7 | 0 | 4 | 6 |
| pack-lavender | 0 | 0 | 0 | 8 | 2 | 0 | 10 |
| pack-orchids | 0 | 1 | 1 | 13 | 0 | 0 | 5 |

Notes on judgement calls:
- animal-friends (owner's Picsum/Unsplash pack): kept the cow, leopard, fawn, vulture, pug, jellyfish,
  lioness, walrus, black puppy, brown bear, stag and gull-free pictures; dropped the cat-nose macro,
  the half-sky highland cow and river bear, the two near-empty seagull frames, the birds-as-specks
  sky and the second blanket pug (same photographer, same scene as the kept one).
- pack-owls: six gilgit2 frames carry a caption/watermark bar and were rejected as quality.
- pack-wild-roses: the cattan2011 rose-pergola series (14 frames of one scene, most with a visitor)
  was reduced to the two frames without people; the Sharon Mollerus hybrid-tea roses were kept at
  two (author cap).
- pack-orchids: the Reichenbachia botanical plates (captioned lithographs) were treated as off-theme
  so the pack stays photographic.
- pack-deer: three "Unknown" frames at 683 px wide were rejected as too small (new floor is 900 px).

## Tooling note

Commons' upload host answered `http 429` for most candidate fetches during the first pool runs
(several workers fetching 1280 px renditions at once). `pool` marks those candidates `bad` and never
retries them, so a pool can report 0 usable for topics that are fine. Workaround used here: a
scratchpad script drops the 429 entries from the pool file and their meta cache, then `pool` is run
again. Suggest `cjw/pool.py` retry 429s (or exclude them from `have`) and back off between fetches.

## Stage 2: rebuilt packs

### animal-friends (Animal Friends)
- Removed 8: 6 weak (cat-nose macro, half-sky highland cow, river bear, seagull x2, birds-as-specks),
  1 similar (second blanket pug), 1 people (mandrill candidate added then dropped: blurred visitors).
- Added 13 from Commons: zebra x2, meerkat, clownfish in anemone, flamingo, hawk, koala, red
  squirrel, polar bear x2, Iberian lynx, rabbit, panther chameleon.
- Final count 24. Description kept ("Furry, feathery and fierce friends from around the world.").

### pack-owls (Owls)
- Removed 18 of 20: 2 people (owl on glove, woman holding owl), 6 quality (gilgit2 caption bar), 3 off-theme
  (owl butterfly, coin, feather), 5 weak (dark/speck), plus 2 later (screech owl on a glove, barn owl with watermark).
- Added 22: great grey owl x2, little owl, long-eared owl x2, short-eared owl, northern saw-whet, spotted owl,
  Ural owl, spectacled owl, Eurasian pygmy owl, Eurasian scops owl, Indian eagle-owl x2, northern hawk-owl,
  western screech owl chick, eastern screech owl, snowy owl in flight, barn owl in flight, African wood owl,
  brown fish owl.
- Final count 24, verified. Description: "Barn, snowy, eagle and pygmy owls, mostly staring straight back at you."

## Stage 3: resumed packs (one line each)

- pack-birds-of-prey: removed 16 (stage-1 rejects: text 4, people 2, off-theme 6, weak 2, quality 2); kept 4 hawks; added 20 Commons picks (harpy, bearded and king vulture, golden/Steller's/white-tailed/martial/bateleur eagles, kestrel, merlin, saker, red-tailed, goshawk, sparrowhawk, brahminy and black kite, osprey, buzzard, caracara, snail kite); 30 candidates rejected (people 3 falconer gloves/crowd, text 1, off-theme 5, similar 8, weak 11, quality 1 watermark); cover king vulture; final 24, verified.
- pack-butterflies: removed 13 (12 stage-1 rejects + 1 similar Freshney blue); kept 7; added 17 Commons species (monarch, swallowtail, small tortoiseshell, red admiral, painted lady, blue morpho, Adonis blue, orange tip, brimstone, silver-washed and Glanville fritillary, Apollo, zebra longwing, clipper, lime swallowtail, purple emperor, scarce swallowtail, comma); 29 candidates rejected (people 3 fingers/skin, text 1 specimen board, off-theme 7 kingfishers/caterpillars/chrysalises, similar 6, weak 12); cover monarch; final 24, verified.
- pack-deer: removed 19 stage-1 rejects; kept 1 (mule deer); added 23 Commons picks across 17 species (red, roe, fallow, sika, white-tailed, moose, reindeer, caribou, Père David's, sambar, chital, barasingha, Reeves's muntjac, Chinese water deer, pudu, fawn, rutting stags); 34 candidates rejected (people 2 hand through fence/painted figure, text 3, off-theme 10 dogs/heron/artefacts/paintings, similar 5, weak 14 specks); cover red deer stag; final 24, verified.
- pack-elephants: removed 15 stage-1 rejects; kept 5; added 19 Commons picks (African savanna, forest, desert and Asian elephants, Borneo pygmy, calf with mother, eye close-up, bathing, herd at Minneriya, tuskers); 18 candidates rejected (people 2 portrait/safari car, quality 2 b&w, off-theme 3 cattle calf/moose calf/temple fire, similar 2, weak 9); cover tusker; final 24, verified.
- pack-cherry-blossom: removed 15 stage-1 rejects + 1 similar (second white close-up by the same author); kept 5; first pool too thin, added 22 more_topics (`pool --more`, 69 usable); added 20 Commons picks (Kanzan, weeping cherry, Hirosaki Castle, pagoda, Tidal Basin, Washington Monument, Shirotae, incisa, speciosa, jamasakura x2, Okame, yedoensis, subhirtella, Shinjuku Gyoen, Ukon); 73 candidates rejected (people 8 crowds/boats/singers, text 5, off-theme 19 bark/leaves/autumn foliage/towers/heron, similar 8, weak 33 incl. dark night shot); cover Kanzan close-up; final 24, verified.
- pack-farm-life: removed 14 stage-1 rejects + 1 uncertain edge (pig photo); kept 6 (cows, horses, donkey); pool had no usable goats, so added 4 goat topics to more_topics and ran `pool --more` (+45); added 18 Commons picks (Valais blacknose, Jacob and Shetland sheep, pigs, Kunekune, hen, rooster, Silkie, Brahma, goose, duck, Boer and pygmy goats x2, alpaca, llama, donkey, Swiss brown cow); Highland cow and Highland calf were dropped after verify found the same URLs newly placed in daily-2023-08/07 by the daily worker (a spring lamb was lost to a mis-targeted position after the shift); 77 candidates rejected (people 10, quality 6 b&w/watermark, text 2, off-theme 33 wild ibex/beetles/carcasses/birds/engravings, similar 5, weak 21); cover rooster; final 24, verified.
- pack-foxes: removed 18 stage-1 rejects (party balloons etc.) + 1 monochrome white-on-snow; kept 2; pool thin, switched sources to ["inat","commons"] and ran `pool --more` with 14 species topics (+39); added 23 picks across 18 species (red, grey, kit, swift, corsac, fennec, Rüppell's, Cape, bat-eared, silver, pampas, island, Bengal, culpeo, Sechuran, arctic x2); 50 candidates rejected (people 6 incl. hand with skull/foot, quality 1 collage, text 1, off-theme 23 fur coats/pelts/tracks/carcasses/hyena/postboxes, similar 3, weak 15); c44 skipped (already in daily-2023-01); cover red fox (iNaturalist); final 24, verified.
- pack-frogs (Frogs & Reptiles): removed 14 stage-1 rejects + 1 similar (second red-eyed tree frog) + 1 off-theme (egg clutch); kept 4; added 20 Commons picks (dyeing, blue and strawberry poison dart frogs, European tree frog, common frog, bullfrog, glass frog, Amazon milk frog, White's tree frog, panther, veiled and Jackson's chameleons, green iguana, leopard and day geckos, green anole, green tree python, corn snake, emerald tree boa, red-eared slider); 39 candidates rejected (people 3 hands, quality 1 engraving, text 1 range map, off-theme 5 bongo/butterfly/skeleton/stuffed turtle, similar 7, weak 22); c01 skipped (already in daily-2023-02); cover blue poison dart frog; final 24, verified.
- pack-horses: removed all 20 stage-1 rejects; added 24 picks (Arabian, Andalusian, Friesian, Icelandic, Haflinger x2, Shetland, Fjord, Camargue, Clydesdale x2, Konik, Przewalski's, Exmoor x2 incl. mare and foal, palomino x2, dapple greys x2, Noriker, Appaloosa foal, Gypsy cob, Connemara); sources now ["inat","commons"], `pool --more` with breed topics (stopped after 7 of 11 topics, +17); 2 later swaps (Lusitano with signature, second Fjord); 59 candidates rejected (people 16 riders/handlers, quality 2 b&w, text 2, off-theme 10 puffins/bones/painting/statue/gardens, similar 8, weak 13); description now "Arabians, Friesians, Haflingers, Fjord horses, Camargue greys, wild Przewalski's horses and foals in the meadow."; cover Arabian grey; final 24, verified.
- pack-hummingbirds: removed 16 stage-1 rejects; kept 4; added 20 Commons picks across 18 species (fiery-throated x3 incl. one titled "Costa's hummingbird" by its search topic, long-tailed sylph, sparkling violetear x2, ruby-throated, rufous, broad-billed, Allen's, violet sabrewing, collared inca, green-crowned brilliant, booted racket-tail, chestnut-breasted coronet, crowned woodnymph x2, rufous-tailed, black-throated mango, bee hummingbird); 41 candidates rejected (text 6 Gould plates/book pages, quality 1 collage, off-theme 3 nest/Haeckel plate/feeder, similar 17 mostly the Charles J. Sharp series over author cap, weak 14 specks/silhouettes/feeders); description reworded (no coquettes); cover fiery-throated (Giles Laurent); final 24, verified.
- pack-kittens: removed 13 stage-1 rejects + 4 (adult cat, black cat speck in a wall, Christmas-paper shot with tag text, corner signature); kept 5; added 19 Commons picks (tabby, Maine Coon, Siamese, Persian, Ragdoll, Bengal, Scottish Fold x2, Russian blue, Sphynx, tortoiseshell, calico, white, tuxedo x2, Birman, Devon Rex, basket litter, Somali); 42 candidates rejected (people 8 hands/bottles, quality 4 b&w/collage/watermark/signature, off-theme 5 statues/paintings/adult on rug, similar 6, weak 19 specks/dark/blurred); description reworded; cover Siberian tabby; final 24, verified.
- pack-lavender: removed 10 stage-1 rejects + 4 (flat distant field, same-scene duplicate, weak speck, bee photo already in daily-2023-07); kept 9 legacy close-ups and rows; added 15 Commons picks, then pool exhausted, so sources now ["inat","commons"] and `pool --more` with species topics (+31) gave 3 more (French lavender close-up, Luberon field, carpenter bee); 55 candidates rejected (people 1, quality 1 signature, text 3 machinery signs/plant label, off-theme 22 balloon/rose/hall/flags/teapots/fabric/green L. viridis/silver-leaf L. lanata/wine, similar 6, weak 22); description reworded (no Hokkaido); cover Luberon field; final 24, verified.
- pack-orchids: removed 15 stage-1 rejects (Reichenbachia plates etc.) + 1 similar (second white Phalaenopsis); kept 4; added 20 Commons picks (Phalaenopsis x2, Cattleya, Oncidium, Cymbidium, Paphiopedilum, Vanda x2, Miltonia, Zygopetalum, Masdevallia, bee, early purple, marsh, fly, pyramidal and lady's slipper orchids x2, Bulbophyllum, Disa uniflora); 52 candidates rejected (off-theme 9 botanical plates/non-orchid, similar 16 same-author series, weak 27 buds/seed spikes/specks/labels/dark); cover Miltonia; final 24, verified.
