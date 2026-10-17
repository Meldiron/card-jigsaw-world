// The board's geometry for the invite card: a port of the parts of lib/game/tiling.dart and
// lib/game/modes.dart that draw a board (piece polygons, the board's proportions, cell size), so the
// link preview shows the real shapes and the real number of pieces. Dart stays the source of truth;
// test/invite-tiling.test.mjs checks piece counts and shapes against values taken from it.

/// The four modes (GameMode in modes.dart).
export const MODES = {
  cards: { label: 'Cards' },
  squares: { label: 'Squares' },
  triangles: { label: 'Triangles' },
  hexagons: { label: 'Hexagons' },
};

/// A board code as the routes and coop_games.grid carry it: `cards-4x5t3`, `hexagons-5x7`, `4x4`
/// (BoardCode.decode). Null when it is not one.
export function parseGrid(grid) {
  const m = /^(?:([a-z]{1,16})[-:])?(\d{1,3})(?:x(\d{1,3}))?(?:[t-](\d{1,2}))?$/.exec(String(grid ?? '').trim());
  if (!m) return null;
  const mode = MODES[m[1] ?? 'cards'] ? (m[1] ?? 'cards') : 'cards';
  const cols = Math.max(1, Number(m[2]));
  const rows = Math.max(1, m[3] === undefined ? cols : Number(m[3]));
  if (cols * rows > 2000) return null;
  return { mode, cols, rows, tier: m[4] === undefined ? null : Number(m[4]) };
}

/// The size as players read it (BoardSpec.size): a triangle column is one up and one down
/// triangle, so the 4x4 triangle board (`triangles-9x4`) reads 4x4.
export const sizeLabel = ({ mode, cols, rows }) => `${mode === 'triangles' ? Math.floor(cols / 2) : cols}x${rows}`;

const SQRT3 = Math.sqrt(3);

// --- Clipping (ClippedTiling.clipToBoard) ---------------------------------------------------------

