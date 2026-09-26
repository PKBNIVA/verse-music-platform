// Removes personal data and credentials from anything sent to the error tracker.
// Dependency-free so it can be unit-tested directly (tests/frontend-monitoring-smoke.mjs).

export const FILTERED = '[Filtered]';
const EMAIL = /[A-Za-z0-9._%+-]+(?:@|%40)[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}/gi; // also URL-encoded (%40)
const AUTH_SCHEME = /\b(Bearer|Basic|Token)\s+[A-Za-z0-9\-._~+/=]+/gi;
// ?token=…, &code=…, &signature=… in URLs, query strings and free text.
const QUERY_SECRET = /((?:^|[?&;#\s"'])[\w\-[\]]*(?:token|code|otp|secret|signature|password|email|key)[\w\-[\]]*=)[^&#\s"'<>]*/gi;
const SENSITIVE_KEY = /pass(word|wd)?|token|secret|signature|otp|authorization|cookie|api[_-]?key|access[_-]?key|credential|session|email|^(code|body|dsn)$/i;
const MAX_DEPTH = 12;

export function scrubString(value: string, secrets: readonly string[] = []): string {
  let out = value;
  for (const secret of secrets) {
    if (secret && secret.length >= 8) out = out.split(secret).join(FILTERED);
  }
  return out
    .replace(AUTH_SCHEME, `$1 ${FILTERED}`)
    .replace(QUERY_SECRET, `$1${FILTERED}`)
    .replace(EMAIL, '[email]');
}

export function isSensitiveKey(key: string) {
  return SENSITIVE_KEY.test(key);
}

export function scrubValue<T>(value: T, secrets: readonly string[] = [], depth = 0): T {
  if (depth > MAX_DEPTH) return FILTERED as unknown as T;
  if (typeof value === 'string') return scrubString(value, secrets) as unknown as T;
  if (Array.isArray(value)) return value.map(item => scrubValue(item, secrets, depth + 1)) as unknown as T;
  if (value && typeof value === 'object' && Object.getPrototypeOf(value) === Object.prototype) {
    const clean: Record<string, unknown> = {};
    for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
      clean[key] = isSensitiveKey(key) ? FILTERED : scrubValue(item, secrets, depth + 1);
    }
    return clean as T;
  }
  return value;
}

type ScrubbableEvent = { user?: Record<string, unknown> | null; request?: { cookies?: unknown; data?: unknown } | null; [key: string]: unknown };

/** Scrubs a whole Sentry event (or transaction) and keeps only an id/role user. */
export function scrubEvent<T extends ScrubbableEvent>(event: T, secrets: readonly string[] = []): T {
  const clean = scrubValue(event, secrets) as T;
  if (clean.user) {
    const { id, role } = clean.user as Record<string, unknown>;
    clean.user = id === undefined && role === undefined ? undefined : { ...(id === undefined ? {} : { id }), ...(role === undefined ? {} : { role }) };
  }
  if (clean.request) {
    delete clean.request.cookies;
    delete clean.request.data;
  }
  return clean;
}
