// Loaded on demand by monitoring.ts, only when VITE_SENTRY_DSN is set.
import { addIntegration, captureException, captureMessage, init, withScope } from '@sentry/react';
import { allowSampled, classifyError, type ReportContext } from './monitoring';
import { scrubEvent, scrubString, scrubValue } from './sentryScrub';

type InitOptions = { dsn: string; release: string; environment: string; tracesSampleRate: number };

// The bearer token must never leave the browser, even if some message happens to include it.
function secrets(): string[] {
  const found: string[] = [];
  for (const store of ['localStorage', 'sessionStorage'] as const) {
    try {
      const token = window[store].getItem('verse_access_token');
      if (token) found.push(token);
    } catch { /* storage blocked */ }
  }
  return found;
}

export function initSentry(options: InitOptions) {
  init({
    dsn: options.dsn,
    release: options.release || undefined,
    environment: options.environment,
    sendDefaultPii: false,
    tracesSampleRate: options.tracesSampleRate,
    // Session replay stays off (privacy and cost); tracing is added below only when a rate is configured.
    replaysSessionSampleRate: 0,
    replaysOnErrorSampleRate: 0,
    maxBreadcrumbs: 40,
    beforeSend(event, hint) {
      const verdict = classifyError(hint?.originalException);
      if (verdict.action === 'ignore') return null;
      if (verdict.action === 'sample' && !allowSampled(verdict.key)) return null;
      return scrubEvent(event as any, secrets()) as typeof event;
    },
    // Spans (only when tracing is on) carry URLs in their names and attributes.
    beforeSendSpan(span: any) {
      return scrubValue(span, secrets());
    },
    beforeBreadcrumb(breadcrumb) {
      const tokens = secrets();
      if (breadcrumb.message) breadcrumb.message = scrubString(breadcrumb.message, tokens);
      if (breadcrumb.data) {
        for (const key of ['url', 'from', 'to']) {
          const value = breadcrumb.data[key];
          if (typeof value === 'string') breadcrumb.data[key] = scrubString(value, tokens);
        }
      }
      return breadcrumb;
    },
  });
  // Performance tracing is its own chunk so error-only builds (the default) never download it.
  if (options.tracesSampleRate > 0) {
    void import('./sentryTracing').then(module => addIntegration(module.browserTracingIntegration())).catch(() => undefined);
  }
}

function applyContext(scope: Parameters<Parameters<typeof withScope>[0]>[0], context?: ReportContext) {
  if (!context) return;
  if (context.level) scope.setLevel(context.level);
  if (context.tags) scope.setTags(context.tags);
  if (context.extra) scope.setExtras(context.extra);
  if (context.fingerprint) scope.setFingerprint(context.fingerprint);
}

export function captureError(error: unknown, context?: ReportContext): string {
  return withScope(scope => {
    applyContext(scope, context);
    return captureException(error);
  });
}

export function captureText(message: string, context?: ReportContext): string {
  return withScope(scope => {
    applyContext(scope, context);
    return captureMessage(message);
  });
}
