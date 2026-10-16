/*
 * Port of PlannerPanel.swift: the Today panel. The checklist (date and
 * progress header, items, add field) on the left, which the header's
 * arrows step to yesterday or tomorrow, swapped for the Plan my day
 * proposal or the End-of-Day Review while one is open; an "Up next"
 * calendar card above a compact focus timer on the right.
 */

import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import type { ModuleContext } from "../../app/context";
import { useStore } from "../../app/useStore";
import { currentLanguage, tr } from "../../core/localization/tr";
import type { ModuleID } from "../../core/modules/moduleId";
import { isWrapUpTime } from "../../core/planner/dayReview";
import { dayKeyStart } from "../../core/planner/plannerDayKey";
import { viewedDayHeaderDateStyles, viewedDayPlanTitle, viewedDayTitle, type PlannerViewedDay } from "../../core/planner/plannerViewedDay";
import { TodayTally } from "../../core/planner/todayTally";
import type { PlanMode } from "../../core/planner/todayPlanSettings";
import type { UpNextAction } from "../../core/planner/upNextEmptyState";
import type { ProvidedAction } from "../../core/providers/progressItem";
import { sharedTodayItems } from "../../core/providers/sharedTodayItem";
import { displayNameGreeting } from "../../core/settings/displayName";
import { Icon } from "../../ui/kit/Icon";
import { IconButton } from "../../ui/kit/IconButton";
import { ProgressRing } from "../../ui/kit/Loading";
import { TextThatFits } from "../../ui/kit/TextThatFits";
import { Tooltip } from "../../ui/kit/Tooltip";
import { DayPlanView } from "./DayPlanView";
import { DayReviewView } from "./DayReviewView";
import { DayStepper, PlannerLeftoversBar } from "./DayStepper";
import { FocusCard, SharedFocusCard } from "./FocusCard";
import type { FocusCardActions } from "./focusCardActions";
import { PlannerList } from "./PlannerList";
import { formatDate } from "./plannerFormat";
import { PlannerMessage, PlannerPillButton } from "./plannerControls";
import type { PlannerStore } from "./plannerStore";
import { UpNextCard } from "./UpNextCard";
import { useClock } from "./useClock";

/** Width of the right column; the checklist keeps the remaining space. */
const SIDE_COLUMN_WIDTH = 200;

export interface TodayPanelProps {
  readonly context: ModuleContext;
  readonly store: PlannerStore;
  readonly focus: FocusCardActions;
  /** Opens another module's tab, running its action first when it has one. */
  readonly openModule: (id: ModuleID, action?: ProvidedAction) => void;
  readonly openConnections: () => void;
  /** Pins the panel's "Wrap up" hour for demo snapshots. */
  readonly eveningOverride?: boolean;
}

/** What Plan my day does, for its tooltips. */
function planHelp(mode: PlanMode, day: PlannerViewedDay): string {
  const tomorrow = day === "tomorrow";
  switch (mode) {
    case "local":
      return tomorrow ? tr("Fit your open tasks, reviews and breaks around tomorrow's calendar") : tr("Fit your open tasks, reviews and breaks around today's calendar");
    case "claude":
      return tomorrow ? tr("Let your AI fit your open tasks around tomorrow's calendar") : tr("Let your AI fit your open tasks around today's calendar");
    case "study":
      return tomorrow ? tr("Fit reviews, study blocks and breaks around tomorrow's calendar") : tr("Fit reviews, study blocks and breaks around today's calendar");
  }
}

