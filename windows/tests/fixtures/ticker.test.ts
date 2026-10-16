import { beforeAll, describe, expect, it } from "vitest";
import type { FocusPhase } from "../../src/core/focus/focusTimer";
import { PET_BREEDS, type PetBreed } from "../../src/core/pets/petKinds";
import { PetPresence } from "../../src/core/pets/petPresence";
import { PetProfile } from "../../src/core/pets/petProfile";
import { ProgressItem } from "../../src/core/providers/progressItem";
import { classifyMeetingURL, type MeetingLink } from "../../src/core/planner/meetingLink";
import { upcomingEvent, type UpcomingEvent } from "../../src/core/planner/upcomingEvent";
import { ProvidedFocus, type ProvidedFocusClock } from "../../src/core/providers/providedFocus";
import { ProvidedParty, type ProvidedPartyPet } from "../../src/core/providers/providedParty";
import { TICKER_HIGHLIGHT_TONES, TickerHighlight, type TickerHighlightTone } from "../../src/core/providers/tickerHighlight";
import {
  tickerFocusClock,
  tickerFocusSummary,
  tickerMeetingCountdown,
  tickerMeetingSummary,
  tickerPartySize,
  tickerPetLabel,
  tickerPetSummary,
  tickerProgressLeft,
  tickerTasksLeft,
} from "../../src/core/ticker/tickerFormat";
import {
  MAX_PARTY_PETS,
  tickerFocus,
  tickerItemAction,
  tickerItemIsPinned,
  tickerItemKind,
  tickerItemModule,
  tickerMeeting,
  tickerPet,
  type TickerItem,
} from "../../src/core/ticker/tickerItem";
import { LEADING_TICKER_KINDS, TICKER_KINDS, TRAILING_TICKER_KINDS, tickerKindModule } from "../../src/core/ticker/tickerKind";
import { TickerRotation } from "../../src/core/ticker/tickerRotation";
import { TickerSources } from "../../src/core/ticker/tickerSources";
import { switchLanguage } from "../support/catalogs";
import { loadFixture } from "../support/fixtures";
import { goldenDiff } from "../support/goldenCompare";

/*
 * Replays shared/fixtures/ticker (written by TickerGoldenTests on the Mac):
 * every source set read at its recorded moments with its recorded kinds
 * turned on, comparing the items, their display strings and the next
 * change, and every rotation sequence step by step.
 */

interface Link {
  provider: string;
  url: string;
}

interface Event {
  id: string;
  title: string;
  start: number;
  end: number;
  isAllDay?: boolean;
  meetingLink?: Link;
}

interface Focus {
  source: string;
  phase: string;
  label: string;
  clock: { kind: string; endsAt?: number; since?: number; shown?: number };
  phaseLength?: number;
}

interface Action {
  id: string;
  title: string;
}

interface Progress {
  id: string;
  source: string;
  title: string;
  completed: number;
  target: number;
  unit: string;
  action?: Action;
  waitsForStart?: boolean;
}

interface Highlight {
  id: string;
  source: string;
  symbol?: string;
  text: string;
  summary: string;
  tone: string;
  priority: number;
  isPinned: boolean;
  expiresAt?: number;
}

interface Pet {
  name: string;
  breed: string;
}

interface PartyPet {
  id: string;
  name: string;
  pet: Pet;
  isAway?: boolean;
}

interface Sources {
  events?: Event[];
  isMusicPlaying?: boolean;
  focus?: Focus;
  tasksRemaining?: number;
  progress?: Progress[];
  highlights?: Highlight[];
  pet?: { pet: Pet; lastActive: number };
  party?: PartyPet[];
}

interface Read {
  at: number;
  enabled?: string[];
  items: unknown[];
  nextChange?: number;
}

interface RotationItem {
  kind: string;
  pinned?: boolean;
}

interface RotationStep {
  at: number;
  interval?: number;
  items: RotationItem[];
  shown?: string;
  currentKind?: string;
  shownSince?: number;
}

interface Golden {
  schema: string;
  version: number;
  constants: { pinLeadTime: number; meetingHorizon: number; petSleepAfter: number; maxPartyPets: number };
  kinds: { kind: string; position: string; module?: string }[];
  selections: { name: string; sources: Sources; reads: Read[] }[];
  rotations: { name: string; interval: number; steps: RotationStep[] }[];
}

const golden = loadFixture<Golden>("ticker/ticker.json");

/* The fixture's display strings are English, with plain counts written the Mac's way. */
const LOCALE = "en";
/* The pet's calendar only places its night, and the fixture's pets have none. */
const CALENDAR = { timeZone: "UTC", firstWeekday: 1 };

function breed(raw: string): PetBreed {
  const found = PET_BREEDS.find((candidate) => candidate === raw);
  if (found === undefined) throw new Error(`Unknown breed ${raw}`);
  return found;
}

