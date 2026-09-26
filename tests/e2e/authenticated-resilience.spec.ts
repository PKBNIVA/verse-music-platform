import {expect, test, type Page} from '@playwright/test';

// Mocked-API regressions for signed-in pages. Live and integration runs use real data instead.
test.skip(Boolean(process.env.QA_BASE_URL) || process.env.QA_INTEGRATION === 'true', 'Uses local API fixtures only.');

type Role = 'jobseeker' | 'employer';

const job = {
  id: 'job-1', title: 'Session Guitarist', company: 'Verse Studio', location: 'Mumbai', kind: 'Contract',
  genre: 'Film', description: 'Record guitar parts for a film score.', requirements: [], skills: [],
  status: 'published', applicants: 0, createdAt: '2026-09-01T00:00:00Z',
};

const fixtures: Record<string, unknown> = {
  '/api/applications': {applications: []},
  '/api/bookings': {bookings: []},
  '/api/employer/applications': {applications: []},
  '/api/dashboard': {stats: {}, jobs: [], applications: [], recommended: []},
  '/api/jobs/job-1': {job},
  '/api/portfolio': {items: []},
  '/api/saved-jobs': {jobs: []},
  '/api/notifications': {notifications: [], unread: 0},
  '/api/notifications/unread': {unread: 0},
};

async function signIn(page: Page, role: Role, me: (attempt: number) => {status: number; body: unknown}) {
  let meCalls = 0;
  // Seed the stored session once; later navigations (e.g. the forced sign-in redirect) must see what the app left behind.
  await page.addInitScript(() => {
    if (localStorage.getItem('qa_seeded')) return;
    localStorage.setItem('qa_seeded', '1');
    localStorage.setItem('verse_access_token', 'qa-token');
  });
  await page.route('**/api/**', route => {
    const pathname = new URL(route.request().url()).pathname;
    if (pathname.endsWith('/me')) {
      const {status, body} = me(++meCalls);
      return route.fulfill({status, contentType: 'application/json', body: JSON.stringify(body)});
    }
    return route.fulfill({status: 200, contentType: 'application/json', body: JSON.stringify(fixtures[pathname] ?? {})});
  });
}

const userFor = (role: Role) => ({id: `qa-${role}`, name: 'QA User', email: 'qa@example.invalid', role, status: 'active', profileComplete: true});

// Each page fetches its data from an effect; the endpoint proves the page mounted before we leave it.
const pagesThatLoadOnMount: Array<[Role, string, string]> = [
  ['jobseeker', '/jobseeker/applications', '/api/applications'],
  ['jobseeker', '/jobseeker/bookings', '/api/bookings'],
  ['jobseeker', '/jobseeker/jobs/job-1', '/api/jobs/job-1'],
  ['jobseeker', '/jobseeker/portfolio', '/api/portfolio'],
  ['jobseeker', '/jobseeker/saved', '/api/saved-jobs'],
  ['employer', '/employer', '/api/dashboard'],
  ['employer', '/employer/applications', '/api/employer/applications'],
];

for (const [role, path, endpoint] of pagesThatLoadOnMount) {
  test(`leaving ${path} does not crash the app`, async ({page}) => {
    const errors: string[] = [];
    page.on('pageerror', error => errors.push(error.message));
    await signIn(page, role, () => ({status: 200, body: {user: userFor(role)}}));

    const pageData = page.waitForResponse(response => new URL(response.url()).pathname === endpoint);
    await page.goto(path);
    await pageData;
    await expect(page.getByText('Preparing your Verse workspace')).toBeHidden();
    await page.evaluate(target => {
      history.pushState({}, '', target);
      dispatchEvent(new PopStateEvent('popstate'));
    }, `/${role}/notifications`);

    await expect(page).toHaveURL(new RegExp(`/${role}/notifications$`));
    await expect(page.locator('body')).not.toContainText('Unexpected Application Error');
    expect(errors).toEqual([]);
  });
}

test('an outage while restoring the session keeps the user signed in and offers a retry', async ({page}) => {
  await signIn(page, 'jobseeker', attempt => attempt <= 2 ? {status: 503, body: {error: 'Unavailable'}} : {status: 200, body: {user: userFor('jobseeker')}});

  await page.goto('/jobseeker/notifications');
  await expect(page.getByRole('alert')).toContainText("We couldn't reach Verse");
  expect(await page.evaluate(() => localStorage.getItem('verse_access_token'))).toBe('qa-token');

  await page.getByRole('button', {name: 'Try again'}).click();
  await expect(page).toHaveURL(/\/jobseeker\/notifications$/);
  await expect(page.getByRole('alert')).toBeHidden();
});

for (const [status, reason] of [[401, 'an expired session'], [403, 'an inactive account']] as const) {
  test(`${reason} still returns the user to sign-in`, async ({page}) => {
    await signIn(page, 'jobseeker', () => ({status, body: {error: 'Authentication required'}}));

    await page.goto('/jobseeker/notifications');
    await expect(page).toHaveURL(/\/auth\/jobseeker$/);
    expect(await page.evaluate(() => localStorage.getItem('verse_access_token'))).toBeNull();
  });
}

test('sign-in accepts existing passwords shorter than the registration minimum', async ({page}) => {
  let submitted: {email?: string; password?: string} = {};
  await page.route('**/api/**', route => {
    const pathname = new URL(route.request().url()).pathname;
    if (pathname.endsWith('/auth/login')) {
      submitted = route.request().postDataJSON();
      return route.fulfill({status: 401, contentType: 'application/json', body: JSON.stringify({error: 'Invalid email or password.'})});
    }
    return route.fulfill({status: 401, contentType: 'application/json', body: JSON.stringify({error: 'Authentication required'})});
  });

  await page.goto('/auth/jobseeker');
  await page.getByLabel('Email').fill('legacy@example.invalid');
  await page.getByLabel('Password', {exact: true}).fill('short1!');
  await page.getByRole('button', {name: 'Sign in', exact: true}).click();

  await expect.poll(() => submitted.password).toBe('short1!');
  await expect(page.getByText('Invalid email or password.')).toBeVisible();
});
