// Split from sentryClient.ts: only loaded when VITE_SENTRY_TRACES_SAMPLE_RATE > 0.
export { browserTracingIntegration } from '@sentry/react';
