export const API_BASE = (import.meta as any).env?.VITE_API_URL || '/api';

const DEFAULT_TIMEOUT_MS = 12_000;
const MIN_RETRY_ATTEMPT_MS = 250;
const RETRYABLE_GET_STATUSES = new Set([429, 502, 503, 504]);
let authRedirectStarted = false;
const TOKEN_KEY = 'verse_access_token';
const RETURN_TO_KEY = 'verse_return_to';
type StoreKind = 'local' | 'session';
// The access token lives in localStorage so new tabs, email links and browser
// restarts keep the session; the return-to path stays per tab in sessionStorage.
// Browsers that block site data throw on storage access; keep the session
// usable for this page load instead of failing every request.
const memoryStore = new Map<string, string>();
// A store whose writes failed (blocked or full) is read from memory from then on,
// so a token saved only in memory is not hidden by a readable-but-stale store.
const unwritableStores = new Set<StoreKind>();

function storageFor(kind: StoreKind): Storage {
  return kind === 'local' ? localStorage : sessionStorage;
}

function readStored(kind: StoreKind, key: string) {
  const memoryKey = `${kind}:${key}`;
  if (unwritableStores.has(kind)) return memoryStore.get(memoryKey) ?? null;
  try {
    return storageFor(kind).getItem(key);
  } catch {
    return memoryStore.get(memoryKey) ?? null;
  }
}

function writeStored(kind: StoreKind, key: string, value: string | null) {
  const memoryKey = `${kind}:${key}`;
  if (value === null) memoryStore.delete(memoryKey);
  else memoryStore.set(memoryKey, value);
  try {
    if (value === null) storageFor(kind).removeItem(key);
    else storageFor(kind).setItem(key, value);
  } catch {
    // The in-memory copy above is the fallback.
    unwritableStores.add(kind);
  }
}

let legacyTokenChecked = false;

function readToken() {
  const token = readStored('local', TOKEN_KEY);
  if (token || legacyTokenChecked) return token;
  // Sessions created before the token moved to localStorage live in this tab's
  // sessionStorage; move such a token across once so the user stays signed in.
  legacyTokenChecked = true;
  const legacy = readStored('session', TOKEN_KEY);
  if (!legacy) return null;
  writeStored('local', TOKEN_KEY, legacy);
  writeStored('session', TOKEN_KEY, null);
  return legacy;
}

function writeToken(token: string | null) {
  legacyTokenChecked = true;
  writeStored('local', TOKEN_KEY, token);
  // Never leave a legacy copy behind that could resurrect a signed-out session.
  writeStored('session', TOKEN_KEY, null);
}

class RequestDeadlineError extends Error {
  constructor() {
    super('Request deadline exceeded');
    this.name = 'AbortError';
  }
}

export type ApiOptions = RequestInit & { timeoutMs?: number; skipAuthRedirect?: boolean };

export class ApiError extends Error {
  status: number;
  code?: string;
  requestId?: string;

  constructor(message: string, status: number, code?: string, requestId?: string) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    this.requestId = requestId;
  }
}

function requestIdFor(response: Response, data?: any) {
  return response.headers.get('x-request-id') || data?.requestId || data?.request_id;
}

function redirectAfterUnauthorized(path: string, rejectedToken: string | null, skipRedirect = false) {
  const currentToken = readToken();
  // Another tab may have signed in again while this request was in flight; only the
  // session the server rejected may be cleared, never a newer one.
  if (currentToken !== rejectedToken) return;
  const hadSession = Boolean(currentToken);
  setAccessToken(null);
  if (!hadSession || skipRedirect || path.startsWith('/auth/') || authRedirectStarted) return;

  const currentPath = `${window.location.pathname}${window.location.search}`;
  if (!/^\/(jobseeker|employer|admin)(\/|$)/.test(window.location.pathname)) return;

  authRedirectStarted = true;
  writeStored('session', RETURN_TO_KEY, currentPath);
  const role = window.location.pathname.split('/')[1] || 'jobseeker';
  window.location.replace(`/auth/${role}`);
}

