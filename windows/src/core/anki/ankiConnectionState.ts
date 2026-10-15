import type { Instant, Seconds } from "../time";
import { type AnkiConnectError, AnkiErrors } from "./ankiConnectError";

/**
 * Port of AnkiRecovery: how fast to retry Anki after a problem. Most
 * problems end by themselves within seconds (a sync finishes, a dialog
 * closes), so the first minute retries every few seconds, the next few
 * minutes less often, and after that once a minute, while someone looks.
 */
export const AnkiRecovery = {
  /** The retry interval during the first `fastWindow` of a problem. */
  fastInterval: 4,
  /** How long a problem gets fast retries, also the only time it is retried with nothing on screen. */
  fastWindow: 60,
  /** The retry interval after the fast window, up to `slowWindow`. */
  slowInterval: 15,
  slowWindow: 5 * 60,
  /** The retry interval for a problem that lasts longer. */
  idleInterval: 60,

  /** Seconds until the next retry of a problem that started `problemAge` seconds ago. */
  interval(problemAge: Seconds): Seconds {
    if (problemAge < AnkiRecovery.fastWindow) return AnkiRecovery.fastInterval;
    if (problemAge < AnkiRecovery.slowWindow) return AnkiRecovery.slowInterval;
    return AnkiRecovery.idleInterval;
  },

  /** Whether to retry with nothing on screen: only in the fast window. */
  pollsWhileHidden(problemAge: Seconds): boolean {
    return problemAge < AnkiRecovery.fastWindow;
  },
} as const;

/**
 * Port of AnkiConnectionState: where the Anki tab stands with AnkiConnect,
 * one case per screen the panel can show. Built from the latest refresh by
 * `resolveAnkiConnectionState`, so the rules are testable.
 */
export type AnkiConnectionState =
  /** Before the first refresh finishes. */
  | { kind: "checking" }
  /** No Anki app on this PC. */
  | { kind: "notInstalled" }
  /** Anki is installed but closed. */
  | { kind: "notRunning" }
  /** Anki was just opened and AnkiConnect isn't listening yet. */
  | { kind: "starting" }
  /** Anki runs but nothing answers on the port. */
  | { kind: "addOnMissing" }
  /** AnkiConnect answered but won't let us in; the error says why. */
  | { kind: "needsPermission"; error: AnkiConnectError }
  /** The add-on is too old for API version 6. */
  | { kind: "addOnOutdated" }
  /** Connected; the summary is current. */
  | { kind: "ready" }
  /** Anything else; transient, so the panel keeps the last summary if it has one. */
  | { kind: "problem"; error: AnkiConnectError };

/**
 * How long after Anki launches a refused connection still means "starting"
 * rather than "add-on missing".
 */
export const ANKI_STARTUP_GRACE: Seconds = 15;

/**
 * The state for a refresh outcome: `error` is the refresh's error or
 * undefined when it worked, `isInstalled` whether Anki exists on disk, and
 * `launchedAt` when the running Anki process started, if known.
 */
export function resolveAnkiConnectionState(
  error: AnkiConnectError | undefined,
  isInstalled: boolean,
  launchedAt: Instant | undefined,
  now: Instant,
): AnkiConnectionState {
  if (!error) return { kind: "ready" };
  switch (error.kind) {
    case "ankiNotRunning":
      /*
       * The HTTP probe is the source of truth: an install we couldn't find
       * (a portable copy) still runs, so only a refused connection with
       * nothing on disk reads as "not installed".
       */
      return isInstalled ? { kind: "notRunning" } : { kind: "notInstalled" };
    case "addOnMissing":
      if (launchedAt !== undefined && now - launchedAt < ANKI_STARTUP_GRACE) return { kind: "starting" };
      return { kind: "addOnMissing" };
    case "permissionDenied":
    case "apiKeyRequired":
      return { kind: "needsPermission", error };
    case "addOnOutdated":
    case "unsupportedAction":
      return { kind: "addOnOutdated" };
    case "timeout":
    case "collectionUnavailable":
    case "syncNotConfigured":
    case "anki":
    case "invalidResponse":
    case "transport":
      return { kind: "problem", error };
  }
}

/** True for the states that need the user to act before any numbers can show. */
export function isSetupStep(state: AnkiConnectionState): boolean {
  switch (state.kind) {
    case "notInstalled":
    case "notRunning":
    case "starting":
    case "addOnMissing":
    case "needsPermission":
    case "addOnOutdated":
      return true;
    case "checking":
    case "ready":
    case "problem":
      return false;
  }
}

/**
 * Whether a summary from an earlier refresh is still worth showing: a
 * transient problem keeps it (dimmed as stale); a setup step means Anki is
 * gone, so old numbers would mislead.
 */
export function keepsLastSummary(state: AnkiConnectionState): boolean {
  return state.kind === "ready" || state.kind === "problem" || state.kind === "checking";
}

/**
 * How often to refresh while the panel is visible. Setup steps poll quickly
 * so the panel flips to the decks moments after the user opens Anki;
 * otherwise due counts only change as the user reviews.
 */
export function refreshInterval(state: AnkiConnectionState, problemAge: Seconds = 0): Seconds {
  switch (state.kind) {
    case "starting":
      return 2;
    case "notRunning":
    case "addOnMissing":
    case "needsPermission":
    case "addOnOutdated":
    case "checking":
      return 5;
    case "problem":
      return AnkiRecovery.interval(problemAge);
    case "notInstalled":
      return 60;
    case "ready":
      return 180;
  }
}

/**
 * Whether to keep refreshing while the panel is hidden: while Anki is
 * starting, and for a problem's first minute, so Today and the ticker get
 * numbers back without opening the panel. Both are bounded.
 */
export function pollsWhileHidden(state: AnkiConnectionState, problemAge: Seconds = 0): boolean {
  if (state.kind === "starting") return true;
  if (state.kind === "problem") return AnkiRecovery.pollsWhileHidden(problemAge);
  return false;
}

/**
 * Parses a state name for pinning the Anki tab to one screen in snapshot
 * runs. Undefined for an unknown name.
 */
export function ankiConnectionStateFromPreviewName(name: string): AnkiConnectionState | undefined {
  switch (name.toLowerCase()) {
    case "checking":
      return { kind: "checking" };
    case "notinstalled":
      return { kind: "notInstalled" };
    case "notrunning":
      return { kind: "notRunning" };
    case "starting":
      return { kind: "starting" };
    case "addonmissing":
      return { kind: "addOnMissing" };
    case "permission":
    case "permissiondenied":
      return { kind: "needsPermission", error: AnkiErrors.permissionDenied };
    case "apikey":
    case "apikeyrequired":
      return { kind: "needsPermission", error: AnkiErrors.apiKeyRequired };
    case "addonoutdated":
      return { kind: "addOnOutdated" };
    case "problem":
      return { kind: "problem", error: AnkiErrors.timeout };
    case "collection":
    case "collectionunavailable":
    case "profile":
      return { kind: "problem", error: AnkiErrors.collectionUnavailable };
    case "anki":
    case "ankierror":
      return {
        kind: "problem",
        error: AnkiErrors.anki("AnkiConnect.getDeckStats() missing 1 required positional argument: 'decks'"),
      };
    case "ready":
      return { kind: "ready" };
    default:
      return undefined;
  }
}
