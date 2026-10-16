import { describe, expect, it } from "vitest";
import { InMemoryDocumentStore } from "../../../src/core/persistence/documentStore";
import { PLANNED_EVENT_NOTE } from "../../../src/core/planner/dayPlanProposal";
import { isPlannedBlockEvent, PlannedBlocksRepository, PlannedBlocksStore } from "../../../src/modules/planner/plannedBlocks";

/* 2026-10-15 09:00 UTC. */
const MORNING = 1_792_054_800;

describe("PlannedBlocksStore", () => {
  it("keeps accepted blocks per day, saves them versioned, and reads them back as events", async () => {
    const documents = new InMemoryDocumentStore();
    const repository = new PlannedBlocksRepository(documents);
    const store = new PlannedBlocksStore(repository, () => "UTC");
    await store.writer().write([
      { title: "Read chapter 4", start: MORNING, end: MORNING + 1800, notes: PLANNED_EVENT_NOTE },
      { title: "Tomorrow's block", start: MORNING + 86400, end: MORNING + 86400 + 1500, notes: PLANNED_EVENT_NOTE },
    ]);
    const text = await documents.read("Plans/2026-10-15.json");
    expect(text).toBeDefined();
    const document = JSON.parse(text ?? "{}") as { schemaVersion: number; blocks: { title: string; start: string }[] };
    expect(document.schemaVersion).toBe(1);
    expect(document.blocks.map((block) => block.title)).toEqual(["Read chapter 4"]);
    expect(document.blocks[0]?.start).toBe("2026-10-15T09:00:00Z");

    const fresh = new PlannedBlocksStore(repository, () => "UTC");
    const events = await fresh.events(MORNING - 3600, MORNING + 2 * 86400);
    expect(events.map((event) => event.title)).toEqual(["Read chapter 4", "Tomorrow's block"]);
    expect(events.every(isPlannedBlockEvent)).toBe(true);
    expect(await fresh.events(MORNING + 1800, MORNING + 3600)).toEqual([]);
  });

  it("treats a corrupt day file as an empty day instead of failing the plan", async () => {
    const documents = new InMemoryDocumentStore();
    await documents.write("Plans/2026-10-15.json", "{\"schemaVersion\":1,\"date\":\"2026-10-15\",\"blocks\":\"nope\"}");
    const store = new PlannedBlocksStore(new PlannedBlocksRepository(documents), () => "UTC");
    expect(await store.blocks("2026-10-15")).toEqual([]);
  });

  it("keeps everything in memory without a repository", async () => {
    const store = new PlannedBlocksStore(undefined, () => "UTC");
    await store.add([{ title: "Essay", start: MORNING, end: MORNING + 900, notes: PLANNED_EVENT_NOTE }]);
    expect(store.known("2026-10-15").map((block) => block.title)).toEqual(["Essay"]);
  });
});
