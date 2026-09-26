import {expect, type Page, type TestInfo} from '@playwright/test';

export const publicRoutes = [
  ['Home', '/'],
  ['Pricing', '/pricing'],
  ['Intent hub', '/start'],
  ['Guide', '/guide'],
  ['Search', '/search'],
  ['Site map', '/sitemap'],
  ['Music jobs', '/music-jobs'],
  ['Music professionals', '/music-professionals'],
  ['Book music', '/book-music'],
  ['About', '/about'],
  ['Terms', '/terms'],
  ['Privacy', '/privacy'],
  ['Safety', '/safety'],
  ['Cookies', '/cookies'],
  ['Refund policy', '/refund-policy'],
  ['Community guidelines', '/community-guidelines'],
  ['Accessibility', '/accessibility'],
  ['Contact', '/contact'],
  ['Forgot password', '/forgot-password'],
  ['Professional authentication', '/auth/jobseeker'],
  ['Employer authentication', '/auth/employer'],
  ['Admin authentication', '/auth/admin'],
] as const;

export const accessibilityRoutes = [
  ['Home', '/'],
  ['Pricing', '/pricing'],
  ['Intent hub', '/start'],
  ['Music jobs', '/music-jobs'],
  ['Music professionals', '/music-professionals'],
  ['Book music', '/book-music'],
  ['Guide', '/guide'],
  ['Search', '/search'],
  ['Site map', '/sitemap'],
  ['About', '/about'],
  ['Terms', '/terms'],
  ['Privacy', '/privacy'],
  ['Refund policy', '/refund-policy'],
  ['Accessibility statement', '/accessibility'],
  ['Contact', '/contact'],
  ['Verify email', '/verify-email'],
  ['Forgot password', '/forgot-password'],
  ['Not found', '/this-page-does-not-exist'],
  ['Professional authentication', '/auth/jobseeker'],
  ['Employer authentication', '/auth/employer'],
] as const;

export function watchRuntimeFailures(page: Page) {
  const failures: string[] = [];
  const liveRun = Boolean(process.env.QA_BASE_URL);
  page.on('pageerror', error => failures.push(`pageerror: ${error.message}`));
  page.on('console', message => {
    // Local runs intentionally return 401 for /me so public pages exercise their
    // signed-out state without requiring a Rails service. Live runs stay strict.
    if (liveRun && message.type() === 'error') failures.push(`console: ${message.text()}`);
  });
  page.on('response', response => {
    if (response.status() >= 500) failures.push(`HTTP ${response.status()}: ${response.url()}`);
  });
  return failures;
}

export async function openSettledPage(page: Page, path: string) {
  if (!process.env.QA_BASE_URL && process.env.QA_INTEGRATION !== 'true') {
    await page.route('**/api/**', async route => {
      const pathname = new URL(route.request().url()).pathname;
      if (pathname.endsWith('/me')) {
        return route.fulfill({status: 401, contentType: 'application/json', body: JSON.stringify({error: 'Authentication required'})});
      }
      const fixtures: Record<string, unknown> = {
        '/api/jobs': {jobs: [], facets: {}},
        '/api/public/talent': {talent: []},
        '/api/public/acts': {acts: []},
        '/api/search': {results: [], interpretedAs: [], provider: 'qa-fixture'},
        '/api/billing/plans': {plans: []},
        '/api/taxonomy': {roleCategories: {}, genres: [], instruments: []},
      };
      const fixtureKey = Object.keys(fixtures).find(key => pathname === key);
      return route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(fixtureKey ? fixtures[fixtureKey] : {}),
      });
    });
  }
  const response = await page.goto(path, {waitUntil: 'domcontentloaded'});
  expect(response, `No document response for ${path}`).not.toBeNull();
  expect(response!.status(), `Document request failed for ${path}`).toBeLessThan(400);
  await expect(page.locator('body')).not.toContainText('Loading Verse…', {timeout: 12_000});
  await page.waitForTimeout(150);
}

export async function assertNoHorizontalOverflow(page: Page, testInfo: TestInfo) {
  const overflow = await page.evaluate(() => {
    const viewport = document.documentElement.clientWidth;
    const offenders = [...document.querySelectorAll<HTMLElement>('body *')]
      .filter(element => {
        const box = element.getBoundingClientRect();
        return box.right > viewport + 2 || box.left < -2;
      })
      .slice(0, 8)
      .map(element => ({
        tag: element.tagName.toLowerCase(),
        text: (element.textContent || '').trim().slice(0, 60),
        left: Math.round(element.getBoundingClientRect().left),
        right: Math.round(element.getBoundingClientRect().right),
      }));
    return {viewport, scrollWidth: document.documentElement.scrollWidth, offenders};
  });

  if (overflow.scrollWidth > overflow.viewport + 2) {
    await testInfo.attach('horizontal-overflow.json', {
      body: JSON.stringify(overflow, null, 2),
      contentType: 'application/json',
    });
  }
  expect(overflow.scrollWidth, JSON.stringify(overflow.offenders)).toBeLessThanOrEqual(overflow.viewport + 2);
}
