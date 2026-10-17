// A small raster toolkit for the invite card, in plain JavaScript: decode a PNG (Node's own zlib) or
// a JPEG (jpeg-js), resample, blur, draw rounded convex pieces with soft edges, blend, and encode the
// JPEG (jpeg.js). No native image library: a native one (Skia, 18 MB built) made every cold
// start of `api` about 1.2 s slower (measured 2026-10-17), and this card is the only drawing the
// function does.
//
// Images are { w, h, d }: d is a Float32Array of RGB (0-255), row after row. Masks are { w, h, d }
// with one coverage value (0-1) per pixel.
import { inflateSync } from 'node:zlib';
import jpeg from 'jpeg-js';

export const image = (w, h) => ({ w, h, d: new Float32Array(w * h * 3) });

// --- Decoding ------------------------------------------------------------------------------------

/// A PNG (8-bit, not interlaced: grey, RGB, palette, grey + alpha, RGBA) as { w, h, rgba }.
export function decodePng(buf) {
  const sig = [137, 80, 78, 71, 13, 10, 26, 10];
  for (let i = 0; i < 8; i++) if (buf[i] !== sig[i]) throw new Error('not a PNG');
  let w = 0;
  let h = 0;
  let depth = 0;
  let type = 0;
  let interlace = 0;
  let palette = null;
  let trns = null;
  const idat = [];
  for (let p = 8; p < buf.length; ) {
    const len = buf.readUInt32BE(p);
    const kind = buf.toString('latin1', p + 4, p + 8);
    const body = buf.subarray(p + 8, p + 8 + len);
    if (kind === 'IHDR') {
      w = body.readUInt32BE(0);
      h = body.readUInt32BE(4);
      depth = body[8];
      type = body[9];
      interlace = body[12];
    } else if (kind === 'PLTE') palette = body;
    else if (kind === 'tRNS') trns = body;
    else if (kind === 'IDAT') idat.push(body);
    else if (kind === 'IEND') break;
    p += 12 + len;
  }
  if (depth !== 8 || interlace !== 0) throw new Error(`PNG: depth ${depth}, interlace ${interlace} not read`);
  const channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[type];
  if (!channels) throw new Error(`PNG: colour type ${type}`);
  const raw = inflateSync(Buffer.concat(idat));
  const stride = w * channels;
  const px = new Uint8Array(h * stride);
  const bpp = channels;
  for (let y = 0; y < h; y++) {
    const f = raw[y * (stride + 1)];
    const ri = y * (stride + 1) + 1;
    const o = y * stride;
    const p = o - stride;
    // One loop per filter (PNG specification, section 9).
    if (f === 0) {
      for (let i = 0; i < stride; i++) px[o + i] = raw[ri + i];
    } else if (f === 1) {
      for (let i = 0; i < stride; i++) px[o + i] = (raw[ri + i] + (i >= bpp ? px[o + i - bpp] : 0)) & 255;
    } else if (f === 2) {
      for (let i = 0; i < stride; i++) px[o + i] = (raw[ri + i] + (y > 0 ? px[p + i] : 0)) & 255;
    } else if (f === 3) {
      for (let i = 0; i < stride; i++) px[o + i] = (raw[ri + i] + (((i >= bpp ? px[o + i - bpp] : 0) + (y > 0 ? px[p + i] : 0)) >> 1)) & 255;
    } else {
      for (let i = 0; i < stride; i++) {
        const a = i >= bpp ? px[o + i - bpp] : 0;
        const b = y > 0 ? px[p + i] : 0;
        const c = i >= bpp && y > 0 ? px[p + i - bpp] : 0;
        const pa = Math.abs(b - c);
        const pb = Math.abs(a - c);
        const pc = Math.abs(a + b - 2 * c);
        px[o + i] = (raw[ri + i] + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c)) & 255;
      }
    }
  }
  const rgba = new Uint8Array(w * h * 4);
  for (let i = 0, j = 0; i < w * h; i++, j += channels) {
    let r;
    let g;
    let b;
    let al = 255;
    if (type === 0) r = g = b = px[j];
    else if (type === 4) {
      r = g = b = px[j];
      al = px[j + 1];
    } else if (type === 3) {
      const k = px[j];
      r = palette[k * 3];
      g = palette[k * 3 + 1];
      b = palette[k * 3 + 2];
      if (trns && k < trns.length) al = trns[k];
    } else {
      r = px[j];
      g = px[j + 1];
      b = px[j + 2];
      if (type === 6) al = px[j + 3];
    }
    rgba[i * 4] = r;
    rgba[i * 4 + 1] = g;
    rgba[i * 4 + 2] = b;
    rgba[i * 4 + 3] = al;
  }
  return { w, h, rgba };
}

