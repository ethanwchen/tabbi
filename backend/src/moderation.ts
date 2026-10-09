/**
 * Moderation used by the Hub: blocks between users, reports, and the maintainer's admin routes.
 *
 * Admin routes are enabled only when the Worker secret ADMIN_TOKEN is set (`wrangler secret put
 * ADMIN_TOKEN`) and are called with it as Bearer. Without the secret they answer 404, like any unknown route.
 */
import { HttpError, Obj, cleanText, oneOf, sha256Hex } from "./lib";

/** How many users one user can block. Bounds the blocks table; real users block a handful. */
export const MAX_BLOCKS = 1000;

/** Why a user is reported, as the app's reason picker offers it. */
export const REPORT_REASONS = ["inappropriate_name", "harassment", "spam", "other"] as const;
export const REPORT_FIELDS = ["code", "reason", "note"] as const;
/** An optional note is a sentence or two, not a document. */
export const MAX_REPORT_NOTE = 280;
/** Reports per minute per user, on top of the general limit; one report takes a few taps. */
export const REPORTS_PER_MIN = 5;
/** Reports one user can file in 24 hours. Stops one user from flooding the review queue. */
export const MAX_REPORTS_PER_DAY = 20;

/** Admin requests per minute per client IP, counted before the token is checked so it cannot be guessed. */
export const ADMIN_PER_MIN = 30;
/** Reports one GET /v1/admin/reports returns, newest first. */
export const ADMIN_REPORTS_PAGE = 100;

export interface AdminSecrets {
  ADMIN_TOKEN?: string;
}

export interface ReportRequest {
  code: string;
  reason: string;
  note: string | null;
}

/** Validates the reason and note of POST /v1/reports; the code is checked by the caller. */
export function parseReport(body: Obj): Omit<ReportRequest, "code"> {
  return {
    reason: oneOf(body.reason, REPORT_REASONS, "reason"),
    note: cleanText(body.note, "note", MAX_REPORT_NOTE) ?? null,
  };
}

/**
 * Whether `token` is the admin secret. Both sides are hashed first, so the comparison takes the same
 * time whatever the token is, and an unset or empty secret never matches.
 */
export async function isAdminToken(token: string | null, secrets: AdminSecrets): Promise<boolean> {
  const secret = secrets.ADMIN_TOKEN;
  if (!secret || !token) return false;
  const [a, b] = await Promise.all([sha256Hex(token), sha256Hex(secret)]);
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** Admin routes answer 404 to anyone without the secret, so their existence is not advertised. */
export const adminNotFound = () => new HttpError(404, "not_found", "not found");
