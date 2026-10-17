#!/usr/bin/env node
// Live check of the security fixes of 2026-10-17 (docs/functions.md, "Integrity sweep"), with
// QA-flagged players on the live backend:
//
// 1. A squatter (Axel) creates rows at the ids the victim's app uses (Vera's block of him, her
//    progress on a picture), names himself with a link and makes a photo of his public. The `blocks`
//    create event removes the squatted block within seconds (`SWEEP_APPLY`), so Vera can block him;
//    her progress write is refused (401) until the sweep runs.
// 2. The sweep runs as the owner (Appwrite CLI): a QA-only dry run, which changes nothing, then a
//    QA-only run for real. Vera can write her rows again, Axel's name is "Player", his photo is his
//    only.
// 3. Gifts: no notification to a one-way friend; at most 5 notifications a day to one player (the
//    6th gift lands quietly); a sender's 21st gift of the day is refused, through `api` and through
//    the old `send-gift` too.
//
//   node tools/dev/security_check.mjs [--keep]
//
// Everything it made is purged afterwards (tools/dev/purge_test_players.py). Needs the Appwrite CLI
// signed in as the owner (the sweep is not for players) and secrets/appwrite-users-key.txt. Key
// values and session secrets are never printed.
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { randomBytes, createHash } from 'node:crypto';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT = '6acb4de5003e38d5ebd9';
const KEY = readFileSync(join(ROOT, 'secrets', 'appwrite-users-key.txt'), 'utf8').trim();
const KEEP = process.argv.includes('--keep');
const RUN = `security-check-${Date.now()}`;
const md5 = (s) => createHash('md5').update(s).digest('hex');
const own = (u) => [`read("user:${u}")`, `update("user:${u}")`, `delete("user:${u}")`];

async function call(method, path, { body, session, key = true, form } = {}) {
  const headers = { 'X-Appwrite-Project': PROJECT };
  if (!form) headers['Content-Type'] = 'application/json';
  if (key) headers['X-Appwrite-Key'] = KEY;
  if (session) headers['X-Appwrite-Session'] = session;
  const r = await fetch(ENDPOINT + path, { method, headers, body: form ?? (body ? JSON.stringify(body) : undefined) });
  const text = await r.text();
  const data = text ? JSON.parse(text) : {};
  if (!r.ok) throw Object.assign(new Error(`${method} ${path}: ${r.status} ${data.message}`), { code: r.status });
  return data;
}
const asPlayer = (p, method, path, body) => call(method, path, { key: false, session: p.secret, body });
const status = (promise) => promise.then(() => 200, (e) => e.code ?? 0);