function clipToBoard(poly, w, h) {
  const eps = 1e-9 * Math.max(1, w, h);
  let out = poly;
  for (const edge of [0, 1, 2, 3]) {
    const inside = ([x, y]) => (edge === 0 ? x >= -eps : edge === 1 ? y >= -eps : edge === 2 ? x <= w + eps : y <= h + eps);
    const cut = (a, b) => {
      const t = edge === 0 ? (0 - a[0]) / (b[0] - a[0]) : edge === 1 ? (0 - a[1]) / (b[1] - a[1]) : edge === 2 ? (w - a[0]) / (b[0] - a[0]) : (h - a[1]) / (b[1] - a[1]);
      const p = [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
      return edge === 0 ? [0, p[1]] : edge === 1 ? [p[0], 0] : edge === 2 ? [w, p[1]] : [p[0], h];
    };
    const input = out;
    out = [];
    if (input.length === 0) break;
    for (let i = 0; i < input.length; i++) {
      const s = input[(i - 1 + input.length) % input.length];
      const e = input[i];
      if (inside(e)) {
        if (!inside(s)) out.push(cut(s, e));
        out.push(e);
      } else if (inside(s)) {
        out.push(cut(s, e));
      }
    }
  }
  const tol = 1e-6 * Math.max(1, w, h);
  const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
  let pts = [];
  for (const p of out) if (pts.length === 0 || dist(pts[pts.length - 1], p) > tol) pts.push(p);
  if (pts.length > 1 && dist(pts[0], pts[pts.length - 1]) <= tol) pts.pop();
  let changed = true;
  while (changed && pts.length > 3) {
    changed = false;
    for (let i = 0; i < pts.length; i++) {
      const a = pts[(i - 1 + pts.length) % pts.length];
      const b = pts[i];
      const c = pts[(i + 1) % pts.length];
      const cross = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
      if (Math.abs(cross) <= tol * (dist(c, a) + 1)) {
        pts = pts.filter((_, k) => k !== i);
        changed = true;
        break;
      }
    }
  }
  return pts;
}

// --- Tilings -------------------------------------------------------------------------------------

/// Rectangular cells (GridTiling): squares are square, cards 5:7.
function grid(mode, cols, rows) {
  const cellAspect = mode === 'cards' ? 5 / 7 : 1;
  const a = (cols / rows) * cellAspect;
  return {
    mode,
    cols,
    rows,
    cells: cols * rows,
    naturalAspectRange: [a, a],
    stretchTolerance: mode === 'cards' ? 0.08 : 0.009,
    polygon(slot, w, h) {
      const cw = w / cols;
      const ch = h / rows;
      const x = (slot % cols) * cw;
      const y = Math.floor(slot / cols) * ch;
      return [[x, y], [x + cw, y], [x + cw, y + ch], [x, y + ch]];
    },
    cellSize: (w, h) => Math.min(w / cols, h / rows),
  };
}

/// Rows of alternating up and down triangles, halves at both ends (TriangleTiling).
function triangles(cols, rows) {
  const steps = Math.max(1, cols - 1);
  const fused = rows === 4 && (cols - 1) % 2 === 1;
  const coords = [];
  for (let r = 0; r < rows; r++) for (let k = 0; k < cols; k++) if (!(fused && k === cols - 1 && r % 2 === 1)) coords.push([k, r]);
  const full = ([k, r], w, h) => {
    const half = w / steps;
    const rh = h / rows;
    const x = k * half;
    const top = r * rh;
    const bottom = (r + 1) * rh;
    if (fused && k === cols - 1) return [[x, top], [x, top + 2 * rh], [x - half, bottom]];
    if ((k + r) % 2 === 1) return [[x - half, bottom], [x + half, bottom], [x, top]];
    return [[x - half, top], [x + half, top], [x, bottom]];
  };
  const a = steps / (rows * SQRT3);
  return {
    mode: 'triangles',
    cols,
    rows,
    cells: coords.length,
    naturalAspectRange: [a, a],
    stretchTolerance: 0.1,
    polygon: (slot, w, h) => clipToBoard(full(coords[slot], w, h), w, h),
    cellSize: (w, h) => Math.min(((2 * w) / steps) * 0.8, h / rows),
  };
}

/// A pointy-top honeycomb cut by the board's edges (HexTiling).
function hexagons(cols, rows) {
  const minCut = 0;
  const maxCut = 0.24;
  const coords = [];
  for (let r = 0; r < rows; r++) {
    if (r % 2 === 0) for (let c = 0; c < cols; c++) coords.push([2 * c + 1, r]);
    else for (let c = 0; c <= cols; c++) coords.push([2 * c, r]);
  }
  const metrics = (w, h) => {
    const cw = w / cols;
    let hh = (cw * 2) / SQRT3;
    const span = (rows - 1) * 0.75;
    let cut = (h / hh - span) / 2;
    if (cut < minCut || cut > maxCut) {
      cut = Math.min(maxCut, Math.max(minCut, cut));
      hh = h / (span + 2 * cut);
    }
    return { cw, hh, top: cut * hh };
  };
  const full = ([X, r], w, h) => {
    const m = metrics(w, h);
    const cx = (X * m.cw) / 2;
    const cy = m.top + r * 0.75 * m.hh;
    const hw = m.cw / 2;
    const qh = m.hh / 4;
    const hh2 = m.hh / 2;
    return [[cx + hw, cy + qh], [cx, cy + hh2], [cx - hw, cy + qh], [cx - hw, cy - qh], [cx, cy - hh2], [cx + hw, cy - qh]];
  };
  const span = (rows - 1) * 0.75;
  const width = (cols * SQRT3) / 2;
  const lo = width / (span + 2 * maxCut);
  const tall = span + 2 * minCut;
  return {
    mode: 'hexagons',
    cols,
    rows,
    cells: coords.length,
    naturalAspectRange: [lo, tall > 0.05 ? width / tall : lo * 4],
    stretchTolerance: 0.1,
    polygon: (slot, w, h) => clipToBoard(full(coords[slot], w, h), w, h),
    cellSize: (w, h) => {
      const m = metrics(w, h);
      return Math.min(m.cw, m.hh * 0.85);
    },
  };
}

/// The tiling of a board (Tiling.of), with its pre-set pieces (Tiling.isPreset: the only piece of
/// its shape, dealt in its place and not counted) and the pieces a player plays (playableCells).
export function tilingOf({ mode, cols, rows }) {
  const c = Math.max(1, cols);
  const r = Math.max(1, rows);
  const t = mode === 'triangles' ? triangles(c, r) : mode === 'hexagons' ? hexagons(c, r) : grid(mode === 'squares' ? 'squares' : 'cards', c, r);
  const presets = t.mode === 'triangles' || t.mode === 'hexagons' ? presetSlots(t) : [];
  return { ...t, presets, playableCells: t.cells - presets.length, boardAspect: (imageAspect) => boardAspect(t, imageAspect) };
}

/// Slots whose shape no other piece has, on a board of the tiling's own proportions
/// (ClippedTiling._computeTopology works them out at its canonicalSize).
function presetSlots(t) {
  if (t.cells <= 1) return [];
  const [lo, hi] = t.naturalAspectRange;
  const h = 1000;
  const w = 1000 * Math.sqrt(lo * hi);
  const keys = Array.from({ length: t.cells }, (_, s) => shapeOf(t.polygon(s, w, h), w).key);
  const count = new Map();
  for (const k of keys) count.set(k, (count.get(k) ?? 0) + 1);
  return keys.flatMap((k, s) => (count.get(k) === 1 ? [s] : []));
}

/// The board's width / height for a picture of [imageAspect] (Tiling.boardAspect): the picture's
/// own proportions where the cells can take them, else the nearest they can.
function boardAspect(t, imageAspect) {
  const [lo, hi] = t.naturalAspectRange;
  const min = lo * (1 - t.stretchTolerance);
  const max = hi * (1 + t.stretchTolerance);
  if (!Number.isFinite(imageAspect) || imageAspect <= 0) return Math.sqrt(lo * hi);
  return Math.min(max, Math.max(min, imageAspect));
}

/// A polygon's vertices relative to its top-most (then left-most) vertex, starting there
/// (ClippedTiling._normalise): pieces with equal keys have the same shape, so one can sit in the
/// other's place.
export function shapeOf(poly, scale) {
  let start = 0;
  for (let i = 1; i < poly.length; i++) {
    const p = poly[i];
    const q = poly[start];
    if (p[1] < q[1] - 1e-6 || (Math.abs(p[1] - q[1]) <= 1e-6 && p[0] < q[0])) start = i;
  }
  const o = poly[start];
  const rel = [];
  for (let i = 0; i < poly.length; i++) {
    const p = poly[(start + i) % poly.length];
    rel.push(`${Math.round(((p[0] - o[0]) / scale) * 1000)},${Math.round(((p[1] - o[1]) / scale) * 1000)}`);
  }
  return { origin: o, key: rel.join(' ') };
}
