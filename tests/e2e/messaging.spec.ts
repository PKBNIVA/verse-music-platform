import {expect, test, type Page, type Route} from '@playwright/test';

// Mocked-API regressions for messaging, unread badges and notifications. Live and integration runs use real data.
test.skip(Boolean(process.env.QA_BASE_URL) || process.env.QA_INTEGRATION === 'true', 'Uses local API fixtures only.');

type Role = 'jobseeker' | 'employer';
type Msg = {id: string; senderId: string; body: string; createdAt: string; readAt: string | null};

const ME = 'me-1';
const at = (minute: number) => new Date(Date.UTC(2026, 8, 20, 10, minute)).toISOString();

async function mockApi(page: Page, role: Role, opts: {conversations?: any[]; threads?: Record<string, Msg[]>; notifications?: any[]} = {}) {
  const state = {
    conversations: opts.conversations ?? [],
    threads: opts.threads ?? {},
    notifications: opts.notifications ?? [],
    unread: 0, unreadMessages: 0,
    sendStatus: 201,
    sent: [] as string[],
    calls: [] as string[],
    readAll: 0,
    patched: [] as string[],
    emailNotifications: true,
    preferenceStatus: 200,
    preferenceWrites: [] as unknown[],
    unsubscribeTokens: [] as string[],
  };
  const json = (route: Route, body: unknown, status = 200) => route.fulfill({status, contentType: 'application/json', body: JSON.stringify(body)});
  await page.addInitScript(() => {
    localStorage.setItem('verse_access_token', 'qa-token');
    localStorage.setItem('verse-tour-v2-jobseeker', 'done');
    localStorage.setItem('verse-tour-v2-employer', 'done');
  });
  await page.route('**/api/**', route => {
    const request = route.request();
    const {pathname} = new URL(request.url());
    const path = pathname.replace(/^\/api/, '');
    state.calls.push(`${request.method()} ${path}`);
    if (path === '/me') return json(route, {user: {id: ME, name: 'Viewer Person', email: 'viewer@example.invalid', role, status: 'active', profileComplete: true}});
    if (path === '/notifications/unread') return json(route, {unread: state.unread, unreadMessages: state.unreadMessages});
    if (path === '/notifications/read-all') { state.readAll += 1; return json(route, {ok: true}); }
    if (path === '/notifications/preferences') {
      if (request.method() === 'PATCH') {
        const value = request.postDataJSON().emailNotifications;
        state.preferenceWrites.push(value);
        if (state.preferenceStatus !== 200) return json(route, {error: 'Service unavailable'}, state.preferenceStatus);
        state.emailNotifications = value;
      }
      return json(route, {emailNotifications: state.emailNotifications});
    }
    if (path === '/notifications/unsubscribe') {
      const token = request.postDataJSON()?.token as string;
      state.unsubscribeTokens.push(token);
      return token === 'good-token' ? json(route, {ok: true, emailNotifications: false}) : json(route, {error: 'This unsubscribe link is invalid.', code: 'INVALID_TOKEN'}, 400);
    }
    if (path === '/notifications') return json(route, {notifications: state.notifications, unread: state.notifications.filter(n => !n.readAt).length});
    const patch = path.match(/^\/notifications\/(.+)$/);
    if (patch) { state.patched.push(patch[1]); return json(route, {ok: true}); }
    if (path === '/conversations') return json(route, {conversations: state.conversations});
    const thread = path.match(/^\/conversations\/([^/]+)\/messages$/);
    if (thread) {
      const id = thread[1];
      if (!state.threads[id]) return json(route, {error: 'Conversation not found'}, 404);
      if (request.method() === 'POST') {
        const body = request.postDataJSON().body as string;
        state.sent.push(body);
        if (state.sendStatus !== 201) return json(route, {error: "You're doing that too often. Try again later.", code: 'RATE_LIMITED'}, state.sendStatus);
        const message = {id: `sent-${state.sent.length}`, senderId: ME, body: body.trim(), createdAt: new Date().toISOString(), readAt: null};
        state.threads[id].push(message);
        return json(route, {message}, 201);
      }
      const list = state.threads[id];
      return json(route, {messages: list.slice(-200), truncated: list.length > 200, limit: 200});
    }
    return json(route, {});
  });
  return state;
}