function phase(raw: string): FocusPhase {
  if (raw !== "focus" && raw !== "rest") throw new Error(`Unknown phase ${raw}`);
  return raw;
}

function tone(raw: string): TickerHighlightTone {
  const found = TICKER_HIGHLIGHT_TONES.find((candidate) => candidate === raw);
  if (found === undefined) throw new Error(`Unknown tone ${raw}`);
  return found;
}

/* A recorded link as the Mac rebuilds it: its provider and URL, checked against the Windows classifier. */
function meetingLink(link: Link): MeetingLink {
  const classified = classifyMeetingURL(link.url);
  if (classified?.provider !== link.provider) throw new Error(`Not a ${link.provider} link: ${link.url}`);
  return classified;
}

const profile = (pet: Pet) => new PetProfile(pet.name, breed(pet.breed));

function clockOf(clock: Focus["clock"]): ProvidedFocusClock {
  switch (clock.kind) {
    case "countdown":
      return { kind: "countdown", endsAt: clock.endsAt ?? 0 };
    case "countUp":
      return { kind: "countUp", since: clock.since ?? 0 };
    case "paused":
      return { kind: "paused", shown: clock.shown ?? 0 };
    default:
      return { kind: "idle" };
  }
}

function tickerSources(sources: Sources): TickerSources {
  const events: UpcomingEvent[] = (sources.events ?? []).map((event) =>
    upcomingEvent({
      id: event.id,
      title: event.title,
      start: event.start,
      end: event.end,
      isAllDay: event.isAllDay ?? false,
      meetingLink: event.meetingLink === undefined ? undefined : meetingLink(event.meetingLink),
    }),
  );
  const focus = sources.focus;
  const party = sources.party;
  return new TickerSources({
    events,
    isMusicPlaying: sources.isMusicPlaying ?? false,
    focus:
      focus === undefined
        ? undefined
        : new ProvidedFocus({
            source: focus.source,
            phase: phase(focus.phase),
            label: focus.label,
            clock: clockOf(focus.clock),
            phaseLength: focus.phaseLength,
          }),
    tasksRemaining: sources.tasksRemaining ?? 0,
    progress: (sources.progress ?? []).map((goal) => new ProgressItem(goal)),
    highlights: (sources.highlights ?? []).map((line) => new TickerHighlight({ ...line, tone: tone(line.tone) })),
    pet: sources.pet === undefined ? undefined : new PetPresence(profile(sources.pet.pet), sources.pet.lastActive, CALENDAR),
    party:
      party === undefined
        ? undefined
        : new ProvidedParty(
            party.map((member): ProvidedPartyPet => ({
              id: member.id,
              name: member.name,
              pet: profile(member.pet),
              isAway: member.isAway ?? false,
            })),
          ),
  });
}

const petJson = (pet: PetProfile) => ({ name: pet.name, breed: pet.breed });

/* One item the way the Mac's fixture encodes it: kind, module, action, pin, and the case's own fields. */
function itemJson(item: TickerItem): Record<string, unknown> {
  const action = tickerItemAction(item);
  const json: Record<string, unknown> = {
    kind: tickerItemKind(item),
    module: tickerItemModule(item),
    isPinned: tickerItemIsPinned(item),
    action: action === undefined ? undefined : { id: action.id, title: action.title },
  };
  switch (item.type) {
    case "meeting": {
      const meeting = item.meeting;
      json.meeting = {
        title: meeting.title,
        timing: meeting.timing.kind === "now" ? { kind: "now" } : { kind: "startsIn", minutes: meeting.timing.minutes },
        canJoin: meeting.canJoin,
        countdown: tickerMeetingCountdown(meeting.timing),
        summary: tickerMeetingSummary(meeting),
      };
      break;
    }
    case "nowPlaying":
      break;
    case "focus": {
      const focus = item.focus;
      json.focus = {
        phase: focus.phase,
        label: focus.label,
        time: focus.time,
        countsUp: focus.countsUp,
        isRunning: focus.isRunning,
        source: focus.source,
        clock: tickerFocusClock(focus.time),
        summary: tickerFocusSummary(focus),
      };
      break;
    }
    case "tasks":
      json.tasks = { remaining: item.remaining, text: tickerTasksLeft(item.remaining) };
      break;
    case "progress": {
      const goal = item.item;
      json.progress = {
        id: goal.id,
        source: goal.source,
        title: goal.title,
        remaining: goal.remaining,
        unit: goal.unit,
        text: tickerProgressLeft(goal, LOCALE),
      };
      break;
    }
    case "highlight": {
      const line = item.highlight;
      json.highlight = {
        id: line.id,
        source: line.source,
        symbol: line.symbol,
        text: line.text,
        summary: line.summary,
        tone: line.tone,
        priority: line.priority,
        isPinned: line.isPinned,
        expiresAt: line.expiresAt,
      };
      break;
    }
    case "pet": {
      const pet = item.pet;
      json.pet = {
        ...petJson(pet.profile),
        mood: pet.mood,
        moodSince: pet.moodSince,
        label: tickerPetLabel(pet),
        /*
         * The Mac's fixture writer and its replay call TickerFormat.petSummary
         * with its default, the real clock, which only matters for an
         * adventure: every recorded block ended long ago, so the pet is home.
         */
        summary: tickerPetSummary(pet, Date.now() / 1000),
      };
      break;
    }
    case "party":
      json.party = {
        pets: item.party.pets.map((member) => ({ id: member.id, name: member.name, pet: petJson(member.pet), isAway: member.isAway })),
        memberCount: item.party.memberCount,
        size: tickerPartySize(item.party.memberCount),
      };
      break;
  }
  return json;
}

