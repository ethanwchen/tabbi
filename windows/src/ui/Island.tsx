/*
 * The island: the shape that hangs from the top edge, the pill it closes
 * to with the live preview in its wings, and the open panel with its
 * header, the selected module's panel or a takeover (first-run setup). It
 * runs the shell state machine (shell/machine.ts), turns its effects into
 * host calls, and animates the shape with the Mac's springs, only while
 * something is moving. Everything it shows comes from AppServices: the
 * settings (theme, panel size, mode), the modules and the ticker.
 */

import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type CSSProperties } from "react";
import type { AppServices } from "../app/appServices";
import { constant } from "../app/store";
import type { NotchTakeover } from "../app/takeover";
import type { TickerState } from "../app/tickerStore";
import { useStore } from "../app/useStore";
import { tr } from "../core/localization/tr";
import type { ModuleID } from "../core/modules/moduleId";
import { panelCanvasSize, panelContentScale } from "../core/settings/panelSize";
import { tickerItemAction, tickerItemModule, type TickerItem } from "../core/ticker/tickerItem";
import type { Host, HostEvent, HotkeyStatus } from "../host/host";
import { Header, HEADER_HEIGHT } from "./Header";
import { useKit } from "./kit/context";
import { ClosedPreview } from "./shell/ClosedPreview";
import { hitRect, notchPath, openSilhouette, pillSilhouette, type CanvasSize, type Silhouette } from "./shell/geometry";
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
import { islandMeasure, wingWidth } from "./shell/previewLayout";
import { MOTION, stepSpring, type SpringSpec, type SpringValue } from "./shell/spring";
import { TabPanels } from "./shell/TabPanels";

export interface IslandProps {
  readonly app: AppServices;
  readonly host: Host;
  readonly initial: ShellState;
  /* Snapshot runs draw every state at rest, with no motion. */
  readonly still?: boolean;
  readonly initialTab?: ModuleID;
  /* The language the strings are in, for numbers in the preview. */
  readonly locale?: string;
  /* A ticker item to show instead of the ticker's (snapshot runs). */
  readonly preview?: TickerItem;
  /* A takeover to show instead of the app's (snapshot runs). */
  readonly takeover?: NotchTakeover;
  /* A closed-island mode to keep whatever the settings say (snapshot runs). */
  readonly mode?: NotchMode;
  /* Starts with the overflow list open (snapshot runs). */
  readonly showsMore?: boolean;
}

const NO_TICKER = constant<TickerState>({ item: undefined, live: false });

/* The pill collapsed into the top edge, so opening grows down from there. */
const HIDDEN_SHAPE: Silhouette = { ...pillSilhouette(0, false), height: 0 };

