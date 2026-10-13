// Catalogue snapshot (Appwrite Function, daily schedule).
//
// Writes packs, puzzles and events to one gzipped JSON file in the `catalog` bucket and points
// `meta/catalog` at it. The app starts from that file and reads only rows changed since, instead of
// reading the whole catalogue from the database (each row returned is a billed read).
//
// A run starts from the previous snapshot and reads only what changed: rows updated since its
// watermarks, and every puzzle of a pack whose row changed (the content tool updates the pack row
// whenever it removes or replaces puzzles, so this catches deletions). Every FULL_EVERY_DAYS, or when
// executed with path /full, it reads everything again (rows deleted by hand in the console).
import { gunzipSync, gzipSync } from 'node:zlib';
import { Client, TablesDB, Storage, ID, Query } from 'node-appwrite';
import { InputFile } from 'node-appwrite/file';

const DB = process.env.APPWRITE_DATABASE_ID || 'cjw';
const BUCKET = 'catalog';
const META_TABLE = 'meta';
const POINTER = 'catalog';
const TABLES = ['packs', 'puzzles', 'events'];
const FULL_EVERY_DAYS = 7;
const OVERLAP_MS = 10_000;
const KEEP_FILES = 2;
const PAGE = 500;
const MAX_QUERY_VALUES = 100;
// Columns the app never reads: Appwrite internals and the content tool's original picture addresses.
const DROP = ['$permissions', '$sequence', '$tableId', '$databaseId', '$createdAt', 'sourceUrl', 'coverSourceUrl'];

const clean = (row) => Object.fromEntries(Object.entries(row).filter(([k]) => !DROP.includes(k)));

const latest = (rows, start = null) => rows.reduce((max, r) => (!max || r.$updatedAt > max ? r.$updatedAt : max), start);

export default async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(req.headers['x-appwrite-key'] ?? '');
  const tables = new TablesDB(client);
  const storage = new Storage(client);
  let reads = 0;

  const listAll = async (tableId, queries = []) => {
    const out = [];
    let cursor = null;
    while (true) {
      const page = await tables.listRows({
        databaseId: DB,
        tableId,
        queries: [...queries, Query.orderAsc('$id'), Query.limit(PAGE), ...(cursor ? [Query.cursorAfter(cursor)] : [])],
        total: false,
      });
      out.push(...page.rows);
      reads += page.rows.length;
      if (page.rows.length < PAGE) return out.map(clean);
      cursor = page.rows[page.rows.length - 1].$id;
    }
  };

  const previous = async () => {
    try {
      const pointer = await tables.getRow({ databaseId: DB, tableId: META_TABLE, rowId: POINTER });
      reads += 1;
      const bytes = await storage.getFileDownload({ bucketId: BUCKET, fileId: pointer.fileId });
      const snap = JSON.parse(gunzipSync(Buffer.from(bytes)).toString('utf8'));
      return snap.v === 1 ? snap : null;
    } catch (e) {
      log(`no previous snapshot: ${e.message}`);
      return null;
    }
  };

  try {
    const now = new Date();
    const prev = await previous();
    const full = req.path === '/full' || !prev || now - new Date(prev.fullAt) > FULL_EVERY_DAYS * 86_400_000;
    let snap;
    let changes = 0;

    if (full) {
      snap = { v: 1, fullAt: now.toISOString(), tables: {} };
      for (const t of TABLES) {
        const rows = await listAll(t);
        snap.tables[t] = { watermark: latest(rows), rows };
      }
      changes = -1;
    } else {
      const fresh = {};
      for (const t of TABLES) {
        const since = new Date(new Date(prev.tables[t].watermark ?? 0).getTime() - OVERLAP_MS).toISOString();
        fresh[t] = await listAll(t, [Query.greaterThanEqual('$updatedAt', since)]);
      }
      const stamps = new Map(prev.tables.packs.rows.map((p) => [p.$id, p.$updatedAt]));
      const changedPacks = fresh.packs.filter((p) => stamps.get(p.$id) !== p.$updatedAt).map((p) => p.$id);
      const repacked = [];
      for (let i = 0; i < changedPacks.length; i += MAX_QUERY_VALUES) {
        repacked.push(...(await listAll('puzzles', [Query.equal('packId', changedPacks.slice(i, i + MAX_QUERY_VALUES))])));
      }
      snap = { v: 1, fullAt: prev.fullAt, tables: {} };
      for (const t of TABLES) {
        const byId = new Map(prev.tables[t].rows.map((r) => [r.$id, r]));
        const incoming = t === 'puzzles' ? [...fresh[t], ...repacked] : fresh[t];
        if (t === 'puzzles' && changedPacks.length) {
          const dropped = new Set(changedPacks);
          for (const [id, r] of byId) if (dropped.has(r.packId)) byId.delete(id);
          changes += 1;
        }
        for (const r of incoming) {
          if (JSON.stringify(byId.get(r.$id)) !== JSON.stringify(r)) changes += 1;
          byId.set(r.$id, r);
        }
        snap.tables[t] = { watermark: latest(incoming, prev.tables[t].watermark), rows: [...byId.values()] };
      }
      if (changes === 0) {
        log(`unchanged since ${prev.builtAt}; ${reads} rows read`);
        return res.json({ ok: true, unchanged: true, reads });
      }
    }

    snap.builtAt = now.toISOString();
    const gz = gzipSync(JSON.stringify(snap), { level: 9 });
    const file = await storage.createFile({ bucketId: BUCKET, fileId: ID.unique(), file: InputFile.fromBuffer(gz, 'catalog.json.gz') });
    await tables.upsertRow({ databaseId: DB, tableId: META_TABLE, rowId: POINTER, data: { fileId: file.$id, builtAt: snap.builtAt, fullAt: snap.fullAt } });

    const files = await storage.listFiles({ bucketId: BUCKET, queries: [Query.orderDesc('$createdAt')] });
    for (const f of files.files.slice(KEEP_FILES)) await storage.deleteFile({ bucketId: BUCKET, fileId: f.$id });

    const counts = Object.fromEntries(TABLES.map((t) => [t, snap.tables[t].rows.length]));
    log(`${full ? 'full' : 'incremental'} snapshot ${file.$id}: ${JSON.stringify(counts)}, ${gz.length} bytes, ${reads} rows read`);
    return res.json({ ok: true, full, fileId: file.$id, counts, bytes: gz.length, reads });
  } catch (e) {
    error(`snapshot failed: ${e.message}`);
    return res.json({ ok: false, error: e.message }, 500);
  }
};
