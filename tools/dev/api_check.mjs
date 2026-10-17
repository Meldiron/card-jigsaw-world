#!/usr/bin/env node
// Live check of the `api` function (docs/functions.md): every route, called the way the app calls
// it (Functions.createExecution with a player's session), by QA-flagged players on the live backend.
// Prints each call's answer and time (wall time on this Mac and the execution's own duration), then
// cleans up: the pack code it made, the private-pack read access its player got, and its players
// (tools/dev/purge_test_players.py; the account-deletion player deletes itself through the api).
//
//   node tools/dev/api_check.mjs [--function api] [--keep]
//
// Players: Ada (hosts a co-op game, sends gifts, redeems a code), Ben (friend, joins, is removed) and
// Dee (friend, joins, deletes the account). Uses secrets/appwrite-users-key.txt; key values, session
// secrets and the pack code are never printed. Run it after every deployment of `api`.
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes, createHash } from 'node:crypto';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT = '6acb4de5003e38d5ebd9';
const KEY = readFileSync(join(ROOT, 'secrets', 'appwrite-users-key.txt'), 'utf8').trim();
const args = process.argv.slice(2);
const FUNCTION = args.includes('--function') ? args[args.indexOf('--function') + 1] : 'api';
const KEEP = args.includes('--keep');
const RUN = `api-check-${Date.now()}`;
const HIDDEN_PACK = 'pack-hidden-object-test';
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
const rows = (table, queries) => call('GET', `/tablesdb/cjw/tables/${table}/rows?` + new URLSearchParams(queries.map((x) => ['queries[]', x])));
const row = (table, id) => call('GET', `/tablesdb/cjw/tables/${table}/rows/${id}`).catch((e) => (e.code === 404 ? null : Promise.reject(e)));

const results = [];
let failures = 0;

/// One execution of the function as player [p]: the answer, timed.
async function api(p, method, path, body) {
  const t0 = Date.now();
  const exec = await call('POST', `/functions/${FUNCTION}/executions`, {
    key: false,
    session: p.secret,
    body: { path, method, body: body === undefined ? '' : JSON.stringify(body), async: false },
  });
  const wall = Date.now() - t0;
  const answer = exec.responseBody ? JSON.parse(exec.responseBody) : {};
  return { status: exec.responseStatusCode, body: answer, wall, duration: Math.round(exec.duration * 1000) };
}

