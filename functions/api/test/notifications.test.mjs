// POST /purchase/notifications (through the router) against an in-memory database: App Store Server
// Notifications V2 do what verify-purchase's /notifications did (renewals, expiries, refunds, Family
// Sharing), in both environments, and each notification is applied once: a second delivery, two at
// once, a delivery after a failure half way and a claim left behind by a call that died.
// functions/verify-purchase holds the same code (test/twins.test.mjs).
//
//   cd functions/api && npm install && npm test
import { test, mock, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

// The function runs with APPLE_ENVIRONMENT=Production (as live); sandbox notifications verify through
// the Sandbox fallback.
process.env.APPLE_ENVIRONMENT = 'Production';
process.env.APPWRITE_FUNCTION_ID = 'api';

class Conflict extends Error {
  constructor() { super('Row with the requested ID already exists.'); this.code = 409; }
}
class Missing extends Error {
  constructor() { super('Row not found'); this.code = 404; }
}

let tables;
let failProfileUpdates = 0;
const db = {
  async getRow({ tableId, rowId }) {
    const row = tables[tableId].get(rowId);
    if (!row) throw new Missing();
    return { ...row };
  },
  async updateRow({ tableId, rowId, data }) {
    await new Promise((r) => setTimeout(r, 2));
    if (tableId === 'profiles' && failProfileUpdates > 0) {
      failProfileUpdates--;
      throw Object.assign(new Error('Server error'), { code: 500 });
    }
    const row = tables[tableId].get(rowId);
    if (!row) throw new Missing();
    Object.assign(row, data);
    return { ...row };
  },
  async createRow({ tableId, rowId, data }) {
    await new Promise((r) => setTimeout(r, 2));
    const t = tables[tableId];
    if (t.has(rowId)) throw new Conflict();
    const row = { ...data, $id: rowId, $createdAt: new Date().toISOString() };
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
    ID: { unique: () => `row${Math.random()}` },
    Query: { equal: (k, v) => ({ equal: [k, v] }), limit: (n) => ({ limit: n }), select: (s) => ({ select: s }), cursorAfter: (c) => ({ cursorAfter: c }) },
    Permission: { read: (r) => `read(${r})` },
    Role: { user: (id) => `user:${id}` },
    Operator: { increment: (n) => ({ increment: n }) },
  },
});

// The test's "JWS" is the payload as JSON. A verifier refuses what Apple signed for the other
// environment, as the real one does; `forged` fails every verifier.
const verifiers = [];
mock.module('@apple/app-store-server-library', {
  namedExports: {
    SignedDataVerifier: class {
      constructor(_roots, _online, environment) { this.environment = environment; verifiers.push(environment); }
      check(jws) {
        const d = JSON.parse(jws);
        if (d.forged) throw new Error('VerificationException: invalid chain');
        const env = d.data?.environment ?? d.environment;
        if (env && env !== this.environment) throw new Error('VerificationException: invalid environment');
        return d;
      }
      async verifyAndDecodeNotification(jws) { return this.check(jws); }
      async verifyAndDecodeTransaction(jws) { return this.check(jws); }
      async verifyAndDecodeRenewalInfo(jws) { return this.check(jws); }
    },
    Environment: { SANDBOX: 'Sandbox', PRODUCTION: 'Production' },
  },
});

const { default: handler } = await import('../src/main.js');

const BUNDLE = 'com.matejbaco.cardjigsawworld';
const DAY = 86400000;
let uuid = 0;

/// A notification as Apple signs it: [tx] becomes data.signedTransactionInfo.
function notification(type, tx, { subtype, environment = 'Production', renewal, id } = {}) {
  const data = { bundleId: BUNDLE, environment };
  if (tx) data.signedTransactionInfo = JSON.stringify({ bundleId: BUNDLE, environment, ...tx });
  if (renewal) data.signedRenewalInfo = JSON.stringify({ environment, ...renewal });
  return JSON.stringify({ notificationType: type, subtype, notificationUUID: id ?? `00000000-0000-4000-8000-${String(++uuid).padStart(12, '0')}`, signedDate: Date.now(), data });
}

async function deliver(signedPayload) {
  let out;
  const logs = [];
  await handler({
    req: { method: 'POST', path: '/purchase/notifications', headers: { 'x-appwrite-trigger': 'http' }, body: JSON.stringify({ signedPayload }) },
    res: { json: (body, status = 200) => (out = { status, body }) },
    log: (m) => logs.push(m),
    error: (m) => logs.push(m),
  });
  return { ...out, logs };
}

const idOf = (signedPayload) => JSON.parse(signedPayload).notificationUUID;
const vip = (id) => tables.profiles.get(id).vipExpiresAt;
const soon = (iso) => Math.abs(Date.parse(iso) - Date.now()) < 5000;

const sub = { transactionId: 't-renew', originalTransactionId: 'o1', productId: 'vip_monthly', inAppOwnershipType: 'PURCHASED' };

