import { describe, expect, it } from "vitest";
import {
  CRASH_REPORT_CONSENTS,
  crashReportAction,
  crashReportConsentAfter,
  crashReportConsentTitle,
  parseCrashReportConsent,
  serializeCrashReportConsent,
} from "../../../src/core/feedback/crashReporting";
import { CrashReport, CrashThread } from "../../../src/core/feedback/crashReport";
import { DiagnosticEnvironment } from "../../../src/core/feedback/diagnosticEnvironment";

/* Port of CrashReportingTests' consent tests; the uploader is not ported yet, so its tests are not either. */
function sampleReport(): CrashReport {
  const report = CrashReport.make(new DiagnosticEnvironment("1.4.0 (52)", "10.0.26200", "tabbi"), "signal", "SIGSEGV", [
    new CrashThread("main", true, ["0 Tabbi 0x1 main + 4"]),
  ]);
  if (!report) throw new Error("expected a report");
  return report;
}

describe("CrashReportConsent", () => {
  it("sends nothing without a yes", () => {
    const report = sampleReport();
    expect(crashReportAction("ask", report)).toEqual({ type: "ask", report });
    expect(crashReportAction("neverSend", report)).toEqual({ type: "nothing" });
    expect(crashReportAction("alwaysSend", report)).toEqual({ type: "send", report });
    for (const consent of CRASH_REPORT_CONSENTS) expect(crashReportAction(consent, undefined)).toEqual({ type: "nothing" });
  });

  it("makes an answer standing only with Don't ask again", () => {
    expect(crashReportConsentAfter("send", false)).toBe("ask");
    expect(crashReportConsentAfter("dontSend", false)).toBe("ask");
    expect(crashReportConsentAfter("send", true)).toBe("alwaysSend");
    expect(crashReportConsentAfter("dontSend", true)).toBe("neverSend");
  });

  it("is stored and defaults to ask", () => {
    expect(parseCrashReportConsent(undefined)).toBe("ask");
    expect(parseCrashReportConsent(null)).toBe("ask");
    for (const consent of CRASH_REPORT_CONSENTS) expect(parseCrashReportConsent(serializeCrashReportConsent(consent))).toBe(consent);
    expect(parseCrashReportConsent("sometimes")).toBe("ask");
    expect(parseCrashReportConsent(true)).toBe("ask");
  });

  it("can take back always send, and every choice has its own title", () => {
    const report = sampleReport();
    expect(crashReportAction(parseCrashReportConsent("ask"), report)).toEqual({ type: "ask", report });
    expect(new Set(CRASH_REPORT_CONSENTS.map(crashReportConsentTitle)).size).toBe(CRASH_REPORT_CONSENTS.length);
  });
});
