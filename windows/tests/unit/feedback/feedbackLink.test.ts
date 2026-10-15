import { describe, expect, it } from "vitest";
import { feedbackLinkTitle, feedbackLinkURL, SUGGEST_LINK_FIELDS } from "../../../src/core/feedback/feedbackLink";
import {
  DiagnosticEnvironment,
  MAX_DIAGNOSTIC_FIELD_LENGTH,
  diagnosticAppVersion,
} from "../../../src/core/feedback/diagnosticEnvironment";
import { SYSTEM_VERSION_FIELD, systemVersionField } from "../../../src/core/feedback/systemVersionField";

/* Port of FeedbackLinkTests. */
const query = (url: string) => Object.fromEntries(new URL(url).searchParams.entries());

describe("FeedbackLink", () => {
  it("carries exactly version, system and edition", () => {
    const url = feedbackLinkURL(new DiagnosticEnvironment("1.4.0 (52)", "10.0.26200", "tabbi"));
    const parsed = new URL(url);
    expect(parsed.protocol).toBe("https:");
    expect(parsed.host).toBe("tabbinotch.com");
    expect(parsed.pathname).toBe("/suggest");
    expect(query(url)).toEqual({ version: "1.4.0 (52)", macos: "10.0.26200", edition: "tabbi" });
    expect(url).toBe("https://tabbinotch.com/suggest?version=1.4.0%20(52)&macos=10.0.26200&edition=tabbi");
    expect(feedbackLinkTitle()).toBe("Suggest a Feature or Report a Bug");
  });

  it("names the system version through the one switch", () => {
    expect(systemVersionField()).toBe(SYSTEM_VERSION_FIELD);
    expect(SUGGEST_LINK_FIELDS).toEqual(["version", SYSTEM_VERSION_FIELD, "edition"]);
  });

  it("builds the app version from the version and build", () => {
    expect(diagnosticAppVersion("1.4.0", "52")).toBe("1.4.0 (52)");
    expect(diagnosticAppVersion("1.4.0")).toBe("1.4.0");
    expect(diagnosticAppVersion("1.4.0", "1.4.0")).toBe("1.4.0");
    expect(diagnosticAppVersion(undefined)).toBe("development");
  });

  it("cleans and caps odd values", () => {
    const environment = new DiagnosticEnvironment("1.0&name=Jane Doe\n<script>", "9".repeat(100), "\u{1F431}");
    expect(environment.appVersion).toBe("1.0nameJane Doescript");
    expect(environment.systemVersion.length).toBe(MAX_DIAGNOSTIC_FIELD_LENGTH);
    expect(environment.edition).toBe("unknown");
    expect(new Set(Object.keys(query(feedbackLinkURL(environment))))).toEqual(new Set(["version", "macos", "edition"]));
  });
});
