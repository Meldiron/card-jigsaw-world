// Which requests are the invite page's (page.js), decided without loading it: the router asks on
// every call, so this module imports nothing heavy.
import { normaliseCode } from '../coop/rules.js';

/// The invites' own address (a domain of this function).
export const JOIN_HOST = 'join.carden.page';

/// The join code in a path: `/<code>` or `/join/<code>` (any case, dashes ignored); null otherwise.
export function codeOfPath(path) {
  const m = /^\/(?:join\/)?([A-Za-z0-9-]{8,12})\/?$/.exec(String(path ?? ''));
  return m ? normaliseCode(m[1]) : null;
}

/// Whether [req] is for the invite page: a GET or HEAD on the invites' domain, an invite's path or
/// the association file.
export function isInviteRequest(req) {
  const method = String(req.method || 'GET').toUpperCase();
  if (method !== 'GET' && method !== 'HEAD') return false;
  const host = String(req.host ?? req.headers?.host ?? '').toLowerCase().split(':')[0];
  if (host === JOIN_HOST) return true;
  const path = String(req.path || '/');
  return path === '/.well-known/apple-app-site-association' || codeOfPath(path) !== null;
}
