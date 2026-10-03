import { expect, test, type BrowserContext, type Page, type Route, type WebSocketRoute } from '@playwright/test';

// R2 live delivery: two people in two browser contexts, one Action Cable stand-in (Playwright's
// WebSocket routing speaks the Action Cable protocol). A message the hirer sends appears in the
// musician's open thread from the live update, well before the 30 s safety poll, exactly once.
test.skip(Boolean(process.env.QA_BASE_URL) || process.env.QA_INTEGRATION === 'true', 'Uses local API fixtures only.');

type Msg = { id: string; senderId: string; body: string; createdAt: string; readAt: string | null };
const thread: Msg[] = [];
const sockets = new Set<{ ws: WebSocketRoute; identifiers: Set<string> }>();
const calls: string[] = [];

/** The cable stand-in: welcome, confirm every subscription, and broadcast to subscribers of a stream. */
async function routeCable(context: BrowserContext) {
  await context.routeWebSocket('**/cable**', (ws) => {
    const socket = { ws, identifiers: new Set<string>() };
    sockets.add(socket);
    ws.send(JSON.stringify({ type: 'welcome' }));
    ws.onMessage((raw) => {
      const { command, identifier } = JSON.parse(String(raw));
      if (command === 'subscribe') {
        socket.identifiers.add(identifier);
        ws.send(JSON.stringify({ identifier, type: 'confirm_subscription' }));
      }
    });
    ws.onClose(() => sockets.delete(socket));
  });
}

function broadcast(channel: string, params: Record<string, string>, message: Record<string, unknown>) {
  const identifier = JSON.stringify({ channel, ...params });
  sockets.forEach((socket) => {
    if (socket.identifiers.has(identifier)) socket.ws.send(JSON.stringify({ identifier, message }));
  });
}

async function signIn(context: BrowserContext, me: string, role: 'jobseeker' | 'employer', live = true) {
  await context.addInitScript((r) => {
    localStorage.setItem('musilynk_access_token', `qa-${r}`);
    localStorage.setItem(`musilynk-tour-v2-${r}`, 'done');
  }, role);
  const json = (route: Route, body: unknown, status = 200) =>
    route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });
  await context.route('**/api/**', (route) => {
    const request = route.request();
    const path = new URL(request.url()).pathname.replace(/^\/api/, '');
    calls.push(`${role} ${request.method()} ${path}`);
    if (path === '/me')
      return json(route, {
        user: { id: me, name: me, email: `${me}@example.invalid`, role, status: 'active', profileComplete: true },
        // The API says it offers live updates; without this the app only polls (and never asks for a ticket).
        realtime: true,
      });
    if (path === '/cable/ticket')
      return json(route, { ticket: `ticket-${role}`, expiresIn: 60, url: 'wss://cable.test/cable' }, 201);
    if (path === '/notifications/unread') return json(route, { unread: 0, unreadMessages: 0 });
    if (path === '/conversations')
      return json(route, {
        conversations: [
          {
            id: 'c1',
            counterpartName: role === 'employer' ? 'Musician' : 'Hirer',
            viewerSide: role === 'employer' ? 'employer' : 'candidate',
            lastMessage: thread.at(-1)?.body ?? '',
            lastMessageFromMe: false,
            unreadCount: 0,
          },
        ],
      });
    if (path === '/conversations/c1/messages') {
      if (request.method() === 'POST') {
        const message = {
          id: `m${thread.length + 1}`,
          senderId: me,
          body: request.postDataJSON().body,
          createdAt: new Date().toISOString(),
          readAt: null,
        };
        thread.push(message);
        // What the server does after the commit (Realtime.message_created).
        broadcast('ConversationChannel', { id: 'c1' }, { type: 'message', id: message.id, conversationId: 'c1' });
        return json(route, { message }, 201);
      }
      return json(route, { messages: thread, truncated: false, limit: 200 });
    }
    return json(route, {});
  });
  if (live) await routeCable(context);
  // The socket is refused (no cable on the API, or a network that drops WebSockets).
  else await context.routeWebSocket('**/cable**', (ws) => ws.close({ code: 1011, reason: 'refused' }));
}

async function open(context: BrowserContext, path: string): Promise<Page> {
  const page = await context.newPage();
  await page.goto(path);
  return page;
}

test('a message sent in one browser appears live in the other, once', async ({
  browser,
  isMobile,
  viewport,
  userAgent,
}) => {
  thread.length = 0;
  calls.length = 0;
  thread.push({
    id: 'm0',
    senderId: 'musician',
    body: 'Hi, still need a drummer?',
    createdAt: new Date(Date.now() - 60_000).toISOString(),
    readAt: null,
  });
  const device = { isMobile, viewport, userAgent: userAgent ?? undefined, hasTouch: isMobile };
  const hirer = await browser.newContext(device);
  const musician = await browser.newContext(device);
  await signIn(hirer, 'hirer', 'employer');
  await signIn(musician, 'musician', 'jobseeker');

  const musicianPage = await open(musician, '/jobseeker/messages?c=c1');
  await expect(musicianPage.getByTestId('message-body')).toHaveText(['Hi, still need a drummer?']);
  // The thread is subscribed: from here on the musician's page polls only every 30 s.
  await expect.poll(() => [...sockets].some((s) => [...s.identifiers].some((i) => i.includes('"c1"')))).toBe(true);
  const threadFetches = () => calls.filter((c) => c === 'jobseeker GET /conversations/c1/messages').length;
  const before = threadFetches();

  const hirerPage = await open(hirer, '/employer/messages?c=c1');
  const box = hirerPage.getByLabel('Message', { exact: true });
  await box.fill('Yes! Soundcheck at 6?');
  await box.press('Enter');

  await expect(musicianPage.getByTestId('message-body')).toHaveText(
    ['Hi, still need a drummer?', 'Yes! Soundcheck at 6?'],
    {
      timeout: 5_000,
    },
  );
  expect(threadFetches() - before).toBe(1);
  // A later poll or a repeated broadcast of the same message never shows it twice.
  broadcast('ConversationChannel', { id: 'c1' }, { type: 'message', id: 'm2', conversationId: 'c1' });
  await expect.poll(threadFetches).toBe(before + 2);
  await expect(musicianPage.getByTestId('message-body')).toHaveCount(2);

  await hirer.close();
  await musician.close();
});

test('with no live connection the thread keeps polling at the usual pace', async ({ browser }) => {
  thread.length = 0;
  calls.length = 0;
  thread.push({
    id: 'm0',
    senderId: 'hirer',
    body: 'Are you free Friday?',
    createdAt: new Date().toISOString(),
    readAt: null,
  });
  const musician = await browser.newContext();
  await signIn(musician, 'musician', 'jobseeker', false);
  const page = await open(musician, '/jobseeker/messages?c=c1');
  await expect(page.getByTestId('message-body')).toHaveText(['Are you free Friday?']);
  thread.push({ id: 'm1', senderId: 'hirer', body: 'Polled in', createdAt: new Date().toISOString(), readAt: null });
  await expect(page.getByTestId('message-body')).toHaveText(['Are you free Friday?', 'Polled in'], { timeout: 6_000 });
  await musician.close();
});
