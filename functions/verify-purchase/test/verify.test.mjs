// POST /verify against an in-memory database: every transaction is granted exactly once, also
// when two calls for it arrive at once, and a grant that fails frees the transaction again.
//
//   cd functions/verify-purchase && npm install && node --test --experimental-test-module-mocks test/
import { test, mock, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

class Conflict extends Error {
  constructor() { super('Document with the requested ID already exists.'); this.code = 409; }
}
class Missing extends Error {
  constructor() { super('Row not found'); this.code = 404; }
}

let tables;
let nextId = 0;
const db = {
  async getRow({ tableId, rowId }) {
    const row = tables[tableId].get(rowId);
    if (!row) throw new Missing();
    return { ...row };
  },
  async updateRow({ tableId, rowId, data }) {
    await new Promise((r) => setTimeout(r, 5));
    const row = tables[tableId].get(rowId);
    if (!row) throw new Missing();
    for (const [k, v] of Object.entries(data)) row[k] = v?.increment !== undefined ? (row[k] ?? 0) + v.increment : v;
    return { ...row };
  },
  async createRow({ tableId, rowId, data }) {
    await new Promise((r) => setTimeout(r, 5));
    const t = tables[tableId];
    if (tableId === 'purchases' && [...t.values()].some((r) => r.transactionId === data.transactionId)) throw new Conflict();
    const row = { ...data, $id: rowId };
    t.set(rowId, row);
    return { ...row };
  },
  async deleteRow({ tableId, rowId }) {
    tables[tableId].delete(rowId);
  },
  async listRows({ tableId, queries }) {
    let rows = [...tables[tableId].values()];
    for (const q of queries) if (q.equal) rows = rows.filter((r) => r[q.equal[0]] === q.equal[1]);
    return { total: rows.length, rows };
  },
};

mock.module('node-appwrite', {
  namedExports: {
    Client: class { setEndpoint() { return this; } setProject() { return this; } setKey() { return this; } },
    TablesDB: class { constructor() { return db; } },
    ID: { unique: () => `row${++nextId}` },
    Query: { equal: (k, v) => ({ equal: [k, v] }), limit: (n) => ({ limit: n }), select: (s) => ({ select: s }), cursorAfter: (c) => ({ cursorAfter: c }) },
    Permission: { read: (r) => `read(${r})` },
    Role: { user: (id) => `user:${id}` },
    Operator: { increment: (n) => ({ increment: n }) },
  },
});
mock.module('@apple/app-store-server-library', {
  namedExports: {
    // The test's "JWS" is the transaction as JSON.
    SignedDataVerifier: class { async verifyAndDecodeTransaction(jws) { return JSON.parse(jws); } },
    Environment: { SANDBOX: 'Sandbox', PRODUCTION: 'Production' },
  },
});

const { default: handler } = await import('../src/main.js');

const tx = (id, productId = 'tickets_5') => JSON.stringify({ transactionId: id, productId, bundleId: 'com.matejbaco.cardjigsawworld', purchaseDate: Date.now(), environment: 'Sandbox' });

async function verify(jws, userId = 'u1') {
  let out;
  await handler({
    req: { method: 'POST', path: '/verify', headers: { 'x-appwrite-user-id': userId }, body: JSON.stringify({ jws, productId: JSON.parse(jws).productId }) },
    res: { json: (body, status = 200) => (out = { status, body }) },
    log: () => {},
    error: () => {},
  });
  return out;
}

beforeEach(() => {
  tables = { profiles: new Map([['u1', { $id: 'u1', coins: 100, tickets: 5, hints: 0 }]]), purchases: new Map(), ledger: new Map() };
});

test('grants a purchase once and answers with the new balances', async () => {
  const first = await verify(tx('t1'));
  assert.equal(first.status, 200);
  assert.deepEqual(first.body, { ok: true, grant: { tickets: 10 }, balances: { coins: 100, tickets: 15, hints: 0, peeks: 0, magics: 0 } });
  const [ledger] = tables.ledger.values();
  assert.equal(ledger.balanceAfter, 15);
  assert.equal([...tables.purchases.values()][0].grant, '{"tickets":10}');

  const again = await verify(tx('t1'));
  assert.deepEqual(again.body, { ok: true, alreadyApplied: true, grant: { tickets: 10 } });
  assert.equal(tables.profiles.get('u1').tickets, 15);
});

test('two calls for one transaction at once grant it once', async () => {
  const answers = await Promise.all([verify(tx('t2', 'coins_1000')), verify(tx('t2', 'coins_1000'))]);
  assert.equal(tables.profiles.get('u1').coins, 2600);
  assert.equal(tables.ledger.size, 1);
  assert.deepEqual(answers.map((a) => a.body.alreadyApplied === true).sort(), [false, true]);
  assert.ok(answers.every((a) => a.body.ok === true));
});

test('a grant adds to the balance as it is when it lands', async () => {
  const call = verify(tx('t3'));
  // The player spends a ticket on another device while the grant is on its way.
  await new Promise((r) => setTimeout(r, 2));
  tables.profiles.get('u1').tickets -= 1;
  await call;
  assert.equal(tables.profiles.get('u1').tickets, 14);
});

test('a grant that fails frees the transaction for the next try', async () => {
  tables.profiles.delete('u1');
  await assert.rejects(() => db.getRow({ tableId: 'profiles', rowId: 'u1' }));
  const failed = await verify(tx('t4'));
  assert.equal(failed.status, 500);
  assert.equal(tables.purchases.size, 0);

  tables.profiles.set('u1', { $id: 'u1', coins: 0, tickets: 0, hints: 0 });
  const retried = await verify(tx('t4'));
  assert.equal(retried.body.ok, true);
  assert.equal(tables.profiles.get('u1').tickets, 10);
});

test('VIP sets the expiry from the transaction', async () => {
  const expires = Date.parse('2026-11-15T10:00:00Z');
  const jws = JSON.stringify({ transactionId: 't5', originalTransactionId: 'o5', productId: 'vip_monthly', bundleId: 'com.matejbaco.cardjigsawworld', expiresDate: expires });
  const res = await verify(jws);
  assert.equal(res.body.grant.vipExpiresAt, '2026-11-15T10:00:00.000Z');
  assert.equal(tables.profiles.get('u1').appleOriginalTransactionId, 'o5');
});

test('a helper bundle adds Peeks, Hints and Magic, with a ledger line for the hints only', async () => {
  tables.profiles.set('u1', { $id: 'u1', coins: 0, tickets: 0, hints: 2, peeks: 1, magics: 0 });
  const res = await verify(tx('t6', 'hints_5'));
  assert.deepEqual(res.body, { ok: true, grant: { hints: 10, peeks: 15, magics: 5 }, balances: { coins: 0, tickets: 0, hints: 12, peeks: 16, magics: 5 } });
  assert.deepEqual([...tables.ledger.values()].map((l) => [l.currency, l.amount]), [['hints', 10]]);
  const big = await verify(tx('t7', 'hints_15'));
  assert.deepEqual(big.body.grant, { hints: 30, peeks: 50, magics: 15 });
  assert.equal(tables.profiles.get('u1').magics, 20);
});
