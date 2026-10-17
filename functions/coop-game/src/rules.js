// The rules of a co-op game that need no database: join codes, board checks and seats. Kept apart
// from main.js so `node --test test/` can check them without Appwrite.

/// Most players in one game, the host included.
export const MAX_PLAYERS = 5;

// Unambiguous characters (no 0/O, 1/I/L), the pack codes' alphabet; 8 of them make about 8.5e11
// codes, and a game lives a day at most.
export const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
export const CODE_LENGTH = 8;

/// A new join code from [random] (a function giving bytes, `crypto.randomBytes` in the function).
export function newCode(random) {
  const bytes = random(CODE_LENGTH);
  let out = '';
  for (let i = 0; i < CODE_LENGTH; i++) out += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length];
  return out;
}

/// A code as typed or linked: upper case, alphabet characters only; null when it cannot be one.
export function normaliseCode(code) {
  const c = String(code ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  if (c.length !== CODE_LENGTH) return null;
  for (const ch of c) if (!CODE_ALPHABET.includes(ch)) return null;
  return c;
}

/// A board code in its path form (`cards-4x5t3`, `hexagons-5x6`, `4x4`), as the app's routes use.
export function validGrid(grid) {
  return typeof grid === 'string' && /^([a-z]{1,16}-)?\d{1,3}(x\d{1,3})?(t\d{1,2})?$/.test(grid);
}

/// The dealt layout as a list of card numbers: a permutation of 0..n-1 with 4 to 1000 cards (the
/// app checks it fits the board before it plays it); null when it is not one.
export function parseLayout(layout) {
  if (!Array.isArray(layout) || layout.length < 4 || layout.length > 1000) return null;
  const seen = new Array(layout.length).fill(false);
  const out = [];
  for (const v of layout) {
    const n = Number(v);
    if (!Number.isInteger(n) || n < 0 || n >= layout.length || seen[n]) return null;
    seen[n] = true;
    out.push(n);
  }
  return out;
}

/// The layout as the row stores it: card numbers separated by commas.
export const encodeLayout = (layout) => layout.join(',');

/// A membership's seat (its `seatN` role), or -1.
export function seatOf(membership) {
  for (const r of membership.roles || []) {
    const m = /^seat(\d)$/.exec(r);
    if (m) return Number(m[1]);
  }
  return -1;
}

/// The smallest seat no membership holds, or -1 when all are taken.
export function freeSeat(memberships) {
  const taken = new Set(memberships.map(seatOf));
  for (let s = 0; s < MAX_PLAYERS; s++) if (!taken.has(s)) return s;
  return -1;
}

/// Who sits where, decided the same way by every call that looks at the same memberships (two
/// players joining at the same moment may both have taken a seat, or a sixth player may have got
/// in): the earliest memberships (by creation, then id) are in, the rest are over the limit; a
/// seat held twice stays with the earlier member and the later one moves to the smallest free seat.
/// Returns the seats (`players`: user id per seat, '' when empty), the members whose seat changed
/// (`moves`: membership and new seat) and the members over the limit (`over`).
export function seating(memberships) {
  const ordered = [...memberships].sort((a, b) => (a.$createdAt < b.$createdAt ? -1 : a.$createdAt > b.$createdAt ? 1 : a.$id < b.$id ? -1 : 1));
  const players = new Array(MAX_PLAYERS).fill('');
  const moves = [];
  const over = [];
  const pending = [];
  for (const m of ordered) {
    if (players.filter((p) => p).length + pending.length >= MAX_PLAYERS) {
      over.push(m);
      continue;
    }
    const s = seatOf(m);
    if (s >= 0 && s < MAX_PLAYERS && !players[s]) players[s] = m.userId;
    else pending.push(m);
  }
  for (const m of pending) {
    const s = players.indexOf('');
    players[s] = m.userId;
    moves.push({ membership: m, seat: s });
  }
  return { players, moves, over };
}

/// The seats with [userId] taken out.
export const without = (players, userId) => players.map((p) => (p === userId ? '' : p));

/// Whether [players] still has a player besides the empty seats.
export const seated = (players) => players.filter((p) => p).length;