beforeEach(() => {
  failProfileUpdates = 0;
  tables = {
    profiles: new Map([
      ['buyer', { $id: 'buyer', appleOriginalTransactionId: 'o1', vipExpiresAt: '2026-10-20T00:00:00.000Z' }],
      ['family', { $id: 'family', appleOriginalTransactionId: 'o1', vipExpiresAt: '2026-10-20T00:00:00.000Z' }],
      ['other', { $id: 'other', appleOriginalTransactionId: 'o9', vipExpiresAt: '2026-10-20T00:00:00.000Z' }],
    ]),
    purchases: new Map([
      ['p1', { $id: 'p1', userId: 'buyer', transactionId: 't1', originalTransactionId: 'o1', ownership: 'PURCHASED' }],
      ['p2', { $id: 'p2', userId: 'family', transactionId: 'f1', originalTransactionId: 'o1', ownership: 'FAMILY_SHARED', appTransactionId: 'app-f' }],
    ]),
    apple_notifications: new Map(),
  };
});

test('a renewal moves VIP on every account of the subscription, and records it', async () => {
  const expires = Date.parse('2026-11-20T00:00:00Z');
  const n = notification('DID_RENEW', { ...sub, expiresDate: expires });
  const r = await deliver(n);
  assert.deepEqual([r.status, r.body], [200, { ok: true, profiles: 2 }]);
  assert.equal(vip('buyer'), '2026-11-20T00:00:00.000Z');
  assert.equal(vip('family'), '2026-11-20T00:00:00.000Z');
  assert.equal(vip('other'), '2026-10-20T00:00:00.000Z');
  const rec = tables.apple_notifications.get(idOf(n));
  assert.deepEqual([rec.type, rec.environment, rec.result, rec.profiles, rec.via], ['DID_RENEW', 'Production', 'applied', 2, 'api']);
  // No transaction id or player: nothing in it outlives an account deletion.
  assert.ok(!JSON.stringify(rec).includes('t-renew') && !JSON.stringify(rec).includes('o1') && !JSON.stringify(rec).includes('buyer'));
});

test('the same notification twice is applied once', async () => {
  const n = notification('EXPIRED', { ...sub, expiresDate: Date.now() - DAY }, { subtype: 'VOLUNTARY' });
  const first = await deliver(n);
  assert.deepEqual(first.body, { ok: true, profiles: 2 });
  assert.ok(soon(vip('buyer')));
  // The player subscribes again before Apple sends the expiry a second time.
  tables.profiles.get('buyer').vipExpiresAt = '2026-12-01T00:00:00.000Z';
  const again = await deliver(n);
  assert.deepEqual([again.status, again.body], [200, { ok: true, alreadyApplied: true }]);
  assert.equal(vip('buyer'), '2026-12-01T00:00:00.000Z');
  assert.equal(tables.apple_notifications.size, 1);
});

test('two deliveries at once apply it once', async () => {
  const n = notification('REFUND', { ...sub, transactionId: 't1', revocationDate: Date.now() });
  let profileWrites = 0;
  const update = db.updateRow;
  db.updateRow = async (args) => { if (args.tableId === 'profiles') profileWrites++; return update(args); };
  try {
    const answers = await Promise.all([deliver(n), deliver(n)]);
    assert.deepEqual(answers.map((a) => a.body.alreadyApplied === true).sort(), [false, true]);
    assert.ok(answers.every((a) => a.status === 200));
  } finally {
    db.updateRow = update;
  }
  assert.equal(profileWrites, 2, 'buyer and family, once each');
  assert.equal(tables.purchases.get('p1').revoked, true);
});

test('a notification that fails half way frees its claim, and Apple\'s next try applies it', async () => {
  const n = notification('DID_RENEW', { ...sub, expiresDate: Date.parse('2026-11-20T00:00:00Z') });
  failProfileUpdates = 1;
  const failed = await deliver(n);
  assert.equal(failed.status, 500);
  assert.equal(tables.apple_notifications.has(idOf(n)), false);
  const retried = await deliver(n);
  assert.deepEqual(retried.body, { ok: true, profiles: 2 });
  assert.equal(vip('buyer'), '2026-11-20T00:00:00.000Z');
  assert.equal(tables.apple_notifications.get(idOf(n)).result, 'applied');
});

test('a claim left pending by a call that died is taken over; a fresh one is not', async () => {
  const n = notification('DID_RENEW', { ...sub, expiresDate: Date.parse('2026-11-20T00:00:00Z') });
  const id = idOf(n);
  tables.apple_notifications.set(id, { $id: id, result: 'pending', claimedAt: new Date(Date.now() - 60 * 1000).toISOString() });
  assert.deepEqual((await deliver(n)).body, { ok: true, alreadyApplied: true });
  assert.equal(vip('buyer'), '2026-10-20T00:00:00.000Z');
  tables.apple_notifications.get(id).claimedAt = new Date(Date.now() - 11 * 60 * 1000).toISOString();
  assert.deepEqual((await deliver(n)).body, { ok: true, profiles: 2 });
  assert.equal(vip('buyer'), '2026-11-20T00:00:00.000Z');
  assert.equal(tables.apple_notifications.get(id).result, 'applied');
});

