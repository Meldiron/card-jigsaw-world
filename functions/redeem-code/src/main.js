// Pack codes: a player types a code (Settings > Redeem a pack code) and gets the pack it names.
//
// Routes:
//   POST /redeem  { code }  called by the app for the signed-in player
//   GET  /health
//
// Codes live in the server-only table `pack_codes` as a SHA-256 hash of the normalised code (16
// characters from CODE_ALPHABET, case and dashes ignored), with the pack id, a use limit and an
// optional expiry; `tools/dev/pack_codes.py` makes them. Each claim is a row in `code_claims`
// whose id comes from the code and the player, so a player claims a code once and a retry is
// harmless. The pack is added to the player's `profiles.unlockedPacks`; a hidden pack
// (`packs.hidden`) shows in the app only once it is there. Pictures of a private pack sit in the
// bucket `private-packs`, readable only by the players who claimed one of its codes: each claim
// adds read(user) to every picture file of the pack. Only the caller is ever granted anything
// (x-appwrite-user-id, set by Appwrite); the body never names a user.
import { createHash } from 'node:crypto';
import { Client, TablesDB, Storage, Query, Permission, Role } from 'node-appwrite';

const DB = process.env.APPWRITE_DATABASE_ID || 'cjw';
const PRIVATE_BUCKET = 'private-packs';
const PAGE = 100;

// Unambiguous characters: no 0/O, 1/I/L.
export const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
export const CODE_LENGTH = 16;

