import type { Instant } from "../time";
import { addingDays, clockText, settingTime, startOfDay } from "../calendar/zonedCalendar";
import { intersection, intervalDuration, longestInterval, type DateInterval } from "./dateInterval";
import { normalizedTitle, type PlannerItem } from "./plannerDay";
import { eventTitle, type UpcomingEvent } from "./upcomingEvent";
import { newUUID, parseUUID } from "./uuid";

/** Port of PlanBlockKind: what a Plan my day block is for. */
export type PlanBlockKind =
  /** General focus time, as the AI plans it. */
  | "focus"
  /** Clearing a shared review goal, such as today's Anki cards. */
  | "reviews"
  /** One study-method-length block, from the study day planner. */
  | "study";

export const PLAN_BLOCK_KINDS: readonly PlanBlockKind[] = ["focus", "reviews", "study"];

/** Port of PlanBlock: one proposed focus block. */
export interface PlanBlock {
  readonly id: string;
  readonly start: Instant;
  readonly end: Instant;
  readonly title: string;
  /** The checklist item this block works on, when one is linked. */
  readonly linkedTaskID?: string;
  readonly kind: PlanBlockKind;
}

/** Builds a block with the Swift initializer's defaults (a fresh id, focus time). */
export function planBlock(input: {
  id?: string;
  start: Instant;
  end: Instant;
  title: string;
  linkedTaskID?: string | undefined;
  kind?: PlanBlockKind;
}): PlanBlock {
  const block: { -readonly [Key in keyof PlanBlock]: PlanBlock[Key] } = {
    id: input.id ?? newUUID(),
    start: input.start,
    end: input.end,
    title: input.title,
    kind: input.kind ?? "focus",
  };
  if (input.linkedTaskID !== undefined) block.linkedTaskID = input.linkedTaskID;
  return block;
}

/* Start, then end: the order proposals keep blocks in. */
export function compareBlocks(a: PlanBlock, b: PlanBlock): number {
  return a.start - b.start || a.end - b.end;
}

/** Shortest block worth planning, in minutes; gaps shorter than this aren't worth a block. */
export const MINIMUM_BLOCK_MINUTES = 15;
/** Proposal rows the panel can show without scrolling. */
export const MAXIMUM_BLOCKS = 5;
/** Longest block title the AI is asked for. */
export const MAXIMUM_TITLE_LENGTH = 22;
/** Planned blocks start on these minute marks. */
export const SLOT_MINUTES = 5;
/** Fast model alias; the plan is a small, structured answer. */
export const DAY_PLANNER_MODEL = "haiku";
/** Where a day planned ahead starts (9 am). */
export const DEFAULT_DAY_START_HOUR = 9;
/** Usual end of the planned day; kits can move it. */
export const DEFAULT_DAY_END_HOUR = 18;
/** The latest a planned day can end. */
export const LATEST_DAY_END_HOUR = 22;

const SLOT = SLOT_MINUTES * 60;

/**
 * The first five-minute mark at or after `instant`. The marks are counted
 * from 1970, which lands on the same marks as Swift's count from 2001.
 */
export function nextSlot(instant: Instant): Instant {
  return Math.ceil(instant / SLOT) * SLOT;
}

/** The last five-minute mark at or before `instant`. */
export function floorSlot(instant: Instant): Instant {
  return Math.floor(instant / SLOT) * SLOT;
}

/** JSON Schema for the plan object, which a provider that can enforce one gets with the prompt. */
export const DAY_PLAN_JSON_SCHEMA =
  '{"type":"object","properties":{"blocks":{"type":"array","items":{"type":"object","properties":{' +
  '"start":{"type":"string","pattern":"^[0-2][0-9]:[0-5][0-9]$"},' +
  '"end":{"type":"string","pattern":"^[0-2][0-9]:[0-5][0-9]$"},' +
  '"title":{"type":"string"},"task":{"type":"string"}},' +
  '"required":["start","end","title"],"additionalProperties":false}}},' +
  '"required":["blocks"],"additionalProperties":false}';

/** Arguments for `claude -p` before `-- <prompt>`: no tools and no MCP servers, only the structured plan. */
export function dayPlannerArguments(): string[] {
  return ["--model", DAY_PLANNER_MODEL, "--tools", "", "--strict-mcp-config", "--json-schema", DAY_PLAN_JSON_SCHEMA];
}

