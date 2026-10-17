// Play together (co-op): the host shares a board, up to four friends join it by a link, everyone
// plays the same board at once. This module keeps the games; the moves never pass through it.
// Moved from the coop-game function, which stays deployed for builds up to 124 (docs/functions.md).
//
// Routes (function `api`, see main.js; POST with a JSON body; the caller is x-appwrite-user-id, set
// by Appwrite):
//   /coop/create { puzzleId, grid, layout, painting }           the host starts a game on a new board
//   /coop/join   { code }                                       a player joins with the link's code
//   /coop/leave  { gameId }                                     a guest leaves; the host leaving ends it
//   /coop/remove { gameId, userId }                             the host removes a player for good
//   /coop/end    { gameId }                                     the host ends the game for everyone
//   /coop/next   { gameId, puzzleId, grid, layout, painting }   the host moves everyone to a new board
//
// A game is a row in `coop_games` (id = the game id) and an Appwrite team with the same id. The row
// is readable by the team only (read(team:<id>)), so only its players see it and its realtime
// events. Players create their moves themselves in `coop_moves` with read(team:<id>) and
// read(user:<self>): Appwrite lets a client grant only roles it holds, so a move row proves its
// author, and a player who left or was removed (no longer in the team) cannot add one. Seats live
// in the memberships' roles (`seat0` to `seat4`, the host also `host`); the row's `players` lists
// the user id per seat ('' for an empty seat), which gives every player a fixed colour.
//
// Rules: at most five players; a removed player cannot come back; players who blocked each other
// (table `blocks`, either way) cannot join each other's games; only catalogue pictures (not My
// Puzzles photos, not pack-code packs); a player is in one game at a time (joining or starting a
// game leaves the others, and ends those the player hosts). A game made by a QA player is marked
// `isTest`. The hourly cleanup (cleanup.js) deletes ended games after an hour and ends games idle for a day.
import { randomBytes } from 'node:crypto';
import { Client, TablesDB, Teams, Users, Query, Permission, Role, ID } from 'node-appwrite';
import { MAX_PLAYERS, LIVE, liveRowId, livePermissions, newCode, normaliseCode, validGrid, parseLayout, encodeLayout, freeSeat, seating, without } from './rules.js';

const DB = process.env.APPWRITE_DATABASE_ID || 'cjw';
const GAMES = 'coop_games';
const PAGE = 100;

/// A refusal the app shows as it is (`reason` picks the alert, `error` is the fallback line).
class Refusal extends Error {
  constructor(status, reason, message) {
    super(message);
    this.status = status;
    this.reason = reason;
  }
}

function services(req) {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(req.headers['x-appwrite-key'] ?? '');
  return { tables: new TablesDB(client), teams: new Teams(client), users: new Users(client) };
}

const gone = (e) => e?.code === 404;
const exists = (e) => e?.code === 409;
const nowIso = () => new Date().toISOString();

/// What the app reads of a game.
function view(g) {
  return {
    id: g.$id,
    code: g.code,
    hostId: g.hostId,
    players: g.players || [],
    removed: g.removed || [],
    status: g.status,
    board: g.board ?? 1,
    puzzleId: g.puzzleId,
    grid: g.grid,
    painting: g.painting === true,
    layout: g.layout,
    endReason: g.endReason ?? null,
  };
}

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

const memberships = (teams, teamId) => listAll((queries) => teams.listMemberships({ teamId, queries, total: false }), 'memberships');
const rows = (tables, tableId, queries) => listAll((q) => tables.listRows({ databaseId: DB, tableId, queries: [...queries, Query.orderAsc('$id'), ...q], total: false }), 'rows');

async function gameById(tables, gameId) {
  if (typeof gameId !== 'string' || !/^[A-Za-z0-9._-]{1,36}$/.test(gameId)) throw new Refusal(404, 'ended', 'This game has ended.');
  try {
    return await tables.getRow({ databaseId: DB, tableId: GAMES, rowId: gameId });
  } catch (e) {
    if (gone(e)) throw new Refusal(404, 'ended', 'This game has ended.');
    throw e;
  }
}

