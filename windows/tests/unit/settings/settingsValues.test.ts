import { afterEach, describe, expect, it } from "vitest";
import { setLookup } from "../../../src/core/localization/tr";
import { cleanedDisplayName, displayNameGreeting } from "../../../src/core/settings/displayName";
import {
  displayPreferenceFromStorage,
  displayPreferenceStorageValue,
  resolveDisplay,
  type DisplayPreference,
} from "../../../src/core/settings/displayPreference";
import {
  DEFAULT_HOTKEY,
  HOTKEY_MODIFIERS,
  decodeHotkey,
  encodeHotkey,
  hotkeyDisplayString,
  hotkeyModifierSymbols,
  isValidHotkey,
  recordHotkey,
  windowsHotkeyLabel,
} from "../../../src/core/settings/hotkey";
import { DEFAULT_NOTCH_MODE, NOTCH_MODES, notchModeTitle, type NotchMode } from "../../../src/core/settings/notchMode";
import { NotchPointerHold } from "../../../src/core/settings/notchPointerHold";
import { HOVER_ZONE_MARGIN, hoverZone, isNotchShown, isPointerNear, notchScreen } from "../../../src/core/settings/notchVisibility";
import { PANEL_SIZES, panelCanvasSize, panelContentScale, panelSizeTitle } from "../../../src/core/settings/panelSize";
import { CloseSwipe, TabSwipe, type SwipePhase, type TabSwipeStep } from "../../../src/core/settings/tabSwipe";

const { control, option, shift, command } = HOTKEY_MODIFIERS;

afterEach(() => setLookup(() => undefined));

describe("Hotkey", () => {
  it("defaults to Control-Option-Space", () => {
    expect(hotkeyDisplayString(DEFAULT_HOTKEY)).toBe("⌃⌥Space");
    expect(isValidHotkey(DEFAULT_HOTKEY)).toBe(true);
    expect(windowsHotkeyLabel(DEFAULT_HOTKEY)).toBe("Ctrl+Alt+Space");
  });

  it("shows modifiers in Apple's order", () => {
    expect(hotkeyDisplayString({ keyCode: 40, modifiers: command | shift | option | control })).toBe(
      "⌃⌥⇧⌘K",
    );
    expect(hotkeyModifierSymbols(command | option)).toBe("⌥⌘");
    expect(hotkeyModifierSymbols(0)).toBe("");
    expect(windowsHotkeyLabel({ keyCode: 40, modifiers: command | shift })).toBe("Shift+Win+K");
  });

  it("needs a non-Shift modifier and a known key", () => {
    expect(isValidHotkey({ keyCode: 0, modifiers: shift })).toBe(false);
    expect(isValidHotkey({ keyCode: 0, modifiers: 0 })).toBe(false);
    expect(isValidHotkey({ keyCode: 999, modifiers: command })).toBe(false);
    expect(isValidHotkey({ keyCode: 0, modifiers: command | shift })).toBe(true);
  });

  it("records safe combinations", () => {
    expect(recordHotkey(49, control | option)).toEqual({ kind: "recorded", hotkey: DEFAULT_HOTKEY });
    expect(recordHotkey(40, option)).toEqual({ kind: "recorded", hotkey: { keyCode: 40, modifiers: option } });
    expect(recordHotkey(40, command | shift)).toEqual({ kind: "recorded", hotkey: { keyCode: 40, modifiers: command | shift } });
  });

  it("refuses combinations that would hijack typing", () => {
    expect(recordHotkey(0, 0)).toEqual({ kind: "needsModifier" });
    expect(recordHotkey(0, shift)).toEqual({ kind: "needsModifier" });
    /* Command-C alone would swallow Copy in every app. */
    expect(recordHotkey(8, command)).toEqual({ kind: "needsModifier" });
  });

  it("cancels on Escape alone but records it with modifiers", () => {
    expect(recordHotkey(53, 0)).toEqual({ kind: "cancelled" });
    expect(recordHotkey(53, control)).toEqual({ kind: "recorded", hotkey: { keyCode: 53, modifiers: control } });
  });

  it("rejects unknown keys", () => {
    expect(recordHotkey(999, control)).toEqual({ kind: "unsupportedKey" });
  });

  it("stores the Mac's JSON", () => {
    expect(encodeHotkey(DEFAULT_HOTKEY)).toBe(`{"keyCode":49,"modifiers":3}`);
    expect(decodeHotkey(`{"modifiers":10,"keyCode":40}`)).toEqual({ keyCode: 40, modifiers: 10 });
    expect(decodeHotkey("garbage")).toBeUndefined();
    expect(decodeHotkey(`{"keyCode":"49","modifiers":3}`)).toBeUndefined();
  });
});

