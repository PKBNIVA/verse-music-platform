import {expect, test, type Page, type Request} from '@playwright/test';
import {assertNoHorizontalOverflow} from './qa-helpers';

// Mocked-API regressions for the public funnel and the admin console.
test.skip(Boolean(process.env.QA_BASE_URL) || process.env.QA_INTEGRATION === 'true', 'Uses local API fixtures only.');

type Reply = {status?: number; body: unknown};
type Handler = (request: Request) => Reply;

async function mockApi(page: Page, routes: Record<string, Reply | Handler>, user?: Record<string, unknown>) {
  const calls: Array<{method: string; path: string; body: any}> = [];
  if (user) await page.addInitScript(() => localStorage.setItem('verse_access_token', 'qa-token'));
  await page.route('**/api/**', route => {
    const request = route.request();
    const path = new URL(request.url()).pathname.replace(/^.*\/api/, '/api');
    let body: any = null;
    try { body = request.postDataJSON(); } catch { body = request.postData(); }
    calls.push({method: request.method(), path, body});
    if (path === '/api/me') {
      return route.fulfill({status: user ? 200 : 401, contentType: 'application/json', body: JSON.stringify(user ? {user} : {error: 'Authentication required'})});
    }
    const entry = routes[`${request.method()} ${path}`] ?? routes[path];
    const reply = typeof entry === 'function' ? entry(request) : entry ?? {body: {}};
    return route.fulfill({status: reply.status ?? 200, contentType: 'application/json', body: JSON.stringify(reply.body)});
  });
  return calls;
}

const admin = {id: 'admin-1', name: 'QA Admin', email: 'admin@example.invalid', role: 'admin', status: 'active', profileComplete: true};
const employer = {id: 'emp-1', name: 'QA Studio', email: 'studio@example.invalid', role: 'employer', status: 'active', profileComplete: true};

const adminFixtures = () => ({
  '/api/admin/stats': {body: {stats: {users: 2, liveJobs: 1, pendingJobs: 1, openReports: 1}}},
  '/api/admin/users': {body: {users: [
    {id: 'u-1', name: 'Asha Rao', email: 'asha@example.invalid', role: 'jobseeker', status: 'active', createdAt: '2026-09-01T00:00:00Z'},
    {id: 'admin-1', name: 'QA Admin', email: 'admin@example.invalid', role: 'admin', status: 'active', createdAt: '2026-09-01T00:00:00Z'},
  ]}},
  '/api/admin/jobs': {body: {jobs: [{id: 'job-1', title: 'Session Bassist', company: 'QA Studio', status: 'pending', opportunity_kind: 'session', description: 'Studio session.'}]}},
  '/api/admin/reviews': {body: {reviews: []}},
  '/api/admin/verifications': {body: {requests: []}},
  '/api/admin/reports': {body: {reports: [{id: 'rep-1', status: 'open', entity_type: 'Job', entity_id: 'job-1', reason: 'Scam', created_at: '2026-09-01T00:00:00Z'}]}},
  '/api/admin/audit': {body: {logs: []}},
  '/api/admin/subscriptions': {body: {subscriptions: []}},
  '/api/admin/bookings': {body: {bookings: []}},
  '/api/admin/billing-attempts': {body: {attempts: [
    {id: 'bill-1', operation: 'subscription_create', provider: 'razorpay', state: 'ambiguous', provider_resource_id: 'sub_1', email: 'studio@example.invalid', created_at: '2026-09-01T00:00:00Z'},
    {id: 'bill-2', operation: 'subscription_create', provider: 'razorpay', state: 'pending', provider_resource_id: null, email: 'studio@example.invalid', created_at: '2026-09-01T00:00:00Z'},
  ]}},
  '/api/admin/billing-events': {body: {events: [{id: 'be-1', eventType: 'payment.captured', processingResult: 'applied', email: 'studio@example.invalid', paymentId: 'pay_1', amount: 250000, currency: 'INR', createdAt: '2026-09-01T00:00:00Z'}], nextBefore: null}},
});

