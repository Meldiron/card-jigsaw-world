// The router (src/main.js): every route reaches its module, nothing runs at the root, a scheduled
// execution runs the co-op cleanup, the manual cleanup refuses players, and calls without a user are
// refused as the old functions refused them.
//
//   cd functions/api && npm install && npm test
import { test, mock } from 'node:test';
import assert from 'node:assert/strict';

// An empty project: every list is empty, so the cleanup has nothing to do. Its only user is `u1`
// (Users.get of anyone else is 404, as for the owner's console account).
const calls = [];
const empty = new Proxy({}, {
  get: (_, method) => async (args) => {
    calls.push(method);
    if (method === 'get' && args?.userId !== 'u1') throw Object.assign(new Error('User not found'), { code: 404 });
    return { total: 0, rows: [], teams: [], memberships: [], files: [], messages: [] };
  },
});
class Service { constructor() { return empty; } }

mock.module('node-appwrite', {
  namedExports: {
    Client: class { setEndpoint() { return this; } setProject() { return this; } setKey() { return this; } },
    TablesDB: Service,
    Teams: Service,
    Users: Service,
    Storage: Service,
    Messaging: Service,
    ID: { unique: () => 'id' },
    Query: new Proxy({}, { get: (_, name) => (...args) => ({ [name]: args }) }),
    Permission: { read: (r) => `read(${r})` },
    Role: { user: (id) => `user:${id}`, team: (id) => `team:${id}` },
    Operator: { increment: (n) => ({ increment: n }) },
  },
});
mock.module('@apple/app-store-server-library', {
  namedExports: {
    SignedDataVerifier: class {},
    Environment: { SANDBOX: 'Sandbox', PRODUCTION: 'Production' },
  },
});

const { default: handler, routeOf } = await import('../src/main.js');
const { COOP_ACTIONS } = await import('../src/coop/game.js');

async function run(method, path, { headers = {}, body } = {}) {
  let out;
  await handler({
    req: { method, path, headers, body: body === undefined ? '' : JSON.stringify(body) },
    res: { json: (b, status = 200) => (out = { status, body: b }) },
    log: () => {},
    error: () => {},
  });
  return out;
}

const player = { 'x-appwrite-user-id': 'u1', 'x-appwrite-trigger': 'http' };

test('routes are method and path, trailing slashes ignored', () => {
  assert.equal(routeOf({ method: 'post', path: '/coop/join/' }), 'POST /coop/join');
  assert.equal(routeOf({ method: 'GET', path: '' }), 'GET /');
});

test('every co-op action of the module is routed', async () => {
  assert.deepEqual([...COOP_ACTIONS].sort(), ['create', 'end', 'join', 'leave', 'next', 'remove']);
  for (const a of COOP_ACTIONS) {
    // Reaching the module without a user gives its own refusal, not the router's 404.
    const r = await run('POST', `/coop/${a}`, { headers: { 'x-appwrite-trigger': 'http' }, body: {} });
    assert.equal(r.body.reason, 'auth', a);
  }
});

test('GET /health', async () => {
  const r = await run('GET', '/health', { headers: player });
  assert.deepEqual(r, { status: 200, body: { ok: true, environment: 'Sandbox', maxPlayers: 5, appleSignIn: 'missing' } });
});

test('nothing runs at the root or on an unknown path', async () => {
  for (const [method, path] of [['POST', '/'], ['GET', '/'], ['POST', '/delete'], ['POST', '/verify'], ['POST', '/send'], ['POST', '/join'], ['GET', '/coop/join'], ['POST', '/coop/nope'], ['GET', '/account/delete']]) {
    const r = await run(method, path, { headers: player });
    assert.deepEqual(r, { status: 404, body: { ok: false, error: 'Not found' } }, `${method} ${path}`);
  }
});

test('calls without a user are refused, each as its old function did', async () => {
  const anon = { 'x-appwrite-trigger': 'http' };
  assert.deepEqual(await run('POST', '/coop/join', { headers: anon, body: { code: 'ABCDEFGH' } }), { status: 401, body: { ok: false, reason: 'auth', error: 'Sign in required' } });
  assert.deepEqual(await run('POST', '/gift/send', { headers: anon, body: {} }), { status: 401, body: { ok: false, error: 'signin' } });
  assert.deepEqual(await run('POST', '/code/redeem', { headers: anon, body: {} }), { status: 401, body: { ok: false, error: 'signin' } });
  assert.deepEqual(await run('POST', '/account/delete', { headers: anon, body: {} }), { status: 401, body: { ok: false, error: 'Sign in required' } });
  assert.deepEqual(await run('POST', '/purchase/verify', { headers: anon, body: {} }), { status: 401, body: { ok: false, error: 'Sign in required' } });
});

test('a co-op refusal keeps its reason', async () => {
  const r = await run('POST', '/coop/join', { headers: player, body: { code: 'nope' } });
  assert.deepEqual(r, { status: 404, body: { ok: false, reason: 'ended', error: 'This invite link does not work.' } });
});

test('a scheduled execution runs the co-op cleanup, whatever its path', async () => {
  calls.length = 0;
  const r = await run('POST', '/', { headers: { 'x-appwrite-trigger': 'schedule' } });
  assert.deepEqual(r, { status: 200, body: { ok: true, ended: 0, deleted: 0, oldBoards: 0, teams: 0 } });
  assert.ok(calls.includes('listRows') && calls.includes('list'), 'it read the games and the teams');
});

test('the manual cleanup is for callers who are not players only', async () => {
  assert.deepEqual(await run('POST', '/coop/cleanup', { headers: player }), { status: 404, body: { ok: false, error: 'Not found' } });
  for (const headers of [{ 'x-appwrite-trigger': 'http' }, { 'x-appwrite-trigger': 'http', 'x-appwrite-user-id': 'console-owner' }]) {
    const r = await run('POST', '/coop/cleanup', { headers });
    assert.equal(r.status, 200, JSON.stringify(headers));
    assert.equal(r.body.ok, true);
  }
});
