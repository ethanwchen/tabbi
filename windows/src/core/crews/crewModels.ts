import { tr } from "../localization/tr";
import { PartyCode, read, type PartyProfile } from "../party/partyModels";
import type { Instant } from "../time";

/*
 * Port of CrewModels: the Study Crews wire models (protocol 3). The shapes
 * are written down in shared/schemas/crews.v1.schema.json and the design in
 * docs/design/crews.md. Like the Party models, ids stay strings, so a newer
 * server's frame, emblem, color or laurel never breaks reading; the app falls
 * back to the first frame, emblem and color it knows, an unknown laurel to
 * none and an unknown visibility to private.
 */

type JSONRecord = Readonly<Record<string, unknown>>;

/** A crew week: Monday 00:00 UTC up to (not including) the next Monday. Times are unix seconds. */
export interface CrewWeek {
  /** The ISO week key, such as `2026-W46`. */
  readonly id: string;
  readonly startsAt: Instant;
  /** Exclusive: the moment the board freezes. */
  readonly endsAt: Instant;
}

/** The week that contains `instant`, computed the way the server does. Port of CrewWeek.containing. */
export function crewWeekContaining(instant: Instant): CrewWeek {
  const day = Math.floor(instant / 86_400);
  /* 1970-01-01 was a Thursday: weekday 0 is Monday. */
  const weekday = (((day + 3) % 7) + 7) % 7;
  const monday = day - weekday;
  const thursday = monday + 3;
  const year = new Date(thursday * 86_400_000).getUTCFullYear();
  const yearStart = Math.floor(Date.UTC(year, 0, 1) / 86_400_000);
  const week = Math.floor((thursday - yearStart) / 7) + 1;
  return { id: `${String(year).padStart(4, "0")}-W${String(week).padStart(2, "0")}`, startsAt: monday * 86_400, endsAt: (monday + 7) * 86_400 };
}

export const CREW_LAURELS = ["gold", "silver", "bronze"] as const;
/** The laurel a crew wears for the week after it finished in the top 3. */
export type CrewLaurel = (typeof CREW_LAURELS)[number];

/** The laurel for a final rank: 1 gold, 2 silver, 3 bronze. */
export function laurelForRank(rank: number): CrewLaurel | undefined {
  return rank === 1 ? "gold" : rank === 2 ? "silver" : rank === 3 ? "bronze" : undefined;
}

export const CREW_VISIBILITIES = ["public", "private"] as const;
/** Who can find and join a crew. Both kinds can be ranked and featured. */
export type CrewVisibility = (typeof CREW_VISIBILITIES)[number];

/** A member's pet as crew pages show it: the same fields and ids as a Party profile. */
export interface CrewPet {
  readonly petName: string;
  readonly species: string;
  readonly breed: string;
  readonly colors: readonly string[];
  readonly costume: string;
  readonly accessories: readonly string[];
}

/** One member on a crew page, addressed by an opaque `ref`, never a friend code. */
export interface CrewMember {
  readonly ref: string;
  readonly name: string;
  /** Undefined when the member hid their pet from crew pages. */
  readonly pet: CrewPet | undefined;
  /** The member's Study Level, once the server sends it. */
  readonly studyLevel: number | undefined;
  readonly badges: readonly string[];
  readonly weekMinutes: number;
  readonly owner: boolean;
  readonly me: boolean;
}

/** The member's pet as a Party profile, so the shared Party appearance code draws it; undefined when hidden. */
export function memberPartyProfile(member: CrewMember): PartyProfile | undefined {
  const pet = member.pet;
  if (pet === undefined) return undefined;
  return {
    code: member.ref,
    name: member.name,
    petName: pet.petName,
    species: pet.species,
    breed: pet.breed,
    colors: pet.colors,
    costume: pet.costume,
    accessories: pet.accessories,
    points: 0,
    level: 1,
    badges: member.badges,
  };
}

/** What every list shows of a crew. */
export interface CrewSummary {
  readonly id: string;
  readonly name: string;
  readonly description: string;
  /** The crest's frame; unknown ids draw as the first frame. */
  readonly frame: string;
  /** The crest's emblem; unknown ids draw as the first emblem. */
  readonly emblem: string;
  /** The crest's color; unknown ids draw as the first color. */
  readonly color: string;
  readonly visibility: CrewVisibility;
  /** What the crew wears this week, or, on the featured board, the tier it won. */
  readonly laurel: CrewLaurel | undefined;
  /** Every top 3 finish ever. */
  readonly trophies: number;
  readonly memberCount: number;
  readonly maxMembers: number;
  readonly weekMinutes: number;
}

export function crewIsFull(crew: CrewSummary): boolean {
  return crew.memberCount >= crew.maxMembers;
}

