import { describe, expect, it } from "vitest";
import { CREW_CATALOG_VERSION, CREW_COLORS, CREW_LIMITS, crewIcons, crewInviteAppURL, crewInviteWebURL, parseCrewInvite, resolvedCrewColor, resolvedCrewIcon } from "../../../src/core/crews/crewCatalog";
import { crewsDemo, CREW_DEMO_SCENARIOS } from "../../../src/core/crews/crewDemo";
import { crewNextChange } from "../../../src/core/crews/crewFormat";
import { decodeCrewIconSet, outlined } from "../../../src/core/crews/crewIconArt";
import { CREW_LAURELS, CREW_VISIBILITIES, readCrewMember, readCrewSummary } from "../../../src/core/crews/crewModels";
import { CrewSessionQueue, CREW_SESSION_MAX_AGE, decodeCrewSessionQueue, encodeCrewSessionQueue, loadCrewSessionQueue, saveCrewSessionQueue } from "../../../src/core/crews/crewSessionQueue";
import { boardEntries, crewErrorMessage, didLoadBoard, didLoadMine, inCrew, showSection } from "../../../src/core/crews/crewsState";
import { PartyError, partyErrorMessage } from "../../../src/core/party/partyError";
import { InMemoryDocumentStore } from "../../../src/core/persistence/documentStore";
import { loadRepoJson } from "../../support/fixtures";

interface ServerCatalog {
  version: number;
  icons: string[];
  colors: Record<string, string>;
  visibilities: string[];
  laurels: string[];
  limits: Record<string, number>;
}

describe("crew catalog", () => {
  it("matches the server's backend/shared/crews.json", () => {
    const server = loadRepoJson<ServerCatalog>("backend/shared/crews.json");
    expect(server.version).toBe(CREW_CATALOG_VERSION);
    expect(server.icons).toEqual(crewIcons());
    expect(server.colors).toEqual(Object.fromEntries(CREW_COLORS.map((color) => [color.id, color.hex])));
    expect(server.visibilities).toEqual([...CREW_VISIBILITIES]);
    expect(server.laurels).toEqual([...CREW_LAURELS]);
    expect(server.limits).toEqual({ ...CREW_LIMITS });
  });

  it("falls back to the first icon and color", () => {
    expect(resolvedCrewIcon("hologram")).toBe(crewIcons()[0]);
    expect(resolvedCrewColor("ultraviolet").id).toBe("coral");
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

describe("crew icon set", () => {
  const base = {
    schema: "crew-icons.v1",
    canvas: 6,
    outline: "O",
    tint: { base: "C", shade: "D", light: "L" },
    colors: { O: "#000000", W: "#FFFFFF" },
    metals: { gold: ["#111111", "#222222", "#333333"], silver: ["#111111", "#222222", "#333333"], bronze: ["#111111", "#222222", "#333333"] },
    laurel: { base: "G", shade: "J", light: "Z", grid: Array.from({ length: 6 }, () => "......") },
    icons: [{ id: "a", grid: ["....", ".CW.", ".DL.", "...."] }],
  };

  it("loads a valid set and refuses broken ones", () => {
    expect(() => decodeCrewIconSet(base)).not.toThrow();
    expect(() => decodeCrewIconSet({ ...base, schema: "crew-icons.v2" })).toThrow();
    expect(() => decodeCrewIconSet({ ...base, icons: [{ id: "a", grid: ["....", ".CQ.", "....", "...."] }] })).toThrow();
    expect(() => decodeCrewIconSet({ ...base, icons: [{ id: "a", grid: ["...", "....", "..."] }] })).toThrow();
    expect(() => decodeCrewIconSet({ ...base, icons: [] })).toThrow();
    expect(() => decodeCrewIconSet({ ...base, icons: [{ id: "a", grid: ["C"] }, { id: "a", grid: ["C"] }] })).toThrow();
    const big = (n: number) => ({
      ...base,
      canvas: 48,
      laurel: { ...base.laurel, grid: Array.from({ length: 48 }, () => ".".repeat(48)) },
      icons: [{ id: "big", grid: Array.from({ length: n }, () => "W".repeat(n)) }],
    });
    expect(() => decodeCrewIconSet(big(40))).not.toThrow();
    expect(() => decodeCrewIconSet(big(41))).toThrow();
  });

  it("outlines around the silhouette only", () => {
    const result = outlined([undefined, undefined, undefined, undefined, "W", undefined, undefined, undefined, undefined], 3, 3, "O");
    expect(result.map((c) => c ?? ".").join("")).toBe(".O.OWO.O.");
  });
});

describe("crew models", () => {
  it("reads newer values leniently", () => {
    const summary = readCrewSummary({ id: "NGHTQWLS2K", name: "N", icon: "x", color: "y", visibility: "unlisted", laurel: "platinum", memberCount: 2 });
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
    let state = crewsDemo("viewing", 1_794_300_000);
    expect(state.viewing).toBeDefined();
    state = showSection(state, "find");
    expect(state.viewing).toBeUndefined();
    expect(state.section).toBe("find");
    state = didLoadMine({ ...state, editing: true }, undefined, state.week);
    expect(state.editing).toBe(false);
    expect(inCrew(state)).toBe(false);
    const current = state.board;
    if (current === undefined) throw new Error("the demo has a board");
    const board = { ...current, featured: undefined };
    state = didLoadBoard({ ...state, showsLastWeek: true }, board);
    expect(state.showsLastWeek).toBe(false);
    expect(boardEntries(state)).toEqual(board.top);
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
