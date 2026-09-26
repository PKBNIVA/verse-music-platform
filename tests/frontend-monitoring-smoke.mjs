import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// Node 22 strips TypeScript types natively; both modules are dependency-free at import time.
const scrub = await import('../src/app/lib/sentryScrub.ts');
const monitoring = await import('../src/app/lib/monitoring.ts');

// --- Scrubbing ------------------------------------------------------------------------
const token = 'vat_4f9a8b7c6d5e4f3a2b1c';
const text = scrub.scrubString(
  `Crash for jane.doe@example.com at https://verse.test/reset-password?token=abc123&step=2 ` +
  `/verify-email?token=v1 /unsubscribe?token=u1 Authorization: Bearer ${token} raw ${token}`,
  [token],
);
assert.doesNotMatch(text, /jane\.doe|abc123|token=v1|token=u1|vat_4f9a/, text);
assert.match(text, /\[email\]/);
assert.equal(scrub.scrubString('keys %7Bqa.crash%40example.invalid%2C'), 'keys [email]%2C', 'URL-encoded emails are scrubbed');
assert.match(text, /\?token=\[Filtered\]&step=2/);

const event = scrub.scrubEvent({
  message: 'failed for a@b.io',
  user: { id: 7, role: 'admin', email: 'a@b.io', ip_address: '1.2.3.4' },
  request: { url: 'https://verse.test/verify-email?token=secret-link', headers: { Referer: 'https://verse.test/unsubscribe?token=zz', Authorization: 'Bearer x' }, cookies: { a: 'b' } },
  extra: { verse_access_token: token, nested: [{ note: `token ${token}` }] },
  breadcrumbs: [{ category: 'navigation', data: { to: '/reset-password?token=r1' } }],
  exception: { values: [{ type: 'Error', value: 'Objects are not valid as a React child (found: object with keys {jane@example.com})' }] },
}, [token]);
const serialized = JSON.stringify(event);
assert.doesNotMatch(serialized, /a@b\.io|1\.2\.3\.4|secret-link|token=zz|token=r1|jane@example|vat_4f9a|Bearer x/, serialized);
assert.deepEqual(event.user, { id: 7, role: 'admin' });
assert.equal(event.request.cookies, undefined);
assert.equal(event.extra.verse_access_token, '[Filtered]');

// --- Classification and rate limiting ----------------------------------------------------
const apiError = (status, code) => Object.assign(new Error('x'), { name: 'ApiError', status, code });
assert.equal(monitoring.classifyError(apiError(404)).action, 'ignore');
assert.equal(monitoring.classifyError(apiError(422, 'VALIDATION_FAILED')).action, 'ignore');
assert.equal(monitoring.classifyError(apiError(401)).action, 'ignore');
assert.equal(monitoring.classifyError(Object.assign(new Error('x'), { name: 'AbortError' })).action, 'ignore');
assert.deepEqual(monitoring.classifyError(apiError(503)), { action: 'sample', key: 'api:503' });
assert.deepEqual(monitoring.classifyError(apiError(0, 'NETWORK_ERROR')), { action: 'sample', key: 'api:NETWORK_ERROR' });
assert.equal(monitoring.classifyError(new TypeError('boom')).action, 'report');

const now = 1_000_000;
assert.equal(monitoring.allowSampled('api:503', now), true);
assert.equal(monitoring.allowSampled('api:503', now + 1_000), false, 'a burst of the same failure is sent once');
assert.equal(monitoring.allowSampled('api:503', now + 6 * 60_000), true, 'the same failure is sent again after the window');
for (let i = 0; i < 10; i += 1) monitoring.allowSampled(`api:${500 + i}`, now);
assert.equal(monitoring.allowSampled('api:599', now + 10 * 60_000), false, 'a page session sends only a handful of sampled failures');

// Without a DSN everything is inert and Sentry is never requested.
assert.equal(monitoring.monitoringEnabled(), false);
monitoring.reportError(new Error('ignored'));
monitoring.reportApiFailure({ status: 503, method: 'GET', path: '/jobs' });
assert.equal(await monitoring.whenMonitoringReady(), false);
assert.equal(await monitoring.sendClientTestError(), null);

// --- Wiring --------------------------------------------------------------------------------
const main = await readFile(new URL('../src/main.tsx', import.meta.url), 'utf8');
const monitoringSource = await readFile(new URL('../src/app/lib/monitoring.ts', import.meta.url), 'utf8');
const clientSource = await readFile(new URL('../src/app/lib/sentryClient.ts', import.meta.url), 'utf8');
assert.match(main, /initMonitoring\(\)/, 'main.tsx starts monitoring');
assert.doesNotMatch(main, /@sentry/, 'Sentry must not be imported eagerly by the entry point');
assert.match(monitoringSource, /import\('\.\/sentryClient'\)/, 'Sentry is loaded with a dynamic import');
assert.match(clientSource, /sendDefaultPii:\s*false/);
assert.match(clientSource, /replaysSessionSampleRate:\s*0/);
assert.match(clientSource, /replaysOnErrorSampleRate:\s*0/);

console.log('frontend monitoring smoke: ok');
