/*
 * Ports of FocusCard.swift and SharedFocusCard.swift: the Today panel's
 * compact Pomodoro card (a progress ring that doubles as the start/pause
 * button, the countdown with its phase, and the linked task; skip and stop
 * appear on hover once a session is under way), and the card that stands in
 * for it when another enabled module runs its own focus clock, mirroring
 * that clock from the provider snapshot in the owner's accent and opening
 * the owner's tab on click.
 */

import { useState, type CSSProperties } from "react";
import type { ModuleContext } from "../../app/context";
import { useStore } from "../../app/useStore";
import { focusClock, focusPhaseName, focusStatus } from "../../core/focus/focusTimerFormat";
import { tr } from "../../core/localization/tr";
import type { ModuleID } from "../../core/modules/moduleId";
import type { PlannerItem } from "../../core/planner/plannerDay";
import type { ProvidedFocus } from "../../core/providers/providedFocus";
import { studyClock } from "../../core/studyMethods/studyTimerFormat";
import { Card } from "../../ui/kit/Card";
import { useTheme } from "../../ui/kit/context";
import { Icon } from "../../ui/kit/Icon";
import { IconButton } from "../../ui/kit/IconButton";
import { ProgressRing } from "../../ui/kit/Loading";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { accentCss } from "../../ui/kit/tokens";
import { Tooltip } from "../../ui/kit/Tooltip";
import type { FocusCardActions } from "./focusCardActions";
import { useClock } from "./useClock";

export interface FocusCardProps {
  readonly context: ModuleContext;
  readonly actions: FocusCardActions;
  /** Today's checklist, to resolve the linked item's title. */
  readonly items: readonly PlannerItem[];
}

export function FocusCard({ context, actions, items }: FocusCardProps) {
  const { timer } = useStore(actions.service);
  const [hovering, setHovering] = useState(false);
  const now = useClock(context, 1, timer.isRunning);
  if (timer.isRunning && (timer.endsAt ?? Number.POSITIVE_INFINITY) <= now) actions.advance();
  const remaining = timer.remaining(now);
  const progress = timer.progress(now);
  const linked = timer.linkedItemID === undefined ? undefined : items.find((item) => item.id === timer.linkedItemID)?.title;
  const idle = timer.runState.kind === "idle";
  const toggleHelp =
    timer.runState.kind === "running"
      ? tr("Pause")
      : timer.runState.kind === "paused"
        ? tr("Resume")
        : timer.phase === "focus"
          ? tr("Start a focus session")
          : tr("Start the break");
  const skipHelp = timer.phase === "focus" ? tr("Skip to the break") : tr("Skip the break");
  const showsControls = hovering && (!idle || timer.phase === "rest");
  return (
    <Card padding={0} className="focus-card" onPointerEnter={() => setHovering(true)} onPointerLeave={() => setHovering(false)}>
      <Tooltip text={toggleHelp}>
        <button type="button" className="focus-ring-button" aria-label={toggleHelp} onClick={() => actions.toggleRunning()}>
          <ProgressRing progress={progress} size={28} lineWidth={2.5}>
            <span className="focus-ring-fill" />
            <span className="focus-ring-glyph" data-running={timer.isRunning}>
              <Icon id={timer.isRunning ? "pause.fill" : "play.fill"} size={10} />
            </span>
          </ProgressRing>
        </button>
      </Tooltip>
      <div className="focus-card-text">
        <div className="focus-card-line">
          <span className="focus-card-clock" data-running={timer.isRunning}>
            {focusClock(remaining)}
          </span>
          <span className="focus-card-phase" data-rest={timer.phase === "rest"}>
            {focusPhaseName(timer.phase)}
          </span>
        </div>
        {linked !== undefined && timer.phase === "focus" ? (
          <div className="focus-card-detail focus-card-linked" title={tr("Focusing on: %@", linked)}>
            <Icon id="scope" size={9} className="focus-card-scope" />
            <MarqueeText text={linked} help={tr("Focusing on: %@", linked)} />
          </div>
        ) : (
          <MarqueeText text={focusStatus(timer)} className="focus-card-detail" />
        )}
      </div>
      {showsControls && (
        <div className="focus-card-controls">
          <IconButton symbol="forward.end.fill" size={20} help={skipHelp} onClick={() => actions.skip()} />
          <IconButton symbol="stop.fill" size={20} help={tr("Stop and keep the time focused so far")} onClick={() => actions.stop()} />
        </div>
      )}
    </Card>
  );
}

export interface SharedFocusCardProps {
  readonly context: ModuleContext;
  readonly owner: ModuleID;
  readonly open: (module: ModuleID) => void;
}

/** Share of the phase done; a phase that counts up shows a full ring. */
function sharedProgress(focus: ProvidedFocus | undefined, now: number): number {
  if (focus === undefined || !focus.isActive) return 0;
  const length = focus.phaseLength;
  if (length === undefined || length <= 0) return 1;
  return Math.min(Math.max(focus.elapsed(now) / length, 0), 1);
}

export function SharedFocusCard({ context, owner, open }: SharedFocusCardProps) {
  const theme = useTheme();
  const snapshot = useStore(context.snapshot);
  const descriptor = context.settings.catalog.descriptor(owner);
  /* The merged clock may come from another engine; only the owner's counts here. */
  const focus = snapshot.focus !== undefined && snapshot.focus.source === owner ? snapshot.focus : undefined;
  const now = useClock(context, 1, focus?.isRunning === true);
  const accent = accentCss(theme, descriptor.accent);
  const help = tr("Open %@ to start, pause or skip", descriptor.title);
  return (
    <Tooltip text={help}>
      <button type="button" className="focus-card-button" aria-label={help} onClick={() => open(owner)}>
        <Card padding={0} className="focus-card shared-focus-card" style={{ "--card-accent": accent } as CSSProperties}>
          <ProgressRing progress={sharedProgress(focus, now)} size={28} lineWidth={2.5} tint={accent} track={`color-mix(in srgb, ${accent} 20%, transparent)`}>
            <span className="focus-ring-fill" style={{ background: `color-mix(in srgb, ${accent} 10%, transparent)` }} />
            <span className="focus-ring-glyph" style={{ color: accent }}>
              <Icon id={descriptor.symbol} size={10} />
            </span>
          </ProgressRing>
          <div className="focus-card-text">
            {focus !== undefined ? (
              <>
                <div className="focus-card-line">
                  <span className="focus-card-clock" data-running={focus.isRunning}>
                    {studyClock(focus.shownTime(now))}
                  </span>
                  <span className="focus-card-phase" data-rest={focus.phase === "rest"} style={focus.phase === "rest" ? { color: accent } : undefined}>
                    {focus.label}
                  </span>
                </div>
                <MarqueeText text={focus.isPaused ? tr("Paused in %@", descriptor.title) : tr("Running in %@", descriptor.title)} className="focus-card-detail" />
              </>
            ) : (
              <>
                <MarqueeText text={tr("Start a timer")} className="focus-card-clock focus-card-idle" />
                <MarqueeText text={tr("Opens the %@ tab", descriptor.title)} className="focus-card-detail focus-card-tertiary" />
              </>
            )}
          </div>
        </Card>
      </button>
    </Tooltip>
  );
}
