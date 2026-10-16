import { describe, expect, it } from "vitest";
import {
  CLAUDE_ASK_PREFERENCES_KEY,
  CLAUDE_ASK_PREFERENCES_SCHEMA,
  ClaudeAskPreferencesStorage,
  decodeClaudeAskPreferencesText,
  encodeClaudeAskPreferences,
} from "../../../src/core/claudeAsk/claudeAskPreferences";
import { InMemoryDefaults } from "../../../src/core/persistence/defaults";
import { VersionedJSON } from "../../../src/core/persistence/versionedJson";

/* Port of ClaudeAskPreferencesTests (storage). */

describe("ClaudeAskPreferencesStorage", () => {
  it("defaults to ask each time when nothing is saved", () => {
    expect(new ClaudeAskPreferencesStorage(new InMemoryDefaults()).load()).toEqual({ largeView: "askEachTime" });
  });

  it("keeps the saved choice across a relaunch", () => {
    const defaults = new InMemoryDefaults();
    new ClaudeAskPreferencesStorage(defaults).save({ largeView: "always" });
    expect(new ClaudeAskPreferencesStorage(defaults).load().largeView).toBe("always");
  });

  it("writes the Mac's versioned document under the Mac's key", () => {
    const defaults = new InMemoryDefaults();
    new ClaudeAskPreferencesStorage(defaults).save({ largeView: "never" });
    const text = defaults.get(CLAUDE_ASK_PREFERENCES_KEY);
    expect(CLAUDE_ASK_PREFERENCES_KEY).toBe("claudeAsk.preferences");
    expect(text).toBe('{"largeView":"never","schemaVersion":1}');
    expect(VersionedJSON.version(typeof text === "string" ? text : "")).toBe(CLAUDE_ASK_PREFERENCES_SCHEMA.current);
    expect(encodeClaudeAskPreferences({ largeView: "askEachTime" })).toBe('{"largeView":"askEachTime","schemaVersion":1}');
  });

  it("keeps the default for a choice from a newer build", () => {
    const defaults = new InMemoryDefaults({ [CLAUDE_ASK_PREFERENCES_KEY]: '{"schemaVersion": 2, "largeView": "sometimes"}' });
    expect(new ClaudeAskPreferencesStorage(defaults).load().largeView).toBe("askEachTime");
    expect(decodeClaudeAskPreferencesText('{"largeView": 3}')).toEqual({ largeView: "askEachTime" });
  });

  it("reads a version 0 document", () => {
    expect(decodeClaudeAskPreferencesText('{"largeView":"always"}')).toEqual({ largeView: "always" });
  });

  it("falls back to the defaults for an unreadable document", () => {
    for (const value of ["not json", "[1]", "null", 42]) {
      const defaults = new InMemoryDefaults({ [CLAUDE_ASK_PREFERENCES_KEY]: value });
      expect(new ClaudeAskPreferencesStorage(defaults).load(), String(value)).toEqual({ largeView: "askEachTime" });
    }
    expect(() => decodeClaudeAskPreferencesText("not json")).toThrow();
  });
});
