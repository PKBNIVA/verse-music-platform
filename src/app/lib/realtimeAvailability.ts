/**
 * Whether the signed-in API offers live updates (`realtime: true` on GET /me). Kept apart from
 * realtime.ts so the auth context can set it without pulling the real-time code into the entry.
 */
let available = false;
const listeners = new Set<(value: boolean) => void>();

export const realtimeAvailable = () => available;

export function setRealtimeAvailable(value: boolean) {
  if (available === value) return;
  available = value;
  listeners.forEach((listener) => listener(value));
}

export function onRealtimeAvailability(listener: (value: boolean) => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}
