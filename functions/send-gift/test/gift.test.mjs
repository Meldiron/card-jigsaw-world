// node --test functions/send-gift/test/gift.test.mjs (no npm install: gift.js has no dependencies).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { KINDS, clampOffset, giftCopy, giftDay, giftRowId, isOffensive, messageLink, shownName } from '../src/gift.js';

test('the two gifts', () => {
  assert.deepEqual(Object.keys(KINDS).sort(), ['coins', 'tickets']);
  assert.equal(KINDS.tickets.amount, 1);
  assert.equal(KINDS.coins.amount, 150);
  assert.equal(KINDS.tickets.column, 'rewardTickets');
  assert.equal(KINDS.coins.column, 'rewardCoins');
});

test('offsets stay within real time zones, in quarter hours', () => {
  assert.equal(clampOffset(120), 120);
  assert.equal(clampOffset(-300), -300);
  assert.equal(clampOffset(345), 345); // Nepal, UTC+5:45
  assert.equal(clampOffset(9999), 840);
  assert.equal(clampOffset(-9999), -720);
  assert.equal(clampOffset(61), 60);
  assert.equal(clampOffset('abc'), 0);
  assert.equal(clampOffset(undefined), 0);
});

test("the day turns at the sender's midnight", () => {
  const t = new Date('2026-10-17T22:30:00Z');
  assert.equal(giftDay(t, 0), '2026-10-17');
  assert.equal(giftDay(t, 120), '2026-10-18', 'Bratislava in summer time: already the 18th');
  assert.equal(giftDay(t, -300), '2026-10-17', 'New York');
  assert.equal(giftDay(new Date('2026-10-17T03:00:00Z'), -300), '2026-10-16');
});

test('one row id per sender, friend and day, as the app computes it', () => {
  const id = giftRowId('a1', 'b2', '2026-10-17');
  assert.equal(id, createHash('md5').update('a1:b2:2026-10-17').digest('hex'));
  assert.equal(id.length, 32);
  assert.notEqual(id, giftRowId('b2', 'a1', '2026-10-17'), 'each direction has its own gift');
  assert.notEqual(id, giftRowId('a1', 'b2', '2026-10-18'));
});

test('copy', () => {
  assert.deepEqual(giftCopy('tickets', 'Anna'), {
    subject: 'Anna sent you a gift',
    body: 'Anna sent you 1 ticket. Claim it within 24 hours.',
    pushTitle: 'Anna sent you a gift',
    pushBody: '1 ticket is waiting in your inbox.',
  });
  assert.deepEqual(giftCopy('coins', 'Anna'), {
    subject: 'Anna sent you a gift',
    body: 'Anna sent you 150 coins. Claim them within 24 hours.',
    pushTitle: 'Anna sent you a gift',
    pushBody: '150 coins are waiting in your inbox.',
  });
  assert.equal(messageLink('6ad35b2402d213fe77bc'), '/inbox?message=6ad35b2402d213fe77bc');
});

test('names: the same filter as the app', () => {
  assert.equal(shownName('Brave Otter'), 'Brave Otter');
  assert.equal(shownName('  Anna  '), 'Anna');
  assert.equal(shownName(''), 'Player');
  assert.equal(shownName(null), 'Player');
  for (const bad of ['f*ck', 'fuuuck', 'f u c k', '$h1t', 'ass', 'Hitler fan', '1488']) assert.ok(isOffensive(bad), bad);
  for (const ok of ['peacock', 'raccoon', 'class', 'Sussex', 'therapist', 'Picasso', 'Grape Ape', 'canal']) assert.ok(!isOffensive(ok), ok);
});
