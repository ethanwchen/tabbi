import { describe, expect, it } from "vitest";
import { ACTIVITY_KINDS, ACTIVITY_UNITS, makeActivityRecord } from "../../src/core/activity/activityRecord";
import { crewColors, crewEmblems, crewFrames, findCrewInvite } from "../../src/core/crews/crewCatalog";
import {
  approveJoinRequest,
  blockCrewMember,
  cancelJoinRequest,
  createCrew,
  crewBoard,
  crewHall,
  crewPage,
  declineJoinRequest,
  joinCrewByInvite,
  leaveCrew,
  myCrew,
  removeCrewMember,
  reportCrew,
  reportCrewSessions,
  requestToJoin,
  searchCrews,
  setShowsPet,
  updateCrew,
} from "../../src/core/crews/crewClient";
import { crewTenths, crewRemainingValue } from "../../src/core/crews/crewFormat";
import { composeCrest, crestPalette, resolvedCrest } from "../../src/core/crews/crewCrestArt";
import {
  crewCrest,
  crewIsFull,
  crewPips,
  crewWeekContaining,
  memberPartyProfile,
  readCrewBoard,
  readCrewDetail,
  readCrewHallPage,
  readCrewMyRequest,
  readCrewSessionsReply,
  readCrewSummary,
  readCrewWeek,
  type CrewBoardEntry,
  type CrewMyRequest,
  type CrewDetail,
  type CrewSummary,
  type CrewWeek,
} from "../../src/core/crews/crewModels";
import { CrewSessionQueue, crewSessionFor } from "../../src/core/crews/crewSessionQueue";
import { crewDraftProblem } from "../../src/core/crews/crewsState";
import { PartyClient } from "../../src/core/party/partyClient";
import { read } from "../../src/core/party/partyModels";
import { partyPet } from "../../src/core/party/partyPetAppearance";
import type { PartyHttpRequest, PartyTransport } from "../../src/core/party/partyTransport";
import { PROTOCOL_HEADER, PROTOCOL_VERSION } from "../../src/core/party/partyWire";
import { CREW_LAURELS } from "../../src/core/crews/crewModels";
import { colorHex } from "../../src/core/pets/petPalette";
import { loadFixture } from "../support/fixtures";

/*
 * Replays shared/fixtures/crews (written by CrewsGoldenTests on the Mac):
 * the Study Crews contract both apps follow. The requests this client sends
 * for the same calls, the summary lines of every sample reply, the board's
 * hours and countdown forms, crew weeks, the session queue, the draft
 * checks, invite links, and every icon's characters and palettes.
 */

type JSONValue = null | boolean | number | string | JSONValue[] | { [key: string]: JSONValue };

interface CrewsFixture {
  protocol: number;
  requests: { name: string; method: string; path: string; schema?: string; body?: JSONValue }[];
  replies: { name: string; schema: string; json: JSONValue; summary: string[] }[];
  hours: { minutes: number; tenths: number }[];
  remaining: { seconds: number; form: string; values: number[] }[];
  weeks: { at: number; week: CrewWeek }[];
  queue: { name: string; records: number[][]; pending: number[][] }[];
  drafts: { name: string; description: string; problem?: string }[];
  invites: { text: string; code?: string }[];
}

interface CrestsFixture {
  grid: number;
  cases: { frame: string; emblem: string; color: string; laurel?: string; pips: number; rows: string[] }[];
  palettes: Record<string, Record<string, Record<string, string>>>;
}

const fixture = loadFixture<CrewsFixture>("crews/crews.json");
const crests = loadFixture<CrestsFixture>("crews/crests.json");
const TOKEN = "a".repeat(64);

function recordingClient(): { client: PartyClient; sent: PartyHttpRequest[] } {
  const sent: PartyHttpRequest[] = [];
  const transport: PartyTransport = async (request) => {
    sent.push(request);
    return { status: 200, body: '{"ok":true}' };
  };
  return { client: new PartyClient(transport, TOKEN), sent };
}

