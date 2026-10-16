/*
 * Port of SchedulePanel.swift: a header with the Day/Week switch, the date
 * (which steps to yesterday and tomorrow in the Day view) and the free
 * time, then either the day's timeline (events, planned blocks, now line)
 * with a line under it for what is on now or the block tapped, or the
 * week's seven days stacked on the same clock hours. Plan puts a proposal
 * for the day (or, from the Week view, the week) on the timeline, which the
 * strip under it adds or skips.
 */

import { useEffect, useLayoutEffect, useRef, useState, type CSSProperties } from "react";
import type { ModuleContext } from "../../app/context";
import { useStore } from "../../app/useStore";
import { dayRange } from "../../core/formatting/dateRangeFormat";
import { currentLanguage, tr } from "../../core/localization/tr";
import type { MeetingLink } from "../../core/planner/meetingLink";
import { meetingProviderName } from "../../core/planner/meetingLink";
import { viewedDayTitle, type PlannerViewedDay } from "../../core/planner/plannerViewedDay";
import { upNextEmptyState, type UpNextSituation } from "../../core/planner/upNextEmptyState";
import { eventStartTime } from "../../core/planner/upcomingEvent";
import {
  scheduleDaySummary,
  scheduleDuration,
  scheduleItemMinutes,
  scheduleItemTitle,
  scheduleRange,
  scheduleStatusText,
  weekDayEventCount,
  weekDayPlannedCount,
  weekDayPosition,
  type PlacedScheduleItem,
  type ScheduleDayLayout,
  type ScheduleItem,
  type ScheduleStatus,
  type ScheduleWeekDay,
  type ScheduleWeekLayout,
} from "../../core/schedule/scheduleDay";
import type { ScheduleDraft } from "../../core/schedule/scheduleDraft";
import { clockTime } from "../../core/schedule/schedulePlanner";
import type { Instant } from "../../core/time";
import { Card } from "../../ui/kit/Card";
import { Icon } from "../../ui/kit/Icon";
import { IconButton } from "../../ui/kit/IconButton";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { StatusMessage } from "../../ui/kit/StatusMessage";
import { TextThatFits } from "../../ui/kit/TextThatFits";
import { Spacing } from "../../ui/kit/tokens";
import { Tooltip } from "../../ui/kit/Tooltip";
import { DayStepper } from "../planner/DayStepper";
import { formatDate, hourLabel } from "../planner/plannerFormat";
import { PlannerPillButton } from "../planner/plannerControls";
import type { ScheduleMode, ScheduleStore } from "./scheduleStore";

export interface SchedulePanelProps {
  readonly context: ModuleContext;
  readonly store: ScheduleStore;
  readonly openConnections: () => void;
}

/** A measured box, so the timeline can place items in pixels. */
function useSize(): [React.RefObject<HTMLDivElement | null>, { width: number; height: number }] {
  const ref = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ width: 0, height: 0 });
  useLayoutEffect(() => {
    const element = ref.current;
    if (!element) return;
    const measure = () => {
      const next = { width: element.clientWidth, height: element.clientHeight };
      setSize((last) => (last.width === next.width && last.height === next.height ? last : next));
    };
    measure();
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);
  return [ref, size];
}

function itemColor(item: ScheduleItem): string {
  if (item.kind !== "event") return "var(--accent)";
  const color = item.calendarColor;
  if (color === undefined) return "var(--secondary-text)";
  const channel = (value: number) => Math.round(Math.min(1, Math.max(0, value)) * 255);
  return `rgb(${channel(color.red)} ${channel(color.green)} ${channel(color.blue)})`;
}

