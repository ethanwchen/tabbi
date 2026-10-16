/*
 * Port of ClosetLimited, ClosetEventBanner, ClosetLimitedShelfTitle and
 * ClosetLimitedTile: the limited edition items, never sold, earned from
 * study milestones, by focusing during seasonal events, or given at events.
 * They sit on shelves (`SeasonalEventCatalog.limitedShelves`): the event
 * going on now or the next one first, then the milestones, then the rest of
 * the year's events. Each tile shows how far along its goal is, and the
 * footer says how to earn the hovered item.
 */

import { useState, type ReactNode } from "react";
import { useStore } from "../../app/useStore";
import { PetCloset, stateIsOwned, type PetClosetItemState } from "../../core/closet/petCloset";
import { howToEarn, limitedEditionOf, limitedProgressFraction, type PetLimitedProgress } from "../../core/closet/petLimited";
import { eventDisplayName, eventDisplayTagline, nextOccurrence, rewardGoalLabel, SeasonalEventProgress, type SeasonalEventOccurrence } from "../../core/events/seasonalEvent";
import { SeasonalEventCatalog, type PetLimitedShelf } from "../../core/events/seasonalEventCatalog";
import { tr } from "../../core/localization/tr";
import { itemDisplayName, type PetItem } from "../../core/pets/petItem";
import type { PetProfile } from "../../core/pets/petProfile";
import type { Instant } from "../../core/time";
import { Icon } from "../../ui/kit/Icon";
import { Marquee, MarqueeText } from "../../ui/kit/MarqueeText";
import { PetSprite } from "../../ui/kit/PetView";
import { Tooltip } from "../../ui/kit/Tooltip";
import { monthDayAt, monthDayLongAt } from "./closetFormat";
import { ClosetFooterDetail } from "./ClosetPanel";
import { ScrollingGrid, TightLabel, thumbnailModel } from "./ClosetWardrobe";
import type { ClosetStore } from "./closetStore";

/** What an unearned seasonal tile shows while its event is not on. Port of ClosetLimitedWait. */
type LimitedWait = { readonly kind: "goal"; readonly label: string } | { readonly kind: "returns"; readonly day: Instant };

