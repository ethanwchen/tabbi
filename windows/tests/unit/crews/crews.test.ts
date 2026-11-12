import { describe, expect, it } from "vitest";
import {
  CREW_CATALOG_VERSION,
  CREW_LIMITS,
  crewColors,
  crewEmblems,
  crewFrames,
  crewInviteAppURL,
  crewInviteWebURL,
  parseCrewInvite,
  resolvedCrewColor,
  resolvedCrewEmblem,
  resolvedCrewFrame,
} from "../../../src/core/crews/crewCatalog";
import { crewsDemo, CREW_DEMO_SCENARIOS } from "../../../src/core/crews/crewDemo";
import { crewHours, crewNextChange, crewOrdinal, crewTenths, crewWeekLabel } from "../../../src/core/crews/crewFormat";
import { composeCrest, crewCrestArt, decodeCrewCrestSet, randomCrest } from "../../../src/core/crews/crewCrestArt";
import { CREW_LAURELS, CREW_VISIBILITIES, readCrewMember, readCrewSummary, type CrewBoardEntry } from "../../../src/core/crews/crewModels";
import { CrewSessionQueue, CREW_SESSION_MAX_AGE, decodeCrewSessionQueue, encodeCrewSessionQueue, loadCrewSessionQueue, saveCrewSessionQueue } from "../../../src/core/crews/crewSessionQueue";
import { crewErrorMessage, didLoadBoard, didLoadHall, didLoadMine, hasRequested, inCrew, isQuietWeek, myWeekEntry, popCrewScreen, showSection, weekEntries } from "../../../src/core/crews/crewsState";
import { PartyClient } from "../../../src/core/party/partyClient";
import { PartyError, partyErrorMessage } from "../../../src/core/party/partyError";
import type { PartyTransport } from "../../../src/core/party/partyTransport";
import { InMemoryDocumentStore } from "../../../src/core/persistence/documentStore";
import { loadRepoJson } from "../../support/fixtures";

interface ServerCatalog {
  version: number;
  frames: string[];
  emblems: string[];
  colors: Record<string, string>;
  visibilities: string[];
  laurels: string[];
  limits: Record<string, number>;
}

describe("crew catalog", () => {
  it("matches the server's backend/shared/crews.json", () => {
    const server = loadRepoJson<ServerCatalog>("backend/shared/crews.json");
    expect(server.version).toBe(CREW_CATALOG_VERSION);
    expect(server.frames).toEqual(crewFrames());
    expect(server.emblems).toEqual(crewEmblems());
    expect(server.colors).toEqual(Object.fromEntries(crewColors().map((color) => [color.id, color.hex])));
    expect(crewColors()).toHaveLength(10);
    expect(server.visibilities).toEqual([...CREW_VISIBILITIES]);
    expect(server.laurels).toEqual([...CREW_LAURELS]);
    expect(server.limits).toEqual({ ...CREW_LIMITS });
  });

  it("falls back to the first frame, emblem and color", () => {
    expect(resolvedCrewFrame("castle")).toBe(crewFrames()[0]);
    expect(resolvedCrewEmblem("dragon")).toBe(crewEmblems()[0]);
    expect(resolvedCrewColor("ultraviolet").id).toBe(crewColors()[0]?.id);
  });

  it("parses crew invite links strictly", () => {
    expect(parseCrewInvite("tabbi://crew/W4LNUT7")).toBe("W4LNUT7");
    expect(parseCrewInvite("https://tabbinotch.com/crew/w4ln-ut7")).toBe("W4LNUT7");
    expect(parseCrewInvite("https://tabbinotch.com/join/W4LNUT7")).toBeUndefined();
    expect(parseCrewInvite("https://evil.example/crew/W4LNUT7")).toBeUndefined();
    expect(crewInviteWebURL("W4LNUT7")).toBe("https://tabbinotch.com/crew/W4LNUT7");
    expect(crewInviteAppURL("W4LNUT7")).toBe("tabbi://crew/W4LNUT7");
  });
});

