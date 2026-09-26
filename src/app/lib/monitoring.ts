// Client-side error reporting.
//
// Sentry is only loaded when VITE_SENTRY_DSN is set at build time, and then lazily after
// the first render (a separate chunk), so pages without a DSN never download it and the
// main bundle stays small. Errors raised before it loads are queued and sent once ready.
// Expected API errors (4xx) are never reported; 5xx/network failures are rate limited.

export type ReportLevel = 'error' | 'warning' | 'info';
export type ReportContext = {
  tags?: Record<string, string>;
  extra?: Record<string, unknown>;
  level?: ReportLevel;
  fingerprint?: string[];
};

type SentryClient = typeof import('./sentryClient');
type Pending = { kind: 'exception'; error: unknown; context?: ReportContext } | { kind: 'message'; message: string; context?: ReportContext };

const env = (import.meta as any).env || {};
export const SENTRY_DSN = String(env.VITE_SENTRY_DSN || '').trim();
export const RELEASE = String(env.VITE_RELEASE || '').trim();
const ENVIRONMENT = String(env.VITE_SENTRY_ENVIRONMENT || env.MODE || 'production').trim();
const TRACES_SAMPLE_RATE = Math.min(Math.max(Number(env.VITE_SENTRY_TRACES_SAMPLE_RATE) || 0, 0), 1);

const MAX_QUEUE = 20;
// At most one event per API failure kind (e.g. 503, NETWORK_ERROR) per window, and a
// small cap per page session, so an outage does not burn the monthly quota.
const BURST_WINDOW_MS = 5 * 60_000;
const MAX_SAMPLED_PER_SESSION = 5;
// A non-JSON success means a deployment misconfiguration (e.g. the SPA served for /api/*):
// one report per page session is enough.
const ONCE_PER_SESSION_CODES = new Set(['INVALID_RESPONSE']);

let client: SentryClient | null = null;
let loading: Promise<boolean> | null = null;
const queue: Pending[] = [];
const lastSampledAt = new Map<string, number>();
let sampledCount = 0;

export const monitoringEnabled = () => Boolean(SENTRY_DSN);
export const monitoringReady = () => client !== null;

type ErrorVerdict = { action: 'report' } | { action: 'ignore' } | { action: 'sample'; key: string };

/** Decides whether an error is worth reporting. Duck-typed to avoid importing api.ts. */
export function classifyError(error: unknown): ErrorVerdict {
  const candidate = error as { name?: string; status?: unknown; code?: unknown } | null;
  if (candidate && typeof candidate === 'object') {
    if (candidate.name === 'AbortError') return { action: 'ignore' };
    if (candidate.name === 'ApiError' && typeof candidate.status === 'number') {
      const status = candidate.status;
      const code = typeof candidate.code === 'string' ? candidate.code : '';
      if (ONCE_PER_SESSION_CODES.has(code)) return { action: 'sample', key: `api:${code}` };
      if (status >= 400 && status < 500) return { action: 'ignore' };
      if (code === 'UPLOAD_CANCELLED') return { action: 'ignore' };
      return { action: 'sample', key: `api:${status || code || 'unknown'}` };
    }
  }
  return { action: 'report' };
}

/** True when a rate-limited failure kind may be sent now (and records that it was). */
export function allowSampled(key: string, now = Date.now()) {
  if (sampledCount >= MAX_SAMPLED_PER_SESSION) return false;
  const last = lastSampledAt.get(key);
  const once = ONCE_PER_SESSION_CODES.has(key.replace(/^api:/, ''));
  if (last !== undefined && (once || now - last < BURST_WINDOW_MS)) return false;
  lastSampledAt.set(key, now);
  sampledCount += 1;
  return true;
}

function enqueue(item: Pending) {
  if (queue.length < MAX_QUEUE) queue.push(item);
}

export function reportError(error: unknown, context?: ReportContext) {
  if (!SENTRY_DSN) return;
  if (client) client.captureError(error, context);
  else enqueue({ kind: 'exception', error, context });
}

