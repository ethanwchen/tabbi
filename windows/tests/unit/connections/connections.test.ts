import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AnkiErrors } from "../../../src/core/anki/ankiConnectError";
import { ankiDiagnosis } from "../../../src/core/connections/ankiConnection";
import { calendarConnectionState, calendarDiagnosis, isGoogleCalendarAddress } from "../../../src/core/connections/calendarConnection";
import {
  claudeDiagnosis,
  claudeInstallCommand,
  claudeSignInCommand,
  parseClaudeSignIn,
  resolveClaudeConnection,
} from "../../../src/core/connections/claudeConnection";
import {
  chainChecks,
  diagnosisDetails,
  diagnosisVerdict,
  firstFailure,
  notReachedAnswer,
  stillCheckingAnswer,
  type ConnectionDiagnosis,
} from "../../../src/core/connections/connectionDiagnosis";
import { everyConnectionState } from "../../../src/core/connections/connectionGallery";
import {
  CONNECTION_KINDS,
  connectionModules,
  connectionSymbol,
  connectionTitle,
  connectionUnlocks,
  demoDiagnosis,
  demoStatus,
  needsLocalTools,
  relevantConnections,
} from "../../../src/core/connections/connectionKind";
import {
  CONNECTION_GUIDES,
  CONNECTION_LIGHTS,
  ConnectionActions,
  actionTitle,
  connectionActionName,
  isConnected,
  lightTitle,
  settingsURL,
} from "../../../src/core/connections/connectionStatus";
import { finishesGuide, guideKind, guideWalkthrough, stepActionTitle, walkthroughWaiting } from "../../../src/core/connections/connectionWalkthrough";
import { doNotDisturbDiagnosis } from "../../../src/core/connections/doNotDisturbConnection";
import { notificationsDiagnosis, NOTIFICATION_SETTINGS } from "../../../src/core/connections/notificationsConnection";
import { PartySetup, resolvePartyConnection } from "../../../src/core/connections/partyConnection";
import { setLookup } from "../../../src/core/localization/tr";
import { MODULE_IDS } from "../../../src/core/modules/moduleId";
import { macCatalog, switchLanguage, windowsCatalog } from "../../support/catalogs";

// Port of ConnectionKindTests, ConnectionDiagnosisTests and ConnectionGalleryTests, adapted for Windows.
const { planner, party, study, anki, closet, spotify, claudeAsk, claudeUsage, system } = MODULE_IDS;

function everyDiagnosis(): ConnectionDiagnosis[] {
  return [
    ...CONNECTION_KINDS.flatMap((kind) => everyConnectionState(kind)),
    ankiDiagnosis({ kind: "problem", error: AnkiErrors.transport("refused") }),
    notificationsDiagnosis("disabledByManifest"),
  ];
}

beforeAll(() => switchLanguage("en"));

describe("ConnectionKind", () => {
  it("lists only what the enabled tabs use", () => {
    expect(relevantConnections([system])).toEqual([]);
    expect(relevantConnections([anki])).toEqual(["anki"]);
    expect(relevantConnections([spotify])).toEqual(["spotify", "music"]);
    expect(relevantConnections([claudeAsk, claudeUsage])).toEqual(["claude"]);
    expect(relevantConnections([claudeAsk])).toEqual([]);
  });

  it("shows Claude for Ask and Today only when Claude Code answers", () => {
    expect(relevantConnections([claudeAsk], { usesClaudeCode: true })).toEqual(["claude"]);
    expect(relevantConnections([planner], { usesClaudeCode: true })).toEqual(["calendar", "notifications", "doNotDisturb", "claude"]);
    expect(relevantConnections([claudeAsk], { localTools: false, usesClaudeCode: true })).toEqual([]);
  });

  it("keeps row order whatever the tab order", () => {
    const medSchool = [party, study, anki, planner, closet];
    expect(relevantConnections(medSchool)).toEqual(["calendar", "anki", "notifications", "doNotDisturb", "party"]);
    expect(relevantConnections([...medSchool].reverse())).toEqual(relevantConnections(medSchool));
  });

  it("hides only Claude without local tools, since Do Not Disturb runs nothing on Windows", () => {
    expect(relevantConnections([planner], { localTools: false })).toEqual(["calendar", "notifications", "doNotDisturb"]);
    expect(CONNECTION_KINDS.filter(needsLocalTools)).toEqual(["claude"]);
  });

  it("explains what every row unlocks in plain words", () => {
    const banned = ["CLI", "API", "localhost", "port", "error", "JSON", "Automation", "notch", "Mac", "\u2014"];
    for (const kind of CONNECTION_KINDS) {
      expect(connectionTitle(kind)).not.toBe("");
      expect(connectionSymbol(kind)).not.toBe("");
      expect(connectionModules(kind).length, kind).toBeGreaterThan(0);
      const unlocks = connectionUnlocks(kind);
      expect(unlocks.endsWith("."), kind).toBe(true);
      expect([...unlocks].length, kind).toBeLessThanOrEqual(38);
      for (const term of banned) expect(new RegExp(`\\b${term}\\b`).test(unlocks), `${kind} uses ${term}`).toBe(false);
    }
  });

  it("shows mostly connected rows in the demo, with a step left", () => {
    const lights = CONNECTION_KINDS.map((kind) => demoStatus(kind).light);
    expect(lights).not.toContain("checking");
    expect(lights.filter((light) => light === "connected").length).toBeGreaterThan(lights.length / 2);
    expect(lights.some((light) => light !== "connected")).toBe(true);
    for (const kind of CONNECTION_KINDS) {
      expect(demoDiagnosis(kind).kind).toBe(kind);
      expect(demoDiagnosis(kind).status).toEqual(demoStatus(kind));
    }
  });
});

