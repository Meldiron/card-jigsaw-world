// The integrity sweep (security review, 2026-10-17; docs/functions.md): rows, profiles, photos and
// names that the app's own writes cannot produce, put right on the server. Rules in rules.js.
//
// 1. progress, event_progress, friends, blocks: a row whose permissions do not belong to its owner,
//    or whose predictable id is not its owner's, is deleted (its owner's app writes it again).
// 2. profiles: deleted when no user has its id (an hour after it was made) or another player is
//    named in its permissions; permissions repaired when only the owner is named but not as the app
//    sets them.
// 3. user-uploads: a photo without a My Puzzles row of its owner goes an hour after the upload; a
//    photo readable or changeable by someone else is made its owner's only; past FILES_PER_PLAYER a
//    player's newest photos go with their rows.
// 4. names: a profile name, or a name copied into friends and blocks, that the name filter refuses
//    (offensive, a link, an @handle, a domain) becomes "Player".
//
// Runs on api's hourly schedule (main.js) over rows written in the last two hours, and over
// everything once a day (FULL_HOUR UTC) or when asked. `apply: false` only reports. `qaOnly` touches
// only rows of QA players (prefs `qa`), for live checks. Reads are paged; deletes go 100 at a time.
import { Client, TablesDB, Storage, Users, Query } from 'node-appwrite';
import { OWNED, FILES_PER_PLAYER, HOUR, rowVerdict, profileVerdict, fileVerdict, nameVerdict, usersIn } from './rules.js';
import { FALLBACK_NAME } from '../gift/gift.js';

const DB = process.env.APPWRITE_DATABASE_ID || 'cjw';
const UPLOADS = 'user-uploads';
const PAGE = 100;
const WINDOW = 2 * HOUR;
const FILE_WINDOW = 26 * HOUR;

/// The hour (UTC) of the day's full pass.
export const FULL_HOUR = 4;

export function services(req) {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(req.headers['x-appwrite-key'] ?? '');
  return { tables: new TablesDB(client), storage: new Storage(client), users: new Users(client) };
}

const gone = (e) => e?.code === 404;
const iso = (ms) => new Date(ms).toISOString();
const chunks = (list, n = PAGE) => Array.from({ length: Math.ceil(list.length / n) }, (_, i) => list.slice(i * n, i * n + n));

async function listAll(fetchPage, key) {
  const out = [];
  let cursor = null;
  for (;;) {
    const page = await fetchPage([Query.limit(PAGE), ...(cursor ? [Query.cursorAfter(cursor)] : [])]);
    out.push(...page[key]);
    if (page[key].length < PAGE) return out;
    cursor = page[key][page[key].length - 1].$id;
  }
}

const rowsOf = (tables, tableId, queries) =>
  listAll((q) => tables.listRows({ databaseId: DB, tableId, queries: [...queries, Query.orderAsc('$id'), ...q], total: false }), 'rows');

