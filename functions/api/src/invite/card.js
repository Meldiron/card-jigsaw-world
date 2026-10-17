// The invite card: the link preview (og:image, 1200 x 630 JPEG) of a Play together invite. The
// design of web/invite-card.jpg (owner, 2026-10-17: "the pieces, the blurred zoomed version in the
// background, the app logo"), drawn for the real board: the picture of the game, dealt in its
// mode's shapes (cards, squares, triangles, hexagons) at its real size, a few pieces still to swap
// and one lifted, the same picture blurred and zoomed behind it, the logo and the board in words.
//
// The function has no fonts: the words come from a white atlas set in SF Pro Rounded
// (assets/invite/text.png + text.json, made by tools/brand/invite_card.py), so only the words
// listed there can be drawn. @napi-rs/canvas (Skia, prebuilt for Appwrite's runtime) draws.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { createCanvas, loadImage } from '@napi-rs/canvas';
import { MODES, sizeLabel, tilingOf, shapeOf } from './tiling.js';

export const WIDTH = 1200;
export const HEIGHT = 630;

// A change to the drawing needs CARD_VERSION in store.js bumped, or kept cards stay as they were.

const ASSETS = new URL('../../assets/invite/', import.meta.url);
let assets = null;

async function loadAssets() {
  if (!assets) {
    const text = JSON.parse(readFileSync(new URL('text.json', ASSETS), 'utf8'));
    const [atlas, logo] = await Promise.all([loadImage(readFileSync(new URL('text.png', ASSETS))), loadImage(readFileSync(new URL('logo.png', ASSETS)))]);
    assets = { text, atlas, logo };
  }
  return assets;
}

// --- Words ---------------------------------------------------------------------------------------

/// A line as tokens of the atlas: words stay whole, numbers go digit by digit, spaces are spaces.
export function tokens(words) {
  const out = [];
  words.forEach((w, i) => {
    if (i > 0) out.push(' ');
    if (/^\d+$/.test(w)) out.push(...w.split(''));
    else if (/^\d+x\d+$/.test(w)) out.push(...w.split(''));
    else out.push(w);
  });
  return out;
}

function lineWidth(text, style, toks) {
  const s = text.styles[style];
  let w = 0;
  for (const t of toks) w += t === ' ' ? s.space : s.tokens[t][4];
  return w;
}

function drawLine(ctx, a, style, toks, x, baseline, alpha = 1) {
  const s = a.text.styles[style];
  const pad = a.text.pad;
  ctx.save();
  ctx.globalAlpha = alpha;
  let pen = x;
  for (const t of toks) {
    if (t === ' ') {
      pen += s.space;
      continue;
    }
    const [gx, gy, gw, gh, adv] = s.tokens[t];
    ctx.drawImage(a.atlas, gx, gy, gw, gh, Math.round(pen - pad), Math.round(baseline - pad - s.ascent), gw, gh);
    pen += adv;
  }
  ctx.restore();
}

/// Whether every token of [words] in [style] is in the atlas.
export function canWrite(text, style, words) {
  const s = text.styles[style];
  return !!s && tokens(words).every((t) => t === ' ' || s.tokens[t]);
}

/// The lines of an invite card: what the board is, in the app's words (BoardSpec.size, "Cards 7x7").
export function inviteLines(board, cells, painting) {
  const count = [String(cells), board.mode === 'cards' ? 'cards' : 'pieces'];
  return {
    headline: ['Play together'],
    detail: [MODES[board.mode].label, sizeLabel(board)],
    muted: painting ? [...count, '·', 'Painting'] : count,
  };
}

// --- Geometry ------------------------------------------------------------------------------------

const sub = (a, b) => [a[0] - b[0], a[1] - b[1]];
const len = (v) => Math.hypot(v[0], v[1]);
const unit = (v) => {
  const l = len(v) || 1;
  return [v[0] / l, v[1] / l];
};