test.describe('admin console', () => {
  test('one failing endpoint only blanks its own panel', async ({page}) => {
    const errors: string[] = [];
    page.on('pageerror', error => errors.push(error.message));
    await mockApi(page, {...adminFixtures(), '/api/admin/reports': {status: 500, body: {error: 'Reports store offline'}}}, admin);
    await page.goto('/admin');
    await expect(page.getByRole('heading', {name: 'Marketplace health'})).toBeVisible();
    await expect(page.getByText('1 of 11 panels could not load')).toBeVisible();
    await expect(page.getByText('Session Bassist')).toBeVisible();
    await page.getByRole('tab', {name: /Reports/}).click();
    await expect(page.getByText('This panel could not load: Reports store offline')).toBeVisible();
    await page.getByRole('tab', {name: 'Users'}).click();
    await expect(page.getByText('asha@example.invalid', {exact: false})).toBeVisible();
    await expect(page).toHaveTitle(/Admin/);
    expect(errors).toEqual([]);
  });

  test('rejecting an opportunity uses an in-page dialog and sends the reason', async ({page}) => {
    let nativeDialog = false;
    page.on('dialog', dialog => { nativeDialog = true; void dialog.dismiss(); });
    const calls = await mockApi(page, {...adminFixtures(), 'PATCH /api/admin/jobs/job-1': {body: {ok: true}}}, admin);
    await page.goto('/admin');
    await page.getByRole('button', {name: 'Reject'}).first().click();
    const dialog = page.getByRole('dialog');
    await expect(dialog).toBeVisible();
    const confirm = dialog.getByRole('button', {name: 'Reject opportunity'});
    await expect(confirm).toBeDisabled();
    await dialog.getByLabel(/Reason/).fill('Please add the fee range.');
    await confirm.click();
    await expect(dialog).toBeHidden();
    const patch = calls.find(call => call.method === 'PATCH' && call.path === '/api/admin/jobs/job-1');
    expect(patch?.body).toEqual({status: 'rejected', note: 'Please add the fee range.'});
    expect(nativeDialog).toBe(false);
  });

  test('suspending asks for confirmation and grant-plan validates days', async ({page}) => {
    const calls = await mockApi(page, {
      ...adminFixtures(),
      'PATCH /api/admin/users/u-1': {body: {ok: true}},
      'POST /api/admin/users/u-1/grant-plan': {status: 201, body: {id: 'sub-1'}},
    }, admin);
    await page.goto('/admin');
    await page.getByRole('tab', {name: 'Users'}).click();
    await page.getByRole('button', {name: 'Suspend'}).click();
    await expect(page.getByRole('dialog')).toContainText('signed out everywhere');
    await page.getByRole('dialog').getByRole('button', {name: 'Cancel'}).click();
    expect(calls.some(call => call.method === 'PATCH')).toBe(false);

    await page.getByRole('button', {name: 'Grant plan'}).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByLabel('Plan').selectOption('studio');
    await dialog.getByLabel('Days').fill('0');
    await expect(dialog.getByRole('button', {name: 'Grant plan'})).toBeDisabled();
    await dialog.getByLabel('Days').fill('45');
    await dialog.getByRole('button', {name: 'Grant plan'}).click();
    await expect(dialog).toBeHidden();
    expect(calls.find(call => call.path === '/api/admin/users/u-1/grant-plan')?.body).toEqual({planCode: 'studio', days: 45});
    // Admin rows never offer plan or status changes.
    await expect(page.getByRole('button', {name: 'Grant plan'})).toHaveCount(1);
  });

  test('billing attempts can be reconciled from the commerce tab', async ({page}) => {
    const calls = await mockApi(page, {...adminFixtures(), 'POST /api/admin/billing-attempts/bill-1/reconcile': {status: 503, body: {error: 'Live billing is not configured.'}}}, admin);
    await page.goto('/admin');
    await page.getByRole('tab', {name: 'Commerce'}).click();
    const buttons = page.getByRole('button', {name: 'Reconcile'});
    await expect(buttons).toHaveCount(2);
    await expect(buttons.nth(1)).toBeDisabled();
    await expect(page.getByRole('region', {name: 'Billing events'})).toContainText('payment.captured');
    await expect(page.getByRole('region', {name: 'Billing events'})).toContainText('INR 2,500');
    await buttons.first().click();
    await expect(page.getByText('Live billing is not configured.')).toBeVisible();
    expect(calls.some(call => call.method === 'POST' && call.path === '/api/admin/billing-attempts/bill-1/reconcile')).toBe(true);
  });

  test('sign-in doctor diagnoses an account and can revoke its sessions', async ({page}) => {
    let active = 3;
    const calls = await mockApi(page, {
      ...adminFixtures(),
      '/api/admin/users/lookup': () => ({body: {
        email: 'asha@example.invalid', exists: true, emailProviderConfigured: false,
        user: {id: 'u-1', name: 'Asha Rao', role: 'jobseeker', status: 'suspended', emailVerified: false, profileComplete: true, passwordSet: true, createdAt: '2026-09-01T00:00:00Z', lastLoginAt: null},
        sessions: {active, createdLast7Days: 4, cap: 10},
        emailTokens: [{purpose: 'reset_password', createdAt: '2026-09-20T00:00:00Z', used: false, expired: false}],
        recentAuthEvents: [{action: 'auth.login', at: '2026-09-19T00:00:00Z', ip: '203.0.x.x'}],
        recentFailedLogins: {count: 2, windowMinutes: 15},
        signInCodes: {outstanding: 1, lastRequestedAt: '2026-09-25T10:00:00Z', requestedLast24Hours: 1},
        diagnosis: [{level: 'error', code: 'ACCOUNT_SUSPENDED', message: 'Account is suspended.'}, {level: 'error', code: 'EMAIL_UNDELIVERABLE', message: '1 password reset(s) requested but no email provider is configured.'}],
      }}),
      'POST /api/admin/users/u-1/revoke-sessions': () => { const revoked = active; active = 0; return {body: {ok: true, revoked}}; },
    }, admin);
    await page.goto('/admin');
    await page.getByRole('tab', {name: 'Sign-in doctor'}).click();
    await page.getByLabel('Account email').fill('  Asha@Example.invalid ');
    await page.getByRole('button', {name: 'Diagnose'}).click();
    const result = page.getByTestId('signin-doctor-result');
    await expect(result).toContainText('Account is suspended.');
    await expect(result).toContainText('no email provider is configured');
    await expect(result).toContainText('203.0.x.x');
    await expect(result).toContainText('1 outstanding');
    expect(calls.find(call => call.path === '/api/admin/users/lookup')).toBeTruthy();
    const lookupUrl = await page.evaluate(() => performance.getEntriesByType('resource').map(e => e.name).find(n => n.includes('/admin/users/lookup')));
    expect(lookupUrl).toContain('email=Asha%40Example.invalid');
    await page.getByRole('button', {name: /Sign out of all 3 session/}).click();
    await expect(page.getByText('Signed out of 3 session(s)')).toBeVisible();
    await expect(page.getByRole('button', {name: /Sign out of all/})).toHaveCount(0);
  });

  test('sign-in doctor reports an unknown email', async ({page}) => {
    await mockApi(page, {...adminFixtures(), '/api/admin/users/lookup': {body: {email: 'nobody@example.invalid', exists: false, diagnosis: [{level: 'error', code: 'NO_ACCOUNT', message: 'No account uses this email.'}]}}}, admin);
    await page.goto('/admin');
    await page.getByRole('tab', {name: 'Sign-in doctor'}).click();
    await page.getByLabel('Account email').fill('nobody@example.invalid');
    await page.keyboard.press('Enter');
    await expect(page.getByTestId('signin-doctor-result')).toContainText('No account uses this email.');
  });

  test('admin console fits a phone screen', async ({page}, testInfo) => {
    await page.setViewportSize({width: 390, height: 844});
    await mockApi(page, adminFixtures(), admin);
    await page.goto('/admin');
    await expect(page.getByRole('heading', {name: 'Marketplace health'})).toBeVisible();
    await assertNoHorizontalOverflow(page, testInfo);
    await page.getByRole('tab', {name: 'Audit'}).click();
    await expect(page.getByText('No audit events yet.')).toBeVisible();
  });
});