export function ClosetLimited({ store }: { store: ClosetStore }) {
  const state = useStore(store);
  const [hovered, setHovered] = useState<PetItem | undefined>(undefined);
  const model = thumbnailModel(state.profile);
  const closet = state.closet;
  const timeZone = store.calendar.timeZone;
  const seasonNow = store.seasonNow;
  const shelves = SeasonalEventCatalog.bundled.limitedShelves(seasonNow, timeZone);

  const hover = (item: PetItem, inside: boolean) => {
    const next = inside ? item : hovered === item ? undefined : hovered;
    setHovered(next);
    store.tryOn(next);
  };

  /* The featured event's focus so far while it runs, which its banner shows in place of the shelf title. */
  const runningEvent = (kind: PetLimitedShelf["kind"]): SeasonalEventProgress | undefined => {
    if (kind.kind !== "event" || !kind.isActive) return undefined;
    return state.seasons.active(seasonNow).find((run) => run.occurrence.event.id === kind.occurrence.event.id);
  };

  /* What an unearned seasonal item waits for between runs: on the upcoming event's shelf its focus goal; further out, the day its event comes back. */
  const waiting = (item: PetItem, shelf: PetLimitedShelf["kind"]): LimitedWait | undefined => {
    const event = SeasonalEventCatalog.bundled.eventOffering(item);
    if (event === undefined) return undefined;
    const reward = event.rewards.find((candidate) => candidate.item === item);
    if (shelf.kind === "event" && reward !== undefined) return { kind: "goal", label: rewardGoalLabel(reward) };
    const next = nextOccurrence(event, seasonNow, timeZone);
    return next === undefined ? undefined : { kind: "returns", day: next.start };
  };

  const earnedCount = PetCloset.limitedShelf.filter((item) => stateIsOwned(closet.state(item))).length;

  return (
    <div className="closet-section closet-limited">
      <ScrollingGrid store={store}>
        <div className="closet-shelves">
          {shelves.map((shelf, index) => {
            const run = runningEvent(shelf.kind);
            return (
              <div key={index} className="closet-shelf">
                {run !== undefined ? <ClosetEventBanner run={run} timeZone={timeZone} /> : <ClosetLimitedShelfTitle kind={shelf.kind} timeZone={timeZone} />}
                <div className="closet-grid">
                  {shelf.items.map((item) => {
                    const edition = limitedEditionOf(item);
                    const progress = (edition === undefined ? undefined : state.milestones.progress(edition, store.now(), store.calendar)) ?? state.seasons.progress(item, seasonNow);
                    return (
                      <ClosetLimitedTile
                        key={item}
                        item={item}
                        state={closet.state(item)}
                        progress={progress}
                        waiting={waiting(item, shelf.kind)}
                        model={model}
                        timeZone={timeZone}
                        onClick={() => store.tap(item)}
                        onHover={(inside) => hover(item, inside)}
                      />
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>
      </ScrollingGrid>
      <div className="closet-footer kit-caption">
        {state.tryingOn !== undefined && limitedEditionOf(state.tryingOn) !== undefined ? (
          <ClosetFooterDetail
            name={itemDisplayName(state.tryingOn)}
            detail={stateIsOwned(closet.state(state.tryingOn)) ? (closet.state(state.tryingOn).kind === "wearing" ? tr("Earned. Click to take off.") : tr("Earned. Click to wear.")) : howToEarn(limitedEditionOf(state.tryingOn) ?? "foundingMember")}
          />
        ) : (
          <>
            <MarqueeText text={tr("Earned by studying, never sold")} className="kit-secondary closet-footer-lead" />
            <span className="kit-tertiary closet-footer-count">{tr("%lld of %lld earned", earnedCount, PetCloset.limitedShelf.length)}</span>
          </>
        )}
      </div>
    </div>
  );
}

/* The run's end is the midnight after its last day. */
function lastDay(occurrence: SeasonalEventOccurrence, timeZone: string): string {
  return monthDayAt(occurrence.end - 1, timeZone);
}

/** The event going on now, at the top of the Limited section: its name, last day and line of copy, and the focus logged toward its next item. */
function ClosetEventBanner({ run, timeZone }: { run: SeasonalEventProgress; timeZone: string }) {
  const event = run.occurrence.event;
  const name = eventDisplayName(event);
  const until = tr("until %@", lastDay(run.occurrence, timeZone));
  const reward = run.nextReward;
  const help =
    reward === undefined
      ? tr("%@: you earned every item. They stay yours after the event.", name)
      : tr("%@ runs until %@. Next item, %@: %@ focused.", name, lastDay(run.occurrence, timeZone), itemDisplayName(reward.item), run.progress(reward).label);
  return (
    <Tooltip text={help}>
      <div className="closet-event-banner">
        <Icon id="sparkles" size={11} className="closet-event-sparkle" />
        <div className="closet-event-text">
          <div className="closet-event-row">
            <Marquee text={`${name} ${until}`} help={help} className="closet-event-title">
              <span className="closet-event-name">{name}</span>
              <span className="kit-caption kit-tertiary">{until}</span>
            </Marquee>
            <span className="closet-event-goal">
              {reward === undefined ? (
                <TightLabel symbol="checkmark" className="closet-event-done">
                  {tr("All earned")}
                </TightLabel>
              ) : (
                <>
                  <span className="closet-event-progress">{run.progress(reward).label}</span>
                  <span className="closet-bar" style={{ width: 32 }}>
                    <span style={{ width: `${limitedProgressFraction(run.progress(reward)) * 100}%` }} />
                  </span>
                </>
              )}
            </span>
          </div>
          <MarqueeText text={eventDisplayTagline(event)} help={help} className="kit-caption kit-secondary closet-event-tagline" />
        </div>
      </div>
    </Tooltip>
  );
}

/** A Limited shelf's title. The featured event's says when it ends, or when it starts, and its tooltip carries the event's line of copy. */
function ClosetLimitedShelfTitle({ kind, timeZone }: { kind: PetLimitedShelf["kind"]; timeZone: string }) {
  let content: ReactNode;
  let help: string;
  switch (kind.kind) {
    case "event":
      content = (
        <>
          <span style={{ color: kind.isActive ? "var(--accent)" : "var(--secondary-text)" }}>{eventDisplayName(kind.occurrence.event)}</span>
          <span className="kit-tertiary">{kind.isActive ? tr("until %@", lastDay(kind.occurrence, timeZone)) : tr("starts %@", monthDayAt(kind.occurrence.start, timeZone))}</span>
        </>
      );
      help = eventDisplayTagline(kind.occurrence.event);
      break;
    case "milestones":
      content = <span className="kit-secondary">{tr("Milestones")}</span>;
      help = tr("Earned by reaching study milestones");
      break;
    case "laterEvents":
      content = <span className="kit-secondary">{tr("More events")}</span>;
      help = tr("Items from the year's other events, earned by focusing while each one runs");
      break;
  }
  return (
    <Tooltip text={help}>
      <div className="closet-shelf-title closet-limited-title">{content}</div>
    </Tooltip>
  );
}

interface LimitedTileProps {
  readonly item: PetItem;
  readonly state: PetClosetItemState;
  readonly progress: PetLimitedProgress | undefined;
  readonly waiting: LimitedWait | undefined;
  readonly model: PetProfile;
  readonly timeZone: string;
  readonly onClick: () => void;
  readonly onHover: (inside: boolean) => void;
}

/** A limited edition tile: the item on the pet, a sparkle badge, and below it On, Owned, the goal's progress with a thin bar, or the day its event comes back. */
function ClosetLimitedTile({ item, state, progress, waiting, model, timeZone, onClick, onHover }: LimitedTileProps) {
  const owned = stateIsOwned(state);
  const name = itemDisplayName(item);
  const edition = limitedEditionOf(item);
  const earn = edition === undefined ? "" : howToEarn(edition);
  let label: ReactNode;
  switch (state.kind) {
    case "wearing":
      label = (
        <TightLabel symbol="checkmark" className="closet-tile-on">
          {tr("On")}
        </TightLabel>
      );
      break;
    case "owned":
      label = <span className="kit-secondary">{tr("Owned")}</span>;
      break;
    default:
      if (progress !== undefined) label = <span className="kit-secondary">{progress.label}</span>;
      else if (waiting?.kind === "goal") {
        label = (
          <TightLabel symbol="timer" className="kit-tertiary">
            {waiting.label}
          </TightLabel>
        );
      } else if (waiting?.kind === "returns") {
        label = (
          <TightLabel symbol="calendar" className="kit-tertiary">
            {monthDayAt(waiting.day, timeZone)}
          </TightLabel>
        );
      } else {
        label = (
          <TightLabel symbol="calendar" className="kit-tertiary">
            {tr("Event")}
          </TightLabel>
        );
      }
  }
  const help =
    state.kind === "wearing"
      ? tr("%@, limited edition: click to take off", name)
      : state.kind === "owned"
        ? tr("%@, limited edition: click to wear", name)
        : progress === undefined && waiting?.kind === "returns"
          ? tr("%@, limited edition: %@ Its event starts %@.", name, earn, monthDayLongAt(waiting.day, timeZone))
          : tr("%@, limited edition: %@", name, earn);
  const showsBar = !owned && progress !== undefined;
  return (
    <Tooltip text={help}>
      <button
        type="button"
        className="closet-tile closet-tile-limited"
        data-item={item}
        data-wearing={state.kind === "wearing" || undefined}
        aria-label={name}
        onClick={onClick}
        onPointerEnter={() => onHover(true)}
        onPointerLeave={() => onHover(false)}
      >
        <span className="closet-tile-sprite" style={{ opacity: owned ? 1 : 0.45, filter: owned ? undefined : "saturate(0.3)" }}>
          <PetSprite profile={PetCloset.wearing(item, model)} pixelSize={1} />
        </span>
        <span className="closet-tile-label">{label}</span>
        <span className="closet-bar closet-tile-bar" style={{ width: 40, opacity: showsBar ? 1 : 0 }}>
          <span style={{ width: `${(progress === undefined ? 0 : limitedProgressFraction(progress)) * 100}%` }} />
        </span>
        <Icon id="sparkles" size={8} className="closet-tile-sparkle" style={{ color: owned ? "var(--accent)" : "var(--tertiary-text)" }} />
      </button>
    </Tooltip>
  );
}
