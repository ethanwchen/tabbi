/*
 * Port of FocusPanel: the Focus tab. A large countdown dial on the left
 * (the panel's primary element), and on the right one card with what this
 * session is for and what focus mode does while it runs, then the timer
 * controls. The focus mode row opens the sound mixer Study uses in place of
 * the timer, so the sound playing in a session can be changed without
 * leaving it.
 */

import { useEffect } from "react";
import type { ModuleContext } from "../../app/context";
import { useStore } from "../../app/useStore";
import { focusClock, focusPhaseName, focusStatus } from "../../core/focus/focusTimerFormat";
import { tr } from "../../core/localization/tr";
import { MODULE_IDS } from "../../core/modules/moduleId";
import type { ModuleAccent } from "../../core/themes/themeColor";
import { Card } from "../../ui/kit/Card";
import { Icon } from "../../ui/kit/Icon";
import { IconButton } from "../../ui/kit/IconButton";
import { ProgressRing } from "../../ui/kit/Loading";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { PrimaryPill } from "../../ui/kit/PrimaryPill";
import { Tooltip } from "../../ui/kit/Tooltip";
import { StudySoundMixer } from "../study/studySoundViews";
import type { FocusController } from "./focusController";
import type { FocusStore } from "./focusStore";
import { PanelCelebrations } from "./panelCelebrations";
import "./focus.css";

export interface FocusPanelProps {
  readonly store: FocusStore;
  /** Focus mode, whose sound settings the panel shows. */
  readonly focusMode: FocusController;
  readonly context: ModuleContext;
  readonly accent: ModuleAccent;
  /** Whether the mixer shows instead of the timer; the module keeps it so a snapshot can open it. */
  readonly showsMixer: boolean;
  readonly setShowsMixer: (shows: boolean) => void;
}

export function FocusPanel({ store, focusMode, context, accent, showsMixer, setShowsMixer }: FocusPanelProps) {
  useEffect(() => {
    store.setVisible(true, "focus");
    return () => store.setVisible(false, "focus");
  }, [store]);
  return (
    <PanelCelebrations
      className="focus-panel"
      requests={(play) => store.celebrations.on(({ style }) => play(style))}
      accent={accent}
      source={MODULE_IDS.focus}
      now={() => context.now()}
      timeZone={() => context.timeZone()}
    >
      {showsMixer ? (
        <StudySoundMixer focus={focusMode} close={() => setShowsMixer(false)} />
      ) : (
        <div className="focus-timer">
          <FocusDial store={store} />
          <div className="focus-column">
            <FocusSessionCard store={store} focusMode={focusMode} context={context} openMixer={() => setShowsMixer(true)} />
            <FocusControls store={store} />
          </div>
        </div>
      )}
    </PanelCelebrations>
  );
}

/** The countdown inside a progress ring, with the phase underneath. */
function FocusDial({ store }: { store: FocusStore }) {
  const { timer, now } = useStore(store);
  const remaining = timer.remaining(now);
  const phase = focusPhaseName(timer.phase);
  const label = timer.isPaused ? tr("%@ · Paused", phase) : phase;
  return (
    <Tooltip text={tr("%@: %@ left", phase, focusClock(remaining))}>
      <Card padding={0} className="focus-dial">
        <ProgressRing progress={timer.progress(now)} size={128} lineWidth={6}>
          <div className="focus-dial-center">
            <span className="focus-dial-value" data-running={timer.isRunning}>
              {focusClock(remaining)}
            </span>
            <span className="kit-caption" style={{ color: timer.phase === "rest" ? "var(--accent)" : "var(--tertiary-text)" }}>
              {label}
            </span>
          </div>
        </ProgressRing>
      </Card>
    </Tooltip>
  );
}

/**
 * What this session is for (the task linked from Today, or the timer's
 * status) at the top and what focus mode does while it runs at the bottom:
 * one card above the controls, as in Study.
 */
function FocusSessionCard({ store, focusMode, context, openMixer }: { store: FocusStore; focusMode: FocusController; context: ModuleContext; openMixer: () => void }) {
  const { timer, sessionsToday } = useStore(store);
  const snapshot = useStore(context.snapshot);
  /* The linked item's title, while some module still lists it. */
  const linkedTitle = timer.linkedItemID === undefined ? undefined : snapshot.tasks.find((task) => task.id === timer.linkedItemID)?.title;
  const heading = timer.phase !== "focus" ? tr("Break") : linkedTitle === undefined ? tr("Focus session") : tr("Focusing on");
  return (
    <Card className="focus-card">
      <div className="focus-caption-row kit-caption kit-tertiary">
        <span>{heading}</span>
        <span className="focus-spacer" />
        {sessionsToday > 0 && <span className="focus-tabular">{tr("%lld sessions today", sessionsToday)}</span>}
      </div>
      {linkedTitle !== undefined && timer.phase === "focus" ? (
        <Tooltip text={tr("Focusing on: %@", linkedTitle)}>
          <span className="focus-task kit-title">
            <Icon id="scope" size={12} className="focus-accent" />
            <MarqueeText text={linkedTitle} userText />
          </span>
        </Tooltip>
      ) : (
        <MarqueeText className="kit-title kit-secondary" text={focusStatus(timer)} />
      )}
      <span className="focus-spacer" />
      <FocusModeRow controller={focusMode} openMixer={openMixer} />
    </Card>
  );
}

/** What focus mode does while a focus phase runs. A click opens the sound mixer, where the sounds, their levels and the volume change live, even mid-session. */
function FocusModeRow({ controller, openMixer }: { controller: FocusController; openMixer: () => void }) {
  const { settings } = useStore(controller);
  const isOn = !settings.mix.isOff;
  return (
    <Tooltip text={tr("Change the focus sound")}>
      <button type="button" className="focus-mode-row kit-caption" onClick={openMixer} aria-label={`${tr("Sound")}: ${settings.mix.summary}`}>
        <Icon id="waveform" size={11} className={isOn ? "focus-accent" : "kit-tertiary"} />
        <span className="kit-tertiary focus-mode-name">{tr("Sound")}</span>
        <MarqueeText className={isOn ? "kit-secondary" : "kit-tertiary"} text={settings.mix.summary} />
      </button>
    </Tooltip>
  );
}

/** Start or pause (the primary action), then skip and stop. */
function FocusControls({ store }: { store: FocusStore }) {
  const { timer } = useStore(store);
  /* A fresh focus session has nothing to skip or stop. */
  const isFresh = timer.runState.kind === "idle" && timer.phase === "focus";
  const primaryTitle = timer.runState.kind === "running" ? tr("Pause") : timer.runState.kind === "paused" ? tr("Resume") : timer.phase === "focus" ? tr("Start focus") : tr("Start break");
  const primaryHelp =
    timer.runState.kind === "running"
      ? tr("Pause the timer")
      : timer.runState.kind === "paused"
        ? tr("Resume the timer")
        : timer.phase === "focus"
          ? tr("Start a focus session")
          : tr("Start the break");
  return (
    <div className="focus-controls">
      <PrimaryPill title={primaryTitle} symbol={timer.isRunning ? "pause.fill" : "play.fill"} help={primaryHelp} onClick={() => store.toggleRunning()} />
      <span className="focus-spacer" />
      <IconButton symbol="forward.end.fill" help={timer.phase === "focus" ? tr("Skip to the break") : tr("Skip the break")} disabled={isFresh} onClick={() => store.skip()} />
      <IconButton symbol="stop.fill" help={tr("Stop and keep the time focused so far")} disabled={isFresh} onClick={() => store.stop()} />
    </div>
  );
}
