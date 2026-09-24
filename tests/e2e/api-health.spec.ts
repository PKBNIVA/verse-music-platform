import {expect, test} from '@playwright/test';

const apiBase = process.env.QA_API_BASE_URL?.replace(/\/$/, '');
const latencyBudgetMs = Number(process.env.QA_API_HEALTH_BUDGET_MS || 2_000);

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