/// A PNG or a JPEG as { w, h, rgba }.
export function decode(buf) {
  if (buf[0] === 137 && buf[1] === 80) return decodePng(buf);
  const j = jpeg.decode(buf, { useTArray: true, formatAsRGBA: true, maxMemoryUsageInMB: 256 });
  return { w: j.width, h: j.height, rgba: j.data };
}

/// The RGB part of a decoded picture as an image.
export function fromRgba({ w, h, rgba }) {
  const out = image(w, h);
  for (let i = 0; i < w * h; i++) {
    out.d[i * 3] = rgba[i * 4];
    out.d[i * 3 + 1] = rgba[i * 4 + 1];
    out.d[i * 3 + 2] = rgba[i * 4 + 2];
  }
  return out;
}

export { encodeJpeg } from './jpeg.js';

// --- Resampling and blur -------------------------------------------------------------------------

/// Weights of a tent filter taking [n] source samples (from [start], [length] of them) to [m]:
/// an average over the source when shrinking, a straight line between samples when growing.
function weights(start, length, n, m) {
  const scale = length / m;
  const support = Math.max(1, scale);
  const taps = Math.ceil(support) * 2 + 2;
  // For each output sample: the first source index and `taps` weights from there (zeros past the end).
  const first = new Int32Array(m);
  const wt = new Float32Array(m * taps);
  for (let x = 0; x < m; x++) {
    const c = start + (x + 0.5) * scale - 0.5;
    const lo = Math.max(0, Math.min(n - 1, Math.floor(c - support)));
    first[x] = lo;
    let sum = 0;
    for (let k = 0; k < taps; k++) {
      const i = lo + k;
      if (i >= n) break;
      const v = Math.max(0, 1 - Math.abs(i - c) / support);
      wt[x * taps + k] = v;
      sum += v;
    }
    if (sum === 0) {
      first[x] = Math.min(n - 1, Math.max(0, Math.round(c)));
      wt[x * taps] = 1;
      sum = 1;
    }
    for (let k = 0; k < taps; k++) wt[x * taps + k] /= sum;
  }
  return { first, wt, taps };
}

/// The part ([sx], [sy], [sw], [sh]) of [src] drawn into [dw] x [dh] pixels.
export function resample(src, sx, sy, sw, sh, dw, dh) {
  const wx = weights(sx, sw, src.w, dw);
  const wy = weights(sy, sh, src.h, dh);
  const y0 = wy.first[0];
  const y1 = Math.min(src.h - 1, wy.first[dh - 1] + wy.taps - 1);
  const rows = y1 - y0 + 1;
  const tmp = new Float32Array(rows * dw * 3);
  const sd = src.d;
  for (let y = 0; y < rows; y++) {
    const srow = (y0 + y) * src.w * 3;
    for (let x = 0; x < dw; x++) {
      let r = 0;
      let g = 0;
      let b = 0;
      const f = wx.first[x];
      const kmax = Math.min(wx.taps, src.w - f);
      for (let k = 0; k < kmax; k++) {
        const v = wx.wt[x * wx.taps + k];
        if (v === 0) continue;
        const o = srow + (f + k) * 3;
        r += sd[o] * v;
        g += sd[o + 1] * v;
        b += sd[o + 2] * v;
      }
      const t = (y * dw + x) * 3;
      tmp[t] = r;
      tmp[t + 1] = g;
      tmp[t + 2] = b;
    }
  }
  const out = image(dw, dh);
  const od = out.d;
  for (let y = 0; y < dh; y++) {
    const f = wy.first[y];
    const kmax = Math.min(wy.taps, y1 - f + 1);
    const t0 = y * dw * 3;
    for (let k = 0; k < kmax; k++) {
      const v = wy.wt[y * wy.taps + k];
      if (v === 0) continue;
      const r0 = (f + k - y0) * dw * 3;
      for (let i = 0; i < dw * 3; i++) od[t0 + i] += tmp[r0 + i] * v;
    }
  }
  return out;
}

