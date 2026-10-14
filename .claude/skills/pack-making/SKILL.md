---
name: pack-making
description: Build, repair and audit picture packs for Card Jigsaw World (library packs, world-day event packs, daily packs, AI and Abstract categories). Use for any request to add a pack, fix a pack, replace images, source freely licensed pictures, review contact sheets, or audit the catalogue against the content rules.
---

# Pack making for Card Jigsaw World

Tooling lives in `tools/content/` (run everything through `tools/content/run.sh`; it reads
`tools/content/.local-env` for the python with Pillow/numpy and the image cache directory).
The rules are in `docs/content-rules.md`; this skill is the procedure.

## The rules you enforce (owner's words, non-negotiable)

1. Never people: no faces, bodies, crowds, hands, silhouettes, painted figures. Giant packs only: small
   incidental figures may stay (about 2% of the frame at most, never the subject, the foreground or the
   focus; "a guy sitting on a bench" must go), see `docs/content-rules.md`.
2. Never repeats inside a pack: same picture, near-duplicate, same scene re-shot, same
   photographer doing the same subject. Reject all but the best one.
3. Never landscape: every image is portrait or square (height >= width).
4. Never a wall of text: signs, posters, manuscript pages, documents, maps full of labels, menus.
5. Never fewer than 20 images in a pack; aim for 24 in themed packs.
6. One clear theme per pack; every image obviously belongs to it.
7. Only free licences (CC0 / PDM / public domain / CC BY / CC BY-SA / NASA); keep author,
   source and licence on every puzzle; never claim AI art is human-made.
8. Events: choose concrete image topics for the day first, then one best image per topic.
9. Never space: no nebulae, galaxies, planets, star fields or telescope pictures (owner, 2026-10-14).
   Earth seen from orbit or the air is fine.

Plus the puzzle-quality rules: one clear subject, several distinct colours, detail in every
region (no big flat sky/water/wall), sharp, no borders or watermarks, >= 900 px short side.

## Sources

Every picture provider the tool knows, permanently recorded here. `tools/content/run.sh sources` prints
the same list with live status (active or not, licence policy, one health request each, cached 10 min).
A spec only uses the providers named in its `"sources"` list (default `["commons"]`), in that order.
API keys and client credentials live in `secrets/content-keys.env` (git-ignored, `KEY=VALUE` lines, an
empty value switches the source off). Openverse uses `OPENVERSE_CLIENT_ID` / `OPENVERSE_CLIENT_SECRET`
of a verified client registered to matejbaco2000@gmail.com. Never print or commit key values.

