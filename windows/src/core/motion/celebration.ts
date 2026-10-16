import type { Instant } from "../time";
import { plannerDayKeyOf } from "../planner/plannerDayKey";
import { SplitMix64 } from "./splitMix64";

/*
 * Port of Celebration.swift: the particle tiers and styles, a seeded
 * procedural burst whose positions are pure functions of elapsed time, and
 * the pacer that keeps celebrations rare enough to stay special.
 */

/** Port of CelebrationTier: a small burst (daily goal, streak kept) or a fuller milestone burst. */
export type CelebrationTier = "burst" | "milestone";

/** Port of CelebrationStyle: what the particles look like, each drawn from paths. */
export type CelebrationStyle = "confetti" | "sparkles" | "hearts" | "pawPrints";

export const CELEBRATION_STYLES: readonly CelebrationStyle[] = ["confetti", "sparkles", "hearts", "pawPrints"];

type Range = readonly [number, number];

interface TierShape {
  readonly particleCount: number;
  /** The longest a particle lives, in seconds. */
  readonly lifetimes: Range;
  /** Launch speeds, in pixels per second. */
  readonly speeds: Range;
  /** How long after the start the last particle may launch. */
  readonly launchSpread: number;
}

const TIERS: Record<CelebrationTier, TierShape> = {
  burst: { particleCount: 36, lifetimes: [0.9, 1.3], speeds: [300, 460], launchSpread: 0.06 },
  milestone: { particleCount: 72, lifetimes: [1.1, 1.6], speeds: [340, 540], launchSpread: 0.15 },
};

const SIZES: Record<CelebrationStyle, Range> = {
  confetti: [4, 7],
  sparkles: [5, 9],
  hearts: [6, 9],
  pawPrints: [7, 10],
};

/** How many particles a tier throws. */
export function particleCount(tier: CelebrationTier): number {
  return TIERS[tier].particleCount;
}

/** Port of CelebrationParticle: one particle's launch, everything that doesn't change over time. */
export interface CelebrationParticle {
  /** The launch direction in radians away from straight up; negative is left. */
  readonly angle: number;
  /** Pixels per second. */
  readonly speed: number;
  /** How long after the burst starts it launches, in seconds. */
  readonly delay: number;
  /** How long it lives once launched, in seconds. */
  readonly lifetime: number;
  /** The rotation at launch, in degrees. */
  readonly rotation: number;
  /** Degrees per second. */
  readonly spin: number;
  readonly size: number;
  /** Which palette color it takes, in 0..<paletteSize. */
  readonly colorIndex: number;
}

/** Port of CelebrationParticleState: where a particle is, relative to the burst's origin. */
export interface CelebrationParticleState {
  /** Positive is right. */
  readonly x: number;
  /** Positive is down, as on screen. */
  readonly y: number;
  readonly rotation: number;
  /** 1 while fresh, fading to 0 over its last `fadeShare`. */
  readonly opacity: number;
  /** Grows from `popScale` to 1 just after launch. */
  readonly scale: number;
}

function smoothstep(value: number): number {
  const v = Math.min(1, Math.max(0, value));
  return v * v * (3 - 2 * v);
}

/**
 * Port of CelebrationBurst. Nothing mutates per frame, so the same moment
 * draws the same picture, and a burst costs nothing once `duration` has
 * passed: a fast launch within 35 degrees of vertical, gravity slowed by
 * strong air drag (a 200 px/s fall), and lifetimes that keep the burst under
 * 1.5 s (burst) or 2 s (milestone).
 */
export class CelebrationBurst {
  static readonly gravity = 700;
  /** Air drag per second; caps the fall at gravity / drag so confetti floats down. */
  static readonly drag = 3.5;
  /** The widest launch angle either side of vertical, in radians. */
  static readonly spread = (35 * Math.PI) / 180;
  /** A particle's scale at launch. */
  static readonly popScale = 0.4;
  /** How long a particle takes to grow to full size. */
  static readonly popDuration = 0.12;
  /** The share of a particle's life spent fading out. */
  static readonly fadeShare = 0.4;

  readonly particles: readonly CelebrationParticle[];

