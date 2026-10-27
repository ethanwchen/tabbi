// GET /download (functions/download.js) and GET /appstore
// (functions/appstore.js). Run `python3 site/build.py` first: this reads the
// generated _generated.mjs.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { APP_STORE, DOWNLOADS } from '../_generated.mjs';
import { appStoreResponse, downloadResponse, platformOf } from '../_download.mjs';
import { onRequestGet as appStoreFunction } from '../functions/appstore.js';
import { onRequestGet as downloadFunction } from '../functions/download.js';

const WINDOWS = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36';
const MAC = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';
const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';
const request = (headers) => new Request('https://tabbinotch.com/download', { headers });

test('the links point at the latest release of each installer', () => {
  assert.match(DOWNLOADS.mac, /\/releases\/latest\/download\/Tabbi\.dmg$/);
  assert.match(DOWNLOADS.windows, /\/releases\/download\/windows-latest\/Tabbi-Setup\.exe$/);
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

test('Mac visitors to /download still get the direct download', () => {
  for (const headers of [{ 'User-Agent': MAC }, { 'Sec-CH-UA-Platform': '"macOS"' }, {}]) {
    const response = downloadFunction({ request: request(headers) });
    assert.equal(response.status, 302);
    assert.equal(response.headers.get('Location'), DOWNLOADS.mac);
  }
});

test('the App Store link is Tabbi\'s Mac App Store page', () => {
  assert.equal(APP_STORE, 'https://apps.apple.com/app/tabbi-notch-timer-study-pet/id6821088964');
});

test('/appstore redirects everyone to the App Store page', () => {
  for (const ua of [MAC, WINDOWS, IPHONE]) {
    const response = appStoreFunction({ request: new Request('https://tabbinotch.com/appstore', { headers: { 'User-Agent': ua } }) });
    assert.equal(response.status, 302);
    assert.equal(response.headers.get('Location'), APP_STORE);
  }
  assert.equal(appStoreResponse().headers.get('Location'), APP_STORE);
});

test('the home page offers both Mac editions, the badge first, and hides the badge on Windows', async () => {
  const { readFile } = await import('node:fs/promises');
  const html = await readFile(new URL('../dist/index.html', import.meta.url), 'utf8');
  const get = html.match(/<div class="cta get">(.*?)<\/div>/s)?.[1] ?? '';
  const badge = get.indexOf(`<a class="store-badge" href="${APP_STORE}" data-windows-hidden>`);
  const button = get.indexOf(`<a class="btn" href="${DOWNLOADS.mac}" data-windows-href="${DOWNLOADS.windows}">`);
  assert.ok(badge >= 0, 'the App Store badge links to the App Store page');
  assert.ok(button > badge, 'the direct download button follows the badge');
  assert.match(get, /alt="Download on the Mac App Store"/);
  assert.match(html, /<p class="editions" data-windows-hidden>/);
});