const conversation = (id: string, extra: Record<string, unknown> = {}) => ({
  id, counterpartName: `Counterpart ${id}`, candidateName: 'Viewer Person', employerName: 'Viewer Person', viewerSide: 'employer',
  jobTitle: null, lastMessage: 'hello', lastMessageFromMe: false, unreadCount: 0, ...extra,
});

test.describe('messages', () => {
  test('shows the counterpart by conversation side and deep-links to a thread with unread and read state', async ({page}) => {
    // A jobseeker who hires is on the employer side: the counterpart is the candidate, never the viewer.
    const state = await mockApi(page, 'jobseeker', {
      conversations: [conversation('c1', {jobTitle: 'Session Drummer'}), conversation('c2', {counterpartName: 'Second Person', unreadCount: 3})],
      threads: {
        c1: [{id: 'm1', senderId: 'other', body: 'first', createdAt: at(1), readAt: at(2)}, {id: 'm2', senderId: ME, body: 'mine', createdAt: at(3), readAt: at(4)}],
        c2: [{id: 'm3', senderId: 'other', body: 'unread one', createdAt: at(5), readAt: null}],
      },
    });
    // Side-by-side list and thread (the mobile layout is covered below).
    await page.setViewportSize({width: 1280, height: 900});
    await page.goto('/jobseeker/messages?c=c2');
    await expect(page.getByTestId('thread-name')).toHaveText('Second Person');
    await expect(page.getByTestId('message-body')).toHaveText(['unread one']);
    // Opening the thread clears its unread badge locally.
    await expect(page.getByRole('button', {name: /Second Person/})).not.toContainText('3');
    await expect(page.getByTestId('conversation-name')).toHaveText(['Counterpart c1', 'Second Person']);
    await expect(page.getByTestId('conversation-name')).not.toContainText(['Viewer Person']);

    await page.getByRole('button', {name: /Counterpart c1/}).click();
    await expect(page).toHaveURL(/\/jobseeker\/messages\?c=c1$/);
    await expect(page.getByTestId('message-body')).toHaveText(['first', 'mine']);
    await expect(page.getByTestId('read-receipt')).toHaveText(/^Seen/);
    expect(state.calls).toContain('GET /conversations/c1/messages');

    // Legacy ?conversation= links still work.
    await page.goto('/jobseeker/messages?conversation=c1');
    await expect(page.getByTestId('thread-name')).toHaveText('Counterpart c1');
  });

  test('composer: Enter sends, Shift+Enter adds a line, whitespace is rejected and markup renders as text', async ({page}) => {
    const state = await mockApi(page, 'employer', {conversations: [conversation('c1')], threads: {c1: []}});
    await page.goto('/employer/messages?c=c1');
    await expect(page.getByTestId('thread-empty')).toContainText('Say hello to Counterpart c1');

    const box = page.getByLabel('Message', {exact: true});
    const send = page.getByRole('button', {name: 'Send message'});
    await box.fill('   \n  ');
    await expect(send).toBeDisabled();
    await box.press('Enter');
    expect(state.sent).toEqual([]);

    await box.fill('Line one 🎸');
    await box.press('Shift+Enter');
    await box.pressSequentially('<img src=x onerror="window.__xss=1"><script>window.__xss=2</script>');
    await box.press('Enter');
    await expect(page.getByTestId('message-body')).toHaveCount(1);
    expect(state.sent).toEqual(['Line one 🎸\n<img src=x onerror="window.__xss=1"><script>window.__xss=2</script>']);
    await expect(box).toHaveValue('');
    const bubble = page.getByTestId('message-body');
    await expect(bubble).toHaveText('Line one 🎸\n<img src=x onerror="window.__xss=1"><script>window.__xss=2</script>');
    await expect(bubble.locator('img, script')).toHaveCount(0);
    expect(await page.evaluate(() => (window as any).__xss)).toBeUndefined();
    await expect(page.getByTestId('read-receipt')).toHaveText('Sent');
  });

  test('long messages wrap, over-limit drafts are blocked and rate limits keep the draft with a clear message', async ({page}) => {
    const state = await mockApi(page, 'employer', {conversations: [conversation('c1')], threads: {c1: [{id: 'm1', senderId: 'other', body: 'x'.repeat(3000), createdAt: at(1), readAt: null}]}});
    await page.setViewportSize({width: 390, height: 844});
    await page.goto('/employer/messages?c=c1');
    await expect(page.getByTestId('message-body')).toHaveCount(1);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);

    const box = page.getByLabel('Message', {exact: true});
    await box.fill('y'.repeat(5001));
    await expect(page.getByTestId('message-counter')).toHaveText('5,001 / 5,000');
    await expect(page.getByRole('button', {name: 'Send message'})).toBeDisabled();

    state.sendStatus = 429;
    await box.fill('Are you free on Friday?');
    await box.press('Enter');
    await expect(page.getByTestId('send-error')).toContainText('sending messages too quickly');
    await expect(box).toHaveValue('Are you free on Friday?');
    await box.pressSequentially(' ');
    await expect(page.getByTestId('send-error')).toBeHidden();
  });

  test('history beyond the cap says only the latest messages are shown', async ({page}) => {
    const many = Array.from({length: 201}, (_, i) => ({id: `m${i}`, senderId: 'other', body: `bulk ${i}`, createdAt: new Date(Date.UTC(2026, 8, 1, 0, 0, i)).toISOString(), readAt: null}));
    await mockApi(page, 'jobseeker', {conversations: [conversation('c1')], threads: {c1: many}});
    await page.goto('/jobseeker/messages?c=c1');
    await expect(page.getByTestId('history-truncated')).toHaveText('Showing the latest 200 messages.');
    await expect(page.getByTestId('message')).toHaveCount(200);
    await expect(page.getByTestId('message-body').last()).toHaveText('bulk 200');
  });

  test('empty inbox, unknown deep link and mobile list/thread navigation', async ({page}) => {
    const state = await mockApi(page, 'jobseeker');
    await page.goto('/jobseeker/messages');
    await expect(page.getByTestId('messages-empty')).toContainText('No conversations yet');
    await expect(page.getByTestId('messages-empty').getByRole('link', {name: 'Explore opportunities'})).toHaveAttribute('href', '/jobseeker/jobs');

    await page.goto('/jobseeker/messages?c=gone');
    await expect(page.getByText('This conversation is unavailable.')).toBeVisible();

    state.conversations = [conversation('c1')];
    state.threads = {c1: [{id: 'm1', senderId: 'other', body: 'hi there', createdAt: at(1), readAt: null}]};
    await page.setViewportSize({width: 390, height: 844});
    await page.goto('/jobseeker/messages');
    // Phones show the list first and do not auto-open a thread.
    await expect(page.getByTestId('conversation-name')).toHaveText(['Counterpart c1']);
    await expect(page).toHaveURL(/\/jobseeker\/messages$/);
    await page.getByRole('button', {name: /Counterpart c1/}).click();
    await expect(page.getByTestId('message-body')).toHaveText(['hi there']);
    await expect(page.getByTestId('conversation-name')).toBeHidden();
    await page.getByRole('button', {name: 'Back to conversations'}).click();
    await expect(page.getByTestId('conversation-name')).toBeVisible();
  });
});

