/*
 * The few Swift number rules the timers lean on, spelled out once so every
 * port rounds the way the Mac does: `rounded()` goes half away from zero
 * (Math.round goes half up), and `Int(x)` truncates toward zero.
 */

/** Swift's `x.rounded()`: to nearest, halves away from zero. */
export function roundHalfAwayFromZero(x: number): number {
  return x < 0 ? -Math.round(-x) : Math.round(x);
}

/** Swift's `Int(x)` for a finite double: truncates toward zero. */
export function swiftInt(x: number): number {
  return Math.trunc(x);
}

/** Swift's integer `/`: truncates toward zero. */
export function intDivide(a: number, b: number): number {
  return Math.trunc(a / b);
}

/** Swift's integer `%`: the sign follows the dividend, like JavaScript's. */
export function intRemainder(a: number, b: number): number {
  return a % b;
}

export function clamp(value: number, lower: number, upper: number): number {
  return Math.min(Math.max(value, lower), upper);
}
