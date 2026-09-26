import {expect, test, type BrowserContext, type Page, type Route} from '@playwright/test';

// Mocked-API regressions for session persistence, route error recovery and form semantics.
test.skip(Boolean(process.env.QA_BASE_URL) || process.env.QA_INTEGRATION === 'true', 'Uses local API fixtures only.');

const jobseeker = {id: 'qa-jobseeker', name: 'QA User', email: 'qa@example.invalid', role: 'jobseeker', status: 'active', profileComplete: true};
const job = {
  id: 'job-1', title: 'Session Guitarist', company: 'Verse Studio', location: 'Mumbai', opportunity_kind: 'Contract',
  description: 'Record guitar parts for a film score.', skills: [], status: 'published', createdAt: '2026-09-01T00:00:00Z',
};

type Handler = (pathname: string, route: Route) => Promise<void> | void | false;

/** Answers every /api request: `/me` succeeds only while a token is sent, everything else returns fixtures. */
function apiMock(extra?: Handler) {
  return async (route: Route) => {
    const request = route.request();
    const pathname = new URL(request.url()).pathname;
    if (extra) {
      const handled = await extra(pathname, route);
      if (handled !== false) return;
    }
    const json = (status: number, body: unknown) => route.fulfill({status, contentType: 'application/json', body: JSON.stringify(body)});
    if (pathname.endsWith('/me')) {
      return request.headers().authorization ? json(200, {user: jobseeker}) : json(401, {error: 'Authentication required'});
    }
    if (pathname.endsWith('/auth/login')) return json(200, {user: jobseeker, accessToken: 'qa-token-2'});
    if (pathname.endsWith('/notifications')) return json(200, {notifications: [], unread: 0});
    if (pathname.endsWith('/notifications/unread')) return json(200, {unread: 0});
    if (pathname.endsWith('/jobs/job-1')) return json(200, {job});
    return json(200, {});
  };
}

async function seedSession(target: Page | BrowserContext) {
  await target.addInitScript(() => {
    // The first-run product tour is a modal; mark it seen so it does not cover the workspace.
    localStorage.setItem('verse-tour-v2-jobseeker', 'done');
    if (localStorage.getItem('qa_seeded')) return;
    localStorage.setItem('qa_seeded', '1');
    localStorage.setItem('verse_access_token', 'qa-token');
  });
}

async function clientNavigate(page: Page, path: string) {
  await page.evaluate(target => {
    history.pushState({}, '', target);
    dispatchEvent(new PopStateEvent('popstate'));
  }, path);
}

test('a session survives opening a new tab', async ({context}) => {
  await seedSession(context);
  await context.route('**/api/**', apiMock());
  const first = await context.newPage();
  await first.goto('/jobseeker/notifications');
  await expect(first.getByRole('heading', {name: 'Notifications'})).toBeVisible();

  const second = await context.newPage();
  await second.goto('/jobseeker/notifications');
  await expect(second.getByRole('heading', {name: 'Notifications'})).toBeVisible();
});

test('a token saved per tab by an older release is migrated and keeps the user signed in', async ({page}) => {
  await page.addInitScript(() => {
    if (sessionStorage.getItem('qa_legacy_seeded')) return;
    sessionStorage.setItem('qa_legacy_seeded', '1');
    sessionStorage.setItem('verse_access_token', 'legacy-token');
  });
  await page.route('**/api/**', apiMock());

  await page.goto('/jobseeker/notifications');
  await expect(page.getByRole('heading', {name: 'Notifications'})).toBeVisible();
  expect(await page.evaluate(() => [localStorage.getItem('verse_access_token'), sessionStorage.getItem('verse_access_token')])).toEqual(['legacy-token', null]);
});

test('signing out in one tab signs out the other, and signing back in restores it', async ({context}) => {
  await seedSession(context);
  await context.route('**/api/**', apiMock());
  const errors: string[] = [];
  const active = await context.newPage();
  const other = await context.newPage();
  other.on('pageerror', error => errors.push(error.message));

  await active.goto('/jobseeker/notifications');
  await other.goto('/jobseeker/notifications');
  await expect(other.getByRole('heading', {name: 'Notifications'})).toBeVisible();

  await active.getByRole('button', {name: 'Open account menu'}).click();
  await active.getByRole('menuitem', {name: 'Sign out'}).click();
  await expect(active).toHaveURL(/\/$/);

  // The other tab drops to signed-out state without a reload and is sent to sign-in.
  await expect(other).toHaveURL(/\/auth\/jobseeker$/);
  await expect(other.locator('body')).not.toContainText('Unexpected Application Error');

  await active.goto('/auth/jobseeker');
  await active.getByLabel('Email').fill('qa@example.invalid');
  await active.getByRole('button', {name: 'Use password instead'}).click();
  await active.getByLabel('Password', {exact: true}).fill('correct horse battery');
  await active.getByRole('button', {name: 'Sign in', exact: true}).click();
  await expect(active).toHaveURL(/\/jobseeker$/);

  // Without reloading, the other tab now has the signed-in user again.
  // localStorage reaches other tabs asynchronously, so retry the in-app navigation until the user is restored.
  let otherDocumentLoads = 0;
  other.on('request', request => { if (request.resourceType() === 'document') otherDocumentLoads += 1; });
  await expect(async () => {
    await clientNavigate(other, '/jobseeker/notifications');
    await expect(other.getByRole('heading', {name: 'Notifications'})).toBeVisible({timeout: 1_000});
  }).toPass({timeout: 10_000});
  expect(otherDocumentLoads).toBe(0);
  await expect(other).toHaveURL(/\/jobseeker\/notifications$/);
  expect(errors).toEqual([]);
});

