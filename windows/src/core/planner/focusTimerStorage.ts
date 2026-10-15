import { FocusTimer, FocusTimerConfig, type FocusPhase, type FocusRunState } from "../focus/focusTimer";
import type { Defaults } from "../persistence/defaults";
import { defaultsString } from "../persistence/defaults";
import { isJSONObject, type JSONObject } from "../persistence/json";
import { VersionedJSON } from "../persistence/versionedJson";
import type { Instant } from "../time";
import type { FocusLogSession } from "./dayReview";
import { parseUUID } from "./uuid";

/*
 * Port of FocusTimerStorage: where the shared Pomodoro timer lives in the
 * preferences, its versioned JSON format, and the session log older builds
 * kept there. Values the Mac keeps as `Data` are JSON text here, the way
 * the core's `Defaults` stores them; the documents inside are the Mac's
 * Codable shapes, with dates as seconds since 2001 (Foundation's default).
 * Moving the `planner.*` keys of builds before settings had a version is
 * `SETTINGS_MIGRATIONS` step 2 in core/settings.
 */

export const FOCUS_TIMER_KEY = "focus.timer";
export const FOCUS_SESSION_LOG_KEY = "focus.sessionLog";
export const FOCUS_LAST_ALIVE_KEY = "focus.lastAlive";

/** The timer format. Version 1 added the `schemaVersion` key. */
export const FOCUS_TIMER_SCHEMA = new VersionedJSON(1);
/** The legacy session log format. Version 1 added the `schemaVersion` key. */
export const FOCUS_SESSION_LOG_SCHEMA = new VersionedJSON(1);

/** Seconds from 1970 to 2001, the reference date Foundation encodes dates against by default. */
const REFERENCE_DATE_OFFSET = 978_307_200;

function finite(value: unknown, key: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) throw new TypeError(`Invalid ${key}`);
  return value;
}

function decodeRunState(json: unknown): FocusRunState {
  if (!isJSONObject(json)) throw new TypeError("Invalid runState");
  if (isJSONObject(json.idle)) return { kind: "idle" };
  if (isJSONObject(json.running)) return { kind: "running", endsAt: finite(json.running.endsAt, "endsAt") + REFERENCE_DATE_OFFSET };
  if (isJSONObject(json.paused)) return { kind: "paused", remaining: finite(json.paused.remaining, "remaining") };
  throw new TypeError("Invalid runState");
}

function encodeRunState(state: FocusRunState): JSONObject {
  switch (state.kind) {
    case "idle":
      return { idle: {} };
    case "running":
      return { running: { endsAt: state.endsAt - REFERENCE_DATE_OFFSET } };
    case "paused":
      return { paused: { remaining: state.remaining } };
  }
}

/** Reads a timer in the Mac's Codable shape; throws on a malformed one. */
export function decodeFocusTimer(document: JSONObject): FocusTimer {
  const phase = document.phase;
  if (phase !== "focus" && phase !== "rest") throw new TypeError("Invalid phase");
  const config = document.config;
  if (!isJSONObject(config)) throw new TypeError("Invalid config");
  const count = document.completedFocusCount;
  if (typeof count !== "number" || !Number.isInteger(count)) throw new TypeError("Invalid completedFocusCount");
  const timer = FocusTimer.withState(
    phase as FocusPhase,
    decodeRunState(document.runState),
    new FocusTimerConfig(finite(config.focusDuration, "focusDuration"), finite(config.restDuration, "restDuration")),
    count,
  );
  const linked = document.linkedItemID;
  if (linked !== undefined && linked !== null) {
    const id = typeof linked === "string" ? parseUUID(linked) : undefined;
    if (id === undefined) throw new TypeError("Invalid linkedItemID");
    timer.linkedItemID = id;
  }
  return timer;
}

/** The timer in the Mac's Codable shape. */
export function encodeFocusTimer(timer: FocusTimer): JSONObject {
  const json: JSONObject = {
    phase: timer.phase,
    runState: encodeRunState(timer.runState),
    config: { focusDuration: timer.config.focusDuration, restDuration: timer.config.restDuration },
    completedFocusCount: timer.completedFocusCount,
  };
  if (timer.linkedItemID !== undefined) json.linkedItemID = timer.linkedItemID;
  return json;
}

/** Reads the legacy session log; throws on a malformed one. */
export function decodeFocusSessionLog(document: JSONObject): FocusLogSession[] {
  if (!Array.isArray(document.sessions)) throw new TypeError("Invalid sessions");
  return document.sessions.map((entry) => {
    if (!isJSONObject(entry)) throw new TypeError("Invalid session");
    return { endedAt: finite(entry.endedAt, "endedAt") + REFERENCE_DATE_OFFSET, duration: finite(entry.duration, "duration") };
  });
}

/** Port of FocusTimerStorage over the core's preferences. */
export class FocusTimerStorage {
  constructor(private readonly defaults: Defaults) {}

  /** The saved timer, or a fresh one when none is saved or it can't be read. */
  loadTimer(): FocusTimer {
    const text = defaultsString(this.defaults, FOCUS_TIMER_KEY);
    if (text === undefined) return new FocusTimer();
    try {
      return FOCUS_TIMER_SCHEMA.decode(text, decodeFocusTimer);
    } catch {
      return new FocusTimer();
    }
  }

  save(timer: FocusTimer): void {
    this.defaults.set(FOCUS_TIMER_KEY, FOCUS_TIMER_SCHEMA.encode(encodeFocusTimer(timer)));
  }

  /**
   * The last moment Tabbi was known to be alive with a session under way
   * (seconds since 1970), so a launch after a crash can end that session
   * there. Undefined when none was saved.
   */
  get lastAlive(): Instant | undefined {
    const value = this.defaults.get(FOCUS_LAST_ALIVE_KEY);
    return typeof value === "number" && Number.isFinite(value) ? value : undefined;
  }

  saveLastAlive(instant: Instant): void {
    this.defaults.set(FOCUS_LAST_ALIVE_KEY, instant);
  }

  /**
   * Hands the session log an older build saved to `move`, and removes it
   * once `move` reports it safely stored elsewhere (the activity log), so a
   * failed move is retried next launch. A log that can't be read is
   * removed without calling `move`, since nothing can be recovered from it.
   */
  async moveSessionLog(move: (sessions: FocusLogSession[]) => boolean | Promise<boolean>): Promise<void> {
    const text = defaultsString(this.defaults, FOCUS_SESSION_LOG_KEY);
    if (text === undefined) return;
    let sessions: FocusLogSession[] | undefined;
    try {
      sessions = FOCUS_SESSION_LOG_SCHEMA.decode(text, decodeFocusSessionLog);
    } catch {
      sessions = undefined;
    }
    if (sessions !== undefined && !(await move(sessions))) return;
    this.defaults.remove(FOCUS_SESSION_LOG_KEY);
  }
}