/// Only catalogue pictures can be shared: a row of `puzzles` in a pack that is listed for everyone
/// (not a pack-code pack, whose pictures are private). My Puzzles photos are not in `puzzles`.
async function checkCatalogue(tables, puzzleId) {
  const refuse = () => new Refusal(400, 'picture', 'Only pictures from the Library can be played together.');
  if (typeof puzzleId !== 'string' || !/^[A-Za-z0-9._-]{1,36}$/.test(puzzleId)) throw refuse();
  let puzzle;
  let pack;
  try {
    puzzle = await tables.getRow({ databaseId: DB, tableId: 'puzzles', rowId: puzzleId });
    pack = await tables.getRow({ databaseId: DB, tableId: 'packs', rowId: puzzle.packId });
  } catch (e) {
    if (gone(e)) throw refuse();
    throw e;
  }
  if (pack.hidden === true || String(puzzle.imageUrl || '').includes('/buckets/private-packs/')) throw refuse();
}

function boardOf(body) {
  const layout = parseLayout(body.layout);
  if (!layout || !validGrid(body.grid)) throw new Refusal(400, 'board', 'This board cannot be shared.');
  return { grid: body.grid, layout: encodeLayout(layout), painting: body.painting === true };
}

/// A QA player's games are test games (the purge tool deletes them with the player).
async function isTestPlayer(tables, users, userId) {
  try {
    const p = await tables.getRow({ databaseId: DB, tableId: 'profiles', rowId: userId });
    if (p.isTest === true) return true;
  } catch (e) {
    if (!gone(e)) throw e;
  }
  try {
    const u = await users.get({ userId });
    return u.prefs?.qa === true;
  } catch (e) {
    if (gone(e)) return false;
    throw e;
  }
}

/// Seats the team's members again (see `seating` in rules.js) and writes `players` when it changed.
/// Two passes: a join at the same moment may have changed the team between the read and the write.
async function reseat(tables, teams, game) {
  let g = game;
  for (let pass = 0; pass < 2; pass++) {
    const members = await memberships(teams, g.$id);
    const { players, moves, over } = seating(members);
    for (const m of over) {
      try {
        await teams.deleteMembership({ teamId: g.$id, membershipId: m.$id });
      } catch (e) {
        if (!gone(e)) throw e;
      }
    }
    for (const { membership, seat } of moves) {
      const roles = [...(membership.roles || []).filter((r) => !/^seat\d$/.test(r)), `seat${seat}`];
      try {
        await teams.updateMembership({ teamId: g.$id, membershipId: membership.$id, roles });
      } catch (e) {
        if (!gone(e)) throw e;
      }
    }
    if (JSON.stringify(players) !== JSON.stringify(g.players || [])) {
      g = await tables.updateRow({ databaseId: DB, tableId: GAMES, rowId: g.$id, data: { players, activeAt: nowIso() } });
    }
  }
  return g;
}

/// Whether [userId] and any of [others] blocked each other.
async function blockedWith(tables, userId, others) {
  if (others.length === 0) return false;
  const one = async (queries) => (await tables.listRows({ databaseId: DB, tableId: 'blocks', queries: [...queries, Query.limit(1)], total: false })).rows.length > 0;
  return (await one([Query.equal('blockerId', [userId]), Query.equal('blockedId', others)])) || (await one([Query.equal('blockerId', others), Query.equal('blockedId', [userId])]));
}

/// The player's live row in the game (picks and drags, see rules.js): made when they start or join
/// it, gone when they leave or are removed (a removed player must not reach the others' screens).
async function ensureLive(tables, gameId, userId) {
  try {
    await tables.createRow({ databaseId: DB, tableId: LIVE, rowId: liveRowId(gameId, userId), data: { gameId, userId }, permissions: livePermissions(gameId, userId) });
  } catch (e) {
    if (!exists(e)) throw e;
  }
}

async function dropLive(tables, gameId, userId) {
  try {
    await tables.deleteRow({ databaseId: DB, tableId: LIVE, rowId: liveRowId(gameId, userId) });
  } catch (e) {
    if (!gone(e)) throw e;
  }
}

