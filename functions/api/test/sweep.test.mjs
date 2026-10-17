// The integrity sweep (src/sweep): the rules on plain rows, then a run against an in-memory project
// (a squatted row, a ghost profile, profile permissions, photos, names; dry run, apply, QA only).
//
//   cd functions/api && npm install && npm test
import { test, mock, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';

const md5 = (s) => createHash('md5').update(s).digest('hex');
const own = (u) => [`read("user:${u}")`, `update("user:${u}")`, `delete("user:${u}")`];
const NOW = Date.parse('2026-10-17T16:00:00Z');
const OLD = '2026-10-17T10:00:00.000+00:00';
const NEW = '2026-10-17T15:50:00.000+00:00';

// --- An in-memory project -------------------------------------------------------------------------
let db;
let files;
let users;
const matches = (row, queries) => queries.every((q) => {
  if (q.equal) return [].concat(q.equal[1]).includes(row[q.equal[0]]);
  if (q.greaterThanEqual) return String(row[q.greaterThanEqual[0]]) >= String(q.greaterThanEqual[1]);
  return true;
});
const page = (list, queries) => {
  let out = list.filter((r) => matches(r, queries)).sort((a, b) => (a.$id < b.$id ? -1 : 1));
  const after = queries.find((q) => q.cursorAfter)?.cursorAfter;
  if (after) out = out.filter((r) => r.$id > after);
  const limit = queries.find((q) => q.limit)?.limit;
  return { total: out.length, list: limit ? out.slice(0, limit) : out };
};
const tablesFake = {
  async listRows({ tableId, queries }) {
    const p = page([...db[tableId].values()], queries);
    return { total: p.total, rows: p.list.map((r) => ({ ...r })) };
  },
  async deleteRows({ tableId, queries }) {
    for (const r of page([...db[tableId].values()], queries).list) db[tableId].delete(r.$id);
  },
  async deleteRow({ tableId, rowId }) {
    db[tableId].delete(rowId);
  },
  async updateRows({ tableId, data, queries }) {
    for (const r of page([...db[tableId].values()], queries).list) Object.assign(db[tableId].get(r.$id), data);
  },
  async updateRow({ tableId, rowId, data, permissions }) {
    const r = db[tableId].get(rowId);
    if (data) Object.assign(r, data);
    if (permissions) r.$permissions = permissions;
    return r;
  },
};
const storageFake = {
  async listFiles({ queries }) {
    const p = page([...files.values()], queries);
    return { total: p.total, files: p.list.map((f) => ({ ...f })) };
  },
  async deleteFile({ fileId }) {
    files.delete(fileId);
  },
  async updateFile({ fileId, permissions }) {
    files.get(fileId).$permissions = permissions;
  },
};
const usersFake = {
  async list({ queries }) {
    const p = page([...users.values()], queries);
    return { total: p.total, users: p.list };
  },
  async get({ userId }) {
    if (!users.has(userId)) throw Object.assign(new Error('missing'), { code: 404 });
    return users.get(userId);
  },
};

mock.module('node-appwrite', {
  namedExports: {
    Client: class { setEndpoint() { return this; } setProject() { return this; } setKey() { return this; } },
    TablesDB: class {}, Storage: class {}, Users: class {},
    Query: {
      equal: (k, v) => ({ equal: [k, v] }),
      greaterThanEqual: (k, v) => ({ greaterThanEqual: [k, v] }),
      limit: (n) => ({ limit: n }),
      cursorAfter: (c) => ({ cursorAfter: c }),
      orderAsc: (k) => ({ orderAsc: k }),
      select: (s) => ({ select: s }),
    },
  },
});

const rules = await import('../src/sweep/rules.js');
const { sweep, sweepNewRow } = await import('../src/sweep/run.js');
const services = { tables: tablesFake, storage: storageFake, users: usersFake };

const row = (table, id, data, permissions, at = NEW) => db[table].set(id, { $id: id, $createdAt: at, $updatedAt: at, $permissions: permissions, ...data });

beforeEach(() => {
  db = { progress: new Map(), event_progress: new Map(), friends: new Map(), blocks: new Map(), profiles: new Map(), my_puzzles: new Map() };
  files = new Map();
  users = new Map();
  for (const [id, qa] of [['anna', false], ['ben', false], ['qa1', true], ['qa2', true]]) {
    users.set(id, { $id: id, prefs: qa ? { qa: true } : {} });
    row('profiles', id, { displayName: id, isTest: qa }, ['read("any")', `update("user:${id}")`, `delete("user:${id}")`], OLD);
  }
});

// --- Rules -----------------------------------------------------------------------------------------
test('rows: the owner\'s own row passes, a squat at a predictable id does not', () => {
  const spec = rules.OWNED.blocks;
  const mine = { $id: md5('anna:ben'), blockerId: 'anna', blockedId: 'ben', $permissions: own('anna') };
  assert.equal(rules.rowVerdict(spec, mine), null);
  // Ben made Anna's row first, as himself: the id is not his.
  assert.equal(rules.rowVerdict(spec, { ...mine, blockerId: 'ben', $permissions: own('ben') }), 'id');
  // ... or naming Anna as the owner: his permissions give him away.
  assert.equal(rules.rowVerdict(spec, { ...mine, $permissions: own('ben') }), 'permissions');
  assert.equal(rules.rowVerdict(spec, { ...mine, $permissions: [...own('anna'), 'read("user:ben")'] }), 'permissions');
  // A row the app made with a unique id (its predictable one was taken) is checked by permissions.
  assert.equal(rules.rowVerdict(spec, { ...mine, $id: '6ad3a1b2c3d4e5f60718' }), null);
  // event_progress rows are readable by every player.
  assert.equal(rules.rowVerdict(rules.OWNED.event_progress, { $id: md5('anna:e1'), userId: 'anna', eventId: 'e1', $permissions: ['read("users")', 'update("user:anna")', 'delete("user:anna")'] }), null);
});

test('profiles: ghosts after an hour, squats, repairs; QA rows only deleted', () => {
  const p = (id, perms, extra = {}) => ({ $id: id, $createdAt: OLD, $permissions: perms, ...extra });
  assert.equal(rules.profileVerdict(p('anna', rules.profilePermissions('anna')), true, NOW), null);
  assert.deepEqual(rules.profileVerdict(p('ghost', ['read("any")', 'update("user:ben")']), false, NOW), { action: 'delete', why: 'no-user' });
  assert.equal(rules.profileVerdict({ ...p('ghost', []), $createdAt: NEW }, false, NOW), null, 'a profile minutes old may wait for its user');
  assert.deepEqual(rules.profileVerdict(p('anna', [...rules.profilePermissions('anna'), 'update("user:ben")']), true, NOW), { action: 'delete', why: 'permissions' });
  assert.equal(rules.profileVerdict(p('anna', ['read("users")', 'update("user:anna")']), true, NOW).action, 'repair');
  assert.equal(rules.profileVerdict(p('qa1', ['read("any")'], { isTest: true }), true, NOW), null);
});

test('photos: orphans after an hour, others\' access taken away', () => {
  const f = (perms, at = OLD) => ({ $id: 'f1', $createdAt: at, $permissions: perms });
  const mine = rules.uploadPermissions('anna');
  assert.equal(rules.fileVerdict(f(mine), new Set(['anna']), NOW), null);
  assert.deepEqual(rules.fileVerdict(f(mine), new Set(), NOW), { action: 'delete', why: 'no-row' });
  assert.equal(rules.fileVerdict(f(mine, NEW), new Set(), NOW), null, 'an upload whose row is on its way');
  assert.equal(rules.fileVerdict(f([...mine, 'read("any")']), new Set(['anna']), NOW).action, 'repair');
  assert.deepEqual(rules.fileVerdict(f(['read("any")']), new Set(['anna']), NOW).permissions, mine);
  // A row of Ben pointing at Anna's photo does not make it Ben's.
  assert.deepEqual(rules.fileVerdict(f(mine), new Set(['ben']), NOW), { action: 'delete', why: 'no-row' });
});

test('names: refused names become Player', () => {
  for (const n of ['visit spam.com', '@anna', 'fuck', 'https://x']) assert.ok(rules.nameVerdict(n), n);
  for (const n of ['Player', 'Brave Otter', 'Mr. Bean', '', null]) assert.ok(!rules.nameVerdict(n), String(n));
});

// --- Runs ------------------------------------------------------------------------------------------
function squats() {
  // Ben squats Anna's block of him (the id Anna's app uses) and her progress on puzzle p1.
  row('blocks', md5('anna:ben'), { blockerId: 'anna', blockedId: 'ben', blockedName: 'Ben' }, own('ben'));
  row('progress', md5('anna:p1'), { userId: 'ben', puzzleId: 'p1' }, own('ben'));
  // Anna's own rows.
  row('progress', md5('anna:p2'), { userId: 'anna', puzzleId: 'p2' }, own('anna'));
  row('friends', md5('anna:ben'), { userId: 'anna', friendId: 'ben', friendName: 'go to spam.com' }, own('anna'));
  // A profile without a user, and Anna's name.
  row('profiles', 'ghost', { displayName: 'Free coins', isTest: false }, ['read("any")', 'update("user:ben")'], OLD);
  db.profiles.get('ghost').$updatedAt = NEW;
  Object.assign(db.profiles.get('anna'), { displayName: '@anna_on_insta', $updatedAt: NEW });
  // Photos: Anna's, an orphan, a public one of Anna.
  row('my_puzzles', 'r1', { userId: 'anna', fileId: 'f1' }, own('anna'));
  row('my_puzzles', 'r2', { userId: 'anna', fileId: 'f3' }, own('anna'));
  files.set('f1', { $id: 'f1', $createdAt: OLD, $permissions: rules.uploadPermissions('anna') });
  files.set('f2', { $id: 'f2', $createdAt: OLD, $permissions: rules.uploadPermissions('ben') });
  files.set('f3', { $id: 'f3', $createdAt: OLD, $permissions: [...rules.uploadPermissions('anna'), 'read("any")'] });
}

test('a dry run reports and changes nothing', async () => {
  squats();
  const before = JSON.stringify([[...db.blocks], [...db.progress], [...db.profiles], [...files]]);
  const r = await sweep(services, { apply: false, now: NOW });
  assert.equal(JSON.stringify([[...db.blocks], [...db.progress], [...db.profiles], [...files]]), before);
  assert.deepEqual(r.counts, { 'progress:id': 1, 'friends:name': 1, 'blocks:permissions': 1, 'profiles:no-user': 1, 'profiles:name': 1, 'files:no-row': 1, 'files:repair': 1 });
});

test('a run puts it right, and the owner can write again', async () => {
  squats();
  await sweep(services, { apply: true, now: NOW });
  assert.equal(db.blocks.size, 0, 'the squatted block row is gone: Anna can block Ben');
  assert.deepEqual([...db.progress.keys()], [md5('anna:p2')], 'Anna\'s own progress stays');
  assert.equal(db.friends.get(md5('anna:ben')).friendName, 'Player');
  assert.equal(db.profiles.has('ghost'), false);
  assert.equal(db.profiles.get('anna').displayName, 'Player');
  assert.deepEqual([...files.keys()].sort(), ['f1', 'f3']);
  assert.deepEqual(files.get('f3').$permissions, rules.uploadPermissions('anna'));
  // A second run finds nothing.
  assert.deepEqual((await sweep(services, { apply: true, now: NOW })).counts, {});
});

test('an hourly run reads only rows changed in the last two hours; a full run reads all', async () => {
  row('progress', md5('anna:old'), { userId: 'ben', puzzleId: 'old' }, own('ben'), OLD);
  assert.deepEqual((await sweep(services, { apply: false, now: NOW })).counts, {});
  assert.deepEqual((await sweep(services, { apply: false, full: true, now: NOW })).counts, { 'progress:id': 1 });
});

test('QA only: rows of real players are left alone', async () => {
  squats();
  row('blocks', md5('qa1:qa2'), { blockerId: 'qa1', blockedId: 'qa2' }, own('qa2'));
  const r = await sweep(services, { apply: true, qaOnly: true, now: NOW });
  assert.deepEqual(r.counts, { 'blocks:permissions': 1 });
  assert.equal(db.blocks.has(md5('qa1:qa2')), false);
  assert.equal(db.blocks.has(md5('anna:ben')), true, 'Anna\'s squatted row waits for a full run');
  assert.equal(db.profiles.get('anna').displayName, '@anna_on_insta');
});

test('too many photos: the newest past the limit go', async () => {
  for (let i = 0; i < rules.FILES_PER_PLAYER + 3; i++) {
    const at = new Date(NOW - (rules.FILES_PER_PLAYER + 3 - i) * 1000).toISOString();
    row('my_puzzles', `r${String(i).padStart(4, '0')}`, { userId: 'anna', fileId: `f${i}` }, own('anna'), at);
    files.set(`f${i}`, { $id: `f${i}`, $createdAt: at, $permissions: rules.uploadPermissions('anna') });
  }
  const r = await sweep(services, { apply: true, now: NOW });
  assert.equal(r.counts['files:over-limit'], 3);
  assert.equal(files.size, rules.FILES_PER_PLAYER);
  assert.equal(files.has(`f${rules.FILES_PER_PLAYER + 2}`), false, 'the newest went');
  assert.equal(files.has('f0'), true);
});

test('a new blocks row is checked at once', async () => {
  const squat = { $id: md5('anna:ben'), blockerId: 'anna', blockedId: 'ben', $permissions: own('ben') };
  db.blocks.set(squat.$id, squat);
  assert.deepEqual(await sweepNewRow(services, 'blocks', squat, { apply: true }), { checked: true, verdict: 'permissions' });
  assert.equal(db.blocks.size, 0);
  const mine = { ...squat, $permissions: own('anna') };
  assert.deepEqual(await sweepNewRow(services, 'blocks', mine, { apply: true }), { checked: true, verdict: null });
});
