#!/usr/bin/env node
// Play together QA: players on the live backend for the app on the simulator to play with. It makes
// QA-flagged players (prefs qa, qaRun coop-bot-<time>, a test profile), plays as them through the
// `api` function (`/coop/<action>`), the moves table and a realtime socket each, and is driven over HTTP on
// 127.0.0.1:8787 (the iOS simulator reaches the Mac's localhost): the integration tests
// integration_test/coop_live_test.dart and coop_host_test.dart call it. On /quit (or Ctrl-C) it ends
// its games and purges its players (tools/dev/purge_test_players.py, which deletes their games and
// moves; teams go with the hourly co-op cleanup of the `api` function).
//
//   node tools/dev/coop_bot.mjs            then run an integration test through tools/dev/qa-run.sh
//
// Two players act: `host` (hosts the bot's games) and `friend` (joins a game by its code, the app's
// own too). Routes (POST unless noted; JSON answers):
//   /game?cells=9|20&giant=1&full=1    a new game hosted by `host` (giant=1: a Giant pack picture on a
//                                      100-card board; full=1: four more players join it)
//   /friend?code=C                     `friend` joins the game of code C (default: the host's game)
//   /move?as=host&changes=s:b:a,...    a change by that player on their game's current board; without
//                                      `changes` one misplaced card goes to its place; &wait=0 answers
//                                      at once and sends the change afterwards
//   /swap?as=host                      two misplaced cards change places (no lock)
//   /solve?as=host                     every card goes to its place, one move each
//   /hold?as=host&card=N               the player holds card N (presence over their socket)
//   /remove?user=ID  /end  /next       the host removes a player, ends the game, opens the next board
//   /relay?key=K&value=V   GET /relay?key=K    hands values between two simulators' tests
//   GET /moves?as=host                 the moves of that player's game board, and the board they make
//   /liverows?as=host|game=ID          live rows (coop_drags) for every player of that player's game,
//                                      as the api function makes them on create and join (for QA
//                                      before api is deployed with them; harmless after)
//   /pick?as=host&card=N               the player picks card N with a tap (-1: puts it down): their live
//                                      row at once; answers when the update is written, with its times
//   /drag?as=host&card=N&to=S&ms=1500&rate=5&end=drop|cancel&wait=0
//                                      the player drags card N to slot S over `ms`, `rate` positions a
//                                      second, then drops it there (with the move) or cancels; `wait=0`
//                                      answers at once and streams in the background
//   GET /live?as=host                  what that player's socket heard of the others' live rows (with
//                                      the time each arrived) and what the bot sent, for latencies
//   /quit                              clean up and stop
import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { execFileSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes, createHash } from 'node:crypto';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT = '6acb4de5003e38d5ebd9';
const KEY = readFileSync(join(ROOT, 'secrets', 'appwrite-users-key.txt'), 'utf8').trim();
const RUN = `coop-bot-${Date.now()}`;
const PORT = Number(process.env.COOP_BOT_PORT || 8787);
const id = () => randomBytes(10).toString('hex');
const q = (method, attribute, values) => JSON.stringify(attribute === undefined ? { method, values } : { method, attribute, values });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function call(method, path, { body, session, key = true } = {}) {
  const headers = { 'X-Appwrite-Project': PROJECT, 'Content-Type': 'application/json' };
  if (key) headers['X-Appwrite-Key'] = KEY;
  if (session) headers['X-Appwrite-Session'] = session;
  const r = await fetch(ENDPOINT + path, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const text = await r.text();
  const data = text ? JSON.parse(text) : {};
  if (!r.ok) throw Object.assign(new Error(`${method} ${path}: ${r.status} ${data.message}`), { code: r.status });
  return data;
}

async function makePlayer(name, avatar) {
  const userId = id();
  await call('POST', '/users', { body: { userId, name } });
  await call('PATCH', `/users/${userId}/prefs`, { body: { prefs: { qa: true, qaRun: RUN } } });
  // A profile row so the app shows a name (profiles are public); flagged as a test player.
  await call('POST', '/tablesdb/cjw/tables/profiles/rows', {
    body: { rowId: userId, data: { userId, displayName: name, avatar, isTest: true }, permissions: ['read("any")'] },
  }).catch((e) => console.log('profile:', e.message));
  const s = await call('POST', `/users/${userId}/sessions`, { body: {} });
  return { userId, secret: s.secret, name, gameId: null, socket: null, heard: new Map(), liveHeard: [], liveSent: [], seq: 0 };
}

async function fn(p, action, body) {
  const exec = await call('POST', '/functions/api/executions', { key: false, session: p.secret, body: { body: JSON.stringify(body), path: `/coop/${action}`, method: 'POST', async: false } });
  return exec.responseBody ? JSON.parse(exec.responseBody) : {};
}

/// A player's realtime socket: hears their game's moves, keeps their presence.
function connect(p) {
  p.socket?.close();
  const ws = new WebSocket(`wss://fra.cloud.appwrite.io/v1/realtime?project=${PROJECT}`);
  p.socket = ws;
  ws.onmessage = (m) => {
    const d = JSON.parse(m.data);
    if (d.type === 'connected') {
      ws.send(JSON.stringify({ type: 'authentication', data: { session: p.secret } }));
      ws.send(JSON.stringify({ type: 'subscribe', data: [{ subscriptionId: 'moves', channels: ['tablesdb.cjw.tables.coop_moves.rows'], queries: [q('equal', 'gameId', [p.gameId])] }] }));
      ws.send(JSON.stringify({ type: 'subscribe', data: [{ subscriptionId: 'live', channels: ['tablesdb.cjw.tables.coop_drags.rows'], queries: [q('equal', 'gameId', [p.gameId]), q('notEqual', 'userId', [p.userId])] }] }));
    } else if (d.type === 'event' && d.data.payload?.gameId === p.gameId) {
      const row = d.data.payload;
      if (d.data.channels?.some((c) => c.includes('coop_drags'))) {
        p.liveHeard.push({ userId: row.userId, seq: row.seq, phase: row.phase, card: row.card, x: row.x, y: row.y, heardAt: Date.now() });
      } else {
        p.heard.set(row.$id, Date.now());
      }
    }
  };
  return sleep(1200);
}

const players = { host: null, friend: null };

const liveId = (gameId, userId) => createHash('md5').update(`live:${gameId}:${userId}`).digest('hex');

/// The live row the api function makes for a player of a game (read by the game, written by them).
async function liveRow(gameId, userId) {
  try {
    await call('POST', '/tablesdb/cjw/tables/coop_drags/rows', {
      body: { rowId: liveId(gameId, userId), data: { gameId, userId }, permissions: [`read("team:${gameId}")`, `update("user:${userId}")`] },
    });
    return true;
  } catch (e) {
    if (e.code === 409) return false;
    throw e;
  }
}

/// Writes the player's live row as the app does; returns when the update is written.
async function live(p, g, data) {
  p.seq = Math.max(p.seq + 1, Date.now());
  const sentAt = Date.now();
  await call('PATCH', `/tablesdb/cjw/tables/coop_drags/rows/${liveId(g.$id, p.userId)}`, { key: false, session: p.secret, body: { data: { board: g.board, seq: p.seq, ...data } } });
  const entry = { seq: p.seq, phase: data.phase, sentAt, answeredAt: Date.now() };
  p.liveSent.push(entry);
  return entry;
}

/// A slot's centre as a fraction of the board (Cards: a grid of `cols` x `rows`).
function centre(grid, slot) {
  const m = /(\d+)x(\d+)/.exec(grid);
  const cols = Number(m[1]), rows = Number(m[2]);
  return { x: ((slot % cols) + 0.5) / cols, y: (Math.floor(slot / cols) + 0.5) / rows };
}

/// The player drags `card` to slot `to`: positions along the way at `rate` a second, then a drop with
/// the move, or a cancel. Returns what was sent.
async function drag(p, card, to, ms, rate, end) {
  const g = await gameOf(p);
  const b = await boardOf(g);
  const from = b.indexOf(card);
  const a = centre(g.grid, from), z = centre(g.grid, to);
  const id = Date.now();
  const started = Date.now();
  const sent = [];
  const at = (f) => {
    const e = f < 0.5 ? 2 * f * f : 1 - (-2 * f + 2) ** 2 / 2;
    return { x: a.x + (z.x - a.x) * e, y: a.y + (z.y - a.y) * e };
  };
  sent.push(await live(p, g, { phase: 'drag', card, drag: id, t: 0, ...a }));
  const gap = 1000 / rate;
  for (let k = 1; ; k++) {
    const due = started + k * gap;
    const wait = due - Date.now();
    if (wait > 0) await sleep(wait);
    const t = Date.now() - started;
    if (t >= ms) break;
    sent.push(await live(p, g, { phase: 'drag', card, drag: id, t, ...at(t / ms) }));
  }
  const t = Date.now() - started;
  if (end === 'cancel') {
    sent.push(await live(p, g, { phase: 'cancel', card, drag: id, t, ...a }));
    return { sent, from, to };
  }
  sent.push(await live(p, g, { phase: 'drop', card, drag: id, t, ...z }));
  const changes = `${to}:${b[to]}:${card},${from}:${card}:${b[to]}`;
  const moveAt = Date.now();
  await send(p, g, changes);
  return { sent, from, to, changes, moveAt };
}
const extras = [];
let puzzles = { normal: [], giant: [] };

async function catalogue() {
  if (puzzles.normal.length) return;
  const list = async (packId, n) => (await call('GET', '/tablesdb/cjw/tables/puzzles/rows?' + new URLSearchParams([['queries[]', q('equal', 'packId', [packId])], ['queries[]', q('limit', undefined, [n])]]))).rows.map((r) => r.$id);
  puzzles.normal = await list('pack-owls', 5);
  const giantPack = (await call('GET', '/tablesdb/cjw/tables/packs/rows?' + new URLSearchParams([['queries[]', q('equal', 'category', ['Giant'])], ['queries[]', q('limit', undefined, [1])]]))).rows[0];
  if (giantPack) puzzles.giant = await list(giantPack.$id, 2);
}

/// The player's game as they can read it now (board number, layout).
async function gameOf(p) {
  return call('GET', `/tablesdb/cjw/tables/coop_games/rows/${p.gameId}`, { key: false, session: p.secret });
}

async function movesOf(g) {
  const out = [];
  let cursor = null;
  for (;;) {
    const qs = [['queries[]', q('equal', 'gameId', [g.$id])], ['queries[]', q('equal', 'board', [g.board])], ['queries[]', q('orderAsc', '$sequence')], ['queries[]', q('limit', undefined, [100])]];
    if (cursor) qs.push(['queries[]', q('cursorAfter', undefined, [cursor])]);
    const page = await call('GET', '/tablesdb/cjw/tables/coop_moves/rows?' + new URLSearchParams(qs));
    out.push(...page.rows);
    if (page.rows.length < 100) return out;
    cursor = page.rows[page.rows.length - 1].$id;
  }
}

/// The board the server order gives: each change applied only when it fits.
async function boardOf(g) {
  let b = String(g.layout).split(',').map(Number);
  for (const r of await movesOf(g)) {
    const ch = r.changes.split(',').map((x) => x.split(':').map(Number));
    if (ch.every(([s, before]) => b[s] === before)) for (const [s, , after] of ch) b[s] = after;
  }
  return b;
}

async function send(p, g, changes, kind = 'move') {
  const rowId = id();
  await call('POST', '/tablesdb/cjw/tables/coop_moves/rows', {
    key: false,
    session: p.secret,
    body: { rowId, data: { gameId: g.$id, board: g.board, userId: p.userId, kind, changes }, permissions: [`read("team:${g.$id}")`, `read("user:${p.userId}")`] },
  });
  return rowId;
}

/// One misplaced card to its place: the card that belongs in slot s comes from where it is.
const homeChange = (b) => {
  const s = b.findIndex((c, i) => c !== i);
  if (s < 0) return null;
  const from = b.indexOf(s);
  return `${s}:${b[s]}:${s},${from}:${s}:${b[s]}`;
};

function derange(n) {
  for (;;) {
    const a = [...Array(n).keys()].sort(() => Math.random() - 0.5);
    if (a.every((v, i) => v !== i)) return a;
  }
}

async function cleanup() {
  for (const p of Object.values(players)) {
    p?.socket?.close();
  }
  try {
    if (players.host?.gameId) await fn(players.host, 'end', { gameId: players.host.gameId });
  } catch (_) {}
  try {
    execFileSync('python3', [join(ROOT, 'tools', 'dev', 'purge_test_players.py'), 'purge', '--run', RUN, '--include-linked', '--apply', '--quiet'], { stdio: 'inherit' });
  } catch (e) {
    console.log('purge failed:', e.message);
  }
}

const relay = new Map();

const server = createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const arg = (k) => url.searchParams.get(k);
  const send200 = (data) => {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(data));
  };
  try {
    const path = url.pathname;
    const as = players[arg('as') || 'host'];
    if (path === '/game') {
      await catalogue();
      players.host ??= await makePlayer('Juniper Host', 'leaf');
      const giant = arg('giant') === '1' && puzzles.giant.length > 0;
      const cells = giant ? 100 : Number(arg('cells') || 20);
      const grid = giant ? 'cards-10x10t8' : cells === 9 ? 'cards-3x3t0' : 'cards-4x5t3';
      const out = await fn(players.host, 'create', { puzzleId: giant ? puzzles.giant[0] : puzzles.normal[0], grid, layout: derange(cells) });
      if (!out.ok) throw new Error(JSON.stringify(out));
      players.host.gameId = out.game.id;
      await liveRow(out.game.id, players.host.userId);
      await connect(players.host);
      if (arg('full') === '1') {
        for (const n of ['Basil', 'Clover', 'Dahlia', 'Fennel']) {
          const p = await makePlayer(`${n} Tester`, 'drop');
          extras.push(p);
          await fn(p, 'join', { code: out.game.code });
        }
      }
      return send200({ code: out.game.code, gameId: out.game.id, hostId: players.host.userId, layout: out.game.layout, puzzleId: out.game.puzzleId, grid });
    }
    if (path === '/friend') {
      players.friend ??= await makePlayer('Rowan Friend', 'star');
      const code = arg('code') || (players.host ? (await gameOf(players.host)).code : null);
      const out = await fn(players.friend, 'join', { code });
      if (out.ok) {
        players.friend.gameId = out.game.id;
        await liveRow(out.game.id, players.friend.userId);
        await connect(players.friend);
      }
      return send200({ ...out, userId: players.friend.userId });
    }
    if (path === '/move' || path === '/swap') {
      const g = await gameOf(as);
      let changes = arg('changes');
      if (!changes) {
        const b = await boardOf(g);
        if (path === '/swap') {
          // Two loose cards trade places without either landing home.
          const loose = [...b.keys()].filter((i) => b[i] !== i);
          const x = loose[0];
          const y = loose.find((i) => i !== x && b[i] !== x && b[x] !== i) ?? loose[1];
          changes = `${x}:${b[x]}:${b[y]},${y}:${b[y]}:${b[x]}`;
        } else {
          changes = homeChange(b);
        }
      }
      if (!changes) return send200({ ok: false, solved: true });
      if (arg('wait') === '0') {
        send(as, g, changes).catch((e) => console.log('send:', e.message));
        return send200({ ok: true, changes, sentAt: Date.now() });
      }
      const sentAt = Date.now();
      const rowId = await send(as, g, changes);
      return send200({ ok: true, id: rowId, changes, sentAt });
    }
    if (path === '/solve') {
      const g = await gameOf(as);
      let n = 0;
      for (;;) {
        const change = homeChange(await boardOf(g));
        if (!change) break;
        await send(as, g, change);
        n++;
      }
      return send200({ ok: true, moves: n });
    }
    if (path === '/hold') {
      const g = await gameOf(as);
      as.socket.send(JSON.stringify({ type: 'presence', data: { status: 'online', presenceId: `bot${as.userId}`, permissions: [`read("team:${g.$id}")`], metadata: { g: g.$id, b: g.board, h: Number(arg('card')) } } }));
      return send200({ ok: true });
    }
    if (path === '/liverows') {
      // ?game=<id>: a game of the apps' own (read with the key); else the bot player's game.
      const g = arg('game') ? await call('GET', `/tablesdb/cjw/tables/coop_games/rows/${arg('game')}`) : await gameOf(as);
      const made = [];
      for (const u of g.players || []) if (u && (await liveRow(g.$id, u))) made.push(u);
      return send200({ ok: true, made, players: (g.players || []).filter((u) => u) });
    }
    if (path === '/pick') {
      const g = await gameOf(as);
      const card = Number(arg('card'));
      return send200({ ok: true, ...(await live(as, g, card < 0 ? { phase: '', card: -1, drag: 0, t: 0, x: 0, y: 0 } : { phase: 'pick', card, drag: 0, t: 0, x: 0, y: 0 })) });
    }
    if (path === '/drag') {
      const run = drag(as, Number(arg('card')), Number(arg('to')), Number(arg('ms') || 1500), Number(arg('rate') || 5), arg('end') || 'drop');
      if (arg('wait') === '0') {
        run.then((r) => (as.lastDrag = r)).catch((e) => console.log('drag:', e.message));
        return send200({ ok: true, startedAt: Date.now() });
      }
      return send200({ ok: true, ...(await run) });
    }
    if (path === '/live') return send200({ heard: as.liveHeard, sent: as.liveSent, lastDrag: as.lastDrag ?? null });
    if (path === '/remove') return send200(await fn(players.host, 'remove', { gameId: players.host.gameId, userId: arg('user') }));
    if (path === '/end') return send200(await fn(players.host, 'end', { gameId: players.host.gameId }));
    if (path === '/next') {
      await catalogue();
      return send200(await fn(players.host, 'next', { gameId: players.host.gameId, puzzleId: puzzles.normal[1] || puzzles.normal[0], grid: 'cards-4x5t3', layout: derange(20) }));
    }
    if (path === '/relay') {
      if (req.method === 'POST') relay.set(arg('key'), arg('value'));
      return send200({ value: relay.get(arg('key')) ?? null });
    }
    if (path === '/moves') {
      const g = await gameOf(as);
      return send200({ board: await boardOf(g), number: g.board, puzzleId: g.puzzleId, moves: (await movesOf(g)).map((r) => ({ id: r.$id, userId: r.userId, kind: r.kind, seq: Number(r.$sequence), heardAt: as.heard.get(r.$id) ?? null })) });
    }
    if (path === '/quit') {
      send200({ ok: true });
      await cleanup();
      process.exit(0);
    }
    res.writeHead(404);
    res.end('{}');
  } catch (e) {
    console.log(e);
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: e.message }));
  }
});

process.on('SIGINT', async () => {
  await cleanup();
  process.exit(130);
});
server.listen(PORT, '127.0.0.1', () => console.log(`coop bot on http://127.0.0.1:${PORT} (run ${RUN})`));
