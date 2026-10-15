/*
 * The island: the shape that hangs from the top edge, the pill it closes to,
 * and the open panel with its header. It runs the shell state machine
 * (shell/machine.ts), turns its effects into host calls, and animates the
 * shape with the Mac's springs, only while something is moving.
 */

import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import type { Host, HostEvent, HotkeyStatus } from "../host/host";
import { CANVAS, HIDDEN, OPEN, PILL, PILL_HOVERED, hitRect, notchPath, type Silhouette } from "./shell/geometry";
import {
  NOTCH_MODES,
  initialEffects,
  reduce,
  type Effect,
  type NotchMode,
  type ShellEvent,
  type ShellState,
  type TimerId,
} from "./shell/machine";
import { MOTION, stepSpring, type SpringSpec, type SpringValue } from "./shell/spring";
import { Header } from "./Header";
import { kitLayout } from "./modules";
import { StatusMessage } from "./StatusMessage";

export interface IslandProps {
  readonly host: Host;
  readonly initial: ShellState;
  /* Snapshot runs draw every state at rest, with no motion. */
  readonly still?: boolean;
  readonly initialTab?: string;
}

function silhouetteFor(state: ShellState): Silhouette {
  switch (state.phase) {
    case "open":
      return OPEN;
    case "pill":
      return state.pillHovered ? PILL_HOVERED : PILL;
    case "hidden":
      return HIDDEN;
    case "closing":
      return state.closingTo === "pill" ? PILL : HIDDEN;
  }
}

function springFor(state: ShellState): SpringSpec {
  if (state.phase === "open") return MOTION.open;
  if (state.phase === "closing") return MOTION.close;
  return MOTION.hover;
}

type Springs = Record<keyof Silhouette, SpringValue>;

function springsAt(shape: Silhouette): Springs {
  return {
    width: { value: shape.width, velocity: 0 },
    height: { value: shape.height, velocity: 0 },
    topRadius: { value: shape.topRadius, velocity: 0 },
    bottomRadius: { value: shape.bottomRadius, velocity: 0 },
  };
}

const KEYS = ["width", "height", "topRadius", "bottomRadius"] as const;

const reducedMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;

function isNotchMode(value: string | null): value is NotchMode {
  return value !== null && (NOTCH_MODES as readonly string[]).includes(value);
}

