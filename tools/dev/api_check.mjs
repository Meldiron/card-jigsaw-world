#!/usr/bin/env node
// Live check of the `api` function (docs/functions.md): every route, called the way the app calls
// it (Functions.createExecution with a player's session), by QA-flagged players on the live backend,
// and every route without a session (the REST API and the function's domain, as Apple calls it).
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

// Callers without a session. Once anyone may execute `api` (execute `any`, so that Apple can send its
// notifications to the function's domain, https://cjw-api.fra.appwrite.run), such a caller, through the
// REST API or the domain, must reach nothing but /health and the notifications route (which needs
// Apple's signature), and x-appwrite-* headers it sends must not count. Before that, Appwrite must
// refuse every such call.
const DOMAIN = 'https://cjw-api.fra.appwrite.run';
const NO_SESSION = [
  ['GET', '/health', undefined, 200],
  ['POST', '/purchase/notifications', { signedPayload: 'a.b.c' }, 401],
  ['POST', '/purchase/notifications', {}, 400],
  ['POST', '/purchase/verify', { jws: 'a.b.c' }, 401],
  ['POST', '/account/delete', {}, 401],
  ['POST', '/code/redeem', { code: 'AAAA-BBBB-CCCC-DDDD' }, 401],
  ['POST', '/gift/send', { friendId: 'x', kind: 'coins' }, 401],
  ...['create', 'join', 'leave', 'remove', 'end', 'next'].map((a) => ['POST', `/coop/${a}`, {}, 401]),
  ['POST', '/coop/cleanup', {}, 404],
  ['POST', '/admin/sweep', { dryRun: false, full: true }, 404],
  ['POST', '/', {}, 404],
];

/// One call without a session: `rest` through Functions.createExecution, `domain` straight to the
/// function's domain (as Apple calls it). Appwrite's own refusal comes back as `{ appwrite: status }`.
async function anonymous(via, method, path, body, headers = {}) {
  const t0 = Date.now();
  if (via === 'domain') {
    const r = await fetch(DOMAIN + path, { method, headers: { 'Content-Type': 'application/json', ...headers }, body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await r.text();
    let answer = {};
    try { answer = text ? JSON.parse(text) : {}; } catch { answer = { text: text.slice(0, 80) }; }
    if (answer.type?.startsWith('router_')) return { appwrite: r.status, body: answer, wall: Date.now() - t0 };
    return { status: r.status, body: answer, wall: Date.now() - t0 };
  }
  try {
    const exec = await call('POST', `/functions/${FUNCTION}/executions`, { key: false, body: { path, method, body: body === undefined ? '' : JSON.stringify(body), async: false } });
    return { status: exec.responseStatusCode, body: exec.responseBody ? JSON.parse(exec.responseBody) : {}, wall: Date.now() - t0 };
  } catch (e) {
    return { appwrite: e.code, body: { error: e.message }, wall: Date.now() - t0 };
  }
}

async function checkWithoutSession(spoofAs) {
  // Until execute is `any`, Appwrite refuses every call without a session before the function runs.
  const open = (await anonymous('domain', 'GET', '/health')).status === 200;
  if (!open) console.log('note no session: api is not executable without a session (execute is not `any`), so Apple cannot reach its domain; its notification URL stays on verify-purchase (docs/functions.md)');
  for (const via of ['rest', 'domain']) {
    for (const [method, path, body, want] of NO_SESSION) {
      const r = await anonymous(via, method, path, body);
      const ok = open ? r.status === want : Boolean(r.appwrite);
      if (!ok) failures++;
      const got = r.appwrite ? `refused by Appwrite ${r.appwrite}` : `${r.status}`;
      console.log(`${ok ? 'ok  ' : 'FAIL'} ${`no session (${via})`.padEnd(44)} ${method} ${path.padEnd(18)} ${got.padEnd(4)} wall ${String(r.wall).padStart(5)} ms  ${JSON.stringify(r.body).slice(0, 100)}${ok ? '' : `  <- expected ${open ? `${want} from the function` : 'a refusal by Appwrite'}`}`);
    }
  }
  if (!open) return;
  // Headers a caller sends through the domain do not make it a player, an event or the schedule.
  const asPlayer = await anonymous('domain', 'POST', '/coop/join', { code: 'ZZZZZZZZ' }, { 'x-appwrite-user-id': spoofAs });
  expectTrue(`no session (domain): x-appwrite-user-id of a player is ignored (${asPlayer.status} ${asPlayer.body.reason ?? ''})`, asPlayer.status === 401 && asPlayer.body.reason === 'auth');
  const asEvent = await anonymous('domain', 'POST', '/', {}, { 'x-appwrite-trigger': 'event', 'x-appwrite-event': 'tablesdb.cjw.tables.friends.rows.x.create' });
  expectTrue(`no session (domain): x-appwrite-trigger event is ignored (${asEvent.status})`, asEvent.status === 404 && !asEvent.body.ignored);
}

// Invite pages (docs/multiplayer.md, "Invite links"): what Messages, WhatsApp and Facebook read at
// https://join.carden.page/<code>, without a session. Messages sends a Safari user agent with
// facebookexternalhit and Twitterbot in it; WhatsApp and Facebook their own.
const JOIN = 'https://join.carden.page';
const READERS = {
  messages: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1 facebookexternalhit/1.1 Facebot Twitterbot/1.0',
  whatsapp: 'WhatsApp/2.25.21.80 i',
  facebook: 'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)',
  safari: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1',
};

/// The invite page of [code] as [reader] sees it: status, meta tags, size, time.
async function invitePage(code, reader, query = '') {
  const t0 = Date.now();
  const r = await fetch(`${JOIN}/${code}${query}`, { headers: { 'user-agent': READERS[reader] }, redirect: 'manual' });
  const html = await r.text();
  const meta = {};
  for (const m of html.matchAll(/<meta property="(og:[a-z:_]+)" content="([^"]*)">/g)) meta[m[1]] = m[2].replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>');
  return { status: r.status, type: r.headers.get('content-type'), edge: r.headers.get('cf-cache-status'), html, meta, bytes: Buffer.byteLength(html), wall: Date.now() - t0 };
}

/// Width and height of a JPEG (its SOF marker).
function jpegSize(b) {
  for (let i = 2; i < b.length - 9; ) {
    if (b[i] !== 0xff) return null;
    const marker = b[i + 1];
    const len = b.readUInt16BE(i + 2);
    if (marker >= 0xc0 && marker <= 0xc3) return [b.readUInt16BE(i + 7), b.readUInt16BE(i + 5)];
    i += 2 + len;
  }
  return null;
}

/// The invite of [game] (hosted by [host], picture [title]) as every reader sees it, and its card.
async function checkInvite(game, host, title, board) {
  const probe = await fetch(`${JOIN}/.well-known/apple-app-site-association`).catch((e) => e);
  if (!(probe instanceof Response)) {
    console.log(`note invite page: ${JOIN} does not answer yet (${probe.cause?.code ?? probe.message}); skipped`);
    return;
  }
  const aasa = await probe.json().catch(() => ({}));
  expectTrue(`invite: association file names the app and invites (${probe.status})`, probe.status === 200 && JSON.stringify(aasa).includes('C24QP73SQM.com.matejbaco.cardjigsawworld') && JSON.stringify(aasa).includes('/????????'));
  let image = null;
  for (const reader of Object.keys(READERS)) {
    const p = await invitePage(game.code, reader);
    const ok = p.status === 200 && p.type?.startsWith('text/html') && p.meta['og:title'] === `${host.name} invites you to play ${title}` && p.meta['og:description'] === `Play together in Carden · ${board} · 1 of 5 players` && p.meta['og:url'] === `${JOIN}/${game.code}` && /\/storage\/buckets\/invite-cards\/files\/[0-9a-f]{32}\/view\?project=/.test(p.meta['og:image'] ?? '') && p.bytes < 300 * 1024 && !p.html.includes(host.userId) && !p.html.includes(game.id);
    expectTrue(`invite page as ${reader.padEnd(9)} ${String(p.status)} ${String(p.wall).padStart(5)} ms (edge ${p.edge ?? '-'}), ${p.bytes} bytes: "${p.meta['og:title']}" / "${p.meta['og:description']}"`, ok);
    image ??= p.meta['og:image'];
  }
  if (image) {
    const t0 = Date.now();
    const r = await fetch(image, { headers: { 'user-agent': READERS.whatsapp } });
    const bytes = Buffer.from(await r.arrayBuffer());
    const size = jpegSize(bytes);
    expectTrue(`invite card: ${r.status} ${r.headers.get('content-type')} ${Math.round(bytes.length / 1024)} KB ${size?.join(' x ')} in ${Date.now() - t0} ms (WhatsApp: under 600 KB; Messages: 900 px wide or more)`, r.status === 200 && r.headers.get('content-type') === 'image/jpeg' && bytes.length < 600 * 1024 && size?.[0] === 1200 && size?.[1] === 630);
  }
  // The domain answers invites and nothing else.
  const post = await fetch(`${JOIN}/coop/join`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ code: game.code }) });
  expectTrue(`invite domain: POST /coop/join is not found there (${post.status})`, post.status === 404);
  const root = await fetch(`${JOIN}/`, { redirect: 'manual' });
  expectTrue(`invite domain: the root goes to the web game (${root.status} ${root.headers.get('location')})`, root.status >= 300 && root.status < 400 && root.headers.get('location') === 'https://play.carden.page/');
}

