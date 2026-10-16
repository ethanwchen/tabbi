import { characterCount, kitSetting, type KitSettingType } from "../kits/kitSettingsSchema";
import { tr } from "../localization/tr";
import { randomElement, type RandomSource } from "../motivation/randomSource";
import { isJSONObject, type JSONValue } from "../persistence/json";

/*
 * Port of PetCoachMessages.swift: what a nudge is about, the pet's lines
 * and a picker that keeps them varied.
 *
 * Copy rules (from the research notes): short enough for a bubble, warm,
 * and never shaming. No counting slip-ups, no guilt, no "you should". The
 * standard lines name no subject, so any kit can use them; a kit adds its
 * own flavor through `coachLines` in its pet settings.
 */

/** What a nudge is about. The UI picks buttons from this. */
export type PetCoachNudgeKind =
  /** A gentle "head back?" bubble after a while in a distracting app. */
  | "distraction"
  /** The kind next step: offer to pause the timer. */
  | "offerPause"
  /** No input for a while. Reading looks idle, so only ask. */
  | "idleCheck"
  /** Away long enough that the app pauses the timer so the time isn't counted. */
  | "autoPause";

export const PET_COACH_NUDGE_KINDS: readonly PetCoachNudgeKind[] = ["distraction", "offerPause", "idleCheck", "autoPause"];

/** One line the pet can say. */
export interface PetCoachMessage {
  /** Stable id, used to avoid repeating recent lines. */
  readonly id: string;
  readonly kind: PetCoachNudgeKind;
  /** The approved English, or a kit's line as written. */
  readonly text: string;
}

/** The line in the user's language, looked up by its English as the Mac's catalog keys it; a line the catalog lacks shows as written. */
export function coachMessageText(message: PetCoachMessage): string {
  return tr(message.text);
}

/** Longest line, in characters, that fits a speech bubble. */
export const PET_COACH_MAX_LINE_LENGTH = 64;

/** Plenty for variety; a kit with more gets a warning, not an error. */
export const PET_COACH_MAX_KIT_LINES_PER_KIND = 20;

const m = (id: string, kind: PetCoachNudgeKind, text: string): PetCoachMessage => ({ id, kind, text });

/** Subject-free lines every kit gets. */
export const STANDARD_COACH_LINES: readonly PetCoachMessage[] = [
  m("distraction.notes", "distraction", "Your notes miss you. Back for a few more minutes?"),
  m("distraction.seat", "distraction", "Your study spot is saving your seat."),
  m("distraction.nextPage", "distraction", "Psst, the next page might be the one that clicks."),
  m("distraction.detour", "distraction", "Brains need detours too. Ready to head back?"),
  m("distraction.warm", "distraction", "Your study block is still warm. Pick it back up?"),
  m("distraction.phones", "distraction", "Everyone checks their phone. Back when ready."),

  m("offerPause.breather", "offerPause", "A breather is part of the plan. Pause for now?"),
  m("offerPause.fresh", "offerPause", "Want me to pause the clock so you come back fresh?"),
  m("offerPause.taking5", "offerPause", "Taking five? I can pause the timer for you."),
  m("offerPause.realBreak", "offerPause", "Looks like a real break might help. Pause?"),

  m("idleCheck.reading", "idleCheck", "Still studying? Reading counts too."),
  m("idleCheck.thinking", "idleCheck", "Thinking something through? Tap if you're here."),
  m("idleCheck.quiet", "idleCheck", "Quiet over here. Still with me?"),
  m("idleCheck.clock", "idleCheck", "Still going? Let me know and I'll keep the clock running."),

  m("autoPause.away", "autoPause", "You stepped away, so I paused the clock. No rush."),
  m("autoPause.honest", "autoPause", "Timer paused so your stats stay honest. Resume anytime."),
  m("autoPause.hydrate", "autoPause", "Paused for now. Hydrate, stretch, then back at it."),
  m("autoPause.welcome", "autoPause", "Paused while you were away. Welcome back anytime."),
];

/** How a kit writes `coachLines`: per nudge kind, a line or a list of lines. */
export const PET_COACH_KIT_SETTING_TYPE: KitSettingType = kitSetting.object(
  Object.fromEntries(
    PET_COACH_NUDGE_KINDS.map((kind) => [kind, kitSetting.lines(PET_COACH_MAX_LINE_LENGTH, PET_COACH_MAX_KIT_LINES_PER_KIND)]),
  ),
);

/**
 * The standard lines plus the kit's own, read from the pet module's kit
 * settings (`{ "coachLines": { "distraction": ["..."] } }`). Kit lines join
 * the standard ones rather than replace them.
 */
export function coachLines(kitSettings: JSONValue | undefined): PetCoachMessage[] {
  return [...STANDARD_COACH_LINES, ...kitCoachLines(kitSettings)];
}

/**
 * Only the kit's valid lines, ids `kit.<kind>.<index>`. Unknown kinds, blank
 * lines and lines longer than the bubble are skipped, so a hand-written kit
 * can't break the bubble.
 */
export function kitCoachLines(kitSettings: JSONValue | undefined): PetCoachMessage[] {
  if (kitSettings === undefined || !isJSONObject(kitSettings)) return [];
  const byKind = kitSettings.coachLines;
  if (byKind === undefined || !isJSONObject(byKind)) return [];
  return PET_COACH_NUDGE_KINDS.flatMap((kind) =>
    entries(byKind[kind]).flatMap((raw, index) => {
      const text = raw?.trim();
      if (text === undefined || text === "" || characterCount(text) > PET_COACH_MAX_LINE_LENGTH) return [];
      return [m(`kit.${kind}.${index}`, kind, text)];
    }),
  );
}

/*
 * One kind's entries, read leniently so one badly shaped entry can't drop
 * the kit's other lines: a single string counts as a one-line list, and
 * non-string items stay as undefined so later ids don't shift.
 */
function entries(value: JSONValue | undefined): (string | undefined)[] {
  if (typeof value === "string") return [value];
  if (Array.isArray(value)) return value.map((item) => (typeof item === "string" ? item : undefined));
  return [];
}

/** The lines of `kind` in `lines`, or the standard ones when there are none. */
export function coachMessages(kind: PetCoachNudgeKind, lines: readonly PetCoachMessage[] = STANDARD_COACH_LINES): PetCoachMessage[] {
  const pool = lines.filter((line) => line.kind === kind);
  return pool.length > 0 ? pool : STANDARD_COACH_LINES.filter((line) => line.kind === kind);
}

/**
 * Picks a line of `kind` from `lines`, skipping ids in `recentIDs` while
 * any other line is left. If every line was used recently, it still avoids
 * the most recent one so the same line never shows twice in a row.
 */
export function pickCoachMessage(
  kind: PetCoachNudgeKind,
  random: RandomSource,
  lines: readonly PetCoachMessage[] = STANDARD_COACH_LINES,
  recentIDs: readonly string[] = [],
): PetCoachMessage {
  const pool = coachMessages(kind, lines);
  const recent = new Set(recentIDs);
  let candidates = pool.filter((line) => !recent.has(line.id));
  const last = recentIDs[recentIDs.length - 1];
  if (candidates.length === 0 && last !== undefined) candidates = pool.filter((line) => line.id !== last);
  if (candidates.length === 0) candidates = pool;
  return randomElement(candidates, random);
}
