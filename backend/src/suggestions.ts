/**
 * The recommendations inbox: `POST /v1/suggestions` takes an idea from the website's Suggest form
 * (a plain HTML form post, answered with a redirect to the site's thank-you page) or from a script
 * using CORS and JSON. The maintainer reads them through `GET /v1/admin/suggestions`.
 *
 * The route needs no account, so it is guarded instead by a honeypot field, per-IP limits (per minute
 * and per day, counted in memory), a global daily cap that bounds storage, and strict validation.
 */
import { HttpError, Obj, oneOf, parseBodyObject, readText } from "./lib";

/** The website form's categories (`SUGGEST_CATEGORIES` in site/build.py): a new tab, an integration, an improvement, something else. */
export const SUGGESTION_CATEGORIES = ["tab", "integration", "improvement", "other"] as const;
/**
 * `website` is the honeypot: hidden from people, filled in by bots. `version`, `macos` and `edition` are
 * hidden fields the form fills in when the app opened it (`FeedbackLink` in TabbiKitCore), so a bug report
 * says which Tabbi and macOS it happened on.
 */
export const SUGGESTION_FIELDS = ["category", "message", "email", "website", "version", "macos", "edition"] as const;

export const MIN_SUGGESTION_MESSAGE = 10;
export const MAX_SUGGESTION_MESSAGE = 2000;
/** The longest address RFC 5321 allows. */
export const MAX_SUGGESTION_EMAIL = 254;
/**
 * The app's facts as `DiagnosticEnvironment` in TabbiKitCore cleans them: letters, digits, spaces and
 * `. _ - ( )`, at most 32 characters, as in "1.4.0 (52)", "15.1.0" or "tabbi".
 */
export const APP_FACT_PATTERN = /^[A-Za-z0-9 ._()-]{1,32}$/;
/**
 * A form body percent-encodes each byte of a 2,000 character message (up to 4 UTF-8 bytes per
 * character) as three characters, so a valid post can approach 24 KB.
 */
export const MAX_SUGGESTION_BODY_BYTES = 32 * 1024;

/** Suggestions per minute and per UTC day from one client IP. A person sends one or two. */
export const SUGGESTIONS_PER_MIN = 3;
export const SUGGESTIONS_PER_DAY = 20;
/** Suggestions stored per rolling 24 hours from everyone; past it, posts are refused until the window moves. */
export const MAX_SUGGESTIONS_PER_DAY = 500;
/** Suggestions are deleted this long after they arrive, if the maintainer has not deleted them already. */
export const SUGGESTION_RETENTION_DAYS = 365;
/** Suggestions one GET /v1/admin/suggestions returns, newest first. */
export const ADMIN_SUGGESTIONS_PAGE = 100;

/** Where a browser goes after the Suggest form posted (the site's /thanks page, which is not indexed). */
export const THANKS_URL = "https://tabbinotch.com/thanks";
/** Where the error page sends someone back to. */
export const SUGGEST_URL = "https://tabbinotch.com/suggest";

export interface Suggestion {
  category: string;
  message: string;
  email: string | null;
  /** The Tabbi version, macOS version and edition id, when the app opened the form; otherwise null. */
  appVersion: string | null;
  macos: string | null;
  edition: string | null;
}

/** A parsed post: the suggestion, or `null` when the honeypot was filled in (accepted, never stored). */
export interface SuggestionPost {
  suggestion: Suggestion | null;
  /** Whether it came from an HTML form, which gets a redirect (or an HTML error page) instead of JSON. */
  form: boolean;
}

const invalid = (field: string, message = `invalid ${field}`) => new HttpError(400, "invalid_field", message);

/** Whether a request is an HTML form post (by its content type), so replies can be pages instead of JSON. */
export function isFormPost(req: Request): boolean {
  return (req.headers.get("Content-Type") ?? "").toLowerCase().startsWith("application/x-www-form-urlencoded");
}

