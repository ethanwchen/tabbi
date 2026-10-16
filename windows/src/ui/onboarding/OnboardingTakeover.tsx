/*
 * Port of OnboardingViews: first-run setup as a NotchTakeover. The step's
 * symbol and name sit where the tab bar usually is, progress dots and Skip
 * Setup where the title and gear are, and the step itself fills the panel
 * canvas above a footer with Back and Skip or Continue. Every step is one
 * tap and every step can be skipped; the kit and tabs are applied as soon
 * as the flow leaves the tab step (onboardingStore.ts).
 */

import { Suspense, useEffect, useMemo, useRef, useState, type CSSProperties, type PointerEvent as ReactPointerEvent, type ReactNode } from "react";
import type { AppServices } from "../../app/appServices";
import { ModuleContext } from "../../app/context";
import type { NotchTakeover } from "../../app/takeover";
import { useStore } from "../../app/useStore";
import { kitAccentModule, kitLayout } from "../../core/kits/kitApplication";
import type { KitManifest, KitQuestion } from "../../core/kits/kitManifest";
import { tr } from "../../core/localization/tr";
import type { ModuleCatalog } from "../../core/modules/moduleCatalog";
import type { ModuleAccent, ModuleDescriptor } from "../../core/modules/moduleDescriptor";
import type { ModuleID } from "../../core/modules/moduleId";
import type { OnboardingExtra } from "../../core/onboarding/onboardingExtra";
import type { OnboardingFlow } from "../../core/onboarding/onboardingFlow";
import type { OnboardingSetupStep } from "../../core/onboarding/onboardingSetupStep";
import { DISPLAY_NAME_MAX_LENGTH } from "../../core/settings/displayName";
import { settingsCleanedName } from "../../core/settings/appSettings";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { studyPet } from "../../modules/closet/closetServices";
import { Card } from "../kit/Card";
import { useTheme, useTransition } from "../kit/context";
import { Icon } from "../kit/Icon";
import { PetPlayer } from "../kit/petPlayer";
import { PetView } from "../kit/PetView";
import { Pill } from "../kit/Pill";
import { TextField } from "../kit/TextField";
import { Toggle } from "../kit/Toggle";
import { accentCss, accentVariables } from "../kit/tokens";
import { Tooltip } from "../kit/Tooltip";
import { useTactile } from "../kit/tactile";
import { setupStepView } from "../shell/SetupFallback";
import { isWindowsStage, type OnboardingStep, OnboardingStore } from "./onboardingStore";
import "./onboarding.css";

/** The takeover the island shows while `store` runs. */
export function onboardingTakeover(store: OnboardingStore, app: AppServices): NotchTakeover {
  return {
    Leading: () => <OnboardingTitle store={store} app={app} />,
    Trailing: () => <OnboardingProgress store={store} app={app} />,
    Body: () => <OnboardingBody store={store} app={app} />,
  };
}

interface Props {
  readonly store: OnboardingStore;
  readonly app: AppServices;
}

function heading(step: OnboardingStep, flow: OnboardingFlow, appName: string): { symbol: string; title: string } {
  switch (step.kind) {
    case "name":
      return { symbol: "sparkles", title: tr("Welcome to %@", appName) };
    case "kit":
    case "finished":
      return flow.asksName ? { symbol: "square.stack.3d.up", title: tr("Pick a kit") } : { symbol: "sparkles", title: tr("Welcome to %@", appName) };
    case "question":
      return { symbol: flow.kit?.symbol ?? "sparkles", title: tr("Set up %@", flow.kit?.name ?? tr("your kit")) };
    case "modules":
      return { symbol: "square.grid.2x2.fill", title: tr("Your tabs") };
    case "setup":
      return { symbol: flow.currentSetupStep?.symbol ?? "gearshape.fill", title: flow.currentSetupStep?.title ?? tr("Setup") };
    case "extras":
      return { symbol: "gift.fill", title: tr("A few extras") };
    case "startWithWindows":
      return { symbol: "bolt.fill", title: tr("Start with Windows") };
    case "trayIcon":
      return { symbol: "menubar.rectangle", title: tr("Pin the tray icon") };
  }
}

