/**
 * Port of RingBuffer: a fixed-capacity queue that drops its oldest element
 * once full, for a bounded metric history behind each sparkline.
 */
export class RingBuffer<T> {
  private storage: T[] = [];
  private head = 0;

  constructor(readonly capacity: number) {
    if (!(capacity > 0)) throw new RangeError("RingBuffer capacity must be positive");
  }

  get count(): number {
    return this.storage.length;
  }

  get isEmpty(): boolean {
    return this.storage.length === 0;
  }

  get isFull(): boolean {
    return this.storage.length === this.capacity;
  }

  /** Elements ordered oldest to newest. */
  get elements(): T[] {
    return [...this.storage.slice(this.head), ...this.storage.slice(0, this.head)];
  }

  /** The most recently appended element. */
  get last(): T | undefined {
    if (this.storage.length === 0) return undefined;
    return this.storage[(this.head + this.storage.length - 1) % this.storage.length];
  }

  append(element: T): void {
    if (this.storage.length < this.capacity) {
      this.storage.push(element);
    } else {
      this.storage[this.head] = element;
      this.head = (this.head + 1) % this.capacity;
    }
  }

  removeAll(): void {
    this.storage = [];
    this.head = 0;
  }
}

/** A point of a sparkline: `x` a slot in 0 to capacity - 1 (newest last), `y` clamped to 0 to 1. */
export interface HistoryPoint {
  x: number;
  y: number;
}

/** One cubic Bezier piece of the sparkline curve, in plot units. */
export interface CurveSegment {
  control1: { x: number; y: number };
  control2: { x: number; y: number };
  end: { x: number; y: number };
}

/**
 * Port of HistorySeries: a plot-ready history. Points are right-aligned on a
 * fixed `capacity`-wide axis, so a history still filling up grows in from
 * the right edge instead of stretching and then jumping.
 */
export class HistorySeries {
  readonly points: HistoryPoint[];

  /** Keeps the newest `capacity` finite values; non-finite samples are dropped. */
  constructor(
    values: readonly number[],
    readonly capacity: number,
  ) {
    if (!(capacity > 0)) throw new RangeError("HistorySeries capacity must be positive");
    const finite = values.filter(Number.isFinite).slice(-capacity);
    const offset = capacity - finite.length;
    this.points = finite.map((value, index) => ({ x: offset + index, y: Math.min(Math.max(value, 0), 1) }));
  }

  get isEmpty(): boolean {
    return this.points.length === 0;
  }

  /** Highest value in the window, or undefined when empty. */
  get peak(): number | undefined {
    return this.points.length === 0 ? undefined : Math.max(...this.points.map((point) => point.y));
  }

  /** Mean value in the window, or undefined when empty. */
  get average(): number | undefined {
    if (this.points.length === 0) return undefined;
    return this.points.reduce((sum, point) => sum + point.y, 0) / this.points.length;
  }

  /**
   * A smooth curve through every point that never overshoots them
   * (monotone cubic interpolation, as d3's `curveMonotoneX`), so a sparkline
   * stays inside 0 to 1 and shows no bump the data lacks. Starts at the
   * first point; empty with fewer than two.
   */
  get monotoneCurve(): CurveSegment[] {
    const count = this.points.length;
    if (count < 2) return [];
    const xs = this.points.map((point) => point.x);
    const ys = this.points.map((point) => point.y);
    const at = (list: number[], index: number) => list[index] ?? 0;
    const slopes: number[] = [];
    for (let i = 0; i < count - 1; i++) {
      const width = at(xs, i + 1) - at(xs, i);
      slopes.push(width === 0 ? 0 : (at(ys, i + 1) - at(ys, i)) / width);
    }
    const tangents: number[] = new Array<number>(count).fill(0);
    for (let i = 1; i < count - 1; i++) {
      const before = at(xs, i) - at(xs, i - 1);
      const after = at(xs, i + 1) - at(xs, i);
      const s0 = at(slopes, i - 1);
      const s1 = at(slopes, i);
      const blended = (s0 * after + s1 * before) / (before + after);
      const sameDirection = (s0 > 0 && s1 > 0) || (s0 < 0 && s1 < 0);
      tangents[i] = sameDirection ? (s0 > 0 ? 1 : -1) * Math.min(Math.abs(s0), Math.abs(s1), 0.5 * Math.abs(blended)) * 2 : 0;
    }
    /* The ends follow the neighbouring tangent toward the end slope. */
    tangents[0] = count === 2 ? at(slopes, 0) : (3 * at(slopes, 0) - at(tangents, 1)) / 2;
    tangents[count - 1] = count === 2 ? at(slopes, count - 2) : (3 * at(slopes, count - 2) - at(tangents, count - 2)) / 2;
    const segments: CurveSegment[] = [];
    for (let i = 0; i < count - 1; i++) {
      const third = (at(xs, i + 1) - at(xs, i)) / 3;
      segments.push({
        control1: { x: at(xs, i) + third, y: at(ys, i) + third * at(tangents, i) },
        control2: { x: at(xs, i + 1) - third, y: at(ys, i + 1) - third * at(tangents, i + 1) },
        end: { x: at(xs, i + 1), y: at(ys, i + 1) },
      });
    }
    return segments;
  }
}
