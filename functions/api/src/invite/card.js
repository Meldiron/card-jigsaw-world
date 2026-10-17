// The invite card: the link preview (og:image, 1200 x 630 JPEG) of a Play together invite. The
// design of web/invite-card.jpg (owner, 2026-10-17: "the pieces, the blurred zoomed version in the
// background, the app logo"), drawn for the real board: the picture of the game, dealt in its
// mode's shapes (cards, squares, triangles, hexagons) at its real size, a few pieces still to swap
// and one lifted, the same picture blurred and zoomed behind it, the logo and the board in words.
//
// The function has no fonts: the words come from a white atlas set in SF Pro Rounded
// (assets/invite/text.png + text.json, made by tools/brand/invite_card.py), so only the words
// listed there can be drawn. raster.js draws, in plain JavaScript.
//
// A change to the drawing needs CARD_VERSION in store.js bumped, or kept cards stay as they were.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { MODES, sizeLabel, tilingOf, shapeOf } from './tiling.js';
import { decode, decodePng, fromRgba, encodeJpeg, resample, blur, roundedPiece, eachPixel, sample, blend, shadow } from './raster.js';

export const WIDTH = 1200;
export const HEIGHT = 630;
const QUALITY = 84;

const ASSETS = new URL('../../assets/invite/', import.meta.url);
let assets = null;

