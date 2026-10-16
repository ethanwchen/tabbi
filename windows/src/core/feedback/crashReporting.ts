import { tr } from "../localization/tr";
import type { CrashReport } from "./crashReport";

/*
 * Port of CrashReportConsent and CrashReportAction: whether Tabbi may send
 * a crash report, as the person chose it in the next-launch prompt or in
 * Settings > About. Opt-in: until they choose, every report is asked
 * about, and nothing is sent without a yes. Sending is a separate step
 * (no uploader is wired yet); this only decides.
 */

export const CRASH_REPORT_CONSENTS = ["ask", "alwaysSend", "neverSend"] as const;
/** `ask` is the default; `alwaysSend` and `neverSend` come from "Don't ask again" or Settings. */
export type CrashReportConsent = (typeof CRASH_REPORT_CONSENTS)[number];

/** The person's answer to one prompt. */
export type CrashReportChoice = "send" | "dontSend";

/** What to do on launch with the report a crash left. */
export type CrashReportAction =
  /** No report, or the person said never: the report is dropped unseen. */
  | { readonly type: "nothing" }
  /** Show the prompt with this report's disclosure. */
  | { readonly type: "ask"; readonly report: CrashReport }
  /** The person said always: send without asking. */
  | { readonly type: "send"; readonly report: CrashReport };

/** The choice as Settings > About lists it. */
export function crashReportConsentTitle(consent: CrashReportConsent): string {
  switch (consent) {
    case "ask":
      return tr("Ask after a crash");
    case "alwaysSend":
      return tr("Always send");
    case "neverSend":
      return tr("Never send");
  }
}

/** The consent to keep after the prompt: unchanged (ask) unless "Don't ask again" made this answer the standing one. */
export function crashReportConsentAfter(choice: CrashReportChoice, dontAskAgain: boolean): CrashReportConsent {
  if (!dontAskAgain) return "ask";
  return choice === "send" ? "alwaysSend" : "neverSend";
}

/** What to do on launch with the report a crash left, if any. */
export function crashReportAction(consent: CrashReportConsent, report: CrashReport | undefined): CrashReportAction {
  if (report === undefined) return { type: "nothing" };
  switch (consent) {
    case "ask":
      return { type: "ask", report };
    case "alwaysSend":
      return { type: "send", report };
    case "neverSend":
      return { type: "nothing" };
  }
}

/** The settings key the consent is stored under, beside the app's settings (the Mac's key). */
export const CRASH_REPORT_CONSENT_KEY = "settings.crashReports";

/** Reads a stored consent; a missing or unknown value is `ask`, so nothing is ever sent unless the person said so. */
export function parseCrashReportConsent(stored: unknown): CrashReportConsent {
  return typeof stored === "string" && (CRASH_REPORT_CONSENTS as readonly string[]).includes(stored)
    ? (stored as CrashReportConsent)
    : "ask";
}

/** The value to store for a consent. */
export function serializeCrashReportConsent(consent: CrashReportConsent): string {
  return consent;
}
