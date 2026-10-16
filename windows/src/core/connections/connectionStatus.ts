import { tr } from "../localization/tr";

/*
 * Port of ConnectionStatus.swift: the status light, headline, sentence and
 * one button of a Settings > Connections row, adapted for Windows.
 *
 * The Mac sends people to System Settings panes and macOS permission
 * prompts; Windows has neither for what Tabbi needs (no calendar or
 * automation consent, and toasts need no prompt), so the actions here are
 * downloads, opening an app, a walkthrough, a Windows Settings page, or
 * checking again. Apps are found by executable name instead of bundle id.
 */

/** The status light on a row. Port of ConnectionLight, plus `unavailable` for a row Windows can't support. */
export type ConnectionLight =
  /** A check is running. Shown briefly, never as a final answer. */
  | "checking"
  /** Everything works. */
  | "connected"
  /** Almost there: one thing left to do (open an app, flip a switch). */
  | "needsStep"
  /** The app is there but was never connected to Tabbi. */
  | "notSetUp"
  /** The app this needs isn't on the PC. */
  | "notInstalled"
  /** Windows has no way for Tabbi to do this (switching Do Not Disturb). */
  | "unavailable";

export const CONNECTION_LIGHTS: readonly ConnectionLight[] = ["checking", "connected", "needsStep", "notSetUp", "notInstalled", "unavailable"];

/** The words beside the light. */
export function lightTitle(light: ConnectionLight): string {
  switch (light) {
    case "checking":
      return tr("Checking");
    case "connected":
      return tr("Connected");
    case "needsStep":
      return tr("Needs one step");
    case "notSetUp":
      return tr("Not set up");
    case "notInstalled":
      return tr("Not installed");
    case "unavailable":
      return tr("Not on Windows");
  }
}

/** An app that a connection opens or asks the user to get. Port of ConnectionApp. */
export interface ConnectionApp {
  readonly id: "anki" | "spotify" | "powershell";
  /** The app's name as the user knows it; a brand name, so never translated. */
  readonly name: string;
  /** Executable names to look for, preferred first (where the Mac lists bundle ids). */
  readonly executables: readonly string[];
  /** The official download page, for "Get <name>". */
  readonly downloadPage?: string;
}

export const CONNECTION_APPS = {
  anki: { id: "anki", name: "Anki", executables: ["anki.exe"], downloadPage: "https://apps.ankiweb.net" },
  spotify: { id: "spotify", name: "Spotify", executables: ["Spotify.exe"], downloadPage: "https://www.spotify.com/download/windows/" },
  /** PowerShell, which comes with every Windows PC; only Claude's setup needs it, where the Mac opens Terminal. */
  powershell: { id: "powershell", name: "PowerShell", executables: ["powershell.exe"] },
} as const satisfies Record<string, ConnectionApp>;

/** The name to show in sentences. Every app here goes by its brand name in every language. */
export function appDisplayName(app: ConnectionApp): string {
  return app.name;
}

/** A Windows Settings page a connection sends the user to, by its `ms-settings:` link. Port of SystemSettingsLink. */
export type WindowsSettingsLink = "notifications";

export function settingsURL(link: WindowsSettingsLink): string {
  switch (link) {
    case "notifications":
      return "ms-settings:notifications";
  }
}

/**
 * A short walkthrough the app shows for a step it can't do by itself. Port
 * of ConnectionGuide, without the Mac's Focus shortcuts guide: Windows has
 * no shortcuts that switch Do Not Disturb.
 */
export type ConnectionGuide =
  /** Install the AnkiConnect add-on from inside Anki. */
  | "ankiAddOn"
  /** Update an old AnkiConnect add-on. */
  | "ankiAddOnUpdate"
  /** Let Tabbi in when AnkiConnect asks, or remove a key that blocks it. */
  | "ankiAccess"
  /** Copy a Google Calendar's private link into Tabbi. */
  | "googleCalendar"
  /** Install Claude, which Plan my day and Ask AI can use. */
  | "claudeInstall"
  /** Sign in to Claude once. */
  | "claudeSignIn";

export const CONNECTION_GUIDES: readonly ConnectionGuide[] = [
  "ankiAddOn",
  "ankiAddOnUpdate",
  "ankiAccess",
  "googleCalendar",
  "claudeInstall",
  "claudeSignIn",
];

