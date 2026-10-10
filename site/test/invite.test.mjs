// The /add/<code> and /join/<code> Pages Functions. Run `python3 site/build.py`
// first: these read the generated _generated.mjs.

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { SITE_HEADERS } from '../_generated.mjs';
import { inviteCode, invitePage, inviteResponse, shownCode } from '../_invite.mjs';

const MAC = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';
const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';
const request = (path, userAgent = MAC) =>
  new Request(`https://tabbinotch.com${path}`, { headers: { 'User-Agent': userAgent } });

test('accepts friend and party codes the way the app normalizes them', () => {
  assert.equal(inviteCode('add', 'K7QW2MZD'), 'K7QW2MZD');
  assert.equal(inviteCode('add', 'k7qw-2mzd'), 'K7QW2MZD');
  assert.equal(inviteCode('join', 'ab3c9x'), 'AB3C9X');
});

test('refuses codes of the wrong length, alphabet or encoding', () => {
  assert.equal(inviteCode('add', 'AB3C9X'), null, 'a party code is not a friend code');
  assert.equal(inviteCode('join', 'K7QW2MZD'), null, 'a friend code is not a party code');
  assert.equal(inviteCode('add', 'K7QW2MZ0'), null, '0 is not in the alphabet');
  assert.equal(inviteCode('add', 'K7QW2MZI'), null, 'I is not in the alphabet');
  assert.equal(inviteCode('add', 'K7QW%322MZD'), null, 'percent-encoded');
  assert.equal(inviteCode('add', '<script>'), null);
  assert.equal(inviteCode('add', ''), null);
  assert.equal(inviteCode('party', 'K7QW2MZD'), null, 'unknown action');
});

test('shows a friend code in two halves and a party code whole', () => {
  assert.equal(shownCode('K7QW2MZD'), 'K7QW-2MZD');
  assert.equal(shownCode('AB3C9X'), 'AB3C9X');
});

test('an add page shows the code, links to Tabbi and hands off on a Mac', () => {
  const { status, html } = invitePage('add', 'k7qw-2mzd', MAC);
  assert.equal(status, 200);
  assert.ok(html.includes('<p class="invite-code">K7QW-2MZD</p>'));
  assert.ok(html.includes('href="tabbi://add/K7QW2MZD"'));
  assert.ok(html.includes('<meta http-equiv="refresh" content="0; url=tabbi://add/K7QW2MZD">'));
  assert.ok(html.includes('releases/latest/download/Tabbi.dmg'));
  assert.ok(html.includes('<meta name="robots" content="noindex">'));
  assert.ok(!/INVITECODE|INVITE-SHOWN|invite-refresh/.test(html), 'every placeholder is filled');
});

test('a join page links to the party', () => {
  const { status, html } = invitePage('join', 'AB3C9X', MAC);
  assert.equal(status, 200);
  assert.ok(html.includes('<p class="invite-code">AB3C9X</p>'));
  assert.ok(html.includes('href="tabbi://join/AB3C9X"'));
  assert.ok(html.includes('url=tabbi://join/AB3C9X'));
});

test('a phone gets the page without the refresh', () => {
  const { status, html } = invitePage('add', 'K7QW2MZD', IPHONE);
  assert.equal(status, 200);
  assert.ok(!html.includes('http-equiv="refresh"'));
  assert.ok(html.includes('href="tabbi://add/K7QW2MZD"'));
});

test('a bad code gets the friendly invalid page and nothing of the input', () => {
  const { status, html } = invitePage('add', '"><b>hi', MAC);
  assert.equal(status, 404);
  assert.ok(html.includes('This invite looks off'));
  assert.ok(!html.includes('<b>hi'));
  assert.ok(!html.includes('tabbi://'));
});

test('the response reads the raw path and carries every site header', async () => {
  const response = inviteResponse('add', request('/add/K7QW2MZD'));
  assert.equal(response.status, 200);
  for (const [name, value] of SITE_HEADERS) assert.equal(response.headers.get(name), value, name);
  assert.equal(response.headers.get('Content-Type'), 'text/html; charset=utf-8');
  assert.equal(response.headers.get('Vary'), 'User-Agent');
  assert.ok((await response.text()).includes('tabbi://add/K7QW2MZD'));

  const encoded = inviteResponse('add', request('/add/K7QW%322MZD'));
  assert.equal(encoded.status, 404);
});