| Provider id | Good for | Licence policy (enforced) | Key / credential | Rate limit and pacing |
| --- | --- | --- | --- | --- |
| `commons` | Everything photographic: places, landscapes, architecture, animals, plants, food, objects; PD-Art museum uploads of paintings; AI and abstract packs (`cat:` topics) | CC0, PD, CC BY, CC BY-SA; NC/ND rejected; personality-rights files skipped | none | No daily limit with our User-Agent; downloads paced 0.7 s across all workers, 429s retried. 1280 px renditions / 960 px thumbs (Wikimedia standard thumbnail steps; spec `commons_width: 1920` opts into larger) |
| `openverse` | Extra photo variety from Flickr, StockSnap, rawpixel, iNaturalist hosts; landscapes, architecture, still subjects | CC0, PDM, CC BY, CC BY-SA | `OPENVERSE_CLIENT_ID` + `OPENVERSE_CLIENT_SECRET` (registered, verified client; bearer token cached until expiry) | Registered: 10,000 requests/day (tool budget 9,800), 100/min burst, 0.7 s spacing. Without credentials: anonymous 190/day shared by all workers |
| `met` | Paintings, still lifes, flowers in art, decorative arts, ceramics, textiles | CC0, only `isPublicDomain` objects | none | 0.1 s spacing (Met allows 80 req/s); one request per object, objects cached 60 days; URL is the original image (often 3000-6000 px, several MB) |
| `nga` | Paintings, prints, drawings, landscapes in art (`nga_classes: ["Painting"]` keeps paintings only) | CC0, only `openaccess = 1` images | none | Open data CSVs (~170 MB) downloaded once into the cache, search is local (no API calls); IIIF `!2000,2000` renditions |
| `rijks` | Dutch Golden Age paintings, flower and botanical drawings, Delftware, prints | Public domain / CC0 as stated per image | none | 0.5 s spacing; 1 search + 3 resolution requests per object (cached 60 days), so ~30-45 s per topic |
| `inat` | Animals, birds, insects, butterflies, flowers, fungi, plants: species names (`Danaus plexippus`, `snowy owl`) | CC0 or CC BY per photo, research grade only | none | 1 request/s across all workers (iNaturalist guidance); `original` photos up to 2048 px |
| `cma` | Fallback for art; small renditions (~700-900 px) | CC0 | none | 0.6 s spacing |
| `nasa` | Earth from orbit only (no space pictures, owner 2026-10-14) | Public domain (NASA) | none | 0.6 s spacing; many landscape images, fetch more |
| `pexels` | Stock photos (inactive until a key is set) | Pexels License: approved by the owner (2026-10-14); a spec opts in with `"allow_licences": ["Pexels License"]` | `PEXELS_API_KEY` (empty; free key at https://www.pexels.com/api/) | 1 s spacing; API limit 200 requests/hour, 20,000/month |
| `pixabay` | Stock photos (inactive until a key is set) | Pixabay Content License: approved by the owner (2026-10-14); a spec opts in with `"allow_licences": ["Pixabay Content License"]`; Pixabay forbids permanent hotlinking, and `apply` re-hosts every pick, as the API asks | `PIXABAY_API_KEY` (empty; free key at https://pixabay.com/api/docs/) | 1 s spacing; API limit 100 requests/minute, responses cached 24 h; standard keys get 1280 px at most |
| `unsplash` | Stock photos (inactive) | Unsplash License: approved by the owner (2026-10-14), but the provider must not run as it is: the API terms require hotlinking (see "Owner-approved new sources") | `UNSPLASH_ACCESS_KEY` (empty) | 1 s spacing; demo apps 50 requests/hour |
| `flickr` | Flickr photos under CC BY, CC BY-SA, CC0, PDM (inactive) | CC licences pass; the free API key is non-commercial: owner review first | `FLICKR_API_KEY` (empty) | 1 s spacing |
| `flickr-commons` | Flickr Commons archives (inactive) | "No known copyright restrictions": owner review + `allow_licences` | `FLICKR_API_KEY` (empty) | 1 s spacing |

Which sources to put in a spec:

| Kind of pack | `"sources"` | Notes |
| --- | --- | --- |
| Animals, birds, insects, butterflies, flowers, fungi | `["inat", "commons"]` | Topics as species (scientific or common names). iNaturalist photos often show a hand or a finger holding the animal: reject `people` on the sheet. |
| Paintings, still lifes, art, botanical art | `["met", "nga", "rijks", "cma", "commons"]` (pick 2-3) | Topics as subjects ("still life flowers", "tulip", "seascape"); museum titles become puzzle titles. Reject figures, portraits, text, and dark varnished canvases. |
| Space | none | The owner does not want space pictures (2026-10-14). Earth from orbit: `["nasa", "commons"]`. |
| Landscapes, mountains, lakes, cities, architecture, travel | `["commons", "openverse"]` | Commons quality images first; Openverse adds variety. |
| Food, objects, patterns, events, daily packs | `["commons"]`, optionally `"openverse"` | |
| AI and Abstract categories | `["commons"]` with `cat:` topics | |
| Stock photo packs | `["pexels", "commons"]` or `["pixabay", "commons"]` once the key is set, with the spec's `allow_licences` | The Pexels and Pixabay licences are approved (2026-10-14); their providers stay inactive until `PEXELS_API_KEY` / `PIXABAY_API_KEY` are in `secrets/content-keys.env`. `flickr` and `flickr-commons` still need the owner's licence review. The Unsplash License is approved, but the `unsplash` provider stays off until the owner settles the hotlinking conflict (see "Owner-approved new sources"). |

Excluded on purpose: ESA/Hubble, ESA/Webb and ESO (space, 2026-10-14). Europeana, excluded earlier, is
now approved for paintings (2026-10-14, see below). Smithsonian Open Access was excluded earlier and is now approved by the owner for pattern
packs (2026-10-14, see below). Blocked: the Art Institute of Chicago and Library of Congress image servers
sit behind Cloudflare challenges and refuse automated downloads (2026-10-14: the AIC API and IIIF server do pass slow, honest clients at 1686 px, and
the owner approved AIC, see below; the Library of Congress stays blocked).

## Owner-approved new sources (2026-10-14), not providers in the tool yet

The owner reviewed samples of new sources (`~/Downloads/new-picture-sources/`, one folder per source with
`SOURCE.txt`) and approved these, each for a kind of pack. None is a `run.sh` provider yet: adding one
means a provider in `tools/content/cjw/sources.py` (search, licence check, author and source strings,
full-size URL), registered in `run.sh sources`. Until then, pick by hand into a spec only with the owner's
go-ahead. Every licence below allows commercial use, changes and re-hosting.

| Source | Owner's use | Licence (verified 2026-10-14) | Credit | Access | Largest | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| USGS Earth as Art (EROS Center, Landsat) | drawings and patterns (abstract Earth from above) | US public domain ("USGS-authored or produced data and information are considered to be in the U.S. Public Domain"; each media page says "Public Domain."), https://www.usgs.gov/information-policies-and-instructions/copyrights-and-credits | requested, not required: "U.S. Geological Survey"; app credit "USGS EROS Center, Earth as Art (Landsat), public domain" | no API; media pages `https://www.usgs.gov/media/images/<slug>` link the S3 "Original"; collections at `/centers/eros/earth-art-1` ... `-6` | about 7200 x 7200 (collections 1-4), 3600 (5-6) | Every file is a poster: black frame, USGS and NASA logos on top, caption below. The square picture inside must be cut out with a fixed per-collection crop before hosting (logos are trademarks and must not show). Square only. About 150-200 images, most giant-board material (sample: sharp 7.9, flat 0, dark 0, alike 0). Slow S3 host (20-60 MB files). |
| ISO Republic | pictures | CC0 1.0 ("All photo and video downloads on ISORepublic.com are free for both personal and commercial use and come with a CC0 license"), https://isorepublic.com/license/ | not required; "ISO Republic, CC0" | keyless WordPress API `https://isorepublic.com/wp-json/wp/v2/media?search=<term>&per_page=50&media_type=image` (source_url = full file, media_details = sizes) | originals up to 4000 x 6000 | Curated site; respect trademarks and do not imply endorsement. Lifestyle-heavy (people, brands): normal packs only, flowers, autumn, food. Shares files with Negative Space: one pool for duplicate checks. |
| Negative Space | pictures | CC0 1.0 ("all the photographs (and their raw image files) are made available under the Creative Commons CC0 license"), https://negativespace.co/license/ | not required; "Negative Space, CC0" | keyless WordPress API: search posts (`/wp-json/wp/v2/posts?search=`), then `/wp-json/wp/v2/media?include=<ids>` | about 4000 x 6000 | Food, autumn, flowers, top-down flat-lays (sample spices 3748 x 4317 passed giant: flat 1.3%, alike 8.6%). No photographer names. |
| SMK National Gallery of Denmark | drawings (paintings, gouaches, prints) | Public Domain Mark (CC0 until 2024): "you are free to use the reproductions ... for any purpose without asking permission ... This includes commercial purposes", https://www.smk.dk/en/article/free-download-of-images/ | optional: "credit the artist ... Please also credit Statens Museum for Kunst"; store "SMK, National Gallery of Denmark, Public domain" | keyless JSON search `https://api.smk.dk/api/v1/art/search/?keys=<q>&rows=100&filters=[public_domain:true],[has_image:true]` (fields `image_width`, `image_height`, `image_iiif_id`, `image_native`, `rights`); IIIF on `iip.smk.dk` (`/full/!4096,4096/0/default.jpg`) | originals 4,000-11,000 px | The cleanest API sampled. 39,508 public-domain works with images, 4,637 paintings: Danish Golden Age flowers and fruit (Løvmand, Bärens, J.L. Jensen), landscapes. Giant sample passed: Løvmand's bouquet at the foot of a tree (4016 x 4510, flat 6.9%, alike 27.6%). |
| J. Paul Getty Museum (Open Content) | drawings (paintings) | CC0: "may be used without restriction or fees for commercial and noncommercial purposes", https://www.getty.edu/projects/open-content-program/; "The only requirement is that you not suggest or imply endorsement by the Getty" | asked: "Digital image courtesy of Getty's Open Content Program."; store "J. Paul Getty Museum, CC0" | keyless Linked Art JSON `https://data.getty.edu/museum/collection/object/<uuid>` and SPARQL `https://data.getty.edu/museum/collection/sparql`; IIIF `https://media.getty.edu/iiif/image/<uuid>/full/!4096,4096/0/default.jpg` | originals 6,000-15,000 px | About 86,000 museum images. Mostly old masters: many figures and dark backgrounds, so normal packs; giant samples failed `alike` (Courbet bouquet 49%). Never imply Getty endorsement. |
| Paris Musées (14 City of Paris museums: Petit Palais, Carnavalet, Cernuschi ...) | drawings (paintings, drawings) | CC0 for public-domain 2D works: "freely accessed and reused by anyone ... whether for commercial use or not", https://parismusees.paris.fr/en/actualite/open-content-150000-works-from-the-museum-collections-of-the-city-of-paris-freely | not required; the download charter asks to cite the museum: "Paris Musées / <museum>, CC0" | GraphQL API `https://apicollections.parismusees.paris.fr` needs a free account token; without it, open IIIF manifests `https://apicollections.parismusees.paris.fr/iiif/<id>/manifest` and original files `https://www.parismuseescollections.paris.fr/sites/default/files/atoms/images/<dir>/<file>.jpg`; the portal is JavaScript-only, and Commons links many objects | about 3,000 px, some up to 7,000 | About 150,000 CC0 works, uneven: frames in shot, posters (text), black-and-white Paris photos, fashion (figures). Check French death dates (life + 70). |
| Smithsonian Open Access (Cooper Hewitt, NMAH, SAAM) | patterns (quilts, textiles, wallpapers, design drawings) | CC0 per item (`usage.access = "CC0"`): "may be used for commercial and noncommercial purposes without fee or copyright restriction" (Terms of Use, quoted from an archive copy because si.edu blocks scripts) | not required; store the unit, e.g. "Cooper Hewitt, Smithsonian Design Museum, CC0" | `api.si.edu/openaccess/api/v1.0/` with a free api.data.gov key (1,000 requests/hour; DEMO_KEY about 10/hour), query `q=quilt AND unit_code:CHNDM AND media_usage:CC0`; bulk metadata keyless on S3 (`smithsonian-open-access`); images `https://ids.si.edu/ids/deliveryService?id=<idsId>&max=4096` (no `max` = original) | originals up to about 14,000 px | Approved by the owner on 2026-10-14 (excluded before). Whole quilts often sit on white or repeat: crop-free picks only; crazy quilts measure very sharp (17) but near the `alike` limit. Tiny embroidered motifs are fine; figurative embroidery is not. |
| Yale Center for British Art and Yale University Art Gallery (via Yale LUX) | pictures | Public domain, CC0 in each IIIF manifest: "can be downloaded and used without restrictions", https://britishart.yale.edu/using-images | encouraged, not required: "Yale Center for British Art, Public domain" / "Yale University Art Gallery, Public domain" | keyless LUX search `https://lux.collections.yale.edu/api/search/item?q={"AND":[{"text":"<q>"},{"hasDigitalImage":1}]}`; each object links a manifest `https://manifests.collections.yale.edu/{ycba,yuag}/obj/<id>` (read "Copyright Statement: Public Domain" there); IIIF `https://images.collections.yale.edu/iiif/2/<unit>:<uuid>/full/!4096,4096/0/default.jpg` | 4,000-10,000 px | Use only objects whose manifest says Public Domain ("Copyright Undetermined" and estates occur). Two requests per object; single-threaded (Yale may block excessive use). British paintings, botanicals, prints (YCBA); textiles, quilts, Asian painting (YUAG). Do not imply Yale endorsement. |
| Minneapolis Institute of Art (Mia) | drawings (paintings, Asian bird-and-flower painting, prints, textiles) | `rights_type = "Public Domain"`: "Artwork is in the public domain. Images are available for any use." (mapped to the Public Domain Mark) | not required; store "Minneapolis Institute of Art, Public domain" plus the record's credit line | keyless search `https://search.artsmia.org/rights_type:"Public Domain" AND image:valid AND image_height:>3800 AND <q>?size=100` (records carry `image_width`, `image_height`, `Cache_Location`, `Primary_RenditionNumber`); files `https://img.artsmia.org/web_objects_cache/<Cache_Location>/<Primary_RenditionNumber>_{800,full}.jpg` | originals up to about 10,000 px; only 800 px or the full original (check Content-Length first: one scroll was 54 MB) | Mia's flag follows US law: also require the artist's death year before 1956 (or anonymous or old), since some flagged works (Matisse, Hasui) are in copyright in the EU. More than 10,000 public-domain objects with images. The quilt and scroll screened failed giant `alike`. |
| Art Institute of Chicago (AIC) | drawings (paintings, prints, Asian art) | CC0 for works with `is_public_domain = true` (open-access page https://www.artic.edu/open-access/open-access-images; it blocks scripts, read it in a browser before the first pack); API docs: "we recommend only using images from artworks that are tagged as public domain" | not required; AIC asks for captions "Artist, Title, Date, The Art Institute of Chicago"; store "Art Institute of Chicago, CC0" | keyless API `https://api.artic.edu/api/v1/artworks/search` (60 requests/minute anonymous; nightly dumps on GitHub `art-institute-of-chicago/api-data`); images `https://www.artic.edu/iiif/2/<image_id>/full/1686,/0/default.jpg`. Cloudflare passes only slow, honest clients: one image at a time, 1 s apart, a truthful User-Agent plus the `AIC-User-Agent` header the docs ask for; a fake browser agent or a burst of probes gets blocked | 1686 px wide in practice (larger originals are not served): normal packs only | 62,115 public-domain artworks: impressionists, old masters, prints, Asian art. `is_public_domain` follows US law: check death dates. The docs prefer hotlinking but allow storing images that follow their scraping guidelines. |
| Europeana | paintings | per item: the record's `rights` (edm:rights) statement; search with `reusability=open` (Public Domain Mark, CC0, CC BY, CC BY-SA) and still check each item's rights URL. API metadata itself is CC0. Terms: https://www.europeana.eu/en/rights/terms-of-use | per the item's licence; name the institution: "<museum> via Europeana, <licence>" (CC BY / BY-SA: creator, provider, licence) | Search API `https://api.europeana.eu/record/v2/search.json` (free personal `wskey`, one key per application, keep it secret like the other keys; `api2demo` only for tests): `qf=TYPE:IMAGE`, `media=true`, `reusability=open`; the full file is the record's `edmIsShownBy` URL, hosted by the partner museum (sometimes only a 400-1200 px preview) | varies per partner (sample: Slovak National Gallery, 3915 x 5000) | An aggregator and a discovery tool: provider rights labels are sometimes wrong (a 1946 painting marked public domain), so check the artist's death date. Good providers found through it: Slovak National Gallery (webumenia.sk, 5000 px downloads, commercial use allowed), Mauritshuis (PDM). Dedupe against Rijksmuseum, SMK and the Finnish National Gallery. |
| Finnish National Gallery (Ateneum, Kiasma, Sinebrychoff) | paintings | CC0 per image ("All images are under CC0 license", API docs; works marked "Copyright Free" on the site): "has released over 36,000 images into the public domain under the CC0-license ... These image files can be downloaded from the website and used free of charge", https://kansallisgalleria.fi/en/photographic-service/ | requested: "Photo: Finnish National Gallery / <photographer>" (the dump has `photographer_name`) | keyless full dump `https://kokoelma.kansallisgalleria.fi/api/v1/objects` (gzipped JSON, 29 MB, 89,095 objects; search it locally); renditions `https://kokoelma.kansallisgalleria.fi/media-assets/1/jpg/{1000,2000,4000}/<mediaId>.jpg`; search API needs a free key | 4,000 px wide rendition, but it is UPSCALED when the original is narrower: pick the rendition from the dump's width and height | 36,450 objects with CC0 images, 27,938 artworks: Finnish and Nordic painting 1750-1955. Bright plein-air painting suits giant boards (Pekka Halonen's Tomatoes, 3295 x 4000 original: flat 0.3%, alike 2.3%, near the reference). Never take paid "In Copyright" works; check death dates. |
| LACMA (Los Angeles County Museum of Art) | paintings | Works marked "Public Domain High Resolution Image Available": "LACMA is providing high resolution images of these works free of charge and for use without restriction", https://www.lacma.org/about/contact-us/terms-use | requested: "Users should cite the author/artist and source ... The citation should include the URL www.lacma.org"; source string "LACMA (www.lacma.org), public domain" | no public API (the old one was retired): object pages `https://collections.lacma.org/object/<id>` list a stable `https://collections-images.lacma.org/images/<id>/<id>-1-print.tif` (convert before hosting); discovery through Commons, which links many LACMA objects | modest: about 1,000-2,500 px (sample: Flowers in a Handled Vase, 1938 x 2330 TIFF) | Only the marked works: "Protected Content" is non-commercial personal use only and needs Art Resource's written approval. LACMA does not warrant privacy or publicity rights, so the people rules apply as always. |
| Unsplash | pictures | Unsplash License, approved by the owner (2026-10-14): "download, copy, modify, distribute, perform, and use images from Unsplash for free, including for commercial purposes, without permission from or attributing the photographer or Unsplash", https://unsplash.com/license. Not allowed: selling images "without significant modification" (a picture cut into a puzzle is modified) and "compiling images from Unsplash to replicate a similar or competing service" (never build a pack catalogue that is mostly Unsplash). | not required by the licence; credit the photographer anyway: "<photographer>, Unsplash" | **Unresolved, ask the owner before any Unsplash pack:** the API terms require apps to hotlink `photo.urls` and to attribute with profile links, which conflicts with self-hosting and the Appwrite-and-Apple-only rule, so pictures fetched through the API cannot be re-hosted. The website sits behind a bot challenge. Lorem Picsum mirrors 993 Unsplash photos (the legacy packs' route) under the plain licence. | camera originals, often 4000-6000 px | No model or property releases: the people rules and brand care apply. Re-check the hotlinking question if Unsplash grants written permission or changes its API terms. |
| Pexels | pictures | Pexels License, approved by the owner (2026-10-14): "All photos and videos on Pexels can be downloaded and used for free", https://www.pexels.com/license/. Not allowed: "sell unaltered copies" (a puzzle is altered), "imply endorsement" by people or brands on the image, "redistribute or sell the photos ... on other stock photo or wallpaper platforms", use in a trademark. | not required by the licence; the API asks to "credit our photographers when possible" and to show "a prominent link to Pexels" where API requests are made (our content tool, not the app); store "<photographer>, Pexels" | tool provider `pexels` with `PEXELS_API_KEY`; files on the public CDN `https://images.pexels.com/photos/<id>/pexels-photo-<id>.jpeg`; the website is behind Cloudflare | camera originals, often 4000-6000 px (recompressed) | No hotlinking rule: download and re-host as always. Never add a wallpaper or save-picture feature for Pexels pictures. People-heavy, shallow focus, vendors and price tags at markets: review sheets carefully. Giant packs occasionally (sample: dried rosebuds stall, 4279 x 6419, flat 4.8%, alike 9.9%, soft top quarter). |
| Pixabay | pictures | Pixabay Content License, approved by the owner (2026-10-14): use for free, "without having to attribute the author", "Modify or adapt Content into new works", https://pixabay.com/service/license-summary/. Not allowed: selling or distributing Content "on a Standalone basis" (no creative effort applied; a puzzle pack is not standalone), use with recognisable people in a bad light, trademarks; terms section 8 and the API forbid "Systematic mass downloads" and scraping. | not required; the API asks to "show your users where the images ... are from" when search results are shown (our tool only); store "<user>, Pixabay" | tool provider `pixabay` with `PIXABAY_API_KEY`; re-hosting is required ("download them to your server first") | 1280 px with a standard key (normal boards only, just above the 900 px floor); originals only with approved full API access | Keep pools small and human-paced (one pack at a time, normal `fetch_per_topic`), never a bulk run. Lots of AI-generated and heavy HDR images: tag AI as AI, reject HDR halos. No giant packs. |
| NPS NPGallery | pictures | per asset, `ConstraintsInformation` in the search JSON; staff photos are US public domain (https://www.nps.gov/aboutus/disclaimer.htm) | appreciated: "NPS / <photographer>, public domain". Paid packs must carry "No claim to original U.S. Government works" (17 U.S.C. 403) in the app's credits. | `https://npgallery.nps.gov/SearchResults?keyword=<term>&PageSize=48` (results JSON in the page), files `https://npgallery.nps.gov/GetAsset/<AssetID>/original.jpg` | camera originals 4000-8700 px | "Public domain" tags are unreliable for contest, volunteer and outside photographers: keep only assets whose PhotoCredit names an NPS employee. Mostly landscape orientation; no Arrowhead logo, signs or uniforms; many visitors in frame. Geology textures can pass giant (Canary Spring: flat 1%, alike 15.6%). Slow site. |


Optional spec fields for sources: `source_limit` (results per topic per provider), `nga_classes`,
`commons_width` (1920 or 3840 renditions instead of 1280), `allow_licences` (owner-approved licences only).

Evaluated on 2026-10-14 and not chosen (do not research again without a new reason): Library of Congress, NYPL, NOAA and USFWS (bot walls or captioned plates), Nationalmuseum Sweden (no
search, mixed licences; its release is on Commons), Philadelphia Museum of Art (educational use only), StockSnap
(Cloudflare; reaches us through Openverse), Life of Pix, Skitterphoto and Magdeleine (unclear or mixed licences),
rawpixel (Cloudflare, editorial-only items), the Public Domain Review (an index), Old Book Illustrations,
Biodiversity Heritage Library and Te Papa (plates on paper with captions), Auckland Museum (no image route),
ESA/Hubble, ESA/Webb and ESO (space). Leads not yet sampled: ESA Copernicus "Earth from Space" (CC BY-SA 3.0 IGO,
mostly landscape).

## Pack spec (tools/content/specs/<packId>.json)

```json
{
 "id": "pack-owls", "name": "Owls", "category": "Animals",
 "description": "Barn, snowy, eagle and pygmy owls, mostly staring straight back at you.",
 "price": "coins", "priceCoins": 500,            // or "free" / "tickets" + priceTickets (new packs only)
 "target": 24, "per_topic": 1, "fetch_per_topic": 4, "author_cap": 2,
 "sources": ["commons"], "commons_quality": true, "openverse_category": "photograph",
 "topics": ["snowy owl portrait", "barn owl in flight", "great horned owl", "...20 to 30 of these"],
 "more_topics": ["..."],                             // used by `pool --more` when the pool runs dry
 "allow_words": ["hand"],                            // keyword-filter exceptions, rarely needed
 "accent": "#B45309", "cover": "https://...",       // optional; cover defaults to the first puzzle
 "accent_from_cover": true                           // new packs: derive accent from the cover's dominant colour
}
```

Topics are specific nouns a search engine understands ("Eibsee Zugspitze lake", not "nice
lake"). For events write 20–24 topics that are objects, dishes, plants, places or symbols of the
day. Daily packs share `specs/daily.json` (pool `daily`): generic, pleasant, varied subjects.
Category topics (`"cat:AI-generated images of nature"`) list a Commons category instead of
searching.

## Pipeline (per pack)

```
tools/content/run.sh dump                      # snapshot the live catalogue (once per session)
tools/content/run.sh audit [--pack ID ...]     # rule violations -> tools/content/reports/audit-<stamp>.md
tools/content/run.sh sheet PACK --puzzles-only # contact sheet of what is in the pack now
tools/content/run.sh reject PACK p03 p07 --reason people      # p = position on the puzzles sheet
tools/content/run.sh pool PACK                 # source candidates from the spec topics (2-3 min)
tools/content/run.sh sheet PACK --candidates-only
tools/content/run.sh reject PACK c12 c15 --reason off-theme   # c = candidate key
tools/content/run.sh apply PACK --pick c02 c05 ... [--no-auto] [--target 24] [--dry]
tools/content/run.sh sheet PACK --puzzles-only # final check: read it again
tools/content/run.sh newpack PACK              # create the pack row for a new spec (before pool/apply)
tools/content/run.sh status PACK ...           # counts, pool size, openverse budget
tools/content/run.sh sources                   # providers: active?, licence policy, live health
```

Daily months ahead of time: `tools/content/run.sh newdaily 2027-03 [2027-04 ...] [--pick ...]` creates
the `daily-YYYY-MM` pack row and one dated puzzle per day from the pool of the daily spec whose
`"months"` list holds that month (`specs/daily-2027a.json`, `daily-2027b.json`); otherwise
`specs/daily-YYYY.json`. The app hides a daily month until its first day and an event pack until 3
days before it opens, so creating content a year ahead is safe. Re-run `tools/store/apply_pack_prices.py`
afterwards.

Reject reasons: `people`, `text`, `landscape`, `duplicate`, `quality` (global: the image is never
used again anywhere) and `off-theme`, `weak`, `similar` (scoped to this pack only).

`apply` deletes rejected puzzles, adds explicit picks first, then auto-fills round-robin over
topics until `target`, skipping near-duplicates of kept images, authors over `author_cap`,
landscape and small images. For daily packs (`daily-YYYY-MM`) it replaces rejected puzzles in
place (same id, date, order). It syncs `imageCount`, cover, blurhash, accent and the event cover.

## Visual review (you are the last filter)

Read every contact sheet you produce. Look at each cell and reject:

- any person, even tiny or from behind, hands, reflections of people, painted figures;
- text-dominated images; borders; watermarks; collages; screenshots; black-and-white;
- the same scene twice (watch the author under each thumbnail: same author + same subject = same scene);
- anything that does not obviously match the pack name; images where the subject is a speck;
- flat images (half sky, half water, blurred backgrounds dominate), dark/underexposed images.
- line drawings, sketches, pale prints and single-tone artworks on plain paper (one colour plus
  thin lines is unsolvable); reason `quality`.

Prefer explicit `--pick` lists over auto-fill for anything the owner will see first (covers,
event packs). After `apply`, read the final puzzles sheet; the job is not done until that sheet is
clean and the count is >= 20.

## Durable progress and resuming

`tools/content/reports/state.json` is the checkpoint: one entry per pack (`status` pending →
audited → fixed → verified, `removed`/`added`/`puzzles` counts, `last_step`, timestamp). The CLI
updates it automatically (`reject` → audited, `apply`/`clone` → fixed, `verify` → verified,
`newpack` → pending). Per-pack logs are in `tools/content/reports/packs/<packId>.log`, the global
log in `reports/changes.jsonl`, rejections in `state/rejects.json`, provenance in
`state/provenance.json`. All commands are idempotent (re-running `apply` on a finished pack
changes nothing; `newpack` updates instead of duplicating).

If the scratch folder is gone (reboot, new machine): progress is safe in git
(`tools/content/reports/state.json`, rejects and provenance); only the download cache and the venv
lived in the temporary scratch folder. Recreate them and point `tools/content/.local-env` at them:

```
python3 -m venv ~/.venvs/cjw-content && ~/.venvs/cjw-content/bin/pip install -r tools/content/requirements.txt
# .local-env: export CJW_PY=~/.venvs/cjw-content/bin/python ; export CJW_CONTENT_CACHE=~/.cache/cjw-content
```

The cache refills itself on the next runs (NGA data and thumbnails download again).

To resume after an interruption:

```
tools/content/run.sh resume                 # board + next pending/audited packs with their last step
tools/content/run.sh resume --prefix evpack- --next 20 --auto   # also builds pools for packs that have a spec but no pool
```

then continue each listed pack from its `last_step` with the per-pack pipeline above, finish with
`run.sh verify PACK`, and every ~10 packs or 30 minutes run `run.sh checkpoint` (commits and pushes
only `tools/content`, this skill and the two content docs; never other paths).

## Batching etiquette

- Workers share Commons, Appwrite and the state files; keep one pack at a time per worker and do
  not run `dump` while others are writing (use `status`/`sheet`, which refresh one pack).
- Log every pack you finish in `tools/content/reports/<batch>.md`: id, removed (with reasons),
  added, final count, anything unresolved. `reports/changes.jsonl` is written automatically.
- Never touch `lib/`, `ios/`, other tools, git. Only `tools/content/**` and the database.

## Re-theming a pack

If a pack cannot satisfy the rules under its current theme (e.g. "Portraits" needs people,
"Medieval Manuscripts" is text, "Vintage Posters" is text), rewrite its spec with a new name and
description that keeps the pack id, note it in the batch report, and rebuild the content.

## New categories

AI packs: Commons categories of AI-generated images (nature, animals, architecture, food,
abstract art, fantasy, science fiction, paintings, pixel art, woodcuts, line drawings, textures,
Moon, objects, geometric shapes, clothing, beverages, utopias, dystopias, paleoart). Author is
"<prompter> / <generator>", source "Wikimedia Commons, Public domain (AI-generated)".
Abstract packs: fluid ink, geometric minimal, light leaks, macro textures, kaleidoscope, bokeh,
smoke, topographic, paper collage, brutalist concrete, stained glass, neon lines, marbling,
fractals, crystal macro, glitch, dunes, water ripples, frost, rust. Search Commons with the
material/phenomenon words ("ink in water macro", "fractal flame", "paper marbling", "hoarfrost
macro") and reject anything representational.

## Titles (added during the resume)

Puzzle titles come from the search topic. iNaturalist pictures are now titled with the species' common name. If a title is wrong (wrong species, filename-like, scientific name), fix it with
`tools/content/run.sh retitle PUZZLE_ID New title`.


## Pictures are self-hosted

Rows never reference third-party images (owner rule, 2026-10-13). `apply`, `clone` and cover updates
upload each picture to the Appwrite Storage bucket `puzzle-images` first (`cjw/host.py`, key in
`secrets/appwrite-storage-key.txt`) and write our `/view` and `/preview` URLs; the original address goes
to `sourceUrl` / `coverSourceUrl`. The catalogue snapshot swaps the source URL back into `imageUrl` /
`coverUrl`, so rejects, duplicates and the image cache keep working on source addresses. After any manual
row edit, run `tools/content/run.sh host` (or `--pack ID`) to host anything that slipped through. Source
URLs may now be up to 2000 characters (the old 512 limit applied to row URLs).
