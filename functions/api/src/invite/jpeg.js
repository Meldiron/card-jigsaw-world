// A baseline JPEG encoder for the invite card: 4:2:0 colour (half the work and a smaller file than
// jpeg-js's 4:4:4), the standard tables of the JPEG specification (Annex K) scaled by quality as
// libjpeg does, and the AAN forward DCT with its scale folded into the quantisation.

const ZIGZAG = new Int32Array([
  0, 1, 5, 6, 14, 15, 27, 28, 2, 4, 7, 13, 16, 26, 29, 42, 3, 8, 12, 17, 25, 30, 41, 43, 9, 11, 18, 24, 31, 40, 44, 53,
  10, 19, 23, 32, 39, 45, 52, 54, 20, 22, 33, 38, 46, 51, 55, 60, 21, 34, 37, 47, 50, 56, 59, 61, 35, 36, 48, 49, 57, 58, 62, 63,
]);

const LUMA_Q = [
  16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55, 14, 13, 16, 24, 40, 57, 69, 56, 14, 17, 22, 29, 51, 87, 80, 62,
  18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92, 49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99,
];
const CHROMA_Q = [
  17, 18, 24, 47, 99, 99, 99, 99, 18, 21, 26, 66, 99, 99, 99, 99, 24, 26, 56, 99, 99, 99, 99, 99, 47, 66, 99, 99, 99, 99, 99, 99,
  99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
];

// Annex K.3 Huffman tables: code counts per length 1-16, then the values.
const DC_LUMA = [[0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]];
const DC_CHROMA = [[0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]];
const AC_LUMA = [
  [0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7d],
  [
    0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xa1, 0x08,
    0x23, 0x42, 0xb1, 0xc1, 0x15, 0x52, 0xd1, 0xf0, 0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0a, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x25, 0x26, 0x27, 0x28,
    0x29, 0x2a, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
    0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
    0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6,
    0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe1, 0xe2,
    0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa,
  ],
];
const AC_CHROMA = [
  [0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77],
  [
    0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, 0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91,
    0xa1, 0xb1, 0xc1, 0x09, 0x23, 0x33, 0x52, 0xf0, 0x15, 0x62, 0x72, 0xd1, 0x0a, 0x16, 0x24, 0x34, 0xe1, 0x25, 0xf1, 0x17, 0x18, 0x19, 0x1a, 0x26,
    0x27, 0x28, 0x29, 0x2a, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58,
    0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
    0x88, 0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4,
    0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda,
    0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa,
  ],
];

/// Code and length for every value of a table.
function huffman([counts, values]) {
  const code = new Int32Array(256);
  const size = new Int32Array(256);
  let c = 0;
  let k = 0;
  for (let len = 1; len <= 16; len++) {
    for (let i = 0; i < counts[len - 1]; i++) {
      code[values[k]] = c;
      size[values[k]] = len;
      c++;
      k++;
    }
    c <<= 1;
  }
  return { code, size };
}

const TABLES = { dcY: huffman(DC_LUMA), acY: huffman(AC_LUMA), dcC: huffman(DC_CHROMA), acC: huffman(AC_CHROMA) };
const AAN = [1, 1.387039845, 1.306562965, 1.175875602, 1, 0.785694958, 0.5411961, 0.275899379];

/// The quantisation table for [quality] in natural order, and the divisors the DCT output is
/// multiplied by (AAN scale folded in).
function quant(base, quality) {
  const q = Math.min(100, Math.max(1, quality));
  const scale = q < 50 ? 5000 / q : 200 - 2 * q;
  const table = new Int32Array(64);
  const div = new Float64Array(64);
  for (let i = 0; i < 64; i++) {
    table[i] = Math.min(255, Math.max(1, Math.floor((base[i] * scale + 50) / 100)));
    div[i] = 1 / (table[i] * AAN[i >> 3] * AAN[i & 7] * 8);
  }
  return { table, div };
}

/// In-place AAN forward DCT of an 8 x 8 block (rows, then columns).
function fdct(d) {
  for (let o = 0; o < 64; o += 8) dct8(d, o, 1);
  for (let o = 0; o < 8; o++) dct8(d, o, 8);
}

