import { PetAdventure } from "../pets/petAdventure";
import type { PetPresence } from "../pets/petPresence";
import type { ProgressItem } from "../providers/progressItem";
import { eventTiming, eventTitle, upNext, type UpcomingEvent } from "../planner/upcomingEvent";
import type { ProvidedFocus } from "../providers/providedFocus";
import type { ProvidedParty } from "../providers/providedParty";
import type { ProviderSnapshot } from "../providers/providerSnapshot";
import type { TickerHighlight } from "../providers/tickerHighlight";
import type { Instant, Seconds } from "../time";
import {
  MAX_PARTY_PETS,
  PIN_LEAD_TIME,
  tickerFocusOf,
  tickerMeeting,
  tickerPet,
  type TickerItem,
} from "./tickerItem";
import { highlightsKind, LEADING_TICKER_KINDS, TICKER_KINDS, TRAILING_TICKER_KINDS, type TickerKind } from "./tickerKind";

/** Which kinds are turned on: a predicate, or a set of kinds. Every kind when undefined. */
export type TickerKindFilter = ((kind: TickerKind) => boolean) | ReadonlySet<TickerKind>;

function enabledPredicate(filter: TickerKindFilter | undefined): (kind: TickerKind) => boolean {
  if (filter === undefined) return () => true;
  if (typeof filter === "function") return filter;
  return (kind) => filter.has(kind);
}

export interface TickerSourcesInit {
  events?: readonly UpcomingEvent[];
  isMusicPlaying?: boolean;
  /** The shared focus clock; its `source` is the module running it. */
  focus?: ProvidedFocus | undefined;
  tasksRemaining?: number;
  /** Shared goals from the enabled modules, in tab order. */
  progress?: readonly ProgressItem[];
  /** Modules' own lines, in tab order. */
  highlights?: readonly TickerHighlight[];
  pet?: PetPresence | undefined;
  party?: ProvidedParty | undefined;
}

/**
 * Port of TickerSources: a snapshot of every module's state the ticker draws
 * from. The app fills it from the merged `ProviderSnapshot`; keeping it a
 * plain value lets the selection rules be tested without any module.
 */
export class TickerSources {
  /** Meetings starting this soon (or already under way) pin themselves. */
  static readonly pinLeadTime: Seconds = PIN_LEAD_TIME;
  /** Meetings further out than this are not "live" yet and stay hidden. */
  static readonly meetingHorizon: Seconds = 60 * 60;

  readonly events: readonly UpcomingEvent[];
  readonly isMusicPlaying: boolean;
  readonly focus: ProvidedFocus | undefined;
  readonly tasksRemaining: number;
  readonly progress: readonly ProgressItem[];
  readonly highlights: readonly TickerHighlight[];
  readonly pet: PetPresence | undefined;
  readonly party: ProvidedParty | undefined;

  constructor(init: TickerSourcesInit = {}) {
    this.events = init.events ?? [];
    this.isMusicPlaying = init.isMusicPlaying ?? false;
    this.focus = init.focus;
    this.tasksRemaining = init.tasksRemaining ?? 0;
    this.progress = init.progress ?? [];
    this.highlights = init.highlights ?? [];
    this.pet = init.pet;
    this.party = init.party;
  }

  /** What the ticker needs from the enabled modules' merged provisions. */
  static of(snapshot: ProviderSnapshot): TickerSources {
    return new TickerSources({
      events: snapshot.events,
      isMusicPlaying: snapshot.isPlaying,
      focus: snapshot.focus,
      tasksRemaining: snapshot.openTasks.length,
      progress: snapshot.progress,
      highlights: snapshot.highlights,
      pet: snapshot.pet,
      party: snapshot.party,
    });
  }

  /**
   * Every item that has something to say at `now`, in rotation order: the
   * leading built-in kinds, then one highlight per module (highest priority
   * first, ties in tab order), then the party and the pet. Kinds `enabled`
   * rejects and kinds with no data are skipped, so an empty result means the
   * island stays plain.
   */
  items(now: Instant, enabled?: TickerKindFilter): TickerItem[] {
    const isEnabled = enabledPredicate(enabled);
    const pick = (kinds: readonly TickerKind[]) =>
      kinds.filter(isEnabled).flatMap((kind) => {
        const item = this.item(kind, now);
        return item === undefined ? [] : [item];
      });
    const highlights = this.topHighlights(now)
      .filter((highlight) => isEnabled(highlightsKind(highlight.source)))
      .map((highlight): TickerItem => ({ type: "highlight", highlight }));
    return [...pick(LEADING_TICKER_KINDS), ...highlights, ...pick(TRAILING_TICKER_KINDS)];
  }

