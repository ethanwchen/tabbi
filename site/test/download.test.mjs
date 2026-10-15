// GET /download (functions/download.js). Run `python3 site/build.py` first:
// this reads the generated _generated.mjs.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { DOWNLOADS } from '../_generated.mjs';
import { downloadResponse, platformOf } from '../_download.mjs';

const WINDOWS = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36';
const MAC = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';
const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';
const request = (headers) => new Request('https://tabbinotch.com/download', { headers });

test('the links point at the latest release of each installer', () => {
  assert.match(DOWNLOADS.mac, /\/releases\/latest\/download\/Tabbi\.dmg$/);
  assert.match(DOWNLOADS.windows, /\/releases\/latest\/download\/Tabbi-Setup\.exe$/);
});

test('Windows gets the Windows installer, everything else the Mac download', () => {
  assert.equal(platformOf(new Headers({ 'User-Agent': WINDOWS })), 'windows');
  assert.equal(platformOf(new Headers({ 'User-Agent': MAC })), 'mac');
  assert.equal(platformOf(new Headers({ 'User-Agent': IPHONE })), 'mac');
  assert.equal(platformOf(new Headers({})), 'mac');
});

test('the platform client hint wins over the user agent', () => {
  assert.equal(platformOf(new Headers({ 'Sec-CH-UA-Platform': '"Windows"', 'User-Agent': MAC })), 'windows');
  assert.equal(platformOf(new Headers({ 'Sec-CH-UA-Platform': '"macOS"', 'User-Agent': WINDOWS })), 'mac');
});

test('answers with an uncached redirect', () => {
  const response = downloadResponse(request({ 'User-Agent': WINDOWS }));
  assert.equal(response.status, 302);
  assert.equal(response.headers.get('Location'), DOWNLOADS.windows);
  assert.equal(response.headers.get('Cache-Control'), 'no-store');
  assert.match(response.headers.get('Vary'), /User-Agent/);
});