function loadAssets() {
  if (!assets) {
    const text = JSON.parse(readFileSync(new URL('text.json', ASSETS), 'utf8'));
    const atlas = decodePng(readFileSync(new URL('text.png', ASSETS)));
    const logo = decodePng(readFileSync(new URL('logo.png', ASSETS)));
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
    if (/^\d+$/.test(w) || /^\d+x\d+$/.test(w)) out.push(...w.split(''));
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

/// White words of the atlas onto [img], [alpha] at most.
function drawLine(img, a, style, toks, x, baseline, alpha) {
  const s = a.text.styles[style];
  const pad = a.text.pad;
  const white = [255, 255, 255];
  let pen = x;
  for (const t of toks) {
    if (t === ' ') {
      pen += s.space;
      continue;
    }
    const [gx, gy, gw, gh, adv] = s.tokens[t];
    const ox = Math.round(pen - pad);
    const oy = Math.round(baseline - pad - s.ascent);
    for (let y = 0; y < gh; y++) {
      const ty = oy + y;
      if (ty < 0 || ty >= img.h) continue;
      for (let x2 = 0; x2 < gw; x2++) {
        const tx = ox + x2;
        if (tx < 0 || tx >= img.w) continue;
        const cov = a.atlas.rgba[((gy + y) * a.atlas.w + gx + x2) * 4 + 3] / 255;
        if (cov > 0) blend(img, ty * img.w + tx, white, cov * alpha);
      }
    }
    pen += adv;
  }
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

// --- Choosing the pieces to swap -----------------------------------------------------------------

const sub = (a, b) => [a[0] - b[0], a[1] - b[1]];
const len = (v) => Math.hypot(v[0], v[1]);

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

function shuffle(list, rnd) {
  const out = [...list];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
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
  // Inner pieces first; the board's own edge pieces only when there are too few.
  const interior = [...Array(n).keys()].filter((i) => !onEdge[i]);
  const pool = shuffle(interior.length >= 2 * want ? interior : [...Array(n).keys()], rnd);
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

// --- Drawing -------------------------------------------------------------------------------------

/// The part of a [w] x [h] picture with the proportions [aspect], from its centre (BoxFit.cover).
function coverCrop(w, h, aspect) {
  let cw = w;
  let ch = h;
  if (w / h > aspect) cw = h * aspect;
  else ch = w / aspect;
  return { sx: (w - cw) / 2, sy: (h - ch) / 2, sw: cw, sh: ch };
}

/// Relative luminance of an sRGB colour (WCAG).
function luminance(r, g, b) {
  const c = (v) => {
    const s = Math.max(0, Math.min(255, v)) / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * c(r) + 0.7152 * c(g) + 0.0722 * c(b);
}

const INK = [12, 12, 16];

/// The blurred, zoomed picture behind the card, dimmed so the white words read on any picture:
/// 52 % towards near-black as before, more where the words would sit on a bright part.
function background(pic, textBox) {
  const q = 4;
  const sw = Math.round(WIDTH / q);
  const sh = Math.round(HEIGHT / q);
  const crop = coverCrop(pic.w, pic.h, WIDTH / HEIGHT);
  // Zoomed in a little (as the picture is in the game's own blurred backdrop).
  const zoom = 1.12;
  const small = resample(pic, crop.sx + (crop.sw - crop.sw / zoom) / 2, crop.sy + (crop.sh - crop.sh / zoom) / 2, crop.sw / zoom, crop.sh / zoom, sw, sh);
  blur(small.d, sw, sh, 3, 9);
  // The words' contrast: white against the brightest tenth of the picture under them.
  const lums = [];
  for (let y = Math.floor(textBox.y / q); y < Math.min(sh, Math.ceil((textBox.y + textBox.h) / q)); y++) {
    for (let x = Math.floor(textBox.x / q); x < Math.min(sw, Math.ceil((textBox.x + textBox.w) / q)); x++) {
      const o = (y * sw + x) * 3;
      lums.push(luminance(small.d[o], small.d[o + 1], small.d[o + 2]));
    }
  }
  lums.sort((a, b) => a - b);
  const bright = lums[Math.floor(lums.length * 0.9)] ?? 0;
  const ink = luminance(...INK);
  // At least 4.5:1 for white against it (the smallest words, 27 px at 72 %, then keep more than
  // 3:1, the large-text minimum).
  let dim = 0.52;
  const target = 1.05 / 4.5 - 0.05;
  if (bright * (1 - dim) + ink * dim > target) dim = Math.min(0.8, (bright - target) / Math.max(1e-6, bright - ink));
  const img = resample(small, 0, 0, sw, sh, WIDTH, HEIGHT);
  for (let i = 0; i < img.d.length; i += 3) {
    img.d[i] += (INK[0] - img.d[i]) * dim;
    img.d[i + 1] += (INK[1] - img.d[i + 1]) * dim;
    img.d[i + 2] += (INK[2] - img.d[i + 2]) * dim;
  }
  return { img, dim };
}

/// Draws the card. [image]: the picture (PNG or JPEG bytes); [board]: parseGrid's answer; [kind]:
/// `invite` (the board in words) or `site` (the tagline and the address: web/invite-card.jpg);
/// [swaps]: the pairs to show swapped instead of a seeded pick. Returns the JPEG and what was drawn.
export function renderCard({ image: bytes, board, painting = false, kind = 'invite', seed, swaps }) {
  const a = loadAssets();
  const pic = fromRgba(decode(bytes));
  const tiling = tilingOf(board);
  const cells = tiling.cells;
  const aspect = tiling.boardAspect(pic.w / pic.h);

  // The words beside the board.
  const lines = kind === 'site' ? { headline: ['Your calm picture puzzle'], detail: null, muted: ['play.carden.page'] } : inviteLines(board, cells, painting);
  for (const [style, words] of [['headline', lines.headline], ['detail', lines.detail], ['muted', lines.muted]]) {
    if (words && !canWrite(a.text, style, words)) throw new Error(`invite card: no lettering for "${words.join(' ')}"`);
  }
  const word = tokens(['Carden']);
  const head = tokens(lines.headline);
  const detail = lines.detail ? tokens(lines.detail) : null;
  const muted = tokens(lines.muted);
  const logoSize = a.logo.w;
  const textW = Math.ceil(Math.max(logoSize, lineWidth(a.text, 'wordmark', word), lineWidth(a.text, 'headline', head), detail ? lineWidth(a.text, 'detail', detail) : 0, lineWidth(a.text, 'muted', muted)));
  const st = a.text.styles;
  // Logo, wordmark, headline, detail, muted: height of each and the gap above it.
  const blocks = [
    ['logo', logoSize, 0],
    ['wordmark', st.wordmark.ascent + st.wordmark.descent * 0.4, 22],
    ['headline', st.headline.ascent + st.headline.descent * 0.6, 10],
    ...(detail ? [['detail', st.detail.ascent + st.detail.descent * 0.6, 20]] : []),
    ['muted', st.muted.ascent + st.muted.descent * 0.6, detail ? 8 : 12],
  ];
  const textH = blocks.reduce((s, [, h, gap]) => s + h + gap, 0);

  // The board: as large as fits beside the words, the two centred together.
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
  const bx = Math.round(Math.max(64, (WIDTH - (bw + gapX + textW)) / 2));
  const by = Math.round((HEIGHT - bh) / 2);
  const tx = bx + bw + gapX;
  const ty = Math.round((HEIGHT - textH) / 2);

  const { img, dim } = background(pic, { x: tx - 8, y: ty, w: Math.min(WIDTH - tx + 8, textW + 16), h: textH });

  // The picture as the board crops it (Tiling.crop), at the board's size.
  const crop = coverCrop(pic.w, pic.h, aspect);
  const boardPic = resample(pic, crop.sx, crop.sy, crop.sw, crop.sh, bw, bh);

  // Pieces: the gutter and corners of the game's classic cards, finer on giant boards.
  const polys = Array.from({ length: cells }, (_, i) => tiling.polygon(i, bw, bh));
  const cell = tiling.cellSize(bw, bh);
  const fine = cells > 100;
  const gap = fine ? Math.max(1.2, cell * 0.05) : Math.max(5, cell * 0.06);
  const radius = fine ? cell * 0.14 : Math.min(15, cell * 0.11);
  const picked = pickSwaps(polys, bw, bh, cell, seed ?? hashSeed(`${board.mode}-${board.cols}x${board.rows}`));
  const { shapes, centres } = picked;
  const pairs = swaps ?? picked.pairs;
  const shows = [...Array(cells).keys()];
  for (const [p, q] of pairs) [shows[p], shows[q]] = [shows[q], shows[p]];
  const lifted = pairs.length ? pairs[0][0] : -1;
  const pieces = polys.map((p) => roundedPiece(p.map(([x, y]) => [x + bx, y + by]), gap / 2, radius));

  // Shadows under every piece at rest.
  const mask = new Float32Array(WIDTH * HEIGHT);
  pieces.forEach((piece, s) => {
    if (piece && s !== lifted) eachPixel(WIDTH, HEIGHT, piece, (i, cover) => (mask[i] = Math.max(mask[i], cover)));
  });
  shadow(img, mask, { l: bx, t: by, r: bx + bw, b: by + bh }, fine ? 4 : 9, fine ? 3 : 6, 0.42);

  // The pieces: in its place a piece shows its own part of the picture; one still to swap shows
  // another's, moved onto it (grey until it is in place, on a Painting board).
  const rgb = [0, 0, 0];
  const grey = (c) => {
    const l = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
    c[0] = c[1] = c[2] = l;
    return c;
  };
  const drawPiece = (s, opts = {}) => {
    const piece = pieces[s];
    if (!piece) return;
    const card = shows[s];
    const dx = shapes[s].origin[0] - shapes[card].origin[0];
    const dy = shapes[s].origin[1] - shapes[card].origin[1];
    const gray = painting && card !== s;
    if (card === s && !opts.transform) {
      // In its place: the board's own pixels, one for one.
      eachPixel(WIDTH, HEIGHT, piece, (i, cover) => {
        const x = Math.min(bw - 1, Math.max(0, (i % WIDTH) - bx));
        const y = Math.min(bh - 1, Math.max(0, Math.floor(i / WIDTH) - by));
        const o = (y * bw + x) * 3;
        rgb[0] = boardPic.d[o];
        rgb[1] = boardPic.d[o + 1];
        rgb[2] = boardPic.d[o + 2];
        blend(img, i, rgb, cover);
      });
      return;
    }
    eachPixel(WIDTH, HEIGHT, piece, (i, cover) => {
      let x = (i % WIDTH) + 0.5;
      let y = Math.floor(i / WIDTH) + 0.5;
      if (opts.transform) [x, y] = opts.transform.back(x, y);
      sample(boardPic, x - bx - dx, y - by - dy, rgb);
      blend(img, i, gray ? grey(rgb) : rgb, cover);
    }, opts);
  };
  for (let s = 0; s < cells; s++) if (s !== lifted) drawPiece(s);

  if (lifted >= 0 && pieces[lifted]) {
    const piece = pieces[lifted];
    // Its place, empty while the piece is up.
    eachPixel(WIDTH, HEIGHT, piece, (i, cover) => blend(img, i, [0, 0, 0], cover * 0.3));
    // The piece, picked up: larger, off its place, a deeper shadow and a light edge. Higher on a
    // giant board, where the pieces are small.
    const scale = fine ? 1.35 : 1.1;
    const cx = centres[lifted][0] + bx;
    const cy = centres[lifted][1] + by;
    const ox = -cell * (fine ? 0.2 : 0.12);
    const oy = -cell * (fine ? 0.3 : 0.16);
    const b = piece.box;
    const forward = (x, y) => [cx + ox + (x - cx) * scale, cy + oy + (y - cy) * scale];
    const [l, t] = forward(b.l, b.t);
    const [r, bt] = forward(b.r, b.b);
    const transform = { back: (x, y) => [cx + (x - cx - ox) / scale, cy + (y - cy - oy) / scale], box: { l, t, r, b: bt } };
    const liftMask = new Float32Array(WIDTH * HEIGHT);
    eachPixel(WIDTH, HEIGHT, piece, (i, cover) => (liftMask[i] = cover), { transform, scale });
    shadow(img, liftMask, transform.box, fine ? 7 : 15, fine ? 6 : 14, 0.5);
    drawPiece(lifted, { transform, scale });
    const edge = fine ? 1.2 : 2;
    eachPixel(WIDTH, HEIGHT, piece, (i, _cover, d) => {
      const ring = Math.max(0, Math.min(1, edge / 2 + 0.5 - Math.abs(d + edge / 2)));
      if (ring > 0) blend(img, i, [255, 255, 255], ring * 0.9);
    }, { transform, scale, pad: 1 });
  }

  // The words and the logo.
  let y = ty;
  for (const [what, h, gapAbove] of blocks) {
    y += gapAbove;
    if (what === 'logo') {
      const lg = a.logo;
      for (let ly = 0; ly < lg.h; ly++) {
        for (let lx = 0; lx < lg.w; lx++) {
          const o = (ly * lg.w + lx) * 4;
          const al = lg.rgba[o + 3] / 255;
          if (al > 0) blend(img, (y + ly) * WIDTH + tx + lx, [lg.rgba[o], lg.rgba[o + 1], lg.rgba[o + 2]], al);
        }
      }
    } else {
      const s = st[what];
      const toks = what === 'wordmark' ? word : what === 'headline' ? head : what === 'detail' ? detail : muted;
      drawLine(img, a, what, toks, what === 'wordmark' ? tx - 4 : tx, Math.round(y + s.ascent), what === 'muted' ? 0.72 : what === 'detail' ? 0.94 : 1);
    }
    y += h;
  }

  const jpeg = encodeJpeg(img, QUALITY);
  return { jpeg, width: WIDTH, height: HEIGHT, cells, board: { x: bx, y: by, w: bw, h: bh }, swapped: pairs.length * 2, dim };
}

/// A number from a text, for the seed.
export function hashSeed(text) {
  return createHash('sha256').update(String(text)).digest().readUInt32LE(0);
}