export function SchedulePanel({ context, store, openConnections }: SchedulePanelProps) {
  const state = useStore(store);
  const locale = currentLanguage();
  const timeZone = context.timeZone();
  useEffect(() => {
    store.setVisible(true);
    return () => store.setVisible(false);
  }, [store]);
  const situation = store.emptySituation;
  const layout = store.dayLayout;
  const selected = store.selectedItem;
  const draft = state.draft;
  const showsInlinePlan = state.mode === "week" && situation === undefined && draft !== undefined;
  return (
    <div className="schedule-panel">
      {showsInlinePlan ? (
        <SchedulePlanStrip store={store} draft={draft} selected={selected?.kind === "proposed" ? selected : undefined} locale={locale} timeZone={timeZone} isInline />
      ) : (
        <ScheduleHeader store={store} layout={layout} locale={locale} timeZone={timeZone} />
      )}
      {situation !== undefined ? (
        <ScheduleAccessMessage situation={situation} appName={context.edition.name} openConnections={openConnections} />
      ) : state.mode === "week" ? (
        <ScheduleWeek layout={store.weekLayout} now={state.now} selectedID={state.selectedID} isDrafting={draft !== undefined} select={(id) => store.select(id)} locale={locale} timeZone={timeZone} />
      ) : (
        <>
          <ScheduleTimeline
            layout={layout}
            now={state.viewing === "today" ? state.now : undefined}
            selectedID={state.selectedID}
            isDrafting={draft !== undefined}
            select={(id) => store.select(id)}
            locale={locale}
            timeZone={timeZone}
          />
          {draft !== undefined && (selected === undefined || selected.kind === "proposed") ? (
            <SchedulePlanStrip store={store} draft={draft} selected={selected} locale={locale} timeZone={timeZone} />
          ) : (
            <ScheduleDetailStrip
              layout={layout}
              now={state.now}
              viewing={state.viewing}
              selected={selected}
              appName={context.edition.name}
              locale={locale}
              timeZone={timeZone}
              join={(link) => store.join(link)}
              close={() => store.select(undefined)}
            />
          )}
        </>
      )}
    </div>
  );
}

/** The Day/Week switch and the date, then what's free: the all-day event and free time left in the day shown, or the free time across the week. */
function ScheduleHeader({ store, layout, locale, timeZone }: { store: ScheduleStore; layout: ScheduleDayLayout; locale: string; timeZone: string }) {
  const state = useStore(store);
  const situation = store.emptySituation;
  const isDay = state.mode === "day";
  const now = state.now;
  const shownDay = store.shownDay;
  const title = isDay ? viewedDayTitle(state.viewing) : undefined;
  const dateText =
    state.mode === "week"
      ? dayRange(now, now + 6 * 86400, locale, timeZone)
      : formatDate(shownDay, { weekday: "short", month: "short", day: "numeric" }, locale, timeZone);
  const shortDateText = state.mode === "week" ? formatDate(now, { month: "short", day: "numeric" }, locale, timeZone) : state.viewing === "today" ? formatDate(shownDay, { weekday: "short", day: "numeric" }, locale, timeZone) : undefined;
  const dateLabel = (
    <span className="schedule-date">
      {title !== undefined && <span className="schedule-date-title">{title}</span>}
      <span className="schedule-date-text">
        <TextThatFits candidates={shortDateText === undefined ? [dateText] : [dateText, shortDateText]} />
      </span>
    </span>
  );
  const allDay = layout.allDay[0];
  const freeTime = (minutes: number, free: string, none: string, help: string) => (
    <Tooltip text={help}>
      <span className="schedule-free" data-free={minutes > 0}>
        {minutes > 0 ? free : none}
      </span>
    </Tooltip>
  );
  const weekFree = state.mode === "week" ? store.weekLayout.freeMinutes : 0;
  return (
    <div className="schedule-header">
      <ScheduleModePicker selection={state.mode} select={(mode) => store.showMode(mode)} />
      <div className="schedule-header-date">
        {isDay && situation === undefined ? (
          <DayStepper viewing={state.viewing} yesterdayHelp={tr("Show yesterday's calendar")} tomorrowHelp={tr("Show tomorrow's calendar")} show={(day) => store.show(day)}>
            {dateLabel}
          </DayStepper>
        ) : (
          dateLabel
        )}
      </div>
      <span className="schedule-header-spacer" />
      {isDay && situation === undefined && allDay !== undefined && (
        <Tooltip text={tr("All day: %@", scheduleItemTitle(allDay))}>
          <span className="schedule-allday">
            <Icon id="sun.max" size={11} />
            <span>{scheduleItemTitle(allDay)}</span>
          </span>
        </Tooltip>
      )}
      {situation === undefined &&
        (isDay
          ? state.viewing !== "yesterday" && (
              <>
                {freeTime(
                  layout.freeMinutes,
                  tr("%@ free", scheduleDuration(layout.freeMinutes)),
                  state.viewing === "today" ? tr("No free time left") : tr("No free time"),
                  state.viewing === "today"
                    ? tr("Free time left in your working day, with a buffer around each event")
                    : tr("Free time in tomorrow's working day, with a buffer around each event"),
                )}
                {state.draft === undefined && layout.freeMinutes > 0 && (
                  <PlannerPillButton
                    title={tr("Plan")}
                    symbol="wand.and.stars"
                    isProminent
                    help={state.viewing === "today" ? tr("Fill today's free time with your open tasks and reviews. Planned on this PC, nothing is added until you say so") : tr("Fill tomorrow's free time with your open tasks and reviews. Planned on this PC, nothing is added until you say so")}
                    onClick={() => store.planDay()}
                  />
                )}
              </>
            )
          : (
              <>
                {freeTime(weekFree, tr("%@ free this week", scheduleDuration(weekFree)), tr("No free time this week"), tr("Free working time over the next seven days, with a buffer around each event"))}
                {state.draft === undefined && weekFree > 0 && (
                  <PlannerPillButton
                    title={tr("Plan")}
                    symbol="wand.and.stars"
                    isProminent
                    help={tr("Spread your open tasks and reviews over the week's free time. Planned on this PC, nothing is added until you say so")}
                    onClick={() => store.planWeek()}
                  />
                )}
              </>
            ))}
    </div>
  );
}

