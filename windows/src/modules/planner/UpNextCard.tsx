/*
 * Port of UpNextCard.swift: the Today panel's "Up next" card, the next few
 * events today with a timing badge and a Join button for video calls, or a
 * compact state explaining why there's nothing to show. While the
 * checklist shows yesterday or tomorrow, it lists that day's events with
 * their times and lengths instead.
 */

import type { CSSProperties } from "react";
import { useStore } from "../../app/useStore";
import { tr } from "../../core/localization/tr";
import type { MeetingLink } from "../../core/planner/meetingLink";
import { meetingProviderName } from "../../core/planner/meetingLink";
import { viewedDayCalendarTitle } from "../../core/planner/plannerViewedDay";
import { upNextEmptyState, type UpNextAction, type UpNextEmptyState } from "../../core/planner/upNextEmptyState";
import { eventBadge, eventLength, eventStartTime, eventTiming, eventTitle, type UpcomingEvent } from "../../core/planner/upcomingEvent";
import type { Instant } from "../../core/time";
import { Card } from "../../ui/kit/Card";
import { Icon } from "../../ui/kit/Icon";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { RowsThatFit } from "../../ui/kit/RowsThatFit";
import { Spacing } from "../../ui/kit/tokens";
import { Tooltip } from "../../ui/kit/Tooltip";
import { PlannerPillButton } from "./plannerControls";
import type { UpNextStore } from "./upNextStore";

export interface UpNextCardProps {
  readonly store: UpNextStore;
  /** The kit's name for what the calendar holds (`TodayPlanSettings.upNextEvents`). */
  readonly upNextEvents: string;
  readonly appName: string;
  readonly locale: string;
  readonly timeZone: string;
  readonly perform: (action: UpNextAction) => void;
}

export function UpNextCard({ store, upNextEvents, appName, locale, timeZone, perform }: UpNextCardProps) {
  const state = useStore(store);
  const situation = store.emptySituation;
  const events = store.shownEvents;
  return (
    <Card padding={Spacing.s} className="upnext-card">
      <div className="upnext-caption">{viewedDayCalendarTitle(state.viewing)}</div>
      {situation !== undefined ? (
        <UpNextMessage state={upNextEmptyState(situation, upNextEvents, appName)} perform={perform} />
      ) : (
        <RowsThatFit
          data={events}
          keyOf={(event) => event.id}
          className="upnext-rows"
          row={(event) => (
            <UpNextRow event={event} now={state.viewing === "today" ? state.now : undefined} locale={locale} timeZone={timeZone} join={(link) => store.join(link)} />
          )}
        />
      )}
    </Card>
  );
}

export interface UpNextRowProps {
  readonly event: UpcomingEvent;
  /** Undefined on another day: the badge gives the event's length and there's no Join. */
  readonly now: Instant | undefined;
  readonly locale: string;
  readonly timeZone: string;
  readonly join: (link: MeetingLink) => void;
}

function eventColor(event: UpcomingEvent): string {
  const color = event.calendarColor;
  if (color === undefined) return "var(--accent)";
  const channel = (value: number) => Math.round(Math.min(1, Math.max(0, value)) * 255);
  return `rgb(${channel(color.red)} ${channel(color.green)} ${channel(color.blue)})`;
}

/** One event: color dot and title, then start time and badge, with a Join button on the right when the event has a video-call link. */
export function UpNextRow({ event, now, locale, timeZone, join }: UpNextRowProps) {
  const timing = now === undefined ? undefined : eventTiming(event, now);
  const title = eventTitle(event);
  const start = eventStartTime(event.start, locale, timeZone);
  const link = event.meetingLink;
  return (
    <div className="upnext-row" title={`${title}, ${start}`}>
      <span className="upnext-dot" style={{ background: eventColor(event) } as CSSProperties} />
      <div className="upnext-text">
        <MarqueeText text={title} className="upnext-title" />
        <div className="upnext-meta">
          <span className="upnext-time">{start}</span>
          <span className="upnext-badge" data-live={timing?.kind === "now"}>
            {timing === undefined ? eventLength(event) : eventBadge(timing)}
          </span>
        </div>
      </div>
      {timing !== undefined && link !== undefined && (
        <Tooltip text={tr("Join %@ call", meetingProviderName(link.provider))}>
          <button type="button" className="upnext-join" data-live={timing.kind === "now"} aria-label={tr("Join %@ call", meetingProviderName(link.provider))} onClick={() => join(link)}>
            <Icon id="video.fill" size={10} />
          </button>
        </Tooltip>
      )}
    </div>
  );
}

/** Icon, title, detail, and an optional action, sized for the narrow card. */
function UpNextMessage({ state, perform }: { state: UpNextEmptyState; perform: (action: UpNextAction) => void }) {
  const action = state.action;
  return (
    <div className="upnext-message">
      <div className="upnext-message-head">
        <span className="upnext-message-icon">
          <Icon id={state.symbol} size={13} />
        </span>
        <MarqueeText text={state.title} className="upnext-message-title" />
      </div>
      <div className="upnext-message-detail" title={state.detail}>
        {state.detail}
      </div>
      {action !== undefined && (
        <div className="upnext-message-action">
          <PlannerPillButton title={state.actionTitle} help={state.actionHelp} onClick={() => perform(action)} />
        </div>
      )}
    </div>
  );
}