test.describe('polling', () => {
  test('an open thread refreshes every 10 s while visible and pauses while hidden', async ({page}) => {
    await page.clock.install();
    const state = await mockApi(page, 'employer', {conversations: [conversation('c1')], threads: {c1: [{id: 'm1', senderId: 'other', body: 'first', createdAt: at(1), readAt: null}]}});
    await page.goto('/employer/messages?c=c1');
    await expect(page.getByTestId('message-body')).toHaveText(['first']);

    state.threads.c1.push({id: 'm2', senderId: 'other', body: 'arrived later', createdAt: at(2), readAt: null});
    await page.clock.fastForward(10_500);
    await expect(page.getByTestId('message-body')).toHaveText(['first', 'arrived later']);

    // Hidden tab: no polling.
    await page.evaluate(() => { Object.defineProperty(document, 'visibilityState', {configurable: true, get: () => 'hidden'}); document.dispatchEvent(new Event('visibilitychange')); });
    const before = state.calls.filter(c => c === 'GET /conversations/c1/messages').length;
    state.threads.c1.push({id: 'm3', senderId: 'other', body: 'while hidden', createdAt: at(3), readAt: null});
    await page.clock.fastForward(35_000);
    expect(state.calls.filter(c => c === 'GET /conversations/c1/messages').length).toBe(before);
    await expect(page.getByTestId('message-body')).toHaveCount(2);

    // Visible again: refreshes immediately.
    await page.evaluate(() => { Object.defineProperty(document, 'visibilityState', {configurable: true, get: () => 'visible'}); document.dispatchEvent(new Event('visibilitychange')); });
    await expect(page.getByTestId('message-body')).toHaveText(['first', 'arrived later', 'while hidden']);
  });

  test('navigation badges poll unread counts every 30 s', async ({page}) => {
    await page.clock.install();
    const state = await mockApi(page, 'jobseeker', {notifications: []});
    await page.goto('/jobseeker/notifications');
    await expect(page.getByTestId('notifications-empty')).toBeVisible();
    await expect(page.getByTestId('unread-notifications-badge')).toBeHidden();

    state.unread = 2; state.unreadMessages = 4;
    await page.clock.fastForward(29_000);
    await expect(page.getByTestId('unread-notifications-badge')).toBeHidden();
    await page.clock.fastForward(2_000);
    await expect(page.getByTestId('unread-notifications-badge')).toHaveText('2');
    await expect(page.getByTestId('unread-messages-badge').first()).toHaveText('4');
    await expect(page.getByRole('link', {name: 'Notifications, 2 unread'})).toBeVisible();
  });
});

