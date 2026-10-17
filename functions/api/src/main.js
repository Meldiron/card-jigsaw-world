// The one Appwrite Function the app calls (owner, 2026-10-17): every feature in one function, which
// stays warm with everyone's calls, instead of a function per feature that each start cold (4-7 s).
// docs/functions.md has which function serves which builds.
//
// Routes (the caller is x-appwrite-user-id, set by Appwrite; bodies are JSON):
//   POST /purchase/verify          purchase.js      a StoreKit transaction (was verify-purchase /verify)
//   POST /purchase/notifications   purchase.js      App Store Server Notifications V2 (Apple still sends
//                                                   them to verify-purchase; this route is for a later move)
//   POST /account/delete           account.js       Account > Delete account (was delete-account /delete)
//   POST /code/redeem              code.js          a pack code, on the web (was redeem-code /redeem)
//   POST /coop/<action>            coop/game.js     Play together: create, join, leave, remove, end, next
//                                                   (was coop-game /<action>)
//   POST /gift/send                gift/send.js     a friend gift (was send-gift /send)
//   POST /coop/cleanup             coop/cleanup.js  the hourly co-op cleanup on demand; only for a caller
//                                                   who is not a player (the owner's CLI, a server key)
//   GET  /health                   { ok, environment, maxPlayers, appleSignIn }
//
// A scheduled execution (trigger `schedule`: the function's hourly `0 * * * *`) runs the co-op cleanup,
// whatever its path (it was the coop-cleanup function). Appwrite sets x-appwrite-trigger itself.
//
// Every feature is its own module, loaded on its first call, so a cold start loads only what that
// call needs (the App Store library only for purchases). Each module answers its own failures as its
// old function did, so the app reads the same answers.
import { MAX_PLAYERS } from './coop/rules.js';

const purchase = () => import('./purchase.js');
const account = () => import('./account.js');
const code = () => import('./code.js');
const coop = () => import('./coop/game.js');
const cleanup = () => import('./coop/cleanup.js');
const gift = () => import('./gift/send.js');

/// The co-op actions (COOP_ACTIONS in coop/game.js, listed here so routing loads nothing).
const COOP = ['create', 'join', 'leave', 'remove', 'end', 'next'];

const ROUTES = {
  'POST /purchase/verify': async (c) => (await purchase()).verify(c),
  'POST /purchase/notifications': async (c) => (await purchase()).notifications(c),
  'POST /account/delete': async (c) => (await account()).deleteAccount(c),
  'POST /code/redeem': async (c) => (await code()).redeemCode(c),
  'POST /gift/send': async (c) => (await gift()).sendGift(c),
  ...Object.fromEntries(COOP.map((name) => [`POST /coop/${name}`, async (c) => (await coop()).coopAction(name, c)])),
  'POST /coop/cleanup': async (c) => {
    if (!(await notAPlayer(c.req))) return notFound(c);
    return (await cleanup()).coopCleanup(c);
  },
  'GET /health': async ({ res }) => {
    const [p, a] = await Promise.all([purchase(), account()]);
    return res.json({ ok: true, environment: p.environmentName(), maxPlayers: MAX_PLAYERS, appleSignIn: a.appleKeyState() });
  },
};

const notFound = ({ res }) => res.json({ ok: false, error: 'Not found' }, 404);

/// Whether the caller is not one of the game's players: no user (a server key) or a console user
/// (the owner's CLI, whose id Appwrite passes too but is no user of this project).
async function notAPlayer(req) {
  const userId = req.headers['x-appwrite-user-id'];
  if (!userId) return true;
  const { Client, Users } = await import('node-appwrite');
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(req.headers['x-appwrite-key'] ?? '');
  try {
    await new Users(client).get({ userId });
    return false;
  } catch (e) {
    if (e?.code === 404) return true;
    throw e;
  }
}

/// The route of a request: method and path without trailing slashes (`POST /coop/join`).
export function routeOf(req) {
  const path = (req.path || '/').replace(/\/+$/, '') || '/';
  return `${String(req.method || 'GET').toUpperCase()} ${path}`;
}

export default async (context) => {
  const { req, error } = context;
  try {
    if (req.headers?.['x-appwrite-trigger'] === 'schedule') return await (await cleanup()).coopCleanup(context);
    const handler = ROUTES[routeOf(req)];
    if (!handler) return notFound(context);
    return await handler(context);
  } catch (e) {
    error(`${routeOf(req)}: ${e?.stack ?? e}`);
    return context.res.json({ ok: false, error: 'Server error' }, 500);
  }
};