describe("ConnectionDiagnosis", () => {
  const banned = ["CLI", "API", "localhost", "port", "error", "TCC", "EventKit", "JSON", "HTTP", "Mac", "macOS", "notch", "\u2014"];

  it("has checks that agree with the light", () => {
    for (const diagnosis of everyDiagnosis()) {
      const label = `${diagnosis.kind} ${diagnosis.technical}`;
      expect(diagnosis.checks.length, label).toBeGreaterThan(0);
      switch (diagnosis.status.light) {
        case "connected":
          expect(firstFailure(diagnosis), label).toBeUndefined();
          expect(diagnosis.checks.some((check) => check.outcome === "skipped"), label).toBe(false);
          break;
        case "checking":
          expect(firstFailure(diagnosis), label).toBeUndefined();
          expect(diagnosis.checks.some((check) => check.outcome === "skipped"), label).toBe(true);
          break;
        case "unavailable":
          expect(firstFailure(diagnosis), label).toBeUndefined();
          expect(diagnosis.checks.every((check) => check.outcome === "note"), label).toBe(true);
          break;
        default:
          expect(firstFailure(diagnosis), label).toBeDefined();
      }
    }
  });

  it("answers plainly and briefly", () => {
    for (const diagnosis of everyDiagnosis()) {
      for (const text of [diagnosisVerdict(diagnosis), ...diagnosis.checks.flatMap((check) => [check.question, check.answer])]) {
        for (const term of banned) expect(new RegExp(`\\b${term}\\b`).test(text), `"${text}" uses ${term}`).toBe(false);
        expect([...text].length, text).toBeLessThanOrEqual(160);
      }
    }
  });

  it("skips the checks after a failure", () => {
    const checks = ankiDiagnosis({ kind: "notRunning" }).checks;
    expect(checks.map((check) => check.outcome)).toEqual(["passed", "failed", "skipped", "skipped", "skipped", "skipped"]);
    expect(checks[0]?.question).toBe("Is Anki on this PC?");
    expect(checks[1]?.question).toBe("Is Anki open?");
    expect(checks[2]?.answer).toBe(notReachedAnswer());
    expect(chainChecks([{ question: "A?", outcome: undefined, answer: "" }])[0]?.answer).toBe(stillCheckingAnswer());
  });

  it("shows the add-on check still running while Anki starts", () => {
    const checks = ankiDiagnosis({ kind: "starting" }).checks;
    expect(checks[2]?.outcome).toBe("skipped");
    expect(checks[2]?.answer).toBe(stillCheckingAnswer());
  });

  it("makes the profile picker the last Anki check, and quotes Anki", () => {
    const diagnosis = ankiDiagnosis({ kind: "problem", error: AnkiErrors.collectionUnavailable });
    expect(firstFailure(diagnosis)?.question).toBe("Can Tabbi see your cards?");
    expect(firstFailure(diagnosis)?.answer).toContain("profile");
    expect(firstFailure(ankiDiagnosis({ kind: "problem", error: AnkiErrors.anki("Bad deck") }))?.answer).toBe("No. Anki said \u201CBad deck\u201D.");
  });

  it("makes a missing Google calendar only a note", () => {
    const diagnosis = calendarDiagnosis({ feeds: [{ name: "School", hasData: true, isGoogle: false }] });
    expect(isConnected(diagnosis.status)).toBe(true);
    expect(diagnosis.checks.at(-1)?.outcome).toBe("note");
    expect(diagnosis.status.suggestion).toEqual(ConnectionActions.showGuide("googleCalendar"));
  });

  it("names versions and checks in the details, but no calendar names or links", () => {
    const diagnosis = calendarDiagnosis({
      feeds: [
        { name: "me@gmail.com", hasData: true, isGoogle: true },
        { name: "Holidays", hasData: true, isGoogle: false },
      ],
    });
    const details = diagnosisDetails(diagnosis, {
      appVersion: "Version 1.2 (34)",
      systemVersion: "Windows 11 24H2",
      checkedAt: Date.UTC(2026, 9, 5, 9, 30) / 1000,
      timeZone: "UTC",
    });
    expect(details).toContain("Connection: Calendar");
    expect(details).toContain("Status: Connected (Calendar is connected)");
    expect(details).toContain("Checked: 2026-10-05 09:30");
    expect(details).toContain("Tabbi: Version 1.2 (34)");
    expect(details).toContain("Windows: Windows 11 24H2");
    expect(details).toContain("State: calendar.feeds=2 loading=0 failing=0 google=true");
    expect(details).toContain("[ok] Did you add a calendar link? Yes.");
    expect(details).not.toContain("me@gmail.com");
    expect(details).not.toContain("Holidays");
    expect(details).not.toContain("\u2014");
  });

  it("leads the verdict with the problem", () => {
    expect(diagnosisVerdict(claudeDiagnosis("signedOut"))).toBe("Sign in to Claude. Claude is installed. Sign in once and Tabbi can use it.");
    expect(diagnosisVerdict(notificationsDiagnosis("enabled")).startsWith("Everything checks out.")).toBe(true);
    expect(diagnosisVerdict(claudeDiagnosis("checking"))).toBe("Tabbi is still checking. This takes a second.");
  });

  it("never restates the headline's subject in the detail", () => {
    for (const diagnosis of everyDiagnosis()) {
      const { headline, detail } = diagnosis.status;
      expect(headline.split(" ")[0], diagnosisVerdict(diagnosis)).not.toBe(detail.split(" ")[0]);
    }
  });
});

