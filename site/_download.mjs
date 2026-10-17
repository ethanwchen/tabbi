// The installer for a visitor's computer, for GET /download
// (functions/download.js). build.py's download_for follows the same rule for
// `--serve`, and writes the two links into _generated.mjs, so the header's
// Download, the home page's button and this redirect cannot disagree.

import { DOWNLOADS } from './_generated.mjs';

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
