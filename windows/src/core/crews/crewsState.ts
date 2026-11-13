import { tr } from "../localization/tr";
import { PartyError, partyErrorMessage } from "../party/partyError";
import { isNameAllowed } from "../party/partyNameFilter";
import type { Instant } from "../time";
import { CREW_LIMITS } from "./crewCatalog";
import {
  crewWeekContaining,
  type CrewBoard,
  type CrewBoardEntry,
  type CrewDetail,
  type CrewHallEntry,
  type CrewHallPage,
  type CrewHallStanding,
  type CrewMyRequest,
  type CrewSummary,
  type CrewWeek,
} from "./crewModels";

/*
 * Port of CrewsState, CrewDraftCheck and CrewErrorText: what the Party
 * tab's Crews mode shows, kept apart from the network so it can be tested
 * and rendered in demo snapshots. The navigation follows the Crews UI spec:
 * four sections in a pill row, and at most one pushed screen (a crew's page
 * or the crest editor) over the section that opened it. Changes return a new
 * state, the Swift struct's value semantics.
 */

/** The sections of the pill row, in order. */
export const CREW_SECTIONS = ["mine", "week", "hall", "find"] as const;
export type CrewSection = (typeof CREW_SECTIONS)[number];

/** A screen pushed over a section; one level deep. */
export type CrewPushed =
  | {
      readonly kind: "crew";
      readonly crew: CrewDetail;
      readonly from: CrewSection;
    }
  | {
      readonly kind: "editor";
      readonly editing: boolean;
      readonly from: CrewSection;
    };

export interface CrewsState {
  readonly section: CrewSection;
  readonly pushed: CrewPushed | undefined;
  /** The current week, from the last reply (or computed until one comes). */
  readonly week: CrewWeek;
  /** My crew; undefined when I am in none. Only meaningful once `mineLoaded`. */
  readonly mine: CrewDetail | undefined;
  readonly mineLoaded: boolean;
  /** My pending request to join a public crew, while I am in none. */
  readonly myRequest: CrewMyRequest | undefined;
  /** The weekly board, with every page of rows loaded so far. */
  readonly board: CrewBoard | undefined;
  /** The Hall of Fame, every page loaded so far, and the next cursor. */
  readonly hall: readonly CrewHallEntry[] | undefined;
  readonly hallNext: string | undefined;
  /** My crew's standing in the Hall of Fame, from its first page. */
  readonly hallMine: CrewHallStanding | undefined;
  readonly query: string;
  /** Find's results for `query`; undefined until the first answer. */
  readonly results: readonly CrewSummary[] | undefined;
  /** An invite link's code, waiting for the user to confirm joining. */
  readonly invite: string | undefined;
  /** The last failure to load, shown in place of the section's content. */
  readonly loadError: PartyError | undefined;
}

export function crewsState(now: Instant, changes: Partial<CrewsState> = {}): CrewsState {
  return {
    section: "week",
    pushed: undefined,
    week: crewWeekContaining(now),
    mine: undefined,
    mineLoaded: false,
    myRequest: undefined,
    board: undefined,
    hall: undefined,
    hallNext: undefined,
    hallMine: undefined,
    query: "",
    results: undefined,
    invite: undefined,
    loadError: undefined,
    ...changes,
  };
}

export function inCrew(state: CrewsState): boolean {
  return state.mine !== undefined;
}

/** Whether I asked to join `crew` and wait for its owner. */
export function hasRequested(state: CrewsState, crew: string): boolean {
  return state.myRequest?.crew.id === crew;
}

/** Goes to a section, closing any pushed screen. */
export function showSection(state: CrewsState, section: CrewSection): CrewsState {
  return { ...state, section, pushed: undefined };
}

/** Back from a pushed screen to the section that opened it. */
export function popCrewScreen(state: CrewsState): CrewsState {
  if (state.pushed === undefined) return state;
  return { ...state, section: state.pushed.from, pushed: undefined };
}

/** My crew came back from the server (or I left it). */
export function didLoadMine(state: CrewsState, crew: CrewDetail | undefined, week: CrewWeek, request?: CrewMyRequest): CrewsState {
  let pushed = state.pushed;
  if (crew === undefined && pushed?.kind === "editor" && pushed.editing) pushed = undefined;
  /* A page of my own crew follows the fresh copy. */
  if (pushed?.kind === "crew" && crew !== undefined && pushed.crew.summary.id === crew.summary.id) pushed = { ...pushed, crew };
  return {
    ...state,
    mine: crew,
    week,
    myRequest: crew === undefined ? request : undefined,
    mineLoaded: true,
    loadError: undefined,
    pushed,
  };
}

/** The first page of the board, or a further page of rows when `appending`. */
export function didLoadBoard(state: CrewsState, page: CrewBoard, appending = false): CrewsState {
  const board = state.board;
  if (appending && board !== undefined) {
    const rows = [...board.rows, ...page.rows.filter((row) => !board.rows.some((known) => known.crew.id === row.crew.id))];
    return {
      ...state,
      board: { ...board, rows, next: page.next },
      week: page.week,
      loadError: undefined,
    };
  }
  return { ...state, board: page, week: page.week, loadError: undefined };
}