describe("crew crest set", () => {
  const row = (n: number, c = ".") => c.repeat(n);
  const base = () => ({
    schema: "crewCrests.v1",
    grid: 8,
    slot: 4,
    palette: {
      O: { role: "outline", hex: "#000000" },
      o: { role: "emblemOutline", hex: null },
      C: { role: "crewBase", hex: null },
      D: { role: "crewShade", hex: null },
      H: { role: "crewHighlight", hex: null },
      g: { role: "rankLeaf", hex: null },
      h: { role: "rankShade", hex: null },
      W: { role: "white", hex: "#FFFFFF" },
    },
    crewColors: [{ id: "red", base: "#FF0000", shade: "#800000", hi: "#FF8080", emblemOutline: "#111111" }],
    ranks: { gold: { leaf: "#FFD700", shade: "#B8860B" }, silver: { leaf: "#C0C0C0", shade: "#808080" }, bronze: { leaf: "#CD7F32", shade: "#8B4513" } },
    frames: [{ id: "box", name: "Box", slot: [2, 2], grid: Array.from({ length: 8 }, () => row(8, "C")) }],
    emblems: [{ id: "dot", name: "Dot", grid: [row(4), ".Wo.", ".oW.", row(4)] }],
    laurel: Array.from({ length: 8 }, () => row(8)),
    pip: ["W"],
    pipPositions: [[7, 0], [7, 1], [7, 2]],
  });

  it("loads a valid set and refuses broken ones", () => {
    expect(() => decodeCrewCrestSet(base())).not.toThrow();
    const broken: ((raw: ReturnType<typeof base>) => unknown)[] = [
      (raw) => ({ ...raw, schema: "crewCrests.v2" }),
      (raw) => ({ ...raw, emblems: [{ id: "dot", name: "Dot", grid: [row(4), ".Q..", row(4), row(4)] }] }),
      (raw) => ({ ...raw, emblems: [{ id: "dot", name: "Dot", grid: [row(3), row(4), row(4), row(4)] }] }),
      (raw) => ({ ...raw, frames: [{ ...raw.frames[0], slot: [5, 0] }] }),
      (raw) => ({ ...raw, frames: [] }),
      (raw) => ({ ...raw, crewColors: [{ id: "red", base: "#FF0000", shade: "#800000", hi: "#FF8080" }] }),
      (raw) => ({ ...raw, crewColors: [{ ...raw.crewColors[0], sparkle: "#FFFFFF" }] }),
      (raw) => ({ ...raw, ranks: { gold: raw.ranks.gold } }),
      (raw) => ({ ...raw, pipPositions: [[8, 0]] }),
    ];
    for (const change of broken) expect(() => decodeCrewCrestSet(change(base()))).toThrow();
  });

  it("composes laurel, frame, emblem and pips in order", () => {
    const set = decodeCrewCrestSet(base());
    const pixels = composeCrest({ frame: "box", emblem: "dot", color: "red" }, false, 2, set);
    expect(pixels.slice(3 * 8, 4 * 8).join("")).toBe("CCCWoCCC");
    expect(pixels[7]).toBe("W");
    expect(pixels[15]).toBe("W");
    expect(pixels[23]).toBe("C");
    /* Unknown ids draw the first frame and emblem. */
    expect(composeCrest({ frame: "castle", emblem: "dragon", color: "x" }, false, 0, set)).toEqual(composeCrest({ frame: "box", emblem: "dot", color: "red" }, false, 0, set));
  });

  it("centers smaller emblems in the frame's slot", () => {
    const shipped = loadRepoJson<Record<string, unknown>>("Sources/TabbiKitCore/Pets/PetArt/crew.json");
    const emblems = shipped.emblems as Record<string, unknown>[];
    const art = decodeCrewCrestSet({ ...shipped, emblems: [{ ...emblems[0], grid: ["WW", "WW"] }, ...emblems.slice(1)] });
    const frame = art.frames[0];
    const emblem = art.emblems[0];
    const color = art.colorIDs[0];
    if (frame === undefined || emblem === undefined || color === undefined) throw new Error("the shipped art has a frame, emblem and color");
    const pixels = composeCrest({ frame: frame.id, emblem: emblem.id, color }, false, 0, art);
    const x = frame.slot.x + Math.floor((art.slot - 2) / 2);
    const y = frame.slot.y + Math.floor((art.slot - 2) / 2);
    for (const [dx, dy] of [[0, 0], [1, 0], [0, 1], [1, 1]] as const) expect(pixels[(y + dy) * art.grid + x + dx]).toBe("W");
  });

  it("refuses emblems larger than the slot or with uneven rows", () => {
    const raw = base();
    expect(() => decodeCrewCrestSet({ ...raw, emblems: [{ id: "big", name: "Big", grid: Array.from({ length: 5 }, () => "WWWWW") }] })).toThrow();
    expect(() => decodeCrewCrestSet({ ...raw, emblems: [{ id: "odd", name: "Odd", grid: ["WW", "W"] }] })).toThrow();
    expect(() => decodeCrewCrestSet({ ...raw, emblems: [{ id: "one", name: "One", grid: ["W"] }] })).not.toThrow();
  });

  it("shuffles to real crests", () => {
    const art = crewCrestArt();
    const crest = randomCrest(() => 0.999);
    expect(art.frames.at(-1)?.id).toBe(crest.frame);
    expect(art.emblems.at(-1)?.id).toBe(crest.emblem);
    expect(art.colorIDs.at(-1)).toBe(crest.color);
  });
});

