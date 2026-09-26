import {devices, expect, test, type Page} from '@playwright/test';

test.skip(Boolean(process.env.QA_BASE_URL) || process.env.QA_INTEGRATION === 'true', 'Uses local API fixtures only.');

async function mockApi(page: Page, overrides: Record<string, {status?: number; contentType: string; body: string}> = {}) {
  await page.route('**/api/**', route => {
    const pathname = new URL(route.request().url()).pathname;
    const override = overrides[pathname];
    if (override) return route.fulfill({status: override.status ?? 200, contentType: override.contentType, body: override.body});
    if (pathname.endsWith('/me')) return route.fulfill({status: 401, json: {error: 'Authentication required'}});
    return route.fulfill({status: 200, json: {jobs: [], talent: [], acts: [], results: [], plans: []}});
  });
}

test.describe('phone public navigation', () => {
  test.use({viewport: devices['Pixel 7'].viewport, isMobile: true, hasTouch: true});

  test('visitors on a phone can reach both sign-in pages from the menu', async ({page}) => {
    await mockApi(page);
    await page.goto('/music-jobs');
    await page.getByRole('button', {name: 'Open navigation'}).click();
    await expect(page.getByRole('menuitem', {name: 'Sign in as a professional'})).toHaveAttribute('href', '/auth/jobseeker');
    await expect(page.getByRole('menuitem', {name: 'Sign in as an employer'})).toHaveAttribute('href', '/auth/employer');
  });
});

for (const path of ['/', '/music-jobs']) test(`the first Tab stop on ${path} skips navigation to the main content`, async ({page}) => {
  await mockApi(page);
  await page.goto(path);
  await expect(page.locator('main')).toBeVisible();
  await page.keyboard.press('Tab');
  const skip = page.getByRole('link', {name: 'Skip to main content'});
  await expect(skip).toBeFocused();
  await expect(skip).toBeVisible();
  await page.keyboard.press('Enter');
  await expect(page.locator('main')).toBeFocused();
});

test('an HTML page returned instead of API data shows an error, not an empty list', async ({page}) => {
  await mockApi(page, {'/api/jobs': {contentType: 'text/html', body: '<!doctype html><html><body>app shell</body></html>'}});
  await page.goto('/music-jobs');
  await expect(page.getByText(/unexpected response/i)).toBeVisible();
  await expect(page.getByRole('button', {name: 'Try again'})).toBeVisible();
});
