import type { Instant, Seconds } from "../time";

/** Port of Foundation's DateInterval as the planners use it: a start and an end no earlier than it. */
export interface DateInterval {
  readonly start: Instant;
  readonly end: Instant;
}

export function interval(start: Instant, end: Instant): DateInterval {
  return { start, end };
}

export function intervalDuration(value: DateInterval): Seconds {
  return value.end - value.start;
}

/** The overlap of two intervals, empty (zero length) when they only touch, undefined when they are apart. */
export function intersection(a: DateInterval, b: DateInterval): DateInterval | undefined {
  const start = Math.max(a.start, b.start);
  const end = Math.min(a.end, b.end);
  return end < start ? undefined : { start, end };
}

export function sameInterval(a: DateInterval, b: DateInterval): boolean {
  return a.start === b.start && a.end === b.end;
}

/** Whether `instant` lies inside, both ends included (`DateInterval.contains`). */
export function intervalContains(value: DateInterval, instant: Instant): boolean {
  return value.start <= instant && instant <= value.end;
}

/** The first longest interval, like Swift's `max(by:)` on durations. */
export function longestInterval(intervals: readonly DateInterval[]): DateInterval | undefined {
  let best: DateInterval | undefined;
  for (const candidate of intervals) {
    if (best === undefined || intervalDuration(best) < intervalDuration(candidate)) best = candidate;
  }
  return best;
}
