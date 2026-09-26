import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { transform } from 'esbuild';

const source = await readFile(new URL('../src/app/lib/api.ts', import.meta.url), 'utf8');
const { code: transformed } = await transform(source, { loader: 'ts', format: 'esm', target: 'es2022' });
// The module is imported from a data: URL, so its relative import of the (DSN-less, inert)
// error-reporting module must be made absolute.
const monitoringUrl = new URL('../src/app/lib/monitoring.ts', import.meta.url).href;
const code = transformed.replace(/from "\.\/monitoring"/, `from ${JSON.stringify(monitoringUrl)}`);
assert.notEqual(code, transformed, 'api.ts imports ./monitoring');

const fakeStorage = () => {
  const storage = new Map();
  return {
    getItem: (key) => storage.get(key) ?? null,
    setItem: (key, value) => storage.set(key, String(value)),
    removeItem: (key) => storage.delete(key),
  };
};
globalThis.sessionStorage = fakeStorage();
globalThis.localStorage = fakeStorage();
// A token saved by an older build lives in this tab's sessionStorage.
sessionStorage.setItem('verse_access_token', 'legacy-token');

const redirects = [];
const listeners = new Map();
globalThis.window = {
  setTimeout,
  clearTimeout,
  addEventListener: (type, handler) => listeners.set(type, handler),
  removeEventListener: (type) => listeners.delete(type),
  location: {
    pathname: '/employer/messages',
    search: '?thread=42',
    replace: (path) => redirects.push(path),
  },
};

const apiModule = await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
const { apiDelete, apiGet, apiPost, ApiError, hasAccessToken, onAccessTokenChange, setAccessToken, uploadMedia } = apiModule;

// The legacy per-tab token is migrated to localStorage on first read so the session survives new tabs.
assert.equal(hasAccessToken(), true);
assert.equal(localStorage.getItem('verse_access_token'), 'legacy-token');
assert.equal(sessionStorage.getItem('verse_access_token'), null);
setAccessToken(null);
assert.equal(hasAccessToken(), false);
setAccessToken('stored-token');
assert.equal(localStorage.getItem('verse_access_token'), 'stored-token');
assert.equal(hasAccessToken(), true);

// Sign-in and sign-out in another tab reach this tab through the storage event.
const changes = [];
const unsubscribe = onAccessTokenChange((signedIn) => changes.push(signedIn));
const storageEvent = listeners.get('storage');
localStorage.removeItem('verse_access_token');
storageEvent({ key: 'verse_access_token', newValue: null, storageArea: localStorage });
storageEvent({ key: 'unrelated', newValue: 'x', storageArea: localStorage });
storageEvent({ key: 'verse_access_token', newValue: 'other', storageArea: sessionStorage });
localStorage.setItem('verse_access_token', 'other-tab-token');
storageEvent({ key: 'verse_access_token', newValue: 'other-tab-token', storageArea: localStorage });
storageEvent({ key: null, newValue: null, storageArea: localStorage });
assert.deepEqual(changes, [false, true, false]);
unsubscribe();
assert.equal(listeners.has('storage'), false);
setAccessToken(null);

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

// A GET has one total deadline across all attempts and a deadline abort is never retried.
calls = 0;
globalThis.fetch = async (_url, options) => {
  calls += 1;
  return new Promise((_resolve, reject) => {
    options.signal.addEventListener('abort', () => reject(options.signal.reason), { once: true });
  });
};
await assert.rejects(
  apiGet('/slow', { timeoutMs: 20 }),
  (error) => error instanceof ApiError && error.code === 'REQUEST_TIMEOUT',
);
assert.equal(calls, 1);

// A transient failure is not retried when the remaining total budget cannot fund another attempt.
calls = 0;
globalThis.fetch = async () => {
  calls += 1;
  throw new TypeError('offline');
};
await assert.rejects(
  apiGet('/budget-exhausted', { timeoutMs: 100 }),
  (error) => error instanceof ApiError && error.code === 'NETWORK_ERROR',
);
assert.equal(calls, 1);

// A retryable response is returned promptly when its retry delay would exceed the total budget.
calls = 0;
globalThis.fetch = async () => {
  calls += 1;
  return new Response(JSON.stringify({ error: 'Busy' }), {
    status: 503,
    headers: { 'content-type': 'application/json', 'retry-after': '2' },
  });
};
await assert.rejects(
  apiGet('/busy', { timeoutMs: 100 }),
  (error) => error instanceof ApiError && error.status === 503,
);
assert.equal(calls, 1);

// Correlation IDs are preserved for support and incident diagnosis.
globalThis.fetch = async () => new Response(JSON.stringify({ error: 'Unavailable' }), {
  status: 503,
  headers: { 'content-type': 'application/json', 'x-request-id': 'req-test-123' },
});
await assert.rejects(apiGet('/jobs'), (error) => error instanceof ApiError && error.requestId === 'req-test-123');

// A 401 for a token another tab has already replaced must not sign that newer session out.
setAccessToken('old-token');
globalThis.fetch = async () => {
  localStorage.setItem('verse_access_token', 'new-token-from-other-tab');
  return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401, headers: { 'content-type': 'application/json' } });
};
await assert.rejects(apiGet('/jobs'), (error) => error instanceof ApiError && error.status === 401);
assert.equal(localStorage.getItem('verse_access_token'), 'new-token-from-other-tab');
assert.deepEqual(redirects, []);