/** The step's symbol and name. */
function OnboardingTitle({ store, app }: Props) {
  const { flow } = useStore(store);
  if (flow === undefined) return null;
  const { symbol, title } = heading(store.step, flow, app.environment.edition.name);
  return (
    <span className="takeover-step ob-title" key={title}>
      <Icon id={symbol} size={13} className="ob-title-symbol" />
      <span className="ob-title-text">{title}</span>
    </span>
  );
}

/** One dot per step (the current one long), then Skip Setup. */
function OnboardingProgress({ store, app }: Props) {
  const state = useStore(store);
  const transition = useTransition("snappy", ["width", "background-color"]);
  if (state.flow === undefined) return null;
  const steps = store.steps;
  const index = store.stepIndex;
  const label = tr("Step %lld of %lld", index + 1, steps.length);
  /* Many steps narrow the dots, then drop them, so Skip Setup never wraps. */
  const dot = steps.length > 8 ? 4 : 5;
  const gap = steps.length > 8 ? 3 : 4;
  return (
    <span className="ob-progress">
      {steps.length <= 12 && (
        <Tooltip text={label}>
          <span className="ob-dots" role="img" aria-label={label} style={{ gap }}>
            {steps.map((step, i) => (
              <span
                key={`${step.kind}-${i}`}
                className="ob-dot"
                data-done={i <= index}
                style={{ width: i === index ? 12 : dot, height: dot, transition }}
              />
            ))}
          </span>
        </Tooltip>
      )}
      <SkipSetup store={store} appName={app.environment.edition.name} />
    </span>
  );
}

function SkipSetup({ store, appName }: { store: OnboardingStore; appName: string }) {
  const tactile = useTactile();
  return (
    <Tooltip text={tr("Start using %@ with what you picked so far. Settings can run setup again.", appName)}>
      <button type="button" className="ob-skip" {...tactile.data} {...tactile.handlers} style={tactile.style} onClick={() => store.finish()}>
        {tr("Skip Setup")}
      </button>
    </Tooltip>
  );
}

/** The current step above a footer with Back and Skip or Continue. */
function OnboardingBody({ store, app }: Props) {
  const state = useStore(store);
  const flow = state.flow;
  if (flow === undefined) return null;
  const step = store.step;
  const catalog = app.settings.catalog;
  const setupView = step.kind === "setup" ? setupViewFor(flow, app) : undefined;
  const key = step.kind === "question" || step.kind === "setup" ? `${step.kind}-${step.id}` : step.kind;
  return (
    <div className="ob">
      <div className="ob-step" key={key}>
        {renderStep(step, flow, store, app, setupView?.View, catalog)}
      </div>
      <OnboardingFooter store={store} app={app} flow={flow} step={step} hasSetupView={setupView?.own === true} />
    </div>
  );
}

function setupViewFor(flow: OnboardingFlow, app: AppServices) {
  const step = flow.currentSetupStep;
  if (step === undefined) return undefined;
  const own = app.modules.setupView(step, flow.layout.enabled);
  return { View: own ?? setupStepView(step, flow.layout.enabled, app.modules, app.settings.catalog), own: own !== undefined };
}

function renderStep(
  step: OnboardingStep,
  flow: OnboardingFlow,
  store: OnboardingStore,
  app: AppServices,
  SetupView: ReturnType<typeof setupStepView> | undefined,
  catalog: ModuleCatalog,
) {
  switch (step.kind) {
    case "name":
      return <NameStep app={app} onSubmit={() => store.next()} />;
    case "kit":
    case "finished":
      return <KitStep flow={flow} store={store} app={app} />;
    case "question": {
      const question = flow.currentQuestion;
      return question === undefined ? null : <QuestionStep flow={flow} question={question} store={store} />;
    }
    case "modules":
      return <ModulesStep flow={flow} store={store} />;
    case "setup": {
      const current = flow.currentSetupStep;
      if (current === undefined || SetupView === undefined) return null;
      return (
        <Suspense fallback={null}>
          <SetupView step={current} done={() => store.next()} />
        </Suspense>
      );
    }
    case "extras":
      return <ExtrasStep extras={flow.currentExtras} catalog={catalog} />;
    case "startWithWindows":
      return <StartWithWindowsStep app={app} />;
    case "trayIcon":
      return <TrayIconStep app={app} />;
  }
}

interface FooterProps extends Props {
  readonly flow: OnboardingFlow;
  readonly step: OnboardingStep;
  /** True when the setup step is drawn by its module (and so has something to keep), false for the pointer-to-the-tab fallback. */
  readonly hasSetupView: boolean;
}