/// [poly] moved in by [h] on every edge (half the gutter between pieces).
function inset(poly, h) {
  const n = poly.length;
  let cx = 0;
  let cy = 0;
  for (const p of poly) {
    cx += p[0] / n;
    cy += p[1] / n;
  }
  const lines = poly.map((p, i) => {
    const q = poly[(i + 1) % n];
    const d = unit(sub(q, p));
    let nx = -d[1];
    let ny = d[0];
    if (nx * (cx - p[0]) + ny * (cy - p[1]) < 0) {
      nx = -nx;
      ny = -ny;
    }
    return { p: [p[0] + nx * h, p[1] + ny * h], d };
  });
  return poly.map((_, i) => {
    const a = lines[(i - 1 + n) % n];
    const b = lines[i];
    const den = a.d[0] * b.d[1] - a.d[1] * b.d[0];
    if (Math.abs(den) < 1e-9) return b.p;
    const t = ((b.p[0] - a.p[0]) * b.d[1] - (b.p[1] - a.p[1]) * b.d[0]) / den;
    return [a.p[0] + a.d[0] * t, a.p[1] + a.d[1] * t];
  });
}

/// The piece's outline with rounded corners (_PieceClip._shape in board_widget.dart, every edge open).
function tracePiece(ctx, pts, radius) {
  const n = pts.length;
  for (let i = 0; i < n; i++) {
    const prev = pts[(i - 1 + n) % n];
    const cur = pts[i];
    const next = pts[(i + 1) % n];
    const r = Math.min(radius, Math.min(len(sub(cur, prev)), len(sub(next, cur))) / 2.2);
    const inDir = unit(sub(cur, prev));
    const outDir = unit(sub(next, cur));
    const a = [cur[0] - inDir[0] * r, cur[1] - inDir[1] * r];
    const b = [cur[0] + outDir[0] * r, cur[1] + outDir[1] * r];
    if (i === 0) ctx.moveTo(a[0], a[1]);
    else ctx.lineTo(a[0], a[1]);
    ctx.quadraticCurveTo(cur[0], cur[1], b[0], b[1]);
  }
  ctx.closePath();
}