/// The code as stored: upper case, only alphabet characters (dashes and spaces dropped).
export function normalise(code) {
  return String(code ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');
}

export function hashCode(code) {
  return createHash('sha256').update(normalise(code)).digest('hex');
}

/// Row id of a player's claim of a code: one claim per player and code.
export function claimId(codeId, userId) {
  return createHash('sha256').update(`${codeId}:${userId}`).digest('hex').slice(0, 32);
}

function services(req) {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(req.headers['x-appwrite-key'] ?? '');
  return { tables: new TablesDB(client), storage: new Storage(client) };
}

const exists = (e) => e?.code === 409;

/// File ids of a private pack's pictures (its puzzles' image URLs in `private-packs`).
async function privateFiles(tables, packId) {
  const ids = new Set();
  const marker = `/buckets/${PRIVATE_BUCKET}/files/`;
  let cursor = null;
  for (;;) {
    const page = await tables.listRows({
      databaseId: DB,
      tableId: 'puzzles',
      queries: [Query.equal('packId', packId), Query.orderAsc('$id'), Query.limit(PAGE), ...(cursor ? [Query.cursorAfter(cursor)] : [])],
      total: false,
    });
    for (const r of page.rows) {
      for (const url of [r.imageUrl, r.thumbUrl]) {
        const at = String(url ?? '').indexOf(marker);
        if (at >= 0) ids.add(String(url).slice(at + marker.length).split(/[/?]/)[0]);
      }
    }
    if (page.rows.length < PAGE) break;
    cursor = page.rows[page.rows.length - 1].$id;
  }
  const pack = await tables.getRow({ databaseId: DB, tableId: 'packs', rowId: packId });
  const at = String(pack.coverUrl ?? '').indexOf(marker);
  if (at >= 0) ids.add(String(pack.coverUrl).slice(at + marker.length).split(/[/?]/)[0]);
  return [...ids].filter(Boolean);
}

/// Lets [userId] read every private picture of [packId].
async function grantFiles(tables, storage, packId, userId) {
  const reader = Permission.read(Role.user(userId));
  let granted = 0;
  for (const fileId of await privateFiles(tables, packId)) {
    const file = await storage.getFile({ bucketId: PRIVATE_BUCKET, fileId });
    const perms = file.$permissions || [];
    if (perms.includes(reader)) continue;
    await storage.updateFile({ bucketId: PRIVATE_BUCKET, fileId, permissions: [...perms, reader] });
    granted++;
  }
  return granted;
}

/// Adds [packId] to the player's unlocked packs (as a purchase would).
async function unlockPack(tables, userId, packId) {
  const profile = await tables.getRow({ databaseId: DB, tableId: 'profiles', rowId: userId });
  const unlocked = Array.isArray(profile.unlockedPacks) ? profile.unlockedPacks : [];
  if (unlocked.includes(packId)) return false;
  await tables.updateRow({ databaseId: DB, tableId: 'profiles', rowId: userId, data: { unlockedPacks: [...unlocked, packId] } });
  return true;
}

async function redeem(req, res, log) {
  const userId = req.headers['x-appwrite-user-id'];
  if (!userId) return res.json({ ok: false, error: 'signin' }, 401);
  let body = {};
  try {
    body = typeof req.body === 'string' && req.body ? JSON.parse(req.body) : (req.bodyJson ?? req.body ?? {});
  } catch {
    return res.json({ ok: false, error: 'invalid' }, 400);
  }
  const code = normalise(body.code);
  if (code.length !== CODE_LENGTH) return res.json({ ok: false, error: 'invalid' });
  const { tables, storage } = services(req);

  const found = await tables.listRows({ databaseId: DB, tableId: 'pack_codes', queries: [Query.equal('codeHash', hashCode(code))], total: false });
  const row = found.rows[0];
  if (!row) return res.json({ ok: false, error: 'invalid' });
  const pack = await tables.getRow({ databaseId: DB, tableId: 'packs', rowId: row.packId }).catch(() => null);
  if (!pack) return res.json({ ok: false, error: 'invalid' });
  const answer = { packId: pack.$id, packName: pack.name };

  // A player who claimed this code already gets the pack again (a retry, or another device).
  const claim = claimId(row.$id, userId);
  const mine = await tables.getRow({ databaseId: DB, tableId: 'code_claims', rowId: claim }).catch(() => null);
  if (!mine) {
    if (row.expiresAt && Date.parse(row.expiresAt) < Date.now()) return res.json({ ok: false, error: 'expired', ...answer });
    if ((row.uses ?? 0) >= row.maxUses) return res.json({ ok: false, error: 'used', ...answer });
    try {
      await tables.createRow({ databaseId: DB, tableId: 'code_claims', rowId: claim, data: { codeId: row.$id, userId, packId: pack.$id } });
    } catch (e) {
      if (!exists(e)) throw e;
    }
    // Two players claiming the last use at once: the claims count decides, the later one gives it back.
    const claims = await tables.listRows({ databaseId: DB, tableId: 'code_claims', queries: [Query.equal('codeId', row.$id), Query.limit(1)] });
    if (claims.total > row.maxUses) {
      await tables.deleteRow({ databaseId: DB, tableId: 'code_claims', rowId: claim }).catch(() => {});
      return res.json({ ok: false, error: 'used', ...answer });
    }
    await tables.updateRow({ databaseId: DB, tableId: 'pack_codes', rowId: row.$id, data: { uses: Math.min(claims.total, row.maxUses) } });
  }
  const unlocked = await unlockPack(tables, userId, pack.$id);
  const files = await grantFiles(tables, storage, pack.$id, userId);
  log(`code ${row.$id} -> pack ${pack.$id} for ${userId} (unlocked ${unlocked}, files ${files}, repeat ${Boolean(mine)})`);
  return res.json({ ok: true, ...answer, repeat: Boolean(mine) });
}

export default async ({ req, res, log, error }) => {
  const path = (req.path || '/').replace(/\/+$/, '') || '/';
  try {
    if (req.method === 'GET' && (path === '/health' || path === '/')) return res.json({ ok: true });
    if (req.method === 'POST' && (path === '/redeem' || path === '/')) return await redeem(req, res, log);
    return res.json({ ok: false, error: 'not found' }, 404);
  } catch (e) {
    error(`redeem-code: ${e?.message ?? e}`);
    return res.json({ ok: false, error: 'server' }, 500);
  }
};
