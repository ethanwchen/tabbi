/*
 * Port of TodayCalendarSetupView.swift for Windows: onboarding's calendar
 * step. What Today does with the calendar, the way to connect one (a
 * calendar link added in Settings > Connections, since Windows has no
 * calendar permission to ask for), and beside it the day as Up next will
 * show it. Before a feed is added it shows the kit's sample day, marked as
 * an example, so the step explains itself.
 */

import type { ModuleContext } from "../../app/context";
import { useStore } from "../../app/useStore";
import { currentLanguage, tr } from "../../core/localization/tr";
import { sampleEvents } from "../../core/planner/plannerSampleData";
import { localizedUpNextEvents, upNextEmptyState } from "../../core/planner/upNextEmptyState";
import { upNext } from "../../core/planner/upcomingEvent";
import { Card } from "../../ui/kit/Card";
import { Icon } from "../../ui/kit/Icon";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { Spacing } from "../../ui/kit/tokens";
import { Tooltip } from "../../ui/kit/Tooltip";
import { PlannerPillButton } from "./plannerControls";
import type { PlannerStore } from "./plannerStore";
import { UpNextRow } from "./UpNextCard";
import { useEffect } from "react";

export interface TodayCalendarSetupViewProps {
  readonly context: ModuleContext;
  readonly store: PlannerStore;
  readonly openConnections: () => void;
}

export function TodayCalendarSetupView({ context, store, openConnections }: TodayCalendarSetupViewProps) {
  const upNextStore = store.upNext;
  const state = useStore(upNextStore);
  const settings = useStore(store, (planner) => planner.planSettings);
  const locale = currentLanguage();
  const timeZone = context.timeZone();
  /* Visible like the panel, so the feeds and events are read fresh. */
  useEffect(() => {
    upNextStore.setVisible(true);
    return () => upNextStore.setVisible(false);
  }, [upNextStore]);
  const connected = state.hasSubscriptions;
  const situation = connected ? upNextStore.emptySituation : undefined;
  const events = connected ? state.events : upNext(sampleEvents(state.now, settings.sampleDay), state.now);
  return (
    <div className="calendar-setup">
      <Card className="calendar-setup-card" style={{ width: 252 }}>
        <div className="calendar-setup-head">
          <span className="calendar-setup-badge">
            <Icon id={connected ? "calendar.badge.checkmark" : "calendar"} size={13} />
          </span>
          <div className="calendar-setup-text">
            <MarqueeText text={tr("Today's calendar")} className="calendar-setup-title" />
            <MarqueeText text={connected ? tr("Connected") : tr("Not connected")} className="calendar-setup-status" data-connected={connected} />
          </div>
        </div>
        <div className="calendar-setup-detail">
          {tr("Up next shows your %@ as the day goes, and Plan my day fits work around them.", localizedUpNextEvents(settings.upNextEvents))}
        </div>
        <div className="calendar-setup-actions">
          {!connected && <PlannerPillButton title={tr("Connect calendar")} symbol="calendar" isProminent height={24} help={tr("Open Connections to connect your calendar")} onClick={openConnections} />}
          <span className="calendar-setup-spacer" />
          <Tooltip text={tr("%@ reads your events on this PC and never uploads them", context.edition.name)}>
            <span className="calendar-setup-lock">
              <Icon id="lock.fill" size={8.5} />
              <span>{tr("Stays on this PC")}</span>
            </span>
          </Tooltip>
        </div>
      </Card>
      <Card padding={Spacing.s} className="upnext-card calendar-setup-day">
        <div className="upnext-caption calendar-setup-caption">
          <span>{tr("Up next")}</span>
          {!connected && (
            <Tooltip text={tr("A sample day. Your own events show here once the calendar is connected.")}>
              <span className="calendar-setup-example">{tr("Example")}</span>
            </Tooltip>
          )}
        </div>
        {situation !== undefined ? (
          <SetupEmpty state={upNextEmptyState(situation, settings.upNextEvents, context.edition.name)} />
        ) : (
          <div className="upnext-rows" data-example={!connected}>
            {events.map((event) => (
              <UpNextRow key={event.id} event={event} now={state.now} locale={locale} timeZone={timeZone} join={(link) => upNextStore.join(link)} />
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}

function SetupEmpty({ state }: { state: ReturnType<typeof upNextEmptyState> }) {
  return (
    <div className="upnext-message">
      <div className="upnext-message-head">
        <span className="upnext-message-icon">
          <Icon id={state.symbol} size={13} />
        </span>
        <MarqueeText text={state.title} className="upnext-message-title" />
      </div>
      <div className="upnext-message-detail">{state.detail}</div>
    </div>
  );
}