/** Two capsule pills, Day and Week; the selected one wears the accent. */
function ScheduleModePicker({ selection, select }: { selection: ScheduleMode; select: (mode: ScheduleMode) => void }) {
  const modes: ScheduleMode[] = ["day", "week"];
  return (
    <div className="schedule-modes" role="tablist">
      {modes.map((mode) => (
        <Tooltip key={mode} text={mode === "day" ? tr("Today on a timeline") : tr("The next seven days at a glance")}>
          <button type="button" role="tab" aria-selected={selection === mode} className="schedule-mode" data-selected={selection === mode} onClick={() => select(mode)}>
            {mode === "day" ? tr("Day") : tr("Week")}
          </button>
        </Tooltip>
      ))}
    </div>
  );
}

const LABEL_HEIGHT = 16;
const LANE_GAP = 2;
/** Below this a title would show only a few letters, so it's left to the tooltip and the strip under the timeline. */
const MINIMUM_LABEL_WIDTH = 24;
const STRIPE_WIDTH = 2.5;

interface TimelineProps {
  readonly layout: ScheduleDayLayout;
  /** Undefined on a day other than today: no now line and nothing faded as past. */
  readonly now: Instant | undefined;
  readonly selectedID: string | undefined;
  /** While a plan is on offer, everything else steps back. */
  readonly isDrafting: boolean;
  readonly select: (id: string) => void;
  readonly locale: string;
  readonly timeZone: string;
}

function blockOpacity(isPast: boolean, isSelected: boolean, isDimmed: boolean): number {
  return isPast && !isSelected ? 0.5 : isDimmed ? 0.55 : 1;
}