/** The crew's crest as it came (`resolvedCrest` swaps ids this app lacks for the defaults). */
export function crewCrest(crew: CrewSummary): { frame: string; emblem: string; color: string } {
  return { frame: crew.frame, emblem: crew.emblem, color: crew.color };
}

/** Trophy pips on the crest: one per top 3 finish, at most three. */
export function crewPips(crew: CrewSummary): number {
  return Math.min(crew.trophies, 3);
}

/** Gold, silver and bronze finishes so far. */
export interface CrewMedals {
  readonly gold: number;
  readonly silver: number;
  readonly bronze: number;
}

/** A crew page: the summary, its members and what I may do there. */
export interface CrewDetail {
  readonly summary: CrewSummary;
  readonly createdAt: Instant;
  readonly medals: CrewMedals;
  /** This week's live rank among all crews; undefined with no minutes yet. */
  readonly rank: number | undefined;
  readonly members: readonly CrewMember[];
  /** I belong to it. */
  readonly mine: boolean;
  /** I own it. */
  readonly owner: boolean;
  /** Only members get it. */
  readonly inviteCode: string | undefined;
  /** The maintainer hid it from the board and Find; only members are told. */
  readonly hidden: boolean;
}

/** My own member row, when I belong. */
export function crewMe(crew: CrewDetail): CrewMember | undefined {
  return crew.members.find((member) => member.me);
}

/** One place on the board. */
export interface CrewBoardEntry {
  readonly rank: number;
  readonly minutes: number;
  readonly crew: CrewSummary;
}

/** A finished week's frozen top 3. */
export interface CrewFeatured {
  readonly week: CrewWeek;
  readonly entries: readonly CrewBoardEntry[];
}

/** `GET /v1/crews/board`: this week's live top 3 and last week's winners. */
export interface CrewBoard {
  readonly week: CrewWeek;
  readonly top: readonly CrewBoardEntry[];
  readonly featured: CrewFeatured | undefined;
}

/** What I send to create or edit a crew; an absent field of an edit keeps the server's value. */
export interface CrewDraft {
  readonly name?: string;
  readonly description?: string;
  readonly frame?: string;
  readonly emblem?: string;
  readonly color?: string;
  readonly visibility?: CrewVisibility;
}

/** One crew in the all-time Hall of Fame: its medals from every weekly top 3 finish, in Olympic order. */
export interface CrewHallEntry {
  /** Competition rank over the whole order; equal tallies reached at the same time share it. */
  readonly rank: number;
  readonly medals: CrewMedals;
  /** When the crew reached its current tally (the end of that week); earlier wins a tie. */
  readonly reachedAt: Instant;
  readonly crew: CrewSummary;
}

/** `GET /v1/crews/hall`: one page of the Hall of Fame and the cursor for the next, undefined at the end. */
export interface CrewHallPage {
  readonly entries: readonly CrewHallEntry[];
  readonly next: string | undefined;
}

/** One finished focus stretch, as the server credits it. */
export interface CrewSession {
  readonly start: Instant;
  readonly end: Instant;
  readonly minutes: number;
}

/**
 * What the server did with one reported session: credited, capped,
 * duplicate, overlap, future, invalid, week_closed or no_crew; a status this
 * app does not know is kept as it came and counts as answered.
 */
export type CrewSessionStatus = string;

export interface CrewSessionResult {
  readonly status: CrewSessionStatus;
  readonly credited: number;
}

/** `POST /v1/crews/sessions`. */
export interface CrewSessionsReply {
  readonly results: readonly CrewSessionResult[];
  readonly week: CrewWeek;
  readonly crewMinutes: number | undefined;
  readonly myMinutes: number;
}

export const CREW_REPORT_REASONS = ["inappropriate_name", "harassment", "spam", "cheating", "other"] as const;
/** Why I report a crew or one of its members; the values are the server's `reason` codes. */
export type CrewReportReason = (typeof CREW_REPORT_REASONS)[number];

export function crewReportReasonTitle(reason: CrewReportReason): string {
  switch (reason) {
    case "inappropriate_name":
      return tr("Inappropriate name");
    case "harassment":
      return tr("Harassment");
    case "spam":
      return tr("Spam");
    case "cheating":
      return tr("Cheating");
    case "other":
      return tr("Other");
  }
}

/** Crew invite codes (7 characters) and ids (10), from the friend code alphabet. */
export const CrewCode = {
  inviteLength: 7,
  idLength: 10,
  invite: (text: string): string | undefined => PartyCode.normalize(text, 7),
  crewID: (text: string): string | undefined => PartyCode.normalize(text, 10),
} as const;

/* MARK: Reading replies */

function laurelOf(value: unknown): CrewLaurel | undefined {
  return typeof value === "string" && (CREW_LAURELS as readonly string[]).includes(value) ? (value as CrewLaurel) : undefined;
}

