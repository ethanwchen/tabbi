import { describe, expect, it } from "vitest";
import {
  JOURNAL_LINES,
  PetAdventure,
  PetJournal,
  entryDetail,
  entryText,
  journalSentence,
  phaseDistance,
  phaseIsOut,
} from "../../../src/core/pets/petAdventure";
import { InMemoryDocumentStore } from "../../../src/core/persistence/documentStore";
import { ProvidedFocus } from "../../../src/core/providers/providedFocus";
import type { FocusPhase } from "../../../src/core/focus/focusTimer";
import { REFERENCE_DATE_OFFSET } from "../../../src/core/pets/petUnlocks";

// Port of PetAdventureTests.swift.

const start = 813_000_000 + REFERENCE_DATE_OFFSET;

function focus(minutes: number, phase: FocusPhase = "focus"): ProvidedFocus {
  return new ProvidedFocus({ source: "focus", phase, clock: { kind: "countdown", endsAt: start + minutes * 60 }, phaseLength: minutes * 60, completedFocusCount: 0 });
}

function plan(block: ProvidedFocus): PetAdventure {
  const adventure = PetAdventure.plan(block, false);
  if (!adventure) throw new Error("no adventure");
  return adventure;
}

function roundTrip(journal: PetJournal): PetJournal {
  return PetJournal.fromJSON(JSON.parse(JSON.stringify(journal.toJSON())));
}

describe("PetAdventure", () => {
  it("plans an adventure for a long focus block", () => {
    const adventure = plan(focus(25));
    const length = 25 * 60;
    const departs = (adventure.departsAt - start) / length;
    expect(departs).toBeGreaterThanOrEqual(PetAdventure.departureRange.lower);
    expect(departs).toBeLessThanOrEqual(PetAdventure.departureRange.upper);
    expect(adventure.endsAt).toBe(start + length);
    expect(adventure.returnsAt).toBe(adventure.endsAt - PetAdventure.walkDuration);
  });

  it("keeps the pet home", () => {
    expect(PetAdventure.plan(focus(14), false), "short block").toBeUndefined();
    expect(PetAdventure.plan(focus(15), false)).toBeDefined();
    expect(PetAdventure.plan(focus(25), true), "Reduce Motion").toBeUndefined();
    expect(PetAdventure.plan(focus(25, "rest"), false), "break").toBeUndefined();
    expect(PetAdventure.plan(undefined, false)).toBeUndefined();
    const paused = new ProvidedFocus({ source: "focus", phase: "focus", clock: { kind: "paused", shown: 600 }, phaseLength: 1500, completedFocusCount: 0 });
    expect(PetAdventure.plan(paused, false)).toBeUndefined();
    const open = new ProvidedFocus({ source: "study", phase: "focus", clock: { kind: "countUp", since: start }, completedFocusCount: 0 });
    expect(PetAdventure.plan(open, false)).toBeUndefined();
  });

  it("departs at the same moment for the same block and varies across blocks", () => {
    expect(plan(focus(25))).toEqual(plan(focus(25)));
    const departures = new Set(
      Array.from({ length: 10 }, (_, offset) => {
        const block = new ProvidedFocus({
          source: "focus",
          phase: "focus",
          clock: { kind: "countdown", endsAt: start + offset * 3600 + 1500 },
          phaseLength: 1500,
          completedFocusCount: 0,
        });
        return plan(block).departsAt - offset * 3600;
      }),
    );
    expect(departures.size).toBeGreaterThan(1);
  });

  it("walks through the phases of the block", () => {
    const block = focus(25);
    const adventure = plan(block);
    const walk = PetAdventure.walkDuration;
    expect(adventure.phase(start)).toEqual({ kind: "home" });
    expect(adventure.phase(adventure.departsAt - 1)).toEqual({ kind: "home" });
    expect(adventure.phase(adventure.departsAt)).toEqual({ kind: "leaving", progress: 0 });
    expect(adventure.phase(adventure.departsAt + walk / 2)).toEqual({ kind: "leaving", progress: 0.5 });
    expect(adventure.phase(adventure.departsAt + walk)).toEqual({ kind: "away" });
    expect(adventure.phase(adventure.returnsAt - 1)).toEqual({ kind: "away" });
    expect(adventure.phase(adventure.returnsAt)).toEqual({ kind: "returning", progress: 0 });
    expect(adventure.phase(adventure.endsAt)).toEqual({ kind: "home" });
    expect(phaseIsOut({ kind: "away" })).toBe(true);
    expect(phaseIsOut({ kind: "home" })).toBe(false);
    expect(PetAdventure.phaseFor(block, adventure.departsAt + 60, true)).toEqual({ kind: "home" });
  });

  it("walks the next change through every boundary", () => {
    const adventure = plan(focus(25));
    expect(adventure.nextChange(start)).toBe(adventure.departsAt);
    expect(adventure.nextChange(adventure.departsAt)).toBe(adventure.departsAt + PetAdventure.walkDuration);
    expect(adventure.nextChange(adventure.departsAt + 60)).toBe(adventure.returnsAt);
    expect(adventure.nextChange(adventure.returnsAt)).toBe(adventure.endsAt);
    expect(adventure.nextChange(adventure.endsAt)).toBeUndefined();
  });

  it("follows the walk with distance and exploring", () => {
    const adventure = plan(focus(25));
    const walk = PetAdventure.walkDuration;
    expect(phaseDistance({ kind: "home" })).toBe(0);
    expect(phaseDistance({ kind: "leaving", progress: 0.25 })).toBe(0.25);
    expect(phaseDistance({ kind: "away" })).toBe(1);
    expect(phaseDistance({ kind: "returning", progress: 0.25 })).toBe(0.75);
    expect(adventure.isExploring(adventure.departsAt - 1)).toBe(false);
    expect(adventure.isExploring(adventure.departsAt)).toBe(true);
    expect(adventure.isExploring(adventure.departsAt + walk + 60)).toBe(true);
    expect(adventure.isExploring(adventure.returnsAt)).toBe(false);
    expect(adventure.isExploring(adventure.endsAt)).toBe(false);
  });
});

