/*
 * Port of SpringSpec: a spring described the way SwiftUI's
 * `Animation.spring(duration:bounce:)` describes it, a perceptual duration and
 * a bounce from -1 to 1 (0 is critically damped, no overshoot). Kept as a pure
 * value so the motion tokens can be tested without a renderer.
 */

/** The two numbers a spring is described by, for callers that pass plain objects. */
export interface SpringParameters {
  readonly duration: number;
  readonly bounce: number;
}

/** Port of SpringSpec, with unit mass. */
export class SpringSpec implements SpringParameters {
  /** Perceptual duration in seconds. */
  readonly duration: number;
  /** -1 to 1; 0 means no overshoot, about 0.15 feels brisk, above 0.4 feels exaggerated. */
  readonly bounce: number;

  constructor(duration: number, bounce = 0) {
    this.duration = Math.max(duration, 0.01);
    this.bounce = Math.min(Math.max(bounce, -1), 1);
  }

  /** The spec for plain parameters, clamped like the constructor. */
  static from(parameters: SpringParameters): SpringSpec {
    return parameters instanceof SpringSpec ? parameters : new SpringSpec(parameters.duration, parameters.bounce);
  }

  /** Stiffness with unit mass: (2 pi / duration)^2. */
  get stiffness(): number {
    const omega = (2 * Math.PI) / this.duration;
    return omega * omega;
  }

  /** Damping with unit mass, Apple's conversion from duration and bounce. */
  get damping(): number {
    const base = (4 * Math.PI) / this.duration;
    return this.bounce >= 0 ? (1 - this.bounce) * base : base / (1 + this.bounce);
  }

  /** 1 is critically damped; below 1 overshoots. */
  get dampingRatio(): number {
    return this.damping / (2 * Math.sqrt(this.stiffness));
  }

  /** True when the spring overshoots its target before settling. */
  get overshoots(): boolean {
    return this.dampingRatio < 1 - 1e-9;
  }

  /**
   * Fraction of the distance travelled at time `t`, starting at rest (0 at
   * t = 0, settling at 1). Can exceed 1 for a bouncy spring.
   */
  value(t: number): number {
    if (!(t > 0)) return 0;
    const omega = Math.sqrt(this.stiffness);
    const zeta = this.dampingRatio;
    if (zeta < 1 - 1e-9) {
      const omegaD = omega * Math.sqrt(1 - zeta * zeta);
      const envelope = Math.exp(-zeta * omega * t);
      return 1 - envelope * (Math.cos(omegaD * t) + ((zeta * omega) / omegaD) * Math.sin(omegaD * t));
    }
    if (zeta > 1 + 1e-9) {
      const root = Math.sqrt(zeta * zeta - 1);
      const r1 = -omega * (zeta - root);
      const r2 = -omega * (zeta + root);
      return 1 - (r2 * Math.exp(r1 * t) - r1 * Math.exp(r2 * t)) / (r2 - r1);
    }
    return 1 - Math.exp(-omega * t) * (1 + omega * t);
  }

  /** The largest value reached, so 1 for no overshoot and 1.1 for a 10% overshoot. */
  get peak(): number {
    if (!this.overshoots) return 1;
    const omega = Math.sqrt(this.stiffness);
    const omegaD = omega * Math.sqrt(1 - this.dampingRatio * this.dampingRatio);
    /* The first maximum of an underdamped spring is at pi / omegaD. */
    return this.value(Math.PI / omegaD);
  }

  /** Time after which the spring stays within `tolerance` of its target. */
  settlingTime(tolerance = 0.01): number {
    const step = 1 / 240;
    let lastOutside = 0;
    let t = 0;
    while (t < 10) {
      if (Math.abs(this.value(t) - 1) > tolerance) lastOutside = t;
      t += step;
    }
    return lastOutside + step;
  }
}