  /**
   * The earliest moment after `now` at which `items` can change from the
   * clock alone: a meeting countdown ticking down a minute, a meeting
   * entering the horizon or ending, a focus phase ending, a highlight
   * expiring, or the pet dozing off. Undefined when nothing is pending.
   *
   * Lets the caller sleep until then instead of polling. A running focus
   * clock's per-second change is left to the caller, which only needs it
   * while that clock is on screen.
   */
  nextChange(now: Instant, enabled?: TickerKindFilter): Instant | undefined {
    const isEnabled = enabledPredicate(enabled);
    const dates: Instant[] = [];
    if (isEnabled(TICKER_KINDS.meeting)) {
      for (const event of this.events) {
        if (event.isAllDay || !(event.end > now)) continue;
        const lead = event.start - now;
        if (lead > TickerSources.meetingHorizon) {
          dates.push(event.start - TickerSources.meetingHorizon);
        } else if (lead > 0) {
          /* The countdown shows whole minutes rounded up, so it drops by one each time the lead crosses a minute. */
          const minutes = Math.ceil(lead / 60);
          dates.push(event.start - (minutes - 1) * 60);
        } else {
          dates.push(event.end);
        }
      }
    }
    const endsAt = this.focus?.endsAt;
    if (isEnabled(TICKER_KINDS.focus) && endsAt !== undefined && endsAt > now) dates.push(endsAt);
    for (const highlight of this.highlights) {
      if (!isEnabled(highlightsKind(highlight.source))) continue;
      if (highlight.expiresAt !== undefined && highlight.expiresAt > now) dates.push(highlight.expiresAt);
    }
    if (isEnabled(TICKER_KINDS.pet) && this.pet) {
      const sleepsAt = this.pet.sleepsAt(this.focus, now);
      if (sleepsAt !== undefined) dates.push(sleepsAt);
    }
    return dates.length === 0 ? undefined : Math.min(...dates);
  }

  /** The next meeting that starts within the pin lead (not yet under way), which the meeting preview shows ahead of one in progress. */
  imminentMeeting(now: Instant): UpcomingEvent | undefined {
    return upNext(this.events, now, this.events.length).find(
      (event) => event.start > now && event.start - now <= TickerSources.pinLeadTime,
    );
  }

  /** Each module's live highlight with the highest priority (ties keep the module's own order), by priority with ties in tab order. */
  private topHighlights(now: Instant): TickerHighlight[] {
    const best = new Map<string, TickerHighlight>();
    for (const highlight of this.highlights) {
      if (!highlight.isLive(now)) continue;
      const current = best.get(highlight.source);
      if (current === undefined || highlight.priority > current.priority) best.set(highlight.source, highlight);
    }
    /* A Map keeps the order modules first appeared in, and the sort is stable, so ties stay in tab order. */
    return [...best.values()].sort((a, b) => b.priority - a.priority);
  }

  private item(kind: TickerKind, now: Instant): TickerItem | undefined {
    switch (kind) {
      case TICKER_KINDS.meeting: {
        /* A meeting about to start beats one already under way, so a long block can't hide "Standup in 3 min". */
        const event = this.imminentMeeting(now) ?? upNext(this.events, now, this.events.length)[0];
        if (event === undefined || event.start - now > TickerSources.meetingHorizon) return undefined;
        return {
          type: "meeting",
          meeting: tickerMeeting({
            title: eventTitle(event),
            timing: eventTiming(event, now),
            canJoin: event.meetingLink !== undefined,
            link: event.meetingLink,
          }),
        };
      }
      case TICKER_KINDS.nowPlaying:
        return this.isMusicPlaying ? { type: "nowPlaying" } : undefined;
      case TICKER_KINDS.focus: {
        /* An idle timer isn't an activity; paused still is, since the user is mid-session. */
        const focus = this.focus;
        if (focus === undefined || !focus.isActive) return undefined;
        return { type: "focus", focus: tickerFocusOf(focus, now) };
      }
      case TICKER_KINDS.tasks:
        return this.tasksRemaining > 0 ? { type: "tasks", remaining: this.tasksRemaining } : undefined;
      case TICKER_KINDS.progress: {
        /* The first goal in tab order with work left; a finished goal has nothing to say, and nor has an untouched aspiration. */
        const item = this.progress.find((goal) => goal.showsBesideNotch);
        return item === undefined ? undefined : { type: "progress", item };
      }
      case TICKER_KINDS.pet: {
        const pet = this.pet;
        if (pet === undefined) return undefined;
        const focus = this.focus;
        const since = focus?.isRunning === true ? now - focus.elapsed(now) : undefined;
        const unlock = pet.nextUnlock?.isNear === true ? pet.nextUnlock : undefined;
        /* Reduce Motion is the wing's to apply, so the plan here is the one the pet follows when it may move. */
        return {
          type: "pet",
          pet: tickerPet({
            profile: pet.profile,
            mood: pet.mood(focus, now),
            moodSince: since,
            unlock,
            adventure: PetAdventure.plan(focus, false),
          }),
        };
      }
      case TICKER_KINDS.party: {
        /* Alone in a party there are no other pets to show. */
        const party = this.party;
        if (party === undefined || party.memberCount <= 1) return undefined;
        return { type: "party", party: { pets: party.pets.slice(0, MAX_PARTY_PETS), memberCount: party.memberCount } };
      }
      default:
        return undefined;
    }
  }
}
