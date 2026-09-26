import {expect, test} from '@playwright/test';

const apiBase = process.env.QA_API_BASE_URL?.replace(/\/$/, '');
const latencyBudgetMs = Number(process.env.QA_API_HEALTH_BUDGET_MS || 2_000);
const webBase = process.env.QA_BASE_URL?.replace(/\/$/, '');
// /api/health reports the first 12 characters of the deployed commit.
const expectedRelease = process.env.QA_EXPECTED_RELEASE?.trim().slice(0, 12);
// Railway/Vercel may still be building when a run is dispatched right after a merge.
const releaseWaitMs = Number(process.env.QA_RELEASE_WAIT_MS || 5 * 60_000);

test.describe('live API health and latency', () => {
  test.skip(!apiBase, 'Set QA_API_BASE_URL to enable non-destructive live API probes.');

  test('health endpoint is consistently healthy and within its warm latency budget', async ({request}) => {
    await request.get(`${apiBase}/health`); // Do not count a potential cold start in the warm budget.
    const timings: number[] = [];

    for (let attempt = 0; attempt < 5; attempt += 1) {
      const startedAt = Date.now();
      const response = await request.get(`${apiBase}/health`);
      timings.push(Date.now() - startedAt);
      expect(response.status()).toBe(200);
      expect(await response.json()).toMatchObject({ok: true, service: 'verse-rails'});
    }

    timings.sort((a, b) => a - b);
    const p95 = timings[Math.ceil(timings.length * 0.95) - 1];
    expect(p95, `Warm health timings: ${timings.join(', ')}ms`).toBeLessThanOrEqual(latencyBudgetMs);
  });

  // Deploy verification: a manually dispatched live run sets QA_EXPECTED_RELEASE to the
  // commit it was started from, and waits for Railway (and Vercel) to serve that commit.
  test('the deployed API and web app serve the expected release', async ({request}) => {
    test.skip(!expectedRelease, 'Set QA_EXPECTED_RELEASE (a commit SHA) to verify the deployed release.');
    test.setTimeout(releaseWaitMs + 60_000);

    await expect.poll(async () => {
      const response = await request.get(`${apiBase}/health`, {failOnStatusCode: false, timeout: 15_000}).catch(() => null);
      return response?.ok() ? String((await response.json().catch(() => ({})))?.release || '') : '';
    }, {message: 'API /health release', timeout: releaseWaitMs, intervals: [5_000, 15_000]}).toBe(expectedRelease);

    if (!webBase) return;
    await expect.poll(async () => {
      const response = await request.get(`${webBase}/`, {failOnStatusCode: false, timeout: 15_000}).catch(() => null);
      const html = response?.ok() ? await response.text() : '';
      return (html.match(/<meta\s+name="verse-release"\s+content="([^"]*)"/i)?.[1] || '').slice(0, 12);
    }, {message: 'web <meta name="verse-release"> release', timeout: releaseWaitMs, intervals: [5_000, 15_000]}).toBe(expectedRelease);
  });

  test('public readiness reports status without exposing deployment configuration', async ({request}) => {
    const response = await request.get(`${apiBase}/readiness`);
    expect([200, 503]).toContain(response.status());
    const body = await response.json();
    expect(body).toMatchObject({service: 'verse-rails'});
    expect(body).not.toHaveProperty('environment');
    expect(body).not.toHaveProperty('checks');
    expect(JSON.stringify(body)).not.toMatch(/secret|password|access[_-]?key|provider/i);
  });
});
