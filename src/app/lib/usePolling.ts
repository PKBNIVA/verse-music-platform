import {useEffect, useRef} from 'react';

/** Fired after the viewer reads messages or notifications so badges refresh without waiting for the next poll. */
export const UNREAD_CHANGED_EVENT = 'verse:unread-changed';
export const announceUnreadChanged = () => {
  try { window.dispatchEvent(new Event(UNREAD_CHANGED_EVENT)); } catch { /* non-browser */ }
};

const isVisible = () => typeof document === 'undefined' || document.visibilityState !== 'hidden';

/**
 * Calls `tick` every `intervalMs` while the tab is visible (Page Visibility API).
 * Hidden tabs do not poll; becoming visible again polls immediately and restarts the timer.
 * `tick` is read from a ref, so callers may pass an inline function. Pass `enabled=false` to pause.
 */
export function useVisiblePolling(tick: () => unknown, intervalMs: number, enabled = true) {
  const tickRef = useRef(tick);
  tickRef.current = tick;
  useEffect(() => {
    if (!enabled) return;
    let timer: ReturnType<typeof setInterval> | undefined;
    const run = () => { try { void tickRef.current(); } catch { /* a failed poll waits for the next tick */ } };
    const start = () => { if (!timer) timer = setInterval(() => { if (isVisible()) run(); }, intervalMs); };
    const stop = () => { if (timer) { clearInterval(timer); timer = undefined; } };
    const onVisibility = () => { if (isVisible()) { run(); start(); } else stop(); };
    if (isVisible()) start();
    document.addEventListener('visibilitychange', onVisibility);
    return () => { stop(); document.removeEventListener('visibilitychange', onVisibility); };
  }, [intervalMs, enabled]);
}