function silhouetteFor(state: ShellState, canvas: CanvasSize, wing: number): Silhouette {
  switch (state.phase) {
    case "open":
      return openSilhouette(canvas);
    case "pill":
      return pillSilhouette(wing, state.pillHovered);
    case "hidden":
      return HIDDEN_SHAPE;
    case "closing":
      return state.closingTo === "pill" ? pillSilhouette(wing, false) : HIDDEN_SHAPE;
  }
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

function isNotchMode(value: string | null): value is NotchMode {
  return value !== null && (NOTCH_MODES as readonly string[]).includes(value);
}

export function Island({ app, host, initial, still = false, initialTab, locale = "en", preview, takeover: forcedTakeover, mode: forcedMode, showsMore: initialShowsMore = false }: IslandProps) {
  const { reduceMotion } = useKit();
  const settings = useStore(app.settings.settings);
  const islandMode = useStore(app.settings.islandMode);
  const ticker = useStore(app.ticker ?? NO_TICKER);
  const snapshot = useStore(app.providers.snapshot);
  const appTakeover = useStore(app.takeover);
  const takeover = forcedTakeover ?? appTakeover;
  const catalog = app.settings.catalog;
  const layout = settings.modules;

  const canvas = useMemo(() => panelCanvasSize(settings.panelSize), [settings.panelSize]);
  const contentScale = panelContentScale(settings.panelSize);
  const item = preview ?? ticker.item;
  const wing = useMemo(() => (item === undefined ? 0 : wingWidth(item, islandMeasure, locale)), [item, locale]);

  const [state, setState] = useState(initial);
  const stateRef = useRef(initial);
  const timers = useRef(new Map<TimerId, number>());
  const queue = useRef(Promise.resolve());
  const [hotkey, setHotkey] = useState<HotkeyStatus | null>(null);
  const [devMode, setDevMode] = useState<NotchMode | undefined>(undefined);

  const [selected, setSelected] = useState<ModuleID>(() => layout.resolvedSelection(initialTab ?? layout.tabs[0] ?? layout.enabled[0] ?? ""));
  const [forward, setForward] = useState(true);
  const shown = layout.resolvedSelection(selected);
  /*
   * The overflow list belongs to the tab and tabs it opened over: picking a
   * tab or changing the tabs hides it, and so does closing the island.
   */
  const [moreFor, setMoreFor] = useState(initialShowsMore ? { tab: shown, layout } : undefined);
  const showsMore = moreFor !== undefined && moreFor.tab === shown && moreFor.layout === layout;
  const setShowsMore = useCallback((shows: boolean) => setMoreFor(shows ? { tab: shown, layout } : undefined), [shown, layout]);
  const select = useCallback(
    (id: ModuleID) => {
      const order = layout.enabled;
      setForward(order.indexOf(id) >= order.indexOf(shown));
      setSelected(id);
    },
    [layout, shown],
  );

  const dispatchRef = useRef<(event: ShellEvent) => void>(() => {});
  /* What the host's shape effects need now: the canvas and the pill's wings. */
  const shapeInputs = useRef({ canvas, wing });

  /* Host calls run one after another, so "open" always lands before "activate". */
  const call = useCallback((run: () => Promise<void>) => {
    queue.current = queue.current.then(run).catch((error: unknown) => console.error("tabbi host", error));
  }, []);

  const runEffects = useCallback(
    (effects: readonly Effect[]) => {
      for (const effect of effects) {
        switch (effect.type) {
          case "shape": {
            const { canvas: size, wing: wings } = shapeInputs.current;
            call(() => host.setShape(effect.shape === "none" ? null : hitRect(effect.shape, size, wings)));
            break;
          }
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
        if (step.state.phase !== "open") setMoreFor(undefined);
      }
      runEffects(step.effects);
    },
    [runEffects],
  );
  useLayoutEffect(() => {
    dispatchRef.current = dispatch;
  }, [dispatch]);

  /* The canvas follows the panel size; the pill's region follows its wings. */
  useEffect(() => {
    shapeInputs.current = { canvas, wing };
    call(() => host.setCanvas(canvas.width, canvas.height));
    const phase = stateRef.current.phase;
    if (phase === "open") call(() => host.setShape(hitRect("open", canvas)));
    if (phase === "pill") call(() => host.setShape(hitRect("pill", canvas, wing)));
  }, [call, host, canvas, wing]);

  /* The mode: the user's, unless a development build forces one. */
  const mode = forcedMode ?? devMode ?? islandMode;
  useEffect(() => {
    dispatch({ type: "mode", mode });
  }, [dispatch, mode]);

  /* Auto mode draws the pill only while something is live. */
  useEffect(() => {
    dispatch({ type: "live", live: ticker.live });
  }, [dispatch, ticker.live]);

  /* The ticker's clock runs only while the island is closed. */
  useEffect(() => {
    app.ticker?.setActive(state.phase !== "open");
  }, [app.ticker, state.phase]);

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
        case "settingsSection":
          return;
      }
    };
    const unsubscribe = host.subscribe(onHost);
    runEffects(initialEffects(stateRef.current));
    const frame = requestAnimationFrame(() => {
      void host.ready().then((startup) => {
        setHotkey(startup.hotkey);
        if (isNotchMode(startup.notchMode)) setDevMode(startup.notchMode);
      });
    });
    const pending = timers.current;
    return () => {
      unsubscribe();
      cancelAnimationFrame(frame);
      for (const id of pending.values()) window.clearTimeout(id);
    };
  }, [dispatch, host, runEffects]);

  /* Keyboard, while the panel is open: Escape closes, arrows and 1-9 pick a tab, a letter a header shortcut. The tab keys pause during a takeover. */
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (stateRef.current.phase !== "open") return;
      if (event.key === "Escape") {
        if (showsMore) setShowsMore(false);
        else dispatch({ type: "escape" });
        return;
      }
      if (takeover !== undefined || event.ctrlKey || event.altKey || event.metaKey) return;
      if (event.target instanceof HTMLElement && event.target.closest("input, textarea, [contenteditable='true']")) return;
      const rtl = document.documentElement.dir === "rtl";
      if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
        const next = (event.key === "ArrowRight") !== rtl;
        select(next ? layout.moduleAfter(shown) : layout.moduleBefore(shown));
      } else if (/^[1-9]$/.test(event.key)) {
        const tab = layout.moduleForShortcut(Number(event.key));
        if (tab === undefined) return;
        select(tab);
      } else if (event.key.length === 1) {
        const shortcut = layout.moduleForHeaderKey(event.key);
        if (shortcut === undefined) return;
        select(shortcut);
      } else {
        return;
      }
      event.preventDefault();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [dispatch, layout, select, setShowsMore, shown, showsMore, takeover]);

  /* The shape: springs toward the state's silhouette, drawn straight into the DOM each frame. */
  const shapeRef = useRef<SVGPathElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);
  const previewRef = useRef<HTMLDivElement>(null);
  const springs = useRef<Springs>(springsAt(silhouetteFor(initial, canvas, wing)));
  const target = useMemo(() => silhouetteFor(state, canvas, wing), [state, canvas, wing]);
  /* The last shape the springs headed for, to tell a hover from a new preview. */
  const lastTarget = useRef({ phase: state.phase, hovered: state.pillHovered });

  const draw = useCallback(() => {
    const s = springs.current;
    /* The open spring overshoots by a few pixels; the window is exactly the canvas, so the overshoot is held at its edge. */
    const path = notchPath(
      {
        width: Math.min(s.width.value, canvas.width),
        height: Math.min(s.height.value, canvas.height),
        topRadius: s.topRadius.value,
        bottomRadius: s.bottomRadius.value,
      },
      canvas.width,
    );
    shapeRef.current?.setAttribute("d", path);
    const clip = path ? `path("${path}")` : "inset(100%)";
    if (contentRef.current) contentRef.current.style.clipPath = clip;
    if (previewRef.current) previewRef.current.style.clipPath = clip;
  }, [canvas]);

  useLayoutEffect(() => {
    /*
     * Opening stretches and settles, closing lands with no overshoot, hover
     * answers quickly, and the pill's width follows a new preview on the
     * content spring, as on the Mac.
     */
    const previous = lastTarget.current;
    const phase = stateRef.current.phase;
    const hovered = stateRef.current.pillHovered;
    const spec: SpringSpec =
      phase === "open"
        ? MOTION.open
        : phase === "closing"
          ? MOTION.close
          : previous.phase === phase && previous.hovered === hovered
            ? MOTION.content
            : MOTION.hover;
    lastTarget.current = { phase, hovered };
    const settle = () => {
      if (stateRef.current.phase === "closing") dispatch({ type: "settled" });
    };
    if (still || reduceMotion) {
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
  }, [target, still, reduceMotion, draw, dispatch]);

  const showContent = state.phase === "open";
  const contentMounted = state.phase === "open" || (state.phase === "closing" && state.closedBy !== "settled");
  const previewShown = item !== undefined && (state.phase === "pill" || (state.phase === "closing" && state.closingTo === "pill"));
  const pill = hitRect("pill", canvas, wing);

  const openSettings = useCallback(() => {
    dispatch({ type: "escape" });
    call(() => host.openSettings(null));
  }, [call, dispatch, host]);

  const onPillClick = () => {
    /* A preview with a one-click action (Anki's "Study <deck>") runs it, and the panel opens on its module to show how it goes. */
    if (item !== undefined) {
      const module = tickerItemModule(item);
      const action = tickerItemAction(item);
      if (action !== undefined) app.modules.perform(action, module);
      if (layout.isEnabled(module)) select(module);
    }
    dispatch({ type: "pillClick" });
  };

  const musicModule = app.modules.modules.find((module) => module.musicWings !== undefined && module.provision?.get().isPlaying === true);

  return (
    <div
      className="island"
      data-phase={state.phase}
      data-still={still}
      style={{ width: canvas.width, height: canvas.height }}
      onPointerEnter={() => dispatch({ type: "panelEnter" })}
      onPointerLeave={() => dispatch({ type: "panelLeave" })}
    >
      <svg className="shape" width="100%" height="100%" aria-hidden="true">
        <path ref={shapeRef} />
      </svg>
      {previewShown && item !== undefined && (
        <div ref={previewRef} className="preview" data-visible={state.phase === "pill"}>
          <ClosedPreview
            item={item}
            wing={wing}
            catalog={catalog}
            now={app.environment.now()}
            locale={locale}
            musicWings={musicModule?.musicWings}
            onJoin={(url) => window.open(url, "_blank", "noopener")}
          />
        </div>
      )}
      {state.phase === "pill" && (
        <div
          className="pill-target"
          style={{ left: pill.x, top: pill.y, width: pill.width, height: pill.height }}
          title={item === undefined ? tr("Open Tabbi") : undefined}
          onPointerEnter={() => dispatch({ type: "pillEnter" })}
          onPointerLeave={() => dispatch({ type: "pillLeave" })}
          onClick={onPillClick}
          onAuxClick={(event) => {
            /* A middle-click shows the next live activity, the Mac's swipe down. */
            if (event.button === 1) app.ticker?.cycle();
          }}
        />
      )}
      <div ref={contentRef} className="content" data-visible={showContent} aria-hidden={!showContent}>
        <div className="glow" aria-hidden="true" />
        {contentMounted &&
          (takeover !== undefined ? (
            <>
              <div className="header takeover-header" style={{ height: HEADER_HEIGHT }}>
                <div className="takeover-leading">
                  <takeover.Leading />
                </div>
                <div className="takeover-trailing">
                  <takeover.Trailing />
                </div>
              </div>
              <div className="body">
                <div className="panel-scaled" style={{ "--panel-scale": String(contentScale) } as CSSProperties}>
                  <takeover.Body />
                </div>
              </div>
            </>
          ) : (
            <>
              <Header
                catalog={catalog}
                layout={layout}
                selected={shown}
                onSelect={select}
                canvasWidth={canvas.width}
                badges={snapshot.badges}
                onOpenSettings={openSettings}
                showsMore={showsMore}
                onShowMore={setShowsMore}
              />
              <div className="body">
                <TabPanels selected={shown} forward={forward} registry={app.modules} catalog={catalog} scale={contentScale} />
                {hotkey && !hotkey.registered && (
                  <p className="hotkey-note">{tr("Another app is using Ctrl+Alt+Space, so open Tabbi from its icon in the tray.")}</p>
                )}
              </div>
            </>
          ))}
      </div>
    </div>
  );
}