/* A stand-in item of `kind`, as the Mac's fixture builds them: the rotation reads only kinds and pins. */
function rotationItem(entry: RotationItem): TickerItem {
  const pinned = entry.pinned ?? false;
  let item: TickerItem;
  switch (entry.kind) {
    case TICKER_KINDS.meeting:
      item = {
        type: "meeting",
        meeting: tickerMeeting({ title: "Standup", timing: pinned ? { kind: "now" } : { kind: "startsIn", minutes: 30 }, canJoin: false }),
      };
      break;
    case TICKER_KINDS.nowPlaying:
      item = { type: "nowPlaying" };
      break;
    case TICKER_KINDS.focus:
      item = { type: "focus", focus: tickerFocus({ phase: "focus", time: 600, isRunning: true }) };
      break;
    case TICKER_KINDS.tasks:
      item = { type: "tasks", remaining: 2 };
      break;
    case TICKER_KINDS.progress:
      item = {
        type: "progress",
        item: new ProgressItem({ id: "reviews", source: "anki", title: "Reviews", completed: 1, target: 2, unit: "cards" }),
      };
      break;
    case TICKER_KINDS.pet:
      item = { type: "pet", pet: tickerPet({ profile: PetProfile.starter("cat"), mood: "awake" }) };
      break;
    case TICKER_KINDS.party:
      item = { type: "party", party: { pets: [], memberCount: 2 } };
      break;
    default:
      item = { type: "highlight", highlight: new TickerHighlight({ id: "line", source: entry.kind, text: "line", isPinned: pinned }) };
  }
  if (tickerItemIsPinned(item) !== pinned) throw new Error(`Only meetings and highlights pin: ${entry.kind}`);
  return item;
}

beforeAll(() => {
  switchLanguage("en");
});

describe("ticker golden fixture", () => {
  it("is the version this suite reads", () => {
    expect(golden.schema).toBe("tabbi.ticker.golden");
    expect(golden.version).toBe(1);
    expect(golden.selections).toHaveLength(19);
    expect(golden.rotations).toHaveLength(13);
  });

  it("has the Mac's constants", () => {
    const constants = {
      pinLeadTime: TickerSources.pinLeadTime,
      meetingHorizon: TickerSources.meetingHorizon,
      petSleepAfter: PetPresence.sleepAfter,
      maxPartyPets: MAX_PARTY_PETS,
    };
    expect(goldenDiff(constants, golden.constants)).toBeUndefined();
  });

  it("has the Mac's built-in kinds in rotation order", () => {
    const kinds = [
      ...LEADING_TICKER_KINDS.map((kind) => ({ kind, position: "leading", module: tickerKindModule(kind) })),
      ...TRAILING_TICKER_KINDS.map((kind) => ({ kind, position: "trailing", module: tickerKindModule(kind) })),
    ];
    expect(goldenDiff(kinds, golden.kinds)).toBeUndefined();
  });

  describe("selections", () => {
    for (const selection of golden.selections) {
      it(selection.name, () => {
        const sources = tickerSources(selection.sources);
        selection.reads.forEach((read, index) => {
          const enabled = read.enabled === undefined ? undefined : new Set(read.enabled);
          const actual = {
            at: read.at,
            enabled: read.enabled,
            items: sources.items(read.at, enabled).map(itemJson),
            nextChange: sources.nextChange(read.at, enabled),
          };
          expect(goldenDiff(actual, read, `${selection.name}.reads[${index}]`)).toBeUndefined();
        });
      });
    }
  });

  describe("rotations", () => {
    for (const rotation of golden.rotations) {
      it(rotation.name, () => {
        const ticker = new TickerRotation(rotation.interval);
        rotation.steps.forEach((step, index) => {
          if (step.interval !== undefined) ticker.interval = step.interval;
          const shown = ticker.update(step.items.map(rotationItem), step.at);
          const actual = {
            at: step.at,
            interval: step.interval,
            items: step.items,
            shown: shown === undefined ? undefined : tickerItemKind(shown),
            currentKind: ticker.currentKind,
            shownSince: ticker.shownSince,
          };
          expect(goldenDiff(actual, step, `${rotation.name}.steps[${index}]`)).toBeUndefined();
        });
      });
    }
  });
});