/** The one button a row shows for its current state. Port of ConnectionAction. */
export type ConnectionAction =
  /** Open the app's download page. */
  | { readonly kind: "download"; readonly app: ConnectionApp }
  /** Open (or bring forward) an installed app. */
  | { readonly kind: "openApp"; readonly app: ConnectionApp }
  /** Show a walkthrough. */
  | { readonly kind: "showGuide"; readonly guide: ConnectionGuide }
  /** Open a Windows Settings page. */
  | { readonly kind: "openSettings"; readonly link: WindowsSettingsLink }
  /** Run the checks again. */
  | { readonly kind: "checkAgain" }
  /** Start a connection that needs a little info from the user (Party's name and pet, a calendar's link). */
  | { readonly kind: "setUp" }
  /** Put a value the user shares (Party's friend code) on the clipboard. */
  | { readonly kind: "copyFriendCode"; readonly code: string };

export const ConnectionActions = {
  download: (app: ConnectionApp): ConnectionAction => ({ kind: "download", app }),
  openApp: (app: ConnectionApp): ConnectionAction => ({ kind: "openApp", app }),
  showGuide: (guide: ConnectionGuide): ConnectionAction => ({ kind: "showGuide", guide }),
  openSettings: (link: WindowsSettingsLink): ConnectionAction => ({ kind: "openSettings", link }),
  checkAgain: { kind: "checkAgain" } as ConnectionAction,
  setUp: { kind: "setUp" } as ConnectionAction,
  copyFriendCode: (code: string): ConnectionAction => ({ kind: "copyFriendCode", code }),
} as const;

/** The button's label. */
export function actionTitle(action: ConnectionAction): string {
  switch (action.kind) {
    case "download":
      return tr("Get %@", appDisplayName(action.app));
    case "openApp":
      return tr("Open %@", appDisplayName(action.app));
    case "showGuide":
      return action.guide === "googleCalendar" ? tr("Add Google Calendar") : tr("Show me how");
    case "openSettings":
      return tr("Open Settings");
    case "checkAgain":
      return tr("Check again");
    case "setUp":
      return tr("Set up");
    case "copyFriendCode":
      return tr("Copy friend code");
  }
}

/**
 * A stable name for an action, such as `openApp.Anki` or
 * `showGuide.ankiAddOn`, the way the Mac's golden fixtures write it. A
 * friend code stays out, so the name is safe for support details.
 */
export function connectionActionName(action: ConnectionAction): string {
  switch (action.kind) {
    case "download":
    case "openApp":
      return `${action.kind}.${action.app.name}`;
    case "showGuide":
      return `showGuide.${action.guide}`;
    case "openSettings":
      return `openSettings.${action.link}`;
    case "checkAgain":
    case "setUp":
    case "copyFriendCode":
      return action.kind;
  }
}

export function sameAction(a: ConnectionAction | undefined, b: ConnectionAction | undefined): boolean {
  if (a === undefined || b === undefined) return a === b;
  return JSON.stringify(a) === JSON.stringify(b);
}

/**
 * Where one integration stands, in words a first-time user follows: a
 * light, a headline, one sentence, and at most one button. Port of
 * ConnectionStatus.
 */
export interface ConnectionStatus {
  readonly light: ConnectionLight;
  /** A few words, such as "Anki is closed". */
  readonly headline: string;
  /** One plain sentence: what's going on or what to do. */
  readonly detail: string;
  /** The button that fixes the current state; undefined when nothing needs doing. */
  readonly action?: ConnectionAction;
  /** A quieter, optional extra (such as adding Google Calendar when the calendar already works). Never a fix for a problem. */
  readonly suggestion?: ConnectionAction;
}

export function connectionStatus(
  light: ConnectionLight,
  headline: string,
  detail: string,
  options: { action?: ConnectionAction; suggestion?: ConnectionAction } = {},
): ConnectionStatus {
  const status: { -readonly [Key in keyof ConnectionStatus]: ConnectionStatus[Key] } = { light, headline, detail };
  if (options.action) status.action = options.action;
  if (options.suggestion) status.suggestion = options.suggestion;
  return status;
}

/** Whether the row is in its final good state. */
export function isConnected(status: ConnectionStatus): boolean {
  return status.light === "connected";
}