export function TodayPanel({ context, store, focus, openModule, openConnections, eveningOverride }: TodayPanelProps) {
  const state = useStore(store);
  const planState = useStore(store.plan);
  const reviewState = useStore(store.review);
  const snapshot = useStore(context.snapshot);
  const timeZone = context.timeZone();
  const locale = currentLanguage();
  /* Re-checks the hour each minute so "Wrap up" takes the lead at 5 pm on its own. */
  const now = useClock(context, 60);
  const isEvening = eveningOverride ?? isWrapUpTime(now, timeZone);
  const isToday = state.viewing === "today";
  const canEdit = store.canEdit;
  const shared = isToday ? sharedTodayItems(snapshot, context.id, locale) : [];
  const hasPlannableWork = store.hasPlannableWork;
  const shownDay = store.shownDay;
  const shownProblem = store.shownProblem;

  useEffect(() => {
    store.refreshDay();
    store.upNext.setVisible(true);
    return () => {
      store.panelClosed();
      store.upNext.setVisible(false);
    };
  }, [store]);

  const perform = (action: UpNextAction) => {
    if (action === "openConnections") openConnections();
  };

  const unreadableTitle = state.viewing === "yesterday" ? tr("Couldn't read yesterday's list") : state.viewing === "tomorrow" ? tr("Couldn't read tomorrow's list") : tr("Couldn't read today's list");

  let content;
  if (reviewState.review !== undefined) {
    content = <DayReviewView store={store.review} locale={locale} />;
  } else if (planState.phase.kind !== "idle") {
    content = <DayPlanView plan={store.plan} locale={locale} timeZone={timeZone} openConnections={openConnections} />;
  } else {
    content = (
      <div className="planner-column">
        <PlannerHeader context={context} store={store} shared={shared} isEvening={isEvening} hasPlannableWork={hasPlannableWork} locale={locale} timeZone={timeZone} />
        <div className="planner-body">
          {shownProblem?.kind === "unreadable" ? (
            <PlannerMessage symbol="exclamationmark.triangle.fill" tint="var(--warning)" title={unreadableTitle} detail={tr("%@ is damaged, so it's left untouched.", shownProblem.fileName)} />
          ) : store.items.length === 0 && shared.length === 0 ? (
            <PlannerEmpty viewing={state.viewing} greeting={displayNameGreeting(state.displayName, now, timeZone)} />
          ) : (
            <PlannerList context={context} store={store} shared={shared} focus={focus} openModule={(id, action) => openModule(id, action ?? undefined)} />
          )}
        </div>
        {state.viewing === "yesterday" ? (
          <PlannerLeftoversBar leftovers={store.leftovers.length} items={store.items.length} done={shownDay.doneCount} moveToToday={() => store.moveToToday()} />
        ) : canEdit ? (
          <div className="planner-bottom">
            <PlannerAddField store={store} viewing={state.viewing} />
            {state.viewing === "tomorrow"
              ? store.hasPlannableTomorrow && (
                  <PlannerPillButton
                    title={viewedDayPlanTitle("tomorrow")}
                    symbol="sparkles"
                    isProminent={isEvening}
                    height={28}
                    help={planHelp(state.planSettings.planMode, "tomorrow")}
                    onClick={() => store.planTomorrow()}
                  />
                )
              : isEvening
                ? (
                    <PlannerPillButton
                      title={tr("Wrap up")}
                      symbol="moon.stars.fill"
                      isProminent
                      height={28}
                      help={tr("Review today and see what carries over to tomorrow")}
                      onClick={() => void store.wrapUp()}
                    />
                  )
                : hasPlannableWork && (
                    <PlannerPillButton title={tr("Plan my day")} symbol="sparkles" height={28} help={planHelp(state.planSettings.planMode, "today")} onClick={() => store.planMyDay()} />
                  )}
          </div>
        ) : null}
      </div>
    );
  }

  const showsSharedClock = state.focusClockOwner !== undefined && (!state.isFocusTabOn || focus.timer.runState.kind === "idle");
  return (
    <div className="planner-panel">
      <div className="planner-main">{content}</div>
      <div className="planner-side" style={{ width: SIDE_COLUMN_WIDTH }}>
        <UpNextCard store={store.upNext} upNextEvents={state.planSettings.upNextEvents} appName={context.edition.name} locale={locale} timeZone={timeZone} perform={perform} />
        {showsSharedClock && state.focusClockOwner !== undefined ? (
          <SharedFocusCard context={context} owner={state.focusClockOwner} open={(id) => openModule(id)} />
        ) : (
          <FocusCard context={context} actions={focus} items={state.day.items} />
        )}
      </div>
    </div>
  );
}

interface PlannerHeaderProps {
  readonly context: ModuleContext;
  readonly store: PlannerStore;
  readonly shared: ReturnType<typeof sharedTodayItems>;
  readonly isEvening: boolean;
  readonly hasPlannableWork: boolean;
  readonly locale: string;
  readonly timeZone: string;
}

