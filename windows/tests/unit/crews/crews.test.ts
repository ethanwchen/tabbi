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
import { crewNextChange } from "../../../src/core/crews/crewFormat";
import { composeCrest, crewCrestArt, decodeCrewCrestSet, randomCrest } from "../../../src/core/crews/crewCrestArt";
import { CREW_LAURELS, CREW_VISIBILITIES, readCrewMember, readCrewSummary } from "../../../src/core/crews/crewModels";
import { CrewSessionQueue, CREW_SESSION_MAX_AGE, decodeCrewSessionQueue, encodeCrewSessionQueue, loadCrewSessionQueue, saveCrewSessionQueue } from "../../../src/core/crews/crewSessionQueue";
import { boardEntries, crewErrorMessage, didLoadBoard, didLoadMine, inCrew, showSection } from "../../../src/core/crews/crewsState";
import { PartyError, partyErrorMessage } from "../../../src/core/party/partyError";
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