describe("the gallery", () => {
  it("walks every row from nothing to connected, except Do Not Disturb, which Windows can't switch", () => {
    for (const kind of CONNECTION_KINDS) {
      const states = everyConnectionState(kind);
      expect(states.length, kind).toBeGreaterThan(0);
      expect(states.every((state) => state.kind === kind), kind).toBe(true);
      if (kind === "doNotDisturb") {
        expect(states.map((state) => state.status.light)).toEqual(["unavailable"]);
        continue;
      }
      expect(states.at(-1)?.status.light, kind).toBe("connected");
      expect(states[0]?.status.light, kind).not.toBe("connected");
    }
  });

  it("lists every state once", () => {
    for (const kind of CONNECTION_KINDS) {
      const labels = everyConnectionState(kind).map((state) => state.technical);
      expect(new Set(labels).size, labels.join(", ")).toBe(labels.length);
    }
  });

  it("gives every problem exactly one next button", () => {
    for (const kind of CONNECTION_KINDS) {
      for (const state of everyConnectionState(kind)) {
        if (isConnected(state.status) || state.status.light === "checking") continue;
        expect(state.status.action, state.technical).toBeDefined();
        if (state.status.light !== "unavailable") expect(firstFailure(state), state.technical).toBeDefined();
      }
    }
  });

  it("never repeats the unlocks line in a row's text", () => {
    const trim = (text: string) => text.toLowerCase().replace(/^[\p{P}]+|[\p{P}]+$/gu, "");
    for (const kind of CONNECTION_KINDS) {
      const unlocks = trim(connectionUnlocks(kind));
      for (const state of everyConnectionState(kind)) {
        for (const text of [state.status.headline, state.status.detail]) {
          const line = trim(text);
          expect(unlocks.startsWith(line) || line.startsWith(unlocks), `${state.technical}: ${text}`).toBe(false);
        }
      }
    }
  });

  it("covers every light, with only Anki and Spotify missing an install", () => {
    const lights = new Set(CONNECTION_KINDS.flatMap((kind) => everyConnectionState(kind).map((state) => state.status.light)));
    expect(lights).toEqual(new Set(CONNECTION_LIGHTS));
    const notInstalled = CONNECTION_KINDS.filter((kind) => everyConnectionState(kind).some((state) => state.status.light === "notInstalled"));
    expect(notInstalled).toEqual(["anki", "spotify", "claude"]);
  });

  it("includes the demo state", () => {
    for (const kind of CONNECTION_KINDS) {
      expect(everyConnectionState(kind).map((state) => state.status)).toContainEqual(demoStatus(kind));
    }
  });
});