describe("crew models", () => {
  it("reads newer values leniently", () => {
    const summary = readCrewSummary({ id: "NGHTQWLS2K", name: "N", frame: "x", emblem: "z", color: "y", visibility: "unlisted", laurel: "platinum", memberCount: 2 });
    expect(summary.visibility).toBe("private");
    expect(summary.laurel).toBeUndefined();
    expect(summary.maxMembers).toBe(20);
    const member = readCrewMember({ ref: "R", name: "N", pet: null });
    expect(member.pet).toBeUndefined();
    expect(member.weekMinutes).toBe(0);
  });
});

describe("crew session queue", () => {
  it("keeps each stretch once, batches, prunes and persists", async () => {
    const t = 1_794_300_000;
    const queue = new CrewSessionQueue();
    queue.add({ start: t, end: t + 1500, minutes: 25 });
    queue.add({ start: t + 1200, end: t + 2400, minutes: 20 });
    expect(queue.pending).toEqual([{ start: t, end: t + 2400, minutes: 40 }]);
    for (let i = 0; i < 30; i++) queue.add({ start: t + 10_000 + i * 4000, end: t + 11_000 + i * 4000, minutes: 10 });
    expect(queue.nextBatch.length).toBe(CREW_LIMITS.maxSessionsPerReport);
    queue.didSend(queue.nextBatch);
    expect(queue.pending.length).toBe(11);
    queue.prune(t + CREW_SESSION_MAX_AGE + 200_000);
    expect(queue.pending.length).toBeLessThan(11);

    const documents = new InMemoryDocumentStore();
    expect((await loadCrewSessionQueue(documents)).pending).toEqual([]);
    await saveCrewSessionQueue(documents, queue);
    expect((await loadCrewSessionQueue(documents)).pending).toEqual(queue.pending);
    expect(JSON.parse(encodeCrewSessionQueue(queue)).schemaVersion).toBe(1);
    expect(decodeCrewSessionQueue("not json").pending).toEqual([]);
  });
});