/// Three box blurs of [radius] over [channels] interleaved values per pixel, edges held: about a
/// Gaussian of sigma sqrt(((2r + 1)^2 - 1) / 4).
export function blur(data, w, h, channels, radius) {
  const r = Math.max(0, Math.round(radius));
  if (r === 0) return data;
  const tmp = new Float32Array(data.length);
  const pass = (src, dst, len, count, step, lineStep) => {
    const win = 2 * r + 1;
    for (let line = 0; line < count; line++) {
      for (let ch = 0; ch < channels; ch++) {
        const base = line * lineStep + ch;
        const at = (i) => src[base + Math.min(len - 1, Math.max(0, i)) * step];
        let sum = 0;
        for (let i = -r; i <= r; i++) sum += at(i);
        for (let i = 0; i < len; i++) {
          dst[base + i * step] = sum / win;
          sum += at(i + r + 1) - at(i - r);
        }
      }
    }
  };
  for (let k = 0; k < 3; k++) {
    pass(data, tmp, w, h, channels, w * channels);
    pass(tmp, data, h, w, w * channels, channels);
  }
  return data;
}

// --- Pieces --------------------------------------------------------------------------------------

/// Signed distance from (px, py) to the convex polygon [poly] (negative inside).
function polygonDistance(poly, px, py) {
  let inside = -Infinity;
  const n = poly.length;
  for (let i = 0; i < n; i++) {
    const e = poly.edges[i];
    const s = (px - e.ax) * e.nx + (py - e.ay) * e.ny;
    if (s > inside) inside = s;
  }
  if (inside <= 0) return inside;
  let best = Infinity;
  for (let i = 0; i < n; i++) {
    const e = poly.edges[i];
    const t = Math.max(0, Math.min(1, ((px - e.ax) * e.dx + (py - e.ay) * e.dy) / e.len2));
    const qx = e.ax + e.dx * t - px;
    const qy = e.ay + e.dy * t - py;
    const d = qx * qx + qy * qy;
    if (d < best) best = d;
  }
  return Math.sqrt(best);
}

/// [pts] (convex) with the edge data the distance needs; the normals point out.
function prepared(pts) {
  let area = 0;
  for (let i = 0; i < pts.length; i++) {
    const a = pts[i];
    const b = pts[(i + 1) % pts.length];
    area += a[0] * b[1] - b[0] * a[1];
  }
  const sign = area > 0 ? 1 : -1;
  const poly = pts.map((p) => p);
  poly.area = Math.abs(area) / 2;
  poly.edges = pts.map((a, i) => {
    const b = pts[(i + 1) % pts.length];
    const dx = b[0] - a[0];
    const dy = b[1] - a[1];
    const l = Math.hypot(dx, dy) || 1;
    // With the vertices clockwise on screen (y down, area > 0) the outward normal is (dy, -dx).
    return { ax: a[0], ay: a[1], dx, dy, len2: dx * dx + dy * dy || 1, nx: (sign * dy) / l, ny: (-sign * dx) / l };
  });
  return poly;
}