test('a sandbox notification verifies on the Production function (TestFlight, App Review)', async () => {
  verifiers.length = 0;
  const n = notification('DID_RENEW', { ...sub, expiresDate: Date.parse('2026-11-20T00:00:00Z') }, { environment: 'Sandbox' });
  const r = await deliver(n);
  assert.deepEqual(r.body, { ok: true, profiles: 2 });
  assert.deepEqual(verifiers, ['Production', 'Sandbox', 'Sandbox'], 'Production first, then the Sandbox fallback; the transaction in Sandbox');
  assert.equal(tables.apple_notifications.get(idOf(n)).environment, 'Sandbox');
});

test('a payload Apple did not sign is refused and records nothing', async () => {
  const r = await deliver(JSON.stringify({ forged: true, notificationType: 'DID_RENEW', notificationUUID: 'x' }));
  assert.deepEqual([r.status, r.body], [401, { ok: false }]);
  assert.equal(tables.apple_notifications.size, 0);
  const empty = await deliver('');
  assert.deepEqual([empty.status, empty.body], [400, { ok: false, error: 'Missing signedPayload' }]);
});

test('a refund ends VIP now and marks the purchase revoked', async () => {
  const r = await deliver(notification('REFUND', { ...sub, transactionId: 't1', revocationDate: Date.now() }));
  assert.deepEqual(r.body, { ok: true, profiles: 2 });
  assert.ok(soon(vip('buyer')) && soon(vip('family')));
  assert.equal(tables.purchases.get('p1').revoked, true);
  assert.equal(tables.purchases.get('p2').revoked, undefined);
});

test('a family member\'s REVOKE reaches only that member (by transaction, else by app transaction)', async () => {
  const r = await deliver(notification('REVOKE', { transactionId: 'f1', originalTransactionId: 'o1', productId: 'vip_monthly', inAppOwnershipType: 'FAMILY_SHARED' }));
  assert.deepEqual(r.body, { ok: true, profiles: 1 });
  assert.ok(soon(vip('family')));
  assert.equal(vip('buyer'), '2026-10-20T00:00:00.000Z');
  assert.equal(tables.purchases.get('p2').revoked, true);
  tables.profiles.get('family').vipExpiresAt = '2026-10-20T00:00:00.000Z';
  const byApp = await deliver(notification('DID_RECOVER', { transactionId: 'f2', originalTransactionId: 'o1', appTransactionId: 'app-f', productId: 'vip_monthly', inAppOwnershipType: 'FAMILY_SHARED', expiresDate: Date.parse('2026-11-21T00:00:00Z') }));
  assert.deepEqual(byApp.body, { ok: true, profiles: 1 });
  assert.equal(vip('family'), '2026-11-21T00:00:00.000Z');
  assert.equal(vip('buyer'), '2026-10-20T00:00:00.000Z');
});

test('a failed renewal keeps VIP through the grace period', async () => {
  const grace = Date.parse('2026-10-26T00:00:00Z');
  const r = await deliver(notification('DID_FAIL_TO_RENEW', { ...sub, expiresDate: Date.parse('2026-10-20T00:00:00Z') }, { subtype: 'GRACE_PERIOD', renewal: { gracePeriodExpiresDate: grace } }));
  assert.deepEqual(r.body, { ok: true, profiles: 2 });
  assert.equal(vip('buyer'), '2026-10-26T00:00:00.000Z');
});

test('TEST, a notification without a transaction and an unknown subscription answer 200 and are recorded', async () => {
  const t = notification('TEST');
  assert.deepEqual((await deliver(t)).body, { ok: true });
  assert.equal(tables.apple_notifications.get(idOf(t)).result, 'test');
  assert.deepEqual((await deliver(t)).body, { ok: true, alreadyApplied: true });
  const summary = notification('RENEWAL_EXTENSION', null, { subtype: 'SUMMARY' });
  assert.deepEqual((await deliver(summary)).body, { ok: true, ignored: true });
  const charge = notification('ONE_TIME_CHARGE', { transactionId: 'c1', originalTransactionId: 'c1', productId: 'tickets_5', inAppOwnershipType: 'PURCHASED' });
  assert.deepEqual((await deliver(charge)).body, { ok: true, unmatched: true });
  assert.equal(tables.apple_notifications.get(idOf(charge)).result, 'unmatched');
});

test('a notification without a usable UUID is still applied', async () => {
  const n = notification('DID_RENEW', { ...sub, expiresDate: Date.parse('2026-11-20T00:00:00Z') }, { id: '' });
  assert.deepEqual((await deliver(n)).body, { ok: true, profiles: 2 });
  assert.equal(tables.apple_notifications.size, 0);
});