export function Island({ host, initial, still = false, initialTab }: IslandProps) {
  const [state, setState] = useState(initial);
  const stateRef = useRef(initial);
  const timers = useRef(new Map<TimerId, number>());
  const queue = useRef(Promise.resolve());
  const [hotkey, setHotkey] = useState<HotkeyStatus | null>(null);

  const layout = useMemo(() => kitLayout(), []);
  const all = useMemo(() => [...layout.tabs, ...layout.shortcuts], [layout]);
  const [selectedId, setSelectedId] = useState(initialTab ?? layout.tabs[0]?.id ?? "");
  const selected = all.find((m) => m.id === selectedId) ?? all[0];

  const dispatchRef = useRef<(event: ShellEvent) => void>(() => {});

  /* Host calls run one after another, so "open" always lands before "activate". */
  const call = useCallback((run: () => Promise<void>) => {
    queue.current = queue.current.then(run).catch((error: unknown) => console.error("tabbi host", error));
  }, []);

  const runEffects = useCallback(
    (effects: readonly Effect[]) => {
      for (const effect of effects) {
        switch (effect.type) {
          case "shape":
            call(() => host.setShape(effect.shape === "none" ? null : hitRect(effect.shape)));
            break;
          case "open":
            call(() => host.setOpen(effect.open));
            break;
          case "activate":
            call(() => host.activate());
            break;
          case "restoreFocus":
            call(() => host.restoreFocus());
            break;
          case "hotZone":
            call(() => host.armHotZone(effect.armed));
            break;
          case "startTimer": {
            window.clearTimeout(timers.current.get(effect.id));
            const id = effect.id;
            timers.current.set(id, window.setTimeout(() => dispatchRef.current({ type: "timer", id }), effect.ms));
            break;
          }
          case "cancelTimer":
            window.clearTimeout(timers.current.get(effect.id));
            timers.current.delete(effect.id);
            break;
        }
      }
    },
    [call, host],
  );

  const dispatch = useCallback(
    (event: ShellEvent) => {
      const step = reduce(stateRef.current, event);
      if (step.state !== stateRef.current) {
        stateRef.current = step.state;
        setState(step.state);
      }
      runEffects(step.effects);
    },
    [runEffects],
  );
  useLayoutEffect(() => {
    dispatchRef.current = dispatch;
  }, [dispatch]);

  /* Host events and the first frame. */
  useEffect(() => {
    const onHost = (event: HostEvent) => {
      switch (event.type) {
        case "hotZone":
          return dispatch({ type: "hotZone" });
        case "toggle":
          return dispatch({ type: "toggle", source: event.source });
        case "open":
          return dispatch({ type: "open", source: event.source });
        case "outsideClick":
          return dispatch({ type: "outsideClick" });
        case "fullscreen":
          return dispatch({ type: "fullscreen", active: event.active });
        case "focus":
          if (!event.focused) dispatch({ type: "blur" });
          return;
        case "link":
          /* Sign-in links arrive with Party and sync; for now a link only brings Tabbi forward. */
          return dispatch({ type: "open", source: "launch" });
        case "placed":
          return;
      }
    };
    const unsubscribe = host.subscribe(onHost);
    runEffects(initialEffects(stateRef.current));
    const frame = requestAnimationFrame(() => {
      void host.ready().then((startup) => {
        setHotkey(startup.hotkey);
        if (isNotchMode(startup.notchMode)) dispatch({ type: "mode", mode: startup.notchMode });
      });
    });
    const pending = timers.current;
    return () => {
      unsubscribe();
      cancelAnimationFrame(frame);
      for (const id of pending.values()) window.clearTimeout(id);
    };
  }, [dispatch, host, runEffects]);

  /* Keyboard, while the panel is open: Escape closes, arrows and numbers pick a tab, P the Closet. */
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (stateRef.current.phase !== "open") return;
      const tabs = layout.tabs;
      const index = tabs.findIndex((t) => t.id === selectedId);
      if (event.key === "Escape") {
        dispatch({ type: "escape" });
      } else if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
        const step = event.key === "ArrowRight" ? 1 : -1;
        const next = tabs[(index + step + tabs.length) % tabs.length];
        if (next) setSelectedId(next.id);
      } else if (/^[1-9]$/.test(event.key)) {
        const tab = tabs[Number(event.key) - 1];
        if (tab) setSelectedId(tab.id);
      } else {
        const shortcut = layout.shortcuts.find((s) => s.headerShortcut === event.key.toLowerCase());
        if (shortcut) setSelectedId(shortcut.id);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [dispatch, layout, selectedId]);

  /* The shape: springs toward the state's silhouette, drawn straight into the DOM each frame. */
  const shapeRef = useRef<SVGPathElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);
  const springs = useRef<Springs>(springsAt(silhouetteFor(initial)));
  const target = silhouetteFor(state);
  const spec = springFor(state);

  const draw = useCallback(() => {
    const s = springs.current;
    /*
     * The open spring overshoots by a few pixels; the window is exactly the
     * canvas, so the overshoot is held at its edge instead of being clipped.
     */
    const path = notchPath({
      width: Math.min(s.width.value, CANVAS.width),
      height: Math.min(s.height.value, CANVAS.height),
      topRadius: s.topRadius.value,
      bottomRadius: s.bottomRadius.value,
    });
    shapeRef.current?.setAttribute("d", path);
    if (contentRef.current) contentRef.current.style.clipPath = path ? `path("${path}")` : "inset(100%)";
  }, []);

  useLayoutEffect(() => {
    const settle = () => {
      if (stateRef.current.phase === "closing") dispatch({ type: "settled" });
    };
    if (still || reducedMotion()) {
      springs.current = springsAt(target);
      draw();
      settle();
      return;
    }
    let frame = 0;
    let last = performance.now();
    const tick = (now: number) => {
      const dt = (now - last) / 1000;
      last = now;
      let atRest = true;
      for (const key of KEYS) {
        atRest = stepSpring(springs.current[key], target[key], spec, dt) && atRest;
      }
      draw();
      if (atRest) settle();
      else frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [target, spec, still, draw, dispatch]);

  const showContent = state.phase === "open";
  const contentMounted = state.phase === "open" || (state.phase === "closing" && state.closedBy !== "settled");
  const pill = hitRect("pill");

  return (
    <div
      className="island"
      data-phase={state.phase}
      data-still={still}
      onPointerEnter={() => dispatch({ type: "panelEnter" })}
      onPointerLeave={() => dispatch({ type: "panelLeave" })}
    >
      <svg className="shape" width="100%" height="100%" aria-hidden="true">
        <path ref={shapeRef} />
      </svg>
      {state.phase === "pill" && (
        <div
          className="pill-target"
          style={{ left: pill.x, top: pill.y, width: pill.width, height: pill.height }}
          title="Open Tabbi"
          onPointerEnter={() => dispatch({ type: "pillEnter" })}
          onPointerLeave={() => dispatch({ type: "pillLeave" })}
          onClick={() => dispatch({ type: "pillClick" })}
        />
      )}
      <div ref={contentRef} className="content" data-visible={showContent} aria-hidden={!showContent}>
        {contentMounted && selected && (
          <>
            <Header tabs={layout.tabs} shortcuts={layout.shortcuts} selected={selected} onSelect={setSelectedId} />
            <div className="body">
              <StatusMessage
                module={selected}
                title={selected.title}
                message="This tab arrives in a later Windows build."
              />
              {hotkey && !hotkey.registered && (
                <p className="caption">
                  Another app is using Ctrl+Alt+Space, so open Tabbi from its icon in the tray.
                </p>
              )}
            </div>
          </>
        )}
      </div>
    </div>
  );
}
