/*
 * Waits until the page has put its first frame on screen, so the host shows a
 * window only once it has something to show. A frame callback runs just
 * before the browser paints, so the second one runs after the first frame was
 * painted. A hidden window may never run frame callbacks, so a timeout calls
 * back anyway: a window that is late to paint still appears.
 */

/* Long enough for a slow first frame, short enough that a stalled one is barely noticed. */
export const FIRST_PAINT_TIMEOUT_MS = 1000;

/* The few timing functions it needs, so tests can drive them. */
export interface FrameClock {
  requestAnimationFrame(callback: () => void): number;
  cancelAnimationFrame(handle: number): void;
  setTimeout(callback: () => void, ms: number): number;
  clearTimeout(handle: number): void;
}

const browserClock: FrameClock = {
  requestAnimationFrame: (callback) => window.requestAnimationFrame(callback),
  cancelAnimationFrame: (handle) => window.cancelAnimationFrame(handle),
  setTimeout: (callback, ms) => window.setTimeout(callback, ms),
  clearTimeout: (handle) => window.clearTimeout(handle),
};

/* Calls `callback` once, after the first painted frame or the timeout, whichever comes first. The returned function cancels it. */
export function afterFirstPaint(callback: () => void, clock: FrameClock = browserClock, timeoutMs = FIRST_PAINT_TIMEOUT_MS): () => void {
  let done = false;
  let frame = 0;
  const finish = () => {
    if (done) return;
    cancel();
    callback();
  };
  const cancel = () => {
    done = true;
    clock.cancelAnimationFrame(frame);
    clock.clearTimeout(timer);
  };
  const timer = clock.setTimeout(finish, timeoutMs);
  frame = clock.requestAnimationFrame(() => {
    if (!done) frame = clock.requestAnimationFrame(finish);
  });
  return cancel;
}
