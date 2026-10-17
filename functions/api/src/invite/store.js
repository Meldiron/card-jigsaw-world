// Invite cards in Storage: bucket `invite-cards` (public read, written only by this function). A
// card depends only on the picture and the board, never on the players, so it is kept by a key of
// those (and the week, so a kept card is never older than a week when a page names it); games on the
// same picture and board share it. The hourly run deletes cards older than ten days (`cleanCards`).
import { createHash } from 'node:crypto';
import { Client, TablesDB, Storage, Query } from 'node-appwrite';

export const BUCKET = 'invite-cards';

/// Bump to draw every card again (its key changes).
export const CARD_VERSION = 1;

/// The address people's apps fetch the card from (the endpoint inside the function may differ).
export const PUBLIC_API = 'https://fra.cloud.appwrite.io/v1';

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
const PICTURE_WIDTH = 640;
export const KEEP_MS = 10 * 24 * 60 * 60 * 1000;
const DB = process.env.APPWRITE_DATABASE_ID || 'cjw';

export function services(req) {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(req.headers['x-appwrite-key'] ?? '');
  return { tables: new TablesDB(client), storage: new Storage(client) };
}

/// The card's file id for a game's board (32 hex characters).
export function cardId({ puzzleId, grid, painting }, now = Date.now()) {
  const week = Math.floor(now / WEEK_MS);
  return createHash('sha256').update(`v${CARD_VERSION}|${puzzleId}|${grid}|${painting === true ? 1 : 0}|${week}`).digest('hex').slice(0, 32);
}

export const cardUrl = (id, project = process.env.APPWRITE_FUNCTION_PROJECT_ID) => `${PUBLIC_API}/storage/buckets/${BUCKET}/files/${id}/view?project=${project}`;

/// Bucket and file of a picture in our Storage (`.../storage/buckets/<b>/files/<f>/view?...`), or null.
export function pictureFile(url) {
  const m = /\/storage\/buckets\/([A-Za-z0-9._-]{1,36})\/files\/([A-Za-z0-9._-]{1,36})\//.exec(String(url ?? ''));
  return m ? { bucketId: m[1], fileId: m[2] } : null;
}

const gone = (e) => e?.code === 404;
const inflight = new Map();

/// The swaps a card shows follow its key, so a card drawn twice comes out the same.
const seedOf = (id) => parseInt(id.slice(0, 8), 16);

/// Draws a card in a worker thread (worker.js), so the function's other calls do not wait; on the
/// main thread if a worker cannot start.
async function draw(args) {
  let Worker;
  try {
    ({ Worker } = await import('node:worker_threads'));
  } catch (_) {
    Worker = null;
  }
  if (!Worker) return (await import('./card.js')).renderCard(args);
  return new Promise((resolve, reject) => {
    const w = new Worker(new URL('./worker.js', import.meta.url), { workerData: args });
    w.once('message', (m) => resolve({ jpeg: Buffer.from(m.jpeg), cells: m.cells }));
    w.once('error', reject);
    w.once('exit', (code) => code !== 0 && reject(new Error(`invite card worker stopped (${code})`)));
  });
}

/// The card of [game]'s board in Storage, drawn now if it is not there yet. Returns its address and
/// whether this call drew it. [puzzle]: the game's `puzzles` row when the caller has it.
export async function ensureCard({ tables, storage }, game, puzzle = null) {
  const id = cardId(game);
  if (inflight.has(id)) return inflight.get(id);
  const job = (async () => {
    const t = Date.now();
    try {
      await storage.getFile({ bucketId: BUCKET, fileId: id });
      return { id, url: cardUrl(id), made: false, ms: Date.now() - t };
    } catch (e) {
      if (!gone(e)) throw e;
    }
    const row = puzzle ?? (await tables.getRow({ databaseId: DB, tableId: 'puzzles', rowId: game.puzzleId }));
    const file = pictureFile(row.imageUrl);
    // Only pictures of the catalogue's own bucket (the co-op calls refuse the others).
    if (!file || file.bucketId !== 'puzzle-images') throw new Error(`invite card: picture not in puzzle-images (${game.puzzleId})`);
    // 640 px wide: about what the board needs (at most 620 x 520) and more than the blurred
    // backdrop does; a PNG decodes quickly here (Node's zlib).
    const image = Buffer.from(await storage.getFilePreview({ bucketId: file.bucketId, fileId: file.fileId, width: PICTURE_WIDTH, output: 'png' }));
    const fetched = Date.now() - t;
    const { parseGrid } = await import('./tiling.js');
    const board = parseGrid(game.grid);
    if (!board) throw new Error(`invite card: board ${game.grid}`);
    const card = await draw({ image, board, painting: game.painting === true, seed: seedOf(id) });
    const drawn = Date.now() - t - fetched;
    const { InputFile } = await import('node-appwrite/file');
    try {
      await storage.createFile({ bucketId: BUCKET, fileId: id, file: InputFile.fromBuffer(card.jpeg, 'card.jpg') });
    } catch (e) {
      // Drawn at the same moment elsewhere: theirs is the same card.
      if (e?.code !== 409) throw e;
    }
    return { id, url: cardUrl(id), made: true, ms: Date.now() - t, fetched, drawn, bytes: card.jpeg.length };
  })();
  inflight.set(id, job);
  try {
    return await job;
  } finally {
    inflight.delete(id);
  }
}

/// Starts drawing the card of a new game's board without waiting (after answering `/coop/create`):
/// the invite is shared a moment later, and its page then finds the card. Drawing takes about 2 s
/// of the runtime's half CPU (measured 2026-10-17), which slows the instance's other calls while it
/// runs, so a next board's card is drawn only when its page is asked for.
export function prepareCard(req, game, log = () => {}) {
  ensureCard(services(req), game)
    .then((r) => r.made && log(`invite card ${r.id}: ${r.ms} ms (picture ${r.fetched} ms, drawing ${r.drawn} ms, ${Math.round(r.bytes / 1024)} KB)`))
    .catch((e) => log(`invite card for ${game?.puzzleId} ${game?.grid}: ${e?.message ?? e}`));
}

/// Deletes cards older than [KEEP_MS] (the hourly run). Returns how many went.
export async function cleanCards(req, log = () => {}) {
  const { storage } = services(req);
  const before = new Date(Date.now() - KEEP_MS).toISOString();
  let deleted = 0;
  for (;;) {
    const page = await storage.listFiles({ bucketId: BUCKET, queries: [Query.lessThan('$createdAt', before), Query.limit(100)], total: false });
    if (page.files.length === 0) break;
    for (const f of page.files) {
      try {
        await storage.deleteFile({ bucketId: BUCKET, fileId: f.$id });
        deleted++;
      } catch (e) {
        if (!gone(e)) throw e;
      }
    }
    if (page.files.length < 100) break;
  }
  if (deleted) log(`invite cards: ${deleted} older than ten days deleted`);
  return deleted;
}