/** Hour marks across the top and the day's items below them, stacked in rows where they overlap, with a line at the current time. */
function ScheduleTimeline({ layout, now, selectedID, isDrafting, select, locale, timeZone }: TimelineProps) {
  const [ref, size] = useSize();
  const width = size.width;
  const trackHeight = Math.max(size.height - LABEL_HEIGHT, 24);
  const hourWidth = width / Math.max(layout.hours.length - 1, 1);
  /* Every hour when there's room for its label, else every other one. */
  const labelEvery = hourWidth >= 34 ? 1 : 2;
  const nowX = now === undefined ? undefined : layout.position(now);
  const isPast = (item: ScheduleItem) => (now === undefined ? false : item.end <= now);
  const laneHeight = (placed: PlacedScheduleItem) => (trackHeight - (placed.lanes - 1) * LANE_GAP) / placed.lanes;
  const laneY = (placed: PlacedScheduleItem) => LABEL_HEIGHT + placed.lane * (laneHeight(placed) + LANE_GAP);
  return (
    <Card padding={Spacing.s} className="schedule-timeline-card">
      <div ref={ref} className="schedule-timeline">
        {width > 0 && (
          <>
            {nowX !== undefined && <div className="schedule-past" style={{ width: width * nowX, top: LABEL_HEIGHT, height: trackHeight }} />}
            {layout.hours.map((hour, index) => {
              const x = width * (layout.position(hour) ?? 1);
              return (
                <span key={index}>
                  <div className="schedule-gridline" style={{ left: x, top: LABEL_HEIGHT, height: trackHeight }} />
                  {index % labelEvery === 0 && index < layout.hours.length - 1 && (
                    <div className="schedule-hour" style={{ left: x + 3 }}>
                      {hourLabel(hour, locale, timeZone)}
                    </div>
                  )}
                </span>
              );
            })}
            {layout.placed.map((placed) => (
              <ScheduleBlock
                key={placed.item.id}
                item={placed.item}
                isPast={isPast(placed.item)}
                isSelected={placed.item.id === selectedID}
                isDimmed={isDrafting && placed.item.kind !== "proposed"}
                style={{ left: width * placed.x + 0.5, top: laneY(placed), width: Math.max(width * placed.width - 1, 3), height: laneHeight(placed) }}
                onClick={() => select(placed.item.id)}
                locale={locale}
                timeZone={timeZone}
              />
            ))}
            {/* Under the labels, so the line never cuts through a title. */}
            {nowX !== undefined && (
              <div className="schedule-now" style={{ left: width * nowX - 3, top: LABEL_HEIGHT - 4, height: trackHeight + 4 }}>
                <span className="schedule-now-dot" />
                <span className="schedule-now-line" />
              </div>
            )}
            {layout.placed.map((placed) => {
              const inset = STRIPE_WIDTH + Spacing.xs;
              const labelWidth = width * placed.labelWidth - inset - Spacing.xs;
              if (labelWidth < MINIMUM_LABEL_WIDTH) return null;
              const height = laneHeight(placed);
              return (
                <div
                  key={`label-${placed.item.id}`}
                  className="schedule-block-label"
                  data-tall={height >= 20}
                  style={{ left: width * placed.x + 0.5 + inset, top: laneY(placed), width: labelWidth, height, opacity: blockOpacity(isPast(placed.item), placed.item.id === selectedID, isDrafting && placed.item.kind !== "proposed") }}
                >
                  <span className="schedule-block-title" data-lines={height >= 48 && labelWidth >= 40 ? 2 : 1}>
                    {scheduleItemTitle(placed.item)}
                  </span>
                  {height >= 34 && width * placed.width >= 48 && <span className="schedule-block-time">{eventStartTime(placed.item.start, locale, timeZone)}</span>}
                </div>
              );
            })}
          </>
        )}
      </div>
    </Card>
  );
}

interface ScheduleBlockProps {
  readonly item: ScheduleItem;
  readonly isPast: boolean;
  readonly isSelected: boolean;
  readonly isDimmed: boolean;
  readonly style: CSSProperties;
  readonly onClick: () => void;
  readonly locale: string;
  readonly timeZone: string;
}

/** One event or planned block. Events take their calendar's color; planned blocks are outlined in the accent, and proposed ones are filled with it more strongly. */
function ScheduleBlock({ item, isPast, isSelected, isDimmed, style, onClick, locale, timeZone }: ScheduleBlockProps) {
  const text = `${scheduleItemTitle(item)}, ${scheduleRange(item.start, item.end, locale, timeZone)}`;
  const help = item.kind === "proposed" ? tr("Proposed: %@. Click to add or skip it", text) : text;
  return (
    <Tooltip text={help}>
      <button
        type="button"
        className="schedule-block"
        data-kind={item.kind}
        data-selected={isSelected}
        aria-label={help}
        style={{ ...style, "--block-color": itemColor(item), opacity: blockOpacity(isPast, isSelected, isDimmed) } as CSSProperties}
        onClick={onClick}
      >
        <span className="schedule-block-stripe" />
      </button>
    </Tooltip>
  );
}

const WEEK_LABEL_WIDTH = 48;
const WEEK_FREE_WIDTH = 64;
const WEEK_AXIS_HEIGHT = 14;

interface WeekProps {
  readonly layout: ScheduleWeekLayout;
  readonly now: Instant;
  readonly selectedID: string | undefined;
  readonly isDrafting: boolean;
  readonly select: (id: string) => void;
  readonly locale: string;
  readonly timeZone: string;
}