/// Calls a route and checks the answer with [expect] (status and the body's fields).
async function check(label, p, method, path, body, expect) {
  const r = await api(p, method, path, body);
  const problems = [];
  if (expect.status !== undefined && r.status !== expect.status) problems.push(`status ${r.status}, expected ${expect.status}`);
  for (const [k, v] of Object.entries(expect.body ?? {})) {
    if (JSON.stringify(r.body[k]) !== JSON.stringify(v)) problems.push(`${k} ${JSON.stringify(r.body[k])}, expected ${JSON.stringify(v)}`);
  }
  if (expect.test && !expect.test(r.body)) problems.push('answer check failed');
  const ok = problems.length === 0;
  if (!ok) failures++;
  const shown = JSON.stringify(r.body).replace(/"code":"[A-Z0-9]{8}"/, '"code":"<code>"').slice(0, 160);
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label.padEnd(44)} ${method} ${path.padEnd(18)} ${String(r.status).padEnd(4)} wall ${String(r.wall).padStart(5)} ms  exec ${String(r.duration).padStart(5)} ms  ${shown}${ok ? '' : '  <- ' + problems.join('; ')}`);
  results.push({ label, path, ...r, ok });
  return r.body;
}

function expectTrue(label, value) {
  if (!value) failures++;
  console.log(`${value ? 'ok  ' : 'FAIL'} ${label}`);
}

async function makePlayer(name, avatar) {
  const userId = 'qaapi' + randomBytes(8).toString('hex');
  await call('POST', '/users', { body: { userId, name } });
  await call('PATCH', `/users/${userId}/prefs`, { body: { prefs: { qa: true, qaRun: RUN } } });
  await call('POST', '/tablesdb/cjw/tables/profiles/rows', {
    body: { rowId: userId, data: { userId, displayName: name, avatar, isTest: true }, permissions: ['read("any")', `update("user:${userId}")`] },
  });
  const s = await call('POST', `/users/${userId}/sessions`, { body: {} });
  return { userId, secret: s.secret, name, avatar };
}

/// [a] has [b] in their friends list (as the app writes it).
async function befriend(a, b) {
  const rowId = createHash('md5').update(`${a.userId}:${b.userId}`).digest('hex');
  await call('POST', '/tablesdb/cjw/tables/friends/rows', {
    body: { rowId, data: { userId: a.userId, friendId: b.userId, friendName: b.name, friendAvatar: b.avatar, status: 'accepted' }, permissions: [`read("user:${a.userId}")`, `update("user:${a.userId}")`, `delete("user:${a.userId}")`] },
  });
}

const players = [];
let codeRow = null;
try {
  const ada = await makePlayer('Ada QA', 'owl');
  const ben = await makePlayer('Ben QA', 'fox');
  const dee = await makePlayer('Dee QA', 'cat');
  players.push(ada, ben, dee);
  console.log(`run ${RUN}, function ${FUNCTION}`);

  // Health (the first call of a fresh deployment is its cold start).
  await check('health', ada, 'GET', '/health', undefined, { status: 200, body: { ok: true, environment: 'Production', maxPlayers: 5, appleSignIn: 'set' } });

  // Purchases: refusals only (a real transaction needs the App Store).
  await check('purchase: no transaction', ada, 'POST', '/purchase/verify', {}, { status: 400, body: { ok: false, error: 'Missing transaction' } });
  await check('purchase: not signed by Apple', ada, 'POST', '/purchase/verify', { jws: 'a.b.c', productId: 'tickets_5' }, { status: 400, body: { ok: false, error: 'Transaction could not be verified' } });
  await check('notification: not signed by Apple', ada, 'POST', '/purchase/notifications', { signedPayload: 'a.b.c' }, { status: 401, body: { ok: false } });

  // Pack codes: a wrong code, then a code made for this run (one use).
  await check('code: wrong', ada, 'POST', '/code/redeem', { code: 'AAAA-BBBB-CCCC-DDDD' }, { status: 200, body: { ok: false, error: 'invalid' } });
  const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  const code = Array.from(randomBytes(16), (b) => alphabet[b % alphabet.length]).join('');
  codeRow = await call('POST', '/tablesdb/cjw/tables/pack_codes/rows', {
    body: { rowId: 'unique()', data: { codeHash: createHash('sha256').update(code).digest('hex'), packId: HIDDEN_PACK, maxUses: 1, uses: 0, note: `api check ${RUN}` } },
  });
  await check('code: right', ada, 'POST', '/code/redeem', { code }, { status: 200, body: { ok: true, packId: HIDDEN_PACK, repeat: false } });
  await check('code: same player again', ada, 'POST', '/code/redeem', { code }, { status: 200, body: { ok: true, repeat: true } });
  await check('code: used up for another player', ben, 'POST', '/code/redeem', { code }, { status: 200, body: { ok: false, error: 'used' } });
  expectTrue('code: the pack is unlocked on the profile', ((await row('profiles', ada.userId)).unlockedPacks || []).includes(HIDDEN_PACK));

  // Friend gifts.
  await befriend(ada, ben);
  await befriend(ben, ada);
  await befriend(ada, dee);
  await befriend(dee, ada);
  await check('gift: not a friend', ben, 'POST', '/gift/send', { friendId: dee.userId, kind: 'coins', utcOffset: 120 }, { status: 403, body: { ok: false, error: 'not-friend' } });
  await check('gift: 1 ticket', ada, 'POST', '/gift/send', { friendId: ben.userId, kind: 'tickets', utcOffset: 120 }, { status: 200, body: { ok: true, kind: 'tickets', amount: 1, friendName: 'Ben QA' } });
  await check('gift: second today', ada, 'POST', '/gift/send', { friendId: ben.userId, kind: 'coins', utcOffset: 120 }, { status: 200, body: { ok: false, error: 'already' } });
  await check('gift: 150 coins back', ben, 'POST', '/gift/send', { friendId: ada.userId, kind: 'coins', utcOffset: 120 }, { status: 200, body: { ok: true, amount: 150 } });
  await check('gift: to Dee (deleted later)', ada, 'POST', '/gift/send', { friendId: dee.userId, kind: 'tickets', utcOffset: 120 }, { status: 200, body: { ok: true } });
  const inbox = (await rows('messages', [q('equal', 'userId', [ben.userId])])).rows;
  expectTrue('gift: in the friend\'s inbox, from Ada, 1 ticket', inbox.some((m) => m.fromUserId === ada.userId && m.rewardTickets === 1));

  // Play together.
  const puzzleId = (await rows('puzzles', [q('equal', 'packId', ['pack-owls']), q('limit', undefined, [2])])).rows.map((r) => r.$id);
  const layout = (n) => Array.from({ length: n }, (_, i) => (i + 1) % n);
  const game = (await check('coop: create', ada, 'POST', '/coop/create', { puzzleId: puzzleId[0], grid: 'cards-3x3t0', layout: layout(9), painting: false }, { status: 200, body: { ok: true }, test: (b) => b.game?.players?.[0] === ada.userId })).game;
  await check('coop: join', ben, 'POST', '/coop/join', { code: game.code }, { status: 200, test: (b) => b.game?.players?.includes(ben.userId) });
  await check('coop: join (Dee)', dee, 'POST', '/coop/join', { code: game.code }, { status: 200, test: (b) => b.game?.players?.includes(dee.userId) });
  await check('coop: join again keeps the seat', ben, 'POST', '/coop/join', { code: game.code }, { status: 200, test: (b) => b.game?.players?.[1] === ben.userId });
  // Live rows (picks and drags): one per player, read by the game, written by its player.
  const liveId = (u) => createHash('md5').update(`live:${game.id}:${u.userId}`).digest('hex');
  for (const p of [ada, ben, dee]) {
    const r = await row('coop_drags', liveId(p));
    expectTrue(`coop: live row of ${p.name ?? p.userId}`, r && [...r.$permissions].sort().join() === [`read("team:${game.id}")`, `update("user:${p.userId}")`].sort().join());
  }
  await check('coop: next board (guest refused)', ben, 'POST', '/coop/next', { gameId: game.id, puzzleId: puzzleId[1], grid: 'cards-4x5t3', layout: layout(20) }, { status: 403, body: { reason: 'host' } });
  await check('coop: next board', ada, 'POST', '/coop/next', { gameId: game.id, puzzleId: puzzleId[1] ?? puzzleId[0], grid: 'cards-4x5t3', layout: layout(20) }, { status: 200, test: (b) => b.game?.board === 2 });
  await check('coop: leave', ben, 'POST', '/coop/leave', { gameId: game.id }, { status: 200, body: { ok: true, left: true } });
  expectTrue('coop: a guest who left has no live row', (await row('coop_drags', liveId(ben))) === null);
  await check('coop: back after leaving', ben, 'POST', '/coop/join', { code: game.code }, { status: 200, test: (b) => b.game?.players?.includes(ben.userId) });
  await check('coop: remove', ada, 'POST', '/coop/remove', { gameId: game.id, userId: ben.userId }, { status: 200, test: (b) => !b.game?.players?.includes(ben.userId) && b.game?.removed?.includes(ben.userId) });
  expectTrue('coop: a removed player has no live row', (await row('coop_drags', liveId(ben))) === null);
  await check('coop: removed cannot come back', ben, 'POST', '/coop/join', { code: game.code }, { status: 403, body: { ok: false, reason: 'removed' } });
  await check('coop: a code that does not exist', ben, 'POST', '/coop/join', { code: 'ZZZZZZZZ' }, { status: 404, body: { ok: false, reason: 'ended' } });
  await check('coop: a picture outside the Library', ada, 'POST', '/coop/create', { puzzleId: 'no-such-picture', grid: 'cards-3x3t0', layout: layout(9) }, { status: 400, body: { reason: 'picture' } });

  // Account deletion (Dee: a profile, friend links both ways, a gift received, a seat in Ada's game).
  const deleted = await check('account: delete', dee, 'POST', '/account/delete', {}, { status: 200, body: { ok: true, user: true, apple: 'not-apple' } });
  const deeId = dee.userId;
  players.splice(players.indexOf(dee), 1);
  expectTrue(`account: rows deleted ${JSON.stringify(deleted.rows)}`, deleted.rows?.profiles === 1 && deleted.rows?.friends >= 2 && deleted.rows?.gifts >= 1 && deleted.rows?.messages >= 1);
  expectTrue('account: the user is gone', (await call('GET', `/users/${deeId}`).catch((e) => e.code)) === 404);
  expectTrue("account: Ada's friend link to Dee is gone", (await rows('friends', [q('equal', 'friendId', [deeId])])).total === 0);
  expectTrue("account: Dee's seat in Ada's game is empty", !((await row('coop_games', game.id))?.players || []).includes(deeId));
  await check('account: without a session', { secret: '' }, 'POST', '/account/delete', {}, { status: 401 }).catch((e) => {
    // Appwrite refuses a guest without a session before the function runs (execute: users).
    expectTrue(`account: a call without a session is refused by Appwrite (${e.code})`, e.code === 401);
  });

  await check('coop: end', ada, 'POST', '/coop/end', { gameId: game.id }, { status: 200, test: (b) => b.game?.status === 'ended' && b.game?.endReason === 'host' });
  await check('coop cleanup: refused for a player', ada, 'POST', '/coop/cleanup', undefined, { status: 404 });
  await check('nothing at the root', ada, 'POST', '/', {}, { status: 404 });
  await check('old paths are not routes', ada, 'POST', '/delete', {}, { status: 404 });
} catch (e) {
  failures++;
  console.log('FAIL', e.stack || e.message);
} finally {
  if (!KEEP) {
    if (codeRow) await call('DELETE', `/tablesdb/cjw/tables/pack_codes/rows/${codeRow.$id}`).catch((e) => console.log('code row:', e.message));
    // The private pictures' read access for this run's players (the purge leaves file permissions).
    for (const p of players) await revokePrivateReads(p.userId).catch((e) => console.log('private files:', e.message));
    for (const p of players) await call('DELETE', `/users/${p.userId}/sessions`).catch(() => {});
    try {
      execFileSync('python3', [join(ROOT, 'tools', 'dev', 'purge_test_players.py'), 'purge', '--run', RUN, '--include-linked', '--apply', '--quiet'], { stdio: 'inherit' });
    } catch (e) {
      console.log('purge failed:', e.message);
    }
  } else {
    console.log(`kept: purge with purge_test_players.py purge --run ${RUN} --include-linked --apply`);
  }
  console.log(failures ? `${failures} check(s) failed` : 'all checks passed');
  process.exitCode = failures ? 1 : 0;
}

async function revokePrivateReads(userId) {
  const reader = `read("user:${userId}")`;
  let cursor = null;
  let removed = 0;
  for (;;) {
    const qs = [q('limit', undefined, [100]), ...(cursor ? [q('cursorAfter', undefined, [cursor])] : [])];
    const page = await call('GET', '/storage/buckets/private-packs/files?' + new URLSearchParams(qs.map((x) => ['queries[]', x])));
    for (const f of page.files) {
      if (!(f.$permissions || []).includes(reader)) continue;
      await call('PUT', `/storage/buckets/private-packs/files/${f.$id}`, { body: { permissions: f.$permissions.filter((x) => x !== reader) } });
      removed++;
    }
    if (page.files.length < 100) break;
    cursor = page.files[page.files.length - 1].$id;
  }
  if (removed) console.log(`private pictures: read access of ${userId} removed from ${removed} file(s)`);
}
