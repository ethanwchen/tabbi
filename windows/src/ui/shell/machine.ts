/*
 * The island's state machine: when it opens, when it closes, and what the
 * host must do on each change. It is a pure reducer (no timers, no DOM, no
 * Tauri), so every rule is tested in Vitest; the island component runs the
 * effects it returns.
 *
 * It keeps the Mac's input rules (NotchController): hover opens after a short
 * rest, the hotkey and the tray toggle, Escape and a click outside close, and
 * a panel opened by hover closes 600 ms after the pointer leaves it.
 */

/*
 * What the closed island shows, the Windows reading of the Mac's NotchMode:
 * "auto" draws the pill only while something is live (a focus clock, music,
 * a meeting soon, a party), "alwaysVisible" always draws it, and "showOnHover"
 * never does. Whenever no pill is drawn, a thin hot zone at the top edge opens
 * the island.
 */
export type NotchMode = "auto" | "alwaysVisible" | "showOnHover";

export const NOTCH_MODES: readonly NotchMode[] = ["auto", "alwaysVisible", "showOnHover"];

export type OpenSource = "hover" | "click" | "hotkey" | "tray" | "launch";

/*
 * hidden: nothing drawn; pill: the slim closed island; open: the panel;
 * closing: animating from open (or the pill) to the closed state, which keeps
 * the old hit area until the animation reports it is done.
 */
export type Phase = "hidden" | "pill" | "open" | "closing";

export type ClosedPhase = "hidden" | "pill";

export type CloseReason = "escape" | "blur" | "outsideClick" | "pointerLeft" | "toggle" | "settled";

export type TimerId = "hoverOpen" | "leaveClose";

/* The Mac's hover-open delay (AppSettings) and close-after-leave delay (NotchController). */
export const HOVER_OPEN_MS = 250;
export const LEAVE_CLOSE_MS = 600;

export interface ShellState {
  readonly phase: Phase;
  /* Where `closing` is headed. */
  readonly closingTo: ClosedPhase;
  readonly source: OpenSource | null;
  readonly closedBy: CloseReason | null;
  readonly mode: NotchMode;
  readonly live: boolean;
  readonly fullscreen: boolean;
  readonly pillHovered: boolean;
  /* Whether the panel took keyboard focus when it opened. */
  readonly focused: boolean;
}

export type ShellEvent =
  | { type: "hotZone" }
  | { type: "pillEnter" }
  | { type: "pillLeave" }
  | { type: "pillClick" }
  | { type: "panelEnter" }
  | { type: "panelLeave" }
  | { type: "toggle"; source: OpenSource }
  | { type: "open"; source: OpenSource }
  | { type: "escape" }
  | { type: "blur" }
  | { type: "outsideClick" }
  | { type: "timer"; id: TimerId }
  | { type: "settled" }
  | { type: "fullscreen"; active: boolean }
  | { type: "live"; live: boolean }
  | { type: "mode"; mode: NotchMode };

/* The window's hit area: the open canvas, the pill, or nothing. */
export type HitShape = "open" | "pill" | "none";

export type Effect =
  | { type: "shape"; shape: HitShape }
  | { type: "open"; open: boolean }
  | { type: "activate" }
  | { type: "restoreFocus" }
  | { type: "hotZone"; armed: boolean }
  | { type: "startTimer"; id: TimerId; ms: number }
  | { type: "cancelTimer"; id: TimerId };

export interface Step {
  readonly state: ShellState;
  readonly effects: readonly Effect[];
}

export function closedPhase(state: Pick<ShellState, "mode" | "live" | "fullscreen">): ClosedPhase {
  if (state.fullscreen) return "hidden";
  if (state.mode === "alwaysVisible") return "pill";
  if (state.mode === "auto" && state.live) return "pill";
  return "hidden";
}

export function initialState(mode: NotchMode = "auto"): ShellState {
  const base = { mode, live: false, fullscreen: false };
  const phase = closedPhase(base);
  return {
    ...base,
    phase,
    closingTo: phase,
    source: null,
    closedBy: null,
    pillHovered: false,
    focused: false,
  };
}

/* What the host must be told to match a state the island starts in. */
export function initialEffects(state: ShellState): Effect[] {
  return settledEffects(state, closedPhase(state));
}

function settledEffects(state: ShellState, target: ClosedPhase): Effect[] {
  return [
    { type: "shape", shape: target === "pill" ? "pill" : "none" },
    { type: "hotZone", armed: target === "hidden" && !state.fullscreen },
  ];
}

const isOpen = (state: ShellState) => state.phase === "open";

