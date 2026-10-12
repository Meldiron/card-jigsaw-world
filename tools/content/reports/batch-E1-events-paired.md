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


### evpack-animal-day-2026 / evpack-animal-day-2027
- Resumed at 15 (earlier pass removed 13: people 1, text 4, quality 4, weak/off-theme 4). Removed 1 more (weak: grey heron titled "African elephant", duplicate topic title); candidate rejects: lion cub with blood x2 (weak), snowy owl sign (text), panda drawing, owl sign, polar bear pelt, museum orangutan (off-theme). Added 10 by pick: red panda, toucan, giraffe, Bengal tiger, snowy owl, scarlet macaw, zebra, grey wolf, polar bear, puffin. Description no longer promises sea turtles. Final 24, verified; cloned to 2027 (24, verified) with a 2027 spec carrying the real description (also applied to coffee-2027 and smile-day-2027, which had "Pictures themed around the day").

### evpack-food-day-2026 / evpack-food-day-2027
- Resumed at 24 with six topics doubled (ramen, sushi, cheese, tacos, dim sum, thali). Removed 11: similar 2 (second ramen and sushi), quality 1 (date-stamped thali), text 1 (labelled Gruyère stack), weak 4 (blurry honeycomb, pumpkin on wall, single green tomato, chicken feet), plus 3 earlier rejects (fish market, coffee with logo, bordered tacos). Pool --more with 28 new dish/market topics (141 candidates, 76 usable); candidate rejects: people 5 (hands), off-theme 7, text 2.
- Added 11 by pick: pumpkin market, Banaue rice terraces, bibimbap, pad thai, baklava, pomegranate tart, red fish at market, bell peppers, pomegranate seeds, charcuterie board, mango sticky rice. Final 24, verified; cloned to 2027 (24, verified, 2027 spec with dated description).

### evpack-mental-health-2026 / evpack-mental-health-2027
- Resumed at 14 with 11 rejects pending (half-sky lakes, sunsets, a person); removed 1 more similar (second lily pond by the same photographer) and the dark tree silhouette. Pool extended with 17 simpler topics (119 candidates); candidate rejects: people 10 (lantern festival crowds, kimono, hands, visitor), quality 4 (date-stamped bamboo x3, signed orchid), text 1, off-theme 7.
- Added 22 by pick, then swapped 3 that verify found in daily packs (bamboo grove, two fern fiddleheads; all fern candidates were already used by daily packs): lotus, bonsai, moss, waterfall stream, cherry blossom, misty forest path, dandelion clock, koi, sand ripples, alpine meadow, stone cairn, lavender field and bundles, succulents, Japanese gardens x2, blooming tea, hydrangea, wisteria, moss gardens x2, white bauhinia. Final 24, verified; cloned to 2027 (24, verified). Description rewritten to match.

### evpack-teachers-2026 / evpack-teachers-2027
- Resumed at 14 with 13 rejects pending; removed the last legacy image too (people: framed portraits above the classroom chalkboard). Pool extended with 13 object/library topics (Commons + Openverse, 180 candidates); candidate rejects: people 17 (visitors in libraries, hands, statues, concerts), text 18 (book pages, calendars, signs, engraved plates).
- Added 24 by pick: pencil shavings, old books x3, one-room schoolhouse, brick schools x2, library spiral stair, globes x2, chalkboard sphere, coloured pencils x3, school bell, abacus, paintbrushes, book-exchange cabinet, bookshop aisle, set square and protractor, hourglass, apple on desk, notebook and pens, school desk, fountain pen. Cover: library staircase. Final 24, verified; cloned to 2027 (24, verified).

### evpack-christmas-2026 / evpack-christmas-2027
- Resumed at 14 with 8 rejects pending; removed 3 more legacy trees (weak: cluttered rooms, dark). Candidate rejects: people 10, text 7, quality 5 (b/w, contact sheets, collage), off-theme 10, weak 19, similar 3. Added 21 by pick: city tree, baubles x3, gnome ornament, baubles in glass, gingerbread house, stockings by fireplace, poinsettia, licitar heart, snow globe, reindeer, buche de Noel, mince pies, flaming pudding, advent wreath, robin in holly, stollen, panettone, holly, mistletoe in snow. Final 24, verified; cloned to 2027 (24, verified, dated description).

### evpack-diwali-2026 / evpack-diwali-2027
- Removed all 10 legacy (from the earlier review). First pool with long phrases gave 15 usable; re-pooled with plain nouns via `--topic` (diya, rangoli, laddu, jalebi, Tagetes erecta, Harmandir Sahib, ...; ~2 min per topic under shared throttling). Candidate rejects: people 14 (hands, a tennis player named Diya, crowds), text 2, quality 1, off-theme 14, weak 16, similar 6. Added 24 by pick: flower rangoli (cover), clay diya stall, Golden Temple at night and fresco panel, lotus, fireworks, illuminated temple, two rangolis, marigold garlands and flowers, sparklers x2, sparkler fountain, laddu, jalebi, barfi box, gulab jamun, kaju katli, akash kandil star lantern, bangles x2, lit diyas, brass deepam. Final 24, verified; cloned to 2027 (24, verified, 29 October 2027).