/** Seven rows, today first, on shared clock hours: each day's busy times in its calendars' colors, planned blocks in the accent, and its free time at the end of the row. */
function ScheduleWeek({ layout, now, selectedID, isDrafting, select, locale, timeZone }: WeekProps) {
  const [ref, size] = useSize();
  const rows = Math.max(layout.days.length, 1);
  const rowGap = 2;
  const rowHeight = Math.max((size.height - WEEK_AXIS_HEIGHT - rowGap * rows) / rows, 8);
  const marks = layout.hourMarks;
  const trackWidth = Math.max(size.width - WEEK_LABEL_WIDTH - WEEK_FREE_WIDTH - 2 * Spacing.s, 1);
  const hourWidth = trackWidth / Math.max(marks.length - 1, 1);
  const every = hourWidth >= 44 ? 1 : hourWidth >= 22 ? 2 : 3;
  const innerMarks = marks.slice(1, -1).map((minute) => layout.positionOfMinute(minute));
  return (
    <Card padding={Spacing.s} className="schedule-week-card">
      <div ref={ref} className="schedule-week">
        <div className="schedule-week-axis" style={{ height: WEEK_AXIS_HEIGHT }}>
          <span style={{ width: WEEK_LABEL_WIDTH, flex: "none" }} />
          <div className="schedule-week-axis-track">
            {marks.map((minute, index) =>
              index % every === 0 && index < marks.length - 1 ? (
                <span key={minute} className="schedule-week-axis-label" style={{ left: `${layout.positionOfMinute(minute) * 100}%` }}>
                  {hourLabel(clockTime(minute, now, timeZone), locale, timeZone)}
                </span>
              ) : null,
            )}
          </div>
          <span style={{ width: WEEK_FREE_WIDTH, flex: "none" }} />
        </div>
        {size.height > 0 &&
          layout.days.map((day) => (
            <ScheduleWeekRow key={day.date} day={day} now={now} hourMarks={innerMarks} height={rowHeight} selectedID={selectedID} isDrafting={isDrafting} select={select} locale={locale} timeZone={timeZone} />
          ))}
      </div>
    </Card>
  );
}

interface WeekRowProps {
  readonly day: ScheduleWeekDay;
  readonly now: Instant;
  readonly hourMarks: readonly number[];
  readonly height: number;
  readonly selectedID: string | undefined;
  readonly isDrafting: boolean;
  readonly select: (id: string) => void;
  readonly locale: string;
  readonly timeZone: string;
}

/** One day of the week: its name, a track of its busy times, its free time. */
function ScheduleWeekRow({ day, now, hourMarks, height, selectedID, isDrafting, select, locale, timeZone }: WeekRowProps) {
  const nowX = day.isToday ? weekDayPosition(day, now) : undefined;
  const events = weekDayEventCount(day);
  const planned = weekDayPlannedCount(day);
  const parts: string[] = [events === 0 ? tr("No events") : tr("%lld events", events)];
  if (planned > 0) parts.push(tr("%lld planned blocks", planned));
  const allDay = day.allDay[0];
  if (allDay !== undefined) parts.push(tr("all day: %@", scheduleItemTitle(allDay)));
  parts.push(day.freeMinutes > 0 ? tr("%@ free", scheduleDuration(day.freeMinutes)) : tr("no free time"));
  const summary = `${formatDate(day.date, { weekday: "long", month: "short", day: "numeric" }, locale, timeZone)}: ${parts.join(", ")}`;
  return (
    <Tooltip text={summary}>
      <div className="schedule-week-row" style={{ height }}>
        <span className="schedule-week-day" data-today={day.isToday} style={{ width: WEEK_LABEL_WIDTH }}>
          {day.isToday ? tr("Today") : formatDate(day.date, { weekday: "short", day: "numeric" }, locale, timeZone)}
        </span>
        <div className="schedule-week-track">
          {hourMarks.map((mark) => (
            <span key={mark} className="schedule-week-mark" style={{ left: `${mark * 100}%` }} />
          ))}
          {nowX !== undefined && <span className="schedule-week-past" style={{ width: `${nowX * 100}%` }} />}
          {day.placed.map((placed) => {
            const laneHeight = (height - (placed.lanes - 1)) / placed.lanes;
            const item = placed.item;
            const isPast = item.end <= now;
            const isSelected = item.id === selectedID;
            const isDimmed = isDrafting && item.kind !== "proposed";
            const style = {
              left: `calc(${placed.x * 100}% + 0.5px)`,
              width: `max(calc(${placed.width * 100}% - 1px), 2px)`,
              top: placed.lane * (laneHeight + 1),
              height: laneHeight,
              "--block-color": itemColor(item),
              opacity: isPast ? 0.45 : isDimmed ? 0.55 : 1,
            } as CSSProperties;
            if (item.kind === "proposed") {
              const help = tr("Proposed: %@. Click to add or skip it", `${scheduleItemTitle(item)}, ${scheduleRange(item.start, item.end, locale, timeZone)}`);
              return (
                <Tooltip key={item.id} text={help}>
                  <button type="button" className="schedule-week-block" data-kind={item.kind} data-selected={isSelected} aria-label={help} style={style} onClick={() => select(item.id)} />
                </Tooltip>
              );
            }
            return <span key={item.id} className="schedule-week-block" data-kind={item.kind} style={style} />;
          })}
          {nowX !== undefined && <span className="schedule-week-now" style={{ left: `calc(${nowX * 100}% - 0.75px)` }} />}
        </div>
        <span className="schedule-week-free" data-free={day.freeMinutes > 0} style={{ width: WEEK_FREE_WIDTH }}>
          {day.freeMinutes > 0 ? scheduleDuration(day.freeMinutes) : tr("Full")}
        </span>
      </div>
    </Tooltip>
  );
}