/** Back on the left; Skip (or Continue where the step has no one-tap answer) on the right. */
function OnboardingFooter({ store, app, flow, step, hasSetupView }: FooterProps) {
  const settings = useStore(app.settings.settings);
  const isLast = store.isLastStep;
  const owner = flow.currentSetupStep === undefined ? undefined : ownerOf(flow.currentSetupStep, flow);
  let primary: boolean;
  switch (step.kind) {
    case "modules":
    case "extras":
    case "startWithWindows":
    case "trayIcon":
      primary = true;
      break;
    case "name":
      primary = settingsCleanedName(settings) !== undefined;
      break;
    case "question":
      primary = flow.currentQuestion?.allowsMultiple === true;
      break;
    case "setup":
      primary = hasSetupView;
      break;
    default:
      primary = false;
  }
  const title = isLast ? (primary ? tr("Done") : tr("Skip and Finish")) : primary ? tr("Continue") : tr("Skip");
  let help: string;
  switch (step.kind) {
    case "name":
      help = primary ? tr("Keep this name") : tr("Go on without a name");
      break;
    case "kit":
    case "finished":
      help = flow.kit === undefined ? tr("Keep the suggested kit") : tr("Keep the %@ kit", flow.kit.name);
      break;
    case "question":
      help = tr("Leave this question unanswered");
      break;
    case "modules":
      help = isLast ? tr("Start with these tabs") : tr("Keep these tabs and set up what they need");
      break;
    case "setup":
      help = hasSetupView ? (isLast ? tr("Finish setup") : tr("Keep this and go on")) : tr("Set this up later from its tab");
      break;
    case "startWithWindows":
      help = isLast ? tr("Finish setup") : tr("Keep this and go on");
      break;
    default:
      help = tr("Finish setup");
  }
  let hint: string;
  switch (step.kind) {
    case "name":
      hint = tr("You can change it any time in Settings > General.");
      break;
    case "kit":
    case "finished":
      hint = tr("A kit is a set of tabs. You can change them any time.");
      break;
    case "question":
      hint = flow.currentQuestion?.allowsMultiple === true ? tr("Pick any that fit.") : tr("One tap moves on.");
      break;
    case "modules":
      hint = tr("Click a tab to turn it on or off. Drag to reorder.");
      break;
    case "setup":
      hint = hasSetupView && owner !== undefined ? tr("You can change this later in the %@ tab.", owner.title) : "";
      break;
    case "extras":
      hint = tr("All optional. Nothing to do now.");
      break;
    case "startWithWindows":
      hint = tr("Off until you turn it on. Settings > General has the switch too.");
      break;
    case "trayIcon":
      hint = tr("Shown once. Tabbi won't ask again.");
      break;
  }
  return (
    <div className="ob-footer">
      {store.canGoBack && <FooterButton title={tr("Back")} symbol="chevron.backward" help={tr("Go back one step")} onClick={() => store.back()} />}
      <span className="ob-hint kit-caption" data-centered={store.canGoBack}>
        {hint}
      </span>
      <FooterButton title={title} symbol="chevron.forward" primary={primary} help={help} onClick={() => store.next()} />
    </div>
  );
}

/** The first enabled tab that asked for `step`. */
function ownerOf(step: OnboardingSetupStep, flow: OnboardingFlow): ModuleDescriptor | undefined {
  return flow.layout.enabled.map((id) => flow.catalog.descriptor(id)).find((descriptor) => descriptor.setup.some((declared) => declared.id === step.id));
}

function FooterButton({ title, symbol, primary = false, help, onClick }: { title: string; symbol: string; primary?: boolean; help: string; onClick: () => void }) {
  const tactile = useTactile();
  const transition = useTransition("snappy", ["background-color", "color"]);
  const back = symbol === "chevron.backward";
  return (
    <Tooltip text={help}>
      <button
        type="button"
        className="ob-footer-button"
        data-primary={primary}
        {...tactile.data}
        {...tactile.handlers}
        style={{ ...tactile.style, transition: [tactile.style.transition, transition].filter(Boolean).join(", ") }}
        onClick={onClick}
      >
        {back && <Icon id={symbol} size={10} />}
        <span>{title}</span>
        {!back && <Icon id={symbol} size={10} />}
      </button>
    </Tooltip>
  );
}