/**
 * A sensible stop time: `endHour` (6 pm by default), or two hours from now
 * when planning later, but never past 10 pm. After 10 pm there is nothing
 * to plan.
 */
export function dayEnd(now: Instant, timeZone: string, endHour: number = DEFAULT_DAY_END_HOUR): Instant {
  const midnight = startOfDay(now, timeZone);
  const usualEnd = settingTime(midnight, Math.min(Math.max(endHour, 0), LATEST_DAY_END_HOUR), 0, 0, timeZone);
  const latest = settingTime(midnight, LATEST_DAY_END_HOUR, 0, 0, timeZone);
  return Math.min(Math.max(usualEnd, now + 2 * 3600), latest);
}

/**
 * Free intervals between `start` and `end` that no timed event touches.
 * All-day events don't block time. The first gap starts on the next
 * five-minute mark, and slivers under `minimumMinutes` are dropped.
 */
export function freeGaps(
  events: readonly UpcomingEvent[],
  start: Instant,
  end: Instant,
  minimumMinutes: number = MINIMUM_BLOCK_MINUTES,
): DateInterval[] {
  let cursor = nextSlot(start);
  const gaps: DateInterval[] = [];
  const busy = events
    .filter((event) => !event.isAllDay && event.end > event.start && event.end > cursor && event.start < end)
    .sort((a, b) => a.start - b.start);
  const close = (boundary: Instant) => {
    const gapEnd = Math.min(boundary, end);
    if (gapEnd - cursor >= minimumMinutes * 60) gaps.push({ start: cursor, end: gapEnd });
  };
  for (const event of busy) {
    if (event.start > cursor) close(event.start);
    cursor = Math.max(cursor, event.end);
    if (cursor >= end) return gaps;
  }
  if (cursor < end) close(end);
  return gaps;
}

/**
 * Port of DayPlanContext: everything Plan my day knows when it asks the AI
 * for a schedule, built once per request so the prompt, the parser and the
 * validator agree on the same day and gaps.
 */
export class DayPlanContext {
  /** When planning starts: now today, or the start of the working day when planning ahead. */
  readonly now: Instant;
  readonly isPlanningAhead: boolean;
  readonly events: readonly UpcomingEvent[];
  /** Unfinished checklist items, in list order. */
  readonly tasks: readonly PlannerItem[];
  /** Work other modules share for today, in a few words each. */
  readonly sharedWork: readonly string[];
  /** The IANA zone every wall-clock time resolves in. */
  readonly timeZone: string;
  /** When planned work should stop for the day. */
  readonly dayEnd: Instant;
  /** Free time between `now` and `dayEnd`, never overlapping a timed event. */
  readonly gaps: readonly DateInterval[];

  constructor(input: {
    now: Instant;
    events: readonly UpcomingEvent[];
    tasks: readonly PlannerItem[];
    sharedWork?: readonly string[];
    timeZone: string;
    dayEndHour?: number;
    isPlanningAhead?: boolean;
  }) {
    this.now = input.now;
    this.isPlanningAhead = input.isPlanningAhead ?? false;
    this.events = input.events;
    this.tasks = input.tasks.filter((task) => !task.isDone);
    this.sharedWork = (input.sharedWork ?? []).map(normalizedTitle).filter((work): work is string => work !== undefined);
    this.timeZone = input.timeZone;
    this.dayEnd = dayEnd(input.now, input.timeZone, input.dayEndHour ?? DEFAULT_DAY_END_HOUR);
    this.gaps = freeGaps(input.events, input.now, this.dayEnd);
  }

  /** Short, stable ids ("t1", "t2", ...) for the prompt; UUIDs waste tokens and invite typos. */
  get taskKeys(): { key: string; task: PlannerItem }[] {
    return this.tasks.map((task, index) => ({ key: `t${index + 1}`, task }));
  }

  /** Keys for `sharedWork`, continuing after the checklist's, so every task in the prompt has one id scheme. */
  get sharedWorkKeys(): { key: string; work: string }[] {
    return this.sharedWork.map((work, index) => ({ key: `t${this.tasks.length + index + 1}`, work }));
  }

  /** Whether there is any free time worth planning. */
  get hasFreeTime(): boolean {
    return this.gaps.length > 0;
  }
}

