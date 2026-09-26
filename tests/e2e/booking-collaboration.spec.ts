import {expect, test, type Page, type Route} from '@playwright/test';

// Mocked-API regressions for the live booking & collaboration pages (acts, book-talent, bookings,
// band-builder, urgent, availability, workspace). Live and integration runs use real data instead.
test.skip(Boolean(process.env.QA_BASE_URL) || process.env.QA_INTEGRATION === 'true', 'Uses local API fixtures only.');

type Role = 'jobseeker' | 'employer';
type Handler = (route: Route, body: any) => unknown;

const userFor = (role: Role) => ({id: `qa-${role}`, name: 'QA User', email: 'qa@example.invalid', role, status: 'active', profileComplete: true});

async function signIn(page: Page, role: Role, handlers: Record<string, Handler | unknown>) {
  const failures: string[] = [];
  page.on('pageerror', error => failures.push(`pageerror: ${error.message}`));
  page.on('dialog', dialog => {
    failures.push(`native ${dialog.type()}: ${dialog.message()}`);
    void dialog.dismiss();
  });
  await page.addInitScript(() => {
    localStorage.setItem('verse_access_token', 'qa-token');
    localStorage.setItem('verse-tour-v2-employer', 'done');
    localStorage.setItem('verse-tour-v2-jobseeker', 'done');
  });
  await page.route('**/api/**', async route => {
    const url = new URL(route.request().url());
    const key = `${route.request().method()} ${url.pathname}`;
    if (url.pathname.endsWith('/me') && !url.pathname.endsWith('/acts/me')) return route.fulfill({json: {user: userFor(role)}});
    const handler = handlers[key] ?? handlers[url.pathname];
    if (typeof handler === 'function') {
      let body: any = {};
      try {
        body = route.request().postDataJSON();
      } catch {}
      return (handler as Handler)(route, body);
    }
    return route.fulfill({json: handler ?? {}});
  });
  return failures;
}

const futureDate = (days: number) => new Date(Date.now() + days * 86_400_000).toISOString().slice(0, 10);
const quote = {id: 'q1', performanceFee: 40000, travelFee: 5000, productionFee: 0, otherFee: 0, total: 45000, currency: 'INR', depositPercent: 50, validUntil: null, inclusions: 'Two sets', exclusions: '', cancellationTerms: 'Half refundable', status: 'sent'};
const booking = (overrides: Record<string, unknown>) => ({
  id: 'b1', actName: 'The Night Owls', status: 'quoted', event_type: 'wedding', event_date: futureDate(40), city: 'Pune', requesterName: 'Event Buyer',
  isOwner: false, isRequester: true, latestQuote: quote, paymentCount: 0, depositPaid: false, currency: 'INR', ...overrides,
});

test('band builder survives malformed genres and shows an empty seat state', async ({page}) => {
  const failures = await signIn(page, 'employer', {
    '/api/band-projects': {projects: [{id: 'p1', name: 'Crew', city: null, genres: 'notarray', roles: null}]},
    '/api/taxonomy': {roleCategories: {live: ['Drummer'], odd: 'not-a-list'}},
  });
  await page.goto('/employer/band-builder');
  await expect(page.getByRole('heading', {name: 'Crew'})).toBeVisible();
  await expect(page.getByText('notarray', {exact: false})).toBeVisible();
  await expect(page.getByText('No seats yet')).toBeVisible();
  await page.getByRole('button', {name: 'Add seat'}).click();
  await page.getByLabel('How many').fill('0');
  await page.getByLabel('Role').fill('Drummer');
  await page.getByRole('dialog').getByRole('button', {name: 'Add role'}).click();
  await expect(page.getByRole('dialog').getByRole('alert')).toContainText('1 to 100');
  await page.keyboard.press('Escape');
  await expect(page.getByRole('dialog')).toBeHidden();
  expect(failures).toEqual([]);
});

