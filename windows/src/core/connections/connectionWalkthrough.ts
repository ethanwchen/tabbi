import { ANKI_CONNECT_ADD_ON_CODE } from "../anki/ankiConnectError";
import { tr } from "../localization/tr";
import { ClaudeSetup, claudeInstallCommand, claudeSignInCommand } from "./claudeConnection";
import type { ConnectionKind } from "./connectionKind";
import { CONNECTION_APPS, appDisplayName, isConnected, sameAction, type ConnectionApp, type ConnectionGuide, type ConnectionStatus } from "./connectionStatus";

/*
 * Port of ConnectionWalkthrough.swift: a short, numbered walkthrough for a
 * step Tabbi can't do by itself, with one button that starts it while
 * Tabbi watches for the result. On Windows Claude's lines run in
 * PowerShell, the Google Calendar guide copies a private iCal link (Tabbi
 * reads ICS feeds, not the accounts the system knows), and there is no
 * Focus shortcuts guide. The Mac's priming screens before a macOS
 * permission prompt (ConnectionPriming) have no Windows counterpart: no
 * row here asks Windows for a permission.
 */

/** A step Tabbi can do with one click. Port of ConnectionStepAction. */
export type ConnectionStepAction =
  /** Put some text on the clipboard, then open an app to paste it in (the add-on code into Anki, a line into PowerShell). */
  | { readonly kind: "copyAndOpen"; readonly text: string; readonly app: ConnectionApp }
  /** Open (or bring forward) an app. */
  | { readonly kind: "openApp"; readonly app: ConnectionApp }
  /** Open a web page in the browser (Google Calendar's settings). */
  | { readonly kind: "openPage"; readonly url: string };

/** The button's label. */
export function stepActionTitle(action: ConnectionStepAction): string {
  switch (action.kind) {
    case "copyAndOpen":
      return action.app.id === "anki" ? tr("Copy code and open Anki") : tr("Copy and open %@", appDisplayName(action.app));
    case "openApp":
      return tr("Open %@", appDisplayName(action.app));
    case "openPage":
      return tr("Open Google Calendar");
  }
}

/** One numbered step: a symbol to recognize it by, one sentence, and optionally a short value to copy. */
export interface ConnectionWalkthroughStep {
  readonly symbol: string;
  readonly text: string;
  readonly copyable?: string;
}

/** Port of ConnectionWalkthrough. */
export interface ConnectionWalkthrough {
  readonly title: string;
  /** Why this is needed and how long it takes, in one or two sentences. */
  readonly intro: string;
  readonly steps: readonly ConnectionWalkthroughStep[];
  /** The one button that starts the walkthrough. */
  readonly start: ConnectionStepAction;
  /** An official page with more help, shown as a quiet link. */
  readonly learnMore?: string;
}

/** What the sheet says while Tabbi waits for the steps to work. */
export function walkthroughWaiting(): string {
  return tr("Tabbi checks by itself and turns green when it works.");
}

/** The row a guide fixes. */
export function guideKind(guide: ConnectionGuide): ConnectionKind {
  switch (guide) {
    case "ankiAddOn":
    case "ankiAddOnUpdate":
    case "ankiAccess":
      return "anki";
    case "googleCalendar":
      return "calendar";
    case "claudeInstall":
    case "claudeSignIn":
      return "claude";
  }
}

/** Google Calendar's settings page, where each calendar's private iCal address is. */
export const GOOGLE_CALENDAR_SETTINGS = "https://calendar.google.com/calendar/r/settings";

