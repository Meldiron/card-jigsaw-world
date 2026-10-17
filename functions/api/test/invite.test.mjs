// Invite links (src/invite): the board's geometry against the game's (lib/game/tiling.dart), the
// words of an invite, its page and the card it draws.
//
//   cd functions/api && npm install && npm test
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { loadImage } from '@napi-rs/canvas';
import { parseGrid, sizeLabel, tilingOf, shapeOf } from '../src/invite/tiling.js';
import { renderCard, inviteLines, canWrite, tokens, pickSwaps } from '../src/invite/card.js';
import { cardId, cardUrl, pictureFile, CARD_VERSION } from '../src/invite/store.js';
import { inviteCopy, renderPage, ASSOCIATION, GET_CARDEN } from '../src/invite/page.js';
import { codeOfPath, isInviteRequest } from '../src/invite/paths.js';

const welcome = (name) => readFileSync(new URL(`../../../assets/welcome/${name}.jpg`, import.meta.url));

/// Polygon area (shoelace).
const area = (p) => Math.abs(p.reduce((s, v, i) => s + v[0] * p[(i + 1) % p.length][1] - p[(i + 1) % p.length][0] * v[1], 0)) / 2;

test('board codes read as the app reads them (BoardCode.decode, BoardSpec.size)', () => {
  assert.deepEqual(parseGrid('cards-4x5t3'), { mode: 'cards', cols: 4, rows: 5, tier: 3 });
  assert.deepEqual(parseGrid('hexagons-5x7'), { mode: 'hexagons', cols: 5, rows: 7, tier: null });
  assert.deepEqual(parseGrid('4x4'), { mode: 'cards', cols: 4, rows: 4, tier: null });
  assert.deepEqual(parseGrid('squares:6x4t2'), { mode: 'squares', cols: 6, rows: 4, tier: 2 });
  assert.equal(parseGrid('cards-4x5;drop'), null);
  assert.equal(sizeLabel(parseGrid('triangles-9x4t2')), '4x4', 'a triangle column is an up and a down triangle');
  assert.equal(sizeLabel(parseGrid('triangles-37x18t11')), '18x18');
  assert.equal(sizeLabel(parseGrid('cards-7x7t7')), '7x7');
  assert.equal(sizeLabel(parseGrid('hexagons-23x23t11')), '23x23');
});

test('piece counts are the game\'s (Tiling.cellCount) and the pieces cover the board exactly', () => {
  const expected = {
    'cards-3x3': 9, 'cards-7x7': 49, 'cards-17x17': 289, 'squares-6x4': 24, 'squares-22x22': 484,
    // TriangleTiling.countFor: cols * rows, less the fused right-edge halves of a four-row board with an odd step count.
    'triangles-9x4': 36, 'triangles-11x5': 55, 'triangles-10x4': 38, 'triangles-37x18': 666,
    // HexTiling.countFor: (rows + 1) ~/ 2 * cols + rows ~/ 2 * (cols + 1).
    'hexagons-5x5': 27, 'hexagons-7x7': 52, 'hexagons-23x23': 540, 'hexagons-5x6': 33,
  };
  for (const [grid, cells] of Object.entries(expected)) {
    const t = tilingOf(parseGrid(grid));
    assert.equal(t.cells, cells, grid);
    const [w, h] = [600 * t.boardAspect(1), 600];
    let sum = 0;
    for (let s = 0; s < t.cells; s++) sum += area(t.polygon(s, w, h));
    assert.ok(Math.abs(sum - w * h) < w * h * 1e-6, `${grid}: the pieces cover ${sum} of ${w * h}`);
  }
});

test('board proportions follow the picture within what the cells allow (Tiling.boardAspect)', () => {
  assert.equal(tilingOf(parseGrid('squares-5x5')).boardAspect(0.66), 1 * (1 - 0.009));
  const cards = tilingOf(parseGrid('cards-3x3'));
  assert.ok(Math.abs(cards.boardAspect(0.7) - 0.7) < 1e-9, 'a card board takes a picture of 0.7 as it is');
  assert.ok(Math.abs(cards.boardAspect(2) - (5 / 7) * 1.08) < 1e-9, 'and stretches its cards at most 8 %');
});

