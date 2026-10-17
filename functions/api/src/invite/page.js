// join.carden.page, a domain of this function: the page of a Play together invite
// (https://join.carden.page/<code>, docs/multiplayer.md, "Invite links").
//
// Messages, WhatsApp, Messenger and the rest read an invite's preview from the page's static meta
// tags (no script runs), so the page is made here, per invite: "Mia invites you to play Red Panda",
// "Play together in Carden · Cards 7x7 · 2 of 5 players" and the invite card (card.js, kept in
// Storage by store.js). The same page serves people: there is no redirect and no user-agent test, so
// a crawler and a person read the same thing. On an iPhone or iPad it offers Open in Carden
// (carden://join/<code>, which every build with Play together reads) and Play in the browser; where
// the app is installed with this domain in its associated domains (build 127 and later), iOS opens
// the app straight from the link and this page is never asked for.
//
// Only what the inviter shares shows: their display name (through the name filter), the picture and
// the board; never a player id. An ended or unknown game shows the site's own card and says so.
import { Query } from 'node-appwrite';
import { MAX_PLAYERS } from '../coop/rules.js';
import { shownName, FALLBACK_NAME } from '../gift/gift.js';
import { services, ensureCard } from './store.js';
import { MODES, parseGrid, sizeLabel, tilingOf } from './tiling.js';
import { JOIN_HOST, codeOfPath } from './paths.js';

export { JOIN_HOST, codeOfPath, isInviteRequest } from './paths.js';
export const JOIN_ORIGIN = `https://${JOIN_HOST}`;
export const SITE = 'https://play.carden.page';
const DB = process.env.APPWRITE_DATABASE_ID || 'cjw';

/// Where people get the app (AppLinks.getCarden in lib/core/links.dart, GET_CARDEN in web/index.html).
export const GET_CARDEN = 'https://testflight.apple.com/join/7nPCfg6A';

/// The site's own card (web/invite-card.jpg): ended and unknown games.
const SITE_CARD = `${SITE}/invite-card.jpg`;

/// Universal links for this domain (the app's `applinks:join.carden.page`, build 127 and later): an
/// invite opens the app; the root and anything else stay in the browser.
export const ASSOCIATION = {
  applinks: {
    details: [
      {
        appIDs: ['C24QP73SQM.com.matejbaco.cardjigsawworld'],
        components: [
          { '/': '/', exclude: true, comment: 'the root goes to the web game' },
          { '/': '/????????', comment: 'Play together invites: join.carden.page/<code>' },
          { '/': '/join/*', comment: 'Play together invites, the long form' },
        ],
      },
    ],
  },
};

const escape = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

/// The words of an invite: title (og:title), the line under it (og:description) and the card's
/// alternative text. [hostName]: the profile's display name; [title]: the picture's.
export function inviteCopy({ hostName, title, grid, painting, players }) {
  const name = shownName(hostName);
  const who = name === FALLBACK_NAME ? null : name;
  const picture = String(title ?? '').trim();
  const what = !picture || picture === 'Untitled' ? 'a picture' : picture;
  const board = parseGrid(grid) ?? { mode: 'cards', cols: 4, rows: 4 };
  const boardText = `${MODES[board.mode].label} ${sizeLabel(board)}${painting ? ' · Painting' : ''}`;
  const seated = Math.max(1, Math.min(MAX_PLAYERS, players));
  const cells = tilingOf(board).playableCells;
  return {
    title: who ? `${who} invites you to play ${what}` : what === 'a picture' ? 'Play a picture together' : `Play ${what} together`,
    description: `Play together in Carden · ${boardText} · ${seated} of ${MAX_PLAYERS} players`,
    board: boardText,
    players: `${seated} of ${MAX_PLAYERS} players`,
    alt: `${what === 'a picture' ? 'A picture' : what} as a board of ${cells} ${board.mode === 'cards' ? 'cards' : 'pieces'}, beside the name Carden`,
  };
}

const GENERIC = {
  title: 'Carden: Your calm picture puzzle',
  description: 'Swap cards until the picture is whole, on your own or together. A new puzzle every day.',
  alt: 'A red panda dealt as nine cards, one lifted, beside the name Carden',
};

