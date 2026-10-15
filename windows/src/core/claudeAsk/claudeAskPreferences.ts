import { tr } from "../localization/tr";

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

/** The settings key, the Mac's `claudeAsk.preferences`. */
export const CLAUDE_ASK_PREFERENCES_KEY = "claudeAsk.preferences";

/**
 * Reads stored preferences leniently: a value this build doesn't know (from
 * a newer one) keeps the default instead of losing every preference.
 */
export function decodeClaudeAskPreferences(stored: unknown): ClaudeAskPreferences {
  const value = typeof stored === "object" && stored !== null ? (stored as { largeView?: unknown }).largeView : undefined;
  const largeView = CLAUDE_ASK_LARGE_VIEWS.find((view) => view === value) ?? "askEachTime";
  return { largeView };
}