export function readCrewWeek(value: unknown): CrewWeek {
  const object = read.record(value, "week");
  return { id: read.string(object, "id"), startsAt: read.number(object, "startsAt"), endsAt: read.number(object, "endsAt") };
}

export function readCrewPet(value: unknown): CrewPet {
  const object = read.record(value, "pet");
  return {
    petName: read.string(object, "petName"),
    species: read.string(object, "species"),
    breed: read.string(object, "breed"),
    colors: read.strings(object, "colors"),
    costume: read.string(object, "costume"),
    accessories: read.strings(object, "accessories"),
  };
}

export function readCrewMember(value: unknown): CrewMember {
  const object = read.record(value, "member");
  return {
    ref: read.string(object, "ref"),
    name: read.string(object, "name"),
    pet: read.optionalObject(object, "pet", readCrewPet),
    studyLevel: read.optional(object, "studyLevel", read.integer),
    badges: read.optional(object, "badges", read.strings) ?? [],
    weekMinutes: read.optional(object, "weekMinutes", read.integer) ?? 0,
    owner: read.optional(object, "owner", read.boolean) ?? false,
    me: read.optional(object, "me", read.boolean) ?? false,
  };
}

/** Reads a crew summary, also from a crew page's object (whose summary fields sit at its top level). */
export function readCrewSummary(value: unknown): CrewSummary {
  const object = read.record(value, "crew");
  const visibility = object.visibility === "public" ? "public" : "private";
  return {
    id: read.string(object, "id"),
    name: read.string(object, "name"),
    description: read.optional(object, "description", read.string) ?? "",
    frame: read.string(object, "frame"),
    emblem: read.string(object, "emblem"),
    color: read.string(object, "color"),
    visibility,
    laurel: laurelOf(object.laurel),
    trophies: read.optional(object, "trophies", read.integer) ?? 0,
    memberCount: read.integer(object, "memberCount"),
    maxMembers: read.optional(object, "maxMembers", read.integer) ?? 20,
    weekMinutes: read.optional(object, "weekMinutes", read.integer) ?? 0,
  };
}

function readMedals(raw: unknown): CrewMedals {
  const m = read.record(raw, "medals");
  return { gold: read.integer(m, "gold"), silver: read.integer(m, "silver"), bronze: read.integer(m, "bronze") };
}

export function readCrewHallPage(value: unknown): CrewHallPage {
  const object = read.record(value, "hall");
  return {
    entries: read.array(object, "entries").map((raw) => {
      const entry = read.record(raw, "entry");
      return { rank: read.integer(entry, "rank"), medals: readMedals(entry.medals), reachedAt: read.number(entry, "reachedAt"), crew: readCrewSummary(entry.crew) };
    }),
    next: read.optional(object, "next", read.string),
  };
}

export function readCrewDetail(value: unknown): CrewDetail {
  const object = read.record(value, "crew");
  const medals = read.optionalObject(object, "medals", readMedals);
  return {
    summary: readCrewSummary(object),
    createdAt: read.number(object, "createdAt"),
    medals: medals ?? { gold: 0, silver: 0, bronze: 0 },
    rank: read.optional(object, "rank", read.integer),
    members: read.array(object, "members").map(readCrewMember),
    mine: read.optional(object, "mine", read.boolean) ?? false,
    owner: read.optional(object, "owner", read.boolean) ?? false,
    inviteCode: read.optional(object, "inviteCode", read.string),
    hidden: read.optional(object, "hidden", read.boolean) ?? false,
  };
}

export function readCrewBoardEntry(value: unknown): CrewBoardEntry {
  const object = read.record(value, "entry");
  return { rank: read.integer(object, "rank"), minutes: read.integer(object, "minutes"), crew: readCrewSummary(object.crew) };
}

export function readCrewBoard(value: unknown): CrewBoard {
  const object = read.record(value, "board");
  return {
    week: readCrewWeek(object.week),
    top: read.array(object, "top").map(readCrewBoardEntry),
    featured: read.optionalObject(object, "featured", (raw) => {
      const featured = read.record(raw, "featured");
      return { week: readCrewWeek(featured.week), entries: read.array(featured, "entries").map(readCrewBoardEntry) };
    }),
  };
}

export function readCrewSessionsReply(value: unknown): CrewSessionsReply {
  const object: JSONRecord = read.record(value, "reply");
  return {
    results: read.array(object, "results").map((raw) => {
      const result = read.record(raw, "result");
      return { status: read.string(result, "status"), credited: read.integer(result, "credited") };
    }),
    week: readCrewWeek(object.week),
    crewMinutes: read.optional(object, "crewMinutes", read.integer),
    myMinutes: read.integer(object, "myMinutes"),
  };
}