interface TileProps {
  readonly selected?: boolean;
  /** The ring's color when selected; the primary text by default. */
  readonly tint?: string;
  /** Short tiles trim their top and bottom padding and center their label. */
  readonly compact?: boolean;
  readonly help: string;
  readonly onClick: () => void;
  readonly className?: string;
  readonly style?: CSSProperties;
  readonly children?: ReactNode;
  readonly onPointerDown?: (event: ReactPointerEvent<HTMLButtonElement>) => void;
}

/** A selectable tile on the island: a card that lights up on hover and rings in `tint` when selected. */
function OnboardingTile({ selected = false, tint, compact = false, help, onClick, className, style, children, onPointerDown }: TileProps) {
  const tactile = useTactile();
  const transition = useTransition("snappy", ["background-color", "box-shadow"]);
  return (
    <Tooltip text={help}>
      <button
        type="button"
        className={["ob-tile", className].filter(Boolean).join(" ")}
        data-selected={selected}
        data-compact={compact}
        aria-pressed={selected}
        {...tactile.data}
        {...tactile.handlers}
        style={{ "--tile-tint": tint ?? "var(--primary-text)", ...tactile.style, transition: [tactile.style.transition, transition].filter(Boolean).join(", "), ...style } as CSSProperties}
        onClick={onClick}
        onPointerDown={(event) => {
          tactile.handlers.onPointerDown(event);
          onPointerDown?.(event);
        }}
      >
        {children}
      </button>
    </Tooltip>
  );
}

/**
 * The name step: one field for what to call the user, saved to the app-wide
 * name as it is typed. Enter moves on. The pet greets the user beside it, so
 * the first thing Tabbi shows is its cat, not a form.
 */
function NameStep({ app, onSubmit }: { app: AppServices; onSubmit: () => void }) {
  const settings = useStore(app.settings.settings);
  const pet = useStore(studyPet(new ModuleContext(MODULE_IDS.closet, app.environment)));
  const offersParty = app.settings.catalog.contains(MODULE_IDS.party);
  const appName = app.environment.edition.name;
  /* A fixed seed keeps snapshots stable; the pet hops hello once as the step appears. */
  const player = useMemo(() => new PetPlayer(pet.profile, { seed: 7 }), [pet.profile]);
  useEffect(() => {
    if (!app.environment.runMode.isSnapshot) player.send({ kind: "nudge" });
  }, [player, app.environment.runMode.isSnapshot]);
  return (
    <Card className="ob-name">
      <Tooltip text={tr("Hi! I'm %@.", pet.profile.name)}>
        <span className="ob-name-pet">
          <PetView player={player} pixelSize={2} />
        </span>
      </Tooltip>
      <div className="ob-name-text">
        <div className="kit-title">{tr("What should we call you?")}</div>
        <div className="kit-caption kit-secondary ob-name-detail">
          {offersParty ? tr("Friends see it in Party, and %@ uses it to greet you.", appName) : tr("%@ uses it to greet you.", appName)}
        </div>
        <TextField
          value={settings.displayName}
          onChange={(value) => app.settings.update((current) => ({ ...current, displayName: [...value].slice(0, DISPLAY_NAME_MAX_LENGTH).join("") }))}
          onSubmit={onSubmit}
          label={tr("Your name")}
          placeholder={tr("Your name")}
          help={tr("Your name, up to %lld characters", DISPLAY_NAME_MAX_LENGTH)}
          width={220}
          className="ob-name-field"
          autoFocus
        />
      </div>
    </Card>
  );
}

/** A row of small tinted tab symbols. */
function TabSymbols({ modules, catalog, size = 14 }: { modules: readonly ModuleID[]; catalog: ModuleCatalog; size?: number }) {
  const theme = useTheme();
  return (
    <span className="ob-tab-symbols">
      {modules.map((id) => {
        const descriptor = catalog.descriptor(id);
        return (
          <Tooltip key={id} text={descriptor.title}>
            <span className="ob-tab-symbol" style={{ width: size, height: size, ...accentVariables(theme, descriptor.accent) } as CSSProperties}>
              <Icon id={descriptor.symbol} size={Math.round(size * 0.55)} />
            </span>
          </Tooltip>
        );
      })}
    </span>
  );
}