/// An ended or unknown invite: the site's own card and words.
async function checkEndedInvite(code, label) {
  // A query of its own, past the edge's copy of the live page (kept ten minutes).
  const p = await invitePage(code, 'messages', `?check=${Date.now()}`).catch(() => null);
  if (!p) return;
  expectTrue(`invite page, ${label}: the site's card (${p.status}, "${p.meta['og:title']}")`, p.status === 200 && p.meta['og:image'] === 'https://play.carden.page/invite-card.jpg' && p.meta['og:title'] === 'Carden: Your calm picture puzzle' && p.html.includes('This game has ended'));
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

  // Callers without a session (Apple, and anyone else).
  if (FUNCTION === 'api') await checkWithoutSession(ada.userId);

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
  const owls = (await rows('puzzles', [q('equal', 'packId', ['pack-owls']), q('limit', undefined, [2])])).rows;
  const puzzleId = owls.map((r) => r.$id);
  const layout = (n) => Array.from({ length: n }, (_, i) => (i + 1) % n);
  const game = (await check('coop: create', ada, 'POST', '/coop/create', { puzzleId: puzzleId[0], grid: 'cards-3x3t0', layout: layout(9), painting: false }, { status: 200, body: { ok: true }, test: (b) => b.game?.players?.[0] === ada.userId })).game;
  if (FUNCTION === 'api') await checkInvite(game, ada, owls[0].title, 'Cards 3x3');
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
    // Appwrite refuses a call without a session before the function runs while execute is `users`.
    expectTrue(`account: a call without a session is refused by Appwrite (${e.code})`, e.code === 401);
  });

  await check('coop: end', ada, 'POST', '/coop/end', { gameId: game.id }, { status: 200, test: (b) => b.game?.status === 'ended' && b.game?.endReason === 'host' });
  if (FUNCTION === 'api') {
    await checkEndedInvite(game.code, 'ended game');
    await checkEndedInvite('ZZZZZZZZ', 'unknown code');
  }
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