let failures = 0;
function expect(label, ok, detail = '') {
  if (!ok) failures++;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${detail ? `  (${detail})` : ''}`);
}

const players = [];
async function makePlayer(name) {
  const userId = 'qasec' + randomBytes(8).toString('hex');
  await call('POST', '/users', { body: { userId, name } });
  await call('PATCH', `/users/${userId}/prefs`, { body: { prefs: { qa: true, qaRun: RUN } } });
  await call('POST', '/tablesdb/cjw/tables/profiles/rows', {
    body: { rowId: userId, data: { userId, displayName: name, avatar: 'owl', isTest: true }, permissions: ['read("any")', `update("user:${userId}")`, `delete("user:${userId}")`] },
  });
  const s = await call('POST', `/users/${userId}/sessions`, { body: {} });
  const p = { userId, secret: s.secret, name };
  players.push(p);
  return p;
}
const befriend = (a, b) => call('POST', '/tablesdb/cjw/tables/friends/rows', {
  body: { rowId: md5(`${a.userId}:${b.userId}`), data: { userId: a.userId, friendId: b.userId, friendName: b.name, friendAvatar: 'owl', status: 'accepted' }, permissions: own(a.userId) },
});

/// The sweep, as the owner through the Appwrite CLI.
const configDir = mkdtempSync(join(tmpdir(), 'cjw-sweep-'));
writeFileSync(join(configDir, 'appwrite.config.json'), JSON.stringify({ projectId: PROJECT, endpoint: ENDPOINT }));
function sweep(body) {
  const out = execFileSync('appwrite', ['functions', 'create-execution', '--function-id', 'api', '--path', '/admin/sweep', '--method', 'POST', '--body', JSON.stringify(body), '--json', '--config-file', join(configDir, 'appwrite.config.json')], { encoding: 'utf8' });
  const exec = JSON.parse(out);
  return JSON.parse(exec.responseBody || '{}');
}

async function gift(from, to, fn = 'api') {
  const exec = await asPlayer(from, 'POST', `/functions/${fn}/executions`, { path: fn === 'api' ? '/gift/send' : '/send', method: 'POST', body: JSON.stringify({ friendId: to.userId, kind: 'tickets', utcOffset: 0 }), async: false });
  return JSON.parse(exec.responseBody || '{}');
}

try {
  console.log(`run ${RUN}`);
  const vera = await makePlayer('Vera QA');
  const axel = await makePlayer('Axel QA');

  // 1. Squats.
  const blockId = md5(`${vera.userId}:${axel.userId}`);
  await asPlayer(axel, 'POST', '/tablesdb/cjw/tables/blocks/rows', { rowId: blockId, data: { blockerId: vera.userId, blockedId: axel.userId, blockedName: 'Axel QA', blockedAvatar: 'fox' }, permissions: own(axel.userId) });
  const progressId = md5(`${vera.userId}:qa-picture`);
  await asPlayer(axel, 'POST', '/tablesdb/cjw/tables/progress/rows', { rowId: progressId, data: { userId: axel.userId, puzzleId: 'qa-picture' }, permissions: own(axel.userId) });
  await asPlayer(axel, 'PATCH', `/tablesdb/cjw/tables/profiles/rows/${axel.userId}`, { data: { displayName: 'visit spam.com' } });
  const form = new FormData();
  form.append('fileId', 'unique()');
  form.append('file', new Blob([Buffer.from('not a photo')], { type: 'image/jpeg' }), 'photo.jpg');
  for (const p of ['read("any")', `read("user:${axel.userId}")`, `delete("user:${axel.userId}")`]) form.append('permissions[]', p);
  const file = await call('POST', '/storage/buckets/user-uploads/files', { key: false, session: axel.secret, form });
  await asPlayer(axel, 'POST', '/tablesdb/cjw/tables/my_puzzles/rows', { rowId: 'unique()', data: { userId: axel.userId, fileId: file.$id, title: 'QA photo' }, permissions: own(axel.userId) });

  const blockVera = () => asPlayer(vera, 'PUT', `/tablesdb/cjw/tables/blocks/rows/${blockId}`, { data: { blockerId: vera.userId, blockedId: axel.userId, blockedName: 'Axel QA', blockedAvatar: 'fox' }, permissions: own(vera.userId) });
  const saveVera = () => asPlayer(vera, 'PUT', `/tablesdb/cjw/tables/progress/rows/${progressId}`, { data: { userId: vera.userId, puzzleId: 'qa-picture' }, permissions: own(vera.userId) });
  // The blocks create event checks a new row at once and deletes one made in someone else's name.
  let blockGone = false;
  for (let i = 0; i < 20 && !blockGone; i++) {
    await new Promise((r) => setTimeout(r, 500));
    blockGone = (await status(call('GET', `/tablesdb/cjw/tables/blocks/rows/${blockId}`))) === 404;
  }
  expect('the blocks event removes the squatted block within 10 s', blockGone);
  expect('then Vera blocks Axel', (await status(blockVera())) === 200);
  expect('squatted: Vera cannot save her picture (401)', (await status(saveVera())) === 401);

  // 2. The sweep: a dry run, then for real (QA players only).
  const dry = sweep({ full: true, qaOnly: true });
  console.log('     dry run:', JSON.stringify(dry.counts));
  expect('dry run finds the squat, the name and the public photo (the block is already fixed)', !dry.counts['blocks:permissions'] && dry.counts['progress:id'] === 1 && dry.counts['profiles:name'] === 1 && dry.counts['files:repair'] === 1);
  expect('dry run changes nothing', (await call('GET', `/tablesdb/cjw/tables/progress/rows/${progressId}`)).userId === axel.userId);
  const real = sweep({ full: true, qaOnly: true, dryRun: false });
  console.log('     run:', JSON.stringify(real.counts));
  expect('Vera blocks Axel again', (await status(blockVera())) === 200);
  expect('Vera saves her picture again', (await status(saveVera())) === 200);
  expect("Axel's name shows as Player", (await call('GET', `/tablesdb/cjw/tables/profiles/rows/${axel.userId}`)).displayName === 'Player');
  const perms = (await call('GET', `/storage/buckets/user-uploads/files/${file.$id}`)).$permissions;
  expect("Axel's photo is his only", !perms.includes('read("any")') && perms.includes(`read("user:${axel.userId}")`), perms.join(' '));
  const after = sweep({ full: true, qaOnly: true });
  expect('a second run finds nothing', Object.keys(after.counts).length === 0, JSON.stringify(after.counts));

  // 3. Gifts.
  const oneWay = await makePlayer('Olga QA');
  await befriend(oneWay, vera);
  const g = await gift(oneWay, vera);
  expect('a one-way friend\'s gift arrives without a notification', g.ok === true && g.pushed === false, JSON.stringify(g));
  const senders = [];
  for (let i = 0; i < 6; i++) senders.push(await makePlayer(`Sender ${i + 1} QA`));
  for (const s of senders) {
    await befriend(s, vera);
    await befriend(vera, s);
  }
  const pushed = [];
  for (const s of senders) pushed.push((await gift(s, vera)).pushed);
  // Olga's gift counts as one of Vera's day: 1 + 6 gifts, notifications for the first 5.
  expect('notifications: at most 5 a day to one player', JSON.stringify(pushed) === JSON.stringify([true, true, true, true, false, false]), JSON.stringify(pushed));
  const recipients = [];
  for (let i = 0; i < 21; i++) recipients.push(await makePlayer(`Recipient ${i + 1} QA`));
  for (const r of recipients) await befriend(axel, r);
  const answers = [];
  for (const r of recipients.slice(0, 20)) answers.push((await gift(axel, r)).ok);
  expect('a sender sends 20 gifts a day', answers.every(Boolean), `${answers.filter(Boolean).length} sent`);
  const over = await gift(axel, recipients[20]);
  expect('the 21st is refused through api', over.ok === false && over.error === 'limit', JSON.stringify(over));
  const overOld = await gift(axel, recipients[20], 'send-gift');
  expect('and through the old send-gift', overOld.ok === false && overOld.error === 'limit', JSON.stringify(overOld));
} catch (e) {
  failures++;
  console.log('FAIL', e.stack || e.message);
} finally {
  if (!KEEP) {
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
