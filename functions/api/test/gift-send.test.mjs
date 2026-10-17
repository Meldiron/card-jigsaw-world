// POST /gift/send against an in-memory database: the daily limit per sender, notifications only
// between mutual friends and at most PUSHES_PER_DAY a day per recipient, names through the filter.
//
//   cd functions/api && npm install && npm test
import { test, mock, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

class Conflict extends Error {
  constructor() { super('exists'); this.code = 409; }
}
class Missing extends Error {
  constructor() { super('missing'); this.code = 404; }
}

let tables;
let pushes;
let nextId = 0;
const matches = (row, queries) => queries.every((q) => {
  if (q.equal) return [].concat(q.equal[1]).includes(row[q.equal[0]]);
  if (q.greaterThan) return String(row[q.greaterThan[0]]) > String(q.greaterThan[1]);
  if (q.lessThan) return String(row[q.lessThan[0]]) < String(q.lessThan[1]);
  return true;
});
const db = {
  async getRow({ tableId, rowId }) {
    const row = tables[tableId].get(rowId);
    if (!row) throw new Missing();
    return { ...row };
  },
  async createRow({ tableId, rowId, data }) {
    if (tables[tableId].has(rowId)) throw new Conflict();
    tables[tableId].set(rowId, { ...data, $id: rowId });
    return { ...data, $id: rowId };
  },
  async deleteRow({ tableId, rowId }) {
    tables[tableId].delete(rowId);
  },
  async listRows({ tableId, queries }) {
    const rows = [...tables[tableId].values()].filter((r) => matches(r, queries));
    const limit = queries.find((q) => q.limit)?.limit;
    return { total: rows.length, rows: limit ? rows.slice(0, limit) : rows };
  },
};
const messaging = {
  async createPush(p) { pushes.push(p); },
  async listMessages() { return { messages: [] }; },
};

mock.module('node-appwrite', {
  namedExports: {
    Client: class { setEndpoint() { return this; } setProject() { return this; } setKey() { return this; } },
    TablesDB: class { constructor() { return db; } },
    Messaging: class { constructor() { return messaging; } },
    ID: { unique: () => `id${++nextId}` },
    Query: {
      equal: (k, v) => ({ equal: [k, v] }),
      greaterThan: (k, v) => ({ greaterThan: [k, v] }),
      lessThan: (k, v) => ({ lessThan: [k, v] }),
      limit: (n) => ({ limit: n }),
      select: (s) => ({ select: s }),
      orderAsc: (k) => ({ orderAsc: k }),
    },
    Permission: { read: (r) => `read(${r})` },
    Role: { user: (id) => `user:${id}` },
  },
});

const { sendGift } = await import('../src/gift/send.js');
const { DAILY_SENDS, PUSHES_PER_DAY, shouldPush } = await import('../src/gift/gift.js');

async function send(from, to, kind = 'tickets') {
  let out;
  await sendGift({
    req: { method: 'POST', path: '/gift/send', headers: { 'x-appwrite-user-id': from }, body: JSON.stringify({ friendId: to, kind, utcOffset: 0 }) },
    res: { json: (body, status = 200) => (out = { status, body }) },
    log: () => {},
    error: (e) => console.log(e),
  });
  return out;
}

const befriend = (a, b) => tables.friends.set(`${a}:${b}`, { $id: `${a}:${b}`, userId: a, friendId: b });

beforeEach(() => {
  pushes = [];
  tables = { friends: new Map(), blocks: new Map(), profiles: new Map(), gifts: new Map(), messages: new Map() };
  for (let i = 0; i < 30; i++) tables.profiles.set(`p${i}`, { $id: `p${i}`, displayName: `Player ${i}` });
  tables.profiles.set('anna', { $id: 'anna', displayName: 'Anna' });
  tables.profiles.set('spam', { $id: 'spam', displayName: 'visit spam.com' });
});

test('the rule: mutual friends only, at most PUSHES_PER_DAY a day', () => {
  assert.equal(shouldPush({ mutual: true, received: 1 }), true);
  assert.equal(shouldPush({ mutual: true, received: PUSHES_PER_DAY }), true);
  assert.equal(shouldPush({ mutual: true, received: PUSHES_PER_DAY + 1 }), false);
  assert.equal(shouldPush({ mutual: false, received: 1 }), false);
});

test('a one-way friend gets the gift without a notification; a mutual friend gets both', async () => {
  befriend('anna', 'p1');
  const oneWay = await send('anna', 'p1');
  assert.equal(oneWay.body.ok, true);
  assert.equal(oneWay.body.pushed, false);
  assert.equal([...tables.messages.values()].filter((m) => m.userId === 'p1').length, 1);

  befriend('anna', 'p2');
  befriend('p2', 'anna');
  const mutual = await send('anna', 'p2');
  assert.equal(mutual.body.pushed, true);
  assert.equal(pushes.length, 1);
  assert.equal(pushes[0].title, 'Anna sent you a gift');
});

test(`a sender sends at most ${DAILY_SENDS} gifts a day`, async () => {
  for (let i = 0; i < 25; i++) befriend('anna', `p${i}`);
  for (let i = 0; i < DAILY_SENDS; i++) assert.equal((await send('anna', `p${i}`)).body.ok, true, `gift ${i}`);
  const over = await send('anna', `p${DAILY_SENDS}`);
  assert.deepEqual([over.status, over.body.ok, over.body.error], [429, false, 'limit']);
  assert.equal(tables.gifts.size, DAILY_SENDS);
});

test(`a recipient gets at most ${PUSHES_PER_DAY} notifications a day; later gifts arrive quietly`, async () => {
  for (let i = 0; i < 8; i++) {
    befriend(`p${i}`, 'anna');
    befriend('anna', `p${i}`);
  }
  const answers = [];
  for (let i = 0; i < 8; i++) answers.push((await send(`p${i}`, 'anna')).body);
  assert.ok(answers.every((a) => a.ok));
  assert.deepEqual(answers.map((a) => a.pushed), [true, true, true, true, true, false, false, false]);
  assert.equal([...tables.messages.values()].filter((m) => m.userId === 'anna').length, 8);
});

test('a name with a link shows as Player in the message and the notification', async () => {
  befriend('spam', 'anna');
  befriend('anna', 'spam');
  await send('spam', 'anna');
  const [m] = [...tables.messages.values()];
  assert.equal(m.fromName, 'Player');
  assert.equal(m.subject, 'Player sent you a gift');
  assert.equal(pushes[0].title, 'Player sent you a gift');
});
