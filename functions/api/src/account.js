// Delete the calling player's account and everything stored for them (App Store guideline 5.1.1(v)).
// Moved from the delete-account function, which stays deployed for builds up to 124 (docs/functions.md):
// this module is the source; a change to what is deleted goes into both until that function retires.
//
// Route (function `api`, see main.js):
//   POST /account/delete  { appleAuthorizationCode? }  called by the app from Account > Delete account
//
// Only the user whose session made the call is deleted (x-appwrite-user-id, set by Appwrite); the
// body never names a user. In order: Sign in with Apple tokens are revoked (when the player has an
// Apple identity, the app sent a fresh authorization code and APPLE_SIGNIN_KEY is set), then their
// My Puzzles photos, their rows in every player table (feedback, friend links, reports, blocks and friend
// gifts in both directions, inbox messages to them and gifts they sent), their co-op games (the games they
// host with every move in them; their seat and name in other players' games), the profile row and finally
// the Appwrite user. Every step ignores what is already gone, so a retry after a failure finishes the job.
// The same tables as PLAYER_TABLES in tools/dev/cjw_admin.py.
import { createPrivateKey, createSign } from 'node:crypto';
import { Client, TablesDB, Storage, Users, Query } from 'node-appwrite';

const DB = process.env.APPWRITE_DATABASE_ID || 'cjw';
const UPLOADS = 'user-uploads';
// Every table keyed by a player's user id; profiles also use the user id as the row id.
const PLAYER_TABLES = ['progress', 'ledger', 'event_progress', 'friends', 'my_puzzles', 'purchases', 'code_claims', 'feedback', 'messages', 'coop_moves'];
// Tables keyed by two player columns (reports made and received, blocks made and received, friend
// gifts sent and received); messages also go where the player is the sender (a friend's gift).
const PAIR_TABLES = { reports: ['reporterId', 'reportedId'], blocks: ['blockerId', 'blockedId'], gifts: ['senderId', 'recipientId'], messages: ['fromUserId'] };
const PAGE = 100;

// Sign in with Apple: the app's bundle id is the client id of native sign-ins.
const APPLE_TEAM_ID = process.env.APPLE_TEAM_ID || 'C24QP73SQM';
const APPLE_KEY_ID = process.env.APPLE_KEY_ID || '2QJPJFW8JW';
const APPLE_CLIENT_ID = process.env.APPLE_CLIENT_ID || 'com.matejbaco.cardjigsawworld';

function services(req) {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(req.headers['x-appwrite-key'] ?? '');
  return { tables: new TablesDB(client), storage: new Storage(client), users: new Users(client) };
}

const gone = (e) => e?.code === 404;

/// Deletes every row of [tableId] matching [queries], a page at a time. Each pass reads the first
/// page again (a cursor would point at a row that no longer exists).
async function deleteRows(tables, tableId, queries) {
  let count = 0;
  for (;;) {
    const page = await tables.listRows({ databaseId: DB, tableId, queries: [...queries, Query.limit(PAGE)], total: false });
    for (const row of page.rows) {
      try {
        await tables.deleteRow({ databaseId: DB, tableId, rowId: row.$id });
        count++;
      } catch (e) {
        if (!gone(e)) throw e;
      }
    }
    if (page.rows.length < PAGE) return count;
  }
}

/// The player's photos: the files their My Puzzles rows point at, and any upload readable only by
/// them that lost its row (an upload whose row write failed).
async function playerFiles(tables, storage, userId) {
  const ids = new Set();
  let cursor = null;
  for (;;) {
    const page = await tables.listRows({
      databaseId: DB,
      tableId: 'my_puzzles',
      queries: [Query.equal('userId', userId), Query.orderAsc('$id'), Query.limit(PAGE), ...(cursor ? [Query.cursorAfter(cursor)] : [])],
      total: false,
    });
    for (const r of page.rows) if (r.fileId) ids.add(r.fileId);
    if (page.rows.length < PAGE) break;
    cursor = page.rows[page.rows.length - 1].$id;
  }
  const mine = `user:${userId}`;
  cursor = null;
  for (;;) {
    const page = await storage.listFiles({ bucketId: UPLOADS, queries: [Query.orderAsc('$id'), Query.limit(PAGE), ...(cursor ? [Query.cursorAfter(cursor)] : [])], total: false });
    for (const f of page.files) if ((f.$permissions || []).some((p) => p.includes(mine))) ids.add(f.$id);
    if (page.files.length < PAGE) break;
    cursor = page.files[page.files.length - 1].$id;
  }
  return [...ids];
}