test('book talent preselects the act from ?act and validates before sending', async ({page}) => {
  const sent: any[] = [];
  const failures = await signIn(page, 'employer', {
    '/api/acts': {acts: []},
    '/api/acts/act-9': {act: {id: 'act-9', name: 'Raga Collective', status: 'active', city: 'Mumbai', act_type: 'ensemble'}},
    'POST /api/bookings': (route: Route, body: any) => {
      sent.push(body);
      return route.fulfill({status: 201, json: {id: 'b-new'}});
    },
  });
  await page.goto('/employer/book-talent?act=act-9');
  const dialog = page.getByRole('dialog');
  await expect(dialog.getByRole('heading', {name: 'Enquire for Raga Collective'})).toBeVisible();
  await expect(page.getByLabel('Event city')).toHaveValue('Mumbai');
  await dialog.getByRole('button', {name: 'Send enquiry'}).click();
  await expect(dialog.getByRole('alert')).toHaveText('Choose the event date.');
  await page.getByLabel('Event date').fill(futureDate(30));
  await page.getByLabel('Budget min').fill('5000');
  await page.getByLabel('Budget max').fill('100');
  await dialog.getByRole('button', {name: 'Send enquiry'}).click();
  await expect(dialog.getByRole('alert')).toContainText('Maximum budget');
  await page.getByLabel('Budget max').fill('9000');
  await dialog.getByRole('button', {name: 'Send enquiry'}).click();
  await expect(dialog).toBeHidden();
  expect(sent).toEqual([expect.objectContaining({actId: 'act-9', city: 'Mumbai', budgetMin: 5000, budgetMax: 9000})]);
  await expect(page).not.toHaveURL(/act=/);
  // The empty search result is explained instead of rendering a blank grid.
  await expect(page.getByText('No acts match this search')).toBeVisible();
  expect(failures).toEqual([]);
});

test('an unavailable ?act explains itself instead of doing nothing', async ({page}) => {
  const failures = await signIn(page, 'employer', {
    '/api/acts': {acts: []},
    '/api/acts/gone': (route: Route) => route.fulfill({status: 404, json: {error: 'Not found'}}),
  });
  await page.goto('/employer/book-talent?act=gone');
  await expect(page.getByText('That act is no longer available for booking.')).toBeVisible();
  await expect(page.getByRole('dialog')).toBeHidden();
  expect(failures).toEqual([]);
});

test('requester accepts a quote through an accessible dialog and sees server errors in place', async ({page}) => {
  let attempts = 0;
  const failures = await signIn(page, 'employer', {
    '/api/bookings': {bookings: [booking({})]},
    'POST /api/bookings/b1/status': (route: Route, body: any) => {
      attempts += 1;
      expect(body).toEqual({status: 'accepted'});
      return attempts === 1
        ? route.fulfill({status: 409, json: {error: 'This quote has expired. Ask the act for a new quote.'}})
        : route.fulfill({json: {ok: true, status: 'accepted'}});
    },
  });
  await page.goto('/employer/bookings');
  const card = page.getByTestId('booking-card');
  await expect(card.getByText('Review the quote, then accept it or ask for changes.')).toBeVisible();
  await expect(card.getByRole('button', {name: 'Decline'})).toHaveCount(0);
  await card.getByRole('button', {name: 'Accept quote'}).click();
  const confirm = page.getByRole('alertdialog');
  await expect(confirm).toContainText('INR 45,000');
  await confirm.getByRole('button', {name: 'Accept quote'}).click();
  await expect(confirm.getByRole('alert')).toHaveText('This quote has expired. Ask the act for a new quote.');
  await confirm.getByRole('button', {name: 'Accept quote'}).click();
  await expect(confirm).toBeHidden();
  expect(attempts).toBe(2);
  expect(failures).toEqual([]);
});

test('each party only sees the actions its role can take', async ({page}) => {
  const failures = await signIn(page, 'jobseeker', {
    '/api/bookings': {
      bookings: [
        booking({id: 'b1', actName: 'Owner Accepted', status: 'accepted', isOwner: true, isRequester: false, depositPaid: true, allowedTransitions: ['completed', 'disputed']}),
        booking({id: 'b2', actName: 'Requester Negotiating', status: 'negotiating', latestQuote: null, allowedTransitions: ['accepted', 'cancelled']}),
        booking({id: 'b3', actName: 'Owner New Enquiry', status: 'requested', isOwner: true, isRequester: false, latestQuote: null, allowedTransitions: ['viewed', 'negotiating', 'declined']}),
        booking({id: 'b4', actName: 'Finished', status: 'completed', allowedTransitions: []}),
      ],
    },
  });
  await page.goto('/jobseeker/bookings');
  const card = (name: string) => page.getByTestId('booking-card').filter({hasText: name});
  await expect(card('Owner Accepted').getByText('Confirmed · deposit paid')).toBeVisible();
  await expect(card('Owner Accepted').getByRole('button', {name: 'Mark completed'})).toBeVisible();
  await expect(card('Owner Accepted').getByRole('button', {name: /Send quote|Pay deposit|Accept/})).toHaveCount(0);
  // No quote yet: accepting would strand the deposit, so the button is not offered.
  await expect(card('Requester Negotiating').getByRole('button', {name: 'Accept quote'})).toHaveCount(0);
  await expect(card('Requester Negotiating').getByText('Waiting for the act to send a quote.')).toBeVisible();
  await expect(card('Owner New Enquiry').getByRole('button', {name: 'Send quote'})).toBeVisible();
  await expect(card('Owner New Enquiry').getByRole('button', {name: 'Decline'})).toBeVisible();
  await expect(card('Finished').getByRole('button', {name: /quote|Cancel|Decline|completed/i})).toHaveCount(0);

  await card('Owner New Enquiry').getByRole('button', {name: 'Send quote'}).click();
  const dialog = page.getByRole('dialog');
  await page.getByLabel('Performance fee').fill('100');
  await page.getByLabel('Currency').fill('R1');
  await page.getByLabel('Cancellation and refund terms').fill('None');
  await dialog.getByRole('button', {name: 'Send quote'}).click();
  await expect(dialog.getByRole('alert')).toContainText('3-letter code');
  await page.keyboard.press('Escape');
  await expect(dialog).toBeHidden();
  expect(failures).toEqual([]);
});

