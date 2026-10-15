import { ACTIVITY_KINDS, ACTIVITY_METADATA, ACTIVITY_UNITS, activityDay, makeActivityRecord } from "../activity/activityRecord";
import type { ActivityRecord } from "../activity/activityRecord";
import { wallTime } from "../calendar/zonedCalendar";
import { durationMinutes, durationQuantity } from "../formatting/durationFormat";
import { joinSentences } from "../formatting/sentences";
import { tr } from "../localization/tr";
import type { ModuleID } from "../modules/moduleId";
import type { DocumentStore } from "../persistence/documentStore";
import { documentName } from "../persistence/documentStore";
import { isJSONObject, type JSONObject } from "../persistence/json";
import { VersionedJSON } from "../persistence/versionedJson";
import { countsAsDone, type StudyPhaseOutcome } from "../studyMethods/studyPhaseRecord";
import type { Instant, Seconds } from "../time";
import type { PlannerDay } from "./plannerDay";
import { isPlannerDayKey, type PlannerDayKey } from "./plannerDayKey";
import type { ProgressItem, StudyDayTally } from "./providedWork";
import { samplePlannerDay } from "./plannerSampleData";
import type { PlannerSampleDay } from "./todayPlanSettings";
import { roundHalfAwayFromZero } from "./upcomingEvent";

/** Port of DayReviewCount: how much of one shared goal got done today, e.g. 112 cards of "Anki reviews". */
export interface DayReviewCount {
  readonly title: string;
  readonly count: number;
  /** Plural noun for the count, e.g. "cards". */
  readonly unit: string;
}

/** The count in its unit, "84 cards" or "1h 30m". */
export function reviewCountAmount(count: DayReviewCount, locale = "en-US"): string {
  return durationQuantity(count.count, count.unit, locale);
}

/**
 * Port of DayReview: the end-of-day review, what got done, what carries
 * over and how much focused work happened, plus a short encouraging line.
 * Stores plain titles rather than item ids that may later change.
 */
export interface DayReview {
  readonly date: PlannerDayKey;
  /** Titles of tasks finished today, in list order. */
  readonly done: readonly string[];
  /** Titles of unfinished tasks that roll over to tomorrow. */
  readonly carryingOver: readonly string[];
  /** Focus phases that ran to their end today. */
  readonly focusSessions: number;
  /** Minutes of completed focus time today. */
  readonly focusMinutes: number;
  /** Study minutes, sessions and points from the modules that keep them; undefined when none does. */
  readonly study?: StudyDayTally;
  /** What other modules' goals got done today. */
  readonly progress: readonly DayReviewCount[];
  /** One or two encouraging sentences; undefined until the AI (or the fallback) answers. */
  readonly summary?: string;
}

/** Whether there is anything to look back on at all. */
export function reviewIsEmpty(review: DayReview): boolean {
  return (
    review.done.length === 0 &&
    review.carryingOver.length === 0 &&
    review.focusSessions === 0 &&
    (review.study?.minutes ?? 0) === 0 &&
    !review.progress.some((count) => count.count > 0)
  );
}

/** Port of DayReviewStat: one figure on the Wrap Up card, an SF Symbol name, a caption and a tooltip. */
export interface DayReviewStat {
  readonly symbol: string;
  readonly text: string;
  readonly help: string;
}

/** Fast model alias; the answer is a sentence or two. */
export const DAY_REVIEW_MODEL = "haiku";
/** From this local hour on, Wrap up is offered prominently. */
export const WRAP_UP_HOUR = 17;
/** Longest summary the review card shows before it is cut at a word. */
export const MAXIMUM_SUMMARY_LENGTH = 220;

/** Whether the day is far enough along to suggest wrapping up. */
export function isWrapUpTime(now: Instant, timeZone: string): boolean {
  return wallTime(now, timeZone).hour >= WRAP_UP_HOUR;
}

/**
 * Whether a focus stretch counts as a finished session: phases that ran
 * out or were stopped at their normal end. A record without an outcome (a
 * module that logs only finished stretches) does.
 */
export function countsAsFinishedSession(record: ActivityRecord): boolean {
  const outcome = record.metadata[ACTIVITY_METADATA.outcome];
  if (outcome === undefined) return true;
  const known: readonly string[] = ["completed", "stopped", "skipped", "abandoned"];
  return known.includes(outcome) ? countsAsDone(outcome as StudyPhaseOutcome) : false;
}

