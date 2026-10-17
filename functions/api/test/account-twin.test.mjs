// Account deletion has two copies while builds up to 124 are in use (docs/functions.md): src/account.js
// (the source) and functions/delete-account (frozen, called by those builds). Both must delete the
// same: a change here goes into delete-account too, and that function is redeployed.
//
//   cd functions/api && node --test test/account-twin.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const read = (path) => readFileSync(fileURLToPath(new URL(path, import.meta.url)), 'utf8');

/// The deletion code of a source: from the imports to the entry point, without comments and blank lines.
function deletionCode(source, endMarker) {
  const body = source.slice(source.indexOf('import '), source.indexOf(endMarker));
  return body
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('//'))
    .join('\n');
}

test('api and delete-account delete the same things the same way', () => {
  const api = deletionCode(read('../src/account.js'), '/// Whether the Sign in with Apple key');
  const old = deletionCode(read('../../delete-account/src/main.js'), 'export default');
  assert.ok(api.includes('PLAYER_TABLES') && api.includes('async function handleDelete'));
  assert.equal(api, old);
});