interface DetailStripProps {
  readonly layout: ScheduleDayLayout;
  readonly now: Instant;
  readonly viewing: PlannerViewedDay;
  readonly selected: ScheduleItem | undefined;
  readonly appName: string;
  readonly locale: string;
  readonly timeZone: string;
  readonly join: (link: MeetingLink) => void;
  readonly close: () => void;
}

function statusSymbol(status: ScheduleStatus): string {
  switch (status.kind) {
    case "busy":
      return "record.circle";
    case "free":
      return "leaf";
    case "dayOver":
      return "moon.stars";
  }
}

/** Under the timeline: the tapped block's details, or what is on now. */
function ScheduleDetailStrip({ layout, now, viewing, selected, appName, locale, timeZone, join, close }: DetailStripProps) {
  if (selected !== undefined) {
    const parts = [scheduleRange(selected.start, selected.end, locale, timeZone), scheduleDuration(scheduleItemMinutes(selected))];
    if (selected.kind !== "event") parts.push(selected.reason ?? tr("Planned with %@", appName));
    const link = selected.meetingLink;
    return (
      <Card padding={Spacing.s} className="schedule-strip">
        <span className="schedule-strip-bar" style={{ background: itemColor(selected) }} />
        <div className="schedule-strip-text">
          <MarqueeText text={scheduleItemTitle(selected)} className="schedule-strip-title" />
          <MarqueeText text={parts.join(", ")} className="schedule-strip-detail" />
        </div>
        {link !== undefined && <PlannerPillButton title={tr("Join")} symbol="video.fill" help={tr("Join %@ call", meetingProviderName(link.provider))} onClick={() => join(link)} />}
        <IconButton symbol="xmark" size={22} help={tr("Close details")} onClick={close} />
      </Card>
    );
  }
  const status = layout.status(now);
  const symbol = viewing === "yesterday" ? "clock.arrow.circlepath" : viewing === "tomorrow" ? "sunrise.fill" : statusSymbol(status);
  const text = viewing === "today" ? scheduleStatusText(status, now, locale, timeZone) : scheduleDaySummary(layout, viewing === "yesterday", locale, timeZone);
  return (
    <Card padding={Spacing.s} className="schedule-strip">
      <span className="schedule-strip-icon">
        <Icon id={symbol} size={12} />
      </span>
      <MarqueeText text={text} className="schedule-strip-status" />
      {layout.placed.length === 0 && viewing === "today" && <span className="schedule-strip-note">{tr("Nothing on your calendar today")}</span>}
    </Card>
  );
}

interface PlanStripProps {
  readonly store: ScheduleStore;
  readonly draft: ScheduleDraft;
  readonly selected: ScheduleItem | undefined;
  readonly locale: string;
  readonly timeZone: string;
  /** Drawn in the header row, without a card of its own (the Week view). */
  readonly isInline?: boolean;
}