function retryDelay(response?: Response) {
  const retryAfter = response?.headers.get('retry-after');
  if (retryAfter) {
    const seconds = Number(retryAfter);
    if (Number.isFinite(seconds)) return Math.min(Math.max(seconds * 1_000, 0), 2_000);
    const retryAt = Date.parse(retryAfter);
    if (Number.isFinite(retryAt)) return Math.min(Math.max(retryAt - Date.now(), 0), 2_000);
  }
  return 200 + Math.floor(Math.random() * 201);
}

function wait(ms: number, signal?: AbortSignal | null) {
  return new Promise<void>((resolve, reject) => {
    if (signal?.aborted) return reject(signal.reason || new DOMException('Aborted', 'AbortError'));
    const onAbort = () => {
      window.clearTimeout(timer);
      reject(signal.reason || new DOMException('Aborted', 'AbortError'));
    };
    const timer = window.setTimeout(() => {
      signal?.removeEventListener('abort', onAbort);
      resolve();
    }, ms);
    signal?.addEventListener('abort', onAbort, { once: true });
  });
}

async function fetchWithTimeout(url: string, options: ApiOptions) {
  const { timeoutMs = DEFAULT_TIMEOUT_MS, signal: callerSignal, ...fetchOptions } = options;
  const controller = new AbortController();
  const abortFromCaller = () => controller.abort(callerSignal?.reason);
  callerSignal?.addEventListener('abort', abortFromCaller, { once: true });
  if (callerSignal?.aborted) abortFromCaller();
  const timer = window.setTimeout(() => controller.abort(new RequestDeadlineError()), timeoutMs);

  try {
    return await fetch(url, { ...fetchOptions, signal: controller.signal });
  } finally {
    window.clearTimeout(timer);
    callerSignal?.removeEventListener('abort', abortFromCaller);
  }
}

export async function api<T = any>(path: string, options: ApiOptions = {}): Promise<T> {
  const headers = new Headers(options.headers || {});
  if (options.body !== undefined && !(options.body instanceof FormData)) headers.set('Content-Type', 'application/json');
  const token = readToken();
  if (token) headers.set('Authorization', `Bearer ${token}`);

  const method = (options.method || 'GET').toUpperCase();
  const canRetry = method === 'GET';
  const { timeoutMs, skipAuthRedirect, signal, ...requestOptions } = options;
  const deadlineAt = Date.now() + (timeoutMs ?? DEFAULT_TIMEOUT_MS);
  let lastResponse: Response | undefined;

  for (let attempt = 0; attempt <= (canRetry ? 1 : 0); attempt += 1) {
    try {
      const remainingMs = Math.max(0, deadlineAt - Date.now());
      if (remainingMs === 0) throw new RequestDeadlineError();
      const response = await fetchWithTimeout(`${API_BASE}${path}`, {
        ...requestOptions, method, headers, credentials: 'omit', timeoutMs: remainingMs, signal,
      });
      lastResponse = response;

      if (canRetry && attempt === 0 && RETRYABLE_GET_STATUSES.has(response.status)) {
        const delayMs = retryDelay(response);
        if (deadlineAt - Date.now() >= delayMs + MIN_RETRY_ATTEMPT_MS) {
          await wait(delayMs, signal);
          continue;
        }
      }

      if (response.status === 204) return undefined as T;
      const data = await response.json().catch(() => ({}));
      const requestId = requestIdFor(response, data);
      if (response.status === 401) redirectAfterUnauthorized(path, token, skipAuthRedirect);
      if (!response.ok) throw new ApiError(data.error || `Request failed (${response.status})`, response.status, data.code, requestId);
      return data;
    } catch (error) {
      if (error instanceof ApiError) throw error;
      if (signal?.aborted) throw error;
      if (error instanceof RequestDeadlineError) {
        throw new ApiError('Request timed out. Please try again.', 0, 'REQUEST_TIMEOUT');
      }
      if (canRetry && attempt === 0) {
        const delayMs = retryDelay(lastResponse);
        if (deadlineAt - Date.now() >= delayMs + MIN_RETRY_ATTEMPT_MS) {
          await wait(delayMs, signal);
          continue;
        }
      }
      const timedOut = error instanceof DOMException && error.name === 'AbortError';
      throw new ApiError(
        timedOut ? 'Request timed out. Please try again.' : 'Network request failed. Check your connection and try again.',
        0,
        timedOut ? 'REQUEST_TIMEOUT' : 'NETWORK_ERROR',
      );
    }
  }

  throw new ApiError('Network request failed. Check your connection and try again.', 0, 'NETWORK_ERROR');
}

