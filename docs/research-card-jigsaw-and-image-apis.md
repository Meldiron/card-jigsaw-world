# Research: card-jigsaw mechanics and free image APIs

Compiled 2026-10-11 while designing Card Jigsaw World.

## Card-jigsaw genre: two families

1. **Jigsaw solitaire / snap-group games** (Jigsolitaire, Jigsawcard Solitaire, Cardscapes, Jigmatch, Jigsaw Card by Finger Media, Jigsortscapes, Jigtile). Cards start scattered on a free board; dragging a card next to a matching-edge card snaps them into a group that moves as one. Hidden rules (small card shrinks large card), lives systems and auto-advance after completion are the top complaints.
2. **Grid tile games** (Picture Tile Swap, SlideMaster 15-puzzle, Grid Jigsaw, Jigsort). Tiles sit on a fixed grid and are swapped, slid into a gap or moved with restricted directions.

Recurring player pain points across reviews: image repetition before level 100-250, confusing hidden rules, punishment systems in a "relaxing" genre, completed picture vanishing immediately, heavy ads with no removal purchase. Praised: no timer, 2-5 minute sessions, one-handed play.

## Chosen mechanic for Card Jigsaw World: swap-to-lock

- Image cut into a fixed grid of cards, all on the board from the start, no rotation.
- Tap a card then tap another to swap, or drag a card onto another and release. Same action, so one-handed play works.
- A card landing in its true cell **locks**: haptic, brightness pulse, settles into the board, and edges toward locked neighbours dissolve so solved regions fuse into the picture. Locked cards cannot move.
- Chain moment: a swap that locks both cards fires a bigger ripple and an "x2" badge.
- Tiers keep columns <= 6 so cards stay >= 55pt wide on a 390pt iPhone: 3x3, 3x4, 4x4, 4x5, 5x5, 5x6, 6x6, 6x8.
- Par = minimum swaps = n - cycles in the shuffle permutation. Stars: 3 at <= par+1, 2 at <= par x 1.5, 1 for completion. Timer optional.
- Boosters: Peek (show full image), Magic Lock (place one wrong card), Undo (free), Highlight.
- Win: gutters dissolve, image zooms, sparse confetti, credit line, stays until tapped.

## Free image sources

| Source | Key | Hotlink | Cache/bundle | Notes |
|---|---|---|---|---|
| Lorem Picsum | none | yes | yes (Unsplash license) | `https://picsum.photos/id/{id}/900/1200`, `/seed/{seed}/w/h`, `/v2/list` for attribution. Ideal for dev; uncurated. |
| Art Institute of Chicago | none | yes (CORS, IIIF) | yes (CC0) | `https://api.artic.edu/api/v1/artworks/search?q=landscape&query[term][is_public_domain]=true&fields=id,title,artist_display,image_id`; image `https://www.artic.edu/iiif/2/{image_id}/full/843,/0/default.jpg`. |
| Cleveland Museum of Art | none | yes | yes (CC0) | `https://openaccess-api.clevelandart.org/api/artworks/?q=landscape&cc0=1&has_image=1&type=Painting` -> `data[].images.web.url`. |
| The Met | none | yes | yes (CC0 when isPublicDomain) | Two-step search then `/objects/{id}` -> `primaryImageSmall`. |
| NASA Image Library | none | yes | yes (credit NASA) | `https://images-api.nasa.gov/search?q=nebula&media_type=image`. |
| Wikimedia Commons | none (User-Agent required) | discouraged | per-file licence | Featured pictures category; use standard thumb widths. |
| Pexels | free key | yes | yes | Best production source. `https://api.pexels.com/v1/search?query=mountain&orientation=portrait&size=large`. Credit photographer + Pexels. |
| Pixabay | free key | no (24h) | download server side | `image_type=photo&editors_choice=true`. |
| Unsplash | key + approval | mandatory | no | Strict hotlink + attribution rules; poor fit for offline packs. |
| Openverse | optional | mixed | per-licence | Needs curation. |
| Smithsonian | api.data.gov key | yes | CC0 | Degraded service in 2026; lowest reliability. |

**Recommendation:** Picsum for the dev catalog, Art Institute of Chicago and NASA for CC0 packs that can ship, Pexels behind an Appwrite Function proxy for production content. Store photographer, source URL and licence next to every image so the win screen can credit it.