describe("DisplayPreference", () => {
  const builtIn = { id: 1, isBuiltIn: true, isMain: false };
  const external = { id: 7, isBuiltIn: false, isMain: true };
  const side = { id: 9, isBuiltIn: false, isMain: false };

  it("resolves each preference", () => {
    const screens = [external, builtIn, side];
    expect(resolveDisplay({ kind: "builtIn" }, screens)).toEqual(builtIn);
    expect(resolveDisplay({ kind: "main" }, screens)).toEqual(external);
    expect(resolveDisplay({ kind: "specific", id: 9 }, screens)).toEqual(side);
  });

  it("falls back when the preferred screen is gone", () => {
    expect(resolveDisplay({ kind: "specific", id: 42 }, [external, builtIn])).toEqual(builtIn);
    expect(resolveDisplay({ kind: "builtIn" }, [side, external])).toEqual(external);
    expect(resolveDisplay({ kind: "main" }, [side])).toEqual(side);
    expect(resolveDisplay({ kind: "main" }, [])).toBeUndefined();
  });

  it("round-trips its stored value", () => {
    const preferences: DisplayPreference[] = [{ kind: "builtIn" }, { kind: "main" }, { kind: "specific", id: 69_733_632 }];
    for (const preference of preferences) {
      expect(displayPreferenceFromStorage(displayPreferenceStorageValue(preference))).toEqual(preference);
    }
    expect(displayPreferenceFromStorage("screen:abc")).toBeUndefined();
    expect(displayPreferenceFromStorage("")).toBeUndefined();
  });

  it("can leave external displays out", () => {
    const laptop = { id: 1, isBuiltIn: true, isMain: false };
    const monitor = { id: 2, isBuiltIn: false, isMain: true };
    const both = [laptop, monitor];
    expect(notchScreen({ kind: "main" }, true, both)).toEqual(monitor);
    expect(notchScreen({ kind: "main" }, false, both)).toEqual(laptop);
    expect(notchScreen({ kind: "specific", id: 2 }, false, both)).toEqual(laptop);
    /* Lid closed: only the monitor is connected. */
    expect(notchScreen({ kind: "builtIn" }, true, [monitor])).toEqual(monitor);
    expect(notchScreen({ kind: "builtIn" }, false, [monitor])).toBeUndefined();
  });
});

describe("NotchVisibility", () => {
  const shown = (
    mode: NotchMode = "always",
    options: Partial<{ hideInFullscreen: boolean; fullscreen: boolean; revealed: boolean; pointerNear: boolean; isOpen: boolean }> = {},
  ) =>
    isNotchShown({
      mode,
      hideInFullscreen: options.hideInFullscreen ?? true,
      fullscreenAppActive: options.fullscreen ?? false,
      revealed: options.revealed ?? false,
      pointerNear: options.pointerNear ?? false,
      isOpen: options.isOpen ?? false,
    });

  it("reveals the panel over a fullscreen app with the shortcut", () => {
    expect(shown("always", { fullscreen: true })).toBe(false);
    expect(shown("always", { fullscreen: true, revealed: true })).toBe(true);
    expect(shown("always", { hideInFullscreen: false, fullscreen: true })).toBe(true);
    expect(shown()).toBe(true);
  });

  it("draws hover mode only while the pointer is near or the panel is open", () => {
    expect(shown("hover")).toBe(false);
    expect(shown("hover", { pointerNear: true })).toBe(true);
    expect(shown("hover", { isOpen: true })).toBe(true);
    expect(shown("hover", { revealed: true })).toBe(true);
  });

  it("ignores the pointer in hidden mode", () => {
    expect(shown("hidden")).toBe(false);
    expect(shown("hidden", { pointerNear: true })).toBe(false);
    expect(shown("hidden", { revealed: true })).toBe(true);
    expect(shown("hidden", { isOpen: true })).toBe(true);
  });

  it("hides behind a fullscreen app in every mode unless revealed", () => {
    for (const mode of NOTCH_MODES) {
      expect(shown(mode, { fullscreen: true, pointerNear: true, isOpen: true }), mode).toBe(false);
      expect(shown(mode, { fullscreen: true, revealed: true }), mode).toBe(true);
    }
  });

  it("widens the closed shape into the hover zone, reaching the top", () => {
    const pill = { x: 620, y: 0, width: 200, height: 32 };
    const zone = hoverZone(pill);
    expect(zone).toEqual({ x: 596, y: 0, width: 248, height: 40 });
    expect(zone?.width).toBe(pill.width + HOVER_ZONE_MARGIN.width * 2);
    expect(hoverZone({ x: 0, y: 0, width: 0, height: 0 })).toBeUndefined();
  });

  it("keeps the pointer near on the drawn shape but not beside a hidden one", () => {
    const zone = hoverZone({ x: 620, y: 0, width: 200, height: 32 });
    const wing = { x: 880, y: 10 };
    const shape = { x: 540, y: 0, width: 360, height: 32 };
    expect(isPointerNear({ x: 720, y: 1 }, zone, undefined)).toBe(true);
    expect(isPointerNear(wing, zone, undefined)).toBe(false);
    expect(isPointerNear(wing, zone, shape)).toBe(true);
    expect(isPointerNear({ x: 720, y: 400 }, zone, shape)).toBe(false);
  });

  it("keeps the Mac's stored mode names", () => {
    expect(NOTCH_MODES).toEqual(["always", "hover", "hidden"]);
    expect(DEFAULT_NOTCH_MODE).toBe("always");
    expect(notchModeTitle("hover")).toBe("Show on Hover");
    setLookup((key) => (key === "Hidden" ? "Ausgeblendet" : undefined));
    expect(notchModeTitle("hidden")).toBe("Ausgeblendet");
  });
});

