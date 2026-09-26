import {expect, test, type Page, type Request} from '@playwright/test';

// Mocked-API regressions for the artist/jobseeker area, found by clicking through every
// /jobseeker screen. Live and integration runs use real data instead.
test.skip(Boolean(process.env.QA_BASE_URL) || process.env.QA_INTEGRATION === 'true', 'Uses local API fixtures only.');

const me = {id: 'qa-seeker', name: 'Asha Rao', email: 'qa@example.invalid', role: 'jobseeker', status: 'active', profileComplete: true};
const job = (id: string, extra: Record<string, unknown> = {}) => ({
  id, title: `Session Guitarist ${id}`, company: 'Verse Studio', location: 'Mumbai', workplace: 'onsite', type: 'Contract',
  opportunity_kind: 'gig', genre: 'Film', description: 'Record guitar parts for a film score.', skills: ['Guitar'],
  applicationsCount: 1, saved: false, ...extra,
});

type Reply = {status?: number; body: unknown};
type Handler = (request: Request, pathname: string) => Reply | undefined;

async function signIn(page: Page, handler: Handler = () => undefined) {
  const errors: string[] = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.addInitScript(() => {
    localStorage.setItem('verse_access_token', 'qa-token');
    localStorage.setItem('verse-tour-v2-jobseeker', 'done');
  });
  await page.route('**/api/**', route => {
    const request = route.request();
    const pathname = new URL(request.url()).pathname;
    let reply = handler(request, pathname);
    if (!reply && pathname.endsWith('/me')) reply = {body: {user: me}};
    reply ??= {body: {}};
    return route.fulfill({status: reply.status ?? 200, contentType: 'application/json', body: JSON.stringify(reply.body)});
  });
  return errors;
}

test('opportunity count is pluralised correctly', async ({page}) => {
  let jobs = [job('a'), job('b')];
  await signIn(page, (_r, path) => (path === '/api/jobs' ? {body: {jobs}} : undefined));
  await page.goto('/jobseeker/jobs');
  await expect(page.getByText('2 opportunities found')).toBeVisible();
  jobs = [job('a')];
  await page.getByRole('button', {name: 'Search', exact: true}).click();
  await expect(page.getByText('1 opportunity found')).toBeVisible();
});

test('changing a filter re-runs the search without pressing Search', async ({page}) => {
  const queries: string[] = [];
  await signIn(page, (request, path) => {
    if (path !== '/api/jobs') return undefined;
    queries.push(new URL(request.url()).search);
    return {body: {jobs: []}};
  });
  await page.goto('/jobseeker/jobs');
  await expect(page.getByText('No exact matches')).toBeVisible();
  await page.getByRole('button', {name: 'Filters'}).click();
  await page.locator('select').first().selectOption('audition');
  await expect.poll(() => queries.some(q => q.includes('kind=audition'))).toBe(true);
});

test('a removed opportunity shows a way back instead of loading forever', async ({page}) => {
  const errors = await signIn(page, (_r, path) => (path === '/api/jobs/gone' ? {status: 404, body: {error: 'Not found'}} : undefined));
  await page.goto('/jobseeker/jobs/gone');
  await expect(page.getByRole('heading', {name: 'This opportunity is no longer available'})).toBeVisible();
  await expect(page.getByText('Loading opportunity…')).toHaveCount(0);
  await page.getByRole('link', {name: 'Back to opportunities'}).click();
  await expect(page).toHaveURL(/\/jobseeker\/jobs$/);
  expect(errors).toEqual([]);
});

test('profile cannot be saved over existing data when it failed to load', async ({page}) => {
  let profileLoads = 0;
  const puts: unknown[] = [];
  await signIn(page, (request, path) => {
    if (path === '/api/profile') { puts.push(request.postDataJSON()); return {body: {user: me}}; }
    // The first /me restores the session; the profile page's own /me then fails.
    if (path.endsWith('/me') && ++profileLoads > 1) return {status: 500, body: {error: 'Profile service unavailable'}};
    return undefined;
  });
  await page.goto('/jobseeker/profile');
  await expect(page.getByRole('alert').filter({hasText: 'Profile service unavailable'})).toBeVisible();
  await expect(page.getByRole('button', {name: 'Loading profile…'})).toBeDisabled();
  expect(puts).toEqual([]);
});

