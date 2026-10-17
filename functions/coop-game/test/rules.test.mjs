// The co-op rules that need no database: codes, boards and seats.
//
//   cd functions/coop-game && node --test
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { CODE_LENGTH, MAX_PLAYERS, newCode, normaliseCode, validGrid, parseLayout, seating, freeSeat, without } from '../src/rules.js';

const member = (userId, seat, at, id = userId) => ({ $id: `m-${id}`, userId, roles: seat < 0 ? ['player'] : ['player', `seat${seat}`], $createdAt: `2026-10-17T10:00:0${at}.000+00:00` });

test('codes are 8 unambiguous characters and read back in any case', () => {
  for (let i = 0; i < 200; i++) {
    const c = newCode(randomBytes);
    assert.equal(c.length, CODE_LENGTH);
    assert.equal(normaliseCode(c.toLowerCase()), c);
    assert.match(c, /^[A-HJ-NP-Z2-9]+$/);
  }
  assert.equal(normaliseCode('k7qh-2mxp'), 'K7QH2MXP');
  assert.equal(normaliseCode('K7QH2MX'), null, 'too short');
  assert.equal(normaliseCode('K7QH2MX0'), null, 'zero is not in the alphabet');
  assert.equal(normaliseCode(null), null);
});

test('boards: grid codes in path form, layouts as permutations', () => {
  for (const g of ['cards-4x5t3', 'hexagons-5x6', '4x4', 'triangles-10x8t7', 'cards-12x14t8']) assert.ok(validGrid(g), g);
  for (const g of ['', 'cards:4x5', '../x', 'cards-4x5t3; drop', 42]) assert.ok(!validGrid(g), String(g));
  assert.deepEqual(parseLayout([2, 0, 3, 1]), [2, 0, 3, 1]);
  assert.deepEqual(parseLayout(['1', '0', '3', '2']), [1, 0, 3, 2]);
  assert.equal(parseLayout([0, 0, 1, 2]), null, 'a card twice');
  assert.equal(parseLayout([0, 1, 2]), null, 'too small');
  assert.equal(parseLayout([0, 1, 2, 4]), null, 'out of range');
  assert.equal(parseLayout('0,1,2,3'), null);
});

test('seats: the host keeps seat 0, joiners fill the smallest free seat', () => {
  const ms = [member('host', 0, 0), member('b', 1, 1), member('c', 2, 2)];
  assert.equal(freeSeat(ms), 3);
  const { players, moves, over } = seating(ms);
  assert.deepEqual(players, ['host', 'b', 'c', '', '']);
  assert.equal(moves.length, 0);
  assert.equal(over.length, 0);
  assert.deepEqual(without(players, 'b'), ['host', '', 'c', '', '']);
});

test('two joins at the same moment that took the same seat: the later one moves', () => {
  const ms = [member('host', 0, 0), member('late', 1, 3), member('early', 1, 2)];
  const { players, moves } = seating(ms);
  assert.deepEqual(players, ['host', 'early', 'late', '', '']);
  assert.deepEqual(moves.map((m) => [m.membership.userId, m.seat]), [['late', 2]]);
  // Every call that sees the same memberships decides the same.
  assert.deepEqual(seating([...ms].reverse()).players, players);
});

test('a sixth player who got in at the same moment is over the limit', () => {
  const ms = [member('host', 0, 0), member('a', 1, 1), member('b', 2, 2), member('c', 3, 3), member('d', 4, 4), member('e', 4, 5)];
  const { players, over } = seating(ms);
  assert.equal(players.filter((p) => p).length, MAX_PLAYERS);
  assert.deepEqual(over.map((m) => m.userId), ['e']);
  assert.equal(freeSeat(ms.slice(0, 5)), -1);
});

test('a seat left empty is taken by the next joiner, the others keep theirs', () => {
  const ms = [member('host', 0, 0), member('c', 2, 2), member('new', -1, 4)];
  const { players, moves } = seating(ms);
  assert.deepEqual(players, ['host', 'new', 'c', '', '']);
  assert.deepEqual(moves.map((m) => m.seat), [1]);
});
