/**
 * A narrow stand-in for the Motion area's MotionPace, which the motion port
 * owns: only the stored raw values Settings keeps.
 */
export type MotionPace = "smooth" | "fast" | "instant";

export const MOTION_PACES: readonly MotionPace[] = ["smooth", "fast", "instant"];

export const DEFAULT_MOTION_PACE: MotionPace = "smooth";

export function isMotionPace(value: unknown): value is MotionPace {
  return typeof value === "string" && (MOTION_PACES as readonly string[]).includes(value);
}