/**
 * Port of DayReviewer.review: the review of `day`'s checklist and the
 * focus stretches in the shared activity log that ended that day (from any
 * timer), plus the study tally and how far each shared goal got (goals
 * with nothing due today are left out).
 */
export function reviewDay(
  day: PlannerDay,
  activity: readonly ActivityRecord[],
  timeZone: string,
  study?: StudyDayTally,
  progress: readonly ProgressItem[] = [],
): DayReview {
  const sessions = activity.filter(
    (record) =>
      record.kind === ACTIVITY_KINDS.focusCompleted && activityDay(record, timeZone) === day.date && countsAsFinishedSession(record),
  );
  const minutes = sessions.reduce((sum, record) => sum + (record.quantity ?? (record.end - record.start) / 60), 0);
  const review: { -readonly [Key in keyof DayReview]: DayReview[Key] } = {
    date: day.date,
    done: day.items.filter((item) => item.isDone).map((item) => item.title),
    carryingOver: day.items.filter((item) => !item.isDone).map((item) => item.title),
    focusSessions: sessions.length,
    focusMinutes: roundHalfAwayFromZero(minutes),
    progress: progress
      .filter((goal) => goal.target > 0 || goal.completed > 0)
      .map((goal) => ({ title: goal.title, count: Math.max(goal.completed, 0), unit: goal.unit })),
  };
  if (study !== undefined) review.study = study;
  return review;
}

/**
 * The figures under the summary, in order: study time and sessions (or
 * focus sessions when no module keeps a study tally), each shared goal's
 * count, then points earned.
 */
export function reviewStats(review: DayReview, locale = "en-US"): DayReviewStat[] {
  const stats: DayReviewStat[] = [];
  const study = review.study;
  if (study !== undefined) {
    const text =
      study.minutes > 0 || study.sessions > 0
        ? `${durationMinutes(study.minutes)} · ${tr("%lld sessions", study.sessions)}`
        : tr("No study yet");
    stats.push({ symbol: "book.closed.fill", text, help: tr("Time studied today and study sessions finished") });
  } else {
    const text =
      review.focusSessions > 0
        ? `${tr("%lld focus sessions", review.focusSessions)} · ${durationMinutes(review.focusMinutes)}`
        : tr("No focus sessions today");
    stats.push({ symbol: "scope", text, help: tr("Focus sessions completed today") });
  }
  for (const goal of review.progress) {
    const amount = reviewCountAmount(goal, locale);
    stats.push({ symbol: "checkmark.circle", text: amount, help: tr("%@: %@ done today", goal.title, amount) });
  }
  if (study !== undefined) {
    stats.push({
      symbol: "star.fill",
      text: tr("%lld pts", study.points),
      help: tr("Study points earned today, to spend on your pet's outfits"),
    });
  }
  return stats;
}

/** Arguments for `claude -p` before `-- <prompt>`: no tools and no MCP servers, only text. */
export function dayReviewArguments(): string[] {
  return ["--model", DAY_REVIEW_MODEL, "--tools", "", "--strict-mcp-config"];
}

/** The prompt that asks the AI for the review's summary. */
export function dayReviewPrompt(review: DayReview, locale = "en-US"): string {
  const list = (titles: readonly string[]) => (titles.length === 0 ? "- none" : titles.map((title) => `- ${title}`).join("\n"));
  const lines: string[] = [];
  if (review.study !== undefined) {
    lines.push(
      `Studied: ${review.study.minutes} minutes over ${review.study.sessions} sessions, ${review.study.points} points earned`,
    );
  }
  for (const goal of review.progress) lines.push(`${goal.title}: ${reviewCountAmount(goal, locale)} done`);
  return [
    "Someone is wrapping up their workday. Write one or two short, warm, specific sentences " +
      "that acknowledge what they finished and set up tomorrow. " +
      "No greeting, no emoji, no lists, no quotes, under 40 words. Plain text only.",
    "",
    "Done today:",
    list(review.done),
    "",
    "Carrying over to tomorrow:",
    list(review.carryingOver),
    "",
    `Focus sessions completed: ${review.focusSessions} (${review.focusMinutes} minutes)` + lines.map((line) => `\n${line}`).join(""),
  ].join("\n");
}

const QUOTES = new Set(['"', "'", "“", "”", "‘", "’"]);

/**
 * Turns the AI's answer into a card-sized summary: strips code fences,
 * wrapping quotes and line breaks, keeps at most two sentences, and cuts
 * overly long text at a word with an ellipsis. Undefined when nothing
 * readable remains.
 */