/// The Sign in with Apple key from the function variable: the .p8 file's contents, with real or
/// escaped (\n) line breaks, with or without the PEM armour.
function appleKey() {
  const raw = (process.env.APPLE_SIGNIN_KEY || '').trim().replace(/\\n/g, '\n');
  if (!raw) return null;
  const pem = raw.includes('BEGIN PRIVATE KEY') ? raw : `-----BEGIN PRIVATE KEY-----\n${raw.replace(/\s+/g, '')}\n-----END PRIVATE KEY-----`;
  return createPrivateKey(pem);
}

/// The client secret Apple's token endpoints ask for: a short-lived ES256 JWT signed with the key.
function appleClientSecret(key) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const input = `${b64({ alg: 'ES256', kid: APPLE_KEY_ID })}.${b64({ iss: APPLE_TEAM_ID, iat: now, exp: now + 300, aud: 'https://appleid.apple.com', sub: APPLE_CLIENT_ID })}`;
  const signature = createSign('SHA256').update(input).sign({ key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
  return `${input}.${signature}`;
}

async function applePost(path, params) {
  const r = await fetch(`https://appleid.apple.com/auth/${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(params),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`Apple ${path} ${r.status}: ${text.slice(0, 200)}`);
  return text ? JSON.parse(text) : {};
}

/// Revokes the player's Apple tokens (Apple requires it when an account made with Sign in with Apple
/// is deleted). Returns what happened; a failure never stops the deletion.
async function revokeApple(users, userId, code, log, error) {
  let identities = [];
  try {
    identities = (await users.listIdentities({ queries: [Query.equal('userId', userId), Query.equal('provider', 'apple')] })).identities;
  } catch (e) {
    if (!gone(e)) error(`identities: ${e.message}`);
  }
  if (identities.length === 0) return 'not-apple';
  if (!code) {
    log('Apple identity without an authorization code: tokens not revoked');
    return 'skipped:no-code';
  }
  let key;
  try {
    key = appleKey();
  } catch (e) {
    error(`APPLE_SIGNIN_KEY could not be read: ${e.message}`);
    return 'skipped:bad-key';
  }
  if (!key) {
    log('APPLE_SIGNIN_KEY is not set: Apple tokens not revoked');
    return 'skipped:no-key';
  }
  try {
    const secret = appleClientSecret(key);
    const tokens = await applePost('token', { client_id: APPLE_CLIENT_ID, client_secret: secret, code, grant_type: 'authorization_code' });
    const token = tokens.refresh_token || tokens.access_token;
    if (!token) return 'failed:no-token';
    await applePost('revoke', { client_id: APPLE_CLIENT_ID, client_secret: secret, token, token_type_hint: tokens.refresh_token ? 'refresh_token' : 'access_token' });
    return 'revoked';
  } catch (e) {
    error(`Apple revoke failed: ${e.message}`);
    return 'failed';
  }
}

/// Co-op games (Play together): the games the player hosts go with all their moves (their teams are
/// left to the hourly co-op cleanup, which deletes teams without a game); in other players' games
/// their seat is emptied and their id leaves the removed list.
async function deleteCoop(tables, userId) {
  let hosted = 0;
  for (;;) {
    const page = await tables.listRows({ databaseId: DB, tableId: 'coop_games', queries: [Query.equal('hostId', userId), Query.limit(PAGE)], total: false });
    for (const g of page.rows) {
      await deleteRows(tables, 'coop_moves', [Query.equal('gameId', g.$id)]);
      try {
        await tables.deleteRow({ databaseId: DB, tableId: 'coop_games', rowId: g.$id });
        hosted++;
      } catch (e) {
        if (!gone(e)) throw e;
      }
    }
    if (page.rows.length < PAGE) break;
  }
  let seats = 0;
  for (const col of ['players', 'removed']) {
    let cursor = null;
    for (;;) {
      const page = await tables.listRows({
        databaseId: DB,
        tableId: 'coop_games',
        queries: [Query.contains(col, [userId]), Query.orderAsc('$id'), Query.limit(PAGE), ...(cursor ? [Query.cursorAfter(cursor)] : [])],
        total: false,
      });
      for (const g of page.rows) {
        const data = col === 'players' ? { players: (g.players || []).map((p) => (p === userId ? '' : p)) } : { removed: (g.removed || []).filter((p) => p !== userId) };
        try {
          await tables.updateRow({ databaseId: DB, tableId: 'coop_games', rowId: g.$id, data });
          seats++;
        } catch (e) {
          if (!gone(e)) throw e;
        }
      }
      if (page.rows.length < PAGE) break;
      cursor = page.rows[page.rows.length - 1].$id;
    }
  }
  return { hosted, seats };
}

async function handleDelete(req, res, log, error) {
  const userId = req.headers['x-appwrite-user-id'];
  if (!userId) return res.json({ ok: false, error: 'Sign in required' }, 401);
  let body = {};
  try {
    body = typeof req.body === 'string' && req.body ? JSON.parse(req.body) : (req.bodyJson ?? req.body ?? {});
  } catch (_) {
    body = {};
  }
  const { tables, storage, users } = services(req);

  const apple = await revokeApple(users, userId, body?.appleAuthorizationCode, log, error);

  let files = 0;
  for (const fileId of await playerFiles(tables, storage, userId)) {
    try {
      await storage.deleteFile({ bucketId: UPLOADS, fileId });
      files++;
    } catch (e) {
      if (!gone(e)) throw e;
    }
  }

  const rows = {};
  for (const t of PLAYER_TABLES) {
    rows[t] = await deleteRows(tables, t, [Query.equal('userId', userId)]);
    // Other players' friend links to this player go too.
    if (t === 'friends') rows[t] += await deleteRows(tables, t, [Query.equal('friendId', userId)]);
  }
  // Reports, blocks and gifts, both directions (the player's own and other players' about them).
  for (const [t, cols] of Object.entries(PAIR_TABLES)) {
    rows[t] = rows[t] ?? 0;
    for (const col of cols) rows[t] += await deleteRows(tables, t, [Query.equal(col, userId)]);
  }
  const coop = await deleteCoop(tables, userId);
  rows.coop_games = coop.hosted;
  try {
    await tables.deleteRow({ databaseId: DB, tableId: 'profiles', rowId: userId });
    rows.profiles = 1;
  } catch (e) {
    if (!gone(e)) throw e;
    rows.profiles = 0;
  }

  let user = true;
  try {
    await users.delete({ userId });
  } catch (e) {
    if (!gone(e)) throw e;
    user = false;
  }
  log(`deleted ${userId}: user ${user}, files ${files}, rows ${JSON.stringify(rows)}, apple ${apple}`);
  return res.json({ ok: true, user, files, rows, apple });
}

/// Whether the Sign in with Apple key can sign a revocation, for GET /health: `set`, `missing` or
/// `unreadable` (never the key itself).
export function appleKeyState() {
  try {
    return appleKey() ? 'set' : 'missing';
  } catch (_) {
    return 'unreadable';
  }
}

export async function deleteAccount({ req, res, log, error }) {
  try {
    return await handleDelete(req, res, log, error);
  } catch (e) {
    error(e.stack || e.message);
    return res.json({ ok: false, error: 'Could not delete the account. Please try again.' }, 500);
  }
}
