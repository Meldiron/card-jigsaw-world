// Image proxy for the web build. Some picture hosts (Cleveland Museum of Art,
// NASA) send no Access-Control-Allow-Origin header, so browsers refuse to
// decode their images for the canvas. This function fetches the image and
// returns it with CORS and cache headers. Only allow-listed hosts are served.
//
//   GET https://cjw-img.fra.appwrite.run/?u=https://openaccess-cdn.clevelandart.org/...
const ALLOWED_HOSTS = new Set([
  'openaccess-cdn.clevelandart.org',
  'images-assets.nasa.gov',
  'cdn.stocksnap.io',
]);
const MAX_BYTES = 8 * 1024 * 1024;

export default async ({ req, res, log, error }) => {
  const cors = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
    'Access-Control-Allow-Headers': '*',
    'Access-Control-Max-Age': '86400',
  };
  if (req.method === 'OPTIONS') return res.text('', 204, cors);
  // Appwrite hands the query value through undecoded, so decode it ourselves.
  let raw = req.query?.u || '';
  if (!/^https?:\/\//.test(raw)) { try { raw = decodeURIComponent(raw); } catch { /* keep raw */ } }
  let target;
  try { target = new URL(raw); } catch { return res.json({ error: 'Missing or invalid u' }, 400, cors); }
  if (target.protocol !== 'https:' || !ALLOWED_HOSTS.has(target.hostname)) {
    return res.json({ error: 'Host not allowed' }, 403, cors);
  }
  try {
    const upstream = await fetch(target, { headers: { 'User-Agent': 'CardJigsawWorld/1.0 (+image proxy)' }, redirect: 'follow' });
    if (!upstream.ok) return res.json({ error: `Upstream ${upstream.status}` }, 502, cors);
    const type = upstream.headers.get('content-type') || 'application/octet-stream';
    if (!type.startsWith('image/')) return res.json({ error: 'Not an image' }, 502, cors);
    const buf = Buffer.from(await upstream.arrayBuffer());
    if (buf.length > MAX_BYTES) return res.json({ error: 'Too large' }, 502, cors);
    return res.binary(buf, 200, {
      ...cors,
      'Content-Type': type,
      'Cache-Control': 'public, max-age=2592000, immutable',
      'X-Proxied-From': target.hostname,
    });
  } catch (e) {
    error(`proxy failed for ${target.href}: ${e}`);
    return res.json({ error: 'Fetch failed' }, 502, cors);
  }
};