describe("Windows rows", () => {
  it("reads calendar feeds instead of calendar access", () => {
    const state = calendarConnectionState(
      [
        { id: "a", name: "School", url: "webcal://calendar.google.com/calendar/ical/x/basic.ics", color: { red: 1, green: 0, blue: 0 } },
        { id: "b", name: "Club", url: "https://example.com/club.ics", color: { red: 0, green: 1, blue: 0 } },
      ],
      [
        { subscriptionID: "a", name: "School", hasData: true },
        { subscriptionID: "b", name: "Club", hasData: false, lastError: "unreachable" },
      ],
    );
    expect(state.feeds.map((feed) => feed.isGoogle)).toEqual([true, false]);
    const diagnosis = calendarDiagnosis(state);
    expect(diagnosis.status.headline).toBe("Tabbi can't reach Club");
    expect(diagnosis.status.action).toEqual(ConnectionActions.checkAgain);
    expect(diagnosis.technical).toBe("calendar.feeds=2 loading=0 failing=1 error=unreachable google=true");
    expect(isGoogleCalendarAddress("https://calendar.google.com/x.ics")).toBe(true);
    expect(isGoogleCalendarAddress("not a link")).toBe(false);
    expect(calendarDiagnosis({ feeds: [] }).status.action).toEqual(ConnectionActions.setUp);
  });

  it("says plainly that Windows can't switch Do Not Disturb, and opens its settings", () => {
    const diagnosis = doNotDisturbDiagnosis();
    expect(diagnosis.status.light).toBe("unavailable");
    expect(lightTitle("unavailable")).toBe("Not on Windows");
    expect(diagnosis.status.action).toEqual(ConnectionActions.openSettings("notifications"));
    expect(settingsURL("notifications")).toBe("ms-settings:notifications");
    expect(actionTitle(ConnectionActions.openSettings("notifications"))).toBe("Open Settings");
  });

  it("maps every toast setting, and only a development build has no button", () => {
    for (const setting of NOTIFICATION_SETTINGS) {
      const status = notificationsDiagnosis(setting).status;
      expect(status.action === undefined, setting).toBe(setting === "enabled" || setting === "disabledByManifest");
    }
  });

  it("reads Claude's sign-in probe and offers PowerShell lines", () => {
    expect(parseClaudeSignIn('{"loggedIn": true, "email": "x"}')).toBe("signedIn");
    expect(parseClaudeSignIn('warning\n{"loggedIn": false}\n')).toBe("signedOut");
    expect(parseClaudeSignIn("Unknown command")).toBe("unknown");
    expect(parseClaudeSignIn('{"loggedIn": "yes"}')).toBe("unknown");
    expect(resolveClaudeConnection(false, "signedIn")).toBe("notInstalled");
    expect(resolveClaudeConnection(true, undefined)).toBe("checking");
    expect(resolveClaudeConnection(true, "unknown")).toBe("ready");
    expect(claudeInstallCommand()).toBe(
      'irm https://claude.ai/install.ps1 | iex; if ($?) { & "$env:USERPROFILE\\.local\\bin\\claude.exe" auth login }',
    );
    expect(claudeSignInCommand(undefined)).toBe("claude auth login");
    expect(claudeSignInCommand("C:\\Users\\O'Neil\\.local\\bin\\claude.exe")).toBe("& 'C:\\Users\\O''Neil\\.local\\bin\\claude.exe' auth login");
    expect(claudeDiagnosis("notInstalled", "C:\\claude.exe").executable).toBeUndefined();
    expect(claudeDiagnosis("ready", "C:\\claude.exe").executable).toBe("C:\\claude.exe");
  });

  it("resolves Party like the Mac", () => {
    expect(resolvePartyConnection({ kind: "ageCheck", tooYoungUntil: undefined }, undefined, false)).toEqual({
      kind: "ageCheck",
      tooYoungUntil: undefined,
    });
    expect(resolvePartyConnection({ kind: "connected" }, "PUFF-42", false)).toEqual({ kind: "notSetUp" });
    expect(resolvePartyConnection({ kind: "connected" }, undefined, true)).toEqual({ kind: "connecting" });
    expect(resolvePartyConnection({ kind: "invalidServer", message: "x" }, undefined, true)).toEqual({ kind: "offline" });
    expect(resolvePartyConnection({ kind: "connected" }, "PUFF-42", true)).toEqual({ kind: "connected", friendCode: "PUFF-42" });
    expect(PartySetup.name("  Sam  ")).toBe("Sam");
    expect(PartySetup.name("   ")).toBeUndefined();
  });

  it("names actions the way the fixtures do", () => {
    expect(connectionActionName(ConnectionActions.copyFriendCode("PUFF-42"))).toBe("copyFriendCode");
    expect(connectionActionName(ConnectionActions.openSettings("notifications"))).toBe("openSettings.notifications");
  });
});