const at = 1_793_000_000;
const CALLS: Record<string, (client: PartyClient) => Promise<unknown>> = {
  create: (c) => createCrew(c, "Night Owls", "Late study sessions.", { frame: crewFrames()[0] ?? "", emblem: crewEmblems()[0] ?? "", color: "indigo" }, "private"),
  "update name and visibility": (c) => updateCrew(c, { name: "Night Owls 2", visibility: "public" }),
  "update the crest": (c) => updateCrew(c, { frame: crewFrames().at(-1) ?? "", emblem: crewEmblems().at(-1) ?? "", color: "teal" }),
  "hide my pet": (c) => setShowsPet(c, false),
  "join by invite": (c) => joinCrewByInvite(c, "w4ln-ut7"),
  "ask to join a public crew": (c) => requestToJoin(c, "MEDSQUAD2K"),
  "cancel my request": (c) => cancelJoinRequest(c),
  "approve a request": (c) => approveJoinRequest(c, "LENAREF3QW"),
  "decline a request": (c) => declineJoinRequest(c, "LENAREF3QW"),
  "board, next page": (c) => crewBoard(c, "eyJyIjo1fQ"),
  leave: (c) => leaveCrew(c),
  "remove a member": (c) => removeCrewMember(c, "MAYAREF4QR"),
  search: (c) => searchCrews(c, "night owls+"),
  board: (c) => crewBoard(c),
  "hall of fame": (c) => crewHall(c),
  "hall of fame, next page": (c) => crewHall(c, "eyJnIjoxfQ+/="),
  mine: (c) => myCrew(c),
  "crew page": (c) => crewPage(c, "MEDSQUAD2K"),
  sessions: (c) =>
    reportCrewSessions(c, [
      { start: at, end: at + 1500, minutes: 25 },
      { start: at + 1800, end: at + 4800, minutes: 48 },
    ]),
  "report a crew": (c) => reportCrew(c, "MEDSQUAD2K", undefined, "inappropriate_name", "  "),
  "report a member": (c) => reportCrew(c, "MEDSQUAD2K", "AVAREF7K3R", "cheating", "Reports 16 hours every day."),
  "block a member": (c) => blockCrewMember(c, "MEDSQUAD2K", "AVAREF7K3R"),
};

/* MARK: Summary lines, as CrewsFixture.summary(of:schema:) writes them */

const bool = (value: boolean) => (value ? "true" : "false");
const week = (w: CrewWeek) => `week ${w.id} ${Math.trunc(w.startsAt)}-${Math.trunc(w.endsAt)}`;
const crew = (c: CrewSummary) => {
  const crest = resolvedCrest(crewCrest(c));
  return (
  `crew ${c.id} "${c.name}" crest=${crest.frame}/${crest.emblem}/${crest.color} pips=${crewPips(c)} ` +
  `${c.visibility} laurel=${c.laurel ?? "none"} trophies=${c.trophies} golds=${c.golds} ` +
  `members=${c.memberCount}/${c.maxMembers} minutes=${c.weekMinutes} full=${bool(crewIsFull(c))}`
  );
};
function detail(d: CrewDetail): string[] {
  return [
    `${crew(d.summary)} rank=${d.rank ?? "none"} mine=${bool(d.mine)} owner=${bool(d.owner)} invite=${d.inviteCode ?? "none"} hidden=${bool(d.hidden)} medals=${d.medals.gold}/${d.medals.silver}/${d.medals.bronze} crews=${d.crewCount}`,
    ...d.history.map((h) => `week ${h.week.id} place=${h.place ?? "none"} minutes=${h.minutes} medal=${h.medal ?? "none"}`),
    ...d.requests.map((r) => `request ${r.ref} "${r.name}" pet=${r.pet?.petName ?? "hidden"} at=${Math.trunc(r.requestedAt)}-${Math.trunc(r.expiresAt)}`),
    ...d.members.map((m) => {
      const profile = memberPartyProfile(m);
      let pet = "pet=hidden";
      if (profile !== undefined) {
        const drawn = partyPet(profile);
        pet = `pet="${profile.petName}" ${drawn.breed} outfit=${drawn.outfit} accessories=${drawn.accessories.join(",")}`;
      }
      return `member ${m.ref} "${m.name}" ${pet} level=${m.studyLevel ?? "none"} minutes=${m.weekMinutes} owner=${bool(m.owner)} me=${bool(m.me)}`;
    }),
  ];
}
const entry = (e: CrewBoardEntry) => `#${e.rank} ${e.minutes} pets=${e.pets.map((p) => p.petName).join(",")} tied=${e.tiedWith.join(",")} ${crew(e.crew)}`;
const waiting = (r: CrewMyRequest | undefined) => (r === undefined ? [] : [`waiting ${r.crew.id} at=${Math.trunc(r.requestedAt)}-${Math.trunc(r.expiresAt)}`]);