function kitTint(kit: KitManifest, catalog: ModuleCatalog, theme: ReturnType<typeof useTheme>): string | undefined {
  const module = kitAccentModule(kit, catalog);
  return module === undefined ? undefined : accentCss(theme, catalog.descriptor(module).accent);
}

/** Step 1: one card per kit with the tabs it turns on, and Start from Scratch. */
function KitStep({ flow, store, app }: { flow: OnboardingFlow; store: OnboardingStore; app: AppServices }) {
  const theme = useTheme();
  const catalog = flow.catalog;
  useStore(app.settings.kitsChanged);
  return (
    <div className="ob-kits">
      {app.settings.kits.kits.map((kit) => {
        const tabs = kitLayout(kit, catalog).enabled;
        const tint = kitTint(kit, catalog, theme) ?? "var(--primary-text)";
        const selected = flow.kit?.id === kit.id && !flow.startedFromScratch;
        return (
          <OnboardingTile
            key={kit.id}
            selected={selected}
            tint={tint}
            help={`${kit.name}: ${tabs.map((id) => catalog.descriptor(id).title).join(", ")}`}
            onClick={() => store.update((current) => current.choose(kit))}
            className="ob-kit"
          >
            <span className="ob-kit-badge" style={{ background: tint }}>
              <Icon id={kit.symbol} size={13} />
            </span>
            <span className="kit-body-emphasis ob-kit-name kit-user-text">{kit.name}</span>
            <span className="kit-caption kit-secondary ob-kit-summary kit-user-text">{kit.summary}</span>
            <span className="ob-kit-tabs">
              <TabSymbols modules={tabs} catalog={catalog} />
            </span>
          </OnboardingTile>
        );
      })}
      <OnboardingTile
        selected={flow.startedFromScratch}
        help={tr("Start with one tab and turn on the ones you want")}
        onClick={() => store.update((current) => current.startFromScratch())}
        className="ob-scratch"
      >
        <span className="ob-scratch-badge">
          <Icon id="plus" size={14} />
        </span>
        <span className="kit-caption kit-secondary">{tr("Start from Scratch")}</span>
      </OnboardingTile>
    </div>
  );
}

/** One of the kit's questions: a row of answer tiles, then the tabs the answers turn on so far. */
function QuestionStep({ flow, question, store }: { flow: OnboardingFlow; question: KitQuestion; store: OnboardingStore }) {
  const theme = useTheme();
  const picked = flow.answers[question.id] ?? new Set<string>();
  const tint = flow.kit === undefined ? undefined : kitTint(flow.kit, flow.catalog, theme);
  return (
    <div className="ob-question">
      <div className="kit-title kit-user-text">{question.prompt}</div>
      <div className="ob-answers">
        {question.options.map((option) => {
          const isPicked = picked.has(option.id);
          return (
            <OnboardingTile
              key={option.id}
              selected={isPicked}
              tint={tint}
              help={isPicked && question.allowsMultiple ? tr('Clear "%@"', option.label) : option.label}
              onClick={() => store.update((current) => current.answer(option.id))}
              className="ob-answer"
            >
              <span className="ob-answer-symbol" style={{ color: isPicked ? (tint ?? "var(--primary-text)") : "var(--secondary-text)" }}>
                <Icon id={option.symbol ?? "circle"} size={16} />
              </span>
              <span className="kit-body ob-answer-label kit-user-text">{option.label}</span>
            </OnboardingTile>
          );
        })}
      </div>
      <div className="ob-your-tabs">
        <span className="kit-caption kit-tertiary">{tr("Your tabs")}</span>
        <TabSymbols modules={flow.layout.enabled} catalog={flow.catalog} />
      </div>
    </div>
  );
}

/* The tabs grid: five columns keep titles such as Claude Usage whole; tiles share the step's height. */
const COLUMNS = 5;
const TILE_HEIGHT = 52;
const ROOMY_TILE_HEIGHT = 49;
const STACKED_TILE_HEIGHT = 41;
const GRID_GAP = 8;