/// [poly] moved in by [h] on every edge; null when nothing is left.
export function inset(poly, h) {
  const n = poly.length;
  if (h <= 0) return poly.map((p) => [...p]);
  const pre = prepared(poly);
  const lines = pre.edges.map((e) => ({ px: e.ax - e.nx * h, py: e.ay - e.ny * h, dx: e.dx, dy: e.dy }));
  const out = [];
  for (let i = 0; i < n; i++) {
    const a = lines[(i - 1 + n) % n];
    const b = lines[i];
    const den = a.dx * b.dy - a.dy * b.dx;
    if (Math.abs(den) < 1e-9) {
      out.push([b.px, b.py]);
      continue;
    }
    const t = ((b.px - a.px) * b.dy - (b.py - a.py) * b.dx) / den;
    out.push([a.px + a.dx * t, a.py + a.dy * t]);
  }
  // Moved past itself (a piece thinner than the inset): nothing is left.
  const after = prepared(out);
  for (let i = 0; i < n; i++) {
    const e0 = pre.edges[i];
    const e1 = after.edges[i];
    if (e0.dx * e1.dx + e0.dy * e1.dy <= 0) return null;
  }
  return after.area > 1e-6 ? out : null;
}

/// A piece: the polygon [poly] less half the gutter [half], its corners rounded with [radius] (the
/// game's corner length along each edge, as board_widget.dart draws it).
export function roundedPiece(poly, half, radius) {
  const base = inset(poly, half);
  if (!base) return null;
  // The corner as an arc: a corner length t along both edges at an angle theta is an arc of radius
  // t * tan(theta / 2). One radius for the whole piece, the smallest of its corners.
  const n = base.length;
  let rho = Infinity;
  for (let i = 0; i < n; i++) {
    const p = base[(i - 1 + n) % n];
    const c = base[i];
    const q = base[(i + 1) % n];
    const a = [p[0] - c[0], p[1] - c[1]];
    const b = [q[0] - c[0], q[1] - c[1]];
    const la = Math.hypot(a[0], a[1]);
    const lb = Math.hypot(b[0], b[1]);
    const theta = Math.acos(Math.max(-1, Math.min(1, (a[0] * b[0] + a[1] * b[1]) / (la * lb || 1))));
    const t = Math.min(radius, Math.min(la, lb) / 2.2);
    rho = Math.min(rho, t * Math.tan(theta / 2));
  }
  let core = null;
  for (let r = rho; r >= 0; r = r > 0.25 ? r * 0.7 : -1) {
    core = inset(base, r);
    if (core) return shape(core, r);
  }
  return shape(base, 0);
}

function shape(core, r) {
  const poly = prepared(core);
  let l = Infinity;
  let t = Infinity;
  let rr = -Infinity;
  let b = -Infinity;
  for (const [x, y] of core) {
    l = Math.min(l, x);
    t = Math.min(t, y);
    rr = Math.max(rr, x);
    b = Math.max(b, y);
  }
  return {
    poly,
    r,
    box: { l: l - r - 1, t: t - r - 1, r: rr + r + 1, b: b + r + 1 },
    /// Signed distance to the rounded outline.
    distance: (x, y) => polygonDistance(poly, x, y) - r,
  };
}

/// Calls [fn](i, cover, d) for every pixel of [img] that [piece] covers (i: the pixel's index; d:
/// signed distance at its centre). [transform]: from screen to the piece's own coordinates (the
/// lifted piece), with its [scale].
export function eachPixel(w, h, piece, fn, { transform = null, scale = 1, pad = 0 } = {}) {
  let box = piece.box;
  if (transform) box = transform.box;
  const x0 = Math.max(0, Math.floor(box.l - pad));
  const y0 = Math.max(0, Math.floor(box.t - pad));
  const x1 = Math.min(w - 1, Math.ceil(box.r + pad));
  const y1 = Math.min(h - 1, Math.ceil(box.b + pad));
  for (let y = y0; y <= y1; y++) {
    for (let x = x0; x <= x1; x++) {
      let px = x + 0.5;
      let py = y + 0.5;
      if (transform) [px, py] = transform.back(px, py);
      const d = piece.distance(px, py) * scale;
      const cover = d <= -0.5 ? 1 : d >= 0.5 + pad ? 0 : Math.max(0, 0.5 - d);
      if (cover > 0 || pad > 0) fn(y * w + x, cover, d);
    }
  }
}