async function endGame(tables, game, reason) {
  if (game.status === 'ended') return game;
  return tables.updateRow({ databaseId: DB, tableId: GAMES, rowId: game.$id, data: { status: 'ended', endedAt: nowIso(), endReason: reason, activeAt: nowIso() } });
}

async function leaveGame(tables, teams, game, userId) {
  if (game.hostId === userId) return endGame(tables, game, 'host-left');
  await dropLive(tables, game.$id, userId);
  for (const m of await memberships(teams, game.$id)) {
    if (m.userId !== userId) continue;
    try {
      await teams.deleteMembership({ teamId: game.$id, membershipId: m.$id });
    } catch (e) {
      if (!gone(e)) throw e;
    }
  }
  return reseat(tables, teams, { ...game, players: without(game.players || [], userId) });
}

/// A player is in one game at a time: starting or joining one leaves every other open game (and
/// ends the ones the player hosts).
async function leaveOthers(tables, teams, userId, exceptId) {
  const open = [
    ...(await rows(tables, GAMES, [Query.equal('hostId', [userId]), Query.equal('status', ['playing'])])),
    ...(await rows(tables, GAMES, [Query.contains('players', [userId]), Query.equal('status', ['playing'])])),
  ];
  const seen = new Set();
  for (const g of open) {
    if (g.$id === exceptId || seen.has(g.$id)) continue;
    seen.add(g.$id);
    await leaveGame(tables, teams, g, userId);
  }
}

function hostOnly(game, userId) {
  if (game.hostId !== userId) throw new Refusal(403, 'host', 'Only the host can do this.');
}

function playing(game) {
  if (game.status !== 'playing') throw new Refusal(410, 'ended', 'This game has ended.');
}

// ---------------------------------------------------------------------------------------------

async function create({ tables, teams, users }, userId, body) {
  const board = boardOf(body);
  await checkCatalogue(tables, body.puzzleId);
  await leaveOthers(tables, teams, userId, null);
  const gameId = ID.unique();
  await teams.create({ teamId: gameId, name: `Co-op ${gameId}` });
  try {
    await teams.createMembership({ teamId: gameId, roles: ['host', 'seat0'], userId });
    const isTest = await isTestPlayer(tables, users, userId);
    for (let attempt = 0; ; attempt++) {
      try {
        const row = await tables.createRow({
          databaseId: DB,
          tableId: GAMES,
          rowId: gameId,
          data: {
            code: newCode(randomBytes),
            hostId: userId,
            players: [userId, ...new Array(MAX_PLAYERS - 1).fill('')],
            removed: [],
            status: 'playing',
            board: 1,
            puzzleId: body.puzzleId,
            ...board,
            activeAt: nowIso(),
            isTest,
          },
          permissions: [Permission.read(Role.team(gameId))],
        });
        await ensureLive(tables, gameId, userId);
        return view(row);
      } catch (e) {
        // The code is taken (unique index): draw another.
        if (!exists(e) || attempt >= 4) throw e;
      }
    }
  } catch (e) {
    try {
      await teams.delete({ teamId: gameId });
    } catch (_) {}
    throw e;
  }
}

async function join({ tables, teams }, userId, body) {
  const code = normaliseCode(body.code);
  if (!code) throw new Refusal(404, 'ended', 'This invite link does not work.');
  const found = (await tables.listRows({ databaseId: DB, tableId: GAMES, queries: [Query.equal('code', [code]), Query.limit(1)], total: false })).rows[0];
  if (!found) throw new Refusal(404, 'ended', 'This game has ended.');
  playing(found);
  if ((found.removed || []).includes(userId)) throw new Refusal(403, 'removed', 'The host removed you from this game.');
  const members = await memberships(teams, found.$id);
  // Back again (another device, a reinstall, a second tap on the link): the same seat.
  if (members.some((m) => m.userId === userId)) {
    await ensureLive(tables, found.$id, userId);
    return view(await reseat(tables, teams, found));
  }
  if (members.length >= MAX_PLAYERS) throw new Refusal(409, 'full', 'This game is full.');
  if (await blockedWith(tables, userId, members.map((m) => m.userId))) throw new Refusal(403, 'blocked', 'You cannot join this game.');
  await leaveOthers(tables, teams, userId, found.$id);
  try {
    await teams.createMembership({ teamId: found.$id, roles: ['player', `seat${Math.max(0, freeSeat(members))}`], userId });
  } catch (e) {
    if (!exists(e)) throw e;
  }
  const game = await reseat(tables, teams, found);
  if (!(game.players || []).includes(userId)) throw new Refusal(409, 'full', 'This game is full.');
  await ensureLive(tables, game.$id, userId);
  return view(game);
}

