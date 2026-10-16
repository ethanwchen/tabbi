import { describe, expect, it } from "vitest";
import { DEFAULT_HOTKEY, HOTKEY_MODIFIERS, hotkeyDisplayString } from "../../../src/core/settings/hotkey";
import {
  interpretKey,
  keyCodeOf,
  modifiersLabel,
  modifiersOf,
  rejectionText,
  windowsLabel,
  windowsReservedReason,
  type KeyLike,
} from "../../../src/ui/kit/hotkeyRecording";

const press = (code: string, mods: Partial<KeyLike> = {}): KeyLike => ({
  code,
  ctrlKey: false,
  altKey: false,
  shiftKey: false,
  metaKey: false,
  ...mods,
});

describe("hotkey recording (HotkeyRecorder)", () => {
  it("maps physical keys to the Mac's key codes", () => {
    expect(keyCodeOf("Space")).toBe(49);
    expect(keyCodeOf("KeyA")).toBe(0);
    expect(keyCodeOf("Digit1")).toBe(18);
    expect(keyCodeOf("F12")).toBe(111);
    expect(keyCodeOf("PrintScreen")).toBeUndefined();
  });

  it("maps Ctrl, Alt, Shift and the Windows key to the Mac's modifier bits", () => {
    expect(modifiersOf(press("Space", { ctrlKey: true, altKey: true }))).toBe(HOTKEY_MODIFIERS.control | HOTKEY_MODIFIERS.option);
    expect(modifiersOf(press("Space", { shiftKey: true, metaKey: true }))).toBe(HOTKEY_MODIFIERS.shift | HOTKEY_MODIFIERS.command);
  });

  it("records Ctrl+Alt+Space as the Mac's Control-Option-Space", () => {
    const meaning = interpretKey(press("Space", { ctrlKey: true, altKey: true }));
    expect(meaning).toEqual({ kind: "recorded", hotkey: DEFAULT_HOTKEY });
    if (meaning.kind === "recorded") expect(hotkeyDisplayString(meaning.hotkey)).toBe("⌃⌥Space");
  });

  it("refuses a bare key, a lone modifier press and an unknown key, and cancels on Esc", () => {
    expect(interpretKey(press("KeyA"))).toEqual({ kind: "needsModifier" });
    expect(interpretKey(press("KeyA", { shiftKey: true }))).toEqual({ kind: "needsModifier" });
    expect(interpretKey(press("ControlLeft", { ctrlKey: true }))).toEqual({ kind: "modifierOnly" });
    expect(interpretKey(press("PrintScreen", { ctrlKey: true }))).toEqual({ kind: "unsupportedKey" });
    expect(interpretKey(press("Escape"))).toEqual({ kind: "cancelled" });
    expect(rejectionText({ kind: "needsModifier" })).toContain("Control or Option");
    expect(rejectionText({ kind: "unsupportedKey" })).toContain("can't be part of a shortcut");
    expect(rejectionText({ kind: "cancelled" })).toBeUndefined();
  });

  it("labels shortcuts the way Windows does", () => {
    expect(windowsLabel(DEFAULT_HOTKEY)).toBe("Ctrl+Alt+Space");
    expect(windowsLabel({ keyCode: 0, modifiers: HOTKEY_MODIFIERS.command | HOTKEY_MODIFIERS.shift })).toBe("Shift+Win+A");
    expect(windowsLabel({ keyCode: 123, modifiers: HOTKEY_MODIFIERS.control })).toBe("Ctrl+←");
    expect(modifiersLabel(HOTKEY_MODIFIERS.control | HOTKEY_MODIFIERS.option)).toBe("Ctrl+Alt");
    expect(modifiersLabel(0)).toBe("");
  });

  it("names the combinations Windows keeps for itself, plainly", () => {
    expect(windowsReservedReason({ keyCode: 37, modifiers: HOTKEY_MODIFIERS.command })).toBe(
      "Windows uses Win+L itself, so Tabbi can't take it. Record a different shortcut.",
    );
    expect(windowsReservedReason({ keyCode: 48, modifiers: HOTKEY_MODIFIERS.option })).toContain("Alt+Tab");
    expect(windowsReservedReason(DEFAULT_HOTKEY)).toBeUndefined();
  });
});

describe("hostShortcut", () => {
  it("writes the plugin's form from a Mac key code and modifier bits", async () => {
    const { hostShortcut } = await import("../../../src/ui/kit/hotkeyRecording");
    const { DEFAULT_HOTKEY, HOTKEY_MODIFIERS } = await import("../../../src/core/settings/hotkey");
    expect(hostShortcut(DEFAULT_HOTKEY)).toBe("ctrl+alt+Space");
    expect(hostShortcut({ keyCode: 17, modifiers: HOTKEY_MODIFIERS.control | HOTKEY_MODIFIERS.shift })).toBe("ctrl+shift+KeyT");
    expect(hostShortcut({ keyCode: 37, modifiers: HOTKEY_MODIFIERS.command })).toBe("super+KeyL");
    expect(hostShortcut({ keyCode: 999, modifiers: HOTKEY_MODIFIERS.control })).toBeUndefined();
  });
});
