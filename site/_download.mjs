// The installer for a visitor's computer, for GET /download
// (functions/download.js), and Tabbi's Mac App Store page, for GET /appstore
// (functions/appstore.js). build.py's download_for follows the same rule for
// `--serve`, and writes the links into _generated.mjs, so the header's
// Download, the home page's button and badge and these redirects cannot
// disagree. Mac visitors to /download keep getting the direct download:
// older links and the Party invite pages rely on it (Party is not in the App
// Store edition).

import { APP_STORE, DOWNLOADS } from './_generated.mjs';

/** 'windows' or 'mac': the platform client hint when sent, else the user agent. */
export function platformOf(headers) {
  const hint = headers.get('Sec-CH-UA-Platform');
  if (hint) return /windows/i.test(hint) ? 'windows' : 'mac';
  return /Windows NT/.test(headers.get('User-Agent') ?? '') ? 'windows' : 'mac';
}

/** A redirect to the right installer. It depends on the request, so nothing caches it. */
export function downloadResponse(request) {
  return new Response(null, {
    status: 302,
    headers: {
      Location: DOWNLOADS[platformOf(request.headers)],
      'Cache-Control': 'no-store',
      Vary: 'Sec-CH-UA-Platform, User-Agent',
    },
  });
}

/** A redirect to Tabbi's Mac App Store page, the same for everyone. Temporary,
    so the short link can move if the App Store page ever does. */
export function appStoreResponse() {
  return new Response(null, {
    status: 302,
    headers: { Location: APP_STORE, 'Cache-Control': 'public, max-age=3600' },
  });
}