describe("PetJournal", () => {
  it("has about twenty distinct short lines", () => {
    const ids = JOURNAL_LINES.map((line) => line.id);
    expect(ids.length).toBe(20);
    expect(new Set(ids).size).toBe(ids.length);
    expect(new Set(JOURNAL_LINES.map((line) => line.phrase)).size).toBe(ids.length);
    expect(JOURNAL_LINES.every((line) => line.phrase.length <= 36)).toBe(true);
  });

  it("makes every line a whole sentence", () => {
    for (const line of JOURNAL_LINES) expect(journalSentence(line.id, "Mochi"), line.id).toBe(`Mochi ${line.phrase}`);
    expect(journalSentence("moon", "Mochi")).toBeUndefined();
  });

  it("reads an entry with the pet's name", () => {
    const journal = new PetJournal(7);
    const entry = journal.record(start);
    expect(entryText(entry, "Mochi")?.startsWith("Mochi ")).toBe(true);
    expect(entryText({ line: "moon", date: start }, "Mochi")).toBeUndefined();
    expect(journal.latest).toEqual(entry);
  });

  it("puts the surprise gift on the adventure it came home from", () => {
    const journal = new PetJournal(7);
    const first = journal.record(start);
    const second = journal.record(start + 3600);
    expect(second.gift).toBeUndefined();
    expect(entryDetail(second, "Mochi")).toBe(entryText(second, "Mochi"));
    const fur = { kind: "rareFur", id: "mint", name: "Mint" } as const;
    const carried = journal.attach(fur, second);
    if (!carried) throw new Error("no gift attached");
    expect(carried.gift).toEqual(fur);
    expect(journal.latest).toEqual(carried);
    expect(journal.entries[0]?.gift).toBeUndefined();
    const text = entryText(second, "Mochi");
    expect(entryDetail(carried, "Mochi")).toBe(`${text} and brought back the rare Mint fur`);
    expect(entryText(carried, "Mochi")).toBe(text);
    expect(journal.attach({ kind: "bonusPoints", points: 10 }, second), "one gift per adventure").toBeUndefined();
    expect(journal.attach({ kind: "bonusPoints", points: 10 }, { line: first.line, date: -1e12 })).toBeUndefined();
    expect(roundTrip(journal).toJSON()).toEqual(journal.toJSON());
  });

  it("drops an unknown gift and still loads the entry", () => {
    const journal = PetJournal.fromJSON({ entries: [{ line: "leaf", date: 0, gift: { kind: "rareFur", value: "plaid" } }] });
    expect(journal.entries[0]?.line).toBe("leaf");
    expect(journal.entries[0]?.gift).toBeUndefined();
    const plain = PetJournal.fromJSON({ entries: [{ line: "leaf", date: 0 }] });
    expect(plain.entries[0]?.gift).toBeUndefined();
  });

  it("repeats no line until every line was used", () => {
    const journal = new PetJournal(42);
    const count = JOURNAL_LINES.length;
    for (let deck = 0; deck < 4; deck++) {
      const lines = Array.from({ length: count }, (_, index) => journal.record(start + deck * count + index).line);
      expect(new Set(lines).size, `deck ${deck}`).toBe(count);
    }
  });

  it("reshuffles decks and never repeats across the seam", () => {
    const journal = new PetJournal(3);
    const count = JOURNAL_LINES.length;
    const all = Array.from({ length: count * 6 }, (_, index) => journal.record(start + index).line);
    for (let index = 1; index < all.length; index++) expect(all[index]).not.toBe(all[index - 1]);
    const decks = new Set(Array.from({ length: 6 }, (_, deck) => all.slice(deck * count, (deck + 1) * count).join(",")));
    expect(decks.size).toBeGreaterThan(1);
  });

  it("rotates deterministically for a seed", () => {
    const lines = (seed: number) => {
      const journal = new PetJournal(seed);
      return Array.from({ length: 30 }, (_, index) => journal.record(start + index).line);
    };
    expect(lines(11)).toEqual(lines(11));
    expect(lines(11)).not.toEqual(lines(12));
  });

  it("keeps the newest entries", () => {
    const journal = new PetJournal(1);
    for (let index = 0; index < PetJournal.maxEntries + 5; index++) journal.record(start + index);
    expect(journal.entries.length).toBe(PetJournal.maxEntries);
    expect(journal.entries[journal.entries.length - 1]?.date).toBe(start + PetJournal.maxEntries + 4);
  });

  it("round-trips and keeps its place in the deck", () => {
    const journal = new PetJournal(9);
    for (let index = 0; index < 5; index++) journal.record(start + index);
    const decoded = roundTrip(journal);
    expect(decoded.toJSON()).toEqual(journal.toJSON());
    expect(decoded.nextLine).toBe(journal.nextLine);
  });

  it("drops unknown and duplicate deck lines when decoding", () => {
    const journal = PetJournal.fromJSON({ seed: 5, deck: ["bookshelf", "moon", "bookshelf"], decksFinished: -2 });
    expect(journal.deck).toEqual(["bookshelf"]);
    expect(journal.decksFinished).toBe(0);
    expect(journal.nextLine).not.toBe("bookshelf");
  });

  it("writes a versioned file that round-trips, even with the largest seed", () => {
    const journal = new PetJournal((1n << 64n) - 1n);
    for (let index = 0; index < 3; index++) journal.record(start + index * 60);
    const json = journal.toJSON();
    expect(json.schemaVersion).toBe(PetJournal.schemaVersion);
    const decoded = roundTrip(journal);
    expect(decoded.toJSON()).toEqual(json);
    expect(decoded.seed).toBe(journal.seed);
    expect(() => PetJournal.fromJSON("not json")).toThrow();
  });

  it("saves a versioned file the Mac can read, the seed as an exact number", async () => {
    const store = new InMemoryDocumentStore();
    expect(await PetJournal.load(store, "journal.json")).toBeUndefined();
    const journal = new PetJournal((1n << 64n) - 1n);
    for (let index = 0; index < 3; index++) journal.record(start + index * 60);
    const first = journal.entries[0];
    if (first) journal.attach({ kind: "bonusPoints", points: 5 }, first);
    await journal.write(store, "journal.json");
    const text = store.snapshot()["journal.json"] ?? "";
    expect(text).toContain('"seed" : 18446744073709551615');
    expect(text).toContain('"schemaVersion" : 1');
    const loaded = await PetJournal.load(store, "journal.json");
    expect(loaded?.seed).toBe(journal.seed);
    expect(loaded?.toJSON()).toEqual(journal.toJSON());
    await store.write("bad.json", "[]");
    await expect(PetJournal.load(store, "bad.json")).rejects.toThrow();
  });

  it("makes a recent, varied demo journal", () => {
    const journal = PetJournal.demo(start);
    expect(new Set(journal.entries.map((entry) => entry.line)).size).toBe(journal.entries.length);
    expect(journal.latest?.date).toBe(start - 3600);
    expect(PetJournal.demo(start).toJSON()).toEqual(journal.toJSON());
  });
});

