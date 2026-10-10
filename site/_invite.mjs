// Serves the Party invite pages, /add/<friend code> and /join/<party code>
// (PartyInvite in TabbiKitCore), on the server, because the site's CSP allows
// no script in the browser. build.py writes the pages and the code rules
// into _generated.mjs; its --serve preview answers the same way
// (invite_page in build.py).

import { INVITE, SITE_HEADERS } from './_generated.mjs';

const PHONES = new RegExp(INVITE.phones);

/**
 * The normalized code in `raw` for `action` ('add' or 'join'), or null.
 * Like PartyCode: upper-cased and dashes dropped, then it must have the
 * action's length and use only the code alphabet. A percent-encoded code is
 * not one Tabbi hands out, so it is refused rather than decoded.
 */
export function inviteCode(action, raw) {
  const length = INVITE.lengths[action];
  if (length === undefined || typeof raw !== 'string' || raw.includes('%')) return null;
  const code = raw.toUpperCase().replaceAll('-', '');
  if (code.length !== length || [...code].some((c) => !INVITE.alphabet.includes(c))) return null;
  return code;
}

/** The code the way the app shows it: a friend code in two halves, a party code whole. */
export function shownCode(code) {
  if (code.length <= 6) return code;
  const half = code.length / 2;
  return `${code.slice(0, half)}-${code.slice(half)}`;
}

/** { status, html } for /<action>/<raw>, asked by a browser with `userAgent`. */
export function invitePage(action, raw, userAgent = '') {
  const code = inviteCode(action, raw);
  if (code === null) return { status: 404, html: INVITE.pages.invalid };
  const { placeholders } = INVITE;
  // Phones cannot run Tabbi, and Safari there would answer the refresh with an error.
  const refresh = PHONES.test(userAgent)
    ? ''
    : `\n  <meta http-equiv="refresh" content="0; url=tabbi://${action}/${code}">`;
  const html = INVITE.pages[action]
    .replace(placeholders.refresh, refresh)
    .replaceAll(placeholders.shown, shownCode(code))
    .replaceAll(placeholders.code, code);
  return { status: 200, html };
}

/**
 * The response for GET /<action>/<code>. The code is read from the raw
 * path, still percent-encoded, so an encoded one is refused. Cloudflare Pages does not apply
 * _headers to a response a Function returns, so this sets them itself, CSP
 * included. The page depends on the browser (the refresh), so caches keep
 * one per user agent.
 */
export function inviteResponse(action, request) {
  const raw = new URL(request.url).pathname.split('/')[2] ?? '';
  const { status, html } = invitePage(action, raw, request.headers.get('User-Agent') ?? '');
  const headers = new Headers(SITE_HEADERS);
  headers.set('Content-Type', 'text/html; charset=utf-8');
  headers.set('Cache-Control', 'no-cache');
  headers.set('Vary', 'User-Agent');
  headers.set('X-Robots-Tag', 'noindex');
  return new Response(html, { status, headers });
}
