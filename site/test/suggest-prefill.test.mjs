// The /suggest Pages Function. Run `python3 site/build.py` first: these read
// the built page and the generated _generated.mjs.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { SITE_HEADERS } from '../_generated.mjs';
import { prefill, suggestResponse } from '../_suggest_prefill.mjs';

const page = readFileSync(new URL('../dist/suggest.html', import.meta.url), 'utf8');
const hidden = (name, value = '') => `<input type="hidden" name="${name}" value="${value}">`;
const asset = (status = 200) => async () =>
  new Response(status === 200 ? page : null, { status, headers: { ETag: '"abc"', 'Content-Type': 'text/html' } });

test('the built form has an empty hidden field for each app fact', () => {
  for (const name of ['version', 'macos', 'edition']) assert.ok(page.includes(hidden(name)), name);
});

test('fills the app facts Tabbi passes and nothing else', () => {
  const params = new URLSearchParams({ version: '1.4.0 (212)', macos: '15.5', edition: 'tabbi', message: 'hi' });
  const html = prefill(page, params);
  assert.ok(html.includes(hidden('version', '1.4.0 (212)')));
  assert.ok(html.includes(hidden('macos', '15.5')));
  assert.ok(html.includes(hidden('edition', 'tabbi')));
  assert.equal(html.replace(/ value="[^"]*"/g, ''), page.replace(/ value="[^"]*"/g, ''));
});

test('leaves a missing, empty, overlong or unsafe value empty', () => {
  const params = new URLSearchParams({
    version: '"><script>alert(1)</script>',
    macos: 'x'.repeat(33),
    edition: '',
  });
  assert.equal(prefill(page, params), page);
  assert.equal(prefill(page, new URLSearchParams()), page);
});

test('the response carries every site header and the filled page', async () => {
  const request = new Request('https://tabbinotch.com/suggest?version=1.4.0&macos=15.5&edition=tabbi');
  const response = await suggestResponse(request, asset());
  assert.equal(response.status, 200);
  for (const [name, value] of SITE_HEADERS) assert.equal(response.headers.get(name), value, name);
  assert.equal(response.headers.get('ETag'), null);
  assert.ok((await response.text()).includes(hidden('version', '1.4.0')));
});

test('without app facts the page passes through unchanged, headers added', async () => {
  const response = await suggestResponse(new Request('https://tabbinotch.com/suggest'), asset());
  assert.equal(response.headers.get('ETag'), '"abc"');
  assert.ok(response.headers.get('Content-Security-Policy').startsWith("default-src 'none'"));
  assert.equal(await response.text(), page);
});

test('a not-modified answer stays one', async () => {
  const response = await suggestResponse(new Request('https://tabbinotch.com/suggest?version=1.4.0'), asset(304));
  assert.equal(response.status, 304);
  assert.equal(response.headers.get('X-Frame-Options'), 'DENY');
});
