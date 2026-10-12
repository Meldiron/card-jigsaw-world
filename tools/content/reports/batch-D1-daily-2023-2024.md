# Batch D1: daily packs 2023-01 .. 2024-12

Worker D1. Shared pool specs: `tools/content/specs/daily-2023.json` and `daily-2024.json` (different topic lists,
~115 topics plus `more_topics` each; Commons only, per_topic 2, fetch_per_topic 6, author_cap 3).

Note on the spec format: the brief asked for `"id": "daily-2023"` inside the year spec, but `specs.load` keeps a
file `id` verbatim and `writer.apply` then looks up a pack row with that id, so `apply daily-2023-01` would stop with
"pack daily-2023 does not exist". The `id` field is therefore omitted; the pool name comes from the file stem.

## Pools

The first `run.sh pool daily-2023` run lost 106 of its first 129 fetched candidates to HTTP 429 from
upload.wikimedia.org (Commons throttles per User-Agent; all workers' pools share the tool's UA, so parallel
pools push the shared bucket over the limit) and the CLI cached each 429 as a permanent "bad" candidate.
Reported; the tooling agent fixed `cjw/imagecache.fetch` (pacing, Retry-After, 429 never cached as permanent)
and added `run.sh recover <pool>`. Interim scratchpad workaround scripts (a sequential fetcher that, wrongly,
sent a worker-specific UA containing the owner's email address; 23 topics were fetched through it) were deleted
on the tooling agent's request; everything from topic 24 on uses `run.sh pool` / `run.sh recover`.

## Review pass (all 24 month sheets read; rejections recorded before any apply)

| month | people | landscape | text | weak | similar | rejected | kept |
| --- | --- | --- | --- | --- | --- | --- | --- |
| daily-2023-01 | 11 | 7 | 0 | 4 | 0 | 22 | 9 |
| daily-2023-02 | 12 | 1 | 1 | 3 | 0 | 17 | 11 |
| daily-2023-03 | 14 | 6 | 3 | 3 | 0 | 26 | 5 |
| daily-2023-04 | 11 | 6 | 1 | 6 | 0 | 24 | 6 |
| daily-2023-05 | 9 | 5 | 0 | 9 | 0 | 23 | 8 |
| daily-2023-06 | 9 | 3 | 0 | 6 | 0 | 18 | 12 |
| daily-2023-07 | 13 | 5 | 2 | 5 | 0 | 25 | 6 |
| daily-2023-08 | 12 | 6 | 1 | 4 | 0 | 23 | 8 |
| daily-2023-09 | 14 | 2 | 3 | 5 | 0 | 24 | 6 |
| daily-2023-10 | 13 | 5 | 2 | 3 | 0 | 23 | 8 |
| daily-2023-11 | 14 | 3 | 1 | 5 | 0 | 23 | 7 |
| daily-2023-12 | 11 | 4 | 0 | 7 | 0 | 22 | 9 |
| daily-2024-01 | 12 | 3 | 0 | 5 | 0 | 20 | 11 |
| daily-2024-02 | 10 | 5 | 0 | 4 | 1 | 20 | 9 |
| daily-2024-03 | 16 | 2 | 3 | 6 | 0 | 27 | 4 |
| daily-2024-04 | 14 | 2 | 0 | 7 | 0 | 23 | 7 |
| daily-2024-05 | 11 | 3 | 2 | 3 | 0 | 19 | 12 |
| daily-2024-06 | 11 | 4 | 1 | 3 | 0 | 19 | 11 |
| daily-2024-07 | 18 | 1 | 0 | 4 | 0 | 23 | 8 |
| daily-2024-08 | 13 | 6 | 2 | 2 | 0 | 23 | 8 |
| daily-2024-09 | 14 | 4 | 3 | 4 | 0 | 25 | 5 |
| daily-2024-10 | 17 | 3 | 0 | 6 | 0 | 26 | 5 |
| daily-2024-11 | 19 | 0 | 1 | 5 | 0 | 25 | 5 |
| daily-2024-12 | 14 | 4 | 2 | 3 | 0 | 23 | 8 |

"people" includes painted figures, hands, feet, silhouettes and tiny figures in scenes; "weak" covers flat
sky/sea frames, monochrome ink sketches, dark interiors, laptops/desks and bokeh-only frames. Landscape
paintings that also had figures were logged as people (global reject) rather than landscape.

## Apply pass