export function setAccessToken(token?: string | null) {
  if (token) {
    writeToken(token);
    authRedirectStarted = false;
  } else {
    writeToken(null);
  }
}

export function hasAccessToken() {
  return Boolean(readToken());
}

/**
 * Calls `listener` when another tab signs in or out. Storage events fire only in
 * the other tabs of this origin, so this tab's own writes never loop back.
 */
export function onAccessTokenChange(listener: (signedIn: boolean) => void) {
  const handler = (event: StorageEvent) => {
    // A null key means the other tab cleared all of localStorage.
    if (event.key !== null && event.key !== TOKEN_KEY) return;
    try {
      if (event.storageArea !== localStorage) return;
    } catch {
      return;
    }
    const token = event.key === null ? null : event.newValue;
    if (token) {
      memoryStore.set(`local:${TOKEN_KEY}`, token);
      authRedirectStarted = false;
    } else {
      memoryStore.delete(`local:${TOKEN_KEY}`);
    }
    listener(Boolean(token));
  };
  window.addEventListener('storage', handler);
  return () => window.removeEventListener('storage', handler);
}

/** Returns and clears the protected page saved before a forced sign-in. */
export function consumeReturnTo() {
  const path = readStored('session', RETURN_TO_KEY);
  writeStored('session', RETURN_TO_KEY, null);
  return path;
}

export const apiGet = <T = any>(path: string, options: ApiOptions = {}) => api<T>(path, { ...options, method: 'GET' });
export const apiPost = <T = any>(path: string, body?: unknown, options: ApiOptions = {}) => api<T>(path, { ...options, method: 'POST', body: JSON.stringify(body ?? {}) });
export const apiPut = <T = any>(path: string, body?: unknown, options: ApiOptions = {}) => api<T>(path, { ...options, method: 'PUT', body: JSON.stringify(body ?? {}) });
export const apiPatch = <T = any>(path: string, body?: unknown, options: ApiOptions = {}) => api<T>(path, { ...options, method: 'PATCH', body: JSON.stringify(body ?? {}) });
export const apiDelete = <T = any>(path: string, options: ApiOptions = {}) => api<T>(path, { ...options, method: 'DELETE' });

export async function uploadMedia(file: File, onProgress?: (pct: number) => void): Promise<{ url: string; metadata?: any; thumbnailUrl?: string; waveformUrl?: string }> {
  const prep = await apiPost<any>('/uploads/presign', { filename: file.name, contentType: file.type, size: file.size });
  if (prep.mode === 'direct') {
    const response = await fetchWithTimeout(prep.uploadUrl, {
      method: prep.method || 'PUT', headers: prep.headers || { 'Content-Type': file.type }, body: file, timeoutMs: 120_000,
    });
    if (!response.ok) throw new ApiError('Upload failed', response.status, undefined, requestIdFor(response));
    onProgress?.(100);
    return { url: prep.publicUrl || prep.url };
  }

  const token = readToken();
  const safeFilename = file.name.replace(/[^A-Za-z0-9_.-]/g, '_') || 'upload';
  const headers: Record<string, string> = { 'Content-Type': file.type, 'X-Filename': safeFilename };
  if (token) headers.Authorization = `Bearer ${token}`;
  const uploadUrl = prep.uploadUrl.startsWith('http') ? prep.uploadUrl : `${API_BASE.replace(/\/api\/?$/, '')}${prep.uploadUrl}`;
  const response = await fetchWithTimeout(uploadUrl, { method: 'PUT', headers, credentials: 'omit', body: file, timeoutMs: 120_000 });
  const data = response.status === 204 ? {} : await response.json().catch(() => ({}));
  const requestId = requestIdFor(response, data);
  if (response.status === 401) redirectAfterUnauthorized('/uploads/local', token);
  if (!response.ok) throw new ApiError(data.error || 'Upload failed', response.status, data.code, requestId);
  onProgress?.(100);
  return data;
}
