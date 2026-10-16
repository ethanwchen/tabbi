import { joinSentences } from "../formatting/sentences";
import { tr } from "../localization/tr";

/** The add-on's AnkiWeb code, for install instructions. */
export const ANKI_CONNECT_ADD_ON_CODE = "2055492159";

/**
 * Port of AnkiConnectError: every way an AnkiConnect call can fail,
 * classified into states the UI can explain in one line with one clear
 * next step.
 */
export type AnkiConnectError =
  /** Connection refused and no Anki process is running. */
  | { kind: "ankiNotRunning" }
  /**
   * Connection refused while Anki is running: the add-on is missing or
   * disabled, or Anki is still starting.
   */
  | { kind: "addOnMissing" }
  /** The request reached Anki but it did not answer in time. */
  | { kind: "timeout" }
  /** `requestPermission` was denied, or the origin was rejected (HTTP 403). */
  | { kind: "permissionDenied" }
  /** The user set an API key in AnkiConnect and ours is missing or wrong. */
  | { kind: "apiKeyRequired" }
  /** The installed add-on speaks an older API than version 6. */
  | { kind: "addOnOutdated"; version: number }
  /** The add-on does not know this action (too old for it). */
  | { kind: "unsupportedAction"; action: string }
  /**
   * Anki has no collection open right now: Anki is on its profile list, or
   * it closed the collection for a while (a full sync, Check Database).
   */
  | { kind: "collectionUnavailable" }
  /** `sync` was asked for but the user has not signed in to AnkiWeb. */
  | { kind: "syncNotConfigured" }
  /** Any other error string AnkiConnect returned, as Anki wrote it. */
  | { kind: "anki"; message: string }
  /** The reply was not the JSON we expected. */
  | { kind: "invalidResponse"; message: string }
  /** Some other network failure. */
  | { kind: "transport"; message: string };

/** Short constructors, so call sites read like the Swift cases. */
export const AnkiErrors = {
  ankiNotRunning: { kind: "ankiNotRunning" },
  addOnMissing: { kind: "addOnMissing" },
  timeout: { kind: "timeout" },
  permissionDenied: { kind: "permissionDenied" },
  apiKeyRequired: { kind: "apiKeyRequired" },
  collectionUnavailable: { kind: "collectionUnavailable" },
  syncNotConfigured: { kind: "syncNotConfigured" },
  addOnOutdated: (version: number): AnkiConnectError => ({ kind: "addOnOutdated", version }),
  unsupportedAction: (action: string): AnkiConnectError => ({ kind: "unsupportedAction", action }),
  anki: (message: string): AnkiConnectError => ({ kind: "anki", message }),
  invalidResponse: (message: string): AnkiConnectError => ({ kind: "invalidResponse", message }),
  transport: (message: string): AnkiConnectError => ({ kind: "transport", message }),
} as const satisfies Record<string, AnkiConnectError | ((value: never) => AnkiConnectError)>;

/** Thrown by the client; `error` says what went wrong. */
export class AnkiConnectFailure extends Error {
  constructor(readonly error: AnkiConnectError) {
    super(`AnkiConnect: ${error.kind}${"message" in error ? `: ${error.message}` : ""}`);
    this.name = "AnkiConnectFailure";
  }
}

export function sameAnkiError(a: AnkiConnectError, b: AnkiConnectError): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}

/**
 * The errors AnkiConnect and Anki's backend return while no collection is
 * open, compared whole (lowercased, without a final period) so an unrelated
 * error that merely mentions a collection is never read as one of them.
 * "collection is not available" is the older add-on with no profile open,
 * "database is not available" and friends a full sync, "CollectionNotOpen"
 * the backend, and the 2026.10 rewrite says "Collection is not available.",
 * "A collection operation is active." and "Collection session changed.".
 */
const collectionClosedMessages = new Set([
  "collection is not available",
  "database is not available",
  "decks are not available",
  "scheduler is not available",
  "media is not available",
  "collectionnotopen",
  "collection session changed",
  "a collection operation is active",
  "collection lifecycle operation is active",
]);

/** Maps an AnkiConnect `error` string to a typed case. */
export function errorFromAnkiMessage(message: string, action: string): AnkiConnectError {
  let lower = message.trim().toLowerCase();
  if (lower.endsWith(".")) lower = lower.slice(0, -1);
  /* AnkiConnect: "valid api key must be provided". */
  if (lower.includes("api key")) return AnkiErrors.apiKeyRequired;
  if (lower === "unsupported action") return AnkiErrors.unsupportedAction(action);
  if (collectionClosedMessages.has(lower)) return AnkiErrors.collectionUnavailable;
  /* AnkiConnect: "sync: auth not configured". */
  if (lower.endsWith("auth not configured")) return AnkiErrors.syncNotConfigured;
  return AnkiErrors.anki(message);
}

/**
 * Whether AnkiConnect could not parse the request body as JSON (Python's
 * "Expecting value: line 1 column 1 (char 0)" and kin): the request reached
 * it damaged, which one retry fixes when it was a fluke.
 */
export function isMalformedRequest(error: AnkiConnectError): boolean {
  if (error.kind !== "anki") return false;
  return error.message.startsWith("Expecting value") || error.message.startsWith("Expecting property name");
}

/**
 * Whether Tabbi can't say what went wrong: an error Tabbi doesn't know, a
 * reply it can't read, or a request that failed some other way. These show
 * the raw message and a reminder to check the add-on.
 */
