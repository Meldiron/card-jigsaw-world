// Verify App Store purchases and apply grants server-side (moved from the verify-purchase function,
// which stays deployed for builds up to 124 and for Apple's notifications; docs/functions.md).
//
// Routes (function `api`, see main.js):
//   POST /purchase/verify         { jws, productId }   called by the app after StoreKit reports a purchase
//   POST /purchase/notifications  { signedPayload }    App Store Server Notifications V2 (Apple still
//                                                      sends them to verify-purchase's domain)
//   GET  /health                                       includes `environment`: the APPLE_ENVIRONMENT in use
//
// GRANTS below and in functions/verify-purchase/src/main.js must stay the same (test/economy_test.dart).
//
// Every transaction is verified with Apple's App Store Server Library
// (certificate chain back to Apple Root CA G3), checked against the bundle id,
// and applied exactly once: the purchases row (unique transactionId) is claimed
// before the grant, so two calls for one transaction cannot both grant it.
// Currencies are added with atomic operators, like the app's own changes, so a
// grant never overwrites a coin or ticket the player spends at the same moment.
//
// Family Sharing (VIP, since 2026-10-14): a family member's device sends its own
// transaction (inAppOwnershipType FAMILY_SHARED, its own transactionId) and gets
// VIP like the purchaser. One subscription (originalTransactionId) unlocks VIP on
// at most MAX_ACCOUNTS_PER_SUBSCRIPTION game accounts, the size of an Apple family,
// so a purchase cannot be spread over unrelated accounts. Notifications for the
// purchaser update every account linked to the subscription; family-only
// notifications (REVOKE when sharing stops, DID_RECOVER, DID_FAIL_TO_RENEW) update
// only that member's accounts. Win-back offers (offerType 4) and every other offer
// are plain transactions of the same products and verify the same way.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Client, TablesDB, ID, Query, Permission, Role, Operator } from 'node-appwrite';
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
// docs/economy.md. The two helper bundles (ids hints_*) give Peeks, Hints and
// Magic since 2026-10-17 (16 and 48 hints before).
const GRANTS = {
  coins_1000: { coins: 2500 },
  coins_3000: { coins: 8000 },
  coins_5500: { coins: 14000 },
  coins_12000: { coins: 30000 },
  tickets_5: { tickets: 10 },
  tickets_15: { tickets: 30 },
  hints_5: { peeks: 15, hints: 10, magics: 5 },
  hints_15: { peeks: 50, hints: 30, magics: 15 },
  vip_monthly: { vip: true },
  vip_yearly: { vip: true },
};

// An Apple family is the organiser plus up to five members.
const MAX_ACCOUNTS_PER_SUBSCRIPTION = 6;
const PAGE = 100;

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

/// Every row matching `queries`, a page at a time (never a single fixed-size read).
async function listAll(db, tableId, queries) {
  const out = [];
  let cursor = null;
  for (;;) {
    const page = await db.listRows({
      databaseId: DB,
      tableId,
      queries: [...queries, Query.limit(PAGE), ...(cursor ? [Query.cursorAfter(cursor)] : [])],
    });
    out.push(...page.rows);
    if (page.rows.length < PAGE) return out;
    cursor = page.rows[page.rows.length - 1].$id;
  }
}

/// Game accounts that already hold VIP from this subscription (purchaser and family).
async function accountsOfSubscription(db, originalTransactionId) {
  const rows = await listAll(db, 'purchases', [Query.equal('originalTransactionId', originalTransactionId), Query.select(['userId'])]);
  return new Set(rows.map((r) => r.userId));
}

const ownershipOf = (tx) => tx.inAppOwnershipType ?? 'PURCHASED';

// The currencies the ledger records (its `currency` column is an enum of these).
const CURRENCIES = ['coins', 'tickets', 'hints'];
// Peeks and Magic in stock: boosters on the profile (columns `peeks`, `magics`), no ledger line,
// as in the app (lib/data/sync/ops.dart, ledgerCurrencies).
const BOOSTERS = ['peeks', 'magics'];
const AMOUNTS = [...CURRENCIES, ...BOOSTERS];

/// What a verified transaction gives the player: amounts of coins, tickets, hints, Peeks and
/// Magic, or the VIP expiry. Stored on the purchases row and returned to the app.
function grantFor(tx, grant) {
  const out = {};
  for (const c of AMOUNTS) if (grant[c]) out[c] = grant[c];
  if (grant.vip) out.vipExpiresAt = iso(tx.expiresDate);
  return out;
}

/// The player's coins, tickets, hints, Peeks and Magic as the profile row has them.
const balancesOf = (row) => Object.fromEntries(AMOUNTS.map((c) => [c, row[c] ?? 0]));

/// Adds [applied] to the profile (atomic increments) and returns the row as it is now.
async function applyGrant(db, userId, tx, applied) {
  const patch = {};
  for (const c of AMOUNTS) if (applied[c]) patch[c] = Operator.increment(applied[c]);
  if ('vipExpiresAt' in applied) {
    patch.vipExpiresAt = applied.vipExpiresAt;
    patch.appleOriginalTransactionId = tx.originalTransactionId ?? tx.transactionId;
  }
  return db.updateRow({ databaseId: DB, tableId: 'profiles', rowId: userId, data: patch });
}

/// One ledger row per currency granted (Peeks and Magic have none). Bookkeeping only: the grant
/// stands if a row fails.
async function writeLedger(db, userId, tx, applied, profile, error) {
  for (const c of CURRENCIES) {
    if (!applied[c]) continue;
    try {
      await db.createRow({
        databaseId: DB,
        tableId: 'ledger',
        rowId: ID.unique(),
        data: { userId, amount: applied[c], currency: c, reason: `iap:${tx.productId}`, balanceAfter: profile[c] ?? 0 },
        permissions: [Permission.read(Role.user(userId))],
      });
    } catch (e) {
      error(`ledger row for ${tx.transactionId} (${c}) failed: ${e}`);
    }
  }
}

