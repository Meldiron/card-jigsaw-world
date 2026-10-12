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