// A 401 clears the stale session and redirects protected pages only once.
setAccessToken('expired-token');
globalThis.fetch = async () => new Response(JSON.stringify({ error: 'Unauthorized' }), {
  status: 401,
  headers: { 'content-type': 'application/json' },
});
await assert.rejects(apiGet('/me'), (error) => error instanceof ApiError && error.status === 401);
assert.equal(localStorage.getItem('verse_access_token'), null);
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

// File bodies go through XMLHttpRequest (upload progress events); a minimal fake records requests.
const xhrRequests = [];
let xhrRespond = () => ({ status: 201, body: { url: '/uploads/demo.mp3' } });
globalThis.XMLHttpRequest = class {
  constructor() { this.headers = {}; this.upload = {}; this.responseHeaders = { 'content-type': 'application/json' }; }
  open(method, url) { this.method = method; this.url = url; }
  setRequestHeader(name, value) { this.headers[name.toLowerCase()] = value; }
  getResponseHeader(name) { return this.responseHeaders[name.toLowerCase()] ?? null; }
  abort() { this.onabort?.(); }
  send(body) {
    this.body = body;
    xhrRequests.push(this);
    queueMicrotask(() => {
      this.upload.onprogress?.({ lengthComputable: true, loaded: 1, total: 2 });
      const { status, body: response } = xhrRespond(this);
      this.status = status;
      this.responseText = JSON.stringify(response);
      this.onload?.();
    });
  }
};

// Local fallback uploads include a sanitized filename for safe server-side storage.
const fetchCalls = [];
globalThis.fetch = async (url, options) => {
  fetchCalls.push([String(url), options.method]);
  if (String(url).endsWith('/uploads/presign')) {
    return new Response(JSON.stringify({ mode: 'proxied', uploadUrl: '/api/uploads/local' }), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  }
  return new Response('{}', { status: 200, headers: { 'content-type': 'application/json' } });
};
const file = new File(['audio'], 'demo song?.mp3', { type: 'audio/mpeg' });
const progress = [];
assert.equal((await uploadMedia(file, (pct) => progress.push(pct))).url, '/uploads/demo.mp3');
const uploadHeaders = xhrRequests.at(-1).headers;
assert.equal(xhrRequests.at(-1).method, 'PUT');
assert.equal(uploadHeaders['x-filename'], 'demo_song_.mp3');
assert.equal(uploadHeaders['content-type'], 'audio/mpeg');
assert.deepEqual(progress, [0, 50, 100]);

// Server rejection of the streamed body surfaces the server's message and code.
xhrRespond = () => ({ status: 422, body: { error: 'File contents do not match the declared type.', code: 'UPLOAD_REJECTED' } });
await assert.rejects(uploadMedia(file), (error) => error instanceof ApiError && error.code === 'UPLOAD_REJECTED' && /do not match/.test(error.message));

// Unsupported files are refused before any request.
fetchCalls.length = 0;
await assert.rejects(uploadMedia(new File(['<svg/>'], 'x.svg', { type: 'image/svg+xml' })), (error) => error.code === 'UNSUPPORTED_TYPE');
assert.equal(fetchCalls.length, 0);

// Direct mode: POST policy form (fields first, file last) to the bucket, then server verification.
globalThis.fetch = async (url, options) => {
  fetchCalls.push([String(url), options.method]);
  const body = String(url).endsWith('/uploads/presign')
    ? { mode: 'direct', id: 'upl_1', method: 'POST', uploadUrl: 'https://bucket.example.test', fields: { key: 'uploads/u/k/demo.mp3', policy: 'p' }, headers: {} }
    : { url: 'https://media.example.test/uploads/u/k/demo.mp3', upload: { id: 'upl_1', contentType: 'audio/mpeg', byteSize: 5 } };
  return new Response(JSON.stringify(body), { status: 200, headers: { 'content-type': 'application/json' } });
};
xhrRespond = () => ({ status: 201, body: {} });
const direct = await uploadMedia(file);
assert.equal(direct.url, 'https://media.example.test/uploads/u/k/demo.mp3');
assert.equal(direct.id, 'upl_1');
assert.equal(xhrRequests.at(-1).method, 'POST');
assert.deepEqual([...xhrRequests.at(-1).body.keys()], ['key', 'policy', 'file']);
assert.ok(fetchCalls.some(([url, method]) => url.endsWith('/uploads/upl_1/complete') && method === 'POST'));

// Blocked site data: every storage access throws, but the session still works in memory.
const blocked = { getItem() { throw new Error('blocked'); }, setItem() { throw new Error('blocked'); }, removeItem() { throw new Error('blocked'); } };
globalThis.localStorage = blocked;
globalThis.sessionStorage = blocked;
const blockedModule = await import(`data:text/javascript;base64,${Buffer.from(`${code}\n// blocked storage`).toString('base64')}`);
assert.equal(blockedModule.hasAccessToken(), false);
blockedModule.setAccessToken('memory-token');
assert.equal(blockedModule.hasAccessToken(), true);
blockedModule.setAccessToken(null);
assert.equal(blockedModule.hasAccessToken(), false);

// Storage that reads but cannot write (full or read-only) must not hide the in-memory token.
const readOnly = { getItem: () => null, setItem() { throw new Error('quota'); }, removeItem() {} };
globalThis.localStorage = readOnly;
globalThis.sessionStorage = readOnly;
const readOnlyModule = await import(`data:text/javascript;base64,${Buffer.from(`${code}\n// read-only storage`).toString('base64')}`);
readOnlyModule.setAccessToken('memory-token');
assert.equal(readOnlyModule.hasAccessToken(), true);

console.log('frontend request resilience smoke: ok');
