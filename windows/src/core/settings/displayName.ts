import type { Instant } from "../time";

/** The friends server's name limit, which every use of the name follows. */
export const DISPLAY_NAME_MAX_LENGTH = 24;

/** Zero-width and direction marks a name could hide behind. */
const INVISIBLE = new Set([
  0x00ad, 0x200b, 0x200c, 0x200d, 0x200e, 0x200f, 0x2060, 0xfeff, 0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2066,
  0x2067, 0x2068, 0x2069,
]);

const segmenter = new Intl.Segmenter("en", { granularity: "grapheme" });

/** Unicode general category Cc, what Foundation's `controlCharacters` set holds alongside Cf format marks. */
function isControl(codePoint: number): boolean {
  return /\p{Cc}|\p{Cf}/u.test(String.fromCodePoint(codePoint));
}

/**
 * Port of DisplayName.cleaned: `text` trimmed, with control and invisible
 * characters removed and at most 24 characters. Undefined when nothing is left.
 */
export function cleanedDisplayName(text: string): string | undefined {
  const kept = [...text].filter((char) => {
    const codePoint = char.codePointAt(0) ?? 0;
    return !isControl(codePoint) && !INVISIBLE.has(codePoint);
  });
  const trimmed = kept.join("").trim();
  if (trimmed === "") return undefined;
  const characters = [...segmenter.segment(trimmed)].map((segment) => segment.segment);
  return characters.slice(0, DISPLAY_NAME_MAX_LENGTH).join("").trim();
}

const hourFormatters = new Map<string, Intl.DateTimeFormat>();

function hourIn(instant: Instant, timeZone: string): number {
  let formatter = hourFormatters.get(timeZone);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", hourCycle: "h23" });
    hourFormatters.set(timeZone, formatter);
  }
  const hour = formatter.formatToParts(new Date(instant * 1000)).find((part) => part.type === "hour")?.value;
  return Number(hour ?? 0) % 24;
}

/**
 * Port of DisplayName.greeting: "Good morning, Ana" for the hour of
 * `instant` in `timeZone` (morning from 4 am, afternoon from noon, evening
 * from 5 pm). Undefined without a name, so callers keep their own wording.
 */
export function displayNameGreeting(name: string | undefined, instant: Instant, timeZone: string): string | undefined {
  const cleaned = name === undefined ? undefined : cleanedDisplayName(name);
  if (cleaned === undefined) return undefined;
  const hour = hourIn(instant, timeZone);
  const part = hour >= 4 && hour < 12 ? "morning" : hour >= 12 && hour < 17 ? "afternoon" : "evening";
  return `Good ${part}, ${cleaned}`;
}