test('credits keep one entry per line after saving twice', async ({page}) => {
  const puts: any[] = [];
  const user = {...me, credits: ['Song A — guitar — 2024'], skills: ['Guitar']};
  await signIn(page, (request, path) => {
    if (path.endsWith('/me')) return {body: {user}};
    if (path === '/api/profile') {
      const body = request.postDataJSON();
      puts.push(body);
      return {body: {user: {...user, ...body}}};
    }
    return undefined;
  });
  await page.goto('/jobseeker/profile');
  const credits = page.getByPlaceholder('Track / project — role — artist / company — year');
  await expect(credits).toHaveValue('Song A — guitar — 2024');
  await credits.fill('Song A — guitar — 2024\nSong B — bass — 2025');
  const save = page.getByRole('button', {name: 'Save career profile'});
  await save.click();
  await expect.poll(() => puts.length).toBe(1);
  await expect(credits).toHaveValue('Song A — guitar — 2024\nSong B — bass — 2025');
  await expect(save).toBeEnabled();
  await save.click();
  await expect.poll(() => puts.length).toBe(2);
  expect(puts[1].credits).toEqual(['Song A — guitar — 2024', 'Song B — bass — 2025']);
  expect(puts[1].skills).toEqual(['Guitar']);
});

test('withdrawing an application asks first and titles link to the opportunity', async ({page}) => {
  let deletes = 0;
  await signIn(page, (request, path) => {
    if (path === '/api/applications') return {body: {applications: [{id: 'app-1', jobId: 'job-9', title: 'Tour Drummer', company: 'Road Co', status: 'Applied', createdAt: '2026-09-01T00:00:00Z'}]}};
    if (request.method() === 'DELETE') { deletes++; return {body: {ok: true}}; }
    return undefined;
  });
  await page.goto('/jobseeker/applications');
  page.once('dialog', dialog => dialog.dismiss());
  await page.getByRole('button', {name: 'Withdraw'}).click();
  await page.waitForTimeout(300);
  expect(deletes).toBe(0);
  await expect(page.getByRole('link', {name: 'Tour Drummer'})).toHaveAttribute('href', '/jobseeker/jobs/job-9');
});

test('dashboard and reviews explain a failed load instead of failing silently', async ({page}) => {
  const errors = await signIn(page, (_r, path) =>
    path === '/api/dashboard' || path === '/api/reviews' ? {status: 500, body: {error: 'Internal error'}} : undefined);
  await page.goto('/jobseeker');
  await expect(page.getByText('Your dashboard could not be loaded')).toBeVisible();
  await page.goto('/jobseeker/reviews');
  await expect(page.getByRole('alert').filter({hasText: 'Internal error'})).toBeVisible();
  expect(errors).toEqual([]);
});

test('saved job removal failure is reported, not thrown', async ({page}) => {
  const errors = await signIn(page, (request, path) => {
    if (path === '/api/saved-jobs') return {body: {jobs: [job('s1')]}};
    if (request.method() === 'DELETE') return {status: 409, body: {error: 'Could not remove right now'}};
    return undefined;
  });
  await page.goto('/jobseeker/saved');
  await page.getByRole('button', {name: 'Remove Session Guitarist s1 from saved'}).click();
  await expect(page.getByText('Could not remove right now')).toBeVisible();
  await expect(page.getByText('Session Guitarist s1')).toBeVisible();
  expect(errors).toEqual([]);
});

test('compare without a selection guides the user and skips the API', async ({page}) => {
  let compareCalls = 0;
  await signIn(page, (_r, path) => (path === '/api/candidates/compare/list' ? (compareCalls++, {status: 400, body: {error: 'Choose at least two professionals to compare.'}}) : undefined));
  await page.goto('/jobseeker/compare');
  await expect(page.getByText('Select two to four professionals')).toBeVisible();
  await expect(page.getByRole('link', {name: 'Choose professionals'})).toHaveAttribute('href', '/jobseeker/hiring/talent');
  expect(compareCalls).toBe(0);
});

test('jobseeker pages fit the viewport with rich data', async ({page}) => {
  const long = 'Extraordinarily-long-unbroken-opportunity-title-that-should-wrap-properly';
  await signIn(page, (_r, path) => ({
    '/api/jobs': {body: {jobs: [job('r1', {title: long, company: long})]}},
    '/api/saved-jobs': {body: {jobs: [job('r2', {title: long})]}},
    '/api/job-alerts': {body: {alerts: [{id: 'al', name: long, frequency: 'weekly', active: true}]}},
    '/api/applications': {body: {applications: [{id: 'ap', jobId: 'j', title: long, company: 'X', status: 'Offer', createdAt: '2026-09-01T00:00:00Z'}]}},
  } as Record<string, Reply>)[path]);
  for (const path of ['/jobseeker/jobs', '/jobseeker/saved', '/jobseeker/alerts', '/jobseeker/applications']) {
    await page.goto(path);
    await expect(page.locator('main')).toContainText(long.slice(0, 20));
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    expect(overflow, `${path} overflows horizontally`).toBeLessThanOrEqual(1);
  }
});
