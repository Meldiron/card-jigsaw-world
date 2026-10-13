# Catalogue sync

The catalogue (packs, puzzles, events) is about 8,700 rows. Appwrite bills every row a query returns as
one read, so reading it whole on each launch cost about 8,700 reads per launch. Since 2026-10-13 the app
uses snapshot + delta sync instead: a launch reads about 30 rows.

## How it works

1. **Snapshot (daily).** The function `catalog-snapshot` (`functions/catalog-snapshot`, Node 22, cron
   `0 3 * * *`) writes the whole catalogue to one gzipped JSON file (about 1 MB) in the public bucket
   `catalog`, and points the row `meta/catalog` (`fileId`, `builtAt`, `fullAt`) at it. It keeps the
   newest two files. A run starts from the previous file and reads only rows updated since its
   watermarks, plus every puzzle of a pack whose row changed; if nothing changed it writes nothing.
   Every 7 days (or when executed with path `/full`) it reads all three tables again.
2. **Base (device).** On first launch and every 7 days, `CatalogSync` (`lib/state/catalog_sync.dart`)
   reads the pointer row (1 read) and downloads the file (bandwidth, not reads). Without a snapshot it
   reads the tables whole, as before.
3. **Delta (every launch and pull to refresh).** Per table, rows with `$updatedAt` at or after the newest
   row on the device, minus a 10-second overlap for writes that landed out of order. A pack whose row
   changed has its puzzles read again whole, which is how removed puzzles disappear.
4. **Offline.** The copy on the device (`catalog` in SharedPreferences / localStorage) is served when the
   server cannot be reached.

## Rules

- **Whoever removes or replaces puzzles must change the pack row.** Appwrite leaves `$updatedAt` alone
  on an update that changes nothing, so the content tool sets `packs.puzzlesUpdatedAt` in
  `finalize_pack` every time (apply and clone call it). Rows deleted by hand in the console reach
  devices with the next weekly base after the next full snapshot.
- **After a schema change** (a new column, a new default), run the function with path `/full`, so the
  file carries the new column on every row:
  `appwrite functions create-execution --function-id catalog-snapshot --path /full`.
- **Deploy** the function from `functions/` with the Appwrite CLI (`--code catalog-snapshot
  --entrypoint src/main.js --commands "npm install" --activate`). Its scopes are rows.read, rows.write,
  files.read, files.write.
- Check it: `appwrite functions list-executions --function-id catalog-snapshot`, or execute it; the
  response names the file, the row counts and how many rows the run read.

## Measured (2026-10-13, live)

| | Rows read |
| --- | --- |
| Launch before (whole tables) | 8,741 |
| First launch (snapshot + delta) | 26, plus 1 pointer read and a 0.96 MB download |
| Next launch | 26 |
| Snapshot run, nothing changed | 39 (no new file) |
| Snapshot run, one pack changed | 71 |
| Full snapshot (weekly) | 8,742 |

`integration_test/catalog_sync_test.dart` checks this against the live tables (snapshot + delta equals
the tables read whole); `test/catalog_sync_test.dart` covers the cases offline.