/** Date and progress for the whole day. Shared goals such as Anki reviews count as items, so the ring and "N of M done" move when they finish too. */
function PlannerHeader({ context, store, shared, isEvening, hasPlannableWork, locale, timeZone }: PlannerHeaderProps) {
  const state = useStore(store);
  const isToday = state.viewing === "today";
  const shownDay = store.shownDay;
  const tally = new TodayTally(shownDay, shared);
  const canEdit = store.canEdit;
  /* Demo mode shows no dates, so store screenshots never carry one. */
  const styles = viewedDayHeaderDateStyles(state.viewing, !context.isDemo);
  const dayStart = dayKeyStart(shownDay.date, timeZone);
  const title = viewedDayTitle(state.viewing);
  const dateText = (style: Intl.DateTimeFormatOptions | undefined) => (style === undefined ? undefined : formatDate(dayStart, style, locale, timeZone));
  const planned = state.viewing === "tomorrow" && tally.doneCount === 0;
  const summary = planned ? tally.plannedSummary : tally.summary;
  const shortSummary = planned ? tally.plannedSummary : tally.shortSummary;
  const shownProblem = store.shownProblem;
  return (
    <div className="planner-header">
      <span className="planner-header-ring">
        <ProgressRing progress={tally.progress} size={16} lineWidth={2} />
      </span>
      <DayStepper viewing={state.viewing} show={(day) => store.show(day)}>
        {title !== undefined ? (
          <>
            <span className="planner-header-day">{title}</span>
            {dateText(styles[0]) !== undefined && <span className="planner-header-date">{dateText(styles[0])}</span>}
          </>
        ) : (
          <span className="planner-header-day">
            <TextThatFits candidates={styles.map(dateText).filter((text): text is string => text !== undefined)} />
          </span>
        )}
      </DayStepper>
      <span className="planner-header-spacer" />
      {shownProblem?.kind === "saveFailed" && (
        <Tooltip text={tr("The last change couldn't be written to disk")}>
          <span className="planner-warning">
            <Icon id="exclamationmark.triangle.fill" size={10} />
            <span>{tr("Not saved")}</span>
          </span>
        </Tooltip>
      )}
      <span className="planner-header-count">
        <TextThatFits candidates={[summary, shortSummary]} />
      </span>
      {shownDay.doneCount > 0 && canEdit && (
        <IconButton symbol="checkmark.circle.badge.xmark" size={20} help={tr("Clear completed tasks")} onClick={() => store.clearCompleted()} />
      )}
      {isToday &&
        canEdit &&
        (isEvening
          ? hasPlannableWork && (
              <IconButton
                symbol="sparkles"
                size={20}
                help={tr("Plan my day: %@", planHelp(state.planSettings.planMode, "today").toLocaleLowerCase(locale))}
                onClick={() => store.planMyDay()}
              />
            )
          : (
              <IconButton symbol="moon.stars" size={20} help={tr("Wrap up: review today and see what carries over")} onClick={() => void store.wrapUp()} />
            ))}
    </div>
  );
}

/** The fresh-day message while both lists are empty, which greets the user by name when they gave one. */
function PlannerEmpty({ viewing, greeting }: { viewing: PlannerViewedDay; greeting: string | undefined }) {
  switch (viewing) {
    case "yesterday":
      return <PlannerMessage symbol="clock.arrow.circlepath" tint="var(--secondary-text)" title={tr("Nothing listed yesterday")} detail={tr("Each day's list shows up here the day after.")} />;
    case "today":
      return <PlannerMessage symbol="checklist" tint="var(--accent)" title={greeting ?? tr("A fresh day")} detail={tr("Add a few things you want to get done today.")} />;
    case "tomorrow":
      return (
        <PlannerMessage symbol="sunrise.fill" tint="var(--accent)" title={tr("Plan tomorrow")} detail={tr("Add what you want to get done. Today's unfinished tasks join them in the morning.")} />
      );
  }
}

/** Port of PlannerAddField: the plus, a placeholder that shortens to fit, and the field itself. */
function PlannerAddField({ store, viewing }: { store: PlannerStore; viewing: PlannerViewedDay }) {
  const [text, setText] = useState("");
  const [focused, setFocused] = useState(false);
  const input = useRef<HTMLInputElement>(null);
  const onKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    /* The island's own Escape closes the panel; inside the field the first Esc clears the draft and the second leaves the field. */
    if (event.key === "Enter") {
      event.preventDefault();
      if (store.add(text)) setText("");
    } else if (event.key === "Escape") {
      event.stopPropagation();
      event.preventDefault();
      if (text === "") input.current?.blur();
      else setText("");
    }
  };
  const candidates = viewing === "tomorrow" ? [tr("Add a task for tomorrow…"), tr("Add a task…"), tr("Add…")] : [tr("Add a task…"), tr("Add…")];
  return (
    <Tooltip text={tr("Type a task and press Return to add it; Esc clears")}>
      <div className="planner-add" data-focused={focused} onClick={() => input.current?.focus()}>
        <span className="planner-add-plus">
          <Icon id="plus" size={11} />
        </span>
        <span className="planner-add-field">
          {text === "" && (
            <span className="planner-add-placeholder">
              <TextThatFits candidates={candidates} />
            </span>
          )}
          <input
            ref={input}
            className="planner-add-input kit-user-text"
            value={text}
            aria-label={candidates[0] ?? ""}
            onChange={(event) => setText(event.target.value)}
            onFocus={() => setFocused(true)}
            onBlur={() => setFocused(false)}
            onKeyDown={onKeyDown}
          />
        </span>
      </div>
    </Tooltip>
  );
}