function dct8(d, o, s) {
  const d0 = d[o];
  const d1 = d[o + s];
  const d2 = d[o + 2 * s];
  const d3 = d[o + 3 * s];
  const d4 = d[o + 4 * s];
  const d5 = d[o + 5 * s];
  const d6 = d[o + 6 * s];
  const d7 = d[o + 7 * s];
  const t0 = d0 + d7;
  const t7 = d0 - d7;
  const t1 = d1 + d6;
  const t6 = d1 - d6;
  const t2 = d2 + d5;
  const t5 = d2 - d5;
  const t3 = d3 + d4;
  const t4 = d3 - d4;
  let t10 = t0 + t3;
  const t13 = t0 - t3;
  let t11 = t1 + t2;
  let t12 = t1 - t2;
  d[o] = t10 + t11;
  d[o + 4 * s] = t10 - t11;
  const z1 = (t12 + t13) * 0.707106781;
  d[o + 2 * s] = t13 + z1;
  d[o + 6 * s] = t13 - z1;
  t10 = t4 + t5;
  t11 = t5 + t6;
  t12 = t6 + t7;
  const z5 = (t10 - t12) * 0.382683433;
  const z2 = 0.5411961 * t10 + z5;
  const z4 = 1.306562965 * t12 + z5;
  const z3 = t11 * 0.707106781;
  const z11 = t7 + z3;
  const z13 = t7 - z3;
  d[o + 5 * s] = z13 + z2;
  d[o + 3 * s] = z13 - z2;
  d[o + s] = z11 + z4;
  d[o + 7 * s] = z11 - z4;
}