async function leave({ tables, teams }, userId, body) {
  let game;
  try {
    game = await gameById(tables, body.gameId);
  } catch (e) {
    if (e instanceof Refusal) return { left: true };
    throw e;
  }
  if (!(game.players || []).includes(userId) && game.hostId !== userId) return { left: true };
  await leaveGame(tables, teams, game, userId);
  return { left: true };
}

async function remove({ tables, teams }, userId, body) {
  const game = await gameById(tables, body.gameId);
  hostOnly(game, userId);
  const target = String(body.userId || '');
  if (!target || target === userId) throw new Refusal(400, 'player', 'This player cannot be removed.');
  // The row first, while the player can still read it: their app hears it and says so.
  let g = await tables.updateRow({
    databaseId: DB,
    tableId: GAMES,
    rowId: game.$id,
    data: { removed: [...new Set([...(game.removed || []), target])], players: without(game.players || [], target), activeAt: nowIso() },
  });
  await dropLive(tables, game.$id, target);
  for (const m of await memberships(teams, game.$id)) {
    if (m.userId !== target) continue;
    try {
      await teams.deleteMembership({ teamId: game.$id, membershipId: m.$id });
    } catch (e) {
      if (!gone(e)) throw e;
    }
  }
  g = await reseat(tables, teams, g);
  return view(g);
}

async function end({ tables }, userId, body) {
  const game = await gameById(tables, body.gameId);
  hostOnly(game, userId);
  return view(await endGame(tables, game, 'host'));
}

async function next({ tables }, userId, body) {
  const game = await gameById(tables, body.gameId);
  hostOnly(game, userId);
  playing(game);
  const board = boardOf(body);
  await checkCatalogue(tables, body.puzzleId);
  const row = await tables.updateRow({
    databaseId: DB,
    tableId: GAMES,
    rowId: game.$id,
    data: { board: (game.board ?? 1) + 1, puzzleId: body.puzzleId, ...board, activeAt: nowIso() },
  });
  return view(row);
}

const ACTIONS = { create, join, leave, remove, end, next };

/// The actions a POST /coop/<action> can name.
export const COOP_ACTIONS = Object.keys(ACTIONS);

/// POST /coop/<name>: one of [COOP_ACTIONS] for the caller.
export async function coopAction(name, { req, res, log, error }) {
  const path = `/coop/${name}`;
  const action = ACTIONS[name];
  if (req.method !== 'POST' || !action) return res.json({ ok: false, error: 'Not found' }, 404);
  const userId = req.headers['x-appwrite-user-id'];
  if (!userId) return res.json({ ok: false, reason: 'auth', error: 'Sign in required' }, 401);
  let body = {};
  try {
    body = typeof req.body === 'string' && req.body ? JSON.parse(req.body) : (req.bodyJson ?? req.body ?? {});
  } catch (_) {
    body = {};
  }
  try {
    const result = await action(services(req), userId, body || {});
    // The invite is shared a moment later: draw its link preview now, without waiting (invite/store.js).
    if (name === 'create' && result?.id) import('../invite/store.js').then((m) => m.prepareCard(req, result, log)).catch(() => {});
    return res.json({ ok: true, game: result?.id ? result : undefined, ...(result?.id ? {} : result) });
  } catch (e) {
    if (e instanceof Refusal) {
      log(`${path} ${userId}: ${e.reason}`);
      return res.json({ ok: false, reason: e.reason, error: e.message }, e.status);
    }
    error(`${path} ${userId}: ${e.stack || e.message}`);
    return res.json({ ok: false, reason: 'server', error: 'Something went wrong. Try again.' }, 500);
  }
}
