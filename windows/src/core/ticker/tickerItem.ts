import type { FocusPhase } from "../focus/focusTimer";
import { focusPhaseName } from "../focus/focusTimerFormat";
import type { UnlockProgress } from "../motivation/unlockProgress";
import type { PetCheer } from "../motion/petCheer";
import { MODULE_IDS, type ModuleID } from "../modules/moduleId";
import type { PetAdventure } from "../pets/petAdventure";
import type { PetMood } from "../pets/petAnimator";
import type { PetProfile } from "../pets/petProfile";
import type { ProgressItem, ProvidedAction } from "../providers/progressItem";
import type { EventTiming, ProvidedMeetingLink } from "../providers/providedEvent";
import type { ProvidedFocus } from "../providers/providedFocus";
import type { ProvidedPartyPet } from "../providers/providedParty";
import type { TickerHighlight } from "../providers/tickerHighlight";
import type { Instant, Seconds } from "../time";
import { highlightsKind, TICKER_KINDS, tickerKindModule, type TickerKind } from "./tickerKind";

/** Meetings starting this soon (or already under way) pin themselves (the Mac's TickerSources.pinLeadTime). */
export const PIN_LEAD_TIME: Seconds = 5 * 60;

/* Whether a meeting with `timing` is close enough to pin, and to offer Join. */
function isWithinPinLead(timing: EventTiming): boolean {
  return timing.kind === "now" || timing.minutes * 60 <= PIN_LEAD_TIME;
}

/** Port of TickerMeeting: the meeting a ticker item counts down to. */
export interface TickerMeeting {
  readonly title: string;
  readonly timing: EventTiming;
  /** Whether the event carries a video-call link, so the opened panel can offer "Join". */
  readonly canJoin: boolean;
  /** The call to join, which the closed island offers once the meeting is close (`meetingOffersJoin`). */
  readonly link: ProvidedMeetingLink | undefined;
  /** The "leave now" pulse is playing (`MeetingNudge`). */
  readonly isNudging: boolean;
}

/** A meeting item; a link always means it can be joined. */
export function tickerMeeting(init: {
  title: string;
  timing: EventTiming;
  canJoin: boolean;
  link?: ProvidedMeetingLink | undefined;
  isNudging?: boolean;
}): TickerMeeting {
  return {
    title: init.title,
    timing: init.timing,
    canJoin: init.canJoin || init.link !== undefined,
    link: init.link,
    isNudging: init.isNudging ?? false,
  };
}

/** Whether the closed island shows a Join button: the meeting has a call and starts within the pin lead or is under way. */
export function meetingOffersJoin(meeting: TickerMeeting): boolean {
  return meeting.link !== undefined && isWithinPinLead(meeting.timing);
}

/** Port of TickerPet: the study pet beside the closed island and what it is doing. */
export interface TickerPet {
  readonly profile: PetProfile;
  readonly mood: PetMood;
  /**
   * When the running focus or break phase began (pauses taken out);
   * undefined with no phase running. A pet drawn anew mid-session reads it,
   * so it still knows how long the user has been at it.
   */
  readonly moodSince: Instant | undefined;
  /** A celebration playing right now (a finished focus session), or undefined. */
  readonly cheer: PetCheer | undefined;
  /** An unlock within a couple of sessions, which the closed island hints at with a slim bar. */
  readonly unlock: UnlockProgress | undefined;
  /**
   * The little adventure of the focus block under way, or undefined when the
   * pet stays home. One value for the whole block, so the item doesn't
   * change as the pet leaves and returns.
   */
  readonly adventure: PetAdventure | undefined;
}

export function tickerPet(init: {
  profile: PetProfile;
  mood: PetMood;
  moodSince?: Instant | undefined;
  cheer?: PetCheer | undefined;
  unlock?: UnlockProgress | undefined;
  adventure?: PetAdventure | undefined;
}): TickerPet {
  return {
    profile: init.profile,
    mood: init.mood,
    moodSince: init.moodSince,
    cheer: init.cheer,
    unlock: init.unlock,
    adventure: init.adventure,
  };
}

/** True while the pet sips because the PC started charging. */
export function tickerPetIsSipping(pet: TickerPet): boolean {
  return pet.cheer?.kind === "sip";
}

/**
 * The unlock hint to draw now: only while the pet is awake between
 * sessions, never during focus (when it may be off on an adventure), a
 * break, a nap or night doze, or a sip, so it stays out of the way of work
 * and of the pet's own states.
 */
export function tickerPetUnlockHint(pet: TickerPet): UnlockProgress | undefined {
  if (pet.mood !== "awake" || pet.adventure !== undefined || tickerPetIsSipping(pet)) return undefined;
  return pet.unlock?.isNear === true ? pet.unlock : undefined;
}

/** Port of TickerParty: the pets the closed island shows while the user is in a study party. */
export interface TickerParty {
  /** The user's pet first, capped at `MAX_PARTY_PETS`. */
  readonly pets: readonly ProvidedPartyPet[];
  /** Everyone in the party, including members whose pets don't fit. */
  readonly memberCount: number;
}