function open(state: ShellState, source: OpenSource): Step {
  if (isOpen(state)) return { state, effects: [] };
  /* Hover never takes focus, so moving the pointer over the island never interrupts typing. */
  const focused = source !== "hover";
  const effects: Effect[] = [
    { type: "cancelTimer", id: "hoverOpen" },
    { type: "cancelTimer", id: "leaveClose" },
    { type: "hotZone", armed: false },
    { type: "shape", shape: "open" },
    { type: "open", open: true },
  ];
  if (focused) effects.push({ type: "activate" });
  return {
    state: { ...state, phase: "open", source, closedBy: null, pillHovered: false, focused },
    effects,
  };
}

function close(state: ShellState, reason: CloseReason): Step {
  if (!isOpen(state)) return { state, effects: [] };
  const effects: Effect[] = [
    { type: "cancelTimer", id: "leaveClose" },
    { type: "open", open: false },
  ];
  if (state.focused) effects.push({ type: "restoreFocus" });
  return {
    state: { ...state, phase: "closing", closingTo: closedPhase(state), closedBy: reason, focused: false },
    effects,
  };
}

/*
 * The closed state can change without the panel opening: the mode changed,
 * something went live, or a fullscreen app took the display. A pill that goes
 * away animates out first (closing), one that appears gets its hit area now.
 */
function reconsiderClosed(state: ShellState): Step {
  const target = closedPhase(state);
  if (state.phase === "open") return { state, effects: [] };
  if (state.phase === "closing") return { state: { ...state, closingTo: target }, effects: [] };
  if (state.phase === target) {
    return { state, effects: [{ type: "hotZone", armed: target === "hidden" && !state.fullscreen }] };
  }
  if (target === "pill") {
    return { state: { ...state, phase: "pill" }, effects: settledEffects(state, "pill") };
  }
  return {
    state: { ...state, phase: "closing", closingTo: "hidden", closedBy: "settled", pillHovered: false },
    effects: [{ type: "cancelTimer", id: "hoverOpen" }],
  };
}

export function reduce(state: ShellState, event: ShellEvent): Step {
  switch (event.type) {
    case "hotZone":
      if (state.phase !== "hidden" || state.fullscreen) return { state, effects: [] };
      return open(state, "hover");

    case "pillEnter":
      if (state.phase !== "pill") return { state, effects: [] };
      return {
        state: { ...state, pillHovered: true },
        effects: [{ type: "startTimer", id: "hoverOpen", ms: HOVER_OPEN_MS }],
      };

    case "pillLeave":
      if (!state.pillHovered) return { state, effects: [] };
      return { state: { ...state, pillHovered: false }, effects: [{ type: "cancelTimer", id: "hoverOpen" }] };

    case "pillClick":
      if (state.phase !== "pill") return { state, effects: [] };
      return open(state, "click");

    case "panelEnter":
      if (!isOpen(state)) return { state, effects: [] };
      return { state, effects: [{ type: "cancelTimer", id: "leaveClose" }] };

    case "panelLeave":
      if (!isOpen(state) || state.source !== "hover") return { state, effects: [] };
      return { state, effects: [{ type: "startTimer", id: "leaveClose", ms: LEAVE_CLOSE_MS }] };

    case "toggle":
      if (isOpen(state)) return close(state, "toggle");
      /*
       * A click on the tray icon while the panel is open first lands outside
       * the panel and starts closing it; the tray's own toggle that follows
       * must not open it again.
       */
      if (state.phase === "closing" && state.closedBy === "outsideClick" && event.source === "tray") {
        return { state, effects: [] };
      }
      return open(state, event.source);

    case "open":
      return open(state, event.source);

    case "escape":
      return close(state, "escape");

    case "blur":
      /* Only a panel that took focus closes when it loses it; a hover-opened one never had it. */
      if (!state.focused) return { state, effects: [] };
      return close(state, "blur");

    case "outsideClick":
      return close(state, "outsideClick");

    case "timer":
      if (event.id === "hoverOpen") {
        if (state.phase !== "pill" || !state.pillHovered) return { state, effects: [] };
        return open(state, "hover");
      }
      return close(state, "pointerLeft");

    case "settled": {
      if (state.phase !== "closing") return { state, effects: [] };
      const target = closedPhase(state);
      return {
        state: { ...state, phase: target, closingTo: target, source: null, pillHovered: false },
        effects: settledEffects(state, target),
      };
    }

    case "fullscreen":
      if (state.fullscreen === event.active) return { state, effects: [] };
      return reconsiderClosed({ ...state, fullscreen: event.active });

    case "live":
      if (state.live === event.live) return { state, effects: [] };
      return reconsiderClosed({ ...state, live: event.live });

    case "mode":
      if (state.mode === event.mode) return { state, effects: [] };
      return reconsiderClosed({ ...state, mode: event.mode });
  }
}