/// JPEG bytes of an RGB image ({ w, h, d: Float32Array of R, G, B in 0-255 }) at [quality].
export function encodeJpeg({ w, h, d }, quality = 85) {
  const qy = quant(LUMA_Q, quality);
  const qc = quant(CHROMA_Q, quality);
  // Planes: Y at full size, Cb and Cr averaged over 2 x 2, all padded by repeating the last
  // row and column to whole MCUs (16 x 16).
  const pw = Math.ceil(w / 16) * 16;
  const ph = Math.ceil(h / 16) * 16;
  const Y = new Float32Array(pw * ph);
  const cw = pw / 2;
  const chh = ph / 2;
  const Cb = new Float32Array(cw * chh);
  const Cr = new Float32Array(cw * chh);
  for (let y = 0; y < ph; y++) {
    const sy = Math.min(h - 1, y);
    for (let x = 0; x < pw; x++) {
      const o = (sy * w + Math.min(w - 1, x)) * 3;
      const r = d[o];
      const g = d[o + 1];
      const b = d[o + 2];
      Y[y * pw + x] = 0.299 * r + 0.587 * g + 0.114 * b - 128;
      const c = (y >> 1) * cw + (x >> 1);
      Cb[c] += (-0.168736 * r - 0.331264 * g + 0.5 * b) / 4;
      Cr[c] += (0.5 * r - 0.418688 * g - 0.081312 * b) / 4;
    }
  }

  // Output with byte stuffing.
  let out = new Uint8Array(Math.max(65536, (w * h) >> 1));
  let n = 0;
  const byte = (v) => {
    if (n >= out.length) {
      const grown = new Uint8Array(out.length * 2);
      grown.set(out);
      out = grown;
    }
    out[n++] = v;
  };
  const word = (v) => {
    byte(v >> 8);
    byte(v & 255);
  };
  let acc = 0;
  let bits = 0;
  const put = (code, len) => {
    for (let i = len - 1; i >= 0; i--) {
      acc = (acc << 1) | ((code >> i) & 1);
      if (++bits === 8) {
        byte(acc);
        if (acc === 0xff) byte(0);
        acc = 0;
        bits = 0;
      }
    }
  };

  // Headers.
  word(0xffd8);
  word(0xffe0);
  word(16);
  for (const c of [0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]) byte(c);
  word(0xffdb);
  word(132);
  for (const [id, q] of [[0, qy], [1, qc]]) {
    byte(id);
    const zz = new Int32Array(64);
    for (let i = 0; i < 64; i++) zz[ZIGZAG[i]] = q.table[i];
    for (let i = 0; i < 64; i++) byte(zz[i]);
  }
  word(0xffc0);
  word(17);
  byte(8);
  word(h);
  word(w);
  byte(3);
  for (const [id, hv, t] of [[1, 0x22, 0], [2, 0x11, 1], [3, 0x11, 1]]) {
    byte(id);
    byte(hv);
    byte(t);
  }
  word(0xffc4);
  const tables = [[0x00, DC_LUMA], [0x10, AC_LUMA], [0x01, DC_CHROMA], [0x11, AC_CHROMA]];
  word(2 + tables.reduce((s, [, [c, v]]) => s + 17 + v.length, 0));
  for (const [cls, [counts, values]] of tables) {
    byte(cls);
    for (const c of counts) byte(c);
    for (const v of values) byte(v);
  }
  word(0xffda);
  word(12);
  byte(3);
  for (const [id, t] of [[1, 0x00], [2, 0x11], [3, 0x11]]) {
    byte(id);
    byte(t);
  }
  byte(0);
  byte(63);
  byte(0);

  // Entropy-coded blocks.
  const block = new Float64Array(64);
  const coef = new Int32Array(64);
  const category = (v) => {
    let a = v < 0 ? -v : v;
    let c = 0;
    while (a) {
      c++;
      a >>= 1;
    }
    return c;
  };
  const unit = (plane, stride, x0, y0, q, dc, ac, prev) => {
    for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) block[y * 8 + x] = plane[(y0 + y) * stride + x0 + x];
    fdct(block);
    for (let i = 0; i < 64; i++) {
      const v = block[i] * q.div[i];
      coef[ZIGZAG[i]] = v > 0 ? Math.floor(v + 0.5) : -Math.floor(-v + 0.5);
    }
    const diff = coef[0] - prev;
    const dcCat = category(diff);
    put(dc.code[dcCat], dc.size[dcCat]);
    if (dcCat) put(diff < 0 ? diff - 1 + (1 << dcCat) : diff, dcCat);
    let last = 63;
    while (last > 0 && coef[last] === 0) last--;
    let zeros = 0;
    for (let i = 1; i <= last; i++) {
      const v = coef[i];
      if (v === 0) {
        zeros++;
        continue;
      }
      while (zeros >= 16) {
        put(ac.code[0xf0], ac.size[0xf0]);
        zeros -= 16;
      }
      const cat = category(v);
      const sym = (zeros << 4) | cat;
      put(ac.code[sym], ac.size[sym]);
      put(v < 0 ? v - 1 + (1 << cat) : v, cat);
      zeros = 0;
    }
    if (last < 63) put(ac.code[0], ac.size[0]);
    return coef[0];
  };
  let pY = 0;
  let pB = 0;
  let pR = 0;
  for (let my = 0; my < ph; my += 16) {
    for (let mx = 0; mx < pw; mx += 16) {
      pY = unit(Y, pw, mx, my, qy, TABLES.dcY, TABLES.acY, pY);
      pY = unit(Y, pw, mx + 8, my, qy, TABLES.dcY, TABLES.acY, pY);
      pY = unit(Y, pw, mx, my + 8, qy, TABLES.dcY, TABLES.acY, pY);
      pY = unit(Y, pw, mx + 8, my + 8, qy, TABLES.dcY, TABLES.acY, pY);
      pB = unit(Cb, cw, mx >> 1, my >> 1, qc, TABLES.dcC, TABLES.acC, pB);
      pR = unit(Cr, cw, mx >> 1, my >> 1, qc, TABLES.dcC, TABLES.acC, pR);
    }
  }
  // Fill the last byte with ones, then the end.
  if (bits > 0) put((1 << (8 - bits)) - 1, 8 - bits);
  word(0xffd9);
  return Buffer.from(out.buffer, 0, n);
}