/** The walkthrough for `guide`. Claude's sign-in runs `claudeExecutable`, the `claude.exe` Tabbi found, by its full path. */
export function guideWalkthrough(guide: ConnectionGuide, claudeExecutable?: string): ConnectionWalkthrough {
  const code = ANKI_CONNECT_ADD_ON_CODE;
  const anki = CONNECTION_APPS.anki;
  const powershell = CONNECTION_APPS.powershell;
  const reopenAnki = { symbol: "arrow.clockwise", text: tr("Quit Anki and open it again. Tabbi notices by itself.") };
  const paste = (copyable: string) => ({
    symbol: "doc.on.clipboard",
    text: tr("Click in the PowerShell window, press Ctrl+V to paste, then press Enter."),
    copyable,
  });
  switch (guide) {
    case "ankiAddOn":
      /* A guide, not an automatic install: Anki installs and updates its own add-ons, and Tabbi never writes into Anki's folders. */
      return {
        title: tr("Add AnkiConnect to Anki"),
        intro: tr("AnkiConnect is a free add-on that lets Tabbi count your due cards. It takes about a minute."),
        steps: [
          { symbol: "menubar.rectangle", text: tr("In Anki's menu bar, click Tools, then Add-ons.") },
          { symbol: "doc.on.clipboard", text: tr("Click Get Add-ons, paste this code, then click OK."), copyable: code },
          reopenAnki,
        ],
        start: { kind: "copyAndOpen", text: code, app: anki },
        learnMore: `https://ankiweb.net/shared/info/${code}`,
      };
    case "ankiAddOnUpdate":
      return {
        title: tr("Update AnkiConnect"),
        intro: tr("Your copy of AnkiConnect is too old for Tabbi. Anki can update it in a few clicks."),
        steps: [
          { symbol: "menubar.rectangle", text: tr("In Anki's menu bar, click Tools, then Add-ons.") },
          { symbol: "arrow.triangle.2.circlepath", text: tr("Click AnkiConnect in the list, then click Check for Updates.") },
          reopenAnki,
        ],
        start: { kind: "openApp", app: anki },
      };
    case "ankiAccess":
      return {
        title: tr("Let Tabbi into Anki"),
        intro: tr("AnkiConnect's settings keep Tabbi out. Putting them back to normal fixes it and leaves your cards alone."),
        steps: [
          { symbol: "menubar.rectangle", text: tr("In Anki, click Tools, then Add-ons. Click AnkiConnect, then Config.") },
          { symbol: "arrow.uturn.backward", text: tr("Click Restore Defaults, then OK.") },
          { symbol: "checkmark.circle", text: tr("Quit Anki and open it again. If it asks about Tabbi, click Yes.") },
        ],
        start: { kind: "openApp", app: anki },
      };
    case "googleCalendar":
      return {
        title: tr("Add your Google Calendar"),
        intro: tr("Tabbi reads a calendar from its private link. Copy your Google Calendar's link once and its events show up."),
        steps: [
          { symbol: "gearshape", text: tr("In Google Calendar's settings, click your calendar under Settings for my calendars.") },
          { symbol: "doc.on.clipboard", text: tr("Scroll to Integrate calendar and copy the Secret address in iCal format.") },
          { symbol: "calendar", text: tr("Back in Tabbi, add it as a new calendar link.") },
        ],
        start: { kind: "openPage", url: GOOGLE_CALENDAR_SETTINGS },
      };
    case "claudeInstall": {
      const command = claudeInstallCommand();
      return {
        title: tr("Set up Claude"),
        intro: tr("Claude is an AI helper. Tabbi uses it to plan your day and answer questions. It's optional: everything else works without it."),
        steps: [
          { symbol: "terminal", text: tr("Click the button below. It copies the setup line and opens PowerShell, which comes with Windows.") },
          paste(command),
          {
            symbol: "safari",
            text: tr("It installs Claude, then opens a sign-in page in your browser. Sign in there and Tabbi notices by itself."),
          },
        ],
        start: { kind: "copyAndOpen", text: command, app: powershell },
        learnMore: ClaudeSetup.installPage,
      };
    }
    case "claudeSignIn": {
      const command = claudeSignInCommand(claudeExecutable);
      return {
        title: tr("Sign in to Claude"),
        intro: tr("Claude is on your PC. Sign in once and Tabbi can use it."),
        steps: [
          { symbol: "terminal", text: tr("Click the button below. It copies the sign-in line and opens PowerShell.") },
          paste(command),
          { symbol: "safari", text: tr("Sign in on the page that opens. Tabbi notices by itself.") },
        ],
        start: { kind: "copyAndOpen", text: command, app: powershell },
        learnMore: ClaudeSetup.installPage,
      };
    }
  }
}

/**
 * Whether a walkthrough opened from this row has done its job. A guide
 * opened to fix a problem is done once the row is connected; one opened as
 * a connected row's suggestion (Add Google Calendar) is done once the row
 * stops suggesting it.
 */
export function finishesGuide(status: ConnectionStatus, guide: ConnectionGuide, openedAsSuggestion: boolean): boolean {
  if (!isConnected(status)) return false;
  return !openedAsSuggestion || !sameAction(status.suggestion, { kind: "showGuide", guide });
}
