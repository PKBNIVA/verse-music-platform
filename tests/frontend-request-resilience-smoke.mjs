import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { transform } from 'esbuild';

const source = await readFile(new URL('../src/app/lib/api.ts', import.meta.url), 'utf8');
const { code } = await transform(source, { loader: 'ts', format: 'esm', target: 'es2022' });

const storage = new Map();
globalThis.sessionStorage = {
  getItem: (key) => storage.get(key) ?? null,
  setItem: (key, value) => storage.set(key, String(value)),
  removeItem: (key) => storage.delete(key),
};

const redirects = [];
globalThis.window = {
  setTimeout,
  clearTimeout,
  location: {
    pathname: '/employer/messages',
    search: '?thread=42',
    replace: (path) => redirects.push(path),
  },
};

const apiModule = await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
const { apiDelete, apiGet, apiPost, ApiError, setAccessToken, uploadMedia } = apiModule;

// GET requests get one bounded retry for transient network failures.
let calls = 0;
globalThis.fetch = async () => {
  calls += 1;
  if (calls === 1) throw new TypeError('offline');
  return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { 'content-type': 'application/json' } });
};
assert.deepEqual(await apiGet('/health'), { ok: true });
assert.equal(calls, 2);

// Mutations are never retried because replaying them can duplicate side effects.
calls = 0;
globalThis.fetch = async () => {
  calls += 1;
  throw new TypeError('offline');
};
await assert.rejects(apiPost('/bookings', { actId: 1 }), (error) => error instanceof ApiError && error.code === 'NETWORK_ERROR');
assert.equal(calls, 1);

// Empty successful responses are valid and must not fail JSON parsing.
globalThis.fetch = async () => new Response(null, { status: 204 });
assert.equal(await apiDelete('/saved-jobs/1'), undefined);

// Correlation IDs are preserved for support and incident diagnosis.
globalThis.fetch = async () => new Response(JSON.stringify({ error: 'Unavailable' }), {
  status: 503,
  headers: { 'content-type': 'application/json', 'x-request-id': 'req-test-123' },
});
await assert.rejects(apiGet('/jobs'), (error) => error instanceof ApiError && error.requestId === 'req-test-123');

// A 401 clears the stale session and redirects protected pages only once.
setAccessToken('expired-token');
globalThis.fetch = async () => new Response(JSON.stringify({ error: 'Unauthorized' }), {
  status: 401,
  headers: { 'content-type': 'application/json' },
});
await assert.rejects(apiGet('/me'), (error) => error instanceof ApiError && error.status === 401);
assert.equal(sessionStorage.getItem('verse_access_token'), null);
assert.equal(sessionStorage.getItem('verse_return_to'), '/employer/messages?thread=42');
assert.deepEqual(redirects, ['/auth/employer']);

// Caller cancellation remains cancellation and is not retried or mislabeled as a timeout.
calls = 0;
const caller = new AbortController();
caller.abort(new DOMException('Cancelled', 'AbortError'));
globalThis.fetch = async (_url, options) => {
  calls += 1;
  if (options.signal.aborted) throw options.signal.reason;
};
await assert.rejects(apiGet('/jobs', { signal: caller.signal }), (error) => error.name === 'AbortError');
assert.equal(calls, 1);

// Local fallback uploads include a sanitized filename for safe server-side storage.
let uploadHeaders;
globalThis.fetch = async (url, options) => {
  if (String(url).endsWith('/uploads/presign')) {
    return new Response(JSON.stringify({ mode: 'local', uploadUrl: '/api/uploads/local' }), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  }
  uploadHeaders = new Headers(options.headers);
  return new Response(JSON.stringify({ url: '/uploads/demo.mp3' }), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });
};
const file = new File(['audio'], 'demo song?.mp3', { type: 'audio/mpeg' });
assert.equal((await uploadMedia(file)).url, '/uploads/demo.mp3');
assert.equal(uploadHeaders.get('x-filename'), 'demo_song_.mp3');

console.log('frontend request resilience smoke: ok');
