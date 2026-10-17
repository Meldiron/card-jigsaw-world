// What the integrity sweep (run.js) checks, without a database: one verdict per row, profile, file
// and name. Kept apart so test/sweep.test.mjs checks the rules on plain objects.
//
// Why (security review, 2026-10-17): players write their own rows, and Appwrite lets a client grant
// only roles it holds. The app gives some rows a predictable id, md5("<owner>:<key>"), so another
// player can create a row at that id first: the owner's later write is refused (401) and their read
// finds nothing (404). Such a row names the wrong player in its permissions, or carries an id that is
// not its owner's. Rows with other ids (`ID.unique()`, 20 characters: rows the app makes when its
// predictable id is taken, older rows) are checked by their permissions only.
import { createHash } from 'node:crypto';
import { isRefused, FALLBACK_NAME } from '../gift/gift.js';

export const HOUR = 60 * 60 * 1000;

/// Most photos one player keeps (My Puzzles): "no limit with VIP" in the app, and far above any real
/// use; past it the newest photos go (an upload loop, not a player).
export const FILES_PER_PLAYER = 500;

/// Tables whose rows a player writes for themself: the column naming the owner, the key the app
/// builds the row id from (md5 of "<owner>:<key>"), and a copied player name to keep clean.
export const OWNED = {
  progress: { owner: 'userId', key: 'puzzleId' },
  event_progress: { owner: 'userId', key: 'eventId' },
  friends: { owner: 'userId', key: 'friendId', name: 'friendName' },
  blocks: { owner: 'blockerId', key: 'blockedId', name: 'blockedName' },
};

export const md5 = (s) => createHash('md5').update(s).digest('hex');

/// The user ids a list of permissions names (`read("user:abc")`, `update("user:abc/verified")`).
export function usersIn(permissions) {
  const out = new Set();
  for (const p of permissions || []) for (const m of String(p).matchAll(/user:([A-Za-z0-9._-]+)/g)) out.add(m[1]);
  return [...out];
}

const sameSet = (a, b) => a.length === b.length && [...a].sort().join('\n') === [...b].sort().join('\n');

/// Why a row of an [OWNED] table must go, or null when it is its owner's: `permissions` (the owner
/// cannot write it, or another player is named), `id` (a predictable id that is not the owner's).
export function rowVerdict(spec, row) {
  const owner = String(row[spec.owner] ?? '');
  const perms = row.$permissions || [];
  if (!owner || !perms.includes(`update("user:${owner}")`) || usersIn(perms).some((u) => u !== owner)) return 'permissions';
  if (/^[0-9a-f]{32}$/.test(row.$id) && row.$id !== md5(`${owner}:${row[spec.key] ?? ''}`)) return 'id';
  return null;
}

/// The permissions the app gives a profile (lib/data/sync/backend.dart, createProfile).
export const profilePermissions = (id) => ['read("any")', `update("user:${id}")`, `delete("user:${id}")`];

/// What to do with a profile row: `delete` (no such user, an hour after it was made; or another
/// player named in its permissions), `repair` (only its owner named, but not the app's permissions),
/// or null. QA players' rows (`isTest`) are made by tools with other permissions: they are only
/// deleted, as above, never repaired (tools/dev/purge_test_players.py removes them).
export function profileVerdict(row, userExists, now) {
  const perms = row.$permissions || [];
  if (!userExists) return now - Date.parse(row.$createdAt) > HOUR ? { action: 'delete', why: 'no-user' } : null;
  if (usersIn(perms).some((u) => u !== row.$id)) return { action: 'delete', why: 'permissions' };
  if (row.isTest !== true && !sameSet(perms, profilePermissions(row.$id))) return { action: 'repair', permissions: profilePermissions(row.$id) };
  return null;
}

/// The permissions the app gives a photo (UploadRepository.upload).
export const uploadPermissions = (owner) => [`read("user:${owner}")`, `delete("user:${owner}")`];

/// What to do with a file of `user-uploads`, given the players whose My Puzzles rows point at it:
/// `delete` (no row of a player it belongs to, an hour after the upload), `repair` (its owner's
/// photo, but readable or changeable by someone else), or null.
export function fileVerdict(file, rowOwners, now) {
  const perms = file.$permissions || [];
  const named = usersIn(perms);
  const owner = named.find((u) => rowOwners.has(u)) ?? (named.length === 0 && rowOwners.size === 1 ? [...rowOwners][0] : undefined);
  if (!owner) return now - Date.parse(file.$createdAt) > HOUR ? { action: 'delete', why: 'no-row' } : null;
  const want = uploadPermissions(owner);
  if (!sameSet(perms, want)) return { action: 'repair', owner, permissions: want };
  return null;
}

/// Whether a stored player name must be reset to "Player": offensive, a link, an @handle or a
/// domain (NameFilter.isRefused in the app, which shows such names as "Player" already).
export const nameVerdict = (name) => typeof name === 'string' && name !== FALLBACK_NAME && name.trim() !== '' && isRefused(name);
