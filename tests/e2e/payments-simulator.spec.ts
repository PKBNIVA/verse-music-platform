import {randomUUID} from 'node:crypto';
import {expect, test, type APIRequestContext, type Page} from '@playwright/test';

// Complete payment journeys in a real browser against Rails running the local Razorpay
// simulator (RAZORPAY_SIMULATOR=true with rzp_test_ keys; never production). The simulated
// checkout modal replaces checkout.js; Razorpay-side events are driven through the dev-only
// /api/dev/razorpay endpoints, which deliver correctly signed webhooks to the server.
test.describe('payments against the Razorpay simulator', () => {
  test.skip(process.env.QA_PAYMENTS_SIMULATOR !== 'true', 'Needs a local Rails API with RAZORPAY_SIMULATOR=true (see DEPLOYMENT.md).');
  const api = () => process.env.QA_API_BASE_URL!;

  async function register(request: APIRequestContext, role: 'employer' | 'jobseeker', name = 'Payments QA') {
    const email = `pay-${randomUUID()}@example.invalid`;
    const response = await request.post(`${api()}/auth/register`, {data: {name, email, password: 'PaymentsPass123!', role}});
    expect(response.status(), await response.text()).toBe(201);
    const body = await response.json();
    return {token: body.accessToken as string, email, role, id: body.user.id as string};
  }

  const call = async (request: APIRequestContext, token: string, method: 'get' | 'post', path: string, data?: unknown) => {
    const response = await request[method](`${api()}${path}`, {headers: {Authorization: `Bearer ${token}`}, data});
    const body = await response.json().catch(() => ({}));
    return {status: response.status(), body};
  };

  async function signIn(page: Page, user: {token: string; role: string}) {
    await page.addInitScript(({token, role}) => {
      localStorage.setItem('verse_access_token', token);
      localStorage.setItem(`verse-tour-v2-${role}`, 'done');
    }, user);
  }

  async function subscriptionId(request: APIRequestContext, token: string) {
    const {body} = await call(request, token, 'get', '/billing/subscription');
    return body.subscription?.provider_subscription_id as string;
  }

  async function simulate(request: APIRequestContext, token: string, subId: string, action: string) {
    const result = await call(request, token, 'post', `/dev/razorpay/subscriptions/${subId}/${action}`);
    expect(result.status, JSON.stringify(result.body)).toBe(200);
    for (const delivery of result.body.deliveries) expect(delivery.status, JSON.stringify(delivery)).toBe(200);
    return result.body;
  }

  const statusLabel = (page: Page) => page.getByTestId('billing-status-label');

  test('trial → authenticated → activated → charged → halted → resumed → cancel at cycle end → completed', async ({page, request}) => {
    const user = await register(request, 'employer');
    await signIn(page, user);
    await page.goto('/employer/billing');
    await expect(page.getByRole('status').filter({hasText: 'Test mode.'})).toBeVisible();

    await page.getByTestId('plan-pro').getByRole('button', {name: 'Start free trial'}).click();
    const checkout = page.getByTestId('razorpay-simulator');
    await expect(checkout).toBeVisible();
    await expect(checkout).toContainText('₹2,499 / month after a 14-day trial');
    await checkout.getByRole('button', {name: 'Pay (simulate success)'}).click();
    await expect(checkout).toBeHidden();
    await expect(statusLabel(page)).toHaveText('Free trial');
    await expect(page.getByTestId('billing-status-copy')).toContainText('first charge of ₹2,499');
    await expect(page.getByTestId('next-charge-date')).toBeVisible();

    const subId = await subscriptionId(request, user.token);
    expect(subId).toMatch(/^sub_Sim/);
    await simulate(request, user.token, subId, 'activate');
    await page.reload();
    await expect(statusLabel(page)).toHaveText('Active');
    await expect(page.getByTestId('billing-status-copy')).toContainText('Next charge: ₹2,499');
    await expect(page.getByTestId('payment-history')).toContainText('Paid');

    await simulate(request, user.token, subId, 'charge');
    await page.reload();
    await expect(page.getByTestId('payment-history').locator('tbody tr')).toHaveCount(2);

    await simulate(request, user.token, subId, 'halt');
    await page.reload();
    await expect(statusLabel(page)).toHaveText('Payment failed');
    await expect(page.getByTestId('billing-status-copy')).toContainText('paid features are paused');
    const limits = await call(request, user.token, 'get', '/billing/subscription');
    expect(limits.body.plan.code).toBe('free');

    await simulate(request, user.token, subId, 'resume');
    await page.reload();
    await expect(statusLabel(page)).toHaveText('Active');

    await page.getByRole('button', {name: 'Cancel subscription'}).click();
    const dialog = page.getByRole('alertdialog');
    await expect(dialog).toContainText('You will not be charged again');
    await dialog.getByRole('button', {name: 'Keep subscription'}).click();
    await expect(dialog).toBeHidden();
    await expect(statusLabel(page)).toHaveText('Active');
    await page.getByRole('button', {name: 'Cancel subscription'}).click();
    await page.getByRole('alertdialog').getByRole('button', {name: 'Cancel at period end'}).click();
    await expect(statusLabel(page)).toHaveText('Cancellation scheduled');
    await expect(page.getByTestId('billing-status-copy')).toContainText('You will not be charged again');
    await expect(page.getByRole('button', {name: 'Cancel subscription'})).toHaveCount(0);

    await simulate(request, user.token, subId, 'complete');
    await page.reload();
    await expect(statusLabel(page)).toHaveText('Cancelled');
    await expect(page.getByTestId('billing-status-copy')).toContainText('You are on the Free plan');
  });

  test('declined and dismissed checkout, double click, and plan change refusal', async ({page, request}) => {
    const user = await register(request, 'employer');
    await signIn(page, user);
    await page.goto('/employer/billing');

    const start = page.getByTestId('plan-pro').getByRole('button', {name: 'Start free trial'});
    await start.dblclick();
    const checkout = page.getByTestId('razorpay-simulator');
    await expect(checkout).toHaveCount(1);
    await checkout.getByRole('button', {name: 'Decline payment'}).click();
    await expect(checkout.getByRole('alert')).toContainText('declined by the bank');
    await checkout.getByRole('button', {name: 'Close checkout'}).click();
    await expect(page.getByText('Payment not completed: Your payment has been declined by the bank.')).toBeVisible();
    await expect(statusLabel(page)).toHaveText('Setup incomplete');

    await page.getByTestId('billing-status').getByRole('button', {name: 'Complete setup'}).click();
    await expect(checkout).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(page.getByText('Checkout closed. Nothing was charged.')).toBeVisible();
    await expect(statusLabel(page)).toHaveText('Setup incomplete');

    const admin = await request.post(`${api()}/auth/login`, {data: {email: 'admin@verse.local', password: 'Admin@12345'}});
    const adminToken = (await admin.json()).accessToken;
    const subs = await call(request, adminToken, 'get', '/admin/subscriptions');
    expect(subs.body.subscriptions.filter((s: any) => s.email === user.email)).toHaveLength(1);

    await page.getByTestId('billing-status').getByRole('button', {name: 'Complete setup'}).click();
    await checkout.getByRole('button', {name: 'Pay (simulate success)'}).click();
    await expect(statusLabel(page)).toHaveText('Free trial');

    await page.getByTestId('plan-studio').getByRole('button', {name: 'Switch to Studio'}).click();
    await expect(page.getByText(/Cancel your current plan first/)).toBeVisible();
    await expect(page.getByTestId('razorpay-simulator')).toHaveCount(0);

    // Trial cancellation is immediate and says so.
    await page.getByRole('button', {name: 'Cancel subscription'}).click();
    await expect(page.getByRole('alertdialog')).toContainText('Your free trial ends now');
    await page.getByRole('alertdialog').getByRole('button', {name: 'Cancel now'}).click();
    await expect(statusLabel(page)).toHaveText('Cancelled');

    const events = await call(request, adminToken, 'get', `/admin/billing-events?userId=${user.id}`);
    expect(events.body.events.map((e: any) => e.eventType)).toEqual(expect.arrayContaining(['subscription.authenticated']));
    const failed = await call(request, adminToken, 'get', '/admin/billing-events?eventType=payment.failed');
    expect(failed.body.events.length).toBeGreaterThan(0);
  });

  test('plan limit shows the upgrade prompt', async ({page, request}) => {
    const user = await register(request, 'employer');
    const teammate = await register(request, 'jobseeker', 'Teammate QA');
    const org = await call(request, user.token, 'post', '/organizations', {name: 'Limit QA Studio', orgType: 'studio'});
    expect(org.status).toBe(201);
    await signIn(page, user);
    await page.goto('/employer/workspace');
    const workspace = page.getByRole('button', {name: /Limit QA Studio/});
    if (await workspace.count()) await workspace.first().click();
    await page.getByPlaceholder('Existing Verse user email').fill(teammate.email);
    await page.getByRole('button', {name: 'Add team member'}).click();
    const prompt = page.getByRole('alertdialog', {name: 'Plan limit reached'});
    await expect(prompt).toContainText('Workspace seat limit reached.');
    await prompt.getByRole('button', {name: 'See plans'}).click();
    await expect(page).toHaveURL(/\/employer\/billing$/);
    await expect(page.getByTestId('plan-pro')).toBeVisible();

    // Every other metered action returns the same contract the prompt listens for.
    const owner = await register(request, 'jobseeker', 'Act Owner QA');
    for (let i = 0; i < 2; i += 1) {
      expect((await call(request, user.token, 'post', '/bookings', {actId: await actFor(request, owner.token), eventType: 'concert', city: 'Mumbai', eventDate: futureDate()})).status).toBe(201);
    }
    const third = await call(request, user.token, 'post', '/bookings', {actId: await actFor(request, owner.token), eventType: 'concert', city: 'Mumbai', eventDate: futureDate()});
    expect(third.status).toBe(402);
    expect(third.body.code).toBe('PLAN_LIMIT_REACHED');
  });

  // Bookings require a future event date.
  function futureDate() { return new Date(Date.now() + 30 * 86_400_000).toISOString().slice(0, 10); }

  async function actFor(request: APIRequestContext, ownerToken: string) {
    const act = await call(request, ownerToken, 'post', '/acts', {name: `QA Act ${randomUUID().slice(0, 6)}`, actType: 'band', city: 'Mumbai'});
    expect(act.status, JSON.stringify(act.body)).toBe(201);
    return act.body.id as string;
  }

  async function acceptedBooking(request: APIRequestContext, requesterToken: string) {
    const owner = await register(request, 'jobseeker', 'Deposit Act Owner');
    const act = await call(request, owner.token, 'post', '/acts', {name: `Deposit Act ${randomUUID().slice(0, 6)}`, actType: 'band', city: 'Pune'});
    const booking = await call(request, requesterToken, 'post', '/bookings', {actId: act.body.id, eventType: 'concert', city: 'Pune', eventName: 'Deposit QA night', eventDate: futureDate()});
    expect(booking.status, JSON.stringify(booking.body)).toBe(201);
    const quote = await call(request, owner.token, 'post', `/bookings/${booking.body.id}/quote`, {performanceFee: 40000, travelFee: 2000, depositPercent: 25, currency: 'INR', cancellationTerms: 'Deposit refundable until 14 days before.'});
    expect(quote.status, JSON.stringify(quote.body)).toBe(201);
    expect((await call(request, requesterToken, 'post', `/bookings/${booking.body.id}/status`, {status: 'accepted'})).status).toBe(200);
    return booking.body.id as string;
  }

  test('booking deposit: decline → retry → paid (booking confirmed) → refunded', async ({page, request}) => {
    const user = await register(request, 'employer');
    const bookingId = await acceptedBooking(request, user.token);
    await signIn(page, user);
    await page.goto('/employer/bookings');

    const pay = page.getByRole('button', {name: 'Pay deposit · INR 10,500'});
    await pay.click();
    const checkout = page.getByTestId('razorpay-simulator');
    await expect(checkout).toContainText('INR 10,500');
    await checkout.getByRole('button', {name: 'Decline payment'}).click();
    await expect(checkout.getByRole('alert')).toContainText('declined');
    await checkout.getByRole('button', {name: 'Close checkout'}).click();
    await expect(page.getByTestId('deposit-declined')).toContainText('declined by the bank');

    await page.getByRole('button', {name: /Retry deposit/}).click();
    await checkout.getByRole('button', {name: 'Pay (simulate success)'}).click();
    await expect(page.getByTestId('deposit-status')).toHaveText('Deposit paid · booking confirmed');
    await expect(page.getByText('Deposit paid. Your booking is confirmed.')).toBeVisible();

    const payments = await call(request, user.token, 'get', `/bookings/${bookingId}/payments`);
    expect(payments.body.payments.map((p: any) => p.status).sort()).toEqual(['failed', 'paid']);
    const paid = payments.body.payments.find((p: any) => p.status === 'paid');
    expect(paid.amount).toBe(10500);
    expect(paid.currency).toBe('INR');

    const refund = await call(request, user.token, 'post', `/dev/razorpay/payments/${paid.provider_payment_id}/refund`);
    expect(refund.status).toBe(200);
    expect(refund.body.deliveries.map((d: any) => d.status)).toEqual([200, 200]);
    await page.reload();
    await expect(page.getByTestId('deposit-status')).toHaveText('Deposit refunded · INR 10,500');
    await page.getByRole('button', {name: /Payment history/}).click();
    await expect(page.getByText(/deposit · INR 10,500/).first()).toBeVisible();
    await expect(page.getByText(/^refunded ·/)).toBeVisible();
  });

  test('the dev simulator refuses other users and the checkout contract carries no client amounts', async ({request}) => {
    const user = await register(request, 'employer');
    const other = await register(request, 'employer');
    const bookingId = await acceptedBooking(request, user.token);
    const order = await call(request, user.token, 'post', `/bookings/${bookingId}/payment-order`, {amount: 1, currency: 'USD'});
    expect(order.status).toBe(200);
    expect(order.body.checkout).toMatchObject({mode: 'razorpay', amount: 1_050_000, currency: 'INR', simulator: true});
    expect(JSON.stringify(order.body)).not.toContain('local_sim_secret');
    const stolen = await call(request, other.token, 'post', '/dev/razorpay/checkout', {orderId: order.body.checkout.orderId, outcome: 'success'});
    expect(stolen.status).toBe(404);
  });
});