function summary(json: JSONValue, schema: string): string[] {
  const reply = read.record(json, "reply");
  switch (schema) {
    case "mineReply": {
      const mine = read.optionalObject(reply, "crew", readCrewDetail);
      return [week(readCrewWeek(reply.week)), ...(mine === undefined ? ["no crew"] : detail(mine)), ...waiting(read.optionalObject(reply, "request", readCrewMyRequest))];
    }
    case "crewReply":
    case "joinReply":
    case "removeReply": {
      const joined = read.optional(reply, "joined", read.boolean);
      return [...(joined === undefined ? [] : [`joined=${bool(joined)}`]), ...waiting(read.optionalObject(reply, "request", readCrewMyRequest)), ...detail(readCrewDetail(reply.crew))];
    }
    case "boardReply": {
      const board = readCrewBoard(reply);
      return [
        week(board.week),
        `crews=${board.crewCount} next=${board.next ?? "none"}`,
        `mine=${board.mine === undefined ? "none" : `${board.mine.rank ?? "none"}/${board.mine.minutes}`}`,
        ...board.top.map(entry),
        ...board.rows.map((row) => `row ${entry(row)}`),
        ...(board.featured === undefined ? ["no featured"] : [`featured ${week(board.featured.week)}`, ...board.featured.entries.map(entry)]),
      ];
    }
    case "searchReply":
      return read.array(reply, "crews").map(readCrewSummary).map(crew);
    case "sessionsReply": {
      const r = readCrewSessionsReply(reply);
      return [week(r.week), `crew=${r.crewMinutes ?? "none"} me=${r.myMinutes}`, ...r.results.map((result) => `${result.status} ${result.credited}`)];
    }
    case "hallReply": {
      const page = readCrewHallPage(reply);
      return [
        ...page.entries.map((e) => `#${e.rank} ${e.medals.gold}/${e.medals.silver}/${e.medals.bronze} at=${Math.trunc(e.reachedAt)} ${crew(e.crew)}`),
        `next=${page.next ?? "none"}`,
        `mine=${page.mine === undefined ? "none" : `${page.mine.rank ?? "none"} ${page.mine.medals.gold}/${page.mine.medals.silver}/${page.mine.medals.bronze}`}`,
      ];
    }
    case "cancelReply":
      return [`cancelled=${bool(read.boolean(reply, "cancelled"))}`];
    case "declineReply":
      return [`declined=${bool(read.boolean(reply, "declined"))}`];
    case "leaveReply":
      return [`left=${bool(read.boolean(reply, "left"))}`];
    case "reportReply":
      return [`created=${bool(read.boolean(reply, "created"))}`];
    case "blockReply":
      return [`blocked=${bool(read.boolean(reply, "blocked"))}`];
    default:
      throw new Error(`no reader for ${schema}`);
  }
}

