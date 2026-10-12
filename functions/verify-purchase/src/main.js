// Verify App Store purchases and apply grants server-side.
//
// Routes:
//   POST /verify         { jws, productId }        called by the app after StoreKit reports a purchase
//   POST /notifications  { signedPayload }         App Store Server Notifications V2
//   GET  /health
//
// Every transaction is verified with Apple's App Store Server Library
// (certificate chain back to Apple Root CA G3), checked against the bundle id,
// and applied exactly once (purchases.transactionId is unique).
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Client, TablesDB, ID, Query, Permission, Role } from 'node-appwrite';
import { SignedDataVerifier, Environment } from '@apple/app-store-server-library';

const __dirname = dirname(fileURLToPath(import.meta.url));

const BUNDLE_ID = process.env.APPLE_BUNDLE_ID || 'com.matejbaco.cardjigsawworld';
const APP_APPLE_ID = process.env.APPLE_APP_ID ? Number(process.env.APPLE_APP_ID) : undefined;
const ENVIRONMENT = (process.env.APPLE_ENVIRONMENT || 'Sandbox') === 'Production' ? Environment.PRODUCTION : Environment.SANDBOX;
const DB = process.env.APPWRITE_DATABASE_ID || 'cjw';

// What each product grants. Apple product ids cannot be renamed, so the number
// in a consumable id is historical. Keep in sync with StoreProducts.grants in
// lib/data/purchases.dart and store/metadata/subscriptions/consumables.json
// (test/economy_test.dart checks all three); the amounts are explained in
// docs/economy.md.
const GRANTS = {
  coins_1000: { coins: 2500 },
  coins_3000: { coins: 8000 },
  coins_5500: { coins: 14000 },
  coins_12000: { coins: 30000 },
  tickets_5: { tickets: 10 },
  tickets_15: { tickets: 30 },
  hints_5: { hints: 16 },
  hints_15: { hints: 48 },
  vip_monthly: { vip: true },
  vip_yearly: { vip: true },
};

const rootCerts = [readFileSync(join(__dirname, '..', 'certs', 'AppleRootCA-G3.cer'))];

function verifier(environment = ENVIRONMENT) {
  return new SignedDataVerifier(rootCerts, true, environment, BUNDLE_ID, APP_APPLE_ID);
}

/// Verifies a transaction in the configured environment, falling back to
/// Sandbox when a Production app receives a sandbox transaction (App Review
/// tests with sandbox accounts).
async function decodeTransaction(jws) {
  try {
    return await verifier().verifyAndDecodeTransaction(jws);
  } catch (e) {
    if (ENVIRONMENT === Environment.PRODUCTION) {
      return await verifier(Environment.SANDBOX).verifyAndDecodeTransaction(jws);
    }
    throw e;
  }
}

async function decodeNotification(signedPayload) {
  try {
    return await verifier().verifyAndDecodeNotification(signedPayload);
  } catch (e) {
    if (ENVIRONMENT === Environment.PRODUCTION) {
      return await verifier(Environment.SANDBOX).verifyAndDecodeNotification(signedPayload);
    }
    throw e;
  }
}

function tables(req) {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(req.headers['x-appwrite-key'] ?? '');
  return new TablesDB(client);
}

const iso = (ms) => (ms ? new Date(ms).toISOString() : null);

async function applyGrant(db, userId, tx, grant, log) {
  const profile = await db.getRow({ databaseId: DB, tableId: 'profiles', rowId: userId });
  const patch = {};
  const applied = {};
  if (grant.coins) { patch.coins = (profile.coins ?? 0) + grant.coins; applied.coins = grant.coins; }
  if (grant.tickets) { patch.tickets = (profile.tickets ?? 0) + grant.tickets; applied.tickets = grant.tickets; }
  if (grant.hints) { patch.hints = (profile.hints ?? 0) + grant.hints; applied.hints = grant.hints; }
  if (grant.vip) {
    const expires = iso(tx.expiresDate);
    patch.vipExpiresAt = expires;
    patch.appleOriginalTransactionId = tx.originalTransactionId ?? tx.transactionId;
    applied.vipExpiresAt = expires;
  }
  await db.updateRow({ databaseId: DB, tableId: 'profiles', rowId: userId, data: patch });
  for (const [currency, amount] of [['coins', applied.coins], ['tickets', applied.tickets], ['hints', applied.hints]]) {
    if (!amount) continue;
    await db.createRow({
      databaseId: DB,
      tableId: 'ledger',
      rowId: ID.unique(),
      data: { userId, amount, currency, reason: `iap:${tx.productId}`, balanceAfter: patch[currency] },
      permissions: [Permission.read(Role.user(userId))],
    });
  }
  log(`granted ${JSON.stringify(applied)} to ${userId} for ${tx.productId} (${tx.transactionId})`);
  return applied;
}