/** Under the timeline while a plan is on offer: the selected proposed block with its reason, or what the plan offers in all, with the buttons that add or skip it. */
function SchedulePlanStrip({ store, draft, selected, locale, timeZone, isInline = false }: PlanStripProps) {
  const state = useStore(store);
  const failureOr = (text: string) => (state.writeFailed ? tr("Couldn't add to Today. Try again") : text);
  let content;
  if (selected !== undefined) {
    const sameDay = formatDate(selected.start, { year: "numeric", month: "numeric", day: "numeric" }, "en", timeZone) === formatDate(state.now, { year: "numeric", month: "numeric", day: "numeric" }, "en", timeZone);
    const parts = [
      ...(sameDay ? [] : [formatDate(selected.start, { weekday: "short", day: "numeric" }, locale, timeZone)]),
      scheduleRange(selected.start, selected.end, locale, timeZone),
      scheduleDuration(scheduleItemMinutes(selected)),
      ...(selected.reason === undefined ? [] : [selected.reason]),
    ];
    content = (
      <>
        <span className="schedule-strip-bar" style={{ background: "var(--accent)" }} />
        <div className="schedule-strip-text">
          <MarqueeText text={scheduleItemTitle(selected)} className="schedule-strip-title" />
          <MarqueeText text={failureOr(parts.join(", "))} className="schedule-strip-detail" style={state.writeFailed ? { color: "var(--danger)" } : undefined} />
        </div>
        <PlannerPillButton title={tr("Skip")} help={tr("Leave this block out of the plan")} onClick={() => store.skip(selected.id)} />
        <PlannerPillButton title={tr("Add")} symbol="plus" isProminent help={tr("Add this block to Today")} onClick={() => void store.add(selected.id)} />
      </>
    );
  } else {
    const assistant = state.assistant;
    const overview = state.isRefining
      ? tr("%@ is looking over this plan...", assistant)
      : state.refineFailed
        ? tr("%@ couldn't refine this plan", assistant)
        : draft.refinement === "changed"
          ? tr("Refined with %@: %@", assistant, draft.summary)
          : draft.refinement === "unchanged"
            ? tr("%@ suggests no changes", assistant)
            : draft.summary;
    content = (
      <>
        <span className="schedule-strip-icon">
          <Icon id="wand.and.stars" size={12} />
        </span>
        <MarqueeText text={failureOr(overview)} help={draft.unplacedDetail ?? tr("Click a block to add or skip just that one")} className="schedule-strip-status" style={state.writeFailed || state.refineFailed ? { color: "var(--danger)" } : undefined} />
        {draft.isEmpty ? (
          <PlannerPillButton title={tr("OK")} help={tr("Close the plan")} onClick={() => store.discardPlan()} />
        ) : (
          <>
            {(store.canRefine || state.isRefining) && (
              <PlannerPillButton title={tr("Refine")} symbol="wand.and.stars" disabled={state.isRefining} help={tr("Refine with %@: suggest a better order or lengths for this plan", assistant)} onClick={() => store.refine()} />
            )}
            <PlannerPillButton title={tr("Discard")} help={tr("Close the plan without adding anything")} onClick={() => store.discardPlan()} />
            <PlannerPillButton title={tr("Add all")} symbol="plus" isProminent disabled={state.isRefining} help={tr("Add every proposed block to Today")} onClick={() => void store.add()} />
          </>
        )}
      </>
    );
  }
  if (isInline) return <div className="schedule-strip schedule-strip-inline">{content}</div>;
  return (
    <Card padding={Spacing.s} className="schedule-strip">
      {content}
    </Card>
  );
}

/** Why there's no timeline yet (no calendar feed), with the one action that fixes it. */
function ScheduleAccessMessage({ situation, appName, openConnections }: { situation: UpNextSituation; appName: string; openConnections: () => void }) {
  const state = upNextEmptyState(situation, "events", appName);
  return (
    <Card className="schedule-access">
      <StatusMessage
        symbol={state.symbol}
        title={tr("See your day at a glance")}
        message={tr("Today's events and the free time between them. Add a calendar link in Settings to see them here.")}
        actions={<PlannerPillButton title={state.actionTitle} isProminent height={24} help={state.actionHelp} onClick={openConnections} />}
      />
    </Card>
  );
}