export function didLoadHall(state: CrewsState, page: CrewHallPage, appending = false): CrewsState {
  const loaded = state.hall;
  if (appending && loaded !== undefined) {
    const hall = [...loaded, ...page.entries.filter((entry) => !loaded.some((known) => known.crew.id === entry.crew.id))];
    return { ...state, hall, hallNext: page.next, loadError: undefined };
  }
  return {
    ...state,
    hall: page.entries,
    hallMine: page.mine,
    hallNext: page.next,
    loadError: undefined,
  };
}

/** The week has no minutes yet: the sleeping-pet state. */
export function isQuietWeek(state: CrewsState): boolean {
  return state.board !== undefined && state.board.top.length === 0 && state.board.rows.length === 0;
}

/** Every crew on the weekly board loaded so far, in place order. */
export function weekEntries(state: CrewsState): readonly CrewBoardEntry[] {
  return [...(state.board?.top ?? []), ...(state.board?.rows ?? [])];
}

/** My crew's entry on the weekly board, when loaded. */
export function myWeekEntry(state: CrewsState): CrewBoardEntry | undefined {
  const id = state.mine?.summary.id;
  return id === undefined ? undefined : weekEntries(state).find((entry) => entry.crew.id === id);
}

/** My crew in the Hall of Fame, when it has a medal and is loaded. */
export function myHallEntry(state: CrewsState): CrewHallEntry | undefined {
  const id = state.mine?.summary.id;
  return id === undefined ? undefined : state.hall?.find((entry) => entry.crew.id === id);
}

/* MARK: Draft checks */

export const CREW_DRAFT_PROBLEMS = ["nameEmpty", "nameTooLong", "nameNotAllowed", "descriptionTooLong", "descriptionNotAllowed"] as const;
export type CrewDraftProblem = (typeof CREW_DRAFT_PROBLEMS)[number];

export function crewDraftProblemMessage(problem: CrewDraftProblem): string {
  switch (problem) {
    case "nameEmpty":
      return tr("Give your crew a name.");
    case "nameTooLong":
      return tr("Crew names can be up to %lld characters.", CREW_LIMITS.nameMaxLength);
    case "nameNotAllowed":
      return tr("That crew name isn't allowed. Please pick another.");
    case "descriptionTooLong":
      return tr("Descriptions can be up to %lld characters.", CREW_LIMITS.descriptionMaxLength);
    case "descriptionNotAllowed":
      return tr("That description isn't allowed. Please change it.");
  }
}

/** Text as it is sent: line breaks folded into spaces, then trimmed. */
export function cleanCrewText(text: string): string {
  return text
    .split(/\r\n|\r|\n/)
    .join(" ")
    .trim();
}

/** Swift's `String.count`: grapheme clusters, not UTF-16 units. */
function characterCount(text: string): number {
  return [...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(text)].length;
}

/** The first problem with a name and description, or undefined when both are fine; the same filter the server applies. */
export function crewDraftProblem(name: string, description: string): CrewDraftProblem | undefined {
  const cleanName = cleanCrewText(name);
  const cleanDescription = cleanCrewText(description);
  if (cleanName === "") return "nameEmpty";
  if (characterCount(cleanName) > CREW_LIMITS.nameMaxLength) return "nameTooLong";
  if (!isNameAllowed(cleanName)) return "nameNotAllowed";
  if (characterCount(cleanDescription) > CREW_LIMITS.descriptionMaxLength) return "descriptionTooLong";
  if (cleanDescription !== "" && !isNameAllowed(cleanDescription)) return "descriptionNotAllowed";
  return undefined;
}

/* MARK: Errors */

/** Crew errors the server names with codes Party itself does not use, as one friendly sentence each. */
export function crewErrorMessage(error: PartyError): string {
  if (error.kind !== "server") {
    if (error.kind === "nameNotAllowed") return crewDraftProblemMessage("nameNotAllowed");
    return partyErrorMessage(error);
  }
  switch (error.code) {
    case "in_crew":
      return tr("You're already in a crew. Leave it first.");
    case "not_in_crew":
      return tr("You're not in a crew anymore.");
    case "crew_not_found":
      return tr("That crew is gone or the code is wrong.");
    case "crew_full":
      return tr("That crew is full.");
    case "not_owner":
      return tr("Only the crew's owner can do that.");
    case "name_taken":
      return tr("Another crew has that name. Please pick another.");
    case "crew_name_not_allowed":
      return crewDraftProblemMessage("nameNotAllowed");
    case "description_not_allowed":
      return crewDraftProblemMessage("descriptionNotAllowed");
    case "removed_from_crew":
      return tr("You can't join that crew.");
    case "member_not_found":
      return tr("That member left the crew.");
    case "request_not_found":
      return tr("That request is no longer waiting.");
    case "requests_full":
      return tr("That crew has a lot of requests waiting. Try again later.");
    case "request_limit":
      return tr("You've asked a lot of crews today. Try again tomorrow.");
    case "crew_limit":
      return tr("You've made a lot of crews today. Try again tomorrow.");
    default:
      return partyErrorMessage(error);
  }
}