describe("walkthroughs", () => {
  it("each fix their own row and start with one button", () => {
    for (const guide of CONNECTION_GUIDES) {
      const walkthrough = guideWalkthrough(guide);
      expect(walkthrough.steps.length, guide).toBeGreaterThan(0);
      expect(stepActionTitle(walkthrough.start)).not.toBe("");
      expect(everyConnectionState(guideKind(guide)).length).toBeGreaterThan(0);
    }
    expect(stepActionTitle(guideWalkthrough("claudeInstall").start)).toBe("Copy and open PowerShell");
    expect(stepActionTitle(guideWalkthrough("ankiAddOn").start)).toBe("Copy code and open Anki");
    expect(guideWalkthrough("claudeSignIn", "C:\\Tools\\claude.exe").steps[1]?.copyable).toBe("& 'C:\\Tools\\claude.exe' auth login");
    expect(guideWalkthrough("googleCalendar").start).toEqual({ kind: "openPage", url: "https://calendar.google.com/calendar/r/settings" });
  });

  it("finish once the row connects, or once a suggestion goes away", () => {
    const withoutGoogle = calendarDiagnosis({ feeds: [{ name: "School", hasData: true, isGoogle: false }] }).status;
    const withGoogle = calendarDiagnosis({ feeds: [{ name: "School", hasData: true, isGoogle: true }] }).status;
    expect(finishesGuide(withoutGoogle, "googleCalendar", true)).toBe(false);
    expect(finishesGuide(withGoogle, "googleCalendar", true)).toBe(true);
    expect(finishesGuide(withoutGoogle, "googleCalendar", false)).toBe(true);
    expect(finishesGuide(claudeDiagnosis("signedOut").status, "claudeSignIn", false)).toBe(false);
  });
});

describe("localization", () => {
  afterAll(() => switchLanguage("en"));

  /* Every string the rows can show, through `tr`. */
  function everyString(): void {
    for (const light of CONNECTION_LIGHTS) lightTitle(light);
    for (const kind of CONNECTION_KINDS) {
      connectionTitle(kind);
      connectionUnlocks(kind);
    }
    for (const diagnosis of everyDiagnosis()) {
      diagnosisVerdict(diagnosis);
      for (const action of [diagnosis.status.action, diagnosis.status.suggestion]) if (action) actionTitle(action);
    }
    for (const guide of CONNECTION_GUIDES) {
      const walkthrough = guideWalkthrough(guide);
      stepActionTitle(walkthrough.start);
      stepActionTitle({ kind: "openApp", app: { id: "anki", name: "Anki", executables: [] } });
    }
    walkthroughWaiting();
    for (const text of Object.values(PartySetup)) if (text.length === 0) (text as () => string)();
  }

  it("finds every key in the Mac's catalog or in Windows.xcstrings", () => {
    const keys = new Set<string>();
    setLookup((key) => {
      keys.add(key);
      return undefined;
    });
    everyString();
    const missing = [...keys].filter((key) => !(key in macCatalog.strings) && !(key in windowsCatalog.strings));
    expect(missing, JSON.stringify(missing, null, 1)).toEqual([]);
  });

  it("puts every Windows wording in Windows.xcstrings, translated", () => {
    switchLanguage("de");
    expect(lightTitle("unavailable")).not.toBe("Not on Windows");
    expect(doNotDisturbDiagnosis().status.headline).not.toBe("Not available on Windows");
    expect(guideWalkthrough("claudeSignIn").intro).not.toBe("Claude is on your PC. Sign in once and Tabbi can use it.");
  });
});
