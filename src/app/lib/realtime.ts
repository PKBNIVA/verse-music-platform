import { useEffect, useRef, useSyncExternalStore } from 'react';
import { apiPost } from './api';
import { onRealtimeAvailability, realtimeAvailable } from './realtimeAvailability';

/**
 * Live updates over Action Cable (`/cable` on the API). Payloads are ids and states only; callers
 * refetch from the API as they did when polling, so authorisation stays in the endpoints.
 *
 * Polling stays the fallback: while the socket is connected, `useRealtimeInterval` stretches a
 * poll to CONNECTED_POLL_MS; when it drops, polls return to their usual intervals at once.
 *
 * The socket opens with a short-lived, single-use ticket from POST /api/cable/ticket, sent as a
 * WebSocket subprotocol (WebSockets cannot send the bearer token, and URLs are logged). After a drop, a fresh ticket is fetched and the socket reopened with backoff
 * (1 s, 2 s, 4 s ... up to 30 s, with jitter). The socket closes when nothing is subscribed (for
 * example after sign-out), and @rails/actioncable is loaded only when something subscribes and
 * the API has said it offers live updates (`realtime: true` on GET /me); until then pages poll.
 */

export const CONNECTED_POLL_MS = 30_000;
/** Subprotocol prefix that carries the ticket (RealtimeTicket::PROTOCOL_PREFIX on the API). */
export const TICKET_PROTOCOL = 'musilynk.ticket.';
export const BACKOFF_START_MS = 1_000;
export const BACKOFF_MAX_MS = 30_000;

export type RealtimeStatus = 'idle' | 'connecting' | 'connected' | 'disconnected';
export interface RealtimeEvent {
  type: string;
  id?: string;
  conversationId?: string;
  status?: string;
  matchStatus?: string;
}
type ChannelName = 'UserChannel' | 'ConversationChannel' | 'UrgentRequestChannel';
type Listener = (event: RealtimeEvent) => void;
type Consumer = import('@rails/actioncable').Consumer;
type Subscription = import('@rails/actioncable').Subscription;
/** One server subscription per channel and params, shared by every listener on it. */
interface Entry {
  channel: ChannelName;
  params: Record<string, string>;
  listeners: Set<Listener>;
  subscription?: Subscription;
}

let status: RealtimeStatus = 'idle';
let consumer: Consumer | null = null;
let socketUrl = '';
let attempts = 0;
let retryTimer: ReturnType<typeof setTimeout> | undefined;
let generation = 0;
const entries = new Map<string, Entry>();
const statusListeners = new Set<() => void>();

function setStatus(next: RealtimeStatus) {
  if (status === next) return;
  status = next;
  statusListeners.forEach((notify) => notify());
}

export const realtimeStatus = () => status;

/** Delay before reconnect attempt `n` (0-based): doubling from 1 s, capped at 30 s, plus up to 20% jitter. */
export function backoffDelay(n: number, random = Math.random) {
  const base = Math.min(BACKOFF_MAX_MS, BACKOFF_START_MS * 2 ** n);
  return Math.round(base * (1 + random() * 0.2));
}

function attach(entry: Entry) {
  if (!consumer || entry.subscription) return;
  entry.subscription = consumer.subscriptions.create(
    { channel: entry.channel, ...entry.params },
    {
      connected: () => {
        attempts = 0;
        setStatus('connected');
      },
      disconnected: () => dropped(),
      received: (data) => {
        if (data && typeof data === 'object') entry.listeners.forEach((listener) => listener(data as RealtimeEvent));
      },
    },
  );
}

/** The socket dropped (or was refused): stop the library's own retries and reconnect with a fresh ticket. */
function dropped() {
  if (status === 'disconnected' || status === 'idle') return;
  setStatus('disconnected');
  consumer?.disconnect();
  scheduleReconnect();
}

function scheduleReconnect() {
  if (retryTimer || entries.size === 0) return;
  retryTimer = setTimeout(() => {
    retryTimer = undefined;
    void open();
  }, backoffDelay(attempts++));
}

async function open() {
  if (entries.size === 0 || !realtimeAvailable()) return;
  const mine = ++generation;
  setStatus('connecting');
  try {
    const [{ ticket, url }, cable] = await Promise.all([
      apiPost<{ ticket: string; url: string }>('/cable/ticket'),
      import('@rails/actioncable'),
    ]);
    if (mine !== generation || entries.size === 0) return;
    // An API without the cable (or a stub that answers {}) leaves the app on polling.
    if (!ticket || !url) throw new Error('No real-time ticket');
    socketUrl = url;
    if (!consumer) {
      consumer = cable.createConsumer(() => socketUrl);
      entries.forEach((entry) => attach(entry));
    }
    // The single-use ticket rides as a WebSocket subprotocol, never in the URL (URLs get logged).
    consumer.subprotocols = [`${TICKET_PROTOCOL}${ticket}`];
    consumer.connect();
  } catch {
    if (mine !== generation) return;
    setStatus('disconnected');
    scheduleReconnect();
  }
}

function close() {
  generation++;
  if (retryTimer) clearTimeout(retryTimer);
  retryTimer = undefined;
  attempts = 0;
  consumer?.disconnect();
  consumer = null;
  entries.forEach((entry) => {
    entry.subscription = undefined;
  });
  setStatus('idle');
}

// Signing in to an API with live updates opens the socket for pages already listening; signing
// out (or an API without them) closes it and leaves those pages polling.
onRealtimeAvailability((available) => {
  if (!available) close();
  else if (entries.size && status === 'idle') void open();
});

/** Listens to a channel until the returned function is called. Opens the socket on first use. */
export function subscribe(channel: ChannelName, params: Record<string, string>, listener: Listener) {
  const key = JSON.stringify([channel, params]);
  let entry = entries.get(key);
  if (!entry) {
    entry = { channel, params, listeners: new Set() };
    entries.set(key, entry);
    if (consumer) attach(entry);
    else if (status === 'idle' && realtimeAvailable()) void open();
  }
  entry.listeners.add(listener);
  const mine = entry;
  return () => {
    mine.listeners.delete(listener);
    if (mine.listeners.size) return;
    mine.subscription?.unsubscribe();
    entries.delete(key);
    if (entries.size === 0) close();
  };
}

/** Subscribes while mounted (and `params` is not null); `onEvent` may change between renders. */
export function useRealtime(channel: ChannelName, params: Record<string, string> | null, onEvent: Listener) {
  const handler = useRef(onEvent);
  handler.current = onEvent;
  const key = params ? JSON.stringify(params) : '';
  useEffect(() => {
    if (!key) return;
    return subscribe(channel, JSON.parse(key) as Record<string, string>, (event) => handler.current(event));
  }, [channel, key]);
}

export function useRealtimeStatus() {
  return useSyncExternalStore(
    (notify) => {
      statusListeners.add(notify);
      return () => statusListeners.delete(notify);
    },
    realtimeStatus,
    realtimeStatus,
  );
}

/** A polling interval: `fallbackMs` normally, stretched to CONNECTED_POLL_MS while the socket is live. */
export function useRealtimeInterval(fallbackMs: number) {
  return useRealtimeStatus() === 'connected' ? Math.max(fallbackMs, CONNECTED_POLL_MS) : fallbackMs;
}

/** Test hook: forget all state. */
export function resetRealtimeForTests() {
  entries.clear();
  close();
}