  /** The same seed always gives the same burst; `paletteSize` is how many colors the view offers. */
  constructor(
    readonly tier: CelebrationTier,
    readonly style: CelebrationStyle,
    seed: bigint | number,
    paletteSize: number,
  ) {
    const random = new SplitMix64(seed);
    const colors = Math.max(1, paletteSize);
    const shape = TIERS[tier];
    const sizes = SIZES[style];
    /* Confetti tumbles; shapes with a clear "up" only sway a little. */
    const spins: Range = style === "confetti" ? [180, 540] : [20, 90];
    const spread = CelebrationBurst.spread;
    const particles: CelebrationParticle[] = [];
    for (let index = 0; index < shape.particleCount; index++) {
      const angle = random.nextIn(-spread, spread);
      const speed = random.nextIn(...shape.speeds);
      const delay = random.nextIn(0, shape.launchSpread);
      const lifetime = random.nextIn(...shape.lifetimes);
      const rotation = style === "confetti" ? random.nextIn(0, 360) : random.nextIn(-15, 15);
      const spinSpeed = random.nextIn(...spins);
      const spin = spinSpeed * (random.nextIn(0, 1) < 0.5 ? -1 : 1);
      const size = random.nextIn(...sizes);
      particles.push({ angle, speed, delay, lifetime, rotation, spin, size, colorIndex: index % colors });
    }
    this.particles = particles;
  }

  /** When the last particle is gone, in seconds after the start. */
  get duration(): number {
    return this.particles.reduce((longest, p) => Math.max(longest, p.delay + p.lifetime), 0);
  }

  isFinished(elapsed: number): boolean {
    return elapsed >= this.duration;
  }

  /** `particle` at `elapsed` seconds after the start, or undefined before it launches and after it fades. */
  static state(particle: CelebrationParticle, elapsed: number): CelebrationParticleState | undefined {
    const t = elapsed - particle.delay;
    if (!(t >= 0) || !(t < particle.lifetime)) return undefined;
    /* Linear drag (dv/dt = g - kv): launch speed decays as e^-kt and the fall approaches g/k. */
    const { drag, gravity, fadeShare, popDuration, popScale } = CelebrationBurst;
    const travel = (1 - Math.exp(-drag * t)) / drag;
    const terminal = gravity / drag;
    const x = particle.speed * Math.sin(particle.angle) * travel;
    const y = -particle.speed * Math.cos(particle.angle) * travel + terminal * (t - travel);
    const life = t / particle.lifetime;
    const fadeStart = 1 - fadeShare;
    const opacity = life <= fadeStart ? 1 : 1 - smoothstep((life - fadeStart) / fadeShare);
    const pop = Math.min(1, t / popDuration);
    const scale = popScale + (1 - popScale) * (1 - (1 - pop) * (1 - pop));
    return { x, y, rotation: particle.rotation + particle.spin * t, opacity, scale };
  }
}

/**
 * Port of CelebrationPacer: at most one particle burst every ten minutes, and
 * one milestone a day. A celebration that isn't admitted still gets its small
 * confirmation, so callers fall back to that on undefined.
 */
export class CelebrationPacer {
  /** The shortest gap between two bursts, in seconds. */
  static readonly burstInterval = 10 * 60;

  constructor(
    private last: { burst?: Instant; milestone?: Instant } = {},
  ) {}

  get lastBurst(): Instant | undefined {
    return this.last.burst;
  }

  get lastMilestone(): Instant | undefined {
    return this.last.milestone;
  }

  /**
   * The tier to play for a `requested` celebration at `at`, recording it, or
   * undefined to play none. A milestone always plays the first time in a day
   * (in `timeZone`); a second one that day is treated as a burst.
   */
  admit(requested: CelebrationTier, at: Instant, timeZone: string): CelebrationTier | undefined {
    const { burst, milestone } = this.last;
    if (requested === "milestone" && (milestone === undefined || plannerDayKeyOf(milestone, timeZone) !== plannerDayKeyOf(at, timeZone))) {
      this.last = { burst: at, milestone: at };
      return "milestone";
    }
    if (burst !== undefined && at - burst < CelebrationPacer.burstInterval && at >= burst) {
      return undefined;
    }
    this.last = { ...this.last, burst: at };
    return "burst";
  }
}
