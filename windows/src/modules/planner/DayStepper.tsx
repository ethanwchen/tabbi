/*
 * Port of PlannerDayStepper.swift: the header's day title between two small
 * arrows that step to yesterday and tomorrow. Clicking the title of another
 * day goes back to today. An arrow with nowhere to go stays in place,
 * dimmed, so the title never shifts. Today steps its checklist with it and
 * Schedule its Day view. Also yesterday's bottom row, which moves the
 * unfinished tasks to today.
 */

import type { ReactNode } from "react";
import { tr } from "../../core/localization/tr";
import { nextViewedDay, previousViewedDay, type PlannerViewedDay } from "../../core/planner/plannerViewedDay";
import { Icon } from "../../ui/kit/Icon";
import { Tooltip } from "../../ui/kit/Tooltip";
import { PlannerPillButton } from "./plannerControls";

export interface DayStepperProps {
  readonly viewing: PlannerViewedDay;
  /** Tooltips of the arrows that leave today, naming what they show. */
  readonly yesterdayHelp?: string;
  readonly tomorrowHelp?: string;
  readonly show: (day: PlannerViewedDay) => void;
  readonly children: ReactNode;
}

export function DayStepper({ viewing, yesterdayHelp, tomorrowHelp, show, children }: DayStepperProps) {
  const arrow = (symbol: string, day: PlannerViewedDay | undefined, help: string) => {
    const label = day === "today" ? tr("Back to today") : help;
    const button = (
      <button
        type="button"
        className="planner-step"
        disabled={day === undefined}
        aria-label={label}
        onClick={() => {
          if (day !== undefined) show(day);
        }}
      >
        <Icon id={symbol} size={9} />
      </button>
    );
    return day === undefined ? button : <Tooltip text={label}>{button}</Tooltip>;
  };
  return (
    <div className="planner-stepper">
      {arrow("chevron.backward", previousViewedDay(viewing), yesterdayHelp ?? tr("Show yesterday's list"))}
      {viewing === "today" ? (
        <span className="planner-stepper-title">{children}</span>
      ) : (
        <Tooltip text={tr("Back to today")}>
          <button type="button" className="planner-stepper-title planner-stepper-button" onClick={() => show("today")}>
            {children}
          </button>
        </Tooltip>
      )}
      {arrow("chevron.forward", nextViewedDay(viewing), tomorrowHelp ?? tr("Plan tomorrow"))}
    </div>
  );
}

export interface PlannerLeftoversBarProps {
  readonly leftovers: number;
  readonly items: number;
  readonly done: number;
  readonly moveToToday: () => void;
}

/** Yesterday's bottom row: one click moves every unfinished task that isn't on today's list yet, or a quiet note once there's nothing left to move. */
export function PlannerLeftoversBar({ leftovers, items, done, moveToToday }: PlannerLeftoversBarProps) {
  if (leftovers > 0) {
    return (
      <div className="planner-leftovers">
        <span className="planner-leftovers-text">{tr("%lld tasks left unfinished", leftovers)}</span>
        <PlannerPillButton
          title={tr("Move to today")}
          symbol="arrow.uturn.forward"
          isProminent
          height={28}
          help={tr("Add the unfinished tasks to the end of today's list")}
          onClick={moveToToday}
        />
      </div>
    );
  }
  if (items === 0) return <div className="planner-leftovers" />;
  return (
    <div className="planner-leftovers">
      <span className="planner-leftovers-note">
        <Icon id="checkmark.circle.fill" size={10} />
        <span>{done === items ? tr("All done") : tr("Everything unfinished is on today")}</span>
      </span>
    </div>
  );
}
