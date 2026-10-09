/**
 * Moderation used by the Hub: blocks between users and reports. The maintainer reviews reports through
 * the admin routes, which share the authentication in admin.ts.
 */
import { Obj, cleanText, oneOf } from "./lib";

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

/** Reports one GET /v1/admin/reports returns, newest first. */
export const ADMIN_REPORTS_PAGE = 100;

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