### evpack-halloween-2026 / evpack-halloween-2027
- Resumed at 14 with 10 rejects pending; removed 2 more (quality: bordered lantern; similar: second carved pumpkin by the same author). Topics rewritten as plain nouns and pooled in `--topic` chunks (Commons + Openverse). Candidate rejects: people 13, text 8, quality 4, off-theme 22, weak 24, similar 7. Added 20 by pick: pineapple and gourd lanterns, pumpkin patch, fruit bat, old house, toffee apples, fly agaric, candelabra, barn owl, gourds, tarantula, pumpkin soup, autumn leaves, forest cobweb, gnarled tree, three Halloween cupcakes, porch skeleton, turban squash, giant carved pumpkin display (cover), pumpkin pie. Final 24, verified; cloned to 2027 (24, verified).

### evpack-kindness-2026 / evpack-kindness-2027
- Removed all 14 legacy (people 12, text 1, off-theme 1, from the earlier review). Topics rewritten as plain nouns (Commons + Openverse, 24 topics in 4 `--topic` chunks, 73 usable). Candidate rejects: people 4, text 4, quality 1, off-theme 12, weak 8, similar 10. Added 24 by pick: tulips in basket (cover), tartan gift box, daisies, bouquet in jug, heart cakes, iced heart cookies, carved gingerbread heart, heart of stones, heart balloons, chocolate boxes, pink rose, hot chocolate, latte heart, heart-shaped leaf, lavender bundle, honey jars, love-lock heart sculpture, ladybird cupcakes, heart cupcake, sunflowers, birdhouse, jam jars, picnic basket, origami heart. Final 24, verified; cloned to 2027 (24, verified).

### evpack-mountain-day-2026 / evpack-mountain-day-2027
- Resumed at 14 with 8 rejects pending; removed 3 more legacy (weak 2: donkey slope, half-sky peak; similar 1: second Matterhorn). Long topic phrases returned nothing, so topics became plain mountain names (Commons + Openverse). Candidate rejects: people 3, text 1, quality 5, off-theme 16, weak 28, similar 14. Added 21 by pick: Matterhorn at nightfall (cover), Ama Dablam, Kirkjufell, Eiger, Mount Assiniboine x2, Grand Teton, Half Dome, ibex, edelweiss, Shuksan, K2, Lofoten x2, Piz Bernina, Annapurna x3, Cradle Mountain, Aoraki trail, Grossglockner. Five first picks (Aoraki, Fitz Roy, two Rainier, Cerro Torre) were already in pack-snowy-peaks / pack-volcanoes and were swapped after `verify`. Final 24, verified; cloned to 2027 (24, verified).

### evpack-new-years-eve-2026 / evpack-new-years-eve-2027
- Resumed at 14 with 10 rejects pending; removed 3 more legacy (similar 1: second fireworks reflection by the same author; weak 2: Eiffel traffic trails, dark Eiffel fireworks). Topics rewritten as plain nouns plus NYE foods and customs (Commons + Openverse, ~40 topics, `recover` for 13 throttled). Candidate rejects: people 22 (hands, cosplay, b/w party photos), text 9 (vasilopita inscriptions, poster, price tags), quality 3, off-theme 16, weak 14, similar 10. Added 21 by pick: fireworks over Sydney Harbour, London, Marina Bay, the Vltava and Prague, pink burst, champagne glass and on ice, disco ball, cocktails, oliebollen, two pocket watches, sparkler, lucky clover, disco ball balloon, streamers, glitter, tinsel, toshikoshi soba, Japanese temple bell, hourglass. Titles cleaned with `retitle`. Final 24, verified; cloned to 2027 (24, verified).
- Also retitled search-phrase and legacy titles ("Christmas 2", "Halloween 4", "Tagetes erecta", "Matterhorn peak Zermatt", ...) in the christmas, diwali, halloween, kindness and mountain-day 2026 packs and re-cloned their 2027 twins (all re-verified).

### evpack-new-year-2027 (single)
- Resumed at 14 with 12 rejects pending; removed 1 more (similar: second Montjuïc night view by the same author). Topics rewritten as plain nouns for Japanese, Korean, German, US and Greek New Year customs and winter plants (Commons + Openverse). Candidate rejects: people 12 (ukiyo-e figures, hands, mochi pounding), text 5, quality 2, off-theme 8, weak 26, similar 9. Added 22 by pick: kagami mochi (cover), kadomatsu, osechi, shimenawa, daruma, snowdrop, two hellebores, Hoppin' John, ladybird, pickled herring, purple mochi, plum blossom, tteok, winter sunrise, camellia, pomegranate, nanten and senryō berries, kumquat x2, sunrise over snow. Titles cleaned. Final 23 (no clean 24th candidate left), verified.