export function isUnexplained(error: AnkiConnectError): boolean {
  return error.kind === "anki" || error.kind === "invalidResponse" || error.kind === "transport";
}

/**
 * Whether this error means nothing can be read right now (Anki is closed,
 * busy, without a collection or locked), rather than one action failing on
 * its own.
 */
export function failsWholeRefresh(error: AnkiConnectError): boolean {
  return !(error.kind === "anki" || error.kind === "invalidResponse" || error.kind === "unsupportedAction");
}

/** The longest message shown; enough for any AnkiConnect error, short enough for two lines. */
export const MESSAGE_LIMIT = 90;

const graphemes = new Intl.Segmenter("en", { granularity: "grapheme" });

/** Splits text into user-perceived characters, as Swift's `String.count` counts them. */
export function characters(text: string): string[] {
  return Array.from(graphemes.segment(text), (segment) => segment.segment);
}

/**
 * The raw message as one short line: whitespace collapsed and long text
 * (a Python error can run on) cut at `MESSAGE_LIMIT` characters.
 */
export function shortMessage(text: string): string {
  const line = text.split(/\s+/u).filter((word) => word.length > 0).join(" ");
  const chars = characters(line);
  if (chars.length <= MESSAGE_LIMIT) return line.length === 0 ? "?" : line;
  return chars.slice(0, MESSAGE_LIMIT - 1).join("").trim() + "…";
}

/** What Anki (or the network) actually said, as one short line, for the unexplained errors. */
export function errorMessage(error: AnkiConnectError): string | undefined {
  switch (error.kind) {
    case "anki":
    case "invalidResponse":
    case "transport":
      return shortMessage(error.message);
    default:
      return undefined;
  }
}

/** The quoted message under an unexplained error, such as "Anki said: <message>". */
export function quotedMessage(error: AnkiConnectError): string | undefined {
  const message = errorMessage(error);
  if (message === undefined) return undefined;
  if (error.kind === "anki") return tr("Anki said: “%@”", message);
  return tr("Details: %@", message);
}

/** `quotedMessage` as a sentence, to lead a longer explanation. */
export function messageSentence(error: AnkiConnectError): string | undefined {
  const message = errorMessage(error);
  if (message === undefined) return undefined;
  if (error.kind === "anki") return tr("Anki said “%@”.", message);
  const quoted = quotedMessage(error);
  return quoted === undefined ? undefined : quoted + ".";
}

/** The reminder an unexplained error ends with, beside a Copy code button. */
export function addOnReminder(): string {
  return tr("Make sure the AnkiConnect add-on is installed and Anki was restarted after installing it.");
}

/** `addOnReminder` with the add-on's code, for places without a Copy code button. */
export function addOnReminderWithCode(): string {
  return tr(
    "Make sure the AnkiConnect add-on (code %@) is installed and Anki was restarted after installing it.",
    ANKI_CONNECT_ADD_ON_CODE,
  );
}

/** Why Anki's cards are closed for now, and that Tabbi waits it out. */
export function collectionUnavailableMessage(): string {
  return tr("Anki may be syncing, checking its database or showing a dialog. Tabbi reconnects when it's done.");
}

/** The hint beside Open Anki while the collection is closed. */
export function profileListHint(): string {
  return tr("On the profile list? Open your profile.");
}

/** Short headline for an empty or error state. */
export function errorTitle(error: AnkiConnectError): string {
  switch (error.kind) {
    case "ankiNotRunning":
      return tr("Anki is closed");
    case "addOnMissing":
      return tr("AnkiConnect isn't answering");
    case "timeout":
      return tr("Anki is busy");
    case "permissionDenied":
      return tr("Anki said no");
    case "apiKeyRequired":
      return tr("AnkiConnect needs your API key");
    case "addOnOutdated":
    case "unsupportedAction":
      return tr("AnkiConnect is out of date");
    case "collectionUnavailable":
      return tr("Waiting for Anki");
    case "syncNotConfigured":
      return tr("Sign in to AnkiWeb to sync");
    case "anki":
      return tr("Anki reported a problem");
    case "invalidResponse":
      return tr("Unexpected reply from Anki");
    case "transport":
      return tr("Couldn't reach Anki");
  }
}

/**
 * What to do next, in a sentence or two. For an unexplained error it also
 * quotes the message and reminds the user to check the add-on.
 */
export function errorSuggestion(error: AnkiConnectError): string {
  switch (error.kind) {
    case "ankiNotRunning":
      return tr("Open Anki to see your due cards.");
    case "addOnMissing":
      return tr("Install AnkiConnect (code %@) from Tools › Add-ons, then restart Anki.", ANKI_CONNECT_ADD_ON_CODE);
    case "timeout":
      return tr("Close any open Anki dialog. If it keeps happening, turn off App Nap for Anki.");
    case "permissionDenied":
      return tr("Allow Tabbi in AnkiConnect's settings, then try again.");
    case "apiKeyRequired":
      return tr("Enter the key from AnkiConnect's config in Settings.");
    case "addOnOutdated":
    case "unsupportedAction":
      return tr("Update AnkiConnect from Tools › Add-ons › Check for Updates.");
    case "collectionUnavailable":
      return collectionUnavailableMessage();
    case "syncNotConfigured":
      return tr("Log in from Anki's Sync button once, then sync here.");
    case "anki":
    case "invalidResponse":
    case "transport":
      return joinSentences([messageSentence(error) ?? "", addOnReminderWithCode()]);
  }
}

