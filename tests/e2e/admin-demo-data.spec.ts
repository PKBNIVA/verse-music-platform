import {expect, test, type Page, type Route} from '@playwright/test';

// Mocked-API test of the admin demo-data panel. The real API is exercised by the Rails request tests.
test.skip(Boolean(process.env.QA_BASE_URL) || process.env.QA_INTEGRATION === 'true', 'Uses local API fixtures only.');

const admin = {id: 'qa-admin', name: 'QA Admin', email: 'admin@example.invalid', role: 'admin', status: 'active', profileComplete: true};
const sizes = {small: {artists: 20, employers: 8}, medium: {artists: 60, employers: 20}, large: {artists: 150, employers: 50}};
const dashboard: Record<string, unknown> = {
  '/api/admin/stats': {stats: {}}, '/api/admin/users': {users: []}, '/api/admin/jobs': {jobs: []},
  '/api/admin/reviews': {reviews: []}, '/api/admin/verifications': {requests: []}, '/api/admin/reports': {reports: []},
  '/api/admin/audit': {logs: []}, '/api/admin/subscriptions': {subscriptions: []}, '/api/admin/bookings': {bookings: []},
};

type Job = {id: string; kind: string; state: string; batch?: string; size?: string; error?: string; result?: Record<string, number | string[]>; createdAt: string; updatedAt: string};

function demoApi() {
  const now = '2026-09-26T10:00:00Z';
  const state = {batches: [] as unknown[], jobs: [] as Job[], polls: 0, requests: [] as string[], conflictNext: false};
  const overview = () => ({batches: state.batches, jobs: state.jobs, busy: state.jobs.some(j => ['queued', 'running'].includes(j.state)),
    demoUsers: state.batches.length ? 28 : 0, maxUsers: 300, sizes});
  const advance = () => {
    const job = state.jobs[0];
    if (!job || !['queued', 'running'].includes(job.state)) return;
    state.polls += 1;
    if (state.polls < 2) { job.state = 'running'; return; }
    job.state = 'succeeded';
    if (job.kind === 'seed') {
      job.result = {jobseekers: 20, employers: 8, jobs: 16, bookings: 16};
      state.batches = [{name: 'demo-20260926-1000', demo: true, visibility: 'public', artists: 20, employers: 8, users: 28, createdAt: now}];
    } else {
      job.result = {usersRemoved: 28, recordsRemoved: 1234, batches: ['demo-20260926-1000']};
      state.batches = [];
    }
  };
  const handle = async (route: Route) => {
    const request = route.request();
    const {pathname} = new URL(request.url());
    const json = (status: number, body: unknown) => route.fulfill({status, contentType: 'application/json', body: JSON.stringify(body)});
    if (pathname.endsWith('/me')) return json(200, {user: admin});
    if (pathname === '/api/admin/demo-data') {
      state.requests.push(`${request.method()} ${pathname}${request.postData() ? ` ${request.postData()}` : ''}`);
      if (request.method() === 'GET') { advance(); return json(200, overview()); }
      if (state.conflictNext) { state.conflictNext = false; return json(409, {error: 'Another demo data job is still running. Wait for it to finish.', code: 'DEMO_JOB_RUNNING'}); }
      state.polls = 0;
      const id = `job-${state.jobs.length + 1}`;
      const job: Job = request.method() === 'POST'
        ? {id, kind: 'seed', state: 'queued', batch: 'demo-20260926-1000', size: JSON.parse(request.postData() || '{}').size, createdAt: now, updatedAt: now}
        : {id, kind: 'purge_all', state: 'queued', createdAt: now, updatedAt: now};
      state.jobs.unshift(job);
      return json(202, {jobId: id, job});
    }
    return json(200, dashboard[pathname] ?? {});
  };
  return {state, handle};
}

async function openAdmin(page: Page) {
  const api = demoApi();
  await page.addInitScript(() => localStorage.setItem('verse_access_token', 'qa-admin-token'));
  await page.route('**/api/**', api.handle);
  await page.goto('/admin');
  // The demo data panel lives in its own tab of the admin console.
  await page.getByRole('tab', {name: 'Demo data'}).click();
  const panel = page.getByTestId('demo-data-panel');
  await expect(panel).toBeVisible();
  return {api, panel};
}

test('admin creates demo data, sees progress and deletes it all after confirming', async ({page}) => {
  const errors: string[] = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('dialog', dialog => { errors.push(`native dialog: ${dialog.message()}`); void dialog.dismiss(); });
  const {api, panel} = await openAdmin(page);

  await expect(panel.getByText('No demo data on the site.')).toBeVisible();
  await expect(panel.getByRole('button', {name: 'Delete all demo data'})).toBeDisabled();

  await panel.getByLabel('Size').selectOption('medium');
  await panel.getByLabel('Size').selectOption('small');
  await panel.getByRole('button', {name: 'Create demo data'}).click();
  await expect(panel.getByTestId('demo-job-status')).toHaveAttribute('data-state', /queued|running/);
  await expect(panel.getByRole('button', {name: 'Create demo data'})).toBeDisabled();
  await expect(panel.getByTestId('demo-job-status')).toHaveAttribute('data-state', 'succeeded', {timeout: 10_000});
  await expect(panel.getByTestId('demo-job-status')).toContainText('20 artists, 8 employers');
  await expect(panel.getByTestId('demo-batches')).toContainText('demo-20260926-1000');
  await expect(panel.getByTestId('demo-batches')).toContainText('20 artists · 8 employers');
  expect(api.state.requests).toContain('POST /api/admin/demo-data {"size":"small"}');

  await panel.getByRole('button', {name: 'Delete all demo data'}).click();
  const dialog = page.getByRole('alertdialog');
  await expect(dialog).toContainText('Delete all demo data?');
  await dialog.getByRole('button', {name: 'Cancel'}).click();
  await expect(dialog).toBeHidden();
  expect(api.state.requests.filter(r => r.startsWith('DELETE'))).toEqual([]);

  await panel.getByRole('button', {name: 'Delete all demo data'}).click();
  await page.getByRole('alertdialog').getByRole('button', {name: 'Delete all demo data'}).click();
  await expect(panel.getByTestId('demo-job-status')).toHaveAttribute('data-state', 'succeeded', {timeout: 10_000});
  await expect(panel.getByTestId('demo-job-status')).toContainText('28 demo accounts');
  await expect(panel.getByText('No demo data on the site.')).toBeVisible();
  expect(api.state.requests).toContain('DELETE /api/admin/demo-data');
  expect(errors).toEqual([]);
});

test('a refused request is reported clearly', async ({page}) => {
  const {api, panel} = await openAdmin(page);
  api.state.conflictNext = true;
  await panel.getByRole('button', {name: 'Create demo data'}).click();
  await expect(panel.getByRole('alert')).toContainText('Another demo data job is still running');
  await expect(panel.getByRole('button', {name: 'Create demo data'})).toBeEnabled();
});