describe("crews state", () => {
  it("navigates and follows replies", () => {
    let state = crewsDemo("crew", 1_794_300_000);
    expect(state.pushed?.kind).toBe("crew");
    state = popCrewScreen(state);
    expect(state.pushed).toBeUndefined();
    expect(state.section).toBe("week");
    state = showSection({ ...state, pushed: { kind: "editor", editing: true, from: "mine" } }, "find");
    expect(state.pushed).toBeUndefined();
    expect(state.section).toBe("find");
    state = didLoadMine({ ...state, pushed: { kind: "editor", editing: true, from: "mine" } }, undefined, state.week);
    expect(state.pushed).toBeUndefined();
    expect(inCrew(state)).toBe(false);
  });

  it("keeps a request only while I am in no crew", () => {
    const demo = crewsDemo("requested", 1_794_300_000);
    const request = demo.myRequest;
    if (request === undefined) throw new Error("the demo has a request");
    expect(hasRequested(demo, request.crew.id)).toBe(true);
    const mine = crewsDemo("mine", 1_794_300_000).mine;
    expect(didLoadMine(demo, mine, demo.week, request).myRequest).toBeUndefined();
    expect(didLoadMine(demo, undefined, demo.week, request).myRequest).toEqual(request);
  });

  it("appends board and hall pages without repeats", () => {
    const state = crewsDemo("week", 1_794_300_000);
    const board = state.board;
    if (board === undefined) throw new Error("the demo has a board");
    const more = didLoadBoard(state, { ...board, rows: [...board.rows.slice(-1), { ...(board.rows[0] as CrewBoardEntry), crew: { ...(board.rows[0] as CrewBoardEntry).crew, id: "NEWCREW222" } }], next: undefined }, true);
    expect(more.board?.rows.length).toBe(board.rows.length + 1);
    expect(more.board?.next).toBeUndefined();
    expect(weekEntries(more).length).toBe(board.top.length + board.rows.length + 1);
    expect(myWeekEntry(more)?.rank).toBe(12);
    const hall = state.hall ?? [];
    const page = didLoadHall(state, { entries: hall.slice(0, 2), next: "next", mine: { rank: undefined, medals: { gold: 0, silver: 0, bronze: 0 }, reachedAt: undefined } });
    expect(page.hall?.length).toBe(2);
    expect(page.hallMine?.rank).toBeUndefined();
    expect(didLoadHall(page, { entries: hall, next: undefined, mine: undefined }, true).hall?.length).toBe(hall.length);
  });

  it("knows a quiet week", () => {
    expect(isQuietWeek(crewsDemo("quietWeek", 1_794_300_000))).toBe(true);
    expect(isQuietWeek(crewsDemo("week", 1_794_300_000))).toBe(false);
    expect(isQuietWeek(crewsDemo("loading", 1_794_300_000))).toBe(false);
  });

  it("ties share a place and name each other", () => {
    const board = crewsDemo("tie", 1_794_300_000).board;
    const tied = board?.rows.filter((row) => row.tiedWith.length > 0) ?? [];
    expect(tied.map((row) => row.rank)).toEqual([5, 5]);
    expect(tied[0]?.tiedWith).toEqual([tied[1]?.crew.name]);
  });

  it("has every demo screen", () => {
    for (const scenario of CREW_DEMO_SCENARIOS) expect(crewsDemo(scenario, 1_794_300_000).mineLoaded).toBe(true);
  });

  it("explains crew errors in friendly words", () => {
    expect(crewErrorMessage(PartyError.fromServer("in_crew", 409, undefined))).not.toBe(partyErrorMessage(PartyError.fromServer("in_crew", 409, undefined)));
    expect(crewErrorMessage(PartyError.of("unreachable"))).toBe(partyErrorMessage(PartyError.of("unreachable")));
  });

  it("ticks the countdown when its text changes", () => {
    const week = { id: "w", startsAt: 0, endsAt: 1_000_000 };
    const now = 1_000_000 - 3 * 86_400 - 1_800;
    expect(crewNextChange(week, now) - now).toBe(1_800);
    expect(crewNextChange(week, 1_000_000 - 90) - (1_000_000 - 90)).toBe(30);
  });
});

describe("crews pulse and formats", () => {
  const presence = { status: "studying", sessionMinutes: 25, todayMinutes: 40, streakDays: 2, day: "2026-11-12", lastSeen: 1_794_300_000 };
  const heartbeat = async (body: unknown) => {
    const transport: PartyTransport = async () => ({ status: 200, body: JSON.stringify({ ok: true, ...(body as object) }) });
    return new PartyClient(transport, "token").heartbeat({ status: "studying" });
  };

  it("reads the heartbeat's crews pulse, and none from an older server", async () => {
    expect((await heartbeat({ presence, heartbeatSeconds: 60, crews: { requests: 2, crew: "PQMQDQRQ2S" } })).crews).toEqual({ requests: 2, crew: "PQMQDQRQ2S" });
    expect((await heartbeat({ presence, heartbeatSeconds: 60, crews: { requests: 0 } })).crews).toEqual({ requests: 0, crew: undefined });
    expect((await heartbeat({ presence, heartbeatSeconds: 60 })).crews).toBeUndefined();
  });

  it("writes hours in tenths at every size", () => {
    expect(crewTenths(599)).toBe(99);
    expect(crewTenths(2_376)).toBe(396);
    expect(crewTenths(-5)).toBe(0);
    expect(crewHours(2_376, "en")).toBe("39.6 h");
  });

  it("writes places as each language does", () => {
    expect([1, 2, 3, 4, 11, 12, 21, 22, 23, 101].map((n) => crewOrdinal(n, "en"))).toEqual(["1st", "2nd", "3rd", "4th", "11th", "12th", "21st", "22nd", "23rd", "101st"]);
    expect(crewOrdinal(12, "de")).toBe("12.");
    expect(crewOrdinal(12, "ja")).toBe("第12");
    expect(crewOrdinal(12, "ar")).toBe("12");
    expect(crewOrdinal(1, "fr")).toBe("1er");
    expect(crewOrdinal(2, "fr")).toBe("2e");
  });

  it("labels a week of the history by its ISO number", () => {
    expect(crewWeekLabel({ id: "2026-W45", startsAt: 0, endsAt: 1 })).toBe("Wk 45");
  });
});
