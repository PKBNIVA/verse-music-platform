import {expect, test, type Page, type Route} from '@playwright/test';

// Mocked-API coverage for the email sign-in code flow on the auth page.
test.skip(Boolean(process.env.QA_BASE_URL) || process.env.QA_INTEGRATION === 'true', 'Uses local API fixtures only.');

const jobseeker = {id: 'qa-jobseeker', name: 'QA User', email: 'qa@example.invalid', role: 'jobseeker', status: 'active', profileComplete: true};
const employer = {id: 'qa-employer', name: 'QA Studio', email: 'studio@example.invalid', role: 'employer', status: 'active', profileComplete: false};
const GENERIC = {ok: true, message: 'If this email can be used on Verse, a 6-digit code is on its way.', expiresIn: 600};

interface Calls { requests: any[]; verifies: any[] }

async function mockApi(page: Page, opts: {user?: typeof jobseeker; validCode?: string; requestDelayMs?: number} = {}) {
  const calls: Calls = {requests: [], verifies: []};
  const user = opts.user ?? jobseeker;
  const validCode = opts.validCode ?? '482913';
  await page.addInitScript(role => localStorage.setItem(`verse-tour-v2-${role}`, 'done'), user.role);
  await page.route('**/api/**', async (route: Route) => {
    const request = route.request();
    const pathname = new URL(request.url()).pathname;
    const json = (status: number, body: unknown) => route.fulfill({status, contentType: 'application/json', body: JSON.stringify(body)});
    if (pathname.endsWith('/auth/otp/request')) {
      calls.requests.push(request.postDataJSON());
      if (opts.requestDelayMs) await new Promise(resolve => setTimeout(resolve, opts.requestDelayMs));
      return json(200, GENERIC);
    }
    if (pathname.endsWith('/auth/otp/verify')) {
      const body = request.postDataJSON();
      calls.verifies.push(body);
      return body.code === validCode
        ? json(200, {user, accessToken: 'qa-otp-token'})
        : json(401, {error: 'Invalid or expired code.', code: 'OTP_INVALID'});
    }
    if (pathname.endsWith('/me')) {
      return request.headers().authorization ? json(200, {user}) : json(401, {error: 'Authentication required'});
    }
    if (pathname.endsWith('/notifications/unread')) return json(200, {unread: 0});
    if (pathname.endsWith('/notifications')) return json(200, {notifications: [], unread: 0});
    return json(200, {});
  });
  return calls;
}

async function pasteCode(page: Page, code: string) {
  const input = page.getByLabel('Sign-in code');
  await input.focus();
  await input.evaluate((element, text) => {
    const data = new DataTransfer();
    data.setData('text/plain', text);
    element.dispatchEvent(new ClipboardEvent('paste', {clipboardData: data, bubbles: true, cancelable: true}));
  }, code);
}

test('email code is the primary sign-in and a pasted code signs in', async ({page}) => {
  const calls = await mockApi(page);
  await page.goto('/auth/jobseeker');
  await expect(page.getByLabel('Password', {exact: true})).toHaveCount(0);

  await page.getByLabel('Email').fill('qa@example.invalid');
  await page.getByRole('button', {name: 'Email me a sign-in code'}).click();
  await expect(page.getByRole('heading', {name: 'Check your email'})).toBeVisible();
  await expect(page.getByLabel('Sign-in code')).toBeFocused();
  expect(calls.requests).toEqual([{email: 'qa@example.invalid'}]);

  await pasteCode(page, 'Your code: 482 913');
  await expect(page).toHaveURL(/\/jobseeker$/);
  expect(calls.verifies).toEqual([{email: 'qa@example.invalid', code: '482913'}]);
  expect(await page.evaluate(() => localStorage.getItem('verse_access_token'))).toBe('qa-otp-token');
});