describe("finishing an adventure", () => {
  const running = (minutes: number, done = 0): ProvidedFocus => new ProvidedFocus({
    source: "focus",
    phase: "focus",
    clock: { kind: "countdown", endsAt: start + minutes * 60 },
    phaseLength: minutes * 60,
    completedFocusCount: done,
  });
  const onBreak = (done: number, source = "focus"): ProvidedFocus => new ProvidedFocus({
    source,
    phase: "rest",
    clock: { kind: "countdown", endsAt: start + 30 * 60 },
    phaseLength: 5 * 60,
    completedFocusCount: done,
  });

  it("brings the pet back when a block runs out", () => {
    const end = start + 25 * 60;
    const adventure = PetAdventure.finished(running(25), onBreak(1), end, false);
    expect(adventure).toEqual(PetAdventure.plan(running(25), false));
    expect(adventure?.endsAt).toBe(end);
    expect(PetAdventure.finished(running(25), onBreak(1), end + 3600, false)).toBeDefined();
  });

  it("counts only a finished long block with the walk home", () => {
    const end = start + 25 * 60;
    const idle = new ProvidedFocus({ source: "focus", phase: "focus", clock: { kind: "idle" }, phaseLength: 25 * 60, completedFocusCount: 0 });
    expect(PetAdventure.finished(running(25), idle, start + 600, false), "stopped early").toBeUndefined();
    expect(PetAdventure.finished(running(25), onBreak(1), start + 600, false), "skipped").toBeUndefined();
    expect(PetAdventure.finished(running(10), onBreak(1), start + 600, false), "too short").toBeUndefined();
    expect(PetAdventure.finished(running(25), onBreak(1), end, true), "Reduce Motion").toBeUndefined();
    expect(PetAdventure.finished(running(25), onBreak(1, "study"), end, false), "another clock").toBeUndefined();
    expect(PetAdventure.finished(running(25), undefined, end, false), "clock gone").toBeUndefined();
    expect(PetAdventure.finished(running(25, 1), running(25, 1), end, false), "nothing finished").toBeUndefined();
  });
});
