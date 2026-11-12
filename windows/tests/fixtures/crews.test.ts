import { describe, expect, it } from "vitest";
import { ACTIVITY_KINDS, ACTIVITY_UNITS, makeActivityRecord } from "../../src/core/activity/activityRecord";
import { CREW_COLORS, crewIcons, crewPetColor, findCrewInvite, resolvedCrewColor, resolvedCrewIcon } from "../../src/core/crews/crewCatalog";
import {
  blockCrewMember,
  createCrew,
  crewBoard,
  crewPage,
  joinCrewByID,
  joinCrewByInvite,
  leaveCrew,
  myCrew,
  removeCrewMember,
  reportCrew,
  reportCrewSessions,
  searchCrews,
  setShowsPet,
  updateCrew,
} from "../../src/core/crews/crewClient";
import { crewHoursValue, crewRemainingValue } from "../../src/core/crews/crewFormat";
import { composeCrewIcon, crewIconIDs, crewIconPalette } from "../../src/core/crews/crewIconArt";
import {
  crewIsFull,
  crewWeekContaining,
  memberPartyProfile,
  readCrewBoard,
  readCrewDetail,
  readCrewSessionsReply,
  readCrewSummary,
  readCrewWeek,
  type CrewBoardEntry,
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
  hours: { minutes: number; form: string; value: number }[];
  remaining: { seconds: number; form: string; values: number[] }[];
  weeks: { at: number; week: CrewWeek }[];
  queue: { name: string; records: number[][]; pending: number[][] }[];
  drafts: { name: string; description: string; problem?: string }[];
  invites: { text: string; code?: string }[];
}

interface IconsFixture {
  canvas: number;
  icons: { id: string; plain: string[]; laurel: string[] }[];
  palettes: Record<string, Record<string, Record<string, string>>>;
}

const fixture = loadFixture<CrewsFixture>("crews/crews.json");
const icons = loadFixture<IconsFixture>("crews/icons.json");
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
  create: (c) => createCrew(c, "Night Owls", "Late study sessions.", crewIcons()[0] ?? "", "indigo", "private"),
  "update name and visibility": (c) => updateCrew(c, { name: "Night Owls 2", visibility: "public" }),
  "hide my pet": (c) => setShowsPet(c, false),
  "join by invite": (c) => joinCrewByInvite(c, "w4ln-ut7"),
  "join a public crew": (c) => joinCrewByID(c, "MEDSQUAD2K"),
  leave: (c) => leaveCrew(c),
  "remove a member": (c) => removeCrewMember(c, "MAYAREF4QR"),
  search: (c) => searchCrews(c, "night owls+"),
  board: (c) => crewBoard(c),
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
const crew = (c: CrewSummary) =>
  `crew ${c.id} "${c.name}" icon=${resolvedCrewIcon(c.icon)} color=${resolvedCrewColor(c.color).id} ` +
  `${c.visibility} laurel=${c.laurel ?? "none"} trophies=${c.trophies} ` +
  `members=${c.memberCount}/${c.maxMembers} minutes=${c.weekMinutes} full=${bool(crewIsFull(c))}`;
function detail(d: CrewDetail): string[] {
  return [
    `${crew(d.summary)} rank=${d.rank ?? "none"} mine=${bool(d.mine)} owner=${bool(d.owner)} invite=${d.inviteCode ?? "none"} hidden=${bool(d.hidden)} medals=${d.medals.gold}/${d.medals.silver}/${d.medals.bronze}`,
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
const entry = (e: CrewBoardEntry) => `#${e.rank} ${e.minutes} ${crew(e.crew)}`;

function summary(json: JSONValue, schema: string): string[] {
  const reply = read.record(json, "reply");
  switch (schema) {
    case "mineReply": {
      const mine = read.optionalObject(reply, "crew", readCrewDetail);
      return [week(readCrewWeek(reply.week)), ...(mine === undefined ? ["no crew"] : detail(mine))];
    }
    case "crewReply":
    case "joinReply":
    case "removeReply": {
      const joined = read.optional(reply, "joined", read.boolean);
      return [...(joined === undefined ? [] : [`joined=${bool(joined)}`]), ...detail(readCrewDetail(reply.crew))];
    }
    case "boardReply": {
      const board = readCrewBoard(reply);
      return [
        week(board.week),
        ...board.top.map(entry),
        ...(board.featured === undefined ? ["no featured"] : [`featured ${week(board.featured.week)}`, ...board.featured.entries.map(entry)]),
      ];
    }
    case "searchReply":
      return read.array(reply, "crews").map(readCrewSummary).map(crew);
    case "sessionsReply": {
      const r = readCrewSessionsReply(reply);
      return [week(r.week), `crew=${r.crewMinutes ?? "none"} me=${r.myMinutes}`, ...r.results.map((result) => `${result.status} ${result.credited}`)];
    }
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
    for (const recorded of fixture.hours) expect(crewHoursValue(recorded.minutes), String(recorded.minutes)).toEqual({ form: recorded.form, value: recorded.value });
  });

  it("counts the week down in the recorded forms", () => {
    const end = 1_794_873_600;
    for (const recorded of fixture.remaining) {
      const value = crewRemainingValue(end, end - recorded.seconds);
      expect({ form: value.form, values: [...value.values] }, String(recorded.seconds)).toEqual({ form: recorded.form, values: recorded.values });
    }
  });

  /* The Mac's fixture encoder writes a Date as seconds since 2001 (Foundation's reference date), so the recorded week is shifted back to unix seconds. */
  const REFERENCE_DATE = 978_307_200;

  it("finds the recorded crew weeks", () => {
    for (const recorded of fixture.weeks) {
      const unix = { id: recorded.week.id, startsAt: recorded.week.startsAt + REFERENCE_DATE, endsAt: recorded.week.endsAt + REFERENCE_DATE };
      expect(crewWeekContaining(recorded.at), String(recorded.at)).toEqual(unix);
    }
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

describe("crew icons fixture", () => {
  it("lists the same icons on the same canvas", () => {
    expect(crewIconIDs()).toEqual(icons.icons.map((icon) => icon.id));
  });

  it.each(icons.icons.map((icon) => [icon.id, icon] as const))("composes %s", (_, recorded) => {
    const rows = (pixels: (string | undefined)[]) =>
      Array.from({ length: icons.canvas }, (__, y) => pixels.slice(y * icons.canvas, (y + 1) * icons.canvas).map((c) => c ?? ".").join(""));
    expect(rows(composeCrewIcon(recorded.id, false))).toEqual(recorded.plain);
    expect(rows(composeCrewIcon(recorded.id, true))).toEqual(recorded.laurel);
  });

  it("colors every character as recorded", () => {
    expect(Object.keys(icons.palettes).sort()).toEqual(CREW_COLORS.map((c) => c.id).sort());
    for (const color of CREW_COLORS) {
      for (const laurel of [undefined, ...CREW_LAURELS]) {
        const palette = crewIconPalette(crewPetColor(color), laurel);
        const got = Object.fromEntries([...palette].map(([c, value]) => [c, colorHex(value)]));
        expect(got, `${color.id} ${laurel ?? "none"}`).toEqual(icons.palettes[color.id]?.[laurel ?? "none"]);
      }
    }
  });
});