/** Every tab as a tile in tab bar order: click turns it on or off, drag moves it. The number is the key that jumps to it. */
function ModulesStep({ flow, store }: { flow: OnboardingFlow; store: OnboardingStore }) {
  const theme = useTheme();
  const grid = useRef<HTMLDivElement>(null);
  const [height, setHeight] = useState(0);
  const [dragging, setDragging] = useState<ModuleID | undefined>(undefined);
  useEffect(() => {
    const element = grid.current;
    if (!element) return;
    const measure = () => setHeight(element.clientHeight);
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);
  const order = flow.layout.order;
  const rows = Math.max(Math.ceil(order.length / COLUMNS), 1);
  const fitted = height > 0 ? Math.floor((height - GRID_GAP * (rows - 1)) / rows) : TILE_HEIGHT;
  const rowHeight = Math.min(TILE_HEIGHT, Math.max(fitted, 24));
  const stacked = rowHeight >= STACKED_TILE_HEIGHT;
  const compact = rowHeight < ROOMY_TILE_HEIGHT;

  /* Moves the dragged tile into the slot under the pointer, live. */
  const dragTo = (id: ModuleID, x: number, y: number) => {
    const element = grid.current;
    if (!element) return;
    const rect = element.getBoundingClientRect();
    const columnWidth = (rect.width - GRID_GAP * (COLUMNS - 1)) / COLUMNS;
    if (columnWidth <= 0) return;
    const rtl = getComputedStyle(element).direction === "rtl";
    const localX = rtl ? rect.right - x : x - rect.left;
    const column = Math.min(Math.max(Math.floor(localX / (columnWidth + GRID_GAP)), 0), COLUMNS - 1);
    const row = Math.max(Math.floor((y - rect.top) / (rowHeight + GRID_GAP)), 0);
    const current = flow.layout.order;
    const from = current.indexOf(id);
    const to = Math.min(row * COLUMNS + column, current.length - 1);
    if (from < 0 || to === from) return;
    store.update((value) => value.move([from], to > from ? to + 1 : to));
  };

  const startDrag = (id: ModuleID) => (event: ReactPointerEvent<HTMLButtonElement>) => {
    if (event.button !== 0) return;
    const startX = event.clientX;
    const startY = event.clientY;
    let moved = false;
    const onMove = (move: PointerEvent) => {
      if (!moved && Math.hypot(move.clientX - startX, move.clientY - startY) < 6) return;
      moved = true;
      setDragging(id);
      dragTo(id, move.clientX, move.clientY);
    };
    const onUp = () => {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      window.removeEventListener("pointercancel", onUp);
      setDragging(undefined);
      /* A drag ends on the tile without toggling it: the click that follows is swallowed once. */
      if (moved) suppressClick.current = true;
    };
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointercancel", onUp);
  };
  const suppressClick = useRef(false);

  return (
    <div ref={grid} className="ob-modules" style={{ gap: GRID_GAP, gridTemplateColumns: `repeat(${COLUMNS}, minmax(0, 1fr))` }}>
      {order.map((id) => {
        const module = flow.catalog.descriptor(id);
        const isOn = flow.layout.isEnabled(id);
        const canTurnOff = flow.layout.canDisable(id);
        const shortcut = flow.layout.shortcut(id);
        const headerKey = flow.layout.headerKey(id);
        const key = shortcut !== undefined ? String(shortcut) : headerKey?.toUpperCase();
        const accent = accentCss(theme, module.accent);
        return (
          <OnboardingTile
            key={id}
            selected={isOn}
            tint={accentCss(theme, module.accent, 0.7)}
            compact={compact}
            help={isOn ? (canTurnOff ? tr("Turn %@ off", module.title) : tr("Keep at least one tab on")) : tr("Turn %@ on", module.title)}
            onClick={() => {
              if (suppressClick.current) {
                suppressClick.current = false;
                return;
              }
              store.update((value) => void value.setEnabled(id, !isOn));
            }}
            onPointerDown={startDrag(id)}
            className="ob-module"
            style={{ height: rowHeight, zIndex: dragging === id ? 1 : undefined, transform: dragging === id ? "scale(1.05)" : undefined, opacity: dragging === id ? 0.8 : undefined }}
          >
            <span className="ob-module-inner" data-stacked={stacked}>
              <span className="ob-module-symbol" style={{ color: isOn ? accent : "var(--tertiary-text)" }}>
                <Icon id={module.symbol} size={12} />
              </span>
              <span className="kit-caption ob-module-title" style={{ color: isOn ? "var(--primary-text)" : "var(--tertiary-text)" }}>
                {module.title}
              </span>
              {key !== undefined && <span className="kit-caption kit-tertiary ob-module-key">{key}</span>}
            </span>
          </OnboardingTile>
        );
      })}
    </div>
  );
}

/** The last screen of the Mac's flow: each optional extra as a tile in one row. */
function ExtrasStep({ extras, catalog }: { extras: readonly OnboardingExtra[]; catalog: ModuleCatalog }) {
  const theme = useTheme();
  return (
    <div className="ob-extras">
      {extras.map((extra) => {
        const accent: ModuleAccent | undefined = extra.module === undefined ? undefined : catalog.descriptor(extra.module).accent;
        const tint = accent === undefined ? "var(--secondary-text)" : accentCss(theme, accent);
        return (
          <Tooltip key={extra.id} text={`${extra.title}: ${extra.detail}`}>
            <div className="ob-extra kit-card">
              <span className="ob-extra-symbol" style={{ color: tint, background: `color-mix(in srgb, ${tint} 16%, transparent)` }}>
                <Icon id={extra.symbol} size={11} />
              </span>
              <span className="ob-extra-text">
                <span className="kit-body-emphasis">{extra.title}</span>
                <span className="kit-caption kit-secondary">{extra.detail}</span>
              </span>
            </div>
          </Tooltip>
        );
      })}
    </div>
  );
}

/** Windows' own step: the opt-in switch for starting Tabbi when the user signs in. */
function StartWithWindowsStep({ app }: { app: AppServices }) {
  const settings = useStore(app.settings.settings);
  const error = useStore(app.settings.launchAtLoginError);
  useEffect(() => {
    void app.settings.refreshLaunchAtLogin();
  }, [app.settings]);
  return (
    <Card className="ob-windows">
      <span className="ob-windows-badge">
        <Icon id="bolt.fill" size={20} />
      </span>
      <span className="ob-windows-text">
        <span className="kit-title">{tr("Start with Windows")}</span>
        <span className="kit-body kit-secondary">{tr("Opens Tabbi when you sign in, so your timer and pet are there from the first minute.")}</span>
        {error !== undefined && <span className="kit-caption ob-windows-error">{tr("Windows didn't accept the change. Try again from Settings > General.")}</span>}
      </span>
      <Toggle isOn={settings.launchAtLogin} onChange={(on) => void app.settings.setLaunchAtLogin(on)} label={tr("Start with Windows")} help={tr("Open Tabbi automatically when you sign in to Windows")} />
    </Card>
  );
}

/** Windows' last step: how to drag the tray icon out of the hidden icons, drawn as a small taskbar. */
function TrayIconStep({ app }: { app: AppServices }) {
  return (
    <Card className="ob-tray">
      <span className="ob-tray-art" aria-hidden="true">
        <span className="ob-tray-bar">
          <span className="ob-tray-chevron">
            <Icon id="chevron.up" size={9} />
          </span>
          <span className="ob-tray-slot" />
          <span className="ob-tray-slot" />
          <span className="ob-tray-icon">
            <Icon id="pawprint.fill" size={9} />
          </span>
          <span className="ob-tray-clock">9:41</span>
        </span>
        <span className="ob-tray-flyout">
          <span className="ob-tray-ghost">
            <Icon id="pawprint.fill" size={9} />
          </span>
          <span className="ob-tray-slot" />
          <span className="ob-tray-slot" />
        </span>
        <svg className="ob-tray-arrow" width="44" height="40" viewBox="0 0 44 40" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
          <path d="M6 4c4 14 16 24 34 30" strokeDasharray="3 3" />
          <path d="m33 29 7 5-4 5" />
        </svg>
      </span>
      <span className="ob-tray-text">
        <span className="kit-title">{tr("Pin the tray icon")}</span>
        <span className="kit-body kit-secondary">{tr("Windows tucks new icons behind the arrow by the clock. Drag Tabbi's paw onto the taskbar once and it stays there.")}</span>
        <span className="ob-tray-actions">
          <Pill title={tr("Open taskbar settings")} symbol="menubar.rectangle" help={tr("Opens Windows' taskbar settings, where tray icons can be turned on too")} onClick={() => void app.environment.host.openUrl("ms-settings:taskbar")} />
        </span>
      </span>
    </Card>
  );
}

/** The step a snapshot names, for the harness. */
export function isOnboardingStepKind(kind: string): kind is OnboardingStep["kind"] {
  return ["name", "kit", "question", "modules", "setup", "extras", "startWithWindows", "trayIcon"].includes(kind);
}

export { isWindowsStage };
