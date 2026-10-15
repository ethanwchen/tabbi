import { tr } from "../localization/tr";
import type { DiagnosticEnvironment } from "./diagnosticEnvironment";
import { SYSTEM_VERSION_FIELD } from "./systemVersionField";

/*
 * Port of FeedbackLink: the website's Suggest page, opened from the island's
 * menu and Settings > About with the app version, system version and edition
 * filled in, so a bug report says where it happened without the person
 * typing it. Those three query parameters are all the link carries.
 */

export const FEEDBACK_PAGE = "https://tabbinotch.com/suggest";

/** The query parameters, in order; the system version's name comes from `SYSTEM_VERSION_FIELD`. */
export const SUGGEST_LINK_FIELDS = ["version", SYSTEM_VERSION_FIELD, "edition"] as const;

/** The menu item and the About link both read this. */
export function feedbackLinkTitle(): string {
  return tr("Suggest a Feature or Report a Bug");
}

/* Cleaned values hold only letters, digits, spaces and `. _ - ( )`, so this matches URLComponents (space as %20). */
const encode = (value: string) => encodeURIComponent(value);

/** The Suggest page with `environment` as query parameters. */
export function feedbackLinkURL(environment: DiagnosticEnvironment): string {
  const values = [environment.appVersion, environment.systemVersion, environment.edition];
  const query = SUGGEST_LINK_FIELDS.map((name, index) => `${name}=${encode(values[index] ?? "")}`).join("&");
  return `${FEEDBACK_PAGE}?${query}`;
}
