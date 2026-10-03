import { act, createElement } from 'react';
import { createRoot } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

type Callbacks = {
  connected?(): void;
  disconnected?(d: { willAttemptReconnect: boolean }): void;
  received?(data: unknown): void;
};
const cable = vi.hoisted(() => {
  const state = {
    urls: [] as string[],
    protocols: [] as string[][],
    created: [] as { params: Record<string, unknown>; callbacks: Callbacks; unsubscribe: ReturnType<typeof vi.fn> }[],
    connect: vi.fn(),
    disconnect: vi.fn(),
    urlFn: (() => '') as () => string,
  };
  return state;
});
vi.mock('@rails/actioncable', () => ({
  createConsumer: (url: () => string) => {
    cable.urlFn = url;
    const consumer = {
      subprotocols: [] as string[],
      connect: () => {
        cable.urls.push(cable.urlFn());
        cable.protocols.push(consumer.subprotocols);
        cable.connect();
      },
      disconnect: cable.disconnect,
      subscriptions: {
        create: (params: Record<string, unknown>, callbacks: Callbacks) => {
          const entry = { params, callbacks, unsubscribe: vi.fn() };
          cable.created.push(entry);
          return { unsubscribe: entry.unsubscribe };
        },
      },
    };
    return consumer;
  },
}));
vi.mock('../api', () => ({ apiPost: vi.fn() }));
import { apiPost } from '../api';
import { setRealtimeAvailable } from '../realtimeAvailability';
import {
  backoffDelay,
  CONNECTED_POLL_MS,
  realtimeStatus,
  resetRealtimeForTests,
  subscribe,
  useRealtimeInterval,
} from '../realtime';

globalThis.IS_REACT_ACT_ENVIRONMENT = true;
const flush = () =>
  act(async () => {
    for (let i = 0; i < 10; i++) await Promise.resolve();
  });

let ticket = 0;
beforeEach(() => {
  vi.useFakeTimers();
  cable.urls.length = 0;
  cable.protocols.length = 0;
  cable.created.length = 0;
  cable.connect.mockReset();
  cable.disconnect.mockReset();
  vi.mocked(apiPost).mockReset();
  vi.mocked(apiPost).mockImplementation(async () => ({ ticket: `t${++ticket}`, url: 'wss://api.example/cable' }));
  setRealtimeAvailable(true);
});
afterEach(() => {
  setRealtimeAvailable(false);
  resetRealtimeForTests();
  vi.useRealTimers();
});

describe('realtime', () => {
  it('asks for nothing until the API says it offers live updates, then opens for pages already listening', async () => {
    setRealtimeAvailable(false);
    subscribe('UserChannel', {}, vi.fn());
    await flush();
    expect(apiPost).not.toHaveBeenCalled();
    expect(realtimeStatus()).toBe('idle');
    setRealtimeAvailable(true);
    await flush();
    expect(apiPost).toHaveBeenCalledWith('/cable/ticket');
    setRealtimeAvailable(false);
    expect(realtimeStatus()).toBe('idle');
    expect(cable.disconnect).toHaveBeenCalled();
  });

  it('opens the socket with a fresh ticket on first subscribe and shares one subscription per channel', async () => {
    const a = vi.fn();
    const b = vi.fn();
    const offA = subscribe('ConversationChannel', { id: 'c1' }, a);
    const offB = subscribe('ConversationChannel', { id: 'c1' }, b);
    await flush();
    expect(apiPost).toHaveBeenCalledWith('/cable/ticket');
    expect(cable.urls[0]).toBe('wss://api.example/cable');
    expect(cable.protocols[0]).toEqual([expect.stringMatching(/^musilynk\.ticket\.t\d+$/)]);
    expect(cable.created).toHaveLength(1);
    expect(cable.created[0].params).toEqual({ channel: 'ConversationChannel', id: 'c1' });
    cable.created[0].callbacks.received?.({ type: 'message', id: 'm1' });
    expect(a).toHaveBeenCalledWith({ type: 'message', id: 'm1' });
    expect(b).toHaveBeenCalledWith({ type: 'message', id: 'm1' });
    offA();
    expect(cable.created[0].unsubscribe).not.toHaveBeenCalled();
    offB();
    expect(cable.created[0].unsubscribe).toHaveBeenCalled();
    expect(realtimeStatus()).toBe('idle');
  });

  it('reconnects after a drop with a new ticket and backoff, and polls at the usual pace meanwhile', async () => {
    subscribe('UserChannel', {}, vi.fn());
    await flush();
    cable.created[0].callbacks.connected?.();
    expect(realtimeStatus()).toBe('connected');

    cable.created[0].callbacks.disconnected?.({ willAttemptReconnect: true });
    expect(realtimeStatus()).toBe('disconnected');
    expect(cable.disconnect).toHaveBeenCalled();
    expect(cable.urls).toHaveLength(1);
    await act(async () => {
      vi.advanceTimersByTime(backoffDelay(0, () => 1));
    });
    await flush();
    expect(cable.urls).toHaveLength(2);
    expect(cable.protocols[1]).not.toEqual(cable.protocols[0]);
    expect(cable.protocols[1]).toHaveLength(1);
  });

  it('a failed ticket request retries with growing delays', async () => {
    vi.mocked(apiPost).mockRejectedValue(new Error('offline'));
    subscribe('UserChannel', {}, vi.fn());
    await flush();
    expect(realtimeStatus()).toBe('disconnected');
    expect(apiPost).toHaveBeenCalledTimes(1);
    await act(async () => {
      vi.advanceTimersByTime(1_200);
    });
    await flush();
    expect(apiPost).toHaveBeenCalledTimes(2);
    await act(async () => {
      vi.advanceTimersByTime(1_000);
    });
    expect(apiPost).toHaveBeenCalledTimes(2);
    expect(backoffDelay(10, () => 0)).toBe(30_000);
  });

  it('stretches polls to 30 s while connected and restores them when the socket drops', async () => {
    const seen: number[] = [];
    function Probe() {
      seen.push(useRealtimeInterval(3_000));
      return null;
    }
    const root = createRoot(document.createElement('div'));
    act(() => root.render(createElement(Probe)));
    expect(seen.at(-1)).toBe(3_000);
    subscribe('UserChannel', {}, vi.fn());
    await flush();
    act(() => cable.created[0].callbacks.connected?.());
    expect(seen.at(-1)).toBe(CONNECTED_POLL_MS);
    act(() => cable.created[0].callbacks.disconnected?.({ willAttemptReconnect: false }));
    expect(seen.at(-1)).toBe(3_000);
    act(() => root.unmount());
  });
});