test('only pieces of one shape swap (ClippedTiling classes)', () => {
  const t = tilingOf(parseGrid('triangles-11x5'));
  const [w, h] = [600, 600 / t.boardAspect(1)];
  const polys = Array.from({ length: t.cells }, (_, i) => t.polygon(i, w, h));
  const shapes = polys.map((p) => shapeOf(p, w).key);
  assert.equal(new Set(shapes).size, 2 + 4, 'up, down and four kinds of half triangle');
  const { pairs } = pickSwaps(polys, w, h, t.cellSize(w, h), 42);
  assert.equal(pairs.length, 3);
  for (const [a, b] of pairs) assert.equal(shapes[a], shapes[b]);
});

test('the words of an invite', () => {
  const base = { hostName: 'Mia', title: 'Red Panda', grid: 'cards-7x7t7', painting: false, players: 2 };
  assert.deepEqual(inviteCopy(base), {
    title: 'Mia invites you to play Red Panda',
    description: 'Play together in Carden · Cards 7x7 · 2 of 5 players',
    board: 'Cards 7x7',
    players: '2 of 5 players',
    alt: 'Red Panda as a board of 49 cards, beside the name Carden',
  });
  assert.equal(inviteCopy({ ...base, painting: true, grid: 'hexagons-5x5t4' }).description, 'Play together in Carden · Hexagons 5x5 · Painting · 2 of 5 players');
  assert.equal(inviteCopy({ ...base, grid: 'triangles-9x4t2' }).board, 'Triangles 4x4');
  // A name the filter refuses, an empty one or the fallback: no name at all.
  for (const hostName of ['', null, 'Player', 'www.spam.com', '@handle']) assert.equal(inviteCopy({ ...base, hostName }).title, 'Play Red Panda together', String(hostName));
  assert.equal(inviteCopy({ ...base, title: 'Untitled' }).title, 'Mia invites you to play a picture');
  assert.equal(inviteCopy({ ...base, title: '', hostName: '' }).title, 'Play a picture together');
});

test('the page: per-invite tags for crawlers, nothing but what the inviter shares', () => {
  const copy = inviteCopy({ hostName: 'Mia <b>', title: 'Owls & "friends"', grid: 'cards-4x4t2', painting: false, players: 1 });
  const image = cardUrl('a'.repeat(32), 'p1');
  const html = renderPage({ code: 'K7QH2MXP', game: { hostId: 'secret-host-id', $id: 'secret-game-id' }, copy, image });
  const tag = (p) => new RegExp(`<meta property="${p}" content="([^"]*)">`).exec(html)?.[1];
  assert.equal(tag('og:title'), 'Mia &lt;b&gt; invites you to play Owls &amp; &quot;friends&quot;');
  assert.equal(tag('og:description'), 'Play together in Carden · Cards 4x4 · 1 of 5 players');
  assert.equal(tag('og:url'), 'https://join.carden.page/K7QH2MXP');
  assert.equal(tag('og:image'), image);
  assert.equal(tag('og:image:width'), '1200');
  assert.ok(!html.includes('secret-host-id') && !html.includes('secret-game-id'), 'no ids');
  assert.ok(html.includes('href="carden://join/K7QH2MXP"') && html.includes('href="https://play.carden.page/join/K7QH2MXP?play=1"'));
  assert.ok(html.includes(`href="${GET_CARDEN}"`));
  assert.ok(Buffer.byteLength(html) < 32 * 1024, 'far under the crawlers\' limits (300 KB head, 1 MB page)');
  assert.ok(html.indexOf('og:image"') < 4096, 'the tags come first');
  assert.ok(!/http-equiv="refresh"|location\.replace/.test(html), 'no redirect: crawlers and people read the same page');

  const ended = renderPage({ code: 'K7QH2MXP', game: null });
  assert.match(ended, /<meta property="og:image" content="https:\/\/play\.carden\.page\/invite-card\.jpg">/);
  assert.match(ended, /<meta property="og:title" content="Carden: Your calm picture puzzle">/);
  assert.match(ended, /This game has ended/);
});

