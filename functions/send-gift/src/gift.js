// What a friend gift is, without the server: the two gifts, the sender's day, the row id that
// keeps one gift per friend and day, the copy of the message and the push, and the name filter.
// No dependencies, so test/gift.test.mjs runs with plain `node --test`.
import { createHash } from 'node:crypto';

/// The gifts a player can send (owner, 2026-10-17): 1 ticket or 150 coins, free for the sender.
/// The amounts live here only; the app shows the same (FriendGifts in lib/state/friend_gifts.dart).
export const KINDS = {
  tickets: { amount: 1, column: 'rewardTickets', one: 'ticket', many: 'tickets' },
  coins: { amount: 150, column: 'rewardCoins', one: 'coin', many: 'coins' },
};

/// A gift leaves the friend's inbox 24 hours after it was sent.
export const LIFETIME_MS = 24 * 60 * 60 * 1000;

/// Appwrite user ids (and the friend codes, which are user ids).
export const USER_ID = /^[A-Za-z0-9][A-Za-z0-9._-]{0,35}$/;

/// The sender's offset from UTC in minutes, as the app sends it, kept to real time zones (UTC-12
/// to UTC+14) and whole quarter hours. Anything else counts as UTC.
export function clampOffset(minutes) {
  const n = Number(minutes);
  if (!Number.isFinite(n)) return 0;
  return Math.max(-720, Math.min(840, Math.round(n / 15) * 15));
}

/// The sender's calendar day ('2026-10-17') at [now] with [offset] minutes from UTC: the limit
/// is one gift per friend per day, and the day turns at the sender's own midnight.
export function giftDay(now, offset) {
  return new Date(now.getTime() + clampOffset(offset) * 60000).toISOString().slice(0, 10);
}

/// Row id of the gift [senderId] sent [recipientId] on [day]: creating it twice fails, so two
/// taps or two devices cannot send two gifts in a day. The app reads the same id to know whether
/// today's gift is sent (deterministicId(sender, '<recipient>:<day>') in lib/data/repositories.dart).
export function giftRowId(senderId, recipientId, day) {
  return createHash('md5').update(`${senderId}:${recipientId}:${day}`).digest('hex');
}

/// "1 ticket", "150 coins".
export function amountText(kind) {
  const k = KINDS[kind];
  return `${k.amount.toLocaleString('en-GB')} ${k.amount === 1 ? k.one : k.many}`;
}

/// The inbox message and the push for a gift from [name].
export function giftCopy(kind, name) {
  const what = amountText(kind);
  const one = KINDS[kind].amount === 1;
  return {
    subject: `${name} sent you a gift`,
    body: `${name} sent you ${what}. Claim ${one ? 'it' : 'them'} within 24 hours.`,
    pushTitle: `${name} sent you a gift`,
    pushBody: `${what} ${one ? 'is' : 'are'} waiting in your inbox.`,
  };
}

/// The app link that opens one message in Social > Inbox (AppLink.parse: `/inbox?message=<id>`).
export function messageLink(messageId) {
  return `/inbox?message=${messageId}`;
}

// --- Offensive names -------------------------------------------------------------------------
// A copy of NameFilter (lib/core/name_filter.dart): the push is drawn by iOS, not the app, so the
// sender's name is checked here before it goes into the message and the notification. Keep the
// lists in step with the Dart file; test/friend_gifts_test.dart compares them.

export const FALLBACK_NAME = 'Player';

const SYMBOLS = { '@': 'a', $: 's', '!': 'i', '|': 'i', '+': 't', '€': 'e' };
const FILLERS = new Set(['*', '.', '-', '_', "'"]);
const DIGITS = { 0: 'o', 1: 'i', 3: 'e', 4: 'a', 5: 's', 7: 't', 8: 'b', 9: 'g' };
const ACCENTS = {
  á: 'a', à: 'a', â: 'a', ä: 'a', ã: 'a', å: 'a', č: 'c', ç: 'c', ć: 'c', ď: 'd',
  é: 'e', è: 'e', ê: 'e', ë: 'e', ě: 'e', í: 'i', ì: 'i', î: 'i', ï: 'i', ľ: 'l',
  ĺ: 'l', ł: 'l', ň: 'n', ñ: 'n', ń: 'n', ó: 'o', ò: 'o', ô: 'o', ö: 'o', õ: 'o',
  ø: 'o', ŕ: 'r', ř: 'r', š: 's', ś: 's', ß: 'ss', ť: 't', ú: 'u', ù: 'u', û: 'u',
  ü: 'u', ů: 'u', ý: 'y', ÿ: 'y', ž: 'z', ź: 'z', ż: 'z',
};

