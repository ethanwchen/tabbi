import { tr } from "../localization/tr";
import { PartyError, partyErrorMessage } from "../party/partyError";
import { isNameAllowed } from "../party/partyNameFilter";
import type { Instant } from "../time";
import { CREW_LIMITS } from "./crewCatalog";
import { crewWeekContaining, type CrewBoard, type CrewBoardEntry, type CrewDetail, type CrewSummary, type CrewWeek } from "./crewModels";

/*
 * Port of CrewsState, CrewDraftCheck and CrewErrorText: what the Party
 * tab's Crew section shows, kept apart from the network so it can be
 * tested and rendered in demo snapshots. Changes return a new state, the
 * Swift struct's value semantics.
 */

export const CREW_SECTIONS = ["mine", "find", "create"] as const;
/** What the Crew section's main card shows; the weekly top 3 sits beside it in every section. */
export type CrewSection = (typeof CREW_SECTIONS)[number];

export interface CrewsState {
  readonly section: CrewSection;
  /** The current week, from the last reply (or computed until one comes). */
  readonly week: CrewWeek;
  /** My crew; undefined when I am in none. Only meaningful once `mineLoaded`. */
  readonly mine: CrewDetail | undefined;
  readonly mineLoaded: boolean;
  readonly board: CrewBoard | undefined;
  /** The top 3 card shows last week's frozen winners instead of the live race. */
  readonly showsLastWeek: boolean;
  readonly query: string;
  /** Find's results for `query`; undefined until the first answer. */
  readonly results: readonly CrewSummary[] | undefined;
  /** A crew page opened from the top 3 or Find, over the section that opened it. */
  readonly viewing: CrewDetail | undefined;
  /** The owner is editing my crew (the create form, filled in). */
  readonly editing: boolean;
  /** An invite link's code, waiting for the user to confirm joining. */
  readonly invite: string | undefined;
  /** The last failure to load, shown in place of the section's content. */
  readonly loadError: PartyError | undefined;
}

export function crewsState(now: Instant, changes: Partial<CrewsState> = {}): CrewsState {
  return {
    section: "mine",
    week: crewWeekContaining(now),
    mine: undefined,
    mineLoaded: false,
    board: undefined,
    showsLastWeek: false,
    query: "",
    results: undefined,
    viewing: undefined,
    editing: false,
    invite: undefined,
    loadError: undefined,
    ...changes,
  };
}

export function inCrew(state: CrewsState): boolean {
  return state.mine !== undefined;
}

/** The entries the top 3 card shows now: the live race, or last week's winners. */
export function boardEntries(state: CrewsState): readonly CrewBoardEntry[] {
  if (state.board === undefined) return [];
  return state.showsLastWeek ? (state.board.featured?.entries ?? []) : state.board.top;
}

/** Moves to a section, closing any crew page and edit form. */
export function showSection(state: CrewsState, section: CrewSection): CrewsState {
  return { ...state, section, viewing: undefined, editing: false };
}

/** My crew came back from the server (or I left it). */
export function didLoadMine(state: CrewsState, crew: CrewDetail | undefined, week: CrewWeek): CrewsState {
  const viewing = state.viewing !== undefined && crew !== undefined && state.viewing.summary.id === crew.summary.id ? crew : state.viewing;
  return { ...state, mine: crew, week, mineLoaded: true, loadError: undefined, editing: crew === undefined ? false : state.editing, viewing };
}

export function didLoadBoard(state: CrewsState, board: CrewBoard): CrewsState {
  return { ...state, board, week: board.week, loadError: undefined, showsLastWeek: board.featured === undefined ? false : state.showsLastWeek };
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
  return text.split(/\r\n|\r|\n/).join(" ").trim();
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
    case "crew_limit":
      return tr("You've made a lot of crews today. Try again tomorrow.");
    default:
      return partyErrorMessage(error);
  }
}
