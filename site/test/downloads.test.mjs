// The home page's download figure (_downloads.py), which the build reads from
// the backend. It runs the Python module, so it needs python3 like the build.

import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const SITE = fileURLToPath(new URL('..', import.meta.url));

// Runs `code` with _downloads imported as d and returns what it prints as JSON.
function python(code, env = {}) {
  const script = `import json, _downloads as d\n${code}`;
  const out = execFileSync('python3', ['-c', script], { cwd: SITE, env: { ...process.env, ...env }, encoding: 'utf8' });
  return JSON.parse(out);
}

test('rounds down to the same steps as the backend, and shows nothing below 10,000', () => {
  const totals = [0, 9999, 10000, 24999, 25000, 60000, 100000, 260000, 999999, 1000000, 3000000];
  assert.deepEqual(python(`print(json.dumps([d.milestone(n) for n in ${JSON.stringify(totals)}]))`),
    [0, 0, 10000, 10000, 25000, 50000, 100000, 250000, 500000, 1000000, 2500000]);
});

test('writes a friendly line only from 10,000', () => {
  assert.deepEqual(python('print(json.dumps([d.downloads_note(0), d.downloads_note(9999)]))'), ['', '']);
  const line = python('print(json.dumps(d.downloads_note(25000)))');
  assert.match(line, /> 25,000\+ downloads<\/span>$/);
  assert.match(line, /<span class="sep" aria-hidden="true">&middot;<\/span>/);
});

test('reads the milestone from the backend and rounds it again', () => {
  const reply = (body) => `
import io, contextlib
@contextlib.contextmanager
def opener(request, timeout):
    yield io.BytesIO(${JSON.stringify(body)}.encode())
print(json.dumps(d.fetch_milestone(opener=opener)))`;
  assert.equal(python(reply('{"ok": true, "milestone": 50000, "at": 1}')), 50000);
  assert.equal(python(reply('{"ok": true, "milestone": 51234, "at": 1}')), 50000);
});

test('leaves the line out when the backend fails or answers oddly', () => {
  const failing = `
def opener(request, timeout):
    raise OSError("offline")
print(json.dumps(d.fetch_milestone(opener=opener)))`;
  assert.equal(python(failing), 0);
  const odd = (body) => `
import io, contextlib
@contextlib.contextmanager
def opener(request, timeout):
    yield io.BytesIO(${JSON.stringify(body)}.encode())
print(json.dumps(d.fetch_milestone(opener=opener)))`;
  for (const body of ['not json', '[]', '{"ok": false}', '{"milestone": "10000"}', '{"milestone": -1}', '{"milestone": true}']) {
    assert.equal(python(odd(body)), 0, body);
  }
});

test('TABBI_DOWNLOADS forces a preview value or turns the request off', () => {
  assert.equal(python('print(json.dumps(d.current_milestone()))', { TABBI_DOWNLOADS: '12345' }), 10000);
  assert.equal(python('print(json.dumps(d.current_milestone()))', { TABBI_DOWNLOADS: 'off' }), 0);
});