describe("PanelSize", () => {
  it("sizes the canvas and scales Large", () => {
    expect(PANEL_SIZES.map(panelCanvasSize)).toEqual([
      { width: 512, height: 224 },
      { width: 560, height: 236 },
      { width: 640, height: 272 },
    ]);
    expect(PANEL_SIZES.map(panelContentScale)).toEqual([1, 1, 9 / 8]);
    expect(PANEL_SIZES.map(panelSizeTitle)).toEqual(["Compact", "Regular", "Large"]);
  });
});

describe("NotchPointerHold", () => {
  it("holds the open panel for a menu until the pointer is back", () => {
    const hold = new NotchPointerHold();
    expect(hold.holdsOpen).toBe(false);
    hold.menuBegan(true);
    expect(hold.holdsOpen).toBe(true);
    hold.pointerEntered();
    expect(hold.holdsOpen).toBe(true);
    hold.menuEnded();
    expect(hold.holdsOpen).toBe(true);
    hold.pointerEntered();
    expect(hold.holdsOpen).toBe(false);
  });

  it("holds nothing for a menu on the closed panel", () => {
    const hold = new NotchPointerHold();
    hold.menuBegan(false);
    expect(hold.holdsOpen).toBe(false);
    hold.menuEnded();
    expect(hold).toEqual(new NotchPointerHold());
  });

  it("ends the hold when the panel closes", () => {
    const hold = new NotchPointerHold();
    hold.menuBegan(true);
    hold.notchClosed();
    expect(hold.holdsOpen).toBe(false);
    hold.menuEnded();
    expect(hold.openMenus).toBe(0);
  });

  it("holds through nested menus until the last closes", () => {
    const hold = new NotchPointerHold();
    hold.menuBegan(true);
    hold.menuBegan(true);
    hold.menuEnded();
    hold.pointerEntered();
    expect(hold.holdsOpen).toBe(true);
    hold.menuEnded();
    hold.pointerEntered();
    expect(hold.holdsOpen).toBe(false);
  });
});

