// Twins while builds up to 124 are in use (docs/functions.md): those builds call the old functions,
// which hold copies of api's modules. Where old builds must get the same behaviour, both copies must
// match: a change here goes into the old function too, and that function is redeployed.
// - Account deletion: src/account.js and functions/delete-account (what is deleted).
// - Friend gifts: src/gift/ and functions/send-gift (the daily limit, notifications, the name filter;
//   otherwise a client could call send-gift directly and skip them).
// - Purchases and Apple's notifications: src/purchase.js and functions/verify-purchase (grants, the
//   checks, the record that applies a notification once).
//
//   cd functions/api && node --test test/twins.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const read = (path) => readFileSync(fileURLToPath(new URL(path, import.meta.url)), 'utf8');

/// The code of a source between its imports and [endMarker], without comments and blank lines.
function code(source, endMarker) {
  const body = source.slice(source.indexOf('import '), source.indexOf(endMarker));
  return body
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('//'))
    .join('\n');
}

test('api and delete-account delete the same things the same way', () => {
  const api = code(read('../src/account.js'), '/// Whether the Sign in with Apple key');
  const old = code(read('../../delete-account/src/main.js'), 'export default');
  assert.ok(api.includes('PLAYER_TABLES') && api.includes('async function handleDelete'));
  assert.equal(api, old);
});

// verify-purchase serves /verify for builds up to 124 and /notifications for notifications Apple sends
// again to its old address; both functions record notifications in the same table, so one delivered to
// each is applied once.
test('api and verify-purchase verify, grant and apply notifications the same way', () => {
  const api = code(read('../src/purchase.js'), '/// The Apple environment in use');
  const old = code(read('../../verify-purchase/src/main.js'), 'export default');
  for (const part of ['const GRANTS', 'async function handleVerify', 'async function handleNotification', 'async function claimNotification', "const NOTIFICATIONS = 'apple_notifications'", 'async function profilesFor']) {
    assert.ok(api.includes(part), part);
  }
  assert.equal(api, old);
});

test('api and send-gift send gifts the same way', () => {
  const api = code(read('../src/gift/send.js'), 'export async function sendGift');
  const old = code(read('../../send-gift/src/main.js'), 'export default');
  assert.ok(api.includes('DAILY_SENDS') && api.includes('shouldPush'));
  assert.equal(api, old);
  assert.equal(read('../../send-gift/src/gift.js'), read('../src/gift/gift.js'));
});
