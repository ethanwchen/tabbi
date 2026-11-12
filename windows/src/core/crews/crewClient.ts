import { PartyError } from "../party/partyError";
import { read } from "../party/partyModels";
import { REPORT_NOTE_LIMIT } from "../party/partyModeration";
import type { PartyClient } from "../party/partyClient";
import { CREW_LIMITS } from "./crewCatalog";
import type { CrewCrest } from "./crewCrestArt";
import {
  CrewCode,
  readCrewBoard,
  readCrewDetail,
  readCrewHallPage,
  readCrewSessionsReply,
  readCrewSummary,
  readCrewWeek,
  type CrewBoard,
  type CrewDetail,
  type CrewDraft,
  type CrewHallPage,
  type CrewReportReason,
  type CrewSession,
  type CrewSessionsReply,
  type CrewSummary,
  type CrewVisibility,
  type CrewWeek,
} from "./crewModels";

/*
 * Port of PartyClient+Crews: the Study Crews routes (protocol 3, see
 * docs/design/crews.md and docs/study/backend-api.md). They send only what
 * the contract lists: a crew's name, description, icon, color and
 * visibility, my pet setting, and finished focus sessions as start, end and
 * minutes. Nothing about what was studied leaves the machine.
 */

function valid(code: string | undefined): string {
  if (code === undefined) throw PartyError.invalidRequest("invalid_field");
  return code;
}

/** The body of a create or edit: exactly the fields present. */
function draftBody(draft: CrewDraft): Record<string, string> {
  const body: Record<string, string> = {};
  for (const key of ["name", "description", "frame", "emblem", "color", "visibility"] as const) {
    const value = draft[key];
    if (value !== undefined) body[key] = value;
  }
  return body;
}

/*
 * A search query as Foundation's URLComponents writes it: percent-encoded,
 * except the characters a query may hold as they are, with `+` encoded too
 * (it reads as a space in a query).
 */
function encodeQuery(text: string): string {
  return encodeURIComponent(text).replace(/%(21|24|27|28|29|2A|2C|2F|3A|3B|3F|40)/g, (_, hex: string) => String.fromCharCode(parseInt(hex, 16)));
}

/** `GET /v1/crews/mine`: my crew, or undefined, and the current week. */
export async function myCrew(client: PartyClient): Promise<{ crew: CrewDetail | undefined; week: CrewWeek }> {
  const reply = await client.send("GET", "/v1/crews/mine");
  return { crew: read.optionalObject(reply, "crew", readCrewDetail), week: readCrewWeek(reply.week) };
}

/** `POST /v1/crews`: a new crew owned by me. `in_crew` while I am in one. */
export async function createCrew(client: PartyClient, name: string, description: string, crest: CrewCrest, visibility: CrewVisibility): Promise<CrewDetail> {
  const reply = await client.send("POST", "/v1/crews", { body: draftBody({ name, description, frame: crest.frame, emblem: crest.emblem, color: crest.color, visibility }) });
  return readCrewDetail(reply.crew);
}

/** `PATCH /v1/crews/mine` (owner): absent fields keep their value. */
export async function updateCrew(client: PartyClient, draft: CrewDraft): Promise<CrewDetail> {
  return readCrewDetail((await client.send("PATCH", "/v1/crews/mine", { body: draftBody(draft) })).crew);
}

/** `PATCH /v1/crews/mine/me`: whether my pet shows on crew pages. */
export async function setShowsPet(client: PartyClient, showsPet: boolean): Promise<CrewDetail> {
  return readCrewDetail((await client.send("PATCH", "/v1/crews/mine/me", { body: { showPet: showsPet } })).crew);
}

/** `POST /v1/crews/join` with an invite code. */
export async function joinCrewByInvite(client: PartyClient, invite: string): Promise<CrewDetail> {
  const code = valid(CrewCode.invite(invite));
  return readCrewDetail((await client.send("POST", "/v1/crews/join", { body: { code } })).crew);
}

/** `POST /v1/crews/join` with a public crew's id. */
export async function joinCrewByID(client: PartyClient, id: string): Promise<CrewDetail> {
  const crew = valid(CrewCode.crewID(id));
  return readCrewDetail((await client.send("POST", "/v1/crews/join", { body: { crew } })).crew);
}

/** `POST /v1/crews/leave`. False when I was not in one. */
export async function leaveCrew(client: PartyClient): Promise<boolean> {
  return read.boolean(await client.send("POST", "/v1/crews/leave", { body: {} }), "left");
}

/** `POST /v1/crews/mine/members/{ref}/remove` (owner). */
export async function removeCrewMember(client: PartyClient, ref: string): Promise<CrewDetail> {
  const valid10 = valid(CrewCode.crewID(ref));
  return readCrewDetail((await client.send("POST", `/v1/crews/mine/members/${valid10}/remove`, { body: {} })).crew);
}

/** `GET /v1/crews?q=`: public crews, most minutes this week first. */
export async function searchCrews(client: PartyClient, query: string): Promise<CrewSummary[]> {
  const trimmed = query.trim();
  let path = "/v1/crews";
  if (trimmed !== "") path += `?q=${encodeQuery([...trimmed].slice(0, CREW_LIMITS.nameMaxLength).join(""))}`;
  return read.array(await client.send("GET", path), "crews").map(readCrewSummary);
}

/** `GET /v1/crews/board`. */
export async function crewBoard(client: PartyClient): Promise<CrewBoard> {
  return readCrewBoard(await client.send("GET", "/v1/crews/board"));
}

/** `GET /v1/crews/hall?cursor=`: a page of the all-time Hall of Fame; pass the previous page's `next` for the following one. */
export async function crewHall(client: PartyClient, cursor?: string): Promise<CrewHallPage> {
  const path = cursor === undefined ? "/v1/crews/hall" : `/v1/crews/hall?cursor=${encodeQuery(cursor)}`;
  return readCrewHallPage(await client.send("GET", path));
}

/** `GET /v1/crews/{id}`: a crew page. */
export async function crewPage(client: PartyClient, id: string): Promise<CrewDetail> {
  const crew = valid(CrewCode.crewID(id));
  return readCrewDetail((await client.send("GET", `/v1/crews/${crew}`)).crew);
}

/** `POST /v1/crews/sessions`: finished focus sessions, at most a request's worth at a time. */
export async function reportCrewSessions(client: PartyClient, sessions: readonly CrewSession[]): Promise<CrewSessionsReply> {
  const body = { sessions: sessions.map((session) => ({ end: Math.round(session.end), minutes: session.minutes, start: Math.round(session.start) })) };
  return readCrewSessionsReply(await client.send("POST", "/v1/crews/sessions", { body }));
}

/** `POST /v1/crews/reports`: a crew, or one member of it by `ref`. */
export async function reportCrew(client: PartyClient, id: string, member: string | undefined, reason: CrewReportReason, note: string): Promise<boolean> {
  const trimmed = note.trim();
  const body = {
    crew: id,
    ...(member === undefined ? {} : { member }),
    reason,
    ...(trimmed === "" ? {} : { note: [...trimmed].slice(0, REPORT_NOTE_LIMIT).join("") }),
  };
  return read.boolean(await client.send("POST", "/v1/crews/reports", { body }), "created");
}

/** `POST /v1/crews/block`: blocks a crew member by `ref`, the same block as everywhere in Party. */
export async function blockCrewMember(client: PartyClient, crew: string, member: string): Promise<boolean> {
  return read.boolean(await client.send("POST", "/v1/crews/block", { body: { crew, member } }), "blocked");
}