/**
 * The prompt for Plan my day. Times are local 24-hour `HH:mm` so the AI
 * never reasons about time zones. `limit` caps the blocks asked for.
 */
export function dayPlanPrompt(context: DayPlanContext, limit: number = MAXIMUM_BLOCKS): string {
  const clock = (instant: Instant) => clockText(instant, context.timeZone);
  const range = (start: Instant, end: Instant) => `${clock(start)}-${clock(end)}`;
  const events = context.events
    .filter((event) => !event.isAllDay && event.end > context.now && event.start < context.dayEnd)
    .sort((a, b) => a.start - b.start)
    .map((event) => `- ${range(event.start, event.end)} ${eventTitle(event)}`);
  const gaps = context.gaps.map((gap) => `- ${range(gap.start, gap.end)}`);
  const tasks = [
    ...context.taskKeys.map(({ key, task }) => `- ${key}: ${task.title}`),
    ...context.sharedWorkKeys.map(({ key, work }) => `- ${key}: ${work}`),
  ];
  const list = (lines: string[]) => (lines.length === 0 ? "- none" : lines.join("\n"));
  const opening = context.isPlanningAhead
    ? `You plan someone's day tomorrow, ahead of time. The day starts at ${clock(context.now)}.`
    : `You plan the rest of someone's day. It is now ${clock(context.now)}.`;
  return [
    `${opening} Planned work should end by ${clock(context.dayEnd)}.`,
    "",
    "Calendar events (fixed, do not move or overlap):",
    list(events),
    "",
    "Free time you may use:",
    list(gaps),
    "",
    "Unfinished tasks:",
    list(tasks),
    "",
    `Propose at most ${limit} focused time blocks that fit entirely inside the free time. ` +
      `Each block is ${MINIMUM_BLOCK_MINUTES} to 120 minutes, starts on a 5-minute mark, and blocks never overlap. ` +
      "Prefer the most important tasks first and leave short breaks. " +
      `Titles are at most ${MAXIMUM_TITLE_LENGTH} characters, a shortened form of the task's words ` +
      '(for example "Draft release notes", not "Write the release notes for the beta launch"). ' +
      'Set "task" to the task id (like "t1") when a block works on a task; omit it otherwise. ' +
      'Use 24-hour local times as "HH:mm". If there is no useful free time, return no blocks.',
    "",
    'Answer with JSON only: {"blocks":[{"start":"HH:mm","end":"HH:mm","title":"...","task":"t1"}]}',
  ].join("\n");
}

/** Why an answer couldn't become a plan: no JSON object or array was found in it. */
export class DayPlanParseError extends Error {
  constructor() {
    super("No JSON found in the answer");
    this.name = "DayPlanParseError";
  }
}

/** The outermost JSON object or array in `text`, ignoring fences and prose. */
export function extractJSON(text: string): string | undefined {
  const openers = [text.indexOf("{"), text.indexOf("[")].filter((index) => index >= 0);
  if (openers.length === 0) return undefined;
  const start = Math.min(...openers);
  const closer = text[start] === "{" ? "}" : "]";
  const end = text.lastIndexOf(closer);
  return end > start ? text.slice(start, end + 1) : undefined;
}

/* Swift's `Int(String)`: optional sign, then ASCII digits only. */
function swiftInt(text: string): number | undefined {
  return /^[+-]?[0-9]+$/.test(text) ? Number(text) : undefined;
}

/* Swift's `.whitespaces`: spaces and tabs (and other horizontal spaces), not line breaks. */
function trimHorizontal(text: string): string {
  return text.replace(/^[\p{Zs}\t]+|[\p{Zs}\t]+$/gu, "");
}

/**
 * `HH:mm` or `H:mm` on the day starting at `midnight`, or undefined when
 * invalid. `24:00` is the next midnight. Resolved as wall-clock time in
 * `timeZone`, so daylight saving days stay right.
 */
export function planTime(text: string, midnight: Instant, timeZone: string): Instant | undefined {
  const fields = trimHorizontal(text)
    .split(":")
    .filter((field) => field !== "");
  if (fields.length !== 2 || fields[1]?.length !== 2) return undefined;
  const hour = swiftInt(fields[0] ?? "");
  const minute = swiftInt(fields[1]);
  if (hour === undefined || minute === undefined) return undefined;
  if (hour < 0 || hour > 24 || minute < 0 || minute >= 60 || hour * 60 + minute > 24 * 60) return undefined;
  if (hour === 24) return addingDays(midnight, 1, timeZone);
  return settingTime(midnight, hour, minute, 0, timeZone);
}

