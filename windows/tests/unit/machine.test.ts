import { describe, expect, it } from "vitest";
import {
  closedPhase,
  initialEffects,
  initialState,
  reduce,
  type Effect,
  type ShellEvent,
  type ShellState,
} from "../../src/ui/shell/machine";

/* Plays events in order and returns the final state with every effect produced on the way. */
function play(state: ShellState, ...events: ShellEvent[]): { state: ShellState; effects: Effect[] } {
  const effects: Effect[] = [];
  for (const event of events) {
    const step = reduce(state, event);
    state = step.state;
    effects.push(...step.effects);
  }
  return { state, effects };
}

const types = (effects: readonly Effect[]) => effects.map((e) => e.type);

describe("closed state", () => {
  it("draws nothing by default and arms the hot zone", () => {
    const state = initialState();
    expect(state.phase).toBe("hidden");
    expect(initialEffects(state)).toEqual([
      { type: "shape", shape: "none" },
      { type: "hotZone", armed: true },
    ]);
  });

  it("follows the mode: auto shows the pill only while something is live", () => {
    expect(closedPhase({ mode: "auto", live: false, fullscreen: false })).toBe("hidden");
    expect(closedPhase({ mode: "auto", live: true, fullscreen: false })).toBe("pill");
    expect(closedPhase({ mode: "alwaysVisible", live: false, fullscreen: false })).toBe("pill");
    expect(closedPhase({ mode: "showOnHover", live: true, fullscreen: false })).toBe("hidden");
    expect(closedPhase({ mode: "alwaysVisible", live: true, fullscreen: true })).toBe("hidden");
  });

  it("shows the pill at once when something goes live, and disarms the hot zone", () => {
    const { state, effects } = play(initialState(), { type: "live", live: true });
    expect(state.phase).toBe("pill");
    expect(effects).toEqual([
      { type: "shape", shape: "pill" },
      { type: "hotZone", armed: false },
    ]);
  });

  it("animates the pill away before dropping its hit area", () => {
    const shown = play(initialState("alwaysVisible")).state;
    const going = play(shown, { type: "mode", mode: "showOnHover" });
    expect(going.state.phase).toBe("closing");
    expect(types(going.effects)).not.toContain("shape");
    const gone = play(going.state, { type: "settled" });
    expect(gone.state.phase).toBe("hidden");
    expect(gone.effects).toEqual([
      { type: "shape", shape: "none" },
      { type: "hotZone", armed: true },
    ]);
  });

  it("hides during fullscreen and comes back after", () => {
    const pill = initialState("alwaysVisible");
    const hiding = play(pill, { type: "fullscreen", active: true }, { type: "settled" });
    expect(hiding.state.phase).toBe("hidden");
    expect(hiding.effects).toContainEqual({ type: "hotZone", armed: false });
    const back = play(hiding.state, { type: "fullscreen", active: false });
    expect(back.state.phase).toBe("pill");
  });

  it("ignores the hot zone during fullscreen", () => {
    const state = play(initialState(), { type: "fullscreen", active: true }).state;
    expect(play(state, { type: "hotZone" }).state.phase).toBe("hidden");
  });
});

describe("opening", () => {
  it("opens from the hot zone without taking focus", () => {
    const { state, effects } = play(initialState(), { type: "hotZone" });
    expect(state).toMatchObject({ phase: "open", source: "hover", focused: false });
    expect(effects).toContainEqual({ type: "shape", shape: "open" });
    expect(effects).toContainEqual({ type: "open", open: true });
    expect(effects).toContainEqual({ type: "hotZone", armed: false });
    expect(types(effects)).not.toContain("activate");
  });

  it("opens from the pill after a 250 ms rest, and not if the pointer moves on", () => {
    const pill = initialState("alwaysVisible");
    const resting = play(pill, { type: "pillEnter" });
    expect(resting.effects).toEqual([{ type: "startTimer", id: "hoverOpen", ms: 250 }]);
    expect(play(resting.state, { type: "timer", id: "hoverOpen" }).state.phase).toBe("open");

    const passing = play(pill, { type: "pillEnter" }, { type: "pillLeave" });
    expect(passing.effects).toContainEqual({ type: "cancelTimer", id: "hoverOpen" });
    expect(play(passing.state, { type: "timer", id: "hoverOpen" }).state.phase).toBe("pill");
  });

  it("takes focus when opened by a click, the hotkey or the tray, after the window may take it", () => {
    for (const event of [
      { type: "pillClick" },
      { type: "toggle", source: "hotkey" },
      { type: "toggle", source: "tray" },
    ] as const) {
      const { state, effects } = play(initialState("alwaysVisible"), event);
      expect(state.focused).toBe(true);
      const kinds = types(effects);
      expect(kinds.indexOf("open")).toBeLessThan(kinds.indexOf("activate"));
    }
  });

  it("opens from the hotkey even when hidden or fullscreen", () => {
    const fullscreen = play(initialState(), { type: "fullscreen", active: true }).state;
    expect(play(fullscreen, { type: "toggle", source: "hotkey" }).state.phase).toBe("open");
  });

  it("opening twice changes nothing", () => {
    const open = play(initialState(), { type: "toggle", source: "hotkey" }).state;
    expect(play(open, { type: "open", source: "launch" })).toEqual({ state: open, effects: [] });
  });
});