test.describe('notifications', () => {
  const kinds = [
    {id: 'n1', type: 'message', link: '/messages?c=abc', jobseeker: '/jobseeker/messages?c=abc', employer: '/employer/messages?c=abc'},
    {id: 'n2', type: 'booking', link: '/bookings', jobseeker: '/jobseeker/bookings', employer: '/employer/bookings'},
    {id: 'n3', type: 'booking_quote', link: '/bookings', jobseeker: '/jobseeker/bookings', employer: '/employer/bookings'},
    {id: 'n4', type: 'booking_status', link: '/bookings', jobseeker: '/jobseeker/bookings', employer: '/employer/bookings'},
    {id: 'n5', type: 'application', link: '/hiring/applicants', jobseeker: '/jobseeker/hiring/applicants', employer: '/employer/applications'},
    {id: 'n6', type: 'application_status', link: '/jobseeker/applications', jobseeker: '/jobseeker/applications', employer: '/employer'},
    {id: 'n7', type: 'urgent_response', link: '/urgent-requests', jobseeker: '/jobseeker/urgent', employer: '/employer/urgent'},
    {id: 'n8', type: 'job_alert', link: '/jobseeker/jobs/j1', jobseeker: '/jobseeker/jobs/j1', employer: '/employer/jobs/j1'},
    {id: 'n9', type: 'job_alert', link: '/jobs/j2', jobseeker: '/jobseeker/jobs/j2', employer: '/employer/jobs/j2'},
    {id: 'n10', type: 'moderation', link: '/employer', jobseeker: '/jobseeker/hiring/applicants', employer: '/employer'},
    {id: 'n11', type: 'verification', link: null, jobseeker: '/jobseeker/profile', employer: '/employer/profile'},
    {id: 'n12', type: 'workspace', link: null, jobseeker: '/jobseeker/workspace', employer: '/employer/workspace'},
  ];
  const items = kinds.map((k, i) => ({id: k.id, type: k.type, title: `Title ${k.id}`, body: `Body ${k.type}`, link: k.link, readAt: null, createdAt: at(30 - i)}));

  for (const role of ['jobseeker', 'employer'] as const) {
    test(`every notification kind links to a ${role} route`, async ({page}) => {
      await mockApi(page, role, {notifications: structuredClone(items)});
      await page.goto(`/${role}/notifications`);
      const cards = page.getByTestId('notification');
      await expect(cards).toHaveCount(kinds.length);
      for (const [index, kind] of kinds.entries()) {
        await expect(cards.nth(index).getByRole('link', {name: 'Open'}), `${kind.type} ${kind.link}`).toHaveAttribute('href', kind[role]);
      }
    });
  }

  test('open marks read, mark one and mark all read, and the empty state', async ({page}) => {
    const state = await mockApi(page, 'employer', {notifications: structuredClone(items.slice(0, 3))});
    await page.goto('/employer/notifications');
    const cards = page.getByTestId('notification');
    await cards.nth(0).getByRole('button', {name: 'Mark as read'}).click();
    await expect(cards.nth(0)).toHaveAttribute('data-read', 'true');
    expect(state.patched).toEqual(['n1']);

    await page.getByRole('button', {name: 'Mark all as read'}).click();
    await expect(page.locator('[data-testid="notification"][data-read="false"]')).toHaveCount(0);
    expect(state.readAll).toBe(1);
    await expect(page.getByRole('button', {name: 'Mark all as read'})).toBeHidden();

    state.notifications = structuredClone(items.slice(1, 2));
    await page.reload();
    await page.getByTestId('notification').getByRole('link', {name: 'Open'}).click();
    await expect(page).toHaveURL(/\/employer\/bookings$/);
    expect(state.patched).toContain('n2');

    state.notifications = [];
    await page.goto('/employer/notifications');
    await expect(page.getByTestId('notifications-empty')).toContainText('all caught up');
  });
});