/// A small seeded random generator (mulberry32), so a board is always drawn the same way.
function random(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/// Which pieces are still to swap: pairs of pieces of the same shape, apart from each other, more
/// on bigger boards; the first of them is the one lifted.
export function pickSwaps(polys, w, h, cell, seed) {
  const n = polys.length;
  const rnd = random(seed);
  const shapes = polys.map((p) => shapeOf(p, w));
  const centres = polys.map((p) => [p.reduce((s, v) => s + v[0], 0) / p.length, p.reduce((s, v) => s + v[1], 0) / p.length]);
  const onEdge = polys.map((p) => p.some((v) => v[0] < 0.5 || v[1] < 0.5 || v[0] > w - 0.5 || v[1] > h - 0.5));
  const want = n <= 12 ? 1 : n <= 36 ? 2 : n <= 120 ? 3 : 4;
  const used = new Set();
  const pairs = [];
  const order = [...Array(n).keys()].sort((a, b) => (onEdge[a] ? 1 : 0) - (onEdge[b] ? 1 : 0) || rnd() - 0.5);
  // Interior pieces first, in random order; the board's own edge pieces only when needed.
  const interior = order.filter((i) => !onEdge[i]);
  const pool = interior.length >= 2 * want ? shuffle(interior, rnd) : shuffle(order, rnd);
  for (const a of pool) {
    if (pairs.length >= want) break;
    if (used.has(a)) continue;
    const mates = pool.filter((b) => b !== a && !used.has(b) && shapes[b].key === shapes[a].key && len(sub(centres[a], centres[b])) > cell * 1.6);
    if (mates.length === 0) continue;
    const b = mates[Math.floor(rnd() * mates.length)];
    used.add(a);
    used.add(b);
    pairs.push([a, b]);
  }
  return { pairs, shapes, centres };
}

function shuffle(list, rnd) {
  const out = [...list];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

// --- Drawing -------------------------------------------------------------------------------------

/// The part of [img] with the proportions [aspect], from its centre (BoxFit.cover).
function coverCrop(img, aspect) {
  let w = img.width;
  let h = img.height;
  if (w / h > aspect) w = h * aspect;
  else h = w / aspect;
  return { sx: (img.width - w) / 2, sy: (img.height - h) / 2, sw: w, sh: h };
}

/// Relative luminance of an sRGB colour (WCAG).
function luminance(r, g, b) {
  const c = (v) => {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * c(r) + 0.7152 * c(g) + 0.0722 * c(b);
}

/// The blurred, zoomed picture behind the card, dimmed so the white words read on any picture:
/// today's 52 % towards near-black, more where the words would sit on a bright part.
function background(ctx, img, textBox) {
  const small = createCanvas(WIDTH / 4, HEIGHT / 4);
  const s = small.getContext('2d');
  const crop = coverCrop(img, WIDTH / HEIGHT);
  // Zoomed in a little, so the blur never reaches past the picture's edge.
  const zoom = 1.12;
  const zw = crop.sw / zoom;
  const zh = crop.sh / zoom;
  s.filter = 'blur(9px)';
  s.drawImage(img, crop.sx + (crop.sw - zw) / 2, crop.sy + (crop.sh - zh) / 2, zw, zh, -6, -6, small.width + 12, small.height + 12);
  s.filter = 'none';
  // The words' contrast: white on the dimmed picture under them, the brightest tenth counted.
  const d = s.getImageData(Math.floor(textBox.x / 4), Math.floor(textBox.y / 4), Math.max(1, Math.ceil(textBox.w / 4)), Math.max(1, Math.ceil(textBox.h / 4))).data;
  const lums = [];
  for (let i = 0; i < d.length; i += 4) lums.push(luminance(d[i], d[i + 1], d[i + 2]));
  lums.sort((a, b) => a - b);
  const bright = lums[Math.floor(lums.length * 0.9)] ?? 0;
  const ink = luminance(12, 12, 16);
  // Dim so that white has at least 4.5:1 against the brightest tenth (the smallest words, 27 px at
  // 72 %, then keep more than 3:1, the large-text minimum).
  let dim = 0.52;
  const target = 1.05 / 4.5 - 0.05;
  if (bright * (1 - dim) + ink * dim > target) dim = Math.min(0.8, (bright - target) / Math.max(1e-6, bright - ink));
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(small, 0, 0, WIDTH, HEIGHT);
  ctx.fillStyle = `rgba(12, 12, 16, ${dim.toFixed(3)})`;
  ctx.fillRect(0, 0, WIDTH, HEIGHT);
  return dim;
}

/// Draws the card. [image]: the picture (encoded); [board]: parseGrid's answer; [kind]: `invite`
/// (the board in words) or `site` (the tagline and the address: web/invite-card.jpg).
/// Returns the JPEG and what was drawn, for logs and tests.
export async function renderCard({ image, board, painting = false, kind = 'invite', seed, swaps }) {
  const a = await loadAssets();
  const img = await loadImage(image);
  const tiling = tilingOf(board);
  const cells = tiling.cells;
  const aspect = tiling.boardAspect(img.width / img.height);

  // The words beside the board.
  const lines = kind === 'site' ? { headline: ['Your calm picture puzzle'], detail: null, muted: ['play.carden.page'] } : inviteLines(board, cells, painting);
  for (const [style, words] of [['headline', lines.headline], ['detail', lines.detail], ['muted', lines.muted]]) {
    if (words && !canWrite(a.text, style, words)) throw new Error(`invite card: no lettering for "${words.join(' ')}"`);
  }
  const head = tokens(lines.headline);
  const detail = lines.detail ? tokens(lines.detail) : null;
  const muted = tokens(lines.muted);
  const logoSize = 96;
  const word = tokens(['Carden']);
  const textW = Math.ceil(Math.max(logoSize, lineWidth(a.text, 'wordmark', word), lineWidth(a.text, 'headline', head), detail ? lineWidth(a.text, 'detail', detail) : 0, lineWidth(a.text, 'muted', muted)));
  const st = a.text.styles;
  // Vertical rhythm: logo, wordmark, headline, detail, muted.
  const blocks = [
    ['logo', logoSize, 0],
    ['wordmark', st.wordmark.ascent + st.wordmark.descent * 0.4, 22],
    ['headline', st.headline.ascent + st.headline.descent * 0.6, 10],
    ...(detail ? [['detail', st.detail.ascent + st.detail.descent * 0.6, 20]] : []),
    ['muted', st.muted.ascent + st.muted.descent * 0.6, detail ? 8 : 12],
  ];
  const textH = blocks.reduce((s, [, h, gap]) => s + h + gap, 0);

  // The board: as large as fits beside the words, centred with them.
  const gapX = 72;
  const maxH = 520;
  const maxW = Math.min(620, WIDTH - 2 * 64 - gapX - textW);
  let bw = Math.min(maxW, maxH * aspect);
  let bh = bw / aspect;
  if (bh > maxH) {
    bh = maxH;
    bw = bh * aspect;
  }
  bw = Math.round(bw);
  bh = Math.round(bh);
  const total = bw + gapX + textW;
  const bx = Math.round(Math.max(64, (WIDTH - total) / 2));
  const by = Math.round((HEIGHT - bh) / 2);
  const tx = bx + bw + gapX;
  const ty = Math.round((HEIGHT - textH) / 2);

  const canvas = createCanvas(WIDTH, HEIGHT);
  const ctx = canvas.getContext('2d');
  const dim = background(ctx, img, { x: tx - 8, y: ty, w: Math.min(WIDTH - tx + 8, textW + 16), h: textH });

  // The picture as the board crops it (Tiling.crop), drawn once into the board's size.
  const crop = coverCrop(img, aspect);
  const pic = createCanvas(bw, bh);
  const pc = pic.getContext('2d');
  pc.imageSmoothingEnabled = true;
  pc.imageSmoothingQuality = 'high';
  pc.drawImage(img, crop.sx, crop.sy, crop.sw, crop.sh, 0, 0, bw, bh);
  let grey = null;
  if (painting) {
    // Painting: a piece is grey until it is in its place.
    grey = createCanvas(bw, bh);
    const gc = grey.getContext('2d');
    gc.filter = 'grayscale(1)';
    gc.drawImage(pic, 0, 0);
  }

  // Pieces: the gutter and corners of the game's classic cards, finer on giant boards.
  const polys = Array.from({ length: cells }, (_, i) => tiling.polygon(i, bw, bh));
  const cell = tiling.cellSize(bw, bh);
  const fine = cells > 100;
  const gap = fine ? Math.max(1.6, cell * 0.06) : Math.max(5, cell * 0.06);
  const radius = fine ? cell * 0.14 : Math.min(15, cell * 0.11);
  const seedValue = seed ?? hashSeed(`${board.mode}-${board.cols}x${board.rows}`);
  const picked = pickSwaps(polys, bw, bh, cell, seedValue);
  const { shapes, centres } = picked;
  const pairs = swaps ?? picked.pairs;
  const shows = [...Array(cells).keys()];
  for (const [p, q] of pairs) [shows[p], shows[q]] = [shows[q], shows[p]];
  const lifted = pairs.length ? pairs[0][0] : -1;
  const shapesInset = polys.map((p) => inset(p, gap / 2).map(([x, y]) => [x + bx, y + by]));

  // Shadows under every piece at rest.
  ctx.save();
  ctx.shadowColor = 'rgba(0, 0, 0, 0.42)';
  ctx.shadowBlur = fine ? 8 : 18;
  ctx.shadowOffsetY = fine ? 3 : 6;
  ctx.fillStyle = 'rgba(14, 14, 18, 1)';
  ctx.beginPath();
  for (let s = 0; s < cells; s++) if (s !== lifted) tracePiece(ctx, shapesInset[s], radius);
  ctx.fill();
  ctx.restore();

  // Pieces in their places: the picture once, through all of them.
  ctx.save();
  ctx.beginPath();
  for (let s = 0; s < cells; s++) if (shows[s] === s) tracePiece(ctx, shapesInset[s], radius);
  ctx.clip();
  ctx.drawImage(pic, bx, by);
  ctx.restore();

  // Pieces still to swap: the picture of another place, moved onto this one.
  const piece = (s, transform) => {
    const card = shows[s];
    const dx = shapes[s].origin[0] - shapes[card].origin[0];
    const dy = shapes[s].origin[1] - shapes[card].origin[1];
    ctx.save();
    if (transform) transform();
    ctx.beginPath();
    tracePiece(ctx, shapesInset[s], radius);
    ctx.clip();
    ctx.drawImage(grey ?? pic, bx + dx, by + dy);
    ctx.restore();
  };
  for (let s = 0; s < cells; s++) if (shows[s] !== s && s !== lifted) piece(s);

  if (lifted >= 0) {
    // Its place, empty while the piece is up.
    ctx.save();
    ctx.beginPath();
    tracePiece(ctx, shapesInset[lifted], radius);
    ctx.fillStyle = 'rgba(0, 0, 0, 0.30)';
    ctx.fill();
    ctx.restore();
    // The piece, picked up: a little larger, off its place, a deeper shadow and a light edge.
    const [cx, cy] = [centres[lifted][0] + bx, centres[lifted][1] + by];
    // On a giant board the pieces are small: lifted higher, so it still reads.
    const scale = fine ? 1.35 : 1.1;
    const lift = () => {
      ctx.translate(cx - cell * (fine ? 0.2 : 0.12), cy - cell * (fine ? 0.3 : 0.16));
      ctx.scale(scale, scale);
      ctx.translate(-cx, -cy);
    };
    ctx.save();
    lift();
    ctx.shadowColor = 'rgba(0, 0, 0, 0.5)';
    ctx.shadowBlur = fine ? 14 : 30;
    ctx.shadowOffsetY = fine ? 6 : 14;
    ctx.fillStyle = 'rgba(14, 14, 18, 1)';
    ctx.beginPath();
    tracePiece(ctx, shapesInset[lifted], radius);
    ctx.fill();
    ctx.restore();
    piece(lifted, lift);
    ctx.save();
    lift();
    ctx.beginPath();
    tracePiece(ctx, shapesInset[lifted], radius);
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.9)';
    ctx.lineWidth = fine ? 1.2 : 2;
    ctx.stroke();
    ctx.restore();
  }

  // The words.
  let y = ty;
  for (const [what, h, gapAbove] of blocks) {
    y += gapAbove;
    if (what === 'logo') {
      ctx.drawImage(a.logo, tx, y, logoSize, logoSize);
    } else {
      const s = st[what];
      const toks = what === 'wordmark' ? word : what === 'headline' ? head : what === 'detail' ? detail : muted;
      drawLine(ctx, a, what, toks, what === 'wordmark' ? tx - 4 : tx, Math.round(y + s.ascent), what === 'muted' ? 0.72 : what === 'detail' ? 0.94 : 1);
    }
    y += h;
  }

  const jpeg = await canvas.encode('jpeg', 86);
  return { jpeg, width: WIDTH, height: HEIGHT, cells, board: { x: bx, y: by, w: bw, h: bh }, swapped: pairs.length * 2, dim };
}

/// A number from a text, for the seed.
export function hashSeed(text) {
  return createHash('sha256').update(String(text)).digest().readUInt32LE(0);
}