/**
 * Reads the AI's answer into blocks on the context's day. Tolerates code
 * fences and surrounding prose, a bare array instead of `{"blocks": [...]}`,
 * `H:mm` times and unknown task ids; malformed entries are skipped. Throws
 * `DayPlanParseError` only when no JSON is present at all.
 */
export function parseDayPlan(text: string, context: DayPlanContext): PlanBlock[] {
  const json = extractJSON(text);
  if (json === undefined) throw new DayPlanParseError();
  let object: unknown;
  try {
    object = JSON.parse(json);
  } catch {
    throw new DayPlanParseError();
  }
  let entries: unknown[];
  if (Array.isArray(object)) {
    entries = object;
  } else if (typeof object === "object" && object !== null) {
    const blocks = (object as Record<string, unknown>).blocks;
    entries = Array.isArray(blocks) ? blocks : [];
  } else {
    throw new DayPlanParseError();
  }

  const tasksByKey = new Map(context.taskKeys.map(({ key, task }) => [key.toLowerCase(), task.id]));
  const tasksByID = new Map(context.tasks.map((task) => [task.id.toLowerCase(), task.id]));
  const midnight = startOfDay(context.now, context.timeZone);
  const blocks: PlanBlock[] = [];
  for (const entry of entries) {
    if (typeof entry !== "object" || entry === null || Array.isArray(entry)) continue;
    const fields = entry as Record<string, unknown>;
    const start = typeof fields.start === "string" ? planTime(fields.start, midnight, context.timeZone) : undefined;
    const end = typeof fields.end === "string" ? planTime(fields.end, midnight, context.timeZone) : undefined;
    const title = typeof fields.title === "string" ? normalizedTitle(fields.title) : undefined;
    if (start === undefined || end === undefined || !(end > start) || title === undefined) continue;
    /* The first key present wins, as Swift's `??` over the dictionary's values does. */
    const rawKey = "task" in fields ? fields.task : "taskId" in fields ? fields.taskId : fields.linkedTaskID;
    const taskKey = typeof rawKey === "string" ? trimHorizontal(rawKey).toLowerCase() : undefined;
    const linked = taskKey === undefined ? undefined : (tasksByKey.get(taskKey) ?? tasksByID.get(taskKey));
    blocks.push(planBlock({ start, end, title, linkedTaskID: linked }));
  }
  return blocks;
}

/**
 * Makes a proposal safe to write to the calendar: each block is clipped to
 * the free gaps (keeping its longest piece), blocks are ordered, overlaps
 * are trimmed off the later one, anything under the minimum is dropped,
 * and the list is capped at `limit`.
 */
export function validateDayPlan(blocks: readonly PlanBlock[], context: DayPlanContext, limit: number = MAXIMUM_BLOCKS): PlanBlock[] {
  const minimum = MINIMUM_BLOCK_MINUTES * 60;
  const clipped: PlanBlock[] = [];
  for (const block of blocks) {
    const pieces = context.gaps
      .map((gap) => intersection(gap, block))
      .filter((piece): piece is DateInterval => piece !== undefined);
    const longest = longestInterval(pieces);
    if (longest === undefined || intervalDuration(longest) < minimum) continue;
    clipped.push({ ...block, start: longest.start, end: longest.end });
  }
  const accepted: PlanBlock[] = [];
  for (const candidate of clipped.sort(compareBlocks)) {
    let block = candidate;
    const previous = accepted.at(-1);
    if (previous !== undefined && block.start < previous.end) block = { ...block, start: previous.end };
    if (block.end - block.start < minimum) continue;
    accepted.push(block);
    if (accepted.length === limit) break;
  }
  return accepted;
}

/** Parses and validates in one step, as the panel uses it. */
export function dayPlanProposalBlocks(text: string, context: DayPlanContext): PlanBlock[] {
  return validateDayPlan(parseDayPlan(text, context), context);
}

/** The id for a block read from a file or a test, or a fresh one. */
export function blockID(text: string | undefined): string {
  return (text === undefined ? undefined : parseUUID(text)) ?? newUUID();
}