export function reviewSummary(text: string): string | undefined {
  let cleaned = text
    .replaceAll("```", " ")
    .split(/\s+/u)
    .filter((piece) => piece !== "")
    .join(" ");
  while (cleaned.length > 1 && QUOTES.has(cleaned.charAt(0)) && QUOTES.has(cleaned.charAt(cleaned.length - 1))) {
    cleaned = cleaned.slice(1, -1).trim();
  }
  if (cleaned === "") return undefined;
  const sentences: string[] = [];
  for (const segment of new Intl.Segmenter("en", { granularity: "sentence" }).segment(cleaned)) {
    const sentence = segment.segment.trim();
    if (sentence !== "") sentences.push(sentence);
    if (sentences.length === 2) break;
  }
  const joined = sentences.length === 0 ? cleaned : sentences.join(" ");
  const characters = [...joined];
  if (characters.length <= MAXIMUM_SUMMARY_LENGTH) return joined;
  const prefix = characters.slice(0, MAXIMUM_SUMMARY_LENGTH - 1).join("");
  const space = prefix.lastIndexOf(" ");
  const cut = space >= 0 ? prefix.slice(0, space) : prefix;
  return `${cut.replace(/^[\p{P}\s]+|[\p{P}\s]+$/gu, "")}…`;
}

/** A friendly line written locally, used when the AI is unavailable, so the review never ends in an error. */
export function fallbackReviewSummary(review: DayReview): string {
  const finished = review.done.length;
  const carrying = review.carryingOver.length;
  if (finished === 0 && carrying === 0) {
    const minutes = review.study?.minutes ?? 0;
    if (minutes > 0) return tr("You put in %@ of study today. Rest up and start fresh tomorrow.", durationMinutes(minutes));
    return review.focusSessions > 0
      ? tr("You put in %lld focus sessions today. Rest up and start fresh tomorrow.", review.focusSessions)
      : tr("A quiet day. Rest up and start fresh tomorrow.");
  }
  if (finished === 0) return tr("Not every day is a checklist day. Tomorrow starts with %lld tasks ready to go.", carrying);
  if (carrying === 0) return tr("You cleared all %lld tasks today. Enjoy the evening.", finished);
  return joinSentences([tr("You finished %lld tasks today.", finished), tr("%lld tasks will be waiting tomorrow.", carrying)]);
}

/**
 * The review of the sample day for demo mode, with a canned summary so no
 * AI call is needed. Pass shared `progress` and a `study` tally to preview
 * a study day's wrap-up.
 */
export function sampleDayReview(
  date: PlannerDayKey,
  timeZone: string,
  kind: PlannerSampleDay = "work",
  study?: StudyDayTally,
  progress: readonly ProgressItem[] = [],
): DayReview {
  const review = reviewDay(samplePlannerDay(date, kind, timeZone), [], timeZone, study, progress);
  return {
    ...review,
    focusSessions: 3,
    focusMinutes: 75,
    summary:
      kind === "work"
        ? "Strong day: the essay outline and the reply to Sam are both done. " +
          "Start tomorrow with chapter 4 while your focus is fresh."
        : "Solid study day: the pathology notes, the lecture recording, and the email are done. " +
          "Start tomorrow with the cardio questions while your focus is fresh.",
  };
}

/** The review file format. Version 1 added the `schemaVersion` key. */
export const DAY_REVIEW_SCHEMA = new VersionedJSON(1);

function stringList(value: unknown, key: string): string[] {
  if (!Array.isArray(value) || !value.every((entry) => typeof entry === "string")) throw new TypeError(`Invalid ${key}`);
  return value as string[];
}

function integer(value: unknown, key: string): number {
  if (typeof value !== "number" || !Number.isInteger(value)) throw new TypeError(`Invalid ${key}`);
  return value;
}

