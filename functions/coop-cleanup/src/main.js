// Tidies the co-op games (Play together, function coop-game) every hour (schedule `0 * * * *`):
//
// 1. A game nobody played for a day ends (`endReason: idle`); its players' apps say so.
// 2. A game ended an hour ago or more goes: its moves, its team and its row. The hour lets every
//    player's app hear that it ended and show the guests their rewards.
// 3. Moves of boards a game has moved past go (the host opened the next board).
// 4. Teams of games that are gone (`Co-op <id>` without a row, an hour old) go.
//
// Activity is the newest of the row's `activeAt` (every coop-game action) and its newest move. Only
// the server writes games; TablesDB has no row expiry, hence this function. POST /run does the same
// on demand (`appwrite functions create-execution --function-id coop-cleanup --path /run`).
import { Client, TablesDB, Teams, Query } from 'node-appwrite';

const DB = process.env.APPWRITE_DATABASE_ID || 'cjw';
const GAMES = 'coop_games';
const MOVES = 'coop_moves';
const PAGE = 100;
const HOUR = 60 * 60 * 1000;
const IDLE = 24 * HOUR;
const TEAM_PREFIX = 'Co-op ';

function services(req) {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(req.headers['x-appwrite-key'] ?? '');
  return { tables: new TablesDB(client), teams: new Teams(client) };
}

const gone = (e) => e?.code === 404;
const iso = (ms) => new Date(ms).toISOString();

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

const games = (tables, queries) => listAll((q) => tables.listRows({ databaseId: DB, tableId: GAMES, queries: [...queries, Query.orderAsc('$id'), ...q], total: false }), 'rows');

/// Newest move of a game, as a time in ms (0 without moves).
async function lastMoveAt(tables, gameId) {
  const page = await tables.listRows({ databaseId: DB, tableId: MOVES, queries: [Query.equal('gameId', [gameId]), Query.orderDesc('$createdAt'), Query.limit(1), Query.select(['$id', '$createdAt'])], total: false });
  return page.rows.length ? Date.parse(page.rows[0].$createdAt) : 0;
}

async function deleteGame(tables, teams, game) {
  await tables.deleteRows({ databaseId: DB, tableId: MOVES, queries: [Query.equal('gameId', [game.$id])] });
  try {
    await teams.delete({ teamId: game.$id });
  } catch (e) {
    if (!gone(e)) throw e;
  }
  try {
    await tables.deleteRow({ databaseId: DB, tableId: GAMES, rowId: game.$id });
  } catch (e) {
    if (!gone(e)) throw e;
  }
}

async function run({ tables, teams }, log) {
  const now = Date.now();
  const done = { ended: 0, deleted: 0, oldBoards: 0, teams: 0 };

  // 1. Idle for a day: end it (the row stays an hour for the players' apps).
  for (const g of await games(tables, [Query.equal('status', ['playing']), Query.lessThan('activeAt', iso(now - IDLE))])) {
    const last = Math.max(Date.parse(g.activeAt || g.$updatedAt), await lastMoveAt(tables, g.$id));
    if (now - last < IDLE) {
      // Played lately: remember when, so the next runs skip it until a day after that.
      await tables.updateRow({ databaseId: DB, tableId: GAMES, rowId: g.$id, data: { activeAt: iso(last) } });
      continue;
    }
    await tables.updateRow({ databaseId: DB, tableId: GAMES, rowId: g.$id, data: { status: 'ended', endedAt: iso(now), endReason: 'idle' } });
    done.ended++;
  }

  // 2. Ended an hour ago or more: delete.
  for (const g of await games(tables, [Query.equal('status', ['ended']), Query.lessThan('endedAt', iso(now - HOUR))])) {
    await deleteGame(tables, teams, g);
    done.deleted++;
  }

  // 3. Boards a game has moved past.
  for (const g of await games(tables, [Query.equal('status', ['playing']), Query.greaterThan('board', 1)])) {
    const r = await tables.deleteRows({ databaseId: DB, tableId: MOVES, queries: [Query.equal('gameId', [g.$id]), Query.lessThan('board', g.board)] });
    done.oldBoards += r?.total ?? 0;
  }

  // 4. Teams whose game is gone (a failed create, a game deleted by hand or with an account).
  const all = await listAll((q) => teams.list({ queries: [Query.startsWith('name', TEAM_PREFIX), Query.orderAsc('$id'), ...q], total: false }), 'teams');
  for (const t of all) {
    if (now - Date.parse(t.$createdAt) < HOUR) continue;
    try {
      await tables.getRow({ databaseId: DB, tableId: GAMES, rowId: t.$id });
    } catch (e) {
      if (!gone(e)) throw e;
      await tables.deleteRows({ databaseId: DB, tableId: MOVES, queries: [Query.equal('gameId', [t.$id])] });
      await teams.delete({ teamId: t.$id });
      done.teams++;
    }
  }
  log(`coop cleanup: ${JSON.stringify(done)}`);
  return done;
}

export default async ({ req, res, log, error }) => {
  const path = (req.path || '/').replace(/\/+$/, '') || '/';
  if (req.method === 'GET' && path === '/health') return res.json({ ok: true });
  try {
    // The schedule calls the root path; /run is the same on demand.
    if (path === '/' || path === '/run') return res.json({ ok: true, ...(await run(services(req), log)) });
    return res.json({ ok: false, error: 'Not found' }, 404);
  } catch (e) {
    error(e.stack || e.message);
    return res.json({ ok: false, error: e.message }, 500);
  }
};
