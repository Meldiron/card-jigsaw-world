# Brief for content workers (pack repair / creation)

Read first: `.claude/skills/pack-making/SKILL.md` and `docs/content-rules.md` (repo root
`/Users/matejbaco/Desktop/card-jigsaw-world`). Run every command from the repo root as
`tools/content/run.sh <cmd>` (it sources `tools/content/.local-env`). Other workers run in parallel on
other packs and another agent edits the app: touch only `tools/content/specs/*.json` (your packs),
`tools/content/reports/<your-batch>.md`, and the database through the CLI. Never run `run.sh dump`,
never use git, never edit code under `tools/content/cjw` (report bugs in your report instead).

## Standard per pack

1. `run.sh sheet PACK --puzzles-only` → Read the PNG. Reject with
   `run.sh reject PACK p03 p07 --reason people` (reasons: people, text, landscape, duplicate,
   quality = global; off-theme, weak, similar = this pack only). Be strict: a tiny person, a hand, a
   reflection, a painted figure, a sign, a page of text, the same scene twice, a picture that does
   not clearly show the pack's subject, a dark or flat picture: all out.
2. Write `tools/content/specs/PACK.json` (keep `id`, `name`, `category` unless re-theming):
   a real one-sentence `description` (no emoji, no marketing fluff), 24–30 specific `topics`
   (proper nouns, species, dishes, named places; what a search engine understands), optional
   `more_topics`, `per_topic` 1, `fetch_per_topic` 4, `author_cap` 2, `target` 24. Optional
   `quality_deepcat` such as `"Quality images of food"`, `"Quality images of plants"`,
   `"Quality images of landscapes"`, `"Quality images of architecture"`, `"Quality images of animals"`
   makes the first search pass use Commons' curated tree.
3. `run.sh pool PACK` (2–4 min). If it reports fewer than ~30 usable candidates, add
   `more_topics` and run `run.sh pool PACK --more`.
4. `run.sh sheet PACK --candidates-only` → Read every sheet. Reject bad candidates (`c12 c15 ...`).
   Watch the author line: same author + same subject = same scene, keep one. Reject
   snapshot-grade pictures (flash, clutter, cut-off subject, blur), anything with a person,
   text, borders, collages, black-and-white, and anything off-theme.
5. `run.sh apply PACK --target 24` (auto-fills one per topic round-robin from what you did not
   reject) or `run.sh apply PACK --no-auto --pick c02 c05 ...` to choose exactly.
6. `run.sh sheet PACK --puzzles-only` → Read it. If anything is wrong: reject it and `apply` again.
   Finished = clean sheet, count >= 20 (24 preferred), coherent theme, good cover (first image or
   `"cover"` in the spec; run `run.sh finalize PACK` after changing the spec's cover/description).
7. Run `run.sh verify PACK` (marks the pack verified in reports/state.json when the audit is clean
   and the count is >= 20; otherwise it prints what is still wrong). Then append to your report: pack id, what was removed and why (counts per reason), what was added,
   final count, anything unresolved.

## Standards for what a good puzzle picture is

Clear single subject that fills the frame, several distinct colour regions, detail in every part of
the frame (no half-empty sky/water/wall), sharp, portrait or square, no borders/watermarks/captions.
Prefer Commons Quality/Featured images (the pool sorts them first).

## Event packs

Name stays; description: `A limited pack for <Day> (<date>). <What is inside>, playable for one
week.` Write 20–24 topics that are objects, dishes, plants, animals, places or symbols of the day,
never people, then one best image per topic (`per_topic` 1). The pack is free. If the pack exists
for 2026 and 2027, finish the 2026 one and run `run.sh clone evpack-x-2026 evpack-x-2027`.

## Re-theming

When a theme cannot satisfy the rules (needs people or text), keep the pack id and give it a new
`name` + `description` in the spec that fits the category; note it in the report.

## Rate limits

Commons is shared by all workers: one pack at a time, no parallel pools. Openverse now runs on a
verified registered client (about 9,800 requests per day shared by everyone, 100 per minute), so it
may be added to `sources` where it fits. Run `tools/content/run.sh sources` to see which providers are
active and read the skill's Sources section for which ones suit which pack. For art prefer `nga` and
`rijks` (IIIF, sized renditions) over `met`, whose images are multi-megabyte originals.

## Throttling (added after the first wave)

`upload.wikimedia.org` returns HTTP 429 when many workers download at once. The fetcher now paces
itself, honours `Retry-After` and never caches a 429 as permanent. If a `pool` run reports few
usable candidates, run `tools/content/run.sh recover PACK` to re-fetch throttled candidates before
adding topics. Do not write your own fetchers and do not change the User-Agent.

## Durability (added after the first wave)

`tools/content/reports/state.json` tracks every pack (pending / audited / fixed / verified) and is
updated by the CLI; `run.sh resume --prefix <yourprefix>` shows what is left. Run `run.sh verify PACK`
as the last step of every pack. The coordinator commits and pushes `tools/content` every 30 minutes;
do not run git yourself.

## Resuming and budget (added after the overnight interruption)

- `tools/content/run.sh resume --batch <B> --next 40` lists your batch's remaining packs with their
  last step, whether a spec exists and how many usable candidates the pool has. Continue each pack
  from that state; everything is idempotent (re-running `pool` only adds, `apply` only fills, `verify`
  only marks).
- Run `pool`, `recover` and `apply` in the FOREGROUND (Bash timeout 600000). If a pool run hits the
  timeout, simply run it again: finished topics are cheap to repeat. Do not start background jobs
  with monitors; every wake-up costs the shared API budget, which is what stopped the first wave.
- Read each contact sheet once; decide; move on. Keep report entries to one line per pack.

## Titles (added during the resume)

Puzzle titles come from the search topic. iNaturalist pictures are now titled with the species' common name. If a title is wrong (wrong species, filename-like, scientific name), fix it with
`tools/content/run.sh retitle PUZZLE_ID New title`.
