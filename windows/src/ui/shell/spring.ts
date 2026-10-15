/*
 * SwiftUI's spring(duration:bounce:), so the island moves with the Mac's
 * curves (MotionTokens). A spring with duration d and bounce b is a unit mass
 * with stiffness (2 pi / d)^2 and damping 4 pi (1 - b) / d; bounce 0 is
 * critically damped and never overshoots.
 */

export interface SpringSpec {
  readonly duration: number;
  readonly bounce: number;
}

/* The Mac's motion tokens, in seconds. */
export const MOTION = {
  open: { duration: 0.45, bounce: 0.2 },
  close: { duration: 0.38, bounce: 0 },
  hover: { duration: 0.25, bounce: 0.1 },
  snappy: { duration: 0.26, bounce: 0.14 },
  content: { duration: 0.34, bounce: 0.1 },
} as const satisfies Record<string, SpringSpec>;

export interface SpringValue {
  value: number;
  velocity: number;
}

/* A value counts as at rest within a hundredth of a pixel. */
const REST = 0.01;
const SUBSTEP = 1 / 1000;

/*
 * Advances a spring toward its target by dt seconds, in 1 ms substeps
 * (semi-implicit Euler, stable for these stiffnesses). Returns true once the
 * value has come to rest, and then sits exactly on the target.
 */
export function stepSpring(spring: SpringValue, target: number, spec: SpringSpec, dt: number): boolean {
  const omega = (2 * Math.PI) / spec.duration;
  const stiffness = omega * omega;
  const damping = (4 * Math.PI * (1 - Math.max(0, spec.bounce))) / spec.duration;
  let remaining = Math.min(dt, 0.1);
  while (remaining > 0) {
    const h = Math.min(SUBSTEP, remaining);
    const force = -stiffness * (spring.value - target) - damping * spring.velocity;
    spring.velocity += force * h;
    spring.value += spring.velocity * h;
    remaining -= h;
  }
  if (Math.abs(spring.value - target) < REST && Math.abs(spring.velocity) < REST * 10) {
    spring.value = target;
    spring.velocity = 0;
    return true;
  }
  return false;
}