/// Hate symbols written as numbers.
export const NUMBERS = ['1488', '14/88', '14 88'];

/// Offensive anywhere inside a word.
export const ROOTS = new Set([
  // English
  'fuck', 'fck', 'fvck', 'phuck', 'shit', 'cunt', 'nigg', 'faggot', 'whore', 'slut', 'bitch', 'bastard', 'asshole',
  'arsehole', 'dickhead', 'motherf', 'cocksuck', 'penis', 'vagina', 'dildo', 'porn', 'hitler',
  'retard', 'wanker', 'twat', 'jizz', 'blowjob', 'handjob', 'orgasm', 'pedophil', 'paedophil',
  'pedofil', 'molest', 'wetback', 'raghead', 'towelhead', 'kkk',
  // Slovak and Czech
  'kurva', 'kurvy', 'jebem', 'jebat', 'jebn', 'hovno', 'sracka', 'zmrd', 'kokot', 'skurvy',
  'chuj', 'buzerant',
  // German, Dutch, Polish
  'scheiss', 'fotze', 'hurensohn', 'wichser', 'arschloch', 'kurwa', 'pierdol', 'jebac', 'kanker',
  // Spanish, Portuguese, Italian, French
  'mierda', 'cabron', 'pendejo', 'maricon', 'caralho', 'buceta', 'cazzo', 'stronzo', 'vaffanculo',
  'puttana', 'putain', 'salope', 'connard', 'encule',
]);

/// Offensive as a whole word only (plurals included).
export const WORDS = new Set([
  // English
  'ass', 'arse', 'cock', 'dick', 'pussy', 'tits', 'titty', 'boob', 'cum', 'sex', 'sexy', 'anal',
  'anus', 'rape', 'raped', 'raping', 'rapist', 'nazi', 'heil', 'fag', 'dyke', 'tranny', 'homo',
  'coon', 'chink', 'gook', 'kike', 'spic', 'paki', 'spaz', 'crap', 'piss', 'pissed', 'xxx', 'milf',
  'horny', 'nude', 'boner', 'hoe', 'skank', 'prick', 'bollocks', 'incest', 'pedo', 'paedo', 'fuk',
  'niga', 'wank', 'idiot',
  // Slovak and Czech
  'pica', 'pice', 'picus', 'debil', 'cigan', 'kreten',
  // Spanish, Portuguese, Italian, French, Dutch
  'puta', 'puto', 'porra', 'pute', 'merde', 'batard', 'kut', 'culo', 'coglione',
]);

function fold(s) {
  let out = '';
  for (const c of s) out += ACCENTS[c] ?? c;
  return out;
}

/// The words of [lower], digits read as gaps ('split'), as letters ('leet') or left out ('drop');
/// single letters in a row (`f u c k`) are joined into one word.
function wordsOf(lower, digits) {
  let buffer = '';
  for (const c of lower) {
    if (digits === 'drop' && (FILLERS.has(c) || c in DIGITS || /[0-9]/.test(c))) continue;
    const mapped = SYMBOLS[c] ?? (digits === 'leet' ? DIGITS[c] : undefined) ?? c;
    buffer += /[a-z]/.test(mapped) ? mapped : ' ';
  }
  const parts = buffer.split(' ').filter((w) => w.length > 0);
  const words = [];
  let spelled = '';
  const flush = () => {
    if (spelled.length > 1) words.push(spelled);
    spelled = '';
  };
  for (const p of parts) {
    if (p.length === 1) {
      spelled += p;
    } else {
      flush();
      words.push(p);
    }
  }
  flush();
  return words;
}

const singular = (w) => (w.length > 4 && w.endsWith('es') ? w.slice(0, -2) : w.length > 3 && w.endsWith('s') ? w.slice(0, -1) : w);
const collapse = (w) => w.replace(/(.)\1+/g, '$1');

/// True when [name] contains an offensive word (the same reading as NameFilter.isOffensive).
export function isOffensive(name) {
  const lower = fold(String(name ?? '').toLowerCase());
  if (NUMBERS.some((n) => lower.includes(n))) return true;
  const words = new Set(['split', 'leet', 'drop'].flatMap((d) => wordsOf(lower, d)));
  for (const word of words) {
    for (const form of new Set([word, collapse(word)])) {
      if (WORDS.has(form) || WORDS.has(singular(form))) return true;
      for (const root of ROOTS) if (form.includes(root)) return true;
    }
  }
  return false;
}

/// The name to show: trimmed, at most 64 characters, "Player" when empty or offensive.
export function shownName(name) {
  const n = String(name ?? '').trim().slice(0, 64);
  return !n || isOffensive(n) ? FALLBACK_NAME : n;
}