describe("TabSwipe", () => {
  function gesture(swipe: TabSwipe, deltaX: number, count: number, momentum = 0): TabSwipeStep[] {
    const steps: (TabSwipeStep | undefined)[] = [swipe.feed(deltaX, 0, "began")];
    for (let i = 1; i < count; i++) steps.push(swipe.feed(deltaX, 0, "changed"));
    steps.push(swipe.feed(0, 0, "ended"));
    for (let i = 0; i < momentum; i++) steps.push(swipe.feed(deltaX, 0, "momentum"));
    return steps.filter((step): step is TabSwipeStep => step !== undefined);
  }

  it("steps exactly once for a long swipe", () => {
    for (let count = 1; count <= 20; count++) {
      const swipe = new TabSwipe();
      expect(gesture(swipe, -100, count), `${count} events`).toEqual(["next"]);
      expect(gesture(swipe, 30, count + 2), `${count + 2} events`).toEqual(["previous"]);
    }
  });

  it("doesn't step again on momentum", () => {
    expect(gesture(new TabSwipe(), -40, 3, 30)).toEqual(["next"]);
  });

  it("doesn't step for a short swipe, and travel doesn't carry over", () => {
    const swipe = new TabSwipe();
    expect(gesture(swipe, -20, 3)).toEqual([]);
    expect(gesture(swipe, -20, 2)).toEqual([]);
  });

  it("ignores mostly vertical scrolling", () => {
    const swipe = new TabSwipe();
    expect(swipe.feed(0, 5, "began")).toBeUndefined();
    for (let i = 0; i < 20; i++) expect(swipe.feed(-10, 40, "changed")).toBeUndefined();
  });

  it("steps a mouse wheel once per threshold of travel", () => {
    const swipe = new TabSwipe();
    const steps = Array.from({ length: 14 }, () => swipe.feed(-10, 0, "none")).filter((step) => step !== undefined);
    expect(steps).toEqual(["next", "next"]);
  });
});

describe("CloseSwipe", () => {
  function gesture(swipe: CloseSwipe, up: number, count: number, options: { deltaX?: number; momentum?: number; overList?: boolean } = {}): number {
    const deltaX = options.deltaX ?? 0;
    const closes = [swipe.feed(deltaX, up, "began", options.overList ?? false)];
    for (let i = 1; i < count; i++) closes.push(swipe.feed(deltaX, up, "changed", false));
    closes.push(swipe.feed(0, 0, "ended", false));
    for (let i = 0; i < (options.momentum ?? 0); i++) closes.push(swipe.feed(0, up, "momentum", false));
    return closes.filter(Boolean).length;
  }

  it("closes once for a swipe up", () => {
    for (let count = 4; count <= 20; count++) expect(gesture(new CloseSwipe(), 20, count, { momentum: 10 }), `${count}`).toBe(1);
  });

  it("doesn't close for a short or downward swipe", () => {
    const swipe = new CloseSwipe();
    expect(gesture(swipe, 20, 3)).toBe(0);
    expect(gesture(swipe, 20, 3)).toBe(0);
    expect(gesture(swipe, -30, 10)).toBe(0);
  });

  it("leaves a swipe over a scrollable list to the list", () => {
    const swipe = new CloseSwipe();
    expect(gesture(swipe, 30, 10, { overList: true })).toBe(0);
    expect(gesture(swipe, 30, 10)).toBe(1);
  });

  it("doesn't close for a sideways tab swipe", () => {
    expect(gesture(new CloseSwipe(), 15, 20, { deltaX: -40 })).toBe(0);
  });

  it("never closes for a mouse wheel", () => {
    const swipe = new CloseSwipe();
    const phase: SwipePhase = "none";
    expect(Array.from({ length: 40 }, () => swipe.feed(0, 30, phase, false)).some(Boolean)).toBe(false);
  });
});

describe("DisplayName", () => {
  const at = (hour: number) => Date.UTC(2026, 9, 6, hour, 30) / 1000;

  it("greets by the hour and needs a name", () => {
    expect(displayNameGreeting(" Ana ", at(4), "UTC")).toBe("Good morning, Ana");
    expect(displayNameGreeting("Ana", at(11), "UTC")).toBe("Good morning, Ana");
    expect(displayNameGreeting("Ana", at(12), "UTC")).toBe("Good afternoon, Ana");
    expect(displayNameGreeting("Ana", at(17), "UTC")).toBe("Good evening, Ana");
    expect(displayNameGreeting("Ana", at(2), "UTC")).toBe("Good evening, Ana");
    expect(displayNameGreeting(undefined, at(9), "UTC")).toBeUndefined();
    expect(displayNameGreeting(" ​ ", at(9), "UTC")).toBeUndefined();
  });

  it("greets on the wall clock of the given zone", () => {
    expect(displayNameGreeting("Ana", at(11), "Asia/Tokyo")).toBe("Good evening, Ana");
  });

  it("strips control and invisible characters and caps the length", () => {
    expect(cleanedDisplayName("A\u0007d‮a")).toBe("Ada");
    expect(cleanedDisplayName("x".repeat(30))).toBe("x".repeat(24));
    expect(cleanedDisplayName("   ")).toBeUndefined();
  });
});