/// The page. [game]: null for an ended or unknown invite.
export function renderPage({ code, game, copy, image }) {
  const live = !!game;
  const url = `${JOIN_ORIGIN}/${code}`;
  const meta = live ? { title: copy.title, description: copy.description, alt: copy.alt, image } : { ...GENERIC, image: SITE_CARD };
  const heading = live ? copy.title : 'This game has ended';
  const line = live ? `${copy.board} · ${copy.players}` : '';
  const text = live ? 'Open it in the Carden app, or play it here in the browser.' : 'Ask for a new invite, or play a picture on your own.';
  const app = live ? `carden://join/${code}` : 'carden://home';
  const web = live ? `${SITE}/join/${code}?play=1` : `${SITE}/`;
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="light dark">
<meta name="theme-color" content="#2F4FBF">
<meta name="robots" content="noindex">
<meta name="referrer" content="strict-origin">
<title>${escape(meta.title)}</title>
<meta name="description" content="${escape(meta.description)}">
<meta property="og:title" content="${escape(meta.title)}">
<meta property="og:description" content="${escape(meta.description)}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Carden">
<meta property="og:url" content="${escape(url)}">
<meta property="og:image" content="${escape(meta.image)}">
<meta property="og:image:secure_url" content="${escape(meta.image)}">
<meta property="og:image:type" content="image/jpeg">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="${escape(meta.alt)}">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" type="image/png" href="${SITE}/favicon.png">
<link rel="apple-touch-icon" href="${SITE}/icons/apple-touch-icon.png">
<style>
:root { --canvas: #F6F6F8; --ink: #111118; --ink-secondary: #5F5F6E; --accent: #2F4FBF; --button: #2F4FBF; --soft: rgba(127, 127, 140, 0.14); }
@media (prefers-color-scheme: dark) { :root { --canvas: #0D0D11; --ink: #F2F2F5; --ink-secondary: #A6A6B4; --accent: #7C9AFF; --button: #4065DD; } }
* { box-sizing: border-box; }
html, body { margin: 0; min-height: 100%; background: var(--canvas); color: var(--ink); font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; -webkit-font-smoothing: antialiased; }
main { min-height: 100vh; min-height: 100dvh; display: flex; align-items: center; justify-content: center; padding: 24px 16px; }
.card { width: 100%; max-width: 420px; display: flex; flex-direction: column; align-items: center; text-align: center; gap: 12px; }
.preview { width: 100%; aspect-ratio: 1200 / 630; border-radius: 16px; overflow: hidden; background: #1C1C22; box-shadow: 0 1px 0 rgba(16, 16, 32, 0.06), 0 10px 28px rgba(16, 16, 32, 0.16); margin-bottom: 8px; }
.preview img { display: block; width: 100%; height: 100%; object-fit: cover; }
.logo { width: 84px; height: 84px; border-radius: 20px; box-shadow: 0 1px 0 rgba(16, 16, 32, 0.06), 0 8px 24px rgba(16, 16, 32, 0.08); margin-bottom: 8px; }
h1 { margin: 0; font-family: ui-rounded, "SF Pro Rounded", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; font-size: 24px; line-height: 1.25; font-weight: 700; letter-spacing: -0.3px; }
.line { margin: 0; font-size: 15px; font-weight: 600; color: var(--ink-secondary); }
p.text { margin: 0 0 12px; font-size: 15px; line-height: 1.4; color: var(--ink-secondary); }
a.button, button { width: 100%; height: 52px; display: flex; align-items: center; justify-content: center; border-radius: 12px; border: 0; font: inherit; font-size: 16px; font-weight: 600; text-decoration: none; cursor: pointer; }
.primary { background: var(--button); color: #FFFFFF; }
.secondary { background: var(--soft); color: var(--ink); }
[hidden] { display: none !important; }
</style>
</head>
<body>
<main>
<div class="card">
${live ? `<div class="preview"><img src="${escape(meta.image)}" alt="${escape(meta.alt)}" width="1200" height="630"></div>` : `<img class="logo" src="${SITE}/icons/Icon-192.png" alt="" width="84" height="84">`}
<h1 id="title">${escape(heading)}</h1>
${line ? `<p class="line">${escape(line)}</p>` : ''}
<p class="text" id="text">${escape(text)}</p>
<a class="button primary" id="app" href="${escape(app)}">Open in Carden</a>
<a class="button secondary" id="web" href="${escape(web)}">Play in the browser</a>
<a class="button secondary" id="get" href="${GET_CARDEN}" hidden>Get Carden</a>
</div>
</main>
<script>
(function () {
  // On an iPhone or iPad: Open in Carden first; if this page is still on screen a moment after the
  // try, the app is not there, and the browser comes first, then Get Carden. Elsewhere: the browser.
  var apple = /iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  var app = document.getElementById('app');
  var web = document.getElementById('web');
  var get = document.getElementById('get');
  function browserFirst(text) {
    if (text) document.getElementById('text').textContent = text;
    app.hidden = true;
    web.className = 'button primary';
    app.parentNode.insertBefore(web, app);
  }
  if (!apple) return browserFirst(${JSON.stringify(live ? 'Swap cards together until the picture is whole, right here in the browser.' : 'Play a picture on your own, right here in the browser.')});
  var tried = false;
  app.addEventListener('click', function (e) {
    if (tried) return;
    e.preventDefault();
    tried = true;
    var left = false;
    function away() { left = true; }
    document.addEventListener('visibilitychange', function () { if (document.hidden) away(); });
    window.addEventListener('pagehide', away);
    location.href = app.href;
    // iOS asks "Open in Carden?" first; give it time before deciding the app is not there.
    setTimeout(function () {
      if (left || document.hidden) return;
      browserFirst(${JSON.stringify(live ? 'If Carden did not open, play right here in the browser, or get the app and open the link again.' : 'If Carden did not open, play right here in the browser, or get the app.')});
      get.hidden = false;
    }, 2500);
  });
})();
</script>
</body>
</html>
`;
}

/// GET on this module's paths (see isInviteRequest).
export async function serve({ req, res, log, error }) {
  const path = String(req.path || '/');
  // Appwrite's edge keeps an answer as long as `s-maxage` says (measured: the second request is a
  // cache hit and never reaches the function), so a friend who taps the link after the preview was
  // read gets the page at once, cold or not. Ten minutes: the player count may be that old. An
  // answer made while something failed is not kept.
  const KEEP = 'public, max-age=60, s-maxage=600';
  const html = (body, cache = KEEP) => res.text(body, 200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': cache, 'x-robots-tag': 'noindex' });
  if (path === '/.well-known/apple-app-site-association' || path === '/apple-app-site-association') {
    return res.text(JSON.stringify(ASSOCIATION), 200, { 'content-type': 'application/json', 'cache-control': 'public, max-age=3600' });
  }
  if (path === '/robots.txt') return res.text('User-agent: *\nAllow: /\n', 200, { 'content-type': 'text/plain; charset=utf-8' });
  const code = codeOfPath(path);
  if (!code) return res.redirect(`${SITE}/`, 302);

  const t = Date.now();
  const s = services(req);
  let game = null;
  try {
    game = (await s.tables.listRows({ databaseId: DB, tableId: 'coop_games', queries: [Query.equal('code', [code]), Query.limit(1)], total: false })).rows[0] ?? null;
  } catch (e) {
    error(`invite page: ${e?.message ?? e}`);
    return html(renderPage({ code, game: null }), 'no-store');
  }
  if (!game || game.status !== 'playing') return html(renderPage({ code, game: null }));

  const [puzzle, host] = await Promise.all([
    s.tables.getRow({ databaseId: DB, tableId: 'puzzles', rowId: game.puzzleId }).catch(() => null),
    s.tables.getRow({ databaseId: DB, tableId: 'profiles', rowId: game.hostId, queries: [Query.select(['displayName'])] }).catch(() => null),
  ]);
  const read = Date.now() - t;
  let image = null;
  try {
    // A crawler waits for the card at most a few seconds; the site's own card stands in after that.
    let timer;
    const late = new Promise((_, no) => {
      timer = setTimeout(() => no(new Error('card took too long')), 8000);
    });
    const card = await Promise.race([ensureCard(s, game, puzzle), late]).finally(() => clearTimeout(timer));
    image = card.url;
    if (card.made) log(`invite card ${card.id} drawn for the page: ${card.ms} ms`);
  } catch (e) {
    error(`invite card: ${e?.message ?? e}`);
  }
  const copy = inviteCopy({
    hostName: host?.displayName,
    title: puzzle?.title,
    grid: game.grid,
    painting: game.painting === true,
    players: (game.players || []).filter((p) => p).length,
  });
  log(`invite page: ${Date.now() - t} ms (rows ${read} ms)`);
  // Without its card (still drawing, or failed) the page shows the site's card and is not kept.
  return html(renderPage({ code, game, copy, image: image ?? SITE_CARD }), image && puzzle ? KEEP : 'no-store');
}