test('a wrong code shows an error, clears the input and allows a retry', async ({page}) => {
  const calls = await mockApi(page);
  await page.goto('/auth/jobseeker');
  await page.getByLabel('Email').fill('qa@example.invalid');
  await page.getByLabel('Email').press('Enter');

  await page.getByLabel('Sign-in code').fill('111111');
  await expect(page.getByRole('alert')).toHaveText('Invalid or expired code.');
  await expect(page.getByLabel('Sign-in code')).toHaveValue('');
  await expect(page.getByLabel('Sign-in code')).toBeFocused();

  await page.getByLabel('Sign-in code').pressSequentially('48291');
  await expect(page.getByRole('button', {name: 'Verify and sign in'})).toBeDisabled();
  await page.getByLabel('Sign-in code').press('3');
  await expect(page).toHaveURL(/\/jobseeker$/);
  expect(calls.verifies.map(v => v.code)).toEqual(['111111', '482913']);
});

test('resend waits 60 seconds and sending shows a busy state', async ({page}) => {
  await page.clock.install();
  const calls = await mockApi(page, {requestDelayMs: 400});
  await page.goto('/auth/jobseeker');
  await page.getByLabel('Email').fill('qa@example.invalid');
  await page.getByRole('button', {name: 'Email me a sign-in code'}).click();
  await expect(page.getByRole('button', {name: 'Sending code…'})).toBeDisabled();

  const resend = page.getByRole('button', {name: /Resend code/});
  await expect(resend).toHaveText('Resend code in 60s');
  await expect(resend).toBeDisabled();
  await page.clock.runFor(30_000);
  await expect(resend).toHaveText(/Resend code in 3\ds/);
  await page.clock.runFor(31_000);
  await expect(resend).toHaveText('Resend code');
  await resend.click();
  await expect.poll(() => calls.requests.length).toBe(2);
  await expect(resend).toBeDisabled();

  await page.getByRole('button', {name: 'Use a different email'}).click();
  await expect(page.getByLabel('Email')).toHaveValue('qa@example.invalid');
});

test('registration by code sends name and role and lands on profile setup', async ({page}) => {
  const calls = await mockApi(page, {user: employer});
  await page.goto('/auth/employer');
  await page.getByRole('button', {name: /create .* account/i}).click();
  await page.getByLabel('Your or company name').fill('QA Studio');
  await page.getByLabel('Email').fill('studio@example.invalid');
  await page.getByRole('button', {name: 'Email me a sign-in code'}).click();
  await expect.poll(() => calls.requests).toEqual([{email: 'studio@example.invalid', name: 'QA Studio', role: 'employer'}]);

  await page.getByLabel('Sign-in code').fill('482913');
  await expect(page).toHaveURL(/\/employer\/profile$/);
});

test('password sign-in remains available as a secondary path', async ({page}) => {
  await mockApi(page);
  await page.goto('/auth/jobseeker');
  await page.getByRole('button', {name: 'Use password instead'}).click();
  await expect(page.getByLabel('Password', {exact: true})).toBeVisible();
  await expect(page.getByRole('link', {name: 'Forgot password?'})).toBeVisible();
  await page.getByRole('button', {name: 'Email me a code instead'}).click();
  await expect(page.getByRole('button', {name: 'Email me a sign-in code'})).toBeVisible();
});

test('admin sign-in offers both code and password', async ({page}) => {
  const calls = await mockApi(page);
  await page.goto('/auth/admin');
  await expect(page.getByRole('button', {name: /create .* account/i})).toHaveCount(0);
  await page.getByLabel('Email').fill('ops@example.invalid');
  await page.getByRole('button', {name: 'Email me a sign-in code'}).click();
  await expect.poll(() => calls.requests).toEqual([{email: 'ops@example.invalid'}]);
  await page.getByRole('button', {name: 'Use a different email'}).click();
  await page.getByRole('button', {name: 'Use password instead'}).click();
  await expect(page.getByLabel('Password', {exact: true})).toBeVisible();
});