test('bookings load failure offers a retry and empty data offers next steps', async ({page}) => {
  let calls = 0;
  const failures = await signIn(page, 'employer', {
    '/api/bookings': (route: Route) => (++calls === 1 ? route.fulfill({status: 500, json: {error: 'Server unavailable'}}) : route.fulfill({json: {bookings: []}})),
  });
  await page.goto('/employer/bookings');
  await expect(page.getByRole('alert')).toContainText('Server unavailable');
  await page.getByRole('button', {name: 'Try again'}).click();
  await expect(page.getByText('No bookings yet')).toBeVisible();
  await expect(page.getByRole('link', {name: 'Book talent'}).last()).toHaveAttribute('href', '/employer/book-talent');
  expect(failures.filter(f => !f.includes('500'))).toEqual([]);
});

test('lineup members and urgent requests use dialogs instead of native prompts', async ({page}) => {
  const posted: any[] = [];
  const failures = await signIn(page, 'jobseeker', {
    '/api/acts/me': {acts: [{id: 'a1', name: 'Night Owls', act_type: 'band', status: 'active', lineup_size: 3, genres: null, members: [{id: 'm1', displayName: 'Lead', roleName: 'Leader', isLeader: true}, {id: 'm2', displayName: 'Sam', roleName: 'Drums', isLeader: false}]}]},
    'POST /api/acts/a1/members': (route: Route, body: any) => {
      posted.push(body);
      return route.fulfill({status: 201, json: {id: 'm3'}});
    },
    'DELETE /api/acts/a1/members/m2': (route: Route) => route.fulfill({status: 409, json: {error: 'Member is locked.'}}),
    '/api/urgent-requests': {requests: []},
  });
  await page.goto('/jobseeker/acts');
  await page.getByRole('button', {name: 'Add member'}).click();
  await page.getByLabel('Member name').fill('Ria');
  await page.getByLabel('Role in the act').fill('Keys');
  await page.getByRole('dialog').getByRole('button', {name: 'Add member'}).click();
  await expect(page.getByRole('dialog')).toBeHidden();
  expect(posted).toEqual([{displayName: 'Ria', roleName: 'Keys', instrument: null}]);
  await page.getByRole('button', {name: 'Remove Sam'}).click();
  await page.getByRole('alertdialog').getByRole('button', {name: 'Remove member'}).click();
  await expect(page.getByRole('alertdialog').getByRole('alert')).toHaveText('Member is locked.');

  await page.goto('/jobseeker/urgent');
  await expect(page.getByText('No open urgent requests right now.')).toBeVisible();
  await page.getByRole('button', {name: 'Post urgent need'}).click();
  await page.getByRole('dialog').getByRole('button', {name: 'Publish request'}).click();
  await expect(page.getByRole('dialog').getByRole('alert')).toContainText('Add a title, role, city and start time.');
  expect(failures).toEqual([]);
});

test('booking pages fit a phone screen', async ({page}) => {
  await page.setViewportSize({width: 412, height: 915});
  const failures = await signIn(page, 'employer', {
    '/api/bookings': {bookings: [booking({actName: 'An exceptionally long act name that keeps going and going for layout checks', requirements: 'x'.repeat(200)})]},
  });
  await page.goto('/employer/bookings');
  await expect(page.getByTestId('booking-card')).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(1);
  expect(failures).toEqual([]);
});