test.describe('public funnel', () => {
  test('pricing shows the plan limits the API enforces and falls back when it is down', async ({page}) => {
    await mockApi(page, {'/api/billing/plans': {body: {plans: [
      {code: 'free', name: 'Free', monthly: 0, trialDays: 0, activePosts: 1, seats: 1, shortlist: 20, bookings: 2},
      {code: 'pro', name: 'Pro', monthly: 3100, trialDays: 7, activePosts: 12, seats: 3, shortlist: 300, bookings: 25},
    ]}}});
    await page.goto('/pricing');
    const plans = page.getByTestId('pricing-plans');
    await expect(plans).toContainText('₹3,100');
    await expect(plans).toContainText('7-day free trial');
    await expect(plans).toContainText('12 active opportunities');
    await expect(plans).not.toContainText('₹2,499');
    await expect(page).toHaveTitle(/Pricing/);
  });

  test('pricing still renders plans when /billing/plans fails', async ({page}) => {
    await mockApi(page, {'/api/billing/plans': {status: 503, body: {error: 'down'}}});
    await page.goto('/pricing');
    await expect(page.getByTestId('pricing-plans')).toContainText('₹2,499');
    await expect(page.getByRole('status')).toContainText('standard plan limits');
  });

  const act = {id: 'act-1', name: 'The QA Trio', act_type: 'band', genres: ['Jazz'], members: [], currency: 'INR'};

  test('an act page carries the act into the booking flow', async ({page}) => {
    await mockApi(page, {'/api/public/acts/act-1': {body: {act}}}, employer);
    await page.goto('/acts/act-1');
    await expect(page.getByRole('link', {name: 'Request a quote'})).toHaveAttribute('href', '/employer/book-talent?act=act-1');
    await expect(page).toHaveTitle(/The QA Trio/);
  });

  test('anonymous visitors are sent to sign in with the act remembered', async ({page}) => {
    await mockApi(page, {'/api/public/acts/act-1': {body: {act}}});
    await page.goto('/acts/act-1');
    await page.getByRole('link', {name: 'Sign in to request a quote'}).click();
    await expect(page).toHaveURL(/\/auth\/employer/);
    const from = await page.evaluate(() => (history.state as any)?.usr?.from);
    expect(from).toBe('/employer/book-talent?act=act-1');
  });

  for (const [path, endpoint, back] of [
    ['/acts/missing', '/api/public/acts/missing', 'Browse bookable acts'],
    ['/professionals/missing', '/api/public/talent/missing', 'Browse professionals'],
    ['/opportunities/missing', '/api/jobs/missing', 'Browse music jobs'],
  ] as const) {
    test(`${path} explains a missing record instead of offering a useless retry`, async ({page}) => {
      await mockApi(page, {[endpoint]: {status: 404, body: {error: 'Not found'}}});
      await page.goto(path);
      await expect(page.getByRole('heading', {level: 1})).toContainText('isn’t available');
      await expect(page.getByRole('button', {name: 'Try again'})).toHaveCount(0);
      await expect(page.getByRole('link', {name: back})).toBeVisible();
      await expect(page).toHaveTitle(/not found/i);
    });
  }

  test('verify-email without a token does not call the API', async ({page}) => {
    const calls = await mockApi(page, {});
    await page.goto('/verify-email');
    await expect(page.getByRole('heading', {level: 1})).toContainText('couldn’t verify');
    expect(calls.some(call => call.path === '/api/auth/verify-email')).toBe(false);
  });

  test('verify-email sends a token exactly once', async ({page}) => {
    const calls = await mockApi(page, {'POST /api/auth/verify-email': {body: {ok: true}}});
    await page.goto('/verify-email?token=abc');
    await expect(page.getByRole('heading', {level: 1})).toHaveText('Email verified');
    expect(calls.filter(call => call.path === '/api/auth/verify-email').map(call => call.body)).toEqual([{token: 'abc'}]);
  });

  test('public pages have their own titles and descriptions', async ({page}) => {
    await mockApi(page, {'/api/jobs': {body: {jobs: []}}, '/api/public/talent': {body: {talent: []}}, '/api/public/acts': {body: {acts: []}}});
    const seen = new Set<string>();
    for (const path of ['/forgot-password', '/reset-password', '/pricing', '/start', '/guide', '/search', '/sitemap', '/music-jobs', '/music-professionals', '/book-music', '/terms', '/contact', '/nowhere']) {
      await page.goto(path);
      await expect(page.locator('h1').first()).toBeVisible();
      await expect(page).not.toHaveTitle('Verse — Music Careers, Hiring & Booking');
      const title = await page.title();
      expect(title, path).toMatch(/Verse/);
      expect(seen.has(title), `${path} reuses title "${title}"`).toBe(false);
      seen.add(title);
      expect(await page.locator('meta[name="description"]').getAttribute('content'), path).toBeTruthy();
    }
  });

  test('search keeps working when browser storage is blocked', async ({page}) => {
    await page.addInitScript(() => {
      Object.defineProperty(Storage.prototype, 'setItem', {value: () => { throw new DOMException('blocked', 'SecurityError'); }});
    });
    await mockApi(page, {'/api/search': {body: {results: [{type: 'talent', id: 'u-1', url: '/professionals/u-1', title: 'Asha Rao', tags: []}], interpretedAs: ['singer']}}});
    await page.goto('/search?q=singer');
    await expect(page.getByText('Asha Rao')).toBeVisible();
    await expect(page.getByText('Search is taking a breather')).toHaveCount(0);
  });
});