test('a stale lazy chunk after a redeploy reloads once and recovers', async ({page}) => {
  let chunkRequests = 0;
  await page.route(/\/assets\/Pricing-[^/]+\.js$/, route => {
    chunkRequests += 1;
    return chunkRequests === 1 ? route.fulfill({status: 404, body: 'Not found'}) : route.fallback();
  });
  await page.route('**/api/**', apiMock());

  await page.goto('/pricing');
  await expect(page.getByRole('heading', {level: 1})).toBeVisible();
  await expect(page.locator('body')).not.toContainText('Unexpected Application Error');
  await expect(page.getByText('Verse has been updated.')).toBeHidden();
  expect(chunkRequests).toBe(2);
});

test('a chunk that keeps failing shows a branded error instead of reloading forever', async ({page}) => {
  let chunkRequests = 0;
  let documentLoads = 0;
  page.on('request', request => { if (request.resourceType() === 'document') documentLoads += 1; });
  const failChunk = (route: Route) => { chunkRequests += 1; return route.fulfill({status: 404, body: 'Not found'}); };
  await page.route(/\/assets\/Pricing-[^/]+\.js$/, failChunk);
  await page.route('**/api/**', apiMock());

  await page.goto('/pricing');
  const alert = page.getByRole('alert');
  await expect(alert.getByRole('heading', {name: 'Verse has been updated.'})).toBeVisible();
  await expect(alert.getByRole('button', {name: 'Go home'})).toBeVisible();
  await expect(page.locator('body')).not.toContainText('Unexpected Application Error');
  // One automatic reload at most, then the page settles on the recovery screen.
  await page.waitForTimeout(500);
  expect(documentLoads).toBe(2);
  expect(chunkRequests).toBe(2);

  await page.unroute(/\/assets\/Pricing-[^/]+\.js$/, failChunk);
  await alert.getByRole('button', {name: 'Reload'}).click();
  await expect(page.getByRole('alert')).toBeHidden();
  await expect(page.getByRole('heading', {level: 1})).toBeVisible();
});

test('legacy job-alert links open the job inside the signed-in workspace', async ({page}) => {
  await seedSession(page);
  await page.route('**/api/**', apiMock((pathname, route) => {
    if (!pathname.endsWith('/notifications')) return false;
    return route.fulfill({status: 200, contentType: 'application/json', body: JSON.stringify({notifications: [
      {id: 'n1', title: 'New job match', body: 'Session Guitarist', link: '/jobs/job-1', createdAt: '2026-09-01T00:00:00Z', readAt: null},
    ]})});
  }));

  await page.goto('/jobseeker/notifications');
  await expect(page.getByRole('link', {name: 'Open'})).toHaveAttribute('href', '/jobseeker/jobs/job-1');
});

test('signing in from a public opportunity returns to that job', async ({page}) => {
  await page.route('**/api/**', apiMock());
  await page.goto('/opportunities/job-1');
  await page.getByRole('link', {name: 'Sign in to apply'}).click();
  await expect(page).toHaveURL(/\/auth\/jobseeker$/);

  await page.getByLabel('Email').fill('qa@example.invalid');
  await page.getByRole('button', {name: 'Use password instead'}).click();
  await page.getByLabel('Password', {exact: true}).fill('correct horse battery');
  await page.getByRole('button', {name: 'Sign in', exact: true}).click();
  await expect(page).toHaveURL(/\/jobseeker\/jobs\/job-1$/);
});

test('password reset request is a labelled form that cannot be submitted twice', async ({page}) => {
  let requests = 0;
  let release!: () => void;
  const released = new Promise<void>(resolve => { release = resolve; });
  await page.route('**/api/**', apiMock(async (pathname, route) => {
    if (!pathname.endsWith('/auth/forgot-password')) return false;
    requests += 1;
    await released;
    await route.fulfill({status: 200, contentType: 'application/json', body: JSON.stringify({ok: true})});
  }));

  await page.goto('/forgot-password');
  await page.getByLabel('Email').fill('qa@example.invalid');
  await page.getByLabel('Email').press('Enter');
  const pending = page.getByRole('button', {name: 'Sending…'});
  await expect(pending).toBeDisabled();
  await pending.click({force: true}).catch(() => {});
  await page.getByLabel('Email').press('Enter');
  release();

  await expect(page.getByText('If an account exists, reset instructions have been sent.')).toBeVisible();
  expect(requests).toBe(1);
});