/// [src] at (x, y), straight lines between its pixels, edges held.
export function sample(src, x, y, out) {
  const fx = Math.min(src.w - 1, Math.max(0, x - 0.5));
  const fy = Math.min(src.h - 1, Math.max(0, y - 0.5));
  const x0 = Math.floor(fx);
  const y0 = Math.floor(fy);
  const x1 = Math.min(src.w - 1, x0 + 1);
  const y1 = Math.min(src.h - 1, y0 + 1);
  const ax = fx - x0;
  const ay = fy - y0;
  for (let c = 0; c < 3; c++) {
    const a = src.d[(y0 * src.w + x0) * 3 + c];
    const b = src.d[(y0 * src.w + x1) * 3 + c];
    const cc = src.d[(y1 * src.w + x0) * 3 + c];
    const dd = src.d[(y1 * src.w + x1) * 3 + c];
    out[c] = (a * (1 - ax) + b * ax) * (1 - ay) + (cc * (1 - ax) + dd * ax) * ay;
  }
  return out;
}

/// Blends colour [rgb] into [img] at pixel [i] with [alpha].
export function blend(img, i, rgb, alpha) {
  const o = i * 3;
  img.d[o] += (rgb[0] - img.d[o]) * alpha;
  img.d[o + 1] += (rgb[1] - img.d[o + 1]) * alpha;
  img.d[o + 2] += (rgb[2] - img.d[o + 2]) * alpha;
}

/// Lays a shadow of [mask] (coverage per pixel of [img], inside [box]) under what comes next:
/// blurred by [sigma], moved down by [dy], [alpha] at most. Soft as it is, it is worked out at half
/// the size and drawn back smoothly.
export function shadow(img, mask, box, sigma, dy, alpha) {
  const margin = Math.ceil(3 * sigma) + 2;
  const x0 = Math.max(0, Math.floor(box.l) - margin) & ~1;
  const y0 = Math.max(0, Math.floor(box.t) - margin) & ~1;
  const x1 = Math.min(img.w, Math.ceil(box.r) + margin);
  const y1 = Math.min(img.h, Math.ceil(box.b) + margin);
  const hw = Math.ceil((x1 - x0) / 2);
  const hh = Math.ceil((y1 - y0) / 2);
  const half = new Float32Array(hw * hh);
  for (let y = y0; y < y1; y++) {
    const row = ((y - y0) >> 1) * hw;
    for (let x = x0; x < x1; x++) half[row + ((x - x0) >> 1)] += mask[y * img.w + x] / 4;
  }
  // Three box passes of radius r make a Gaussian of sigma about sqrt((2r + 1)^2 - 1) / 2.
  const s = sigma / 2;
  const r = Math.max(1, Math.round((Math.sqrt(4 * s * s + 1) - 1) / 2));
  blur(half, hw, hh, 1, r);
  const off = Math.round(dy);
  for (let y = Math.max(0, y0 + off); y < Math.min(img.h, y1 + off); y++) {
    const fy = Math.min(hh - 1, Math.max(0, (y - off - y0 + 0.5) / 2 - 0.5));
    const iy = Math.floor(fy);
    const ay = fy - iy;
    const iy1 = Math.min(hh - 1, iy + 1);
    for (let x = x0; x < x1; x++) {
      const fx = Math.min(hw - 1, Math.max(0, (x - x0 + 0.5) / 2 - 0.5));
      const ix = Math.floor(fx);
      const ax = fx - ix;
      const ix1 = Math.min(hw - 1, ix + 1);
      const m = (half[iy * hw + ix] * (1 - ax) + half[iy * hw + ix1] * ax) * (1 - ay) + (half[iy1 * hw + ix] * (1 - ax) + half[iy1 * hw + ix1] * ax) * ay;
      const a = m * alpha;
      if (a <= 0.001) continue;
      const o = (y * img.w + x) * 3;
      img.d[o] *= 1 - a;
      img.d[o + 1] *= 1 - a;
      img.d[o + 2] *= 1 - a;
    }
  }
}
