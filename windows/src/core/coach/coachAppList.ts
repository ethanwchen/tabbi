import type { JSONObject } from "../persistence/json";

/*
 * Port of CoachAppCategory, CoachAppSuggestion and CoachAppList.
 *
 * The Mac matches apps by bundle id. Windows has no bundle ids, so this
 * list matches the frontmost app by its executable name (`Discord.exe`),
 * which the host reads from the foreground window's process. As on the
 * Mac, the coach only ever sees that name: never window titles, URLs or
 * keystrokes. The categories and their meaning are the Mac's; only the
 * app names are Windows' own equivalents.
 */

/** How the coach treats the app in front. */
export type CoachAppCategory =
  /** On the user's focus apps list (Anki, a Qbank). Never a distraction. */
  | "focus"
  /** On the user's distracting apps list. */
  | "distracting"
  /** Anything else, including an unknown frontmost app. */
  | "neutral";

export const COACH_APP_CATEGORIES: readonly CoachAppCategory[] = ["focus", "distracting", "neutral"];

/** A suggested distracting app, shown as an opt-in chip in Settings. */
export interface CoachAppSuggestion {
  /** The executable name, as the Mac's suggestion holds a bundle id. */
  readonly executable: string;
  readonly name: string;
}

/**
 * Anki's executable is a focus app out of the box, as the Mac's two Anki
 * bundle ids are.
 */
export const DEFAULT_FOCUS_APPS: readonly string[] = ["anki.exe"];

/**
 * Common distractions offered in Settings, not pre-selected: the Windows
 * builds of the Mac's chat and game apps. Phone Link stands in for the
 * Mac's Messages and Teams joins the chat apps; the Mac's TV app has no
 * desktop equivalent with a stable executable name, so it has no chip.
 * Browsers (chrome.exe, msedge.exe) and editors (Code.exe) stay neutral,
 * as on the Mac: a website such as YouTube can't be told apart from study
 * reading without window titles, so the Settings copy should say so.
 */
export const SUGGESTED_DISTRACTING_APPS: readonly CoachAppSuggestion[] = [
  { executable: "PhoneExperienceHost.exe", name: "Phone Link" },
  { executable: "Discord.exe", name: "Discord" },
  { executable: "slack.exe", name: "Slack" },
  { executable: "ms-teams.exe", name: "Teams" },
  { executable: "WhatsApp.exe", name: "WhatsApp" },
  { executable: "Telegram.exe", name: "Telegram" },
  { executable: "steam.exe", name: "Steam" },
];

/**
 * An executable name as the lists keep it: trimmed, lowercased (Windows
 * file names ignore case, as macOS bundle ids do) and without a folder,
 * so a full path from the host matches too.
 */
export function normalizedExecutable(name: string): string {
  const trimmed = name.trim();
  const slash = Math.max(trimmed.lastIndexOf("\\"), trimmed.lastIndexOf("/"));
  return trimmed.slice(slash + 1).toLowerCase();
}

/**
 * The user's focus and distracting app lists, matched by executable name.
 *
 * The distracting list starts empty on purpose: the user picks it, and
 * `SUGGESTED_DISTRACTING_APPS` only offers common choices. When an app is
 * on both lists, focus wins, so the coach errs toward staying quiet.
 */
export class CoachAppList {
  private readonly focusSet: Set<string>;
  private readonly distractingSet: Set<string>;

  constructor(focus: Iterable<string> = DEFAULT_FOCUS_APPS, distracting: Iterable<string> = []) {
    this.focusSet = new Set([...focus].map(normalizedExecutable));
    this.distractingSet = new Set([...distracting].map(normalizedExecutable));
  }

  /** The focus apps, normalized and sorted. */
  get focus(): string[] {
    return [...this.focusSet].sort();
  }

  /** The distracting apps, normalized and sorted. */
  get distracting(): string[] {
    return [...this.distractingSet].sort();
  }

  category(executable: string | undefined): CoachAppCategory {
    if (executable === undefined || executable.trim() === "") return "neutral";
    const id = normalizedExecutable(executable);
    if (this.focusSet.has(id)) return "focus";
    if (this.distractingSet.has(id)) return "distracting";
    return "neutral";
  }

  /** Marks an app distracting, taking it off the focus list. */
  markDistracting(executable: string): void {
    const id = normalizedExecutable(executable);
    this.focusSet.delete(id);
    this.distractingSet.add(id);
  }

  /** Marks an app as a focus app, taking it off the distracting list. */
  markFocus(executable: string): void {
    const id = normalizedExecutable(executable);
    this.distractingSet.delete(id);
    this.focusSet.add(id);
  }

  isDistracting(executable: string): boolean {
    return this.category(executable) === "distracting";
  }

  /** Settings' one-tap switch: adds the app to the distracting list, or takes it off when it is already there. */
  toggleDistracting(executable: string): void {
    if (this.isDistracting(executable)) this.forget(executable);
    else this.markDistracting(executable);
  }

  /** Distracting apps the user added beyond the suggestions, normalized and sorted so Settings lists them stably. */
  get addedDistracting(): string[] {
    const suggested = new Set(SUGGESTED_DISTRACTING_APPS.map((app) => normalizedExecutable(app.executable)));
    return this.distracting.filter((id) => !suggested.has(id));
  }

  /** Takes an app off both lists. */
  forget(executable: string): void {
    const id = normalizedExecutable(executable);
    this.focusSet.delete(id);
    this.distractingSet.delete(id);
  }

  clone(): CoachAppList {
    return new CoachAppList(this.focusSet, this.distractingSet);
  }

  equals(other: CoachAppList): boolean {
    return sameList(this.focus, other.focus) && sameList(this.distracting, other.distracting);
  }

  /** The Mac's Codable shape: both lists as arrays (sorted here, so a save comes out the same each time). */
  toJSON(): JSONObject {
    return { focus: this.focus, distracting: this.distracting };
  }

  /** Reads `toJSON`'s shape; throws on a malformed one. */
  static fromJSON(json: unknown): CoachAppList {
    if (typeof json !== "object" || json === null || Array.isArray(json)) throw new TypeError("Invalid app list");
    const { focus, distracting } = json as { focus?: unknown; distracting?: unknown };
    return new CoachAppList(strings(focus, "focus"), strings(distracting, "distracting"));
  }
}

function strings(value: unknown, key: string): string[] {
  if (!Array.isArray(value) || !value.every((item): item is string => typeof item === "string")) {
    throw new TypeError(`Invalid ${key}`);
  }
  return value;
}

function sameList(a: readonly string[], b: readonly string[]): boolean {
  return a.length === b.length && a.every((item, index) => item === b[index]);
}