/** Most pets that fit beside the island: the user's and three others. */
export const MAX_PARTY_PETS = 4;

/** Port of TickerFocus: a focus or break clock under way, as the closed island shows it. */
export interface TickerFocus {
  readonly phase: FocusPhase;
  /** The running engine's name for the phase, e.g. "Focus" or "Review". */
  readonly label: string;
  /** Time left, or time worked when `countsUp`. */
  readonly time: Seconds;
  /** An open-ended phase (Flowtime, a card sprint) that counts up. */
  readonly countsUp: boolean;
  readonly isRunning: boolean;
  /** The module running the clock, whose panel a click opens. */
  readonly source: ModuleID;
  /** Full length of the phase, which sizes the ring around the closed timer's icon; undefined while counting up. */
  readonly length: Seconds | undefined;
}

export function tickerFocus(init: {
  phase: FocusPhase;
  label?: string | undefined;
  time: Seconds;
  countsUp?: boolean;
  isRunning: boolean;
  source?: ModuleID;
  length?: Seconds | undefined;
}): TickerFocus {
  return {
    phase: init.phase,
    label: init.label ?? focusPhaseName(init.phase),
    time: init.time,
    countsUp: init.countsUp ?? false,
    isRunning: init.isRunning,
    source: init.source ?? MODULE_IDS.planner,
    length: init.length,
  };
}

/** The shared focus clock at `now`. */
export function tickerFocusOf(focus: ProvidedFocus, now: Instant): TickerFocus {
  return tickerFocus({
    phase: focus.phase,
    label: focus.label,
    time: focus.shownTime(now),
    countsUp: focus.countsUp,
    isRunning: focus.isRunning,
    source: focus.source,
    length: focus.phaseLength,
  });
}

/**
 * How much of the phase has passed, 0...1, for the ring around the closed
 * timer. An open-ended phase has no end to fill toward, so it gets no ring.
 */
export function tickerFocusProgress(focus: TickerFocus): number | undefined {
  const length = focus.length;
  if (focus.countsUp || length === undefined || !(length > 0) || !Number.isFinite(focus.time)) return undefined;
  return Math.min(Math.max(1 - focus.time / length, 0), 1);
}

/** Port of TickerItem: one live activity the closed island can show. */
export type TickerItem =
  | { readonly type: "meeting"; readonly meeting: TickerMeeting }
  /** Music is playing; the app renders artwork and the equalizer itself. */
  | { readonly type: "nowPlaying" }
  /** A focus clock under way, from whichever module runs it. */
  | { readonly type: "focus"; readonly focus: TickerFocus }
  | { readonly type: "tasks"; readonly remaining: number }
  /** An unfinished shared goal, e.g. Anki cards left to review today. */
  | { readonly type: "progress"; readonly item: ProgressItem }
  /** A module's own line, drawn with its symbol and accent. */
  | { readonly type: "highlight"; readonly highlight: TickerHighlight }
  | { readonly type: "pet"; readonly pet: TickerPet }
  | { readonly type: "party"; readonly party: TickerParty };

export function tickerItemKind(item: TickerItem): TickerKind {
  switch (item.type) {
    case "highlight":
      return highlightsKind(item.highlight.source);
    case "meeting":
      return TICKER_KINDS.meeting;
    case "nowPlaying":
      return TICKER_KINDS.nowPlaying;
    case "focus":
      return TICKER_KINDS.focus;
    case "tasks":
      return TICKER_KINDS.tasks;
    case "progress":
      return TICKER_KINDS.progress;
    case "pet":
      return TICKER_KINDS.pet;
    case "party":
      return TICKER_KINDS.party;
  }
}

/**
 * The panel a click on this item opens: the module running a focus clock or
 * that provided a progress goal or highlight, otherwise the kind's module.
 */
export function tickerItemModule(item: TickerItem): ModuleID {
  switch (item.type) {
    case "focus":
      return item.focus.source;
    case "progress":
      return item.item.source;
    case "highlight":
      return item.highlight.source;
    default:
      return tickerKindModule(tickerItemKind(item)) ?? MODULE_IDS.planner;
  }
}

/** What a click runs besides opening the module: the action the module offered on its progress goal, if any. */
export function tickerItemAction(item: TickerItem): ProvidedAction | undefined {
  return item.type === "progress" ? item.item.action : undefined;
}

/**
 * Whether this item should hold the island instead of rotating away. A
 * meeting that starts within the pin lead or is under way is the one thing
 * the user must not miss; a module can pin a highlight for the same reason.
 */
export function tickerItemIsPinned(item: TickerItem): boolean {
  switch (item.type) {
    case "meeting":
      return isWithinPinLead(item.meeting.timing);
    case "highlight":
      return item.highlight.isPinned;
    default:
      return false;
  }
}
