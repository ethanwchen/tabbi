/*
 * SwiftUI's spring(duration:bounce:), so the island moves with the Mac's
 * curves. The numbers and the duration and bounce to stiffness and damping
 * conversion come from the core's port of MotionTokens and SpringSpec; this
 * file only steps a value along the spring frame by frame.
 */

import { MotionTokens } from "../../core/motion/motionTokens";
import { SpringSpec as CoreSpringSpec, type SpringParameters } from "../../core/motion/springSpec";

export type SpringSpec = SpringParameters;

/* The Mac's motion tokens the island plays, in seconds. */
export const MOTION = {
  open: MotionTokens.open,
  close: MotionTokens.close,
  hover: MotionTokens.hover,
  snappy: MotionTokens.snappy,
  content: MotionTokens.content,
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
  const { stiffness, damping } = CoreSpringSpec.from(spec);
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
