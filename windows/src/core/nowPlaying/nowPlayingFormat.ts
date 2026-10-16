import type { Seconds } from "../time";
import type { MediaThumbnail } from "./mediaSession";
import type { NowPlayingTrack } from "./nowPlayingPlayback";

/** Port of PlaybackTimeFormatter: `m:ss`, or `h:mm:ss` for long episodes. */
export function playbackTime(seconds: Seconds): string {
  const total = Number.isFinite(seconds) ? Math.max(Math.floor(seconds), 0) : 0;
  const hours = Math.trunc(total / 3600);
  const minutes = Math.trunc((total % 3600) / 60);
  const secs = total % 60;
  const pad = (value: number) => String(value).padStart(2, "0");
  return hours > 0 ? `${hours}:${pad(minutes)}:${pad(secs)}` : `${minutes}:${pad(secs)}`;
}

/** Time left, with a minus sign (`-1:05`). */
export function remainingTime(position: Seconds, duration: Seconds): string {
  return "-" + playbackTime(Math.ceil(Math.max(duration - position, 0)));
}

/**
 * Port of SpotifyGeneratedCover: colors for a cover drawn when a track has
 * no artwork, from the track id so the same track always gets the same
 * cover. Hues are 0 to 1; the end hue is 50 to 110 degrees from the start.
 */
export interface GeneratedCover {
  startHue: number;
  endHue: number;
}

const FNV_OFFSET = 0xcbf29ce484222325n;
const FNV_PRIME = 0x00000100000001b3n;

/** FNV-1a over the UTF-8 bytes, 64 bits: stable across launches and the same as the Mac's. */
function fnv1a(text: string): bigint {
  let hash = FNV_OFFSET;
  for (const byte of new TextEncoder().encode(text)) {
    hash ^= BigInt(byte);
    hash = BigInt.asUintN(64, hash * FNV_PRIME);
  }
  return hash;
}

export function generatedCover(seed: string): GeneratedCover {
  const hash = fnv1a(seed);
  const startHue = Number(hash % 360n) / 360;
  /* Step 50 to 110 degrees around the wheel for a rich, analogous gradient. */
  const step = 50 + Number((hash / 360n) % 61n);
  return { startHue, endHue: (startHue + step / 360) % 1 };
}

/** What the artwork square shows: the session's thumbnail, or a cover generated from the track. */
export type ArtworkChoice =
  | { kind: "thumbnail"; thumbnail: MediaThumbnail; dataURL: string }
  | { kind: "generated"; cover: GeneratedCover };

/** The artwork for `track`: its thumbnail when the app published one, otherwise a generated cover. */
export function artworkChoice(track: NowPlayingTrack): ArtworkChoice {
  if (track.artwork && track.artwork.base64.length > 0) {
    return { kind: "thumbnail", thumbnail: track.artwork, dataURL: `data:${track.artwork.contentType};base64,${track.artwork.base64}` };
  }
  return { kind: "generated", cover: generatedCover(track.id) };
}

/**
 * Port of SpotifyMarquee: scroll position for a title that doesn't fit its
 * line. The text is drawn twice, `gap` apart, and both shift left by the
 * offset; one cycle moves exactly one text width plus the gap, so the loop
 * has no seam. A pure function of time.
 */
export const Marquee = {
  /** Space between the end of the text and the start of its repeat. */
  gap: 32,
  /** Scroll speed in pixels per second; slow enough to read along. */
  speed: 28,
  /** Rest at the start of each cycle, so the opening words can be read. */
  pause: 1.2,

  /** Whether the text overflows and should scroll; half a pixel of slack absorbs rounding. */
  needsScrolling(textWidth: number, containerWidth: number): boolean {
    return Number.isFinite(textWidth) && Number.isFinite(containerWidth) && textWidth > containerWidth + 0.5;
  },

  /** Horizontal offset (zero or negative) `elapsed` seconds after scrolling started; eases in and out each cycle. */
  offset(elapsed: Seconds, textWidth: number, containerWidth: number): number {
    if (!Number.isFinite(elapsed) || elapsed <= 0 || !Marquee.needsScrolling(textWidth, containerWidth)) return 0;
    const distance = textWidth + Marquee.gap;
    const travel = distance / Marquee.speed;
    const t = elapsed % (Marquee.pause + travel);
    if (t <= Marquee.pause) return 0;
    const progress = (t - Marquee.pause) / travel;
    const eased = progress * progress * (3 - 2 * progress);
    return -distance * eased;
  },
} as const;

