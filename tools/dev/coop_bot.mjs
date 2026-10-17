#!/usr/bin/env node
// Play together QA: a host (and helpers) on the live backend for the app on the simulator to play
// with. It makes QA-flagged players (prefs qa, qaRun coop-bot-<time>), plays as them through the
// coop-game function, the moves table and a realtime socket, and is driven over HTTP on
// 127.0.0.1:8787 (the iOS simulator reaches the Mac's localhost): integration_test/coop_live_test.dart
// calls it. On /quit (or Ctrl-C) it ends its games and purges its players
// (tools/dev/purge_test_players.py, which deletes their games and moves; teams go with coop-cleanup).
//
//   node tools/dev/coop_bot.mjs            then run the integration test through tools/dev/qa-run.sh
//
// Routes (POST unless noted; JSON answers):
//   /game?cells=20&full=0     a new game hosted by the bot (full=1: four more players join it)
//   /friend?code=C            a second bot player joins the current game (or the game of code C)
//   /move                     the host makes one move (two misplaced cards change places)
//   /hold?card=N              the host holds card N (presence over its realtime socket)
//   /remove?user=ID           the host removes a player
//   /end                      the host ends the game for everyone
//   /next                     the host opens the next board
//   GET /moves                the game's moves (author, sequence, when the bot heard each over realtime)
//   /quit                     clean up and stop
import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { execFileSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT = '6acb4de5003e38d5ebd9';
const KEY = readFileSync(join(ROOT, 'secrets', 'appwrite-users-key.txt'), 'utf8').trim();
const RUN = `coop-bot-${Date.now()}`;
const PORT = Number(process.env.COOP_BOT_PORT || 8787);
const id = () => randomBytes(10).toString('hex');
const q = (method, attribute, values) => JSON.stringify(attribute === undefined ? { method, values } : { method, attribute, values });

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

const players = [];
async function player(name) {
  const userId = id();
  await call('POST', '/users', { body: { userId, name } });
  await call('PATCH', `/users/${userId}/prefs`, { body: { prefs: { qa: true, qaRun: RUN } } });
  // A profile row so the app shows a name (profiles are public); flagged as a test player.
  await call('POST', '/tablesdb/cjw/tables/profiles/rows', {
    body: { rowId: userId, data: { userId, displayName: name, avatar: 'fox', isTest: true }, permissions: ['read("any")'] },
  }).catch((e) => console.log('profile:', e.message));
  const s = await call('POST', `/users/${userId}/sessions`, { body: {} });
  const p = { userId, secret: s.secret, name };
  players.push(p);
  return p;
}

async function fn(p, action, body) {
  const exec = await call('POST', '/functions/coop-game/executions', { key: false, session: p.secret, body: { body: JSON.stringify(body), path: `/${action}`, method: 'POST', async: false } });
  return exec.responseBody ? JSON.parse(exec.responseBody) : {};
}

// The bot's realtime socket (the host's): hears the moves, keeps a presence.
let socket = null;
const heard = new Map();
function connect(p, gameId) {
  socket?.close();
  const ws = new WebSocket(`wss://fra.cloud.appwrite.io/v1/realtime?project=${PROJECT}`);
  socket = ws;
  ws.onmessage = (m) => {
    const d = JSON.parse(m.data);
    if (d.type === 'connected') {
      ws.send(JSON.stringify({ type: 'authentication', data: { session: p.secret } }));
      ws.send(JSON.stringify({ type: 'subscribe', data: [{ subscriptionId: 'moves', channels: ['tablesdb.cjw.tables.coop_moves.rows'], queries: [q('equal', 'gameId', [gameId])] }] }));
    } else if (d.type === 'event' && d.data.payload?.gameId === gameId) {
      heard.set(d.data.payload.$id, Date.now());
    }
  };
  return new Promise((r) => setTimeout(r, 1200));
}

let host = null;
let game = null;
let puzzles = [];

async function newGame(cells, full) {
  if (!host) host = await player('Juniper Host');
  if (!puzzles.length) puzzles = (await call('GET', '/tablesdb/cjw/tables/puzzles/rows?' + new URLSearchParams([['queries[]', q('equal', 'packId', ['pack-owls'])], ['queries[]', q('limit', undefined, [5])]]))).rows.map((r) => r.$id);
  const layout = derange(cells);
  const out = await fn(host, 'create', { puzzleId: puzzles[0], grid: cells === 20 ? 'cards-4x5t3' : 'cards-3x3t0', layout });
  if (!out.ok) throw new Error(JSON.stringify(out));
  game = out.game;
  await connect(host, game.id);
  if (full) {
    for (const n of ['Basil', 'Clover', 'Dahlia', 'Fennel']) {
      const p = await player(`${n} Tester`);
      await fn(p, 'join', { code: game.code });
    }
  }
  return game;
}

function derange(n) {
  for (;;) {
    const a = [...Array(n).keys()].sort(() => Math.random() - 0.5);
    if (a.every((v, i) => v !== i)) return a;
  }
}

async function moves() {
  const page = await call('GET', '/tablesdb/cjw/tables/coop_moves/rows?' + new URLSearchParams([['queries[]', q('equal', 'gameId', [game.id])], ['queries[]', q('equal', 'board', [game.board])], ['queries[]', q('orderAsc', '$sequence')], ['queries[]', q('limit', undefined, [500])]]));
  return page.rows;
}

async function board() {
  let b = String(game.layout).split(',').map(Number);
  for (const r of await moves()) {
    const ch = r.changes.split(',').map((x) => x.split(':').map(Number));
    if (ch.every(([s, before]) => b[s] === before)) for (const [s, , after] of ch) b[s] = after;
  }
  return b;
}

async function move() {
  const b = await board();
  // Put one misplaced card in its place: the card that belongs in slot s comes from where it is.
  const s = b.findIndex((c, i) => c !== i);
  const from = b.indexOf(s);
  const changes = `${s}:${b[s]}:${s},${from}:${s}:${b[s]}`;
  const rowId = id();
  const sentAt = Date.now();
  await call('POST', '/tablesdb/cjw/tables/coop_moves/rows', {
    key: false,
    session: host.secret,
    body: { rowId, data: { gameId: game.id, board: game.board, userId: host.userId, kind: 'move', changes }, permissions: [`read("team:${game.id}")`, `read("user:${host.userId}")`] },
  });
  return { id: rowId, sentAt, changes };
}

async function cleanup() {
  try {
    if (game && host) await fn(host, 'end', { gameId: game.id });
  } catch (_) {}
  socket?.close();
  try {
    execFileSync('python3', [join(ROOT, 'tools', 'dev', 'purge_test_players.py'), 'purge', '--run', RUN, '--include-linked', '--apply', '--quiet'], { stdio: 'inherit' });
  } catch (e) {
    console.log('purge failed:', e.message);
  }
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const send = (code, data) => {
    res.writeHead(code, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(data));
  };
  try {
    const p = url.pathname;
    if (p === '/game') {
      const g = await newGame(Number(url.searchParams.get('cells') || 20), url.searchParams.get('full') === '1');
      return send(200, { code: g.code, gameId: g.id, hostId: host.userId, layout: g.layout });
    }
    if (p === '/friend') {
      const f = await player('Rowan Friend');
      return send(200, { ...(await fn(f, 'join', { code: url.searchParams.get('code') || game.code })), userId: f.userId });
    }
    if (p === '/move') return send(200, await move());
    if (p === '/hold') {
      socket.send(JSON.stringify({ type: 'presence', data: { status: 'online', presenceId: id(), permissions: [`read("team:${game.id}")`], metadata: { g: game.id, b: game.board, h: Number(url.searchParams.get('card')) } } }));
      return send(200, { ok: true });
    }
    if (p === '/remove') return send(200, await fn(host, 'remove', { gameId: game.id, userId: url.searchParams.get('user') }));
    if (p === '/end') return send(200, await fn(host, 'end', { gameId: game.id }));
    if (p === '/next') {
      const out = await fn(host, 'next', { gameId: game.id, puzzleId: puzzles[1] || puzzles[0], grid: 'cards-4x5t3', layout: derange(20) });
      if (out.ok) game = out.game;
      return send(200, out);
    }
    if (p === '/moves') return send(200, { moves: (await moves()).map((r) => ({ id: r.$id, userId: r.userId, seq: Number(r.$sequence), createdAt: r.$createdAt, heardAt: heard.get(r.$id) ?? null })), board: await board() });
    if (p === '/quit') {
      send(200, { ok: true });
      await cleanup();
      process.exit(0);
    }
    send(404, { error: 'not found' });
  } catch (e) {
    console.log(e);
    send(500, { error: e.message });
  }
});

process.on('SIGINT', async () => {
  await cleanup();
  process.exit(130);
});
server.listen(PORT, '127.0.0.1', () => console.log(`coop bot on http://127.0.0.1:${PORT} (run ${RUN})`));