test('invite paths and the association file', () => {
  assert.equal(codeOfPath('/K7QH2MXP'), 'K7QH2MXP');
  assert.equal(codeOfPath('/k7qh-2mxp'), 'K7QH2MXP');
  assert.equal(codeOfPath('/join/K7QH2MXP/'), 'K7QH2MXP');
  for (const p of ['/', '/health', '/K7QH2MX0', '/join', '/join/a/b', '/FEEDBACK1']) assert.equal(codeOfPath(p), null, p);
  assert.equal(isInviteRequest({ method: 'GET', path: '/K7QH2MXP', headers: {} }), true);
  assert.equal(isInviteRequest({ method: 'POST', path: '/K7QH2MXP', headers: {} }), false);
  assert.equal(isInviteRequest({ method: 'GET', path: '/health', headers: {} }), false);
  assert.equal(isInviteRequest({ method: 'GET', path: '/', host: 'join.carden.page', headers: {} }), true);
  assert.equal(isInviteRequest({ method: 'GET', path: '/.well-known/apple-app-site-association', headers: {} }), true);
  const [details] = ASSOCIATION.applinks.details;
  assert.deepEqual(details.appIDs, ['C24QP73SQM.com.matejbaco.cardjigsawworld']);
  const match = (pattern, path) => new RegExp(`^${pattern.split('').map((c) => (c === '*' ? '.*' : c === '?' ? '.' : c.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))).join('')}$`).test(path);
  const opens = (path) => {
    for (const c of details.components) if (match(c['/'], path)) return c.exclude !== true;
    return false;
  };
  assert.equal(opens('/K7QH2MXP'), true);
  assert.equal(opens('/join/K7QH2MXP'), true);
  assert.equal(opens('/'), false);
  assert.equal(opens('/robots.txt'), false);
});

test('a card is kept by its picture and board, never by its game', () => {
  const g = { puzzleId: 'pack-owls-01', grid: 'cards-4x4t2', painting: false, code: 'K7QH2MXP', $id: 'g1', hostId: 'h1' };
  const now = Date.UTC(2026, 9, 17);
  const id = cardId(g, now);
  assert.match(id, /^[0-9a-f]{32}$/);
  assert.equal(cardId({ ...g, code: 'OTHERCDE', $id: 'g2', hostId: 'h2' }, now), id, 'another game on the same board shares it');
  assert.notEqual(cardId({ ...g, painting: true }, now), id);
  assert.notEqual(cardId({ ...g, grid: 'cards-5x5t4' }, now), id);
  assert.notEqual(cardId(g, now + 8 * 86400e3), id, 'a new one each week');
  assert.equal(CARD_VERSION, 1);
  assert.deepEqual(pictureFile('https://fra.cloud.appwrite.io/v1/storage/buckets/puzzle-images/files/pde0e018/view?project=x'), { bucketId: 'puzzle-images', fileId: 'pde0e018' });
  assert.equal(pictureFile('https://example.com/a.jpg'), null);
});

test('the lettering has every word a card can show', () => {
  const text = JSON.parse(readFileSync(new URL('../assets/invite/text.json', import.meta.url), 'utf8'));
  for (const grid of ['cards-7x7', 'squares-22x22', 'triangles-37x18', 'hexagons-23x23', 'cards-10x14']) {
    for (const painting of [false, true]) {
      const board = parseGrid(grid);
      const lines = inviteLines(board, tilingOf(board).cells, painting);
      for (const style of ['headline', 'detail', 'muted']) assert.ok(canWrite(text, style, lines[style]), `${grid} ${style}: ${lines[style].join(' ')}`);
    }
  }
  assert.deepEqual(tokens(['Cards', '17x17']), ['Cards', ' ', '1', '7', 'x', '1', '7']);
});

test('cards: 1200 x 630 JPEG under WhatsApp\'s 600 KB, for every shape and a giant board', async () => {
  for (const [name, grid, painting] of [['red-panda', 'cards-7x7t7', false], ['tulip-fields', 'squares-5x5t4', true], ['parthenon', 'triangles-11x5t4', false], ['meerkat', 'hexagons-5x5t4', false], ['azure-window', 'hexagons-23x23t11', false]]) {
    const t = performance.now();
    const card = await renderCard({ image: welcome(name), board: parseGrid(grid), painting, seed: 1 });
    const ms = performance.now() - t;
    const img = await loadImage(card.jpeg);
    assert.deepEqual([img.width, img.height], [1200, 630], grid);
    assert.ok(card.jpeg.length < 600 * 1024, `${grid}: ${card.jpeg.length} bytes`);
    assert.equal(card.cells, tilingOf(parseGrid(grid)).cells);
    assert.ok(card.swapped >= 2, `${grid}: pieces still to swap`);
    assert.ok(card.board.x >= 64 && card.board.x + card.board.w < 1200 - 300, `${grid}: the board leaves room for the words`);
    assert.ok(ms < 5000, `${grid}: ${ms} ms`);
  }
});