describe("crews fixture", () => {
  it("speaks protocol 3", () => {
    expect(PROTOCOL_VERSION).toBe(fixture.protocol);
  });

  describe("requests", () => {
    it.each(fixture.requests.map((request) => [request.name, request] as const))("%s", async (name, recorded) => {
      const call = CALLS[name];
      expect(call, `no call for ${name}`).toBeDefined();
      const { client, sent } = recordingClient();
      await call?.(client).catch(() => undefined);
      const request = sent[0];
      expect(request).toBeDefined();
      expect(request?.method).toBe(recorded.method);
      expect(request?.path).toBe(recorded.path);
      expect(request?.headers?.[PROTOCOL_HEADER]).toBe(String(fixture.protocol));
      const body = request?.body === undefined ? undefined : (JSON.parse(request.body) as JSONValue);
      expect(body).toEqual(recorded.body);
    });
  });

  describe("replies", () => {
    it.each(fixture.replies.map((reply) => [reply.name, reply] as const))("%s", (_, reply) => {
      expect(summary(reply.json, reply.schema)).toEqual(reply.summary);
    });
  });

  it("writes hours in the recorded forms", () => {
    for (const recorded of fixture.hours) expect(crewTenths(recorded.minutes), String(recorded.minutes)).toBe(recorded.tenths);
  });

  it("counts the week down in the recorded forms", () => {
    const end = 1_794_873_600;
    for (const recorded of fixture.remaining) {
      const value = crewRemainingValue(end, end - recorded.seconds);
      expect({ form: value.form, values: [...value.values] }, String(recorded.seconds)).toEqual({ form: recorded.form, values: recorded.values });
    }
  });

  it("finds the recorded crew weeks", () => {
    for (const recorded of fixture.weeks) expect(crewWeekContaining(recorded.at), String(recorded.at)).toEqual(recorded.week);
  });

  it.each(fixture.queue.map((c) => [c.name, c] as const))("queue: %s", (_, recorded) => {
    const queue = new CrewSessionQueue();
    for (const [start = 0, end = 0, quantity = 0] of recorded.records) {
      const session = crewSessionFor(makeActivityRecord({ source: "party", kind: ACTIVITY_KINDS.focusCompleted, start, end, quantity, unit: ACTIVITY_UNITS.minutes }));
      if (session !== undefined) queue.add(session);
    }
    expect(queue.pending.map((s) => [s.start, s.end, s.minutes])).toEqual(recorded.pending);
  });

  it("checks drafts as recorded", () => {
    for (const recorded of fixture.drafts) expect(crewDraftProblem(recorded.name, recorded.description), JSON.stringify(recorded.name)).toBe(recorded.problem);
  });

  it("reads invites as recorded", () => {
    for (const recorded of fixture.invites) expect(findCrewInvite(recorded.text), recorded.text).toBe(recorded.code);
  });
});

describe("crew crests fixture", () => {
  it.each(crests.cases.map((c, index) => [`${index} ${c.frame} ${c.emblem} ${c.color} ${c.laurel ?? "none"} ${c.pips}`, c] as const))("composes %s", (_, recorded) => {
    const pixels = composeCrest({ frame: recorded.frame, emblem: recorded.emblem, color: recorded.color }, recorded.laurel !== undefined, recorded.pips);
    const rows = Array.from({ length: crests.grid }, (__, y) => pixels.slice(y * crests.grid, (y + 1) * crests.grid).map((c) => c ?? ".").join(""));
    expect(rows).toEqual(recorded.rows);
  });

  it("colors every character as recorded", () => {
    expect(Object.keys(crests.palettes).sort()).toEqual(crewColors().map((c) => c.id).sort());
    for (const color of crewColors()) {
      for (const laurel of [undefined, ...CREW_LAURELS]) {
        const got = Object.fromEntries([...crestPalette(color.id, laurel)].map(([c, value]) => [c, colorHex(value)]));
        expect(got, `${color.id} ${laurel ?? "none"}`).toEqual(crests.palettes[color.id]?.[laurel ?? "none"]);
      }
    }
  });
});