/** Reads a form-encoded or JSON body into an object, rejecting unknown and repeated fields. */
export async function readSuggestionBody(req: Request): Promise<Obj> {
  const type = (req.headers.get("Content-Type") ?? "").toLowerCase();
  const raw = await readText(req, MAX_SUGGESTION_BODY_BYTES);
  if (type.startsWith("application/x-www-form-urlencoded")) {
    const body: Obj = {};
    for (const [k, v] of new URLSearchParams(raw)) {
      if (!(SUGGESTION_FIELDS as readonly string[]).includes(k)) throw new HttpError(400, "unknown_field", `unknown field: ${k}`);
      if (k in body) throw invalid(k, `repeated field: ${k}`);
      body[k] = v;
    }
    return body;
  }
  if (type.startsWith("application/json") || type === "") return parseBodyObject(raw, SUGGESTION_FIELDS, MAX_SUGGESTION_BODY_BYTES);
  throw new HttpError(415, "unsupported_media_type", "send JSON or a form");
}

/**
 * The message as the maintainer will read it: line breaks kept (as `\n`), tabs as spaces, every other
 * control or invisible formatting character removed, and surrounding whitespace trimmed.
 */
export function cleanMessage(v: unknown): string {
  if (typeof v !== "string") throw invalid("message", "message is required");
  const s = v
    .replace(/\r\n?/g, "\n")
    .replace(/\t/g, " ")
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u0009\u000b-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2028\u2029\u2066-\u2069\ufeff]/g, "")
    .trim();
  const length = [...s].length;
  if (length < MIN_SUGGESTION_MESSAGE || length > MAX_SUGGESTION_MESSAGE) {
    throw invalid("message", `message must be ${MIN_SUGGESTION_MESSAGE} to ${MAX_SUGGESTION_MESSAGE} characters`);
  }
  return s;
}

/** An optional reply address: empty means none; otherwise one plausible address, at most 254 characters. */
export function cleanEmail(v: unknown): string | null {
  if (v === undefined || v === null) return null;
  if (typeof v !== "string") throw invalid("email");
  const s = v.trim();
  if (s === "") return null;
  if (s.length > MAX_SUGGESTION_EMAIL || !/^[^\s@<>()"',;:]+@[^\s@<>()"',;:]+\.[^\s@<>()"',;:]{2,}$/.test(s)) throw invalid("email");
  return s;
}

/** An optional fact about the app (`APP_FACT_PATTERN`): empty means none, anything else must fit. */
export function cleanAppFact(v: unknown, field: string): string | null {
  if (v === undefined || v === null) return null;
  if (typeof v !== "string") throw invalid(field);
  const s = v.trim();
  if (s === "") return null;
  if (!APP_FACT_PATTERN.test(s)) throw invalid(field);
  return s;
}

/**
 * Validates a suggestion body. A filled-in honeypot short-circuits before any other check, so a bot
 * learns nothing from validation errors and is told it succeeded.
 */
export function parseSuggestion(body: Obj): Suggestion | null {
  if (body.website !== undefined && body.website !== null && body.website !== "") return null;
  if (body.category === undefined) throw invalid("category", "category is required");
  return {
    category: oneOf(body.category, SUGGESTION_CATEGORIES, "category"),
    message: cleanMessage(body.message),
    email: cleanEmail(body.email),
    appVersion: cleanAppFact(body.version, "version"),
    macos: cleanAppFact(body.macos, "macos"),
    edition: cleanAppFact(body.edition, "edition"),
  };
}

const escapeHtml = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c] as string);

/**
 * The page a form post gets when it cannot be accepted. The form validates in the browser, so this is
 * rare (a script, an old page, a rate limit); it says what went wrong and links back to the form.
 */
export function formErrorPage(e: HttpError): Response {
  const message = e.status === 429
    ? "That is a lot of ideas at once. Please wait a minute and try again."
    : e.status === 503
      ? "The inbox is full for today. Please try again tomorrow."
      : `That suggestion could not be sent: ${e.message}.`;
  const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex"><title>Suggestion not sent | Tabbi</title></head>
<body><main><h1>Suggestion not sent</h1><p>${escapeHtml(message)}</p>
<p><a href="${SUGGEST_URL}">Back to the form</a></p></main></body></html>
`;
  return new Response(html, {
    status: e.status,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "Content-Security-Policy": "default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      ...e.headers,
    },
  });
}