export function reportMessage(message: string, context?: ReportContext) {
  if (!SENTRY_DSN) return;
  if (client) client.captureText(message, context);
  else enqueue({ kind: 'message', message, context });
}

/** A failed API call the user saw (5xx, timeout, network). Reported sparingly. */
export function reportApiFailure(details: { status: number; code?: string; method: string; path: string; requestId?: string }) {
  if (!SENTRY_DSN) return;
  const once = ONCE_PER_SESSION_CODES.has(details.code || '');
  if (!once && details.status >= 400 && details.status < 500) return;
  // An offline device is the user's connection, not a Verse outage.
  if (details.code === 'NETWORK_ERROR' && typeof navigator !== 'undefined' && navigator.onLine === false) return;
  const kind = once ? String(details.code) : String(details.status || details.code || 'unknown');
  if (!allowSampled(`api:${kind}`)) return;
  const route = details.path.split('?')[0].replace(/\/(\d+|[0-9a-f]{8}-[0-9a-f-]{27,})(?=\/|$)/gi, '/:id');
  reportMessage(`API ${details.method} ${route} failed (${kind})`, {
    level: 'warning',
    tags: { source: 'api', apiStatus: String(details.status), apiCode: details.code || 'none' },
    extra: { requestId: details.requestId },
    fingerprint: ['api-failure', kind, details.method, route],
  });
}

function onEarlyError(event: ErrorEvent) {
  reportError(event.error ?? event.message, { tags: { source: 'window.onerror' } });
}

function onEarlyRejection(event: PromiseRejectionEvent) {
  reportError(event.reason, { tags: { source: 'unhandledrejection' } });
}

function stopEarlyCapture() {
  window.removeEventListener('error', onEarlyError);
  window.removeEventListener('unhandledrejection', onEarlyRejection);
}

function loadSentry(): Promise<boolean> {
  return import('./sentryClient')
    .then(module => {
      module.initSentry({ dsn: SENTRY_DSN, release: RELEASE, environment: ENVIRONMENT, tracesSampleRate: TRACES_SAMPLE_RATE });
      // Sentry's own global handlers take over from here.
      stopEarlyCapture();
      client = module;
      for (const item of queue.splice(0)) {
        if (item.kind === 'exception') module.captureError(item.error, item.context);
        else module.captureText(item.message, item.context);
      }
      return true;
    })
    .catch(() => {
      stopEarlyCapture();
      queue.length = 0;
      return false;
    });
}

/**
 * Starts error reporting. Without a DSN this does nothing at all. With one, early errors
 * are queued immediately and the Sentry chunk loads once the browser is idle.
 */
export function initMonitoring() {
  if (!SENTRY_DSN || loading || typeof window === 'undefined') return;
  window.addEventListener('error', onEarlyError);
  window.addEventListener('unhandledrejection', onEarlyRejection);
  loading = new Promise<boolean>(resolve => {
    const start = () => { void loadSentry().then(resolve); };
    const idle = (window as any).requestIdleCallback as ((cb: () => void, options?: { timeout: number }) => number) | undefined;
    if (idle) idle(start, { timeout: 2_000 });
    else window.setTimeout(start, 1_000);
  });
}

/** Resolves true once Sentry is loaded, false when it is disabled or failed to load. */
export function whenMonitoringReady(): Promise<boolean> {
  if (!SENTRY_DSN) return Promise.resolve(false);
  initMonitoring();
  return loading ?? Promise.resolve(false);
}

/** Admin check: sends a tagged client-side test error. Returns the event id, or null. */
export async function sendClientTestError(): Promise<string | null> {
  if (!(await whenMonitoringReady()) || !client) return null;
  return client.captureError(new Error('Verse Sentry client test error (triggered by an admin; safe to resolve)'), {
    tags: { source: 'admin_sentry_test', verse_test: 'true' },
  }) || null;
}
