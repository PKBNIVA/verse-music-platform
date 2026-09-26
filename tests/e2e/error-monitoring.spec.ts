import {randomUUID} from 'node:crypto';
import {expect, test, type APIRequestContext, type Browser, type Page} from '@playwright/test';

// Client error reporting. The default preview build has no DSN. A second preview build
// (playwright.config.ts, QA_SENTRY_BASE_URL) has a DSN pointing at a local sink
// (tests/e2e/support/sentry-sink.mjs), so nothing ever reaches a real Sentry.
test.skip(Boolean(process.env.QA_BASE_URL) || process.env.QA_INTEGRATION === 'true', 'Uses local builds and API fixtures only.');

const sentryBaseUrl = (process.env.QA_SENTRY_BASE_URL || 'http://127.0.0.1:4174').replace(/\/$/, '');
const sinkUrl = (process.env.QA_SENTRY_SINK_URL || 'http://127.0.0.1:4175').replace(/\/$/, '');
const token = 'qa-secret-token-5b7f1c2d9e';
const email = 'qa.crash@example.invalid';

const job = {
  id: 'job-1', company: 'Verse Studio', location: 'Mumbai', kind: 'Contract', genre: 'Film',
  description: 'Record guitar parts.', requirements: [], skills: [], status: 'published', applicants: 0,
  createdAt: '2026-09-01T00:00:00Z',
  // Rendering an object as a React child throws; its keys land in the error message, so the
  // report must prove the email and token were scrubbed from it.
  title: {[email]: 1, [token]: 2},
};

// The app's /api calls only; the sink's /api/<project>/envelope/ must pass through untouched.
const isAppApi = (url: URL) => url.pathname.startsWith('/api/') && !url.pathname.endsWith('/envelope/');

async function signInWithCrashingJob(page: Page) {
  await page.addInitScript(value => localStorage.setItem('verse_access_token', value), token);
  await page.route(isAppApi, route => {
    const pathname = new URL(route.request().url()).pathname;
    if (pathname.endsWith('/me')) {
      return route.fulfill({status: 200, contentType: 'application/json', body: JSON.stringify({user: {id: 'qa-js', name: 'QA', email, role: 'jobseeker', status: 'active', profileComplete: true}})});
    }
    const body = pathname.endsWith('/jobs/job-1') ? {job} : pathname.endsWith('/notifications/unread') ? {unread: 0} : {};
    return route.fulfill({status: 200, contentType: 'application/json', body: JSON.stringify(body)});
  });
}

function trackSentryTraffic(page: Page) {
  const requests: string[] = [];
  page.on('request', request => {
    const url = request.url();
    if (/sentry/i.test(new URL(url).hostname) || /sentryClient|sentryTracing|\/envelope\//.test(url)) requests.push(url);
  });
  return requests;
}

/**
 * A page whose user agent carries a unique run id. Sentry sends the user agent (but, with
 * sendDefaultPii off, not the query string), so the sink's envelopes can be matched per test.
 */
async function runPage(browser: Browser) {
  const runId = `qa_run_${randomUUID().replaceAll('-', '')}`;
  const context = await browser.newContext({userAgent: `Mozilla/5.0 VerseQA/${runId}`});
  return {runId, page: await context.newPage()};
}

/** Event envelopes recorded by the sink for this test run. */
async function eventsFor(request: APIRequestContext, runId: string) {
  const all: string[] = await (await request.get(`${sinkUrl}/__envelopes`)).json();
  return all.filter(body => body.includes(runId) && body.includes('"type":"event"'));
}

test('without a DSN Sentry is never downloaded or contacted, even when a route crashes', async ({page}) => {
  const sentryTraffic = trackSentryTraffic(page);
  await signInWithCrashingJob(page);
  await page.goto('/jobseeker/jobs/job-1');
  await expect(page.getByRole('heading', {name: 'This screen missed a beat.'})).toBeVisible();
  await page.goto('/');
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(2_500); // longer than the idle-load delay a DSN build would use
  expect(sentryTraffic).toEqual([]);
  expect(await page.locator('meta[name="verse-release"]').getAttribute('content')).toBeTruthy();
});

test('with a DSN a crashing route is reported, without the access token or email', async ({browser, request}) => {
  const {runId, page} = await runPage(browser);
  const publicSentry: string[] = [];
  page.on('request', r => { if (/sentry\.io/i.test(r.url())) publicSentry.push(r.url()); });
  await signInWithCrashingJob(page);

  await page.goto(`${sentryBaseUrl}/jobseeker/jobs/job-1?token=url-secret-77&email=${encodeURIComponent(email)}`);
  await expect(page.getByRole('heading', {name: 'This screen missed a beat.'})).toBeVisible();

  await expect.poll(async () => (await eventsFor(request, runId)).length, {timeout: 15_000}).toBeGreaterThanOrEqual(1);
  const events = (await eventsFor(request, runId)).join('\n');
  expect(events).not.toContain(token);
  expect(events).not.toContain(email);
  expect(events).not.toContain('url-secret-77');
  expect(events).not.toContain(encodeURIComponent(email));
  expect(events).toMatch(/Objects are not valid as a React child|React error #31/);
  expect(events).toContain('route_error');
  expect(events).toContain('[email]');
  expect(events).toContain('qa-sentry-build'); // release
  expect(publicSentry).toEqual([]);
  await page.context().close();
});

test('with a DSN expected API errors are not reported and repeated 5xx failures are sent sparingly', async ({browser, request}) => {
  const {runId, page} = await runPage(browser);
  let jobCalls = 0;
  await page.route(isAppApi, route => {
    const pathname = new URL(route.request().url()).pathname;
    if (pathname.endsWith('/me')) return route.fulfill({status: 401, contentType: 'application/json', body: '{"error":"Authentication required"}'});
    if (pathname === '/api/jobs') {
      jobCalls += 1;
      return route.fulfill({status: 503, contentType: 'application/json', body: '{"error":"Service is not ready.","code":"NOT_READY"}'});
    }
    return route.fulfill({status: 404, contentType: 'application/json', body: '{"error":"Not found"}'});
  });

  await page.goto(`${sentryBaseUrl}/music-jobs`);
  await expect.poll(() => jobCalls).toBeGreaterThanOrEqual(2); // the GET is retried once
  await expect.poll(async () => (await eventsFor(request, runId)).length, {timeout: 15_000}).toBeGreaterThanOrEqual(1);
  // Trigger the same failure again within the page session: it must not be sent again.
  const before = jobCalls;
  await page.getByRole('button', {name: 'Try again'}).first().click();
  await expect.poll(() => jobCalls).toBeGreaterThan(before);
  await page.getByRole('button', {name: 'Try again'}).first().click();
  await page.waitForTimeout(2_500);
  const events = await eventsFor(request, runId);
  const apiEvents = events.filter(body => body.includes('failed (503)'));
  expect(apiEvents.length, `jobs requests: ${before} then ${jobCalls}`).toBe(1);
  expect(events.join('\n')).not.toMatch(/\(404\)|\(401\)|Authentication required/);
  await page.context().close();
});