/** Reads a review the way the Mac decodes one; reviews saved before study stats have no `progress`. Throws on a malformed file. */
export function decodeDayReview(document: JSONObject): DayReview {
  const date = document.date;
  if (typeof date !== "string" || !isPlannerDayKey(date)) throw new TypeError("Invalid date");
  const review: { -readonly [Key in keyof DayReview]: DayReview[Key] } = {
    date,
    done: stringList(document.done, "done"),
    carryingOver: stringList(document.carryingOver, "carryingOver"),
    focusSessions: integer(document.focusSessions, "focusSessions"),
    focusMinutes: integer(document.focusMinutes, "focusMinutes"),
    progress: [],
  };
  const study = document.study;
  if (study !== undefined && study !== null) {
    if (!isJSONObject(study)) throw new TypeError("Invalid study");
    review.study = {
      minutes: integer(study.minutes ?? 0, "study.minutes"),
      sessions: integer(study.sessions ?? 0, "study.sessions"),
      points: integer(study.points ?? 0, "study.points"),
    };
  }
  const progress = document.progress;
  if (progress !== undefined && progress !== null) {
    if (!Array.isArray(progress)) throw new TypeError("Invalid progress");
    review.progress = progress.map((entry) => {
      if (!isJSONObject(entry) || typeof entry.title !== "string" || typeof entry.unit !== "string") {
        throw new TypeError("Invalid progress entry");
      }
      return { title: entry.title, count: integer(entry.count, "progress.count"), unit: entry.unit };
    });
  }
  if (typeof document.summary === "string") review.summary = document.summary;
  return review;
}

/** The review as the Mac encodes it, nil fields left out. */
export function encodeDayReview(review: DayReview): JSONObject {
  const json: JSONObject = {
    date: review.date,
    done: [...review.done],
    carryingOver: [...review.carryingOver],
    focusSessions: review.focusSessions,
    focusMinutes: review.focusMinutes,
    progress: review.progress.map((count) => ({ title: count.title, count: count.count, unit: count.unit })),
  };
  if (review.study !== undefined) {
    json.study = { minutes: review.study.minutes, sessions: review.study.sessions, points: review.study.points };
  }
  if (review.summary !== undefined) json.summary = review.summary;
  return json;
}

/** Port of DayReviewRepository: one review per day as `Reviews/yyyy-MM-dd.json` in the edition's storage. */
export class DayReviewRepository {
  /** The folder in an edition's storage. */
  static readonly folderName = "Reviews";

  constructor(
    private readonly store: DocumentStore,
    readonly folder: string = DayReviewRepository.folderName,
  ) {}

  documentName(date: PlannerDayKey): string {
    return documentName(this.folder, `${date}.json`);
  }

  /** The saved review, or undefined if none exists. Rejects on an unreadable file. */
  async load(date: PlannerDayKey): Promise<DayReview | undefined> {
    const text = await this.store.read(this.documentName(date));
    return text === undefined ? undefined : DAY_REVIEW_SCHEMA.decode(text, decodeDayReview);
  }

  /** Writes the review, replacing an earlier one of the same day. */
  async save(review: DayReview): Promise<void> {
    await this.store.write(this.documentName(review.date), DAY_REVIEW_SCHEMA.encode(encodeDayReview(review), { pretty: true, sortedKeys: true }));
  }
}

/** Port of FocusSessionLog.Session: a completed focus phase as builds before the activity log kept them. */
export interface FocusLogSession {
  readonly endedAt: Instant;
  readonly duration: Seconds;
}

/** Seconds from 1970 to 2001, the Mac's reference date. */
const REFERENCE_DATE_OFFSET = 978_307_200;

/**
 * The same UUID for the same session on every launch: the big-endian bit
 * patterns of its end time (seconds since 2001) and length fill the 16
 * bytes, as the Mac derives it.
 */
export function focusLogSessionID(session: FocusLogSession): string {
  const view = new DataView(new ArrayBuffer(16));
  view.setFloat64(0, session.endedAt - REFERENCE_DATE_OFFSET);
  view.setFloat64(8, session.duration);
  const hex = [...new Uint8Array(view.buffer)].map((byte) => byte.toString(16).padStart(2, "0").toUpperCase()).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

/**
 * Port of FocusSessionLog.activityRecords: each legacy session as the
 * record the Pomodoro logs for a finished focus phase, with ids from the
 * session itself so a retried move skips what it already wrote.
 */
export function focusLogActivityRecords(sessions: readonly FocusLogSession[], source: ModuleID): ActivityRecord[] {
  return sessions.map((session) =>
    makeActivityRecord({
      id: focusLogSessionID(session),
      source,
      kind: ACTIVITY_KINDS.focusCompleted,
      start: session.endedAt - session.duration,
      end: session.endedAt,
      quantity: session.duration / 60,
      unit: ACTIVITY_UNITS.minutes,
      metadata: { [ACTIVITY_METADATA.method]: "pomodoro", [ACTIVITY_METADATA.outcome]: "completed" },
    }),
  );
}