/**
 * Port of SpotifyEqualizer: bar heights for the closed island's
 * equalizer, a pure function of time so the view can draw it from an
 * animation frame that simply stops when playback pauses.
 */
interface EqualizerAPI {
  readonly barCount: number;
  readonly minimumLevel: number;
  restingLevels(count?: number): number[];
  levels(time: Seconds, count?: number): number[];
  loop(bar: number, duration?: Seconds, frameRate?: number, blend?: Seconds, count?: number): number[];
}

export const Equalizer: EqualizerAPI = {
  /** Bars drawn in the compact wing. */
  barCount: 4,
  /** Lowest level a bar reaches; keeps every bar visible as a short pill. */
  minimumLevel: 0.22,

  /** Short, staggered heights shown while paused, so the bars read as resting. */
  restingLevels(count: number = Equalizer.barCount): number[] {
    return Array.from({ length: Math.max(count, 0) }, (_, index) => Equalizer.minimumLevel + 0.08 * (index % 2));
  },

  /**
   * Levels in `minimumLevel` to 1 for each bar at `time` seconds: two sines
   * at unrelated frequencies for a steady pulse, mixed with smooth hashed
   * noise so every peak differs. The same time always gives the same levels.
   */
  levels(time: Seconds, count: number = Equalizer.barCount): number[] {
    if (!Number.isFinite(time)) return Equalizer.restingLevels(count);
    return Array.from({ length: Math.max(count, 0) }, (_, index) => {
      const slow = Math.sin(time * (5.1 + index * 1.3) + index * 1.7);
      const fast = Math.sin(time * (8.3 + index * 0.9) + index * 2.9);
      const pulse = (slow * 0.6 + fast * 0.4 + 1) / 2;
      const jitter = noise(time * (3.7 + index * 0.6) + index * 13.1, index);
      const mixed = pulse * 0.6 + jitter * 0.4;
      return Equalizer.minimumLevel + (1 - Equalizer.minimumLevel) * Math.min(Math.max(mixed, 0), 1);
    });
  },

  /**
   * One bar's heights over a loop that repeats without a seam, sampled at
   * `frameRate`, for a CSS or Web Animations keyframe loop that plays
   * without waking the app. Over the last `blend` seconds the values ease
   * into the loop's own start, so the first and last are equal.
   */
  loop(bar: number, duration: Seconds = 30, frameRate = 30, blend: Seconds = 1, count: number = Equalizer.barCount): number[] {
    if (!(duration > 0) || !(frameRate > 0) || bar < 0 || bar >= count) return [];
    const frames = Math.round(duration * frameRate);
    const span = Math.min(Math.max(blend, 0), duration);
    return Array.from({ length: frames + 1 }, (_, frame) => {
      const time = frame / frameRate;
      const level = Equalizer.levels(time, count)[bar] ?? Equalizer.minimumLevel;
      const into = time - (duration - span);
      if (!(span > 0) || !(into > 0)) return level;
      const t = Math.min(into / span, 1);
      const eased = t * t * (3 - 2 * t);
      const start = Equalizer.levels(time - duration, count)[bar] ?? level;
      return level + (start - level) * eased;
    });
  },
};

/** 1D value noise in 0 to 1: a random target per whole beat, eased between neighbors. */
function noise(beat: number, bar: number): number {
  /* Wrap so the beat index always fits in 64 bits; the seam is days apart. */
  const wrapped = beat % 1_099_511_627_776;
  const floor = Math.floor(wrapped);
  const t = wrapped - floor;
  const eased = t * t * (3 - 2 * t);
  const a = random(BigInt(floor), bar);
  const b = random(BigInt(floor) + 1n, bar);
  return a + (b - a) * eased;
}

/** SplitMix64 hash of (beat, bar) mapped to 0 to 1, bit for bit the Mac's. */
function random(beat: bigint, bar: number): number {
  let z = BigInt.asUintN(64, BigInt.asUintN(64, beat) + BigInt.asUintN(64, BigInt(bar) * 0x9e3779b97f4a7c15n));
  z = BigInt.asUintN(64, (z ^ (z >> 30n)) * 0xbf58476d1ce4e5b9n);
  z = BigInt.asUintN(64, (z ^ (z >> 27n)) * 0x94d049bb133111ebn);
  z ^= z >> 31n;
  return Number(z >> 11n) / 2 ** 53;
}