async function handleVerify(req, res, log, error) {
  const userId = req.headers['x-appwrite-user-id'];
  if (!userId) return res.json({ ok: false, error: 'Sign in required' }, 401);
  let body;
  try { body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.bodyJson ?? req.body ?? {}); } catch { body = {}; }
  const { jws, productId } = body;
  if (!jws) return res.json({ ok: false, error: 'Missing transaction' }, 400);

  let tx;
  try {
    tx = await decodeTransaction(jws);
  } catch (e) {
    error(`verification failed: ${e}`);
    return res.json({ ok: false, error: 'Transaction could not be verified' }, 400);
  }
  if (tx.bundleId !== BUNDLE_ID) return res.json({ ok: false, error: 'Wrong app' }, 400);
  if (productId && tx.productId !== productId) return res.json({ ok: false, error: 'Product mismatch' }, 400);
  if (tx.revocationDate) return res.json({ ok: false, error: 'Transaction was refunded' }, 400);
  const grant = GRANTS[tx.productId];
  if (!grant) return res.json({ ok: false, error: `Unknown product ${tx.productId}` }, 400);

  const db = tables(req);
  const existing = await db.listRows({ databaseId: DB, tableId: 'purchases', queries: [Query.equal('transactionId', tx.transactionId), Query.limit(1)] });
  if (existing.total > 0) {
    const row = existing.rows[0];
    return res.json({ ok: true, alreadyApplied: true, grant: JSON.parse(row.grant || '{}') });
  }

  const applied = await applyGrant(db, userId, tx, grant, log);
  await db.createRow({
    databaseId: DB,
    tableId: 'purchases',
    rowId: ID.unique(),
    data: {
      userId,
      transactionId: tx.transactionId,
      originalTransactionId: tx.originalTransactionId ?? tx.transactionId,
      productId: tx.productId,
      type: grant.vip ? 'subscription' : 'consumable',
      environment: tx.environment ?? 'Sandbox',
      purchasedAt: iso(tx.purchaseDate),
      expiresAt: iso(tx.expiresDate),
      grant: JSON.stringify(applied),
    },
  });
  return res.json({ ok: true, grant: applied });
}

const RENEW_TYPES = new Set(['DID_RENEW', 'SUBSCRIBED', 'DID_CHANGE_RENEWAL_STATUS', 'OFFER_REDEEMED', 'RENEWAL_EXTENDED', 'RENEWAL_EXTENSION', 'REFUND_REVERSED']);
const END_TYPES = new Set(['EXPIRED', 'REFUND', 'REVOKE', 'GRACE_PERIOD_EXPIRED']);

async function handleNotification(req, res, log, error) {
  let body;
  try { body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.bodyJson ?? req.body ?? {}); } catch { body = {}; }
  if (!body.signedPayload) return res.json({ ok: false, error: 'Missing signedPayload' }, 400);
  let payload;
  try {
    payload = await decodeNotification(body.signedPayload);
  } catch (e) {
    error(`notification verification failed: ${e}`);
    return res.json({ ok: false }, 401);
  }
  const type = payload.notificationType;
  log(`notification ${type} ${payload.subtype ?? ''}`);
  if (type === 'TEST') return res.json({ ok: true });
  const data = payload.data ?? {};
  if (!data.signedTransactionInfo) return res.json({ ok: true, ignored: true });

  const v = verifier(payload.data?.environment === 'Sandbox' ? Environment.SANDBOX : ENVIRONMENT);
  const tx = await v.verifyAndDecodeTransaction(data.signedTransactionInfo);
  let renewal = null;
  if (data.signedRenewalInfo) {
    try { renewal = await v.verifyAndDecodeRenewalInfo(data.signedRenewalInfo); } catch (e) { error(`renewal info: ${e}`); }
  }
  const originalId = tx.originalTransactionId ?? tx.transactionId;
  const db = tables(req);
  const profiles = await db.listRows({ databaseId: DB, tableId: 'profiles', queries: [Query.equal('appleOriginalTransactionId', originalId), Query.limit(1)] });
  if (profiles.total === 0) {
    log(`no profile for original transaction ${originalId}`);
    return res.json({ ok: true, unmatched: true });
  }
  const profile = profiles.rows[0];
  const patch = {};
  if (RENEW_TYPES.has(type)) {
    patch.vipExpiresAt = iso(tx.expiresDate);
  } else if (END_TYPES.has(type)) {
    patch.vipExpiresAt = new Date().toISOString();
    if (type === 'REFUND' || type === 'REVOKE') {
      const rows = await db.listRows({ databaseId: DB, tableId: 'purchases', queries: [Query.equal('transactionId', tx.transactionId), Query.limit(1)] });
      for (const row of rows.rows) {
        await db.updateRow({ databaseId: DB, tableId: 'purchases', rowId: row.$id, data: { revoked: true } });
      }
    }
  } else if (type === 'DID_CHANGE_RENEWAL_PREF' || type === 'DID_FAIL_TO_RENEW' || type === 'PRICE_INCREASE') {
    // Access continues until expiresDate; keep it in sync.
    if (tx.expiresDate) patch.vipExpiresAt = iso(tx.expiresDate);
  }
  if (renewal?.gracePeriodExpiresDate && type === 'DID_FAIL_TO_RENEW') {
    patch.vipExpiresAt = iso(renewal.gracePeriodExpiresDate);
  }
  if (Object.keys(patch).length > 0) {
    await db.updateRow({ databaseId: DB, tableId: 'profiles', rowId: profile.$id, data: patch });
    log(`profile ${profile.$id}: ${JSON.stringify(patch)}`);
  }
  return res.json({ ok: true });
}

export default async ({ req, res, log, error }) => {
  const path = (req.path || '/').replace(/\/+$/, '') || '/';
  try {
    if (req.method === 'GET' && (path === '/health' || path === '/')) return res.json({ ok: true });
    if (req.method === 'POST' && path === '/verify') return await handleVerify(req, res, log, error);
    if (req.method === 'POST' && path === '/notifications') return await handleNotification(req, res, log, error);
    return res.json({ ok: false, error: 'Not found' }, 404);
  } catch (e) {
    error(`unhandled: ${e?.stack ?? e}`);
    return res.json({ ok: false, error: 'Server error' }, 500);
  }
};
