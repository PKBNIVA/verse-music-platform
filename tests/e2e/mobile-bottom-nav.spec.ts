import {devices, expect, test, type Page} from '@playwright/test';

// The fixed bottom "Quick navigation" bar must never cover the last controls of a signed-in page.
test.skip(Boolean(process.env.QA_BASE_URL) || process.env.QA_INTEGRATION === 'true', 'Uses local API fixtures only.');
test.use({viewport: devices['Pixel 7'].viewport, isMobile: true, hasTouch: true});

type Role = 'jobseeker' | 'employer';
const user = (role: Role) => ({id: `qa-${role}`, name: 'QA User', email: 'qa@example.invalid', role, status: 'active', profileComplete: true});

async function signIn(page: Page, role: Role) {
  await page.addInitScript(() => {
    localStorage.setItem('verse_access_token', 'qa-token');
    for (const key of ['verse-tour-v2-jobseeker', 'verse-tour-v2-employer']) localStorage.setItem(key, 'done');
  });
  await page.route('**/api/**', route => {
    const pathname = new URL(route.request().url()).pathname;
    const body = pathname.endsWith('/me') ? {user: user(role)} : {};
    return route.fulfill({status: 200, contentType: 'application/json', body: JSON.stringify(body)});
  });
}

const pages: Array<[Role, string]> = [
  ['jobseeker', '/jobseeker/portfolio'],
  ['jobseeker', '/jobseeker/profile'],
  ['jobseeker', '/jobseeker/alerts'],
  ['jobseeker', '/jobseeker/availability'],
  ['employer', '/employer/profile'],
  ['employer', '/employer/post-job'],
  ['employer', '/employer/workspace'],
];

for (const [role, path] of pages) {
  test(`the bottom navigation does not cover the last control on ${path}`, async ({page}) => {
    await signIn(page, role);
    await page.goto(path);
    await expect(page.getByRole('navigation', {name: 'Quick navigation'})).toBeVisible();
    await page.waitForLoadState('networkidle');
    // Make the page long enough to reach the bar, ending in a control, like any content-rich page.
    const covered = await page.evaluate(async () => {
      const main = document.querySelector('main')!;
      const spacer = document.createElement('div');
      spacer.style.height = '2000px';
      const last = document.createElement('button');
      last.textContent = 'Last control';
      last.style.minHeight = '44px'; // a real touch target
      const after = document.createElement('div');
      after.style.height = '2000px';
      main.append(spacer, last, after);
      // Browsers scroll a control only just into view on focus, validation errors and taps;
      // with a fixed bottom bar that lands it underneath unless scroll padding reserves room.
      last.scrollIntoView({block: 'nearest', behavior: 'instant'});
      await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      const nav = document.querySelector('nav[aria-label="Quick navigation"]')!;
      const box = last.getBoundingClientRect();
      const hit = document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2);
      return nav.contains(hit) ? 'Last control' : null;
    });
    expect(covered, `"${covered}" sits under the bottom navigation`).toBeNull();
  });
}