describe("closing", () => {
  const openedBy = (event: ShellEvent) => play(initialState(), event).state;

  it("closes on Escape, a click outside or the hotkey, then settles to the closed state", () => {
    for (const event of [{ type: "escape" }, { type: "outsideClick" }, { type: "toggle", source: "hotkey" }] as const) {
      const closing = play(openedBy({ type: "toggle", source: "hotkey" }), event);
      expect(closing.state.phase).toBe("closing");
      expect(closing.effects).toContainEqual({ type: "open", open: false });
      expect(closing.effects).toContainEqual({ type: "restoreFocus" });
      /* The open hit area stays until the shape has finished closing. */
      expect(types(closing.effects)).not.toContain("shape");
      const settled = play(closing.state, { type: "settled" });
      expect(settled.state.phase).toBe("hidden");
      expect(settled.effects).toContainEqual({ type: "shape", shape: "none" });
    }
  });

  it("closes a hover-opened panel 600 ms after the pointer leaves, unless it comes back", () => {
    const open = openedBy({ type: "hotZone" });
    const left = play(open, { type: "panelLeave" });
    expect(left.effects).toEqual([{ type: "startTimer", id: "leaveClose", ms: 600 }]);
    const back = play(left.state, { type: "panelEnter" });
    expect(back.effects).toEqual([{ type: "cancelTimer", id: "leaveClose" }]);
    const closed = play(left.state, { type: "timer", id: "leaveClose" });
    expect(closed.state).toMatchObject({ phase: "closing", closedBy: "pointerLeft" });
    expect(types(closed.effects)).not.toContain("restoreFocus");
  });

  it("keeps a panel opened on purpose when the pointer leaves", () => {
    const open = openedBy({ type: "toggle", source: "tray" });
    expect(play(open, { type: "panelLeave" }).effects).toEqual([]);
  });

  it("closes a focused panel when it loses focus, but not a hover-opened one", () => {
    expect(play(openedBy({ type: "toggle", source: "hotkey" }), { type: "blur" }).state.phase).toBe("closing");
    expect(play(openedBy({ type: "hotZone" }), { type: "blur" }).state.phase).toBe("open");
  });

  it("does not reopen when the click that closed it was on the tray icon", () => {
    const open = openedBy({ type: "toggle", source: "tray" });
    const { state } = play(open, { type: "outsideClick" }, { type: "toggle", source: "tray" });
    expect(state.phase).toBe("closing");
  });

  it("reopens when the hotkey is pressed again while it is still closing", () => {
    const open = openedBy({ type: "toggle", source: "hotkey" });
    const { state } = play(open, { type: "toggle", source: "hotkey" }, { type: "toggle", source: "hotkey" });
    expect(state.phase).toBe("open");
  });

  it("settles to the pill when the mode asks for it", () => {
    const open = play(initialState("alwaysVisible"), { type: "pillClick" }).state;
    const { state, effects } = play(open, { type: "escape" }, { type: "settled" });
    expect(state.phase).toBe("pill");
    expect(effects).toContainEqual({ type: "shape", shape: "pill" });
    expect(effects).toContainEqual({ type: "hotZone", armed: false });
  });

  it("a mode change while open applies once it closes", () => {
    const open = openedBy({ type: "toggle", source: "hotkey" });
    const changed = play(open, { type: "mode", mode: "alwaysVisible" });
    expect(changed.state.phase).toBe("open");
    expect(play(changed.state, { type: "escape" }, { type: "settled" }).state.phase).toBe("pill");
  });

  it("ignores close events while closed", () => {
    const closed = initialState();
    for (const event of [{ type: "escape" }, { type: "blur" }, { type: "outsideClick" }, { type: "settled" }] as const) {
      expect(play(closed, event)).toEqual({ state: closed, effects: [] });
    }
  });
});