/// Runs the sweep. Returns counts per kind and, for a report, up to 20 ids of each.
export async function sweep({ tables, storage, users }, { apply = false, full = false, qaOnly = false, now = Date.now(), log = () => {} } = {}) {
  const since = full ? null : iso(now - WINDOW);
  const changed = since ? [Query.greaterThanEqual('$updatedAt', since)] : [];
  const report = { apply, full, qaOnly, counts: {}, ids: {} };
  const note = (kind, id) => {
    report.counts[kind] = (report.counts[kind] || 0) + 1;
    (report.ids[kind] ||= []).length < 20 && report.ids[kind].push(id);
  };

  // Every user, when the pass needs them all (a full pass, or QA-only scope).
  let userIds = null;
  let qa = null;
  if (full || qaOnly) {
    const all = await listAll((q) => users.list({ queries: [Query.orderAsc('$id'), ...q], total: false }), 'users');
    userIds = new Set(all.map((u) => u.$id));
    qa = new Set(all.filter((u) => u.prefs?.qa === true).map((u) => u.$id));
  }
  const userExists = async (id) => {
    if (userIds) return userIds.has(id);
    try {
      await users.get({ userId: id });
      return true;
    } catch (e) {
      if (gone(e)) return false;
      throw e;
    }
  };
  // QA-only: act only where every existing user involved is a QA player (and there is one).
  const inScope = (ids) => {
    if (!qaOnly) return true;
    const involved = ids.filter((id) => id && userIds.has(id));
    return involved.length > 0 && involved.every((id) => qa.has(id));
  };

  const deleteRows = async (tableId, ids) => {
    if (!apply) return;
    for (const part of chunks(ids)) await tables.deleteRows({ databaseId: DB, tableId, queries: [Query.equal('$id', part)] });
  };
  const renameRows = async (tableId, column, ids) => {
    if (!apply) return;
    for (const part of chunks(ids)) await tables.updateRows({ databaseId: DB, tableId, data: { [column]: FALLBACK_NAME }, queries: [Query.equal('$id', part)] });
  };

  // 1. Rows a player writes for themself (and names copied into friends and blocks).
  for (const [tableId, spec] of Object.entries(OWNED)) {
    const doomed = [];
    const renamed = [];
    for (const row of await rowsOf(tables, tableId, changed)) {
      if (!inScope([row[spec.owner], ...usersIn(row.$permissions)])) continue;
      const why = rowVerdict(spec, row);
      if (why) {
        doomed.push(row.$id);
        note(`${tableId}:${why}`, row.$id);
      } else if (spec.name && nameVerdict(row[spec.name])) {
        renamed.push(row.$id);
        note(`${tableId}:name`, row.$id);
      }
    }
    await deleteRows(tableId, doomed);
    await renameRows(tableId, spec.name, renamed);
  }

  // 2. Profiles, and 4. their names.
  const ghosts = [];
  const renamed = [];
  for (const row of await rowsOf(tables, 'profiles', [...changed, Query.select(['$id', '$createdAt', 'isTest', 'displayName'])])) {
    if (!inScope([row.$id, ...usersIn(row.$permissions)])) continue;
    const verdict = profileVerdict(row, await userExists(row.$id), now);
    if (verdict?.action === 'delete') {
      ghosts.push(row.$id);
      note(`profiles:${verdict.why}`, row.$id);
      continue;
    }
    if (verdict?.action === 'repair') {
      note('profiles:repair', row.$id);
      if (apply) await tables.updateRow({ databaseId: DB, tableId: 'profiles', rowId: row.$id, permissions: verdict.permissions });
    }
    if (nameVerdict(row.displayName)) {
      renamed.push(row.$id);
      note('profiles:name', row.$id);
    }
  }
  await deleteRows('profiles', ghosts);
  await renameRows('profiles', 'displayName', renamed);

  // 3. Photos.
  const fileQueries = full ? [] : [Query.greaterThanEqual('$createdAt', iso(now - FILE_WINDOW))];
  const files = await listAll((q) => storage.listFiles({ bucketId: UPLOADS, queries: [...fileQueries, Query.orderAsc('$id'), ...q], total: false }), 'files');
  const owners = new Map();
  for (const part of chunks(files.map((f) => f.$id))) {
    for (const r of await rowsOf(tables, 'my_puzzles', [Query.equal('fileId', part), Query.select(['$id', 'userId', 'fileId'])])) {
      if (!owners.has(r.fileId)) owners.set(r.fileId, new Set());
      owners.get(r.fileId).add(r.userId);
    }
  }
  const players = new Set();
  for (const f of files) {
    const rowOwners = owners.get(f.$id) ?? new Set();
    if (!inScope([...rowOwners, ...usersIn(f.$permissions)])) continue;
    const verdict = fileVerdict(f, rowOwners, now);
    if (verdict?.action === 'delete') {
      note('files:no-row', f.$id);
      if (apply) await deleteFile(storage, f.$id);
    } else if (verdict?.action === 'repair') {
      note('files:repair', f.$id);
      if (apply) await storage.updateFile({ bucketId: UPLOADS, fileId: f.$id, permissions: verdict.permissions });
    }
    for (const o of rowOwners) players.add(o);
  }
  // Too many photos: the newest past FILES_PER_PLAYER go, row and file.
  for (const userId of players) {
    const mine = await tables.listRows({ databaseId: DB, tableId: 'my_puzzles', queries: [Query.equal('userId', [userId]), Query.select(['$id']), Query.limit(1)] });
    if (mine.total <= FILES_PER_PLAYER) continue;
    const rows = await rowsOf(tables, 'my_puzzles', [Query.equal('userId', [userId]), Query.select(['$id', '$createdAt', 'fileId'])]);
    rows.sort((a, b) => (a.$createdAt < b.$createdAt ? -1 : a.$createdAt > b.$createdAt ? 1 : 0));
    const extra = rows.slice(FILES_PER_PLAYER);
    for (const r of extra) note('files:over-limit', r.fileId);
    if (apply) {
      for (const r of extra) await deleteFile(storage, r.fileId);
      await deleteRows('my_puzzles', extra.map((r) => r.$id));
    }
  }

  log(`integrity sweep (${apply ? 'applied' : 'dry run'}${full ? ', full' : ''}${qaOnly ? ', QA only' : ''}): ${JSON.stringify(report.counts)}`);
  return report;
}

async function deleteFile(storage, fileId) {
  try {
    await storage.deleteFile({ bucketId: UPLOADS, fileId });
  } catch (e) {
    if (!gone(e)) throw e;
  }
}

/// One row just created in an [OWNED] table (the `blocks` create event): deleted at once when it is
/// not its owner's, so a player can always block someone.
export async function sweepNewRow({ tables }, tableId, row, { apply = false, log = () => {} } = {}) {
  const spec = OWNED[tableId];
  if (!spec || !row?.$id) return { checked: false };
  const why = rowVerdict(spec, row);
  if (why) {
    log(`${tableId} ${row.$id}: ${why}${apply ? ', deleted' : ' (dry run)'}`);
    if (apply) {
      try {
        await tables.deleteRow({ databaseId: DB, tableId, rowId: row.$id });
      } catch (e) {
        if (!gone(e)) throw e;
      }
    }
  }
  return { checked: true, verdict: why };
}