test.describe('email notification preference', () => {
  test('the labelled switch reads, saves and rolls back the preference', async ({page}) => {
    const state = await mockApi(page, 'jobseeker');
    state.emailNotifications = false;
    await page.goto('/jobseeker/notifications');
    const toggle = page.getByRole('switch', {name: 'Email me about messages, bookings and application updates'});
    await expect(toggle).toHaveAttribute('aria-checked', 'false');
    await expect(toggle).toBeEnabled();

    await toggle.click();
    await expect(toggle).toHaveAttribute('aria-checked', 'true');
    expect(state.preferenceWrites).toEqual([true]);

    state.preferenceStatus = 503;
    await toggle.press('Space');
    await expect.poll(() => state.preferenceWrites).toEqual([true, false]);
    await expect(toggle).toHaveAttribute('aria-checked', 'true');
    await expect(page.getByText('Service unavailable')).toBeVisible();
  });

  test('the unsubscribe page turns emails off without signing in and explains bad links', async ({page}) => {
    const state = await mockApi(page, 'jobseeker');
    await page.addInitScript(() => localStorage.removeItem('verse_access_token'));
    await page.goto('/unsubscribe?token=good-token');
    await expect(page.getByTestId('unsubscribe-status')).toContainText('won’t get emails about messages, bookings or application updates');
    expect(state.unsubscribeTokens).toEqual(['good-token']);
    await expect(page).toHaveURL(/\/unsubscribe\?token=good-token$/);

    await page.goto('/unsubscribe?token=tampered');
    await expect(page.getByTestId('unsubscribe-status')).toContainText('invalid or incomplete');

    await page.goto('/unsubscribe');
    await expect(page.getByTestId('unsubscribe-status')).toContainText('invalid or incomplete');
    expect(state.unsubscribeTokens).toEqual(['good-token', 'tampered']);
  });
});
