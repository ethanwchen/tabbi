import { tr } from "../localization/tr";
import { defaultsString, type Defaults } from "../persistence/defaults";
import { isJSONObject } from "../persistence/json";
import { VersionedJSON } from "../persistence/versionedJson";

/** Port of ClaudeAskLargeView: when an Ask answer opens in the large chat view. */
export const CLAUDE_ASK_LARGE_VIEWS = ["askEachTime", "always", "never"] as const;
export type ClaudeAskLargeView = (typeof CLAUDE_ASK_LARGE_VIEWS)[number];

/** The choice as Settings lists it. */
export function largeViewTitle(view: ClaudeAskLargeView): string {
  switch (view) {
    case "askEachTime":
      return tr("Ask each time");
    case "always":
      return tr("Always");
    case "never":
      return tr("Never");
  }
}

/**
 * Whether sending a question grows the panel; `expandShortcut` is true when
 * the user sent it with the send-and-expand shortcut (Command-Return on the
 * Mac, Ctrl+Enter here).
 */
export function opensLarge(view: ClaudeAskLargeView, expandShortcut: boolean): boolean {
  switch (view) {
    case "askEachTime":
      return expandShortcut;
    case "always":
      return true;
    case "never":
      return false;
  }
}

/** Whether the chat offers an Expand button; with `never` there is nothing to expand into. */
export function offersExpand(view: ClaudeAskLargeView): boolean {
  return view !== "never";
}

/** Port of ClaudeAskPreferences: Ask's own preferences. */
export interface ClaudeAskPreferences {
  largeView: ClaudeAskLargeView;
}

export const DEFAULT_CLAUDE_ASK_PREFERENCES: Readonly<ClaudeAskPreferences> = { largeView: "askEachTime" };

/** The settings key, the Mac's `claudeAsk.preferences`. */
export const CLAUDE_ASK_PREFERENCES_KEY = "claudeAsk.preferences";

/** Port of ClaudeAskPreferencesStorage.schema. Version 1 is the first format. */
export const CLAUDE_ASK_PREFERENCES_SCHEMA = new VersionedJSON(1);

/**
 * Reads stored preferences leniently: a value this build doesn't know (from
 * a newer one) keeps the default instead of losing every preference.
 */
export function decodeClaudeAskPreferences(stored: unknown): ClaudeAskPreferences {
  const value = isJSONObject(stored) ? stored.largeView : undefined;
  const largeView = CLAUDE_ASK_LARGE_VIEWS.find((view) => view === value) ?? DEFAULT_CLAUDE_ASK_PREFERENCES.largeView;
  return { largeView };
}

/** Reads a stored document after its migrations; throws only when `text` isn't a JSON object. */
export function decodeClaudeAskPreferencesText(text: string): ClaudeAskPreferences {
  return CLAUDE_ASK_PREFERENCES_SCHEMA.decode(text, decodeClaudeAskPreferences);
}

/** The document the Mac's default `JSONEncoder` writes: `{"largeView":...,"schemaVersion":1}`. */
export function encodeClaudeAskPreferences(preferences: ClaudeAskPreferences): string {
  return CLAUDE_ASK_PREFERENCES_SCHEMA.encode({ largeView: preferences.largeView });
}

/**
 * Port of ClaudeAskPreferencesStorage: the preferences as JSON text under
 * `claudeAsk.preferences`, where the Mac keeps the same document as `Data`
 * in `UserDefaults`.
 */
export class ClaudeAskPreferencesStorage {
  constructor(private readonly defaults: Defaults) {}

  /** The saved preferences, or the defaults when none are saved or they can't be read. */
  load(): ClaudeAskPreferences {
    const text = defaultsString(this.defaults, CLAUDE_ASK_PREFERENCES_KEY);
    if (text === undefined) return { ...DEFAULT_CLAUDE_ASK_PREFERENCES };
    try {
      return decodeClaudeAskPreferencesText(text);
    } catch {
      return { ...DEFAULT_CLAUDE_ASK_PREFERENCES };
    }
  }

  save(preferences: ClaudeAskPreferences): void {
    this.defaults.set(CLAUDE_ASK_PREFERENCES_KEY, encodeClaudeAskPreferences(preferences));
  }
}
