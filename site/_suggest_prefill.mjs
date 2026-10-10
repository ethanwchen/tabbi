// Fills the Suggest form's hidden app facts from the page's query, on the
// server, because the site's CSP allows no script in the browser. Tabbi opens
// /suggest?version=&macos=&edition= (FeedbackLink in TabbiKitCore), and the
// form posts those fields to the friends backend's /v1/suggestions.

import { SITE_HEADERS, SUGGEST_APP_FACTS } from './_generated.mjs';

// The same rule the backend checks (APP_FACT_PATTERN in backend/src/suggestions.ts).
// None of these characters needs escaping inside a quoted HTML attribute.
export const APP_FACT_PATTERN = /^[A-Za-z0-9 ._()-]{1,32}$/;

/** `html` with each hidden app fact set from `params`; a missing or ill-formed value stays empty. */
export function prefill(html, params) {
  for (const name of SUGGEST_APP_FACTS) {
    const value = params.get(name);
    if (value === null || !APP_FACT_PATTERN.test(value)) continue;
    html = html.replace(
      `<input type="hidden" name="${name}" value="">`,
      `<input type="hidden" name="${name}" value="${value}">`,
    );
  }
  return html;
}

/**
 * The response for GET /suggest. Cloudflare Pages does not apply _headers to a
 * response a Function returns, so this sets them itself, CSP included.
 */
export async function suggestResponse(request, next) {
  const response = await next();
  const params = new URL(request.url).searchParams;
  const headers = new Headers(response.headers);
  for (const [name, value] of SITE_HEADERS) headers.set(name, value);
  let body = response.body;
  if (response.status === 200 && SUGGEST_APP_FACTS.some((name) => params.has(name))) {
    body = prefill(await response.text(), params);
    // The bytes changed, so the asset's validator and length no longer describe them.
    headers.delete('ETag');
    headers.delete('Content-Length');
  }
  return new Response(body, { status: response.status, statusText: response.statusText, headers });
}