async function findPurchase(db, transactionId) {
  const page = await db.listRows({ databaseId: DB, tableId: 'purchases', queries: [Query.equal('transactionId', transactionId), Query.limit(1)] });
  return page.rows[0] ?? null;
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
  const existing = await findPurchase(db, tx.transactionId);
  if (existing) return res.json({ ok: true, alreadyApplied: true, grant: JSON.parse(existing.grant || '{}') });

  const originalId = tx.originalTransactionId ?? tx.transactionId;
  const ownership = ownershipOf(tx);
  if (grant.vip) {
    const accounts = await accountsOfSubscription(db, originalId);
    if (!accounts.has(userId) && accounts.size >= MAX_ACCOUNTS_PER_SUBSCRIPTION) {
      log(`refused ${tx.productId} (${tx.transactionId}, ${ownership}) for ${userId}: subscription ${originalId} already on ${accounts.size} accounts`);
      return res.json({ ok: false, error: 'This subscription is already in use on the most accounts it can unlock.' }, 403);
    }
  }

  // Claim the transaction first (unique transactionId): of two calls at once, only one grants.
  const applied = grantFor(tx, grant);
  let claim;
  try {
    claim = await db.createRow({
      databaseId: DB,
      tableId: 'purchases',
      rowId: ID.unique(),
      data: {
        userId,
        transactionId: tx.transactionId,
        originalTransactionId: originalId,
        ownership,
        appTransactionId: tx.appTransactionId ? String(tx.appTransactionId) : null,
        productId: tx.productId,
        type: grant.vip ? 'subscription' : 'consumable',
        environment: tx.environment ?? 'Sandbox',
        purchasedAt: iso(tx.purchaseDate),
        expiresAt: iso(tx.expiresDate),
        grant: JSON.stringify(applied),
      },
    });
  } catch (e) {
    if (e?.code !== 409) throw e;
    log(`${tx.transactionId} was claimed by another call a moment ago`);
    const row = await findPurchase(db, tx.transactionId);
    return res.json({ ok: true, alreadyApplied: true, grant: row ? JSON.parse(row.grant || '{}') : applied });
  }

  let profile;
  try {
    profile = await applyGrant(db, userId, tx, applied);
  } catch (e) {
    // Nothing was granted: free the transaction so the app's next try applies it.
    try {
      await db.deleteRow({ databaseId: DB, tableId: 'purchases', rowId: claim.$id });
    } catch (d) {
      error(`could not free ${tx.transactionId} after a failed grant: ${d}`);
    }
    throw e;
  }
  log(`granted ${JSON.stringify(applied)} to ${userId} for ${tx.productId} (${tx.transactionId})`);
  if (ownership !== 'PURCHASED' || tx.offerType) log(`  ownership ${ownership}, offerType ${tx.offerType ?? '-'} ${tx.offerIdentifier ?? ''}`);
  await writeLedger(db, userId, tx, applied, profile, error);
  return res.json({ ok: true, grant: applied, balances: balancesOf(profile) });
}

const RENEW_TYPES = new Set(['DID_RENEW', 'DID_RECOVER', 'SUBSCRIBED', 'DID_CHANGE_RENEWAL_STATUS', 'OFFER_REDEEMED', 'RENEWAL_EXTENDED', 'RENEWAL_EXTENSION', 'REFUND_REVERSED']);
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
  const ownership = ownershipOf(tx);
  const db = tables(req);
  const profileIds = await profilesFor(db, tx, originalId, ownership);
  if (profileIds.length === 0) {
    log(`no profile for ${ownership} transaction ${tx.transactionId} (original ${originalId})`);
    return res.json({ ok: true, unmatched: true });
  }
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
    for (const id of profileIds) {
      await db.updateRow({ databaseId: DB, tableId: 'profiles', rowId: id, data: patch });
      log(`profile ${id}: ${JSON.stringify(patch)} (${ownership})`);
    }
  }
  return res.json({ ok: true, profiles: profileIds.length });
}

/// The profiles a notification applies to. A family member's notification
/// (FAMILY_SHARED) reaches only the accounts that verified that member's
/// transactions (by transactionId, else by the member's appTransactionId); the
/// purchaser's reaches every account linked to the subscription.
async function profilesFor(db, tx, originalId, ownership) {
  if (ownership === 'FAMILY_SHARED') {
    let rows = await listAll(db, 'purchases', [Query.equal('transactionId', tx.transactionId), Query.select(['userId'])]);
    if (rows.length === 0 && tx.appTransactionId) {
      rows = await listAll(db, 'purchases', [Query.equal('appTransactionId', String(tx.appTransactionId)), Query.select(['userId'])]);
    }
    return [...new Set(rows.map((r) => r.userId))];
  }
  const rows = await listAll(db, 'profiles', [Query.equal('appleOriginalTransactionId', originalId), Query.select(['userId'])]);
  return rows.map((r) => r.$id);
}

/// The Apple environment in use, for GET /health.
export const environmentName = () => (ENVIRONMENT === Environment.PRODUCTION ? 'Production' : 'Sandbox');

/// Runs [handler], answering an unexpected failure as verify-purchase did.
async function guarded(handler, { req, res, log, error }) {
  try {
    return await handler(req, res, log, error);
  } catch (e) {
    error(`unhandled: ${e?.stack ?? e}`);
    return res.json({ ok: false, error: 'Server error' }, 500);
  }
}

export const verify = (context) => guarded(handleVerify, context);
export const notifications = (context) => guarded(handleNotification, context);
